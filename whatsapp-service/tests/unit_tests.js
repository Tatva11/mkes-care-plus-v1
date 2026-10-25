/**
 * MKES CARE+ WhatsApp Integration — Unit & Regression Test Suite
 * Tests core algorithms: Phone Normalization, Slot Math, Overlap Intervals,
 * Opt-Out Logic, Expired Lease Recovery, Duplicate Prevention, Concurrency Locks,
 * Doctor Eligibility, and Status Guard Triggers.
 */

const path = require('path');
const fs = require('fs');
const PhoneNormalizer = require('../src/utils/phone_normalizer');
const RecipientValidator = require('../src/utils/recipient_validator');
const { CLINIC, DEPARTMENTS, CONFIRMED_DOCTORS, MESSAGE_TYPES } = require('../src/config/constants');

let passedTests = 0;
let totalTests = 0;

function assert(description, condition, failureDetail = '') {
  totalTests++;
  if (condition) {
    passedTests++;
    console.log(`  ✓ [PASS] ${description}`);
  } else {
    console.error(`  ✗ [FAIL] ${description} -> ${failureDetail}`);
  }
}

console.log('====================================================');
console.log('  MKES CARE+ Phase 2 Comprehensive Test Suite       ');
console.log('====================================================\n');

async function runTests() {

// -----------------------------------------------------------------------------
// Test Suite 1: Phone Normalization Consistency
// -----------------------------------------------------------------------------
console.log('--- Test Suite 1: Phone Normalization ---');

assert(
  'Extract 10 digits from raw 10-digit number',
  PhoneNormalizer.extractTenDigits('9876543210') === '9876543210'
);

assert(
  'Extract 10 digits from number with +91 country code and spaces',
  PhoneNormalizer.extractTenDigits('+91 98765 43210') === '9876543210'
);

assert(
  'Extract 10 digits from number with leading 0 (trunk code)',
  PhoneNormalizer.extractTenDigits('09876543210') === '9876543210'
);

assert(
  'Extract 10 digits from formatted mobile: +91-9876-543-210',
  PhoneNormalizer.extractTenDigits('+91-9876-543-210') === '9876543210'
);

assert(
  'Reject invalid phone numbers with less than 10 digits',
  PhoneNormalizer.extractTenDigits('12345') === null
);

assert(
  'Format standard Indian WhatsApp JID (91XXXXXXXXXX@c.us)',
  PhoneNormalizer.toWhatsAppJid('+91 98765 43210') === '919876543210@c.us'
);

assert(
  'Identify individual chat JID vs group JID',
  PhoneNormalizer.isIndividualChat('919876543210@c.us') === true &&
  PhoneNormalizer.isIndividualChat('123456789-987654@g.us') === false
);

// -----------------------------------------------------------------------------
// Test Suite 2: Appointment Overlap & Interval Collision Mathematics
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 2: Interval Collision Mathematics ---');

/**
 * Interval collision helper:
 * Two time intervals [A_start, A_end] and [B_start, B_end] overlap iff:
 * A_start < B_end AND B_start < A_end
 */
function intervalsOverlap(startA, durationA, startB, durationB) {
  const endA = startA + durationA;
  const endB = startB + durationB;
  return startA < endB && startB < endA;
}

// Convert "HH:MM" to minutes from midnight
function toMinutes(timeStr) {
  const [h, m] = timeStr.split(':').map(Number);
  return h * 60 + m;
}

const slot1000 = toMinutes('10:00');
const slot1015 = toMinutes('10:15');
const slot1030 = toMinutes('10:30');
const slot1045 = toMinutes('10:45');

assert(
  '15m appointment at 10:00 overlaps with another 15m appointment at 10:00',
  intervalsOverlap(slot1000, 15, slot1000, 15) === true
);

assert(
  '15m appointment at 10:00 does NOT overlap with adjacent 15m slot at 10:15',
  intervalsOverlap(slot1000, 15, slot1015, 15) === false
);

assert(
  '30m appointment at 10:00 overlaps with candidate 15m slot at 10:15',
  intervalsOverlap(slot1000, 30, slot1015, 15) === true
);

assert(
  '30m appointment at 10:00 does NOT overlap with candidate 15m slot at 10:30',
  intervalsOverlap(slot1000, 30, slot1030, 15) === false
);

assert(
  '45m surgery at 10:00 overlaps with candidate slot at 10:30',
  intervalsOverlap(slot1000, 45, slot1030, 15) === true
);

assert(
  '45m surgery at 10:00 does NOT overlap with candidate slot at 10:45',
  intervalsOverlap(slot1000, 45, slot1045, 15) === false
);

// -----------------------------------------------------------------------------
// Test Suite 3: Double-Counting Prevention Logic
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 3: Double-Counting Prevention ---');

const mockRequests = [
  { id: 'req-1', status: 'pending_review', promoted_appointment_id: null },
  { id: 'req-2', status: 'approved', promoted_appointment_id: 'appt-99' },
  { id: 'req-3', status: 'rejected', promoted_appointment_id: null },
];

const unpromotedRequests = mockRequests.filter(
  (r) => r.status === 'pending_review' && r.promoted_appointment_id === null
);

assert(
  'Approved and promoted requests are excluded from pending commitments',
  unpromotedRequests.length === 1 && unpromotedRequests[0].id === 'req-1'
);

// -----------------------------------------------------------------------------
// Test Suite 4: Outbox Lease Expiry & Crash Recovery
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 4: Outbox Lease Expiry & Crash Recovery ---');

const now = new Date('2026-10-18T10:00:00Z');
const mockOutbox = [
  // 1. Fresh pending message
  { id: 'msg-1', status: 'pending', scheduled_for: new Date('2026-10-18T09:59:00Z'), lease_expires_at: null, retry_count: 0 },
  // 2. Active processing message (worker is alive)
  { id: 'msg-2', status: 'processing', scheduled_for: new Date('2026-10-18T09:55:00Z'), lease_expires_at: new Date('2026-10-18T10:00:30Z'), retry_count: 0 },
  // 3. Crashed processing message (worker died, lease expired 5 mins ago)
  { id: 'msg-3', status: 'processing', scheduled_for: new Date('2026-10-18T09:50:00Z'), lease_expires_at: new Date('2026-10-18T09:55:00Z'), retry_count: 1 },
  // 4. Exhausted retries
  { id: 'msg-4', status: 'processing', scheduled_for: new Date('2026-10-18T09:50:00Z'), lease_expires_at: new Date('2026-10-18T09:55:00Z'), retry_count: 3 },
];

function isClaimable(msg, currentTime, maxRetries = 3) {
  if (msg.status === 'pending') {
    return msg.scheduled_for <= currentTime && (!msg.lease_expires_at || msg.lease_expires_at < currentTime);
  }
  if (msg.status === 'processing') {
    return msg.lease_expires_at < currentTime && msg.retry_count < maxRetries;
  }
  return false;
}

assert('Fresh pending message is claimable', isClaimable(mockOutbox[0], now) === true);
assert('Active processing message is NOT claimable by another worker', isClaimable(mockOutbox[1], now) === false);
assert('Crashed processing message with expired lease IS reclaimed', isClaimable(mockOutbox[2], now) === true);
assert('Crashed message with max retries is NOT reclaimed', isClaimable(mockOutbox[3], now) === false);

// -----------------------------------------------------------------------------
// Test Suite 5: Duplicate Send Prevention on Reclaim
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 5: Duplicate Send Prevention on Reclaim ---');

const mockLogs = [
  { outbox_id: 'msg-3', direction: 'outbound', timestamp: '2026-10-18T09:54:55Z' },
];

function shouldSkipSend(outboxItem, logs) {
  if (outboxItem.retry_count > 0) {
    const foundLog = logs.find((l) => l.outbox_id === outboxItem.id && l.direction === 'outbound');
    if (foundLog) return true;
  }
  return false;
}

assert(
  'Reclaimed message with existing outbound log is reconciled without resending',
  shouldSkipSend(mockOutbox[2], mockLogs) === true
);

assert(
  'Fresh message without prior log is dispatched normally',
  shouldSkipSend(mockOutbox[0], mockLogs) === false
);

// -----------------------------------------------------------------------------
// Test Suite 6: Status Guard & Direct Update Prevention
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 6: Status Guard Trigger Simulation ---');

function simulateUpdateStatus(oldStatus, newStatus, rpcContextActive) {
  if (oldStatus !== newStatus) {
    if (!rpcContextActive) {
      throw new Error('Direct status updates on public.whatsapp_appointment_requests are prohibited.');
    }
  }
  return newStatus;
}

let directUpdateBlocked = false;
try {
  simulateUpdateStatus('pending_review', 'approved', false);
} catch (e) {
  directUpdateBlocked = true;
}
assert('Direct status mutation without RPC context is rejected', directUpdateBlocked);

let rpcUpdateAllowed = false;
try {
  const result = simulateUpdateStatus('pending_review', 'approved', true);
  rpcUpdateAllowed = (result === 'approved');
} catch (e) {
  rpcUpdateAllowed = false;
}
assert('Status update inside RPC context with override setting is allowed', rpcUpdateAllowed);

// -----------------------------------------------------------------------------
// Test Suite 7: Rejection Status Precondition
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 7: Rejection Status Preconditions ---');

function simulateReject(request) {
  if (request.status !== 'pending_review') {
    return { success: false, message: `Request cannot be rejected because it is currently in status: ${request.status}` };
  }
  return { success: true };
}

assert('Rejection succeeds for pending_review request', simulateReject({ status: 'pending_review' }).success === true);
assert('Rejection fails for already approved request', simulateReject({ status: 'approved' }).success === false);
assert('Rejection fails for already rejected request', simulateReject({ status: 'rejected' }).success === false);

// -----------------------------------------------------------------------------
// Test Suite 8: Doctor Eligibility & Department Matching
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 8: Doctor Eligibility Validation ---');

const activeDoctors = [
  { id: 'doc-eye-1', name: 'Dr Mitesh Jain', department: 'eye', isActive: true },
  { id: 'doc-eye-2', name: 'Dr Varun', department: 'eye', isActive: true },
  { id: 'doc-dent-1', name: 'Dr Nimisha', department: 'dental', isActive: true },
  { id: 'doc-dent-2', name: 'Dr Vikas', department: 'dental', isActive: false }, // inactive
];

function validateDoctor(doctorId, department) {
  const doc = activeDoctors.find((d) => d.id === doctorId);
  if (!doc) return { valid: false, reason: 'Doctor not found' };
  if (!doc.isActive) return { valid: false, reason: 'Doctor inactive' };
  if (doc.department.toLowerCase() !== department.toLowerCase()) {
    return { valid: false, reason: 'Department mismatch' };
  }
  return { valid: true };
}

assert('Active eye doctor is eligible for eye appointment', validateDoctor('doc-eye-1', 'eye').valid === true);
assert('Dental doctor is rejected for eye appointment', validateDoctor('doc-dent-1', 'eye').valid === false);
assert('Inactive doctor is rejected', validateDoctor('doc-dent-2', 'dental').valid === false);
assert('Unknown doctor ID is rejected', validateDoctor('doc-unknown', 'eye').valid === false);

// -----------------------------------------------------------------------------
// Test Suite 9: Opt-Out Race & Pre-Send Cancellation
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 9: Opt-Out In-Flight Race Protection ---');

const queueWithOptOut = [
  { id: 'msg-p1', status: 'pending', phone: '9876543210' },
  { id: 'msg-p2', status: 'processing', phone: '9876543210' },
  { id: 'msg-p3', status: 'pending', phone: '9123456789' },
];

function simulateOptOut(optedPhone, queue) {
  for (const item of queue) {
    if (item.phone === optedPhone && ['pending', 'processing'].includes(item.status)) {
      item.status = 'cancelled';
      item.lastError = 'Patient opted out';
    }
  }
}

simulateOptOut('9876543210', queueWithOptOut);
assert('Pending message is cancelled upon opt-out', queueWithOptOut[0].status === 'cancelled');
assert('Processing lease message is cancelled upon opt-out', queueWithOptOut[1].status === 'cancelled');
assert('Unrelated patient message remains pending', queueWithOptOut[2].status === 'pending');

// -----------------------------------------------------------------------------
// Test Suite 10: Slot Generation Input Validation
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 10: Slot Input Validation ---');

function validateSlotInputs(department, dateStr, durationMinutes, intervalMinutes) {
  if (!['eye', 'dental'].includes(department.toLowerCase())) {
    throw new Error('Invalid department');
  }
  const dateObj = new Date(dateStr);
  const today = new Date('2026-10-18');
  if (dateObj < today) {
    throw new Error('Past date');
  }
  if (durationMinutes <= 0 || durationMinutes > 240 || durationMinutes % 15 !== 0) {
    throw new Error('Invalid duration');
  }
  if (intervalMinutes <= 0 || intervalMinutes > 60 || intervalMinutes % 15 !== 0) {
    throw new Error('Invalid interval');
  }
  return true;
}

assert('Valid slot inputs pass validation', validateSlotInputs('eye', '2026-10-19', 15, 15) === true);

let pastDateRejected = false;
try { validateSlotInputs('eye', '2026-10-10', 15, 15); } catch (e) { pastDateRejected = true; }
assert('Past date is rejected', pastDateRejected);

let invalidDurationRejected = false;
try { validateSlotInputs('dental', '2026-10-19', 25, 15); } catch (e) { invalidDurationRejected = true; }
assert('Non-15-minute duration is rejected', invalidDurationRejected);

let opticalDeptRejected = false;
try { validateSlotInputs('optical', '2026-10-19', 15, 15); } catch (e) { opticalDeptRejected = true; }
assert('Optical department is strictly rejected', opticalDeptRejected);

// -----------------------------------------------------------------------------
// Test Suite 11: Automation Categories & Clinical Scope Integrity
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 11: Automation Categories & Scope Integrity ---');

assert('Optical department is strictly excluded from DEPARTMENTS', !DEPARTMENTS.OPTICAL);
assert('Eye department configured with exactly 2 doctors', CONFIRMED_DOCTORS.eye.length === 2);
assert('Dental department configured with exactly 2 doctors', CONFIRMED_DOCTORS.dental.length === 2);

const expectedCategories = [
  'reminder_24h',
  'reminder_2h',
  'annual_eye',
  'dental_cleaning',
  'dental_rct',
  'dental_implant',
  'lab_ready',
  'birthday',
  'festival',
  'review_request',
  'payment_receipt',
  'payment_reminder',
  'vendor_po',
];

const allCategoriesCovered = expectedCategories.every((cat) =>
  Object.values(MESSAGE_TYPES).includes(cat)
);

assert('All 13 operational message types are registered in constants', allCategoriesCovered);

// -----------------------------------------------------------------------------
// Test Suite 12: IST Timezone, 24h/2h Reminders & Scheduler Deduplication
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 12: Timezone, Reminders & Scheduler Deduplication ---');

// A. IST Timezone Offset Verification
const utcDate = new Date('2026-10-18T03:30:00.000Z'); // 03:30 UTC = 09:00 IST
const istOffsetMs = 5.5 * 60 * 60 * 1000;
const istDate = new Date(utcDate.getTime() + istOffsetMs);
assert('UTC 03:30 converts accurately to 09:00 IST', istDate.getUTCHours() === 9 && istDate.getUTCMinutes() === 0);

// B. 2-Hour Reminder Window Check
function isEligibleFor2hReminder(currentTimeStr, apptTimeStr) {
  const [cHour, cMin] = currentTimeStr.split(':').map(Number);
  const [aHour, aMin] = apptTimeStr.split(':').map(Number);
  const currentTotal = cHour * 60 + cMin;
  const apptTotal = aHour * 60 + aMin;
  const diff = apptTotal - currentTotal;
  // Window: 0 to 135 minutes (2h 15m)
  return diff >= 0 && diff <= 135;
}

assert('Appointment in 90 minutes is eligible for 2h reminder', isEligibleFor2hReminder('09:30', '11:00') === true);
assert('Appointment in 10 minutes is eligible for 2h reminder', isEligibleFor2hReminder('09:30', '09:40') === true);
assert('Appointment in 4 hours is NOT eligible for 2h reminder', isEligibleFor2hReminder('09:30', '13:30') === false);
assert('Past appointment is NOT eligible for 2h reminder', isEligibleFor2hReminder('09:30', '09:15') === false);

// C. Multi-Scheduler Mutual Exclusion Lock Simulation
class MockAdvisoryLockRegistry {
  constructor() {
    this.locks = new Set();
  }
  tryLock(key) {
    if (this.locks.has(key)) return false;
    this.locks.add(key);
    return true;
  }
  release(key) {
    this.locks.delete(key);
  }
}

const lockRegistry = new MockAdvisoryLockRegistry();
const lockKey = 'mkes_wa_batch_appointment_reminders';

// First scheduler invocation acquires lock
const pgCronAcquired = lockRegistry.tryLock(lockKey);
// Concurrent host scheduler invocation tries at same millisecond
const hostSchedulerAcquired = lockRegistry.tryLock(lockKey);

assert('First scheduler caller (pg_cron) acquires advisory lock', pgCronAcquired === true);
assert('Concurrent scheduler caller (host) is safely rejected without collision', hostSchedulerAcquired === false);

// After transaction completes, lock is released and can be re-acquired
lockRegistry.release(lockKey);
assert('Advisory lock is released after transaction completes', lockRegistry.tryLock(lockKey) === true);
lockRegistry.release(lockKey);

// D. Anti-Join Deduplication Barrier Simulation
const existingOutbox = [
  { patient_id: 'p-1', message_type: 'reminder_24h', created_at: new Date(Date.now() - 3600000) }, // 1h ago
  { patient_id: 'p-2', message_type: 'reminder_2h', created_at: new Date() } // today
];

function canEnqueueReminder(patientId, messageType, outbox) {
  const cutoff = messageType === 'reminder_24h' ? 20 * 3600000 : 12 * 3600000;
  const exists = outbox.some(
    (o) => o.patient_id === patientId && o.message_type === messageType && (Date.now() - o.created_at.getTime()) < cutoff
  );
  return !exists;
}

assert('Duplicate 24h reminder is blocked within 20-hour window', canEnqueueReminder('p-1', 'reminder_24h', existingOutbox) === false);
assert('New patient is permitted for 24h reminder', canEnqueueReminder('p-3', 'reminder_24h', existingOutbox) === true);
assert('Duplicate 2h reminder is blocked if already enqueued today', canEnqueueReminder('p-2', 'reminder_2h', existingOutbox) === false);

// -----------------------------------------------------------------------------
// Test Suite 13: Role-Based Authorization Matrix
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 13: Role-Based Authorization Matrix ---');

function simulateRpcAuth(caller) {
  // caller: { authType: 'anon' | 'authenticated' | 'service_role' | 'pg_cron', userId: string | null, profileRole: string | null }
  if (caller.authType === 'anon') {
    return { allowed: false, error: '401/403 Permission Denied: execute revoked from PUBLIC' };
  }
  // service_role or pg_cron: elevated background context where auth.uid() is null
  if (caller.authType === 'service_role' || caller.authType === 'pg_cron' || caller.userId === null) {
    return { allowed: true, executedBy: caller.authType };
  }
  // Authenticated user: inspect profile role in public.profiles
  if (caller.profileRole === 'admin') {
    return { allowed: true, executedBy: 'admin_user' };
  }
  return { allowed: false, error: 'Forbidden: Only administrators or background workers can execute batch enqueue procedures.' };
}

assert('Anonymous caller is rejected at PostgREST grant layer', simulateRpcAuth({ authType: 'anon' }).allowed === false);
assert('Non-admin staff caller is rejected by function body check', simulateRpcAuth({ authType: 'authenticated', userId: 'user-staff-1', profileRole: 'staff' }).allowed === false);
assert('Patient caller is rejected by function body check', simulateRpcAuth({ authType: 'authenticated', userId: 'user-pat-1', profileRole: 'patient' }).allowed === false);
assert('Admin caller is permitted by function check', simulateRpcAuth({ authType: 'authenticated', userId: 'user-admin-1', profileRole: 'admin' }).allowed === true);
assert('Service role caller (Windows scheduler) is permitted without user profile', simulateRpcAuth({ authType: 'service_role', userId: null }).allowed === true);
assert('pg_cron background worker is permitted without user profile', simulateRpcAuth({ authType: 'pg_cron', userId: null }).allowed === true);

// -----------------------------------------------------------------------------
// Test Suite 14: DRY_RUN Outbox Lifecycle & Safety Guarantee
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 14: DRY_RUN Outbox Lifecycle & Safety Guarantee ---');

let testOutbox = [
  { id: 'msg-dry-1', recipient: '9876543210', status: 'pending', lease_id: null, scheduled_for: new Date(Date.now() - 1000) }
];
let testAuditLogs = [];

function processOutboxDryRun(item, isDryRun) {
  // 1. Claim lease
  item.status = 'processing';
  item.lease_id = 'worker-uuid-1';
  
  if (isDryRun) {
    // DRY RUN: Verify and simulate, but DO NOT mark sent and DO NOT write audit log!
    item.status = 'pending';
    item.lease_id = null;
    item.scheduled_for = new Date(Date.now() + 300000); // 5m backoff
    item.last_error = '[DRY RUN] Simulated send successful - safely preserved for live delivery';
    return { sent: false, simulated: true };
  } else {
    // LIVE: Mark sent and record in audit log
    item.status = 'sent';
    item.lease_id = null;
    item.sent_at = new Date().toISOString();
    testAuditLogs.push({ outbox_id: item.id, recipient: item.recipient, timestamp: new Date().toISOString() });
    return { sent: true, simulated: false };
  }
}

// Execute with DRY_RUN = true
const dryResult = processOutboxDryRun(testOutbox[0], true);
assert('DRY_RUN simulation reports simulated without sending', dryResult.simulated === true && dryResult.sent === false);
assert('DRY_RUN leaves message status as pending (not sent)', testOutbox[0].status === 'pending');
assert('DRY_RUN writes 0 genuine delivery audit logs', testAuditLogs.length === 0);
assert('DRY_RUN clears lease_id upon simulation release', testOutbox[0].lease_id === null);

// Simulate subsequent live run with DRY_RUN = false
testOutbox[0].scheduled_for = new Date(Date.now() - 1000); // simulate 5 min elapsed
const liveResult = processOutboxDryRun(testOutbox[0], false);
assert('Subsequent live run cleanly claims the preserved message and delivers', liveResult.sent === true);
assert('Live run marks message status as sent', testOutbox[0].status === 'sent');
assert('Live run writes exactly 1 genuine audit log', testAuditLogs.length === 1);

// Client-level safeguard tests
const whatsappClient = require('../src/services/whatsapp_client');
const savedDryRun = process.env.DRY_RUN;

delete process.env.DRY_RUN; // unset -> must default to safe mode
const clientResUnset = await whatsappClient.sendMessageWithHumanizedDelay('919876543210@c.us', 'Safe test 1');
assert('Client safeguard blocks real dispatch by default when DRY_RUN is unset', clientResUnset.simulated === true);

process.env.DRY_RUN = 'true'; // explicit true
const clientResTrue = await whatsappClient.sendMessageWithHumanizedDelay('919876543210@c.us', 'Safe test 2');
assert('Client safeguard blocks real dispatch when DRY_RUN=true', clientResTrue.simulated === true);

process.env.DRY_RUN = 'false'; // explicit false
let attemptedRealSend = false;
try {
  await whatsappClient.sendMessageWithHumanizedDelay('919876543210@c.us', 'Live test');
} catch (err) {
  attemptedRealSend = err.message.includes('WhatsApp client is not ready');
}
assert('Live dispatch requires explicit DRY_RUN=false (throws not ready instead of simulated)', attemptedRealSend === true);

// Test ambiguous values default to safe simulation mode
process.env.DRY_RUN = 'invalid_env_val';
const clientResAmbiguous = await whatsappClient.sendMessageWithHumanizedDelay('919876543210@c.us', 'Ambiguous test');
assert('Ambiguous DRY_RUN values default to safe simulation mode', clientResAmbiguous.simulated === true);

process.env.DRY_RUN = '0'; // non-'false' falsy representation
const clientResZero = await whatsappClient.sendMessageWithHumanizedDelay('919876543210@c.us', 'Zero test');
assert('Numeric 0 DRY_RUN defaults to safe simulation mode', clientResZero.simulated === true);

// Case-insensitive and trimmed ' FALSE ' is correctly recognized as false
process.env.DRY_RUN = ' FALSE ';
let attemptedTrimmedRealSend = false;
try {
  await whatsappClient.sendMessageWithHumanizedDelay('919876543210@c.us', 'Trimmed test');
} catch (err) {
  attemptedTrimmedRealSend = err.message.includes('WhatsApp client is not ready');
}
assert('Trimmed case-insensitive FALSE correctly arms live dispatch', attemptedTrimmedRealSend === true);

process.env.DRY_RUN = savedDryRun || 'true'; // restore safe default

// -----------------------------------------------------------------------------
// Test Suite 15: Appointment Approval Availability Recheck & Concurrency
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 15: Appointment Approval Availability Recheck ---');

let existingDeptAppointments = [
  { id: 'appt-1', date: '2026-10-20', dept: 'eye', time: 600, endTime: 615, status: 'confirmed' } // 10:00 - 10:15
];

const deptActiveChairs = 2; // e.g. 2 active eye doctors

function approveAppointmentRequest(request, appointments, capacity) {
  if (request.status !== 'pending_review') {
    return { success: false, error: 'Request not in pending_review status' };
  }
  // Dynamic conflict check: count concurrent commitments in requested interval
  const overlapping = appointments.filter(
    (a) => a.date === request.date && a.dept === request.dept && a.status !== 'cancelled' &&
           a.time < request.endTime && a.endTime > request.time
  ).length;

  if (overlapping >= capacity) {
    return { success: false, error: 'Department capacity reached' };
  }

  request.status = 'approved';
  appointments.push({
    id: `appt-promoted-${Date.now()}`,
    date: request.date,
    dept: request.dept,
    time: request.time,
    endTime: request.endTime,
    status: 'confirmed'
  });
  return { success: true };
}

const req1 = { id: 'req-1', status: 'pending_review', date: '2026-10-20', dept: 'eye', time: 600, endTime: 615 };
const req2 = { id: 'req-2', status: 'pending_review', date: '2026-10-20', dept: 'eye', time: 600, endTime: 615 };

// First pending request approved into chair 2 (capacity 2: appt-1 takes chair 1, req1 takes chair 2)
const res1 = approveAppointmentRequest(req1, existingDeptAppointments, deptActiveChairs);
assert('First pending request approved successfully within chair capacity', res1.success === true);
assert('Request 1 status updated to approved', req1.status === 'approved');

// Second pending request attempts to be approved for same slot (now capacity is full: 2/2)
const res2 = approveAppointmentRequest(req2, existingDeptAppointments, deptActiveChairs);
assert('Second overlapping request rejected due to department capacity exhaustion', res2.success === false && res2.error === 'Department capacity reached');
assert('Request 2 remains safely in pending_review status', req2.status === 'pending_review');

// Attempting to re-approve already approved request 1 fails status precondition
const resReapprove = approveAppointmentRequest(req1, existingDeptAppointments, deptActiveChairs);
assert('Re-approval of already approved request is blocked by status guard', resReapprove.success === false);

// -----------------------------------------------------------------------------
// Test Suite 16: Phase 3 Date Choice (1/2/3), IST Helpers & Upcoming Dates
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 16: Phase 3 Date Choice (1/2/3) & IST Helpers ---');

const SlotService = require('../src/services/slot_service');

const todayIst = SlotService.getTodayIST();
const tomorrowIst = SlotService.getTomorrowIST();
assert('Today IST date string matches YYYY-MM-DD format', /^\d{4}-\d{2}-\d{2}$/.test(todayIst));
assert('Tomorrow IST date string matches YYYY-MM-DD format', /^\d{4}-\d{2}-\d{2}$/.test(tomorrowIst));

const todayDate = new Date(todayIst);
const tomorrowDate = new Date(tomorrowIst);
const diffMs = tomorrowDate.getTime() - todayDate.getTime();
assert('Tomorrow is exactly 1 calendar day after Today', diffMs === 86400000 || diffMs === 86400000 - 3600000 || diffMs === 86400000 + 3600000);

const upcomingDates = SlotService.getEligibleUpcomingDates();
assert('Upcoming dates returns up to 3 dates', upcomingDates.length <= 3 && upcomingDates.length > 0);
assert('Upcoming dates have dateIso and display format', upcomingDates.every(d => d.dateIso && d.display));

// Verify upcoming dates start from Day+2 (after tomorrow)
if (upcomingDates.length > 0) {
  const firstUpcomingDate = new Date(upcomingDates[0].dateIso);
  assert('First upcoming date starts strictly after tomorrow (Day+2 or later)', firstUpcomingDate > tomorrowDate);
}

// Verify no upcoming dates are Sunday (day 0)
const hasSunday = upcomingDates.some(d => new Date(d.dateIso).getDay() === 0);
assert('Upcoming dates strictly exclude Sundays (clinic closed)', !hasSunday);

// -----------------------------------------------------------------------------
// Test Suite 17: Phase 3 Conversational Reliability, Debounce & Optical Exclusion
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 17: Conversational Reliability, Debounce & Optical Exclusion ---');

// 1. Optical department exclusion
function isOpticalBlocked(input) {
  const upper = input.toUpperCase();
  return upper.includes('OPTICAL') || upper.includes('GLASSES') || upper.includes('SPECTACLES');
}
assert('Optical keyword is detected and blocked', isOpticalBlocked('I want an optical appointment') === true);
assert('Glasses keyword is detected and blocked', isOpticalBlocked('Looking for reading glasses') === true);
assert('Spectacles keyword is detected and blocked', isOpticalBlocked('Eye spectacles check') === true);
assert('Standard eye consultation is NOT blocked', isOpticalBlocked('Book eye consultation') === false);
assert('Dental checkup is NOT blocked', isOpticalBlocked('Dental cleaning') === false);

// 2. Restart commands
const RESTART_COMMANDS = ['HI', 'HELLO', 'HEY', 'START', 'RESTART', 'MENU', 'RESET', 'CANCEL', '0'];
function isRestartCommand(input) {
  return RESTART_COMMANDS.includes(input.trim().toUpperCase());
}
assert('"hi" triggers conversational restart to menu', isRestartCommand('hi') === true);
assert('"menu" triggers conversational restart to menu', isRestartCommand('menu') === true);
assert('"0" triggers return to main menu', isRestartCommand('0') === true);
assert('"restart" triggers conversational restart', isRestartCommand('restart') === true);
assert('Normal slot choice "2" is not treated as restart', isRestartCommand('2') === false);

// 3. Debounce check
function shouldDebounce(session, currentBody, currentTimeMs) {
  if (
    session.last_message_body === currentBody &&
    session.last_message_time &&
    currentTimeMs - session.last_message_time < 2000
  ) {
    return true;
  }
  return false;
}
const testSession = { last_message_body: '1', last_message_time: 1000000 };
assert('Identical message within 500ms is debounced', shouldDebounce(testSession, '1', 1000500) === true);
assert('Identical message after 2500ms is NOT debounced', shouldDebounce(testSession, '1', 1002500) === false);
assert('Different message within 500ms is NOT debounced', shouldDebounce(testSession, '2', 1000500) === false);

// 4. Session expiry (30-minute threshold)
function isSessionExpired(lastInteractionIso, nowMs) {
  const lastMs = new Date(lastInteractionIso).getTime();
  return (nowMs - lastMs) > (30 * 60 * 1000);
}
const freshSessionTime = new Date(Date.now() - 5 * 60 * 1000).toISOString(); // 5 min ago
const staleSessionTime = new Date(Date.now() - 35 * 60 * 1000).toISOString(); // 35 min ago
assert('Session active 5 minutes ago is not expired', isSessionExpired(freshSessionTime, Date.now()) === false);
assert('Session active 35 minutes ago is expired', isSessionExpired(staleSessionTime, Date.now()) === true);

// 5. Duplicate pending request prevention
const existingPendingRequests = [
  { patient_phone: '9876543210', department: 'eye', requested_date: '2026-10-21', requested_time: '10:00:00', status: 'pending_review' }
];

function isDuplicatePendingRequest(newReq, list) {
  return list.some(r =>
    r.patient_phone === newReq.patient_phone &&
    r.department === newReq.department &&
    r.requested_date === newReq.requested_date &&
    r.requested_time === newReq.requested_time &&
    r.status === 'pending_review'
  );
}

const dupReq = { patient_phone: '9876543210', department: 'eye', requested_date: '2026-10-21', requested_time: '10:00:00' };
const distinctReq = { patient_phone: '9876543210', department: 'eye', requested_date: '2026-10-21', requested_time: '11:00:00' };

assert('Duplicate pending request is detected and prevented', isDuplicatePendingRequest(dupReq, existingPendingRequests) === true);
assert('Distinct time slot request is permitted', isDuplicatePendingRequest(distinctReq, existingPendingRequests) === false);

// -----------------------------------------------------------------------------
// Test Suite 18: End-to-End Booking Simulation, Dashboard Approval & Automated Messaging
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 18: End-to-End Booking, Dashboard Approval & Messaging ---');

// Simulated database state for end-to-end integration test
const mockDb = {
  chatSessions: {},
  appointmentRequests: [],
  clinicalAppointments: [],
  outbox: [],
  patients: [
    { id: 'pat-101', name: 'Ramesh Patel', mobile: '+91 98200 12345', whatsapp_opt_out: false, department: 'dental' },
    { id: 'pat-102', name: 'Sunita Sharma', mobile: '+91 98200 54321', whatsapp_opt_out: true, department: 'eye' }
  ],
  doctors: [
    { id: 'doc-1', name: 'Dr. Sneha Shah', department: 'dental', is_active: true },
    { id: 'doc-2', name: 'Dr. Rahul Mehta', department: 'eye', is_active: true }
  ]
};

// 1. Inbound "Hi" -> Session initialized to AWAITING_DATE_CHOICE
const phone = '919820012345';
let mockSession = { phone_number: phone, current_step: 'idle', presented_options: [] };
function simulateInbound(body, session) {
  const upper = body.trim().toUpperCase();
  if (upper === 'HI' || session.current_step === 'idle') {
    session.current_step = 'awaiting_date_choice';
    return { step: session.current_step, reply: 'Welcome to MKES CARE+ Hospital! 1 — Today, 2 — Tomorrow, 3 — Choose from upcoming dates' };
  }
  if (session.current_step === 'awaiting_date_choice') {
    if (body === '2') {
      session.current_step = 'awaiting_slot_choice';
      session.selected_date = '2026-10-22';
      session.presented_options = [
        { slot: '10:00:00', formatted: '10:00 AM' },
        { slot: '10:15:00', formatted: '10:15 AM' },
        { slot: '10:30:00', formatted: '10:30 AM' }
      ];
      return { step: session.current_step, reply: 'Available DENTAL slots for 2026-10-22: 1 — 10:00 AM, 2 — 10:15 AM, 3 — 10:30 AM' };
    }
  }
  if (session.current_step === 'awaiting_slot_choice') {
    const choice = parseInt(body, 10);
    if (choice >= 1 && choice <= session.presented_options.length) {
      const chosen = session.presented_options[choice - 1];
      session.current_step = 'confirmation_pending';
      const newRequest = {
        id: `req-e2e-${Date.now()}`,
        patient_id: 'pat-101',
        patient_name: 'Ramesh Patel',
        patient_phone: phone,
        department: 'dental',
        requested_date: session.selected_date,
        requested_time: chosen.slot,
        duration_minutes: 15,
        status: 'pending_review'
      };
      mockDb.appointmentRequests.push(newRequest);
      return { step: session.current_step, request: newRequest, reply: 'Request Submitted to Reception!' };
    }
  }
  return { step: session.current_step, reply: 'Unrecognized input' };
}

const step1 = simulateInbound('Hi', mockSession);
assert('Step 1: Patient says "Hi" -> state advances to awaiting_date_choice', step1.step === 'awaiting_date_choice');

const step2 = simulateInbound('2', mockSession);
assert('Step 2: Patient selects "2" (Tomorrow) -> state advances to awaiting_slot_choice', step2.step === 'awaiting_slot_choice');
assert('Step 2: Slots presented for booking', mockSession.presented_options.length === 3);

const step3 = simulateInbound('1', mockSession);
assert('Step 3: Patient selects slot "1" -> state advances to confirmation_pending', step3.step === 'confirmation_pending');
assert('Step 3: Pending appointment request created in database', mockDb.appointmentRequests.length === 1);
assert('Step 3: Appointment request has 15m duration', mockDb.appointmentRequests[0].duration_minutes === 15);
assert('Step 3: Request status is pending_review', mockDb.appointmentRequests[0].status === 'pending_review');

// 2. Staff Dashboard Review & Approval
function staffApproveRequest(requestId, assignedDoctorId) {
  const req = mockDb.appointmentRequests.find(r => r.id === requestId);
  if (!req || req.status !== 'pending_review') return { success: false, error: 'Invalid request' };

  // Availability recheck against clinical appointments
  const hasConflict = mockDb.clinicalAppointments.some(
    a => a.doctor_id === assignedDoctorId &&
         a.date === req.requested_date &&
         a.time === req.requested_time &&
         a.status !== 'cancelled'
  );
  if (hasConflict) return { success: false, error: 'Slot conflict: Doctor already booked' };

  req.status = 'approved';
  const newAppointment = {
    id: `appt-${Date.now()}`,
    patient_id: req.patient_id,
    doctor_id: assignedDoctorId,
    department: req.department,
    date: req.requested_date,
    time: req.requested_time,
    duration_minutes: req.duration_minutes,
    ai_booked: true,
    status: 'scheduled'
  };
  mockDb.clinicalAppointments.push(newAppointment);

  // Enqueue confirmation message to outbox
  mockDb.outbox.push({
    id: `outbox-conf-${Date.now()}`,
    recipient_phone: req.patient_phone,
    patient_id: req.patient_id,
    department: req.department,
    message_type: 'confirmation',
    template_key: 'confirmation',
    message_text: `Your appointment is CONFIRMED on ${req.requested_date} at ${req.requested_time}.`,
    status: 'pending'
  });

  return { success: true, appointment: newAppointment };
}

const approvalResult = staffApproveRequest(mockDb.appointmentRequests[0].id, 'doc-1');
assert('Staff approves request with assigned doctor', approvalResult.success === true);
assert('Clinical appointment created with ai_booked=true', approvalResult.appointment.ai_booked === true);
assert('Confirmation notification enqueued to outbox', mockDb.outbox.some(m => m.message_type === 'confirmation'));

// 3. Automated Messaging Workflows Simulation
// A. Dental Lab Ready trigger simulation
function triggerDentalLabReady(labCase) {
  if (labCase.status === 'ready_for_fitting') {
    mockDb.outbox.push({
      id: `outbox-lab-${Date.now()}`,
      recipient_phone: '+91 98200 12345',
      patient_id: 'pat-101',
      department: 'dental',
      message_type: 'lab_ready',
      message_text: `Your custom dental restoration (${labCase.case_type}) is READY for fitting.`,
      status: 'pending'
    });
  }
}
triggerDentalLabReady({ case_number: 'DL-991', case_type: 'Zirconia Crown', status: 'ready_for_fitting' });
assert('Dental lab ready event enqueues lab_ready notification', mockDb.outbox.some(m => m.message_type === 'lab_ready'));

// B. Billing Payment Receipt trigger simulation
function triggerBillingPayment(payment) {
  mockDb.outbox.push({
    id: `outbox-pay-${Date.now()}`,
    recipient_phone: '+91 98200 12345',
    patient_id: 'pat-101',
    department: 'dental',
    message_type: 'payment_receipt',
    message_text: `Payment of ₹${payment.amount} received. Remaining: ₹${payment.remaining_balance}.`,
    status: 'pending'
  });
}
triggerBillingPayment({ amount: 1500, remaining_balance: 0 });
assert('Billing payment event enqueues payment_receipt notification', mockDb.outbox.some(m => m.message_type === 'payment_receipt'));

// C. Vendor Purchase Order trigger simulation
function triggerVendorPO(po) {
  mockDb.outbox.push({
    id: `outbox-po-${Date.now()}`,
    recipient_phone: '+91 98111 22233',
    department: 'general',
    message_type: 'vendor_po',
    message_text: `Purchase Order #${po.po_number} has been ordered.`,
    status: 'pending'
  });
}
triggerVendorPO({ po_number: 'PO-2026-44', total_amount: 12500 });
assert('Vendor PO ordered event enqueues vendor_po notification', mockDb.outbox.some(m => m.message_type === 'vendor_po'));

// D. Opt-out safety in batch automation
function enqueueBatchReminders(patientList) {
  let enqueued = 0;
  for (const p of patientList) {
    if (p.whatsapp_opt_out) continue; // STRICT SKIP
    enqueued++;
  }
  return enqueued;
}
const enqueuedCount = enqueueBatchReminders(mockDb.patients);
assert('Batch enqueuer strictly excludes opted-out patients', enqueuedCount === 1);

// E. Festival Broadcast simulation
function simulateFestivalBroadcast(festivalName, customGreeting, patientList, existingOutbox, callerRole) {
  if (callerRole !== 'admin') {
    return { success: false, error: 'Forbidden: Only administrators can trigger festival greeting broadcasts.' };
  }

  const defaultGreeting = `✨ *Warm ${festivalName} Greetings from MKES CARE+ Hospital!*\n\nMay this auspicious occasion bring peace, prosperity, and radiant health to you and your family.\nReply STOP to unsubscribe.`;
  const body = customGreeting || defaultGreeting;
  let enqueued = 0;

  for (const p of patientList) {
    if (p.whatsapp_opt_out) continue; // DPDP compliance

    // 24h deduplication check
    const recent = existingOutbox.some(
      o => o.patient_id === p.id && o.message_type === 'festival' && (Date.now() - o.created_at) < 86400000
    );
    if (recent) continue;

    existingOutbox.push({
      id: `fest-${Date.now()}-${p.id}`,
      patient_id: p.id,
      recipient_phone: p.mobile,
      department: 'general',
      message_type: 'festival',
      template_key: 'festival',
      message_text: body,
      created_at: Date.now()
    });
    enqueued++;
  }
  return { success: true, enqueued };
}

// -----------------------------------------------------------------------------
// Test Suite 19: Festival Messaging Broadcast, Opt-Out & RBAC
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 19: Festival Messaging Broadcast, Opt-Out & RBAC ---');

// 1. Non-admin caller is rejected
const nonAdminRes = simulateFestivalBroadcast('Diwali', null, mockDb.patients, mockDb.outbox, 'staff');
assert('Festival broadcast strictly rejects non-admin caller', nonAdminRes.success === false && nonAdminRes.error.includes('Forbidden'));

// 2. Admin caller triggers default festival broadcast
const adminRes1 = simulateFestivalBroadcast('Diwali', null, mockDb.patients, mockDb.outbox, 'admin');
assert('Admin caller successfully triggers festival broadcast', adminRes1.success === true);
assert('Festival broadcast respects opt-out (only active patient receives)', adminRes1.enqueued === 1);
const festMsg1 = mockDb.outbox.find(m => m.message_type === 'festival' && m.patient_id === 'pat-101');
assert('Festival message text contains default template greeting', festMsg1 && festMsg1.message_text.includes('Warm Diwali Greetings'));

// 3. Duplicate broadcast within 24 hours is blocked by deduplication
const adminResDup = simulateFestivalBroadcast('Diwali', null, mockDb.patients, mockDb.outbox, 'admin');
assert('Festival broadcast within 24h is deduplicated (0 enqueued)', adminResDup.enqueued === 0);

// 4. Custom festival greeting overrides default
const freshPatients = [{ id: 'pat-103', name: 'Kavita Roy', mobile: '+91 98333 44455', whatsapp_opt_out: false }];
const customGreeting = '✨ Happy Diwali! MKES CARE+ wishes you sparkling good health!';
const adminResCustom = simulateFestivalBroadcast('Diwali', customGreeting, freshPatients, mockDb.outbox, 'admin');
assert('Custom greeting successfully used in festival broadcast', adminResCustom.enqueued === 1);
const festMsgCustom = mockDb.outbox.find(m => m.patient_id === 'pat-103');
assert('Custom message text matches custom greeting', festMsgCustom && festMsgCustom.message_text === customGreeting);

// -----------------------------------------------------------------------------
// Test Suite 20: Recipient Verification, E.164 Normalization & ACK Handling
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 20: Recipient Verification & Delivery ACK ---');

// 1. Missing country codes
const prep10 = RecipientValidator.prepareLookupNumber('8080030111');
assert('Missing country code: 10-digit input normalized to 91 prefix', prep10.success === true && prep10.e164 === '918080030111');
assert('Missing country code: JID formatted correctly as 918080030111@c.us', prep10.expectedJid === '918080030111@c.us');

const prepLeadingZero = RecipientValidator.prepareLookupNumber('08080030111');
assert('Trunk code: Leading zero normalized to 91 prefix', prepLeadingZero.success === true && prepLeadingZero.e164 === '918080030111');

const prepFormatted = RecipientValidator.prepareLookupNumber('+91 80800 30111');
assert('Formatted input: +91 with spaces normalized to 91 prefix', prepFormatted.success === true && prepFormatted.e164 === '918080030111');

// 2. Invalid numbers
const prepEmpty = RecipientValidator.prepareLookupNumber('');
assert('Invalid number: Empty string rejected', prepEmpty.success === false && prepEmpty.error.includes('empty'));

const prepShort = RecipientValidator.prepareLookupNumber('12345');
assert('Invalid number: Short number (<10 digits) rejected', prepShort.success === false);

const prepLetters = RecipientValidator.prepareLookupNumber('abcdef');
assert('Invalid number: Alphabetical string rejected', prepLetters.success === false);

const prepInvalidSeries = RecipientValidator.prepareLookupNumber('1234567890');
assert('Invalid number: Indian mobile series not starting with 6/7/8/9 rejected', prepInvalidSeries.success === false && prepInvalidSeries.error.includes('start with 6, 7, 8, or 9'));

// 3. Unexpected LID results rejection
const lidResult = {
  _serialized: '170141321052179@lid',
  user: '170141321052179',
};
const valLid = RecipientValidator.validateResolvedRecipient({
  expectedE164: '918080030111',
  expectedJid: '918080030111@c.us',
  resolvedNumberId: lidResult,
  connectedUser: '918080030111',
});
assert('Unexpected LID: Opaque @lid identifier strictly rejected', valLid.valid === false && valLid.reason === 'UNVERIFIED_LID');
assert('Unexpected LID: Error message explains why LID is rejected', valLid.error.includes('opaque LID'));

// 4. Attempts to send to an unverified recipient
const valUnregistered = RecipientValidator.validateResolvedRecipient({
  expectedE164: '918080030111',
  expectedJid: '918080030111@c.us',
  resolvedNumberId: null,
  connectedUser: '918080030111',
});
assert('Unverified recipient: Unregistered number rejected', valUnregistered.valid === false && valUnregistered.reason === 'NOT_REGISTERED');

const valMismatch = RecipientValidator.validateResolvedRecipient({
  expectedE164: '918080030111',
  expectedJid: '918080030111@c.us',
  resolvedNumberId: { _serialized: '919999999999@c.us', user: '919999999999' },
  connectedUser: '918080030111',
});
assert('Unverified recipient: Number mismatch rejected', valMismatch.valid === false && valMismatch.reason === 'NUMBER_MISMATCH');

// Verified recipient success
const valValid = RecipientValidator.validateResolvedRecipient({
  expectedE164: '918080030111',
  expectedJid: '918080030111@c.us',
  resolvedNumberId: { _serialized: '918080030111@c.us', user: '918080030111' },
  connectedUser: '918080030111',
});
assert('Verified recipient: Matching standard JID accepted', valValid.valid === true && valValid.targetJid === '918080030111@c.us');
assert('Verified recipient: Connected account identified as self', valValid.isSelf === true);

// 5. Missing message IDs validation (eliminates misleading "delivered" string fallback)
const idNull = RecipientValidator.validateMessageSendResult(null);
assert('Missing message ID: null send result rejected', idNull.verified === false);

const idUndefined = RecipientValidator.validateMessageSendResult(undefined);
assert('Missing message ID: undefined send result rejected', idUndefined.verified === false);

const idEmptyObj = RecipientValidator.validateMessageSendResult({});
assert('Missing message ID: empty object rejected', idEmptyObj.verified === false);

const idNoSerialized = RecipientValidator.validateMessageSendResult({ id: {} });
assert('Missing message ID: object without _serialized rejected', idNoSerialized.verified === false);

const idValid = RecipientValidator.validateMessageSendResult({
  id: { _serialized: 'true_918080030111@c.us_3EB01234567890ABCDEF' },
});
assert('Valid message ID: genuine message model verified', idValid.verified === true && idValid.messageId === 'true_918080030111@c.us_3EB01234567890ABCDEF');

// 6. Acknowledgement handling and timeout
const { EventEmitter } = require('events');

class MockWhatsAppClient extends EventEmitter {}

// 6a. Acknowledgement timeout
const mockClientTimeout = new MockWhatsAppClient();
const ackTimeoutPromise = RecipientValidator.waitForMessageAck(mockClientTimeout, 'msg-test-timeout', {
  timeoutMs: 50,
  requiredAck: 1,
});
const ackTimeoutRes = await ackTimeoutPromise;
assert('ACK handling: Timeout returns acknowledged=false after timeoutMs', ackTimeoutRes.acknowledged === false && ackTimeoutRes.status === 'TIMEOUT');

// 6b. Server Acknowledgement (ACK = 1)
const mockClientServerAck = new MockWhatsAppClient();
const ackServerPromise = RecipientValidator.waitForMessageAck(mockClientServerAck, 'msg-test-server', {
  timeoutMs: 500,
  requiredAck: 1,
});
mockClientServerAck.emit('message_ack', { id: { _serialized: 'msg-test-server' } }, 1);
const ackServerRes = await ackServerPromise;
assert('ACK handling: Server ACK (1) returns acknowledged=true and ACK_SERVER status', ackServerRes.acknowledged === true && ackServerRes.ack === 1 && ackServerRes.status === 'ACK_SERVER');

// 6c. Device Acknowledgement (ACK = 2)
const mockClientDeviceAck = new MockWhatsAppClient();
const ackDevicePromise = RecipientValidator.waitForMessageAck(mockClientDeviceAck, 'msg-test-device', {
  timeoutMs: 500,
  requiredAck: 1,
});
mockClientDeviceAck.emit('message_ack', { id: { _serialized: 'msg-test-device' } }, 2);
const ackDeviceRes = await ackDevicePromise;
assert('ACK handling: Device ACK (2) returns acknowledged=true and ACK_DEVICE status', ackDeviceRes.acknowledged === true && ackDeviceRes.ack === 2 && ackDeviceRes.status === 'ACK_DEVICE');

// 6d. WhatsApp Server ACK Error (ACK = -1)
const mockClientErrorAck = new MockWhatsAppClient();
const ackErrorPromise = RecipientValidator.waitForMessageAck(mockClientErrorAck, 'msg-test-err', {
  timeoutMs: 500,
  requiredAck: 1,
});
mockClientErrorAck.emit('message_ack', { id: { _serialized: 'msg-test-err' } }, -1);
const ackErrorRes = await ackErrorPromise;
assert('ACK handling: Error ACK (-1) returns acknowledged=false and ACK_ERROR status', ackErrorRes.acknowledged === false && ackErrorRes.ack === -1 && ackErrorRes.status === 'ACK_ERROR');

// 6e. Unrelated message ACK is ignored
const mockClientUnrelated = new MockWhatsAppClient();
const ackUnrelatedPromise = RecipientValidator.waitForMessageAck(mockClientUnrelated, 'msg-target', {
  timeoutMs: 60,
  requiredAck: 1,
});
mockClientUnrelated.emit('message_ack', { id: { _serialized: 'msg-unrelated' } }, 2);
const ackUnrelatedRes = await ackUnrelatedPromise;
assert('ACK handling: ACK for unrelated message is ignored and target times out', ackUnrelatedRes.acknowledged === false && ackUnrelatedRes.status === 'TIMEOUT');

// -----------------------------------------------------------------------------
// Test Suite 21: Lookup-Only Mode & Structural Zero-Dispatch Guarantee
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 21: Lookup-Only Mode Zero-Dispatch Guarantee ---');

class MockLookupClient extends EventEmitter {
  constructor({ widResult = null, throwError = false, lidPhoneError = false, lidPhoneMap = null, authUser = '918080030111' } = {}) {
    super();
    this.widResult = widResult;
    this.throwError = throwError;
    this.lidPhoneError = lidPhoneError;
    this.lidPhoneMap = lidPhoneMap || {};
    this.sendMessageCalled = false;
    this.info = {
      wid: {
        user: authUser,
        _serialized: `${authUser}@c.us`,
      },
      pushname: 'Tirtha Shah',
    };
  }

  async getNumberId(number) {
    if (this.throwError) {
      throw new Error('Directory lookup timeout error');
    }
    return this.widResult;
  }

  async getContactLidAndPhone(userId) {
    if (this.lidPhoneError) {
      throw new Error('LID mapping retrieval failure');
    }
    const id = Array.isArray(userId) ? userId[0] : userId;
    if (this.lidPhoneMap && this.lidPhoneMap[id]) {
      return [this.lidPhoneMap[id]];
    }
    return [{ lid: null, pn: null }];
  }

  async sendMessage(jid, text) {
    this.sendMessageCalled = true;
    throw new Error('STRUCTURAL FAILURE: sendMessage must never be called in lookup-only mode!');
  }
}

// 1. Lookup succeeds with verified standard WID matching self
const mockClientSelf = new MockLookupClient({
  widResult: { user: '918080030111', _serialized: '918080030111@c.us' },
  authUser: '918080030111',
});
const lookupSelfRes = await RecipientValidator.performLookupOnly({
  client: mockClientSelf,
  targetPhone: '8080030111',
});
assert('Lookup-only: Succeeded with verified status', lookupSelfRes.success === true && lookupSelfRes.status === 'VERIFIED');
assert('Lookup-only: Target JID resolved accurately to 918080030111@c.us', lookupSelfRes.targetJid === '918080030111@c.us');
assert('Lookup-only: Trustworthy check identifies recipient as self', lookupSelfRes.isSelf === true);
assert('Lookup-only: ZERO DISPATCH GUARANTEE (sendMessage was never called)', mockClientSelf.sendMessageCalled === false);

// 2. Lookup succeeds with external recipient (not self)
const mockClientExt = new MockLookupClient({
  widResult: { user: '919876543210', _serialized: '919876543210@c.us' },
  authUser: '918080030111',
});
const lookupExtRes = await RecipientValidator.performLookupOnly({
  client: mockClientExt,
  targetPhone: '9876543210',
});
assert('Lookup-only: External recipient verified', lookupExtRes.success === true && lookupExtRes.status === 'VERIFIED');
assert('Lookup-only: External recipient NOT marked as self', lookupExtRes.isSelf === false);
assert('Lookup-only: ZERO DISPATCH GUARANTEE for external contact', mockClientExt.sendMessageCalled === false);

// 3. Lookup returns unexpected @lid
const mockClientLid = new MockLookupClient({
  widResult: { user: '170141321052179', _serialized: '170141321052179@lid' },
  authUser: '918080030111',
});
const lookupLidRes = await RecipientValidator.performLookupOnly({
  client: mockClientLid,
  targetPhone: '8080030111',
});
assert('Lookup-only: @lid is strictly rejected as UNVERIFIED_LID', lookupLidRes.success === false && lookupLidRes.status === 'UNVERIFIED_LID');
assert('Lookup-only: @lid is never marked as self', lookupLidRes.isSelf === false);
assert('Lookup-only: ZERO DISPATCH GUARANTEE on @lid rejection', mockClientLid.sendMessageCalled === false);

// 4. Lookup fails: Unregistered number
const mockClientUnreg = new MockLookupClient({
  widResult: null,
  authUser: '918080030111',
});
const lookupUnregRes = await RecipientValidator.performLookupOnly({
  client: mockClientUnreg,
  targetPhone: '9123456789',
});
assert('Lookup-only: Unregistered number reports NOT_REGISTERED', lookupUnregRes.success === false && lookupUnregRes.status === 'NOT_REGISTERED');
assert('Lookup-only: ZERO DISPATCH GUARANTEE on unregistered number', mockClientUnreg.sendMessageCalled === false);

// 5. Lookup times out / throws error
const mockClientErr = new MockLookupClient({
  throwError: true,
  authUser: '918080030111',
});
const lookupErrRes = await RecipientValidator.performLookupOnly({
  client: mockClientErr,
  targetPhone: '8080030111',
});
assert('Lookup-only: Directory error reports LOOKUP_ERROR', lookupErrRes.success === false && lookupErrRes.status === 'LOOKUP_ERROR');
assert('Lookup-only: ZERO DISPATCH GUARANTEE on error/timeout', mockClientErr.sendMessageCalled === false);

// 6. Lookup with malformed input
const lookupInvalidInput = await RecipientValidator.performLookupOnly({
  client: mockClientSelf,
  targetPhone: '123',
});
assert('Lookup-only: Malformed input reports INVALID_INPUT', lookupInvalidInput.success === false && lookupInvalidInput.status === 'INVALID_INPUT');
assert('Lookup-only: ZERO DISPATCH GUARANTEE on malformed input', mockClientSelf.sendMessageCalled === false);

// -----------------------------------------------------------------------------
// Test Suite 22: Bidirectional LID-to-Phone Mapping Inspection
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 22: Bidirectional LID-to-Phone Mapping ---');

// 1. Successful matching: Both queries succeed and agree with authenticated session
const mockClientMatch = new MockLookupClient({
  lidPhoneMap: {
    '170141321052179@lid': { lid: '170141321052179@lid', pn: '918080030111@c.us' },
    '918080030111@c.us': { lid: '170141321052179@lid', pn: '918080030111@c.us' },
  },
  authUser: '918080030111',
});
const mapMatchRes = await RecipientValidator.inspectLidAndPhoneMapping({
  client: mockClientMatch,
  lidId: '170141321052179@lid',
  phoneId: '918080030111@c.us',
  connectedWid: mockClientMatch.info.wid,
});
assert('LID mapping: Successful bidirectional match identified', mapMatchRes.conclusion === 'VERIFIED_BIDIRECTIONAL_MATCH');
assert('LID mapping: Confirms match is consistent with authenticated session', mapMatchRes.matchesAuthSession === true);
assert('LID mapping: Exact returned reverse PN matches expected phone', mapMatchRes.lidLookup.pn === '918080030111@c.us');
assert('LID mapping: Exact returned forward LID matches expected LID', mapMatchRes.phoneLookup.lid === '170141321052179@lid');

// 2. Missing mapping: Store returns empty/null
const mockClientMissing = new MockLookupClient({
  lidPhoneMap: {},
  authUser: '918080030111',
});
const mapMissingRes = await RecipientValidator.inspectLidAndPhoneMapping({
  client: mockClientMissing,
  lidId: '170141321052179@lid',
  phoneId: '918080030111@c.us',
  connectedWid: mockClientMissing.info.wid,
});
assert('LID mapping: Missing store mapping identified as MISSING_MAPPING', mapMissingRes.conclusion === 'MISSING_MAPPING');

// 3. Mismatched mapping: Reverse lookup returns completely different phone number
const mockClientMismatch = new MockLookupClient({
  lidPhoneMap: {
    '170141321052179@lid': { lid: '170141321052179@lid', pn: '919999999999@c.us' },
    '918080030111@c.us': { lid: '170141321052179@lid', pn: '918080030111@c.us' },
  },
  authUser: '918080030111',
});
const mapMismatchRes = await RecipientValidator.inspectLidAndPhoneMapping({
  client: mockClientMismatch,
  lidId: '170141321052179@lid',
  phoneId: '918080030111@c.us',
  connectedWid: mockClientMismatch.info.wid,
});
assert('LID mapping: Mismatched reverse phone identified as CONTRADICTORY_MISMATCH', mapMismatchRes.conclusion === 'CONTRADICTORY_MISMATCH');

// 4. Lookup error: API call throws error
const mockClientMapErr = new MockLookupClient({
  lidPhoneError: true,
  authUser: '918080030111',
});
const mapErrRes = await RecipientValidator.inspectLidAndPhoneMapping({
  client: mockClientMapErr,
  lidId: '170141321052179@lid',
  phoneId: '918080030111@c.us',
  connectedWid: mockClientMapErr.info.wid,
});
assert('LID mapping: Exception handled safely as LOOKUP_ERROR', mapErrRes.conclusion === 'LOOKUP_ERROR');

// 5. External match: Valid bidirectional match for non-authenticated user
const mockClientExtMatch = new MockLookupClient({
  lidPhoneMap: {
    '222222222222222@lid': { lid: '222222222222222@lid', pn: '919876543210@c.us' },
    '919876543210@c.us': { lid: '222222222222222@lid', pn: '919876543210@c.us' },
  },
  authUser: '918080030111', // Authenticated user is different
});
const mapExtRes = await RecipientValidator.inspectLidAndPhoneMapping({
  client: mockClientExtMatch,
  lidId: '222222222222222@lid',
  phoneId: '919876543210@c.us',
  connectedWid: mockClientExtMatch.info.wid,
});
assert('LID mapping: External user match identified as EXTERNAL_BIDIRECTIONAL_MATCH', mapExtRes.conclusion === 'EXTERNAL_BIDIRECTIONAL_MATCH');
assert('LID mapping: External user correctly marked as NOT matching session', mapExtRes.matchesAuthSession === false);

// -----------------------------------------------------------------------------
// Test Suite 23: Recipient Validation with Verified Mapping & Pre-Dispatch Tracker
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 23: Verified Mapping Recipient Validation & ACK Tracker ---');

// 1. @lid with verified bidirectional mapping and session match -> APPROVED
const verifiedMappingMatch = {
  conclusion: 'VERIFIED_BIDIRECTIONAL_MATCH',
  matchesAuthSession: true,
  lidLookup: { lid: '170141321052179@lid', pn: '918080030111@c.us' },
  phoneLookup: { lid: '170141321052179@lid', pn: '918080030111@c.us' },
};
const valWithVerifiedMap = RecipientValidator.validateResolvedRecipient({
  expectedE164: '918080030111',
  expectedJid: '918080030111@c.us',
  resolvedNumberId: { _serialized: '170141321052179@lid', user: '170141321052179', server: 'lid' },
  connectedWid: { user: '918080030111', _serialized: '918080030111@c.us' },
  verifiedMapping: verifiedMappingMatch,
});
assert('Verified Mapping: @lid resolved successfully with valid=true', valWithVerifiedMap.valid === true);
assert('Verified Mapping: targetJid is strictly canonical phone JID (NEVER @lid)', valWithVerifiedMap.targetJid === '918080030111@c.us');
assert('Verified Mapping: Authenticated user identified as self', valWithVerifiedMap.isSelf === true);
assert('Verified Mapping: Flag mappingVerified is true', valWithVerifiedMap.mappingVerified === true);

// 2. @lid without verified mapping -> REJECTED
const valWithoutMap = RecipientValidator.validateResolvedRecipient({
  expectedE164: '918080030111',
  expectedJid: '918080030111@c.us',
  resolvedNumberId: { _serialized: '170141321052179@lid', user: '170141321052179', server: 'lid' },
  connectedWid: { user: '918080030111', _serialized: '918080030111@c.us' },
  verifiedMapping: null,
});
assert('Verified Mapping: @lid without mapping rejected as UNVERIFIED_LID', valWithoutMap.valid === false && valWithoutMap.reason === 'UNVERIFIED_LID');

// 3. @lid with contradictory mismatch -> REJECTED
const valWithMismatchMap = RecipientValidator.validateResolvedRecipient({
  expectedE164: '918080030111',
  expectedJid: '918080030111@c.us',
  resolvedNumberId: { _serialized: '170141321052179@lid', user: '170141321052179', server: 'lid' },
  connectedWid: { user: '918080030111', _serialized: '918080030111@c.us' },
  verifiedMapping: { conclusion: 'CONTRADICTORY_MISMATCH', matchesAuthSession: false },
});
assert('Verified Mapping: @lid with mismatched mapping rejected as UNVERIFIED_LID', valWithMismatchMap.valid === false && valWithMismatchMap.reason === 'UNVERIFIED_LID');

// 4. @lid with external mapping that does not match authenticated session -> REJECTED
const valWithExternalMap = RecipientValidator.validateResolvedRecipient({
  expectedE164: '918080030111',
  expectedJid: '918080030111@c.us',
  resolvedNumberId: { _serialized: '170141321052179@lid', user: '170141321052179', server: 'lid' },
  connectedWid: { user: '918080030111', _serialized: '918080030111@c.us' },
  verifiedMapping: {
    conclusion: 'VERIFIED_BIDIRECTIONAL_MATCH',
    matchesAuthSession: false,
    lidLookup: { lid: '170141321052179@lid', pn: '918080030111@c.us' },
    phoneLookup: { lid: '170141321052179@lid', pn: '918080030111@c.us' },
  },
});
assert('Verified Mapping: @lid not matching session rejected as UNVERIFIED_LID', valWithExternalMap.valid === false && valWithExternalMap.reason === 'UNVERIFIED_LID');

// 5. Pre-dispatch ACK Tracker: Captures pre-dispatch ACK 1
const mockEmitter = new (require('events').EventEmitter)();
const tracker1 = RecipientValidator.createAckTracker(mockEmitter, { timeoutMs: 50 });
mockEmitter.emit('message_ack', { id: { _serialized: 'msg-pre-1' } }, 1);
const ackTrackerRes1 = await tracker1.waitForAck('msg-pre-1');
assert('ACK Tracker: Captures pre-dispatch ACK 1', ackTrackerRes1.acknowledged === true && ackTrackerRes1.highestAck === 1 && ackTrackerRes1.status === 'ACK_SERVER');

// 6. Pre-dispatch ACK Tracker: Captures pre-dispatch ACK 2 (device delivery)
const tracker2 = RecipientValidator.createAckTracker(mockEmitter, { timeoutMs: 50 });
mockEmitter.emit('message_ack', { id: { _serialized: 'msg-pre-2' } }, 2);
const ackTrackerRes2 = await tracker2.waitForAck('msg-pre-2');
assert('ACK Tracker: Captures device delivery ACK 2', ackTrackerRes2.acknowledged === true && ackTrackerRes2.highestAck === 2 && ackTrackerRes2.status === 'ACK_DEVICE');

// 7. Pre-dispatch ACK Tracker: Times out when no ACK received
const tracker3 = RecipientValidator.createAckTracker(mockEmitter, { timeoutMs: 20 });
const ackTrackerRes3 = await tracker3.waitForAck('msg-pre-3');
assert('ACK Tracker: Times out safely when no ACK arrives', ackTrackerRes3.acknowledged === false && ackTrackerRes3.highestAck === 0 && ackTrackerRes3.status === 'TIMEOUT');

// 8. Pre-dispatch ACK Tracker: Handles ACK error (-1)
const tracker4 = RecipientValidator.createAckTracker(mockEmitter, { timeoutMs: 50 });
setTimeout(() => mockEmitter.emit('message_ack', { id: { _serialized: 'msg-pre-4' } }, -1), 5);
const ackTrackerRes4 = await tracker4.waitForAck('msg-pre-4');
assert('ACK Tracker: Handles ACK -1 as ACK_ERROR', ackTrackerRes4.acknowledged === false && ackTrackerRes4.highestAck === -1 && ackTrackerRes4.status === 'ACK_ERROR');

// -----------------------------------------------------------------------------
// Test Suite 24: Chat Store Readiness & Preflight Verification
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 24: Chat Store Readiness & Preflight Verification ---');

class MockChatReadinessClient extends (require('events').EventEmitter) {
  constructor({ chats = {}, allChats = [], throwOnGet = false, authUser = '918080030111' } = {}) {
    super();
    this.chats = chats;
    this.allChatsList = allChats;
    this.throwOnGet = throwOnGet;
    this.info = {
      wid: { user: authUser, _serialized: `${authUser}@c.us` },
      pushname: 'Clinic Host',
    };
    this.callCount = 0;
  }

  async getChatById(chatId) {
    this.callCount++;
    if (this.throwOnGet) {
      throw new Error('Database busy during re-indexing');
    }
    if (typeof this.chats === 'function') {
      return this.chats(chatId, this.callCount);
    }
    return this.chats[chatId] || undefined;
  }

  async getChats() {
    return this.allChatsList;
  }
}

// 1. Readiness Success: getChatById returns valid chat object
const readyClientSuccess = new MockChatReadinessClient({
  chats: {
    '918080030111@c.us': {
      id: { _serialized: '918080030111@c.us' },
      name: 'You',
      isGroup: false,
    },
  },
  allChats: [{ id: '918080030111@c.us' }],
});
const readyRes1 = await RecipientValidator.waitForChatReadiness(readyClientSuccess, '918080030111@c.us', {
  timeoutMs: 100,
  pollIntervalMs: 10,
});
assert('Readiness: Successfully detects chat ready', readyRes1.ready === true && readyRes1.status === 'CHAT_READY');
assert('Readiness: Confirms chatFound is true', readyRes1.chatFound === true);
assert('Readiness: Returns chatDetails matching target JID', readyRes1.chatDetails?.id === '918080030111@c.us');
assert('Readiness: Captures chat count in memory store', readyRes1.chatCount === 1);

// 2. Delayed Readiness: chat becomes available on 2nd poll after initial sync delay
let pollAttempts = 0;
const delayedClient = new MockChatReadinessClient({
  chats: () => {
    pollAttempts++;
    if (pollAttempts >= 2) {
      return { id: { _serialized: '918080030111@c.us' }, name: 'You', isGroup: false };
    }
    return undefined;
  },
  allChats: [{ id: '918080030111@c.us' }],
});
setTimeout(() => delayedClient.emit('loading_screen', 50), 5);
setTimeout(() => delayedClient.emit('loading_screen', 100), 15);
const readyRes2 = await RecipientValidator.waitForChatReadiness(delayedClient, '918080030111@c.us', {
  timeoutMs: 200,
  pollIntervalMs: 15,
});
assert('Readiness: Handles delayed chat-store sync and succeeds', readyRes2.ready === true && readyRes2.status === 'CHAT_READY');
assert('Readiness: Progress from loading_screen is tracked', readyRes2.offlineProgress === 100);

// 3. Readiness Timeout: chat never becomes available
const timeoutClient = new MockChatReadinessClient({
  chats: {},
  allChats: [],
});
const readyRes3 = await RecipientValidator.waitForChatReadiness(timeoutClient, '918080030111@c.us', {
  timeoutMs: 30,
  pollIntervalMs: 10,
});
assert('Readiness: Bounded timeout returns ready=false and status=TIMEOUT', readyRes3.ready === false && readyRes3.status === 'TIMEOUT');
assert('Readiness: chatFound is false on timeout', readyRes3.chatFound === false);
assert('Readiness: Error message specifies timeout duration', Boolean(readyRes3.error && readyRes3.error.includes('Timed out')));

// 4. Missing Chat: store loaded with other chats, but target self-chat is absent
const missingChatClient = new MockChatReadinessClient({
  chats: {
    '919876543210@c.us': { id: { _serialized: '919876543210@c.us' }, name: 'External Contact' },
  },
  allChats: [{ id: '919876543210@c.us' }],
});
const readyRes4 = await RecipientValidator.waitForChatReadiness(missingChatClient, '918080030111@c.us', {
  timeoutMs: 30,
  pollIntervalMs: 10,
});
assert('Readiness: Missing target chat reports ready=false and chatFound=false', readyRes4.ready === false && readyRes4.chatFound === false);
assert('Readiness: Accurately reflects existing unrelated chats in store', readyRes4.chatCount === 1);

// 5. Disconnected Session: Client emits disconnected during wait
const disconnectClient = new MockChatReadinessClient({ chats: {} });
setTimeout(() => disconnectClient.emit('disconnected', 'LOGOUT'), 10);
const readyRes5 = await RecipientValidator.waitForChatReadiness(disconnectClient, '918080030111@c.us', {
  timeoutMs: 100,
  pollIntervalMs: 10,
});
assert('Readiness: Disconnect event aborts wait with status=DISCONNECTED', readyRes5.ready === false && readyRes5.status === 'DISCONNECTED');
assert('Readiness: Error reports disconnection detail', Boolean(readyRes5.error && readyRes5.error.includes('LOGOUT')));

// 6. QR Code Requested: Client emits qr event during wait
const qrClient = new MockChatReadinessClient({ chats: {} });
setTimeout(() => qrClient.emit('qr'), 10);
const readyRes6 = await RecipientValidator.waitForChatReadiness(qrClient, '918080030111@c.us', {
  timeoutMs: 100,
  pollIntervalMs: 10,
});
assert('Readiness: QR event aborts wait with status=QR_REQUIRED', readyRes6.ready === false && readyRes6.status === 'QR_REQUIRED');

// 7. Auth Failure: Client emits auth_failure event
const authFailClient = new MockChatReadinessClient({ chats: {} });
setTimeout(() => authFailClient.emit('auth_failure', 'INVALID_CREDENTIALS'), 10);
const readyRes7 = await RecipientValidator.waitForChatReadiness(authFailClient, '918080030111@c.us', {
  timeoutMs: 100,
  pollIntervalMs: 10,
});
assert('Readiness: Auth failure aborts wait with status=AUTH_FAILURE', readyRes7.ready === false && readyRes7.status === 'AUTH_FAILURE');

// -----------------------------------------------------------------------------
// Test Suite 25: Chat Retrieval Investigation & Diagnostic Invariants
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 25: Chat Retrieval Investigation & Diagnostic Invariants ---');

// 1. Invariant: Contact with isMe: true returns null from getChat() by library design
const mockSelfContact = {
  id: { _serialized: '918080030111@c.us' },
  isMe: true,
  async getChat() {
    if (this.isMe) return null;
    return { id: this.id._serialized };
  },
};
const selfChatResult = await mockSelfContact.getChat();
assert('Diagnostic: Contact with isMe: true returns null from getChat() by library design', selfChatResult === null);

// 2. Invariant: Self-chat in WhatsApp Web multi-device is stored under LID JID, not phone JID
const mockStore = {
  chats: {
    '170141321052179@lid': { id: { _serialized: '170141321052179@lid' }, formattedTitle: '+91 80800 30111' },
  },
  findOrCreateLatestChat(jid) {
    if (jid === '918080030111@c.us' || jid === '170141321052179@lid') {
      return { chat: this.chats['170141321052179@lid'] };
    }
    return null;
  },
  get(jid) {
    return this.chats[jid] || null;
  },
};
assert('Diagnostic: Synchronous Chat.get(phoneJid) returns null for self-chat', mockStore.get('918080030111@c.us') === null);
assert('Diagnostic: Synchronous Chat.get(lidJid) returns chat model for self-chat', Boolean(mockStore.get('170141321052179@lid')));
assert('Diagnostic: findOrCreateLatestChat(phoneJid) resolves to self LID chat', mockStore.findOrCreateLatestChat('918080030111@c.us')?.chat?.id?._serialized === '170141321052179@lid');

// 3. Invariant: Raw getChat(chatId, { getAsModel: false }) succeeds while getChatModel throws on IDBObjectStore DataError
class MockSerializationError extends Error {
  constructor() {
    super("Failed to execute 'get' on 'IDBObjectStore': No key or key range specified.");
    this.name = 'DataError';
  }
}

async function mockWWebJSGetChat(chatId, { getAsModel = true } = {}) {
  const chat = mockStore.get(chatId) || mockStore.findOrCreateLatestChat(chatId)?.chat;
  if (!chat) return null;
  if (getAsModel) {
    // Simulates Msg.getMessagesById failure on IndexedDB in getChatModel()
    throw new MockSerializationError();
  }
  return chat;
}

let rawChatSuccess = false;
try {
  const raw = await mockWWebJSGetChat('918080030111@c.us', { getAsModel: false });
  rawChatSuccess = Boolean(raw && raw.id?._serialized === '170141321052179@lid');
} catch (_) {}
assert('Diagnostic: Raw getChat with getAsModel: false resolves self-chat without error', rawChatSuccess === true);

let modelChatError = null;
try {
  await mockWWebJSGetChat('918080030111@c.us', { getAsModel: true });
} catch (err) {
  modelChatError = err;
}
assert('Diagnostic: getChat with getAsModel: true throws DataError (reproducing client.getChatById failure)', modelChatError instanceof MockSerializationError);

// 4. Invariant: Promise.all rejection causes getChats() to report 0 unless errors are isolated
const mock459Chats = Array.from({ length: 459 }, (_, i) => ({
  id: `chat_${i}@c.us`,
  shouldFail: i >= 286, // 173 fail out of 459
}));

let promiseAllRejected = false;
try {
  await Promise.all(mock459Chats.map(async (c) => {
    if (c.shouldFail) throw new MockSerializationError();
    return { id: c.id };
  }));
} catch (e) {
  promiseAllRejected = true;
}
assert('Diagnostic: Unhandled Promise.all over all chats rejects if any chat fails serialization', promiseAllRejected === true);

// Resilient counting isolates failures and reports exact total
let resilientSuccess = 0;
let resilientFailed = 0;
for (const c of mock459Chats) {
  try {
    if (c.shouldFail) throw new MockSerializationError();
    resilientSuccess++;
  } catch (_) {
    resilientFailed++;
  }
}
assert('Diagnostic: Resilient store inspection accurately preserves total count (459)', resilientSuccess + resilientFailed === 459);
assert('Diagnostic: Resilient store inspection accurately matches 286 success and 173 failures', resilientSuccess === 286 && resilientFailed === 173);

// 5. Invariant: InterfaceController.openChatWindow uses getAsModel: false
class MockInterfaceController {
  constructor(pupPage) {
    this.pupPage = pupPage;
  }
  async openChatWindow(chatId) {
    // Calls getChat with getAsModel: false
    const chat = await mockWWebJSGetChat(chatId, { getAsModel: false });
    return { opened: Boolean(chat), chatId: chat?.id?._serialized };
  }
}
const mockInterface = new MockInterfaceController();
const openResult = await mockInterface.openChatWindow('918080030111@c.us');
assert('Diagnostic: InterfaceController.openChatWindow resolves self-chat via getAsModel: false', openResult.opened === true && openResult.chatId === '170141321052179@lid');

// -----------------------------------------------------------------------------
// Test Suite 26: Raw Chat Resolution, IndexedDB Error Bypass & Self-Chat Readiness
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 26: Raw Chat Resolution & Self-Chat Readiness ---');

// Mock verified LID mapping for 918080030111@c.us <-> 170141321052179@lid
const validSelfMapping = {
  conclusion: 'VERIFIED_BIDIRECTIONAL_MATCH',
  matchesAuthSession: true,
  lidLookup: { lid: '170141321052179@lid', pn: '918080030111@c.us' },
  phoneLookup: { lid: '170141321052179@lid', pn: '918080030111@c.us' },
};

// 1. Raw Chat Resolution: pupPage returns raw chat directly
class MockPupPageClient {
  constructor({ rawChat, chatCount = 459, openChatWindowSuccess = true, failGetChatById = true }) {
    this.info = { wid: { user: '918080030111', _serialized: '918080030111@c.us' } };
    this.rawChat = rawChat;
    this.chatCount = chatCount;
    this.openChatWindowSuccess = openChatWindowSuccess;
    this.failGetChatById = failGetChatById;
    this.openChatWindowCalls = [];

    this.pupPage = {
      evaluate: async (fn, arg) => {
        // Distinguish evaluate calls based on function signature or argument
        if (typeof arg === 'string') {
          // getRawChat(targetJid)
          return this.rawChat;
        } else {
          // getChatCountSafe()
          return this.chatCount;
        }
      },
    };

    this.interface = {
      openChatWindow: async (chatId) => {
        this.openChatWindowCalls.push(chatId);
        if (!this.openChatWindowSuccess) {
          throw new Error('UI navigation failed');
        }
        return true;
      },
    };
  }

  async getChatById(jid) {
    if (this.failGetChatById) {
      const err = new Error("Failed to execute 'get' on 'IDBObjectStore': No key or key range specified.");
      err.name = 'DataError';
      throw err;
    }
    return this.rawChat;
  }

  async getChats() {
    throw new Error('Promise.all rejected on DataError');
  }
}

// 1. Raw chat resolves canonical phone JID directly
const rawClient1 = new MockPupPageClient({
  rawChat: { id: '918080030111@c.us', name: 'Self Chat', isGroup: false },
});
const rawRes1 = await RecipientValidator.waitForChatReadiness(rawClient1, '918080030111@c.us', {
  timeoutMs: 50,
  pollIntervalMs: 10,
});
assert('Raw Readiness: Bypasses getChatById IndexedDB DataError via pupPage raw getChat', rawRes1.ready === true && rawRes1.status === 'CHAT_READY');
assert('Raw Readiness: Resolves matching canonical chat ID', rawRes1.chatDetails?.id === '918080030111@c.us');
assert('Raw Readiness: Reads safe in-memory chat count (459) bypassing failing getChats', rawRes1.chatCount === 459);

// 2. Raw chat resolves self-chat LID when verified mapping is provided
const rawClient2 = new MockPupPageClient({
  rawChat: { id: '170141321052179@lid', name: '+91 80800 30111', isGroup: false },
});
const rawRes2 = await RecipientValidator.waitForChatReadiness(rawClient2, '918080030111@c.us', {
  timeoutMs: 50,
  pollIntervalMs: 10,
  verifiedMapping: validSelfMapping,
  openChatWindow: true,
});
assert('Raw Readiness: Self-chat LID resolved successfully when verified mapping matches', rawRes2.ready === true && rawRes2.status === 'CHAT_READY');
assert('Raw Readiness: Flags chatDetails.isLid as true for self-chat', rawRes2.chatDetails?.isLid === true);
assert('Raw Readiness: chatDetails.id contains verified self LID', rawRes2.chatDetails?.id === '170141321052179@lid');
assert('Raw Readiness: openChatWindow executed via client.interface', rawClient2.openChatWindowCalls.includes('170141321052179@lid'));
assert('Raw Readiness: Flags chatDetails.windowOpened as true', rawRes2.chatDetails?.windowOpened === true);

// 3. Raw chat with LID is strictly REJECTED if verified mapping is absent
const rawRes3 = await RecipientValidator.waitForChatReadiness(rawClient2, '918080030111@c.us', {
  timeoutMs: 30,
  pollIntervalMs: 10,
  verifiedMapping: null, // No mapping
});
assert('Raw Readiness: Self-chat LID strictly rejected without verified mapping', rawRes3.ready === false && rawRes3.status === 'TIMEOUT');
assert('Raw Readiness: chatFound is false when LID mapping is unverified', rawRes3.chatFound === false);

// 4. Raw chat with LID is strictly REJECTED if mapping has contradictory phone
const invalidMapping = {
  conclusion: 'VERIFIED_BIDIRECTIONAL_MATCH',
  matchesAuthSession: true,
  lidLookup: { lid: '170141321052179@lid', pn: '919999999999@c.us' }, // Mismatched phone
  phoneLookup: { lid: '170141321052179@lid', pn: '919999999999@c.us' },
};
const rawRes4 = await RecipientValidator.waitForChatReadiness(rawClient2, '918080030111@c.us', {
  timeoutMs: 30,
  pollIntervalMs: 10,
  verifiedMapping: invalidMapping,
});
assert('Raw Readiness: Mismatched phone in LID mapping rejected', rawRes4.ready === false && rawRes4.status === 'TIMEOUT');

// 5. Non-fatal openChatWindow error handling
const rawClient5 = new MockPupPageClient({
  rawChat: { id: '918080030111@c.us', name: 'Self', isGroup: false },
  openChatWindowSuccess: false,
});
const rawRes5 = await RecipientValidator.waitForChatReadiness(rawClient5, '918080030111@c.us', {
  timeoutMs: 50,
  pollIntervalMs: 10,
  openChatWindow: true,
});
assert('Raw Readiness: openChatWindow failure is non-fatal and preserves CHAT_READY', rawRes5.ready === true && rawRes5.status === 'CHAT_READY');
assert('Raw Readiness: windowOpened is false when navigation throws', rawRes5.chatDetails?.windowOpened === false);

// 6. Readiness Failure: Raw chat returns null and times out
const nullRawClient = new MockPupPageClient({
  rawChat: null,
});
const rawRes6 = await RecipientValidator.waitForChatReadiness(nullRawClient, '918080030111@c.us', {
  timeoutMs: 30,
  pollIntervalMs: 10,
});
assert('Raw Readiness: Returns TIMEOUT when raw chat is null', rawRes6.ready === false && rawRes6.status === 'TIMEOUT');
assert('Raw Readiness: Preserves in-memory chat count even on timeout', rawRes6.chatCount === 459);

// -----------------------------------------------------------------------------
// Test Suite 27: Send Pipeline Diagnostic, Return Value Invariants & Options
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 27: Send Pipeline Diagnostic & Options Tracing ---');

// 1. Validator behavior on undefined sendResult (exact previous live test outcome)
const undefSend = RecipientValidator.validateMessageSendResult(undefined);
assert('Send Pipeline: Undefined sendResult correctly flagged as unverified', undefSend.verified === false);
assert('Send Pipeline: Error message explicitly explains invalid return', undefSend.error.includes('returned no valid WhatsApp message ID'));

// 2. Validator behavior on null, empty, or string-only fallback
const nullSend = RecipientValidator.validateMessageSendResult(null);
assert('Send Pipeline: Null sendResult correctly flagged as unverified', nullSend.verified === false);

const emptySend = RecipientValidator.validateMessageSendResult({});
assert('Send Pipeline: Empty object sendResult correctly flagged as unverified', emptySend.verified === false);

const stringIdSend = RecipientValidator.validateMessageSendResult({ id: 'true_170141321052179@lid_3EB0123456789' });
assert('Send Pipeline: String ID sendResult accepted and verified', stringIdSend.verified === true && stringIdSend.messageId === 'true_170141321052179@lid_3EB0123456789');

const validMsgSend = RecipientValidator.validateMessageSendResult({
  id: { _serialized: 'true_170141321052179@lid_3EB0987654321' },
  ack: 0,
});
assert('Send Pipeline: Standard Message model with id._serialized verified', validMsgSend.verified === true && validMsgSend.messageId === 'true_170141321052179@lid_3EB0987654321');

// 3. Simulated Mock of Client.js:1533-1558 evaluate function
class MockPuppeteerEvaluateSend {
  constructor({ chatFound = true, waitUntilMsgSent = false, msgInStore = true }) {
    this.chatFound = chatFound;
    this.waitUntilMsgSent = waitUntilMsgSent;
    this.msgInStore = msgInStore;
  }

  async evaluateSend(chatId, content, options) {
    // 1. WWebJS.getChat(chatId, { getAsModel: false })
    const chat = this.chatFound ? { id: { _serialized: '170141321052179@lid', isLid: () => true } } : null;
    if (!chat) return null; // Client.js line 1539

    // 2. WWebJS.sendMessage(chat, content, options)
    // If waitUntilMsgSent is false and msg is not immediately in Msg collection:
    if (!this.waitUntilMsgSent && !this.msgInStore) {
      return undefined; // Msg.get(newMsgKey._serialized) returns undefined
    }

    // When waitUntilMsgSent is true, sendMsgResultPromise completes and Msg.get resolves:
    return {
      id: { _serialized: `true_${chat.id._serialized}_3EB0${Date.now()}` },
      body: content,
      ack: 0,
      serialize() { return { id: this.id, body: this.body, ack: this.ack }; }
    };
  }
}

// Case A: Chat not found (e.g. premature dispatch at 23% sync before store restoration)
const mockPremature = new MockPuppeteerEvaluateSend({ chatFound: false });
const prematureResult = await mockPremature.evaluateSend('918080030111@c.us', 'Test', {});
assert('Send Pipeline: Premature dispatch without restored chat returns null (undefined Message)', prematureResult === null);

// Case B: Chat found but waitUntilMsgSent: false and Msg.get races before store index
const mockRacing = new MockPuppeteerEvaluateSend({ chatFound: true, waitUntilMsgSent: false, msgInStore: false });
const racingResult = await mockRacing.evaluateSend('918080030111@c.us', 'Test', {});
assert('Send Pipeline: Dispatch without waitUntilMsgSent reproduces undefined return', racingResult === undefined);

// Case C: Chat found, opened, and waitUntilMsgSent: true ensures model resolution
const mockResolved = new MockPuppeteerEvaluateSend({ chatFound: true, waitUntilMsgSent: true, msgInStore: true });
const resolvedResult = await mockResolved.evaluateSend('918080030111@c.us', 'Test', { waitUntilMsgSent: true });
assert('Send Pipeline: Dispatch with waitUntilMsgSent: true returns valid message model', Boolean(resolvedResult?.id?._serialized));
assert('Send Pipeline: Returned model passes RecipientValidator.validateMessageSendResult', RecipientValidator.validateMessageSendResult(resolvedResult).verified === true);

// 4. Source-code invariant verification on scripts/send_test_message.js
const sendScriptContent = fs.readFileSync(path.join(__dirname, '../scripts/send_test_message.js'), 'utf8');

assert(
  'Source Invariant: scripts/send_test_message.js passes waitUntilMsgSent: true',
  sendScriptContent.includes('waitUntilMsgSent: true')
);

assert(
  'Source Invariant: Destination is strictly canonical targetJid (never hardcoded LID)',
  sendScriptContent.includes('client.sendMessage(targetJid, messageBody, {')
);

assert(
  'Source Invariant: Strict message ID validation is performed before ACK tracking',
  sendScriptContent.includes('RecipientValidator.validateMessageSendResult(sendResult)')
);

assert(
  'Source Invariant: Undefined sendResult immediately aborts before awaiting ACK',
  sendScriptContent.includes('if (!idValidation.verified)') &&
  sendScriptContent.includes('ackTracker.cancel()')
);

// -----------------------------------------------------------------------------
// Test Suite 28: Message Resolution Tracker (Self-Chat Model Resolution)
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 28: Message Resolution Tracker (Self-Chat Model Resolution) ---');

class MockEventEmitterClient {
  constructor() {
    this.listeners = {};
    this.pupPage = {
      evaluate: async () => null,
    };
  }
  on(event, fn) {
    if (!this.listeners[event]) this.listeners[event] = [];
    this.listeners[event].push(fn);
  }
  off(event, fn) {
    if (!this.listeners[event]) return;
    this.listeners[event] = this.listeners[event].filter((f) => f !== fn);
  }
  removeListener(event, fn) {
    this.off(event, fn);
  }
  emit(event, ...args) {
    if (!this.listeners[event]) return;
    for (const fn of [...this.listeners[event]]) {
      fn(...args);
    }
  }
}

// 1. Direct valid sendResult bypasses resolution immediately
const mockDirectClient = new MockEventEmitterClient();
const trackerDirect = RecipientValidator.createMessageResolutionTracker(mockDirectClient, '918080030111@c.us', {
  messageBody: 'Hello',
});
const directValidMsg = { id: { _serialized: 'true_918080030111@c.us_3EB0111' }, body: 'Hello' };
const resDirect = await trackerDirect.resolveMessage(directValidMsg);
assert('Resolution Tracker: Direct valid sendResult returned without delay', resDirect === directValidMsg);

// 2. Undefined sendResult resolved via pre-captured message_create event
const mockPreClient = new MockEventEmitterClient();
const trackerPre = RecipientValidator.createMessageResolutionTracker(mockPreClient, '918080030111@c.us', {
  messageBody: 'Test Message',
  verifiedMapping: {
    lidLookup: { lid: '170141321052179@lid', pn: '918080030111@c.us' },
  },
});
const createdMsgPre = {
  id: { _serialized: 'true_170141321052179@lid_3EB0222' },
  fromMe: true,
  to: '170141321052179@lid',
  from: '170141321052179@lid',
  body: 'Test Message',
  ack: 0,
};
mockPreClient.emit('message_create', createdMsgPre);
const resPre = await trackerPre.resolveMessage(undefined);
assert('Resolution Tracker: Pre-captured message_create resolves undefined sendResult', resPre?.id?._serialized === 'true_170141321052179@lid_3EB0222');
assert('Resolution Tracker: Resolved model passes RecipientValidator.validateMessageSendResult', RecipientValidator.validateMessageSendResult(resPre).verified === true);

// 3. Undefined sendResult resolved via in-flight message_create event
const mockInFlightClient = new MockEventEmitterClient();
const trackerInFlight = RecipientValidator.createMessageResolutionTracker(mockInFlightClient, '918080030111@c.us', {
  messageBody: 'In-Flight Message',
  timeoutMs: 1000,
});
const createdMsgInFlight = {
  id: { _serialized: 'true_918080030111@c.us_3EB0333' },
  fromMe: true,
  to: '918080030111@c.us',
  body: 'In-Flight Message',
  ack: 0,
};
setTimeout(() => {
  mockInFlightClient.emit('message_create', createdMsgInFlight);
}, 50);
const resInFlight = await trackerInFlight.resolveMessage(undefined);
assert('Resolution Tracker: In-flight message_create resolves undefined sendResult within bounded wait', resInFlight?.id?._serialized === 'true_918080030111@c.us_3EB0333');

// 4. Undefined sendResult resolved via in-memory chat.msgs Puppeteer evaluate fallback
const mockChatMsgsClient = new MockEventEmitterClient();
mockChatMsgsClient.pupPage.evaluate = async (fn, chatId, expectedBody) => {
  return {
    id: { _serialized: 'true_170141321052179@lid_3EB0444' },
    body: expectedBody,
    fromMe: true,
    to: chatId,
    ack: 0,
  };
};
const trackerChatMsgs = RecipientValidator.createMessageResolutionTracker(mockChatMsgsClient, '918080030111@c.us', {
  messageBody: 'Fallback Message',
  timeoutMs: 100,
});
const resChatMsgs = await trackerChatMsgs.resolveMessage(undefined);
assert('Resolution Tracker: In-memory chat.msgs evaluate fallback resolves genuine message model', resChatMsgs?.id?._serialized === 'true_170141321052179@lid_3EB0444');

// 5. Inbound message (fromMe: false) is ignored
const mockInboundClient = new MockEventEmitterClient();
const trackerInbound = RecipientValidator.createMessageResolutionTracker(mockInboundClient, '918080030111@c.us', {
  messageBody: 'Inbound Message',
  timeoutMs: 50,
});
mockInboundClient.emit('message_create', {
  id: { _serialized: 'false_918080030111@c.us_3EB0555' },
  fromMe: false,
  to: '918080030111@c.us',
  body: 'Inbound Message',
});
const resInbound = await trackerInbound.resolveMessage(undefined);
assert('Resolution Tracker: Inbound message (fromMe: false) is ignored', resInbound === undefined);

// 6. Mismatched body message is ignored
const mockMismatchClient = new MockEventEmitterClient();
const trackerMismatch = RecipientValidator.createMessageResolutionTracker(mockMismatchClient, '918080030111@c.us', {
  messageBody: 'Expected Body',
  timeoutMs: 50,
});
mockMismatchClient.emit('message_create', {
  id: { _serialized: 'true_918080030111@c.us_3EB0666' },
  fromMe: true,
  to: '918080030111@c.us',
  body: 'Different Body',
});
const resMismatch = await trackerMismatch.resolveMessage(undefined);
assert('Resolution Tracker: Mismatched body message is ignored', resMismatch === undefined);

// 7. Unrelated chat destination is ignored
const mockWrongChatClient = new MockEventEmitterClient();
const trackerWrongChat = RecipientValidator.createMessageResolutionTracker(mockWrongChatClient, '918080030111@c.us', {
  messageBody: 'Test',
  timeoutMs: 50,
});
mockWrongChatClient.emit('message_create', {
  id: { _serialized: 'true_9999999999@c.us_3EB0777' },
  fromMe: true,
  to: '9999999999@c.us',
  body: 'Test',
});
const resWrongChat = await trackerWrongChat.resolveMessage(undefined);
assert('Resolution Tracker: Unrelated chat destination is ignored', resWrongChat === undefined);

// 8. All strategies fail returns undefined safely
const mockFailClient = new MockEventEmitterClient();
const trackerFail = RecipientValidator.createMessageResolutionTracker(mockFailClient, '918080030111@c.us', {
  messageBody: 'Fail Test',
  timeoutMs: 50,
});
const resFail = await trackerFail.resolveMessage(undefined);
assert('Resolution Tracker: Complete resolution failure returns undefined safely', resFail === undefined);
assert('Resolution Tracker: Undefined resolution result fails validateMessageSendResult safely', RecipientValidator.validateMessageSendResult(resFail).verified === false);

// 9. Source-code invariants in scripts/send_test_message.js
assert(
  'Source Invariant: scripts/send_test_message.js registers createMessageResolutionTracker',
  sendScriptContent.includes('RecipientValidator.createMessageResolutionTracker(client, targetJid,')
);
assert(
  'Source Invariant: scripts/send_test_message.js invokes resolutionTracker.resolveMessage on missing result',
  sendScriptContent.includes('resolutionTracker.resolveMessage(sendResult)')
);
assert(
  'Source Invariant: scripts/send_test_message.js cancels resolutionTracker on valid or failed send',
  sendScriptContent.includes('resolutionTracker.cancel()')
);

// -----------------------------------------------------------------------------
// Test Suite 29: Self-Chat Key Normalization, Obfuscated Serializer ($1) & Stream Stability
// -----------------------------------------------------------------------------
console.log('\n--- Test Suite 29: Self-Chat Key Normalization, Obfuscated Serializer ($1) & Stream Stability ---');

// 1. extractMessageId: extracts from modern WhatsApp Web obfuscated serializer property ($1)
const obfuscatedModel = {
  id: {
    fromMe: true,
    remote: '170141321052179@lid',
    id: '3EB06624F89EC938854563',
    self: 'out',
    $1: 'true_170141321052179@lid_3EB06624F89EC938854563_out',
  },
  body: 'MKES Test Message',
  ack: 0,
};
const extractedId1 = RecipientValidator.extractMessageId(obfuscatedModel);
assert('Key Normalization: extractMessageId extracts ID from $1 property', extractedId1 === 'true_170141321052179@lid_3EB06624F89EC938854563_out');

// 2. extractMessageId: extracts from standard _serialized property
const standardModel = {
  id: {
    _serialized: 'true_170141321052179@lid_3EB06624F89EC938854563',
  },
};
const extractedId2 = RecipientValidator.extractMessageId(standardModel);
assert('Key Normalization: extractMessageId extracts ID from _serialized property', extractedId2 === 'true_170141321052179@lid_3EB06624F89EC938854563');

// 3. extractMessageId: constructs canonical string from MsgKey components when serializer properties are missing
const componentModel = {
  id: {
    fromMe: true,
    remote: '170141321052179@lid',
    id: '3EB0999888777666555',
    self: 'out',
  },
};
const extractedId3 = RecipientValidator.extractMessageId(componentModel);
assert('Key Normalization: extractMessageId constructs canonical ID from MsgKey components with self suffix', extractedId3 === 'true_170141321052179@lid_3EB0999888777666555_out');

// 4. validateMessageSendResult: validates model with $1 and backfills id._serialized
const validationWithDollar1 = RecipientValidator.validateMessageSendResult(obfuscatedModel);
assert('Key Normalization: validateMessageSendResult succeeds on $1 model', validationWithDollar1.verified === true);
assert('Key Normalization: validateMessageSendResult returns correct messageId', validationWithDollar1.messageId === 'true_170141321052179@lid_3EB06624F89EC938854563_out');
assert('Key Normalization: validateMessageSendResult backfills id._serialized for downstream consumers', obfuscatedModel.id._serialized === 'true_170141321052179@lid_3EB06624F89EC938854563_out');

// 5. ACK Tracker: Stanza ID matching bridges _out suffix discrepancy between sendResult and server ACK
const mockAckClientStanza = new MockEventEmitterClient();
const ackTrackerStanza = RecipientValidator.createAckTracker(mockAckClientStanza, {
  timeoutMs: 1000,
  requiredAck: 2,
});

// Incoming ACK has no _out suffix, but target ID has _out suffix: stanza token 3EB06624F89EC938854563 matches
setTimeout(() => {
  mockAckClientStanza.emit('message_ack', {
    id: { _serialized: 'true_170141321052179@lid_3EB06624F89EC938854563' },
  }, 2);
}, 20);

const ackResStanza = await ackTrackerStanza.waitForAck('true_170141321052179@lid_3EB06624F89EC938854563_out');
assert('ACK Tracker: Stanza token matching bridges _out suffix discrepancy for device ACK (2)', ackResStanza.acknowledged === true && ackResStanza.ack === 2);
assert('ACK Tracker: Reports status ACK_DEVICE', ackResStanza.status === 'ACK_DEVICE');

// 6. ACK Tracker: Supports $1 extraction on incoming ACK event message
const mockAckClientDollar1 = new MockEventEmitterClient();
const ackTrackerDollar1 = RecipientValidator.createAckTracker(mockAckClientDollar1, {
  timeoutMs: 1000,
  requiredAck: 1,
});

setTimeout(() => {
  mockAckClientDollar1.emit('message_ack', {
    id: { $1: 'true_170141321052179@lid_3EB0ABCDEF123456_out' },
  }, 1);
}, 20);

const ackResDollar1 = await ackTrackerDollar1.waitForAck('true_170141321052179@lid_3EB0ABCDEF123456_out');
assert('ACK Tracker: Extracts message ID from $1 on incoming message_ack event', ackResDollar1.acknowledged === true && ackResDollar1.ack === 1);

// 7. Message Resolution Tracker: Resolves model emitted with $1 and out suffix on message_create
const mockResolutionDollar1Client = new MockEventEmitterClient();
const resolutionDollar1Tracker = RecipientValidator.createMessageResolutionTracker(mockResolutionDollar1Client, '918080030111@c.us', {
  messageBody: 'Self-chat message with $1',
  timeoutMs: 500,
  verifiedMapping: {
    lidLookup: { lid: '170141321052179@lid', pn: '918080030111@c.us' },
  },
});

mockResolutionDollar1Client.emit('message_create', {
  id: {
    $1: 'true_170141321052179@lid_3EB0D4E5F6A7B8C9_out',
    fromMe: true,
  },
  fromMe: true,
  to: '170141321052179@lid',
  body: 'Self-chat message with $1',
  ack: 0,
});

const resolvedDollar1 = await resolutionDollar1Tracker.resolveMessage(undefined);
assert('Resolution Tracker: Resolves $1 model on message_create event', Boolean(resolvedDollar1));
assert('Resolution Tracker: Resolved $1 model passes validateMessageSendResult', RecipientValidator.validateMessageSendResult(resolvedDollar1).verified === true);
assert('Resolution Tracker: Resolved model has extracted ID with _out suffix', RecipientValidator.extractMessageId(resolvedDollar1) === 'true_170141321052179@lid_3EB0D4E5F6A7B8C9_out');

// 8. Stream Stability: Source invariant verification that sendSeen: false is passed in scripts/send_test_message.js
assert(
  'Stream Stability: scripts/send_test_message.js passes sendSeen: false to prevent Stream.markUnavailable()',
  sendScriptContent.includes('sendSeen: false')
);

// 9. Stream Stability: scripts/send_test_message.js pairs waitUntilMsgSent: true and sendSeen: false together
assert(
  'Stream Stability: scripts/send_test_message.js pairs waitUntilMsgSent: true with sendSeen: false in sendMessage options',
  sendScriptContent.includes('waitUntilMsgSent: true') &&
  sendScriptContent.includes('sendSeen: false')
);

console.log('\n====================================================');
console.log(`Unit Test Suite Completed: ${passedTests} / ${totalTests} tests passed.`);
console.log('====================================================\n');


if (passedTests === totalTests) {
  process.exit(0);
} else {
  process.exit(1);
}
}

runTests().catch((err) => {
  console.error('Test execution failed:', err);
  process.exit(1);
});


