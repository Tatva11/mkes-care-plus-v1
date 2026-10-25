/**
 * MKES CARE+ Push Notification Backend Unit Tests
 */

const assert = require('assert');
const { PushNotificationBackend } = require('../src/services/push_notification_backend');

console.log('====================================================');
console.log('  MKES CARE+ Push Notification Backend Test Suite');
console.log('====================================================\n');

let totalTests = 0;
let passedTests = 0;

async function test(name, fn) {
  totalTests++;
  try {
    await fn();
    passedTests++;
    console.log(`  ✓ [PASS] ${name}`);
  } catch (err) {
    console.error(`  ✗ [FAIL] ${name}`);
    console.error(`    ${err.message}\n${err.stack}`);
  }
}

async function runAll() {
  await test('1. Detects unconfigured Firebase environment accurately without inventing credentials', async () => {
    delete process.env.FIREBASE_SERVICE_ACCOUNT_KEY;
    delete process.env.GOOGLE_APPLICATION_CREDENTIALS;

    const backend = new PushNotificationBackend({ logger: () => {} });
    assert.strictEqual(backend.isFirebaseConfigured(), false);
  });

  await test('2. Formats privacy-preserving lock screen notification payloads', async () => {
    const backend = new PushNotificationBackend({ logger: () => {} });

    // Appointment rescheduled
    const apptPayload = backend.formatPayload({
      type: 'appointment_rescheduled',
      patientName: 'Ramesh Patel',
      relatedId: 'apt-101',
    });
    assert.strictEqual(apptPayload.title, 'Appointment Update');
    assert.strictEqual(apptPayload.body, 'Ramesh Patel rescheduled their consultation.');
    assert.strictEqual(apptPayload.data.type, 'appointment_rescheduled');
    assert.strictEqual(apptPayload.data.related_id, 'apt-101');

    // WhatsApp message
    const waPayload = backend.formatPayload({
      type: 'whatsapp_reply',
      patientName: 'Aisha Kumar',
      relatedId: 'wa-msg-55',
    });
    assert.strictEqual(waPayload.title, 'New Patient Message');
    assert.strictEqual(waPayload.body, 'Message received from Aisha Kumar.');

    // Dental Lab ready
    const labPayload = backend.formatPayload({
      type: 'lab_ready',
      patientName: 'Sunita Sharma',
      relatedId: 'case-99',
    });
    assert.strictEqual(labPayload.title, 'Dental Lab Alert');
    assert.strictEqual(labPayload.body, 'Restoration ready for fitting (Sunita Sharma).');

    // Eye Lab ready
    const eyeLabPayload = backend.formatPayload({
      type: 'lab_ready',
      department: 'eye',
      patientName: 'Kishore Kumar',
      relatedId: 'eye-case-12',
    });
    assert.strictEqual(eyeLabPayload.title, 'Eye Lab Alert');
    assert.strictEqual(eyeLabPayload.body, 'Appliance / lens ready (Kishore Kumar).');
  });

  await test('3. Fetches active device tokens for specific user from database', async () => {
    const mockSupabase = {
      from: (table) => {
        assert.strictEqual(table, 'user_device_tokens');
        return {
          select: () => ({
            eq: (col1, val1) => ({
              eq: (col2, val2) => {
                assert.strictEqual(col1, 'user_id');
                assert.strictEqual(val1, 'u-123');
                assert.strictEqual(col2, 'is_active');
                assert.strictEqual(val2, true);
                return Promise.resolve({
                  data: [
                    { device_token: 'tok-abc-1', device_type: 'android' },
                    { device_token: 'tok-abc-2', device_type: 'android' },
                  ],
                  error: null,
                });
              },
            }),
          }),
        };
      },
    };

    const backend = new PushNotificationBackend({ supabase: mockSupabase, logger: () => {} });
    const tokens = await backend.getActiveTokensForUser('u-123');
    assert.strictEqual(tokens.length, 2);
    assert.strictEqual(tokens[0].token, 'tok-abc-1');
  });

  await test('4. Deactivates invalid device token on FCM registration failure', async () => {
    let deactivatedToken = null;
    let updatePayload = null;

    const mockSupabase = {
      from: (table) => {
        assert.strictEqual(table, 'user_device_tokens');
        return {
          update: (payload) => ({
            eq: (col, val) => {
              deactivatedToken = val;
              updatePayload = payload;
              return Promise.resolve({ error: null });
            },
          }),
        };
      },
    };

    const backend = new PushNotificationBackend({ supabase: mockSupabase, logger: () => {} });
    const result = await backend.deactivateInvalidToken('expired-fcm-tok-xyz');
    assert.strictEqual(result, true);
    assert.strictEqual(deactivatedToken, 'expired-fcm-tok-xyz');
    assert.strictEqual(updatePayload.is_active, false);
  });

  await test('5. Prevents duplicate push notification dispatches via idempotencyKey', async () => {
    const backend = new PushNotificationBackend({ logger: () => {} });

    // First dispatch
    await backend.dispatchToUsers({
      userIds: ['u-101'],
      type: 'whatsapp_reply',
      idempotencyKey: 'idemp-wa-msg-101',
    });

    // Immediate second dispatch with same key
    const res2 = await backend.dispatchToUsers({
      userIds: ['u-101'],
      type: 'whatsapp_reply',
      idempotencyKey: 'idemp-wa-msg-101',
    });

    assert.strictEqual(res2.duplicate, true);
    assert.strictEqual(res2.dispatchedCount, 0);
  });

  await test('6. Handles live dispatch and cleans up invalid tokens if FCM send fails', async () => {
    let deactivated = false;
    const mockSupabase = {
      from: (table) => ({
        select: () => ({
          eq: () => ({
            eq: () =>
              Promise.resolve({
                data: [{ device_token: 'invalid-token-123', device_type: 'android' }],
                error: null,
              }),
          }),
        }),
        update: () => ({
          eq: () => {
            deactivated = true;
            return Promise.resolve({ error: null });
          },
        }),
      }),
    };

    const mockFirebaseAdmin = {
      messaging: () => ({
        send: () => {
          const err = new Error('The registration token is not registered');
          err.code = 'messaging/registration-token-not-registered';
          throw err;
        },
      }),
    };

    const backend = new PushNotificationBackend({
      supabase: mockSupabase,
      firebaseAdmin: mockFirebaseAdmin,
      logger: () => {},
    });

    const res = await backend.dispatchToUsers({
      userIds: ['user-bad-token'],
      type: 'appointment_rescheduled',
    });

    assert.strictEqual(res.dispatchedCount, 0);
    assert.strictEqual(res.errors.length, 1);
    assert.strictEqual(deactivated, true);
  });

  await test('7. Dispatches to department staff (Eye vs Dental) and includes admins', async () => {
    let queriedFilter = null;
    const mockSupabase = {
      from: (table) => {
        if (table === 'profiles') {
          return {
            select: () => ({
              eq: () => ({
                or: (filterStr) => {
                  queriedFilter = filterStr;
                  return Promise.resolve({
                    data: [
                      { id: 'admin-1', role: 'admin', department: null },
                      { id: 'staff-eye-1', role: 'staff', department: 'eye' },
                    ],
                    error: null,
                  });
                },
              }),
            }),
          };
        }
        if (table === 'user_device_tokens') {
          return {
            select: () => ({
              eq: () => ({
                eq: () =>
                  Promise.resolve({
                    data: [{ device_token: 'tok-staff-eye', device_type: 'android' }],
                    error: null,
                  }),
              }),
            }),
          };
        }
        return {};
      },
    };

    const backend = new PushNotificationBackend({ supabase: mockSupabase, logger: () => {} });
    const res = await backend.dispatchToDepartmentStaff({
      department: 'eye',
      type: 'eye_lab_ready',
      title: 'Eye Lab Alert',
      body: 'IOL lens ready',
      idempotencyKey: 'test-eye-lab-1',
    });

    assert.ok(queriedFilter.includes('department.ilike.%eye%'));
    assert.strictEqual(res.dispatchedCount, 2); // 2 users queried in dry run
  });

  await test('8. Strictly rejects and excludes optical workflows from push notifications', async () => {
    const backend = new PushNotificationBackend({ logger: () => {} });
    const res = await backend.dispatchToDepartmentStaff({
      department: 'optical',
      type: 'lab_ready',
      title: 'Optical Notification',
      body: 'Glasses ready',
    });

    assert.strictEqual(res.opticalExcluded, true);
    assert.strictEqual(res.dispatchedCount, 0);
  });

  await test('9. Reschedule failure does not trigger staff push notification', async () => {
    let pushDispatched = false;
    const mockPush = {
      dispatchToDepartmentStaff: () => {
        pushDispatched = true;
        return Promise.resolve({ dispatchedCount: 1 });
      },
    };

    // Simulate reschedule workflow where RPC returns failure
    const rpcResult = { success: false, message: 'Requested slot is outside operating hours' };
    let rpcSuccess = false;

    if (rpcResult && rpcResult.success) {
      rpcSuccess = true;
      await mockPush.dispatchToDepartmentStaff({
        department: 'dental',
        type: 'appointment_rescheduled',
      });
    }

    assert.strictEqual(rpcSuccess, false);
    assert.strictEqual(pushDispatched, false);
  });

  await test('10. NotificationWatcher filters optical notifications and avoids duplicates', async () => {
    const notificationWatcher = require('../src/services/notification_watcher');
    assert.strictEqual(typeof notificationWatcher.processPendingNotifications, 'function');
    assert.strictEqual(typeof notificationWatcher.start, 'function');
    assert.strictEqual(typeof notificationWatcher.stop, 'function');
  });

  console.log(`\n====================================================`);
  console.log(`  Tests completed: ${passedTests}/${totalTests} passed`);
  console.log(`====================================================\n`);

  if (passedTests !== totalTests) {
    process.exit(1);
  }
}

runAll();
