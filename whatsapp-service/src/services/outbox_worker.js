const { supabase, hasServiceRole } = require('../config/supabase');
const whatsappClient = require('./whatsapp_client');
const invoicePdfService = require('./invoice_pdf_service');
const PhoneNormalizer = require('../utils/phone_normalizer');
const RecipientValidator = require('../utils/recipient_validator');
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
      if (!hasServiceRole) {
        logger.warn('[CONFIG REQUIRED] Outbox poller paused: SUPABASE_SERVICE_ROLE_KEY is required for background worker operations.');
        return;
      }
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

    // Pre-flight check 4: DRY_RUN Controlled Dispatch Switch
    // When DRY_RUN=true, simulate sending and preserve outbox record in pending state.
    // When DRY_RUN=false, allow actual sending to all eligible registered patient numbers.
    const isDryRun = String(process.env.DRY_RUN || 'true').trim().toLowerCase() !== 'false';
    if (isDryRun) {
      logger.info(`[DRY RUN SIMULATION] Outbox ${id} to ${recipient_phone} (${tenDigits}) safely simulated (DRY_RUN=true).`);
      await supabase
        .from('whatsapp_messages_outbox')
        .update({
          status: 'pending',
          scheduled_for: new Date(Date.now() + 300000).toISOString(),
          lease_id: null,
          lease_expires_at: null,
          last_error: '[DRY RUN] Simulated dispatch - safely preserved for live delivery when DRY_RUN=false',
          updated_at: new Date().toISOString(),
        })
        .eq('id', id);
      return;
    }

    try {
      logger.info(`Dispatching outbox ${id} to ${jid} (type: ${outboxRecord.message_type})`);
      let result;

      // Handle Invoice PDF Delivery (Requirement 6)
      const isInvoice = outboxRecord.message_type === 'payment_receipt' ||
        (outboxRecord.media_url && outboxRecord.media_url.startsWith('invoice://')) ||
        (outboxRecord.message_text && outboxRecord.message_text.includes('MKES CARE+ Invoice #')) ||
        (outboxRecord.template_key && outboxRecord.template_key.startsWith('invoice_'));

      if (isInvoice) {
        try {
          let invRef = (outboxRecord.media_url && outboxRecord.media_url.startsWith('invoice://'))
            ? outboxRecord.media_url.replace('invoice://', '')
            : (outboxRecord.template_key && outboxRecord.template_key !== 'custom' ? outboxRecord.template_key.replace('invoice_', '') : null);

          if (!invRef && outboxRecord.message_text) {
            const match = outboxRecord.message_text.match(/MKES CARE\+ Invoice #([^\*\n\s]+)/);
            if (match && match[1]) {
              invRef = match[1];
            }
          }

          const { media } = await invoicePdfService.generateInvoicePdf(invRef, outboxRecord);
          result = await whatsappClient.sendMediaWithHumanizedDelay(jid, media, message_text);
        } catch (pdfErr) {
          logger.error(`PDF generation failed for outbox ${id}: ${pdfErr.message}. Falling back to text receipt.`);
          result = await whatsappClient.sendMessageWithHumanizedDelay(jid, message_text);
        }
      } else {
        result = await whatsappClient.sendMessageWithHumanizedDelay(jid, message_text);
      }

      // Check if dispatch was simulated (do not mark sent prematurely)
      if (result && result.simulated) {
        logger.info(`[SIMULATION] Dispatch returned simulated result for outbox ${id}. Preserving pending state.`);
        await supabase
          .from('whatsapp_messages_outbox')
          .update({
            status: 'pending',
            scheduled_for: new Date(Date.now() + 300000).toISOString(),
            lease_id: null,
            lease_expires_at: null,
            last_error: '[DRY RUN] Simulated dispatch',
            updated_at: new Date().toISOString(),
          })
          .eq('id', id);
        return;
      }

      const messageId = RecipientValidator.extractMessageId(result);

      // Mark Sent in Outbox only upon verified WhatsApp dispatch
      await supabase
        .from('whatsapp_messages_outbox')
        .update({
          status: 'sent',
          sent_at: new Date().toISOString(),
          whatsapp_message_id: messageId || null,
          last_error: null,
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
        raw_payload: {
          id: messageId,
          messageId: messageId,
          status: 'sent',
          ack: 1,
          timestamp: Math.floor(Date.now() / 1000),
        },
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

  /**
   * Reconciles message delivery receipt (ACK) from WhatsApp server.
   * Maps ACK values: 1 = sent, 2 = delivered, 3 = read, -1 = error
   */
  async handleMessageAck(msg, ack, messageId) {
    if (!messageId && !msg) return;
    const msgId = messageId || RecipientValidator.extractMessageId(msg);
    if (!msgId) return;

    let statusStr = 'sent';
    if (ack >= 3) {
      statusStr = 'read';
    } else if (ack === 2) {
      statusStr = 'delivered';
    } else if (ack === -1) {
      statusStr = 'failed';
    } else if (ack === 1) {
      statusStr = 'sent';
    } else {
      return;
    }

    try {
      const { data: logs } = await supabase
        .from('whatsapp_message_logs')
        .select('id, raw_payload, outbox_id')
        .or(`raw_payload->>messageId.eq.${msgId},raw_payload->>id.eq.${msgId}`)
        .limit(1);

      if (logs && logs.length > 0) {
        const logRow = logs[0];
        const updatedPayload = {
          ...(logRow.raw_payload || {}),
          ack,
          status: statusStr,
          ack_updated_at: new Date().toISOString(),
        };

        await supabase
          .from('whatsapp_message_logs')
          .update({ raw_payload: updatedPayload })
          .eq('id', logRow.id);

        if (logRow.outbox_id) {
          const updateFields = { updated_at: new Date().toISOString() };
          if (statusStr === 'delivered') {
            updateFields.status = 'delivered';
            updateFields.delivered_at = new Date().toISOString();
          } else if (statusStr === 'read') {
            updateFields.status = 'read';
            updateFields.read_at = new Date().toISOString();
          } else if (statusStr === 'failed') {
            updateFields.status = 'failed';
            updateFields.last_error = 'WhatsApp server reported ACK_ERROR (-1)';
          }
          await supabase
            .from('whatsapp_messages_outbox')
            .update(updateFields)
            .eq('id', logRow.outbox_id);
        }
        logger.debug(`Reconciled ACK ${ack} (${statusStr}) for message ${msgId}`);
      }
    } catch (err) {
      logger.error(`Error handling message_ack for ${msgId}: ${err.message}`);
    }
  }
}

module.exports = new OutboxWorker();
