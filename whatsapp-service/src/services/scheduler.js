/**
 * MKES CARE+ WhatsApp Automation Scheduler
 * Runs batch enqueue procedures on scheduled intervals in Indian Standard Time (IST, UTC+5:30).
 * Provides automatic host-level triggering as a resilient companion to database pg_cron.
 */

const { supabase } = require('../config/supabase');
const logger = require('../utils/logger');

class AutomationScheduler {
  constructor() {
    this.timer = null;
    this.isRunning = false;
    this.checkIntervalMs = 60000; // Check every 60 seconds
    this.lastRuns = {
      appointmentReminders: null,
      googleReviews: null,
      birthdays: null,
      annualEye: null,
      dentalFollowups: null,
      eyeFollowups: null,
      eyeLab: null,
      paymentReminders: null,
    };
  }

  start() {
    if (this.isRunning) return;
    const mode = (process.env.SCHEDULER_MODE || 'disabled').toLowerCase();
    // Safety Requirement: Keep unattended schedulers and background workers disabled unless explicitly approved
    if (mode !== 'active' && mode !== 'enabled') {
      logger.info(`AutomationScheduler: host-level background scheduler is DISABLED by default safety policy (SCHEDULER_MODE='${mode}').`);
      return;
    }

    this.isRunning = true;
    logger.info(`AutomationScheduler started (SCHEDULER_MODE='${mode}'). Monitoring IST schedules for approved in-scope batch enqueue jobs.`);
    this._scheduleTick();
  }

  stop() {
    this.isRunning = false;
    if (this.timer) clearTimeout(this.timer);
    logger.info('AutomationScheduler stopped.');
  }

  getISTDate() {
    // Current time in IST (UTC + 5:30)
    const now = new Date();
    const utc = now.getTime() + now.getTimezoneOffset() * 60000;
    return new Date(utc + 3600000 * 5.5);
  }

  async _scheduleTick() {
    if (!this.isRunning) return;

    try {
      await this.runPendingSchedules();
    } catch (err) {
      logger.error(`Error in scheduler tick: ${err.message}`, err);
    } finally {
      if (this.isRunning) {
        this.timer = setTimeout(() => this._scheduleTick(), this.checkIntervalMs);
      }
    }
  }

  async runPendingSchedules() {
    const ist = this.getISTDate();
    const hours = ist.getHours();
    const minutes = ist.getMinutes();
    const todayStr = ist.toISOString().split('T')[0];

    // 1. Appointment Reminders (Every 15 min between 08:00 and 20:00 IST) - In Scope
    if (hours >= 8 && hours <= 20) {
      const fifteenMinBlock = `${todayStr}-${hours}-${Math.floor(minutes / 15)}`;
      if (this.lastRuns.appointmentReminders !== fifteenMinBlock) {
        this.lastRuns.appointmentReminders = fifteenMinBlock;
        await this._executeBatchRpc('enqueue_appointment_reminders_batch', 'Appointment Reminders (24h/2h)');
      }
    }

    // 2. Daily Birthday Greetings (At 09:00 AM IST) - In Scope
    if (hours === 9 && minutes >= 0 && minutes < 10) {
      if (this.lastRuns.birthdays !== todayStr) {
        this.lastRuns.birthdays = todayStr;
        await this._executeBatchRpc('enqueue_birthday_greetings_batch', 'Patient Birthday Greetings');
      }
    }

    // 3. Annual Eye Checkup Reminders (At 09:15 AM IST) - In Scope
    if (hours === 9 && minutes >= 15 && minutes < 25) {
      if (this.lastRuns.annualEye !== todayStr) {
        this.lastRuns.annualEye = todayStr;
        await this._executeBatchRpc('enqueue_annual_eye_reminders_batch', 'Annual Eye Checkup Reminders');
      }
    }

    // 4. Dental Follow-Ups (Cleaning, RCT, Implant) (At 09:30 AM IST) - In Scope
    if (hours === 9 && minutes >= 30 && minutes < 40) {
      if (this.lastRuns.dentalFollowups !== todayStr) {
        this.lastRuns.dentalFollowups = todayStr;
        await this._executeBatchRpc('enqueue_dental_followups_batch', 'Dental Follow-Ups (Cleaning, RCT, Implant)');
      }
    }

    // 5. Eye Surgery Post-Operative Follow-Ups (At 09:45 AM IST) - In Scope
    if (hours === 9 && minutes >= 45 && minutes < 55) {
      if (this.lastRuns.eyeFollowups !== todayStr) {
        this.lastRuns.eyeFollowups = todayStr;
        await this._executeBatchRpc('enqueue_eye_surgery_followups_batch', 'Eye Surgery Post-Op Follow-Ups');
      }
    }

    // 6. Eye Lab (IOL Lens Ready) Notifications (Hourly between 09:00 and 19:00 IST) - In Scope
    if (hours >= 9 && hours <= 19) {
      const hourlyBlock = `${todayStr}-${hours}`;
      if (this.lastRuns.eyeLab !== hourlyBlock) {
        this.lastRuns.eyeLab = hourlyBlock;
        await this._executeBatchRpc('enqueue_eye_lab_notifications_batch', 'Eye Lab (IOL Lens Ready) Notifications');
      }
    }

    // 7. Billing Payment Reminders (At 10:00 AM IST)
    if (hours === 10 && minutes >= 0 && minutes < 10) {
      if (this.lastRuns.paymentReminders !== todayStr) {
        this.lastRuns.paymentReminders = todayStr;
        await this._executeBatchRpc('enqueue_billing_payment_reminders_batch', 'Billing Payment Reminders');
      }
    }

    // NOTE: Per clinical requirement, Google Review requests, festival greetings, and optical workflows are excluded from active scope.
  }

  async _executeBatchRpc(rpcName, jobLabel) {
    try {
      logger.info(`Scheduler executing: ${jobLabel} via RPC ${rpcName}...`);
      const { data, error } = await supabase.rpc(rpcName);
      if (error) {
        if (error.code === 'PGRST202' || error.message?.includes('does not exist') || error.code === '42883') {
          logger.warn(`Scheduler skipped ${jobLabel}: Database RPC '${rpcName}' not yet applied to database.`);
        } else {
          logger.error(`Scheduler RPC error for ${jobLabel}: ${error.message}`);
        }
      } else {
        logger.info(`Scheduler ${jobLabel} completed. Enqueued count: ${data || 0}`);
      }
    } catch (err) {
      logger.error(`Exception executing scheduler RPC for ${jobLabel}: ${err.message}`, err);
    }
  }

  async triggerFestivalBroadcast(festivalName, customGreeting = null) {
    try {
      logger.info(`Triggering festival broadcast: "${festivalName}" via RPC enqueue_festival_greeting_broadcast...`);
      const { data, error } = await supabase.rpc('enqueue_festival_greeting_broadcast', {
        p_festival_name: festivalName,
        p_custom_greeting: customGreeting,
      });
      if (error) {
        if (error.code === 'PGRST202' || error.message?.includes('does not exist') || error.code === '42883') {
          logger.warn(`Festival broadcast skipped: RPC enqueue_festival_greeting_broadcast not yet applied to database.`);
          return { success: false, enqueued: 0, reason: 'unapplied_migration' };
        }
        logger.error(`Failed to enqueue festival broadcast: ${error.message}`);
        return { success: false, error: error.message };
      }
      logger.info(`Festival broadcast for "${festivalName}" enqueued successfully. Count: ${data || 0}`);
      return { success: true, enqueued: data || 0 };
    } catch (err) {
      logger.error(`Exception during festival broadcast: ${err.message}`, err);
      return { success: false, error: err.message };
    }
  }
}

module.exports = new AutomationScheduler();

