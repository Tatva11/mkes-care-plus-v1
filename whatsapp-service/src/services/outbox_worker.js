const { supabase } = require('../config/supabase');
const whatsappClient = require('./whatsapp_client');
const invoicePdfService = require('./invoice_pdf_service');
const PhoneNormalizer = require('../utils/phone_normalizer');
const logger = require('../utils/logger');
const crypto = require('crypto');

class OutboxWorker {
  constructor() {
    this.workerId = crypto.randomUUID();
    this.isRunning = false;
    this.pollIntervalMs = parseInt(process.env.OUTBOX_POLL_INTERVAL_MS, 10) || 5000;
    this.minDelayMs = parseInt(process.env.MIN_SEND_DELAY_MS, 10) || 6000;
    this.maxDelayMs = parseInt(process.env.MAX_SEND_DELAY_MS, 10) || 14000;
    this.timer = null;
  }

  start() {
    if (this.isRunning) return;
    this.isRunning = true;
    logger.info(`OutboxWorker started. Worker ID: ${this.workerId}, poll interval: ${this.pollIntervalMs}ms`);
    this._pollLoop();
  }

  stop() {
    this.isRunning = false;
    if (this.timer) clearTimeout(this.timer);
    logger.info('OutboxWorker stopped.');
  }

  async _pollLoop() {
    if (!this.isRunning) return;

    try {
      const isDryRun = String(process.env.DRY_RUN || 'true').trim().toLowerCase() !== 'false';
      if (whatsappClient.isReady || isDryRun) {
        await this._processBatch();
      } else {
        logger.debug('WhatsApp client not ready yet. Skipping outbox cycle.');
      }
    } catch (err) {
      logger.error(`Error in outbox poll cycle: ${err.message}`, err);
    } finally {
      if (this.isRunning) {
        this.timer = setTimeout(() => this._pollLoop(), this.pollIntervalMs);
      }
    }
  }

  async _processBatch() {
    // 1. Claim batch using atomic RPC
    const { data: messages, error } = await supabase.rpc('claim_whatsapp_outbox_batch', {
      p_worker_id: this.workerId,
      p_batch_size: 3,
      p_lease_duration_seconds: 60,
    });

    if (error) {
      if (error.code === 'PGRST202' || error.message?.includes('does not exist') || error.code === '42883') {
        logger.warn(`Outbox claim skipped: Database migration 'claim_whatsapp_outbox_batch' not yet applied to database.`);
      } else {
        logger.error(`Failed to claim outbox batch: ${error.message}`);
      }
      return;
    }

    if (!messages || messages.length === 0) {
      return;
    }

    logger.info(`Claimed ${messages.length} message(s) from outbox.`);

    for (const msg of messages) {
      await this._dispatchSingleMessage(msg);

      // Pacing delay between messages to emulate human rhythm
      const delayMs = Math.floor(Math.random() * (this.maxDelayMs - this.minDelayMs + 1)) + this.minDelayMs;
      logger.debug(`Applying pacing delay: ${delayMs}ms before next message.`);
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }

  async _dispatchSingleMessage(outboxRecord) {
    const { id, recipient_phone, message_text, patient_id, retry_count, max_retries } = outboxRecord;

    const jid = PhoneNormalizer.toWhatsAppJid(recipient_phone);
    if (!jid) {
      logger.warn(`Invalid recipient phone: "${recipient_phone}". Marking outbox record ${id} as failed.`);
      await this._markFailed(id, 'Invalid phone number format. Could not normalize to WhatsApp JID.');
      return;
    }

    // Pre-flight check: Verify message was not cancelled while waiting in worker memory
    const { data: currentStatus } = await supabase
      .from('whatsapp_messages_outbox')
      .select('status')
      .eq('id', id)
      .maybeSingle();

    if (currentStatus && currentStatus.status === 'cancelled') {
      logger.info(`Outbox message ${id} was cancelled in database (e.g. via STOP command). Skipping dispatch.`);
      return;
    }

    // Pre-flight check: Re-verify patient opt-out flag by phone digits
    const tenDigits = PhoneNormalizer.extractTenDigits(recipient_phone);
    if (tenDigits) {
      const { data: optedOut } = await supabase
        .from('patients')
        .select('id')
        .ilike('mobile', `%${tenDigits}`)
        .eq('whatsapp_opt_out', true)
        .limit(1);

      if (optedOut && optedOut.length > 0) {
        logger.info(`Patient with phone ${recipient_phone} opted out prior to dispatch. Cancelling message ${id}.`);
        await supabase
          .from('whatsapp_messages_outbox')
          .update({
            status: 'cancelled',
            last_error: 'Patient opted out prior to delivery.',
            lease_id: null,
            lease_expires_at: null,
            updated_at: new Date().toISOString(),
          })
          .eq('id', id);
        return;
      }
    }

    // Pre-flight check 3: Duplicate send prevention for reclaimed crash leases
    if (outboxRecord.retry_count > 0) {
      const { data: existingLog } = await supabase
        .from('whatsapp_message_logs')
        .select('id, timestamp')
        .eq('outbox_id', id)
        .eq('direction', 'outbound')
        .maybeSingle();

      if (existingLog) {
        logger.warn(`Outbox ${id} was already delivered and logged at ${existingLog.timestamp}. Reconciling status to sent without resending.`);
        await supabase
          .from('whatsapp_messages_outbox')
          .update({
            status: 'sent',
            sent_at: existingLog.timestamp,
            lease_id: null,
            lease_expires_at: null,
            updated_at: new Date().toISOString(),
          })
          .eq('id', id);
        return;
      }
    }

    // Pre-flight check 4: Test phone whitelist enforcement (if configured)
    const whitelistStr = process.env.TEST_PHONE_WHITELIST;
    if (whitelistStr) {
      const allowedNumbers = whitelistStr.split(',').map((n) => PhoneNormalizer.extractTenDigits(n.trim()));
      if (!allowedNumbers.includes(tenDigits)) {
        logger.info(`[TEST MODE] Recipient ${recipient_phone} (${tenDigits}) not in TEST_PHONE_WHITELIST. Leaving pending for production.`);
        await supabase
          .from('whatsapp_messages_outbox')
          .update({
            status: 'pending',
            scheduled_for: new Date(Date.now() + 300000).toISOString(),
            lease_id: null,
            lease_expires_at: null,
            last_error: '[TEST MODE] Held: outside TEST_PHONE_WHITELIST',
            updated_at: new Date().toISOString(),
          })
          .eq('id', id);
        return;
      }
    }

    // Pre-flight check 5: DRY_RUN simulation (DEFAULT: active unless explicitly 'false')
    const isDryRun = String(process.env.DRY_RUN || 'true').trim().toLowerCase() !== 'false';
    if (isDryRun) {
      logger.info(`[DRY RUN] Verified outbox ${id} -> Would dispatch to ${jid} (${outboxRecord.message_type}). Body preview: "${message_text.replace(/\n/g, ' ').substring(0, 80)}..."`);
      await supabase
        .from('whatsapp_messages_outbox')
        .update({
          status: 'pending',
          scheduled_for: new Date(Date.now() + 300000).toISOString(),
          lease_id: null,
          lease_expires_at: null,
          last_error: '[DRY RUN] Simulated send successful - safely preserved for live delivery',
          updated_at: new Date().toISOString(),
        })
        .eq('id', id);
      return;
    }

    try {
      logger.info(`Dispatching outbox ${id} to ${jid} (type: ${outboxRecord.message_type})`);
      let result;

      // Handle Invoice PDF Delivery (Requirement 6)
      if (outboxRecord.message_type === 'payment_receipt' || (outboxRecord.media_url && outboxRecord.media_url.startsWith('invoice://'))) {
        try {
          const invRef = outboxRecord.media_url?.replace('invoice://', '') || outboxRecord.template_key?.replace('invoice_', '');
          const { media } = await invoicePdfService.generateInvoicePdf(invRef, outboxRecord);
          result = await whatsappClient.sendMediaWithHumanizedDelay(jid, media, message_text);
        } catch (pdfErr) {
          logger.error(`PDF generation failed for outbox ${id}: ${pdfErr.message}. Falling back to text receipt.`);
          result = await whatsappClient.sendMessageWithHumanizedDelay(jid, message_text);
        }
      } else {
        result = await whatsappClient.sendMessageWithHumanizedDelay(jid, message_text);
      }

      // Mark Sent in Outbox
      await supabase
        .from('whatsapp_messages_outbox')
        .update({
          status: 'sent',
          sent_at: new Date().toISOString(),
          lease_id: null,
          lease_expires_at: null,
          updated_at: new Date().toISOString(),
        })
        .eq('id', id);

      // Insert into Audit Log
      await supabase.from('whatsapp_message_logs').insert({
        outbox_id: id,
        direction: 'outbound',
        phone_number: recipient_phone,
        patient_id: patient_id || null,
        message_body: message_text,
        raw_payload: { messageId: result?.id?._serialized || null },
      });

      logger.info(`Outbox message ${id} sent successfully.`);
    } catch (sendErr) {
      logger.error(`Failed to send outbox ${id}: ${sendErr.message}`);
      const newRetryCount = (retry_count || 0) + 1;
      if (newRetryCount >= (max_retries || 3)) {
        await this._markFailed(id, `Exceeded max retries: ${sendErr.message}`);
      } else {
        // Reschedule for retry with exponential backoff (e.g. 2 min, 5 min)
        const backoffSeconds = newRetryCount * 120;
        const nextScheduled = new Date(Date.now() + backoffSeconds * 1000).toISOString();
        await supabase
          .from('whatsapp_messages_outbox')
          .update({
            status: 'pending',
            retry_count: newRetryCount,
            last_error: sendErr.message,
            scheduled_for: nextScheduled,
            lease_id: null,
            lease_expires_at: null,
            updated_at: new Date().toISOString(),
          })
          .eq('id', id);
        logger.info(`Rescheduled outbox ${id} for retry #${newRetryCount} at ${nextScheduled}`);
      }
    }
  }

  async _markFailed(id, reason) {
    await supabase
      .from('whatsapp_messages_outbox')
      .update({
        status: 'failed',
        last_error: reason,
        lease_id: null,
        lease_expires_at: null,
        updated_at: new Date().toISOString(),
      })
      .eq('id', id);
  }
}

module.exports = new OutboxWorker();
