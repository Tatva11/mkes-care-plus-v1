/**
 * MKES CARE+ — Consolidated WhatsApp Deployment SQL Validation Test Suite
 *
 * Verifies all 9 critical fixes required for CONSOLIDATED_WHATSAPP_DEPLOYMENT.sql:
 * 1. Outbox permissions & RLS least-privilege
 * 2. QR/session privacy (no qr_code_data in settings)
 * 3. Staff message recipient validation (patient-phone mismatch rejection)
 * 4. Opt-out authorization for register_patient_whatsapp_opt_out
 * 5. Data-preserving status constraint migration (no blind rewrite to 'pending')
 * 6. Appointment approval (Eye/Dental only, slot concurrency locking, opt-out check)
 * 7. Phone matching (exact 10-digit normalized matching & ambiguous recipient rejection)
 * 8. Timezone handling (type-safe date/time extraction from 'Asia/Kolkata')
 * 9. Schema compatibility & Preflight check block
 */

const fs = require('fs');
const path = require('path');
const assert = require('assert');

let passedTests = 0;
let failedTests = 0;

function runTest(testName, fn) {
  try {
    fn();
    console.log(`  [PASS] ${testName}`);
    passedTests++;
  } catch (err) {
    console.error(`  [FAIL] ${testName}: ${err.message}`);
    failedTests++;
  }
}

console.log('================================================================');
console.log('  MKES CARE+ — SQL MIGRATION CONSOLIDATED VALIDATION TESTS      ');
console.log('================================================================\n');

const sqlPath = path.resolve(__dirname, '../../supabase/migrations/CONSOLIDATED_WHATSAPP_DEPLOYMENT.sql');
assert(fs.existsSync(sqlPath), `SQL migration file must exist at ${sqlPath}`);
const sqlContent = fs.readFileSync(sqlPath, 'utf8');

console.log('--- 1. Outbox Permissions & Direct Client Mutation Denial ---');

runTest('Explicit revocation of all permissions on whatsapp_messages_outbox from anon, authenticated, PUBLIC', () => {
  const match = sqlContent.match(/REVOKE\s+ALL\s+ON\s+TABLE\s+public\.whatsapp_messages_outbox\s+FROM\s+([a-zA-Z0-9_,\s]+);/i);
  assert(match, 'Must have REVOKE ALL ON TABLE public.whatsapp_messages_outbox statement');
  const roles = match[1].split(',').map(s => s.trim().toLowerCase());
  assert(roles.includes('anon'), 'Must revoke from anon');
  assert(roles.includes('authenticated'), 'Must revoke from authenticated');
  assert(roles.includes('public'), 'Must revoke from PUBLIC');
});

runTest('Only SELECT is granted to authenticated on whatsapp_messages_outbox', () => {
  const authGrants = [...sqlContent.matchAll(/GRANT\s+([A-Z,\s]+)\s+ON\s+TABLE\s+public\.whatsapp_messages_outbox\s+TO\s+authenticated/gi)];
  assert(authGrants.length === 1, 'Must have exactly one GRANT to authenticated on outbox');
  const privs = authGrants[0][1].trim().toUpperCase();
  assert.strictEqual(privs, 'SELECT', 'Only SELECT may be granted to authenticated on outbox');
});

runTest('Direct mutation RLS policies dropped for outbox', () => {
  assert(sqlContent.includes('DROP POLICY IF EXISTS "Staff and Admins insert outbox" ON public.whatsapp_messages_outbox;'), 'Must drop insert policy');
  assert(sqlContent.includes('DROP POLICY IF EXISTS "Staff and Admins update outbox" ON public.whatsapp_messages_outbox;'), 'Must drop update policy');
  assert(sqlContent.includes('DROP POLICY IF EXISTS "Staff and Admins delete outbox" ON public.whatsapp_messages_outbox;'), 'Must drop delete policy');
});

console.log('\n--- 2. QR & Session Privacy ---');

runTest('qr_code_data is NOT added to whatsapp_settings', () => {
  const addColumnsMatch = sqlContent.match(/ALTER\s+TABLE\s+public\.whatsapp_settings\s+ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+([\s\S]+?);/i);
  assert(addColumnsMatch, 'Must find ALTER TABLE public.whatsapp_settings ADD COLUMN');
  const columnsAdded = addColumnsMatch[1].toLowerCase();
  assert(!columnsAdded.includes('qr_code_data'), 'qr_code_data must NOT be added in ADD COLUMN');
});

runTest('qr_code_data is explicitly dropped if present from legacy migration', () => {
  assert(sqlContent.includes('ALTER TABLE public.whatsapp_settings DROP COLUMN IF EXISTS qr_code_data;'), 'Must drop qr_code_data column');
});

runTest('whatsapp_settings UPDATE grant restricted to configuration columns', () => {
  const updateGrant = sqlContent.match(/GRANT\s+UPDATE\s*\(([^)]+)\)\s+ON\s+TABLE\s+public\.whatsapp_settings\s+TO\s+authenticated/i);
  assert(updateGrant, 'Must grant column-level UPDATE on whatsapp_settings');
  const cols = updateGrant[1].split(',').map(s => s.trim().toLowerCase());
  assert(!cols.includes('qr_code_data'), 'Must not grant UPDATE on qr_code_data');
  assert(!cols.includes('session_status'), 'Must not grant UPDATE on session_status');
  assert(!cols.includes('last_heartbeat'), 'Must not grant UPDATE on last_heartbeat');
  assert(!cols.includes('connected_phone'), 'Must not grant UPDATE on connected_phone');
  assert(cols.includes('is_enabled'), 'Must grant update on is_enabled');
  assert(cols.includes('daily_send_limit'), 'Must grant update on daily_send_limit');
});

console.log('\n--- 3. Staff Message Recipient Validation & Anti-Spoofing ---');

runTest('send_staff_whatsapp_message verifies phone belongs to supplied patient_id', () => {
  assert(sqlContent.includes('v_patient_clean_mobile := public.normalize_phone_10(v_patient_record.mobile);'), 'Must normalize registered patient mobile');
  assert(sqlContent.includes('IF v_patient_clean_mobile IS NULL OR v_patient_clean_mobile <> v_ten_digits THEN'), 'Must check phone mismatch');
  assert(sqlContent.includes('Recipient phone mismatch: The provided phone number does not match the registered mobile for this patient.'), 'Must return mismatch message');
});

runTest('send_staff_whatsapp_message rejects empty message body and invalid phone length', () => {
  assert(sqlContent.includes('IF v_ten_digits IS NULL THEN'), 'Must check phone validity');
  assert(sqlContent.includes('Invalid phone number format: must contain at least 10 valid digits.'), 'Must return invalid phone error');
  assert(sqlContent.includes('Message body cannot be empty.'), 'Must reject empty message body');
});

console.log('\n--- 4. Opt-Out Authorization ---');

runTest('register_patient_whatsapp_opt_out is revoked from authenticated', () => {
  const revokeMatch = sqlContent.match(/REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.register_patient_whatsapp_opt_out\(TEXT\)\s+FROM\s+([a-zA-Z0-9_,\s]+);/i);
  assert(revokeMatch, 'Must revoke register_patient_whatsapp_opt_out');
  const roles = revokeMatch[1].split(',').map(s => s.trim().toLowerCase());
  assert(roles.includes('authenticated'), 'Must revoke from authenticated');
  assert(roles.includes('public'), 'Must revoke from PUBLIC');
});

runTest('register_patient_whatsapp_opt_out has internal role guard for service_role or admin', () => {
  const fnBodyMatch = sqlContent.match(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.register_patient_whatsapp_opt_out[\s\S]+?AS\s+\$\$([\s\S]+?)\$\$;/i);
  assert(fnBodyMatch, 'Must find register_patient_whatsapp_opt_out body');
  const body = fnBodyMatch[1];
  assert(body.includes('service_role') && body.includes('admin'), 'Must check service_role or admin');
  assert(body.includes('Forbidden: Only administrators or background service workers can register opt-outs by phone number.'), 'Must raise exception for unauthorized callers');
});

console.log('\n--- 5. Data-Preserving Status Constraint Handling ---');

runTest('Status migration preserves sent messages with sent_at', () => {
  assert(sqlContent.includes("SET status = 'sent'"), 'Must preserve sent status');
  assert(sqlContent.includes("sent_at IS NOT NULL;"), 'Must check sent_at IS NOT NULL');
});

runTest('Status migration preserves failed messages with last_error', () => {
  assert(sqlContent.includes("SET status = 'failed'"), 'Must preserve failed status');
  assert(sqlContent.includes("last_error IS NOT NULL"), 'Must check last_error IS NOT NULL');
});

runTest('Status migration safely neutralizes unknown/unsupported statuses to cancelled', () => {
  assert(sqlContent.includes("SET status = 'cancelled'"), 'Must neutralize legacy to cancelled');
  assert(sqlContent.includes("Migrated legacy non-conforming status:"), 'Must log provenance in last_error');
  assert(!sqlContent.includes("SET status = 'pending'\nWHERE status IS NULL OR status NOT IN"), 'Must NOT blindly update all to pending');
});

runTest('Status check constraint permits exactly the 7 canonical statuses', () => {
  const checkMatch = sqlContent.match(/CHECK\s*\(\s*status\s+IN\s*\(([^)]+)\)\s*\)/i);
  assert(checkMatch, 'Must find CHECK (status IN (...)) constraint');
  const statuses = checkMatch[1].split(',').map(s => s.trim().replace(/'/g, ''));
  const expected = ['pending', 'processing', 'sent', 'delivered', 'read', 'failed', 'cancelled'];
  assert.deepStrictEqual(statuses.sort(), expected.sort(), 'Must permit all 7 canonical statuses');
});

console.log('\n--- 6. Appointment Approval Security & Concurrency ---');

runTest('approve_whatsapp_appointment_request enforces Eye/Dental and strictly excludes Optical', () => {
  const fnBodyMatch = sqlContent.match(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.approve_whatsapp_appointment_request[\s\S]+?AS\s+\$\$([\s\S]+?)\$\$;/i);
  assert(fnBodyMatch, 'Must find approve_whatsapp_appointment_request body');
  const body = fnBodyMatch[1];
  assert(body.includes("NOT IN ('eye', 'dental')"), 'Must reject departments not in eye/dental');
  assert(body.includes("Optical is strictly excluded."), 'Must specifically cite Optical exclusion');
});

runTest('approve_whatsapp_appointment_request employs concurrency-safe advisory locks', () => {
  const fnBodyMatch = sqlContent.match(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.approve_whatsapp_appointment_request[\s\S]+?AS\s+\$\$([\s\S]+?)\$\$;/i);
  const body = fnBodyMatch[1];
  assert(body.includes('pg_advisory_xact_lock'), 'Must use pg_advisory_xact_lock');
  assert(body.includes('appt_slot_'), 'Must lock doctor/slot combination');
});

runTest('approve_whatsapp_appointment_request verifies opt-out before enqueuing confirmation', () => {
  const fnBodyMatch = sqlContent.match(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.approve_whatsapp_appointment_request[\s\S]+?AS\s+\$\$([\s\S]+?)\$\$;/i);
  const body = fnBodyMatch[1];
  assert(body.includes('whatsapp_opt_out'), 'Must check whatsapp_opt_out');
  assert(body.includes('IF NOT coalesce(v_is_opted_out, false) AND v_req_phone <> \'\' THEN'), 'Must guard confirmation message outbox insert');
});

console.log('\n--- 7. Exact Normalized Phone Matching & Ambiguity Handling ---');

runTest('Ambiguous multiple patients sharing phone number triggers safe failure', () => {
  assert(sqlContent.includes('ELSIF v_match_count > 1 THEN'), 'Must handle match_count > 1');
  assert(sqlContent.includes('Ambiguous recipient: multiple registered patients share this phone number. Please specify the exact patient ID.'), 'Must fail safely without picking arbitrary record');
  assert(!sqlContent.includes('ORDER BY created_at ASC LIMIT 1;'), 'Must NOT guess using LIMIT 1 on patient matching');
});

runTest('normalize_phone_10 function handles arbitrary prefixes and guarantees exact 10 digits', () => {
  assert(sqlContent.includes('CREATE OR REPLACE FUNCTION public.normalize_phone_10'), 'Must define normalize_phone_10');
  assert(sqlContent.includes('ELSE NULL'), 'Must return NULL if fewer than 10 digits');
});

console.log('\n--- 8. Timezone Handling (Asia/Kolkata) ---');

runTest('Timezone extraction uses type-safe DATE and TIME without naive TIMESTAMPTZ assignment', () => {
  assert(sqlContent.includes("v_clinic_today DATE := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;"), 'Must extract DATE safely');
  assert(sqlContent.includes("v_clinic_time TIME := (now() AT TIME ZONE 'Asia/Kolkata')::TIME;"), 'Must extract TIME safely');
  assert(!sqlContent.includes("v_clinic_now TIMESTAMPTZ := now() AT TIME ZONE 'Asia/Kolkata';"), 'Must NOT assign naive local time to TIMESTAMPTZ');
});

console.log('\n--- 9. Preflight Checks & Schema Compatibility ---');

runTest('Preflight check verifies core tables before migration', () => {
  assert(sqlContent.includes('=== MKES CARE+ WHATSAPP MIGRATION: RUNNING PREFLIGHT AUDIT ==='), 'Must have preflight notice');
  assert(sqlContent.includes("'profiles', 'patients', 'appointments'"), 'Must verify base clinic tables');
  assert(sqlContent.includes("'whatsapp_messages_outbox', 'whatsapp_settings'"), 'Must verify WhatsApp tables');
  assert(sqlContent.includes('RAISE EXCEPTION \'PREFLIGHT CHECK FAILED:'), 'Must abort transaction on missing required table');
});

runTest('claim_whatsapp_outbox_batch included for background worker and granted to service_role', () => {
  assert(sqlContent.includes('CREATE OR REPLACE FUNCTION public.claim_whatsapp_outbox_batch'), 'Must define claim_whatsapp_outbox_batch');
  assert(sqlContent.includes('GRANT EXECUTE ON FUNCTION public.claim_whatsapp_outbox_batch(UUID, INT, INT) TO service_role;'), 'Must grant execute to service_role');
});

runTest('Optical department excluded across all batch automations', () => {
  const deptsInBatch = [...sqlContent.matchAll(/lower\(trim\(a\.department\)\)\s+IN\s*\(([^)]+)\)/gi)];
  for (const m of deptsInBatch) {
    const list = m[1].toLowerCase();
    assert(list.includes("'eye'") && list.includes("'dental'"), 'Must include eye and dental');
    assert(!list.includes("'optical'"), 'Must NOT include optical');
  }
});

console.log('\n================================================================');
console.log(`  VALIDATION SUMMARY: ${passedTests} passed, ${failedTests} failed`);
console.log('================================================================');

if (failedTests > 0) {
  process.exit(1);
} else {
  process.exit(0);
}
