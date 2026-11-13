/**
 * MKES CARE+ — Notification Watcher Service
 * 
 * Monitors in-app notification events in Supabase and bridges them to
 * push notification dispatches for active staff and admin device tokens.
 * Enforces department routing, lock-screen privacy, duplicate prevention,
 * and clinical scope (Optical strictly excluded).
 */

const { supabase } = require('../config/supabase');
const { pushNotificationBackend } = require('./push_notification_backend');
const logger = require('../utils/logger');

class NotificationWatcher {
  constructor() {
    this.isRunning = false;
    this.timer = null;
    this.pollIntervalMs = 4000; // Check every 4 seconds
    this.processedIds = new Set();
    this.maxTrackedIds = 5000;
  }

  start() {
    if (this.isRunning) return;
    this.isRunning = true;
    logger.info('NotificationWatcher started. Monitoring unified notifications for FCM push delivery.');
    this._pollLoop();
  }

  stop() {
    this.isRunning = false;
    if (this.timer) clearTimeout(this.timer);
    logger.info('NotificationWatcher stopped.');
  }

  async _pollLoop() {
    if (!this.isRunning) return;

    try {
      await this.processPendingNotifications();
    } catch (err) {
      logger.error(`Error in notification watcher cycle: ${err.message}`, err);
    } finally {
      if (this.isRunning) {
        this.timer = setTimeout(() => this._pollLoop(), this.pollIntervalMs);
      }
    }
  }

  async processPendingNotifications() {
    if (!supabase) return;

    // Fetch recent notifications created within the last 5 minutes
    const windowStart = new Date(Date.now() - 5 * 60 * 1000).toISOString();

    const { data: notifications, error } = await supabase
      .from('notifications')
      .select('id, user_id, title, message, type, related_id, created_at')
      .gte('created_at', windowStart)
      .order('created_at', { ascending: true })
      .limit(50);

    if (error || !notifications || notifications.length === 0) {
      return;
    }

    for (const notif of notifications) {
      if (this.processedIds.has(notif.id)) {
        continue;
      }

      this.processedIds.add(notif.id);
      if (this.processedIds.size > this.maxTrackedIds) {
        const first = this.processedIds.values().next().value;
        this.processedIds.delete(first);
      }

      // 1. Enforce Optical Exclusion: Drop any notification referencing optical
      const textForAudit = `${notif.title || ''} ${notif.message || ''} ${notif.type || ''}`.toLowerCase();
      if (textForAudit.includes('optical')) {
        logger.debug(`[NotificationWatcher] Skipping notification ${notif.id}: Optical workflow excluded.`);
        continue;
      }

      // 2. Dispatch push notification to recipient staff device tokens
      const idempotencyKey = `push_watcher_${notif.id}`;
      try {
        await pushNotificationBackend.dispatchToUsers({
          userIds: [notif.user_id],
          type: notif.type,
          title: notif.title,
          body: notif.message,
          relatedId: notif.related_id,
          idempotencyKey,
        });
      } catch (dispatchErr) {
        logger.warn(`[NotificationWatcher] Failed push dispatch for notif ${notif.id}: ${dispatchErr.message}`);
      }
    }
  }
}

module.exports = new NotificationWatcher();
