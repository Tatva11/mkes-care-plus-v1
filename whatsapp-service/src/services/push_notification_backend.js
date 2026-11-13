/**
 * MKES CARE+ — Push Notification Backend Service
 * 
 * Provides trusted server-side dispatch for Firebase Cloud Messaging (FCM),
 * device token lifecycle management, invalid-token cleanup, role-based targeting,
 * and lock-screen privacy enforcement.
 */

const firebaseConfig = require('../config/firebase');

class PushNotificationBackend {
  /**
   * @param {Object} options
   * @param {Object} [options.supabase] - Supabase client instance
   * @param {Object} [options.firebaseAdmin] - Initialized firebase-admin messaging instance
   * @param {Function} [options.logger] - Logger function
   */
  constructor({ supabase = null, firebaseAdmin = null, logger = console.log } = {}) {
    this.supabase = supabase;
    this.firebaseAdmin = firebaseAdmin || firebaseConfig.firebaseAdmin;
    this.logger = logger;
    this.recentDispatches = new Set();
  }

  /**
   * Check whether Firebase credentials are configured on the server.
   * @returns {boolean}
   */
  isFirebaseConfigured() {
    if (this.firebaseAdmin) return true;
    return !!(
      process.env.FIREBASE_SERVICE_ACCOUNT_KEY ||
      process.env.GOOGLE_APPLICATION_CREDENTIALS ||
      firebaseConfig.isConfigured
    );
  }

  /**
   * Fetches active device tokens for a given user.
   * @param {string} userId
   * @returns {Promise<Array<{token: string, deviceType: string}>>}
   */
  async getActiveTokensForUser(userId) {
    if (!this.supabase || !userId) return [];
    try {
      const { data, error } = await this.supabase
        .from('user_device_tokens')
        .select('device_token, device_type')
        .eq('user_id', userId)
        .eq('is_active', true);

      if (error || !data) return [];
      return data.map((row) => ({
        token: row.device_token,
        deviceType: row.device_type || 'android',
      }));
    } catch (e) {
      this.logger(`[PushBackend] Error fetching tokens for user ${userId}: ${e.message}`);
      return [];
    }
  }

  /**
   * Fetches active device tokens for all users belonging to a specific role and optional department.
   * @param {string} role - 'admin' | 'staff'
   * @param {string} [department] - 'eye' | 'dental'
   * @returns {Promise<Array<{userId: string, token: string}>>}
   */
  async getActiveTokensForRole(role, department = null) {
    if (!this.supabase || !role) return [];
    try {
      let query = this.supabase
        .from('profiles')
        .select('id, role, department')
        .eq('role', role);

      if (department) {
        query = query.ilike('department', `%${department}%`);
      }

      const { data: profiles, error: pErr } = await query;
      if (pErr || !profiles || profiles.length === 0) return [];

      const userIds = profiles.map((p) => p.id);
      const { data: tokens, error: tErr } = await this.supabase
        .from('user_device_tokens')
        .select('user_id, device_token')
        .in('user_id', userIds)
        .eq('is_active', true);

      if (tErr || !tokens) return [];
      return tokens.map((t) => ({
        userId: t.user_id,
        token: t.device_token,
      }));
    } catch (e) {
      this.logger(`[PushBackend] Error fetching tokens for role ${role}: ${e.message}`);
      return [];
    }
  }

  /**
   * Deactivates an invalid or expired device token in the database.
   * @param {string} deviceToken
   * @returns {Promise<boolean>}
   */
  async deactivateInvalidToken(deviceToken) {
    if (!this.supabase || !deviceToken) return false;
    try {
      const { error } = await this.supabase
        .from('user_device_tokens')
        .update({
          is_active: false,
          updated_at: new Date().toISOString(),
        })
        .eq('device_token', deviceToken);

      if (!error) {
        this.logger(`[PushBackend] Deactivated invalid token: ${deviceToken.substring(0, 12)}...`);
        return true;
      }
      return false;
    } catch (e) {
      this.logger(`[PushBackend] Error deactivating token: ${e.message}`);
      return false;
    }
  }

  /**
   * Formats a privacy-preserving push payload to protect sensitive patient data on lock screens.
   * @param {Object} notification
   * @returns {{title: string, body: string, data: Object}}
   */
  formatPayload({ type, title, body, patientName, relatedId, department }) {
    let safeTitle = title || 'MKES CARE+ Alert';
    let safeBody = body || 'You have a new clinic update.';
    const isEye = (department && department.toLowerCase() === 'eye') || type === 'eye_lab_ready';

    switch (type) {
      case 'appointment_rescheduled':
        safeTitle = 'Appointment Update';
        safeBody = patientName
          ? `${patientName} rescheduled their consultation.`
          : 'A patient rescheduled their appointment.';
        break;
      case 'whatsapp_reply':
        safeTitle = 'New Patient Message';
        safeBody = patientName
          ? `Message received from ${patientName}.`
          : 'New incoming WhatsApp message.';
        break;
      case 'lab_ready':
      case 'eye_lab_ready':
      case 'dental_lab_ready':
        safeTitle = isEye ? 'Eye Lab Alert' : 'Dental Lab Alert';
        safeBody = patientName
          ? (isEye ? `Appliance / lens ready (${patientName}).` : `Restoration ready for fitting (${patientName}).`)
          : (isEye ? 'Eye lab order / lens ready for patient.' : 'Lab restoration case ready for delivery.');
        break;
      case 'eye_surgery_assigned':
        safeTitle = 'Surgery Schedule';
        safeBody = 'You have an eye surgery assignment update.';
        break;
      case 'inventory_low_stock':
        safeTitle = 'Inventory Notice';
        safeBody = body || 'Item stock level reached reorder point.';
        break;
    }

    return {
      title: safeTitle,
      body: safeBody,
      data: {
        type: type || 'general',
        department: department || (isEye ? 'eye' : 'dental'),
        related_id: relatedId ? String(relatedId) : '',
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
        timestamp: new Date().toISOString(),
      },
    };
  }

  /**
   * Dispatches a push notification to one or more user IDs.
   * @param {Object} params
   * @param {Array<string>} params.userIds
   * @param {string} params.type
   * @param {string} [params.title]
   * @param {string} [params.body]
   * @param {string} [params.patientName]
   * @param {string} [params.relatedId]
   * @param {string} [params.idempotencyKey]
   * @returns {Promise<{dispatchedCount: number, skippedCount: number, errors: Array}>}
   */
  async dispatchToUsers({
    userIds = [],
    type,
    title,
    body,
    patientName,
    relatedId,
    idempotencyKey,
  }) {
    // 1. Prevent duplicate notifications
    if (idempotencyKey) {
      if (this.recentDispatches.has(idempotencyKey)) {
        this.logger(`[PushBackend] Skipping duplicate dispatch: idempotencyKey=${idempotencyKey}`);
        return { dispatchedCount: 0, skippedCount: userIds.length, errors: [], duplicate: true };
      }
      this.recentDispatches.add(idempotencyKey);
      // Bound the memory set to 1000 items
      if (this.recentDispatches.size > 1000) {
        const first = this.recentDispatches.values().next().value;
        this.recentDispatches.delete(first);
      }
    }

    const payload = this.formatPayload({ type, title, body, patientName, relatedId });
    const errors = [];
    let dispatchedCount = 0;
    let skippedCount = 0;

    for (const userId of userIds) {
      const tokens = await this.getActiveTokensForUser(userId);
      if (tokens.length === 0) {
        skippedCount++;
        continue;
      }

      for (const { token } of tokens) {
        if (!this.isFirebaseConfigured()) {
          // Trusted dry-run logging when external Firebase credentials are not yet supplied
          this.logger(
            `[PushBackend][DRY_RUN] Dispatched to token ${token.substring(0, 10)}... | Title: "${payload.title}" | Body: "${payload.body}"`
          );
          dispatchedCount++;
          continue;
        }

        try {
          if (this.firebaseAdmin && this.firebaseAdmin.messaging) {
            await this.firebaseAdmin.messaging().send({
              token,
              notification: {
                title: payload.title,
                body: payload.body,
              },
              data: payload.data,
              android: {
                priority: 'high',
                notification: {
                  channelId: 'mkes_care_high_importance',
                  visibility: 'private', // Lock screen privacy
                },
              },
            });
            dispatchedCount++;
          }
        } catch (fcmErr) {
          this.logger(`[PushBackend] FCM dispatch failed for token: ${fcmErr.message}`);
          errors.push({ token, error: fcmErr.message });

          // If token unregistered or invalid, automatically deactivate
          if (
            fcmErr.code === 'messaging/registration-token-not-registered' ||
            fcmErr.code === 'messaging/invalid-registration-token' ||
            (fcmErr.message && fcmErr.message.includes('not-registered'))
          ) {
            await this.deactivateInvalidToken(token);
          }
        }
      }
    }

    return { dispatchedCount, skippedCount, errors };
  }

  /**
   * Dispatches push notification to staff of a specific clinical department (Eye / Dental) and admins.
   * Strictly enforces clinical scope by excluding 'optical'.
   * @param {Object} params
   * @param {string} params.department - 'eye' | 'dental'
   * @param {string} params.type
   * @param {string} [params.title]
   * @param {string} [params.body]
   * @param {string} [params.patientName]
   * @param {string} [params.relatedId]
   * @param {string} [params.idempotencyKey]
   * @param {boolean} [params.includeAdmins=true]
   * @returns {Promise<{dispatchedCount: number, skippedCount: number, errors: Array, opticalExcluded?: boolean}>}
   */
  async dispatchToDepartmentStaff({
    department,
    type,
    title,
    body,
    patientName,
    relatedId,
    idempotencyKey,
    includeAdmins = true,
  }) {
    const deptNormalized = (department || '').toLowerCase().trim();
    if (deptNormalized === 'optical') {
      this.logger(`[PushBackend] Optical department notification excluded by clinical scope.`);
      return { dispatchedCount: 0, skippedCount: 0, errors: [], opticalExcluded: true };
    }

    if (!this.supabase) {
      return { dispatchedCount: 0, skippedCount: 0, errors: [] };
    }

    try {
      let query = this.supabase
        .from('profiles')
        .select('id, role, department')
        .eq('is_active', true);

      if (includeAdmins) {
        if (deptNormalized) {
          query = query.or(`role.eq.admin,and(role.eq.staff,department.ilike.%${deptNormalized}%)`);
        } else {
          query = query.in('role', ['admin', 'staff']);
        }
      } else {
        if (deptNormalized) {
          query = query.eq('role', 'staff').ilike('department', `%${deptNormalized}%`);
        } else {
          query = query.eq('role', 'staff');
        }
      }

      const { data: profiles, error } = await query;
      if (error || !profiles || profiles.length === 0) {
        return { dispatchedCount: 0, skippedCount: 0, errors: [] };
      }

      const userIds = profiles.map((p) => p.id);
      return await this.dispatchToUsers({
        userIds,
        type,
        title,
        body,
        patientName,
        relatedId,
        department: deptNormalized,
        idempotencyKey,
      });
    } catch (err) {
      this.logger(`[PushBackend] Error dispatching to department staff: ${err.message}`);
      return { dispatchedCount: 0, skippedCount: 0, errors: [err.message] };
    }
  }
}

let defaultInstance = null;
function getPushNotificationBackend() {
  if (!defaultInstance) {
    try {
      const { supabase } = require('../config/supabase');
      const logger = require('../utils/logger');
      defaultInstance = new PushNotificationBackend({
        supabase,
        logger: (msg) => logger.info(msg),
      });
    } catch (_) {
      defaultInstance = new PushNotificationBackend();
    }
  }
  return defaultInstance;
}

module.exports = {
  PushNotificationBackend,
  pushNotificationBackend: getPushNotificationBackend(),
};
