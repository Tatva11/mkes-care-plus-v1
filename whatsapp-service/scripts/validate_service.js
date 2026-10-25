/**
 * MKES CARE+ WhatsApp Service Validator
 * Comprehensive pre-deployment diagnostic and verification script
 */

const fs = require('fs');
const path = require('path');

try {
  const dotenv = require('dotenv');
  const serviceEnvPath = path.join(__dirname, '../.env');
  const rootEnvPath = path.join(__dirname, '../../.env');
  if (fs.existsSync(serviceEnvPath)) {
    dotenv.config({ path: serviceEnvPath });
  } else if (fs.existsSync(rootEnvPath)) {
    dotenv.config({ path: rootEnvPath });
  }
  dotenv.config();
} catch (_) {}

const PhoneNormalizer = require('../src/utils/phone_normalizer');
const { CLINIC, DEPARTMENTS, CONFIRMED_DOCTORS, MESSAGE_TYPES } = require('../src/config/constants');
const logger = require('../src/utils/logger');

console.log('====================================================');
console.log('  MKES CARE+ WhatsApp Service — Preflight Validation');
console.log('====================================================\n');

let passedChecks = 0;
let totalChecks = 0;
const warnings = [];

function check(label, assertion, detail = '') {
  totalChecks++;
  if (assertion) {
    passedChecks++;
    console.log(`  [PASS] ${label}`);
  } else {
    console.error(`  [FAIL] ${label} -> ${detail}`);
  }
}

function warn(label, detail = '') {
  warnings.push(`${label}: ${detail}`);
  console.log(`  [WARN] ${label} -> ${detail}`);
}

// 1. Node Environment Check
const nodeMajor = parseInt(process.versions.node.split('.')[0], 10);
check('Node.js Version >= 18', nodeMajor >= 18, `Current: v${process.versions.node}`);

// 2. Clinical Scope Check
check('Optical Department Strictly Excluded', !DEPARTMENTS.OPTICAL && !CONFIRMED_DOCTORS.optical, 'Optical must not exist');
check('Eye Department Configured', DEPARTMENTS.EYE === 'eye' && CONFIRMED_DOCTORS.eye.length === 2);
check('Dental Department Configured', DEPARTMENTS.DENTAL === 'dental' && CONFIRMED_DOCTORS.dental.length === 2);

// 3. Clinic Hours Check
check('Opening Hour is 09:00 AM', CLINIC.OPENING_HOUR === 9);
check('Closing Hour is 08:00 PM', CLINIC.CLOSING_HOUR === 20);

// 4. Message Categories Check
check('All 13 Operational Categories Defined', Object.keys(MESSAGE_TYPES).length >= 13);

// 5. Phone Normalizer Tests
check('Phone Normalizer: 10-digit standard', PhoneNormalizer.extractTenDigits('9876543210') === '9876543210');
check('Phone Normalizer: with +91 prefix', PhoneNormalizer.extractTenDigits('+91 98765 43210') === '9876543210');
check('Phone Normalizer: with leading 0', PhoneNormalizer.extractTenDigits('09876543210') === '9876543210');
check('Phone Normalizer: E.164 conversion', PhoneNormalizer.toIndianE164('9876543210') === '919876543210');
check('Phone Normalizer: WhatsApp JID format', PhoneNormalizer.toWhatsAppJid('9876543210') === '919876543210@c.us');
check('Phone Normalizer: Individual Chat Detection', PhoneNormalizer.isIndividualChat('919876543210@c.us') === true);

// 6. Logging Subsystem & Directory Access
const logDir = path.join(__dirname, '../logs');
let canWriteLogs = false;
try {
  if (!fs.existsSync(logDir)) fs.mkdirSync(logDir, { recursive: true });
  const testLog = path.join(logDir, '.write_test');
  fs.writeFileSync(testLog, 'ok');
  fs.unlinkSync(testLog);
  canWriteLogs = true;
} catch (_) {
  canWriteLogs = false;
}
check(`Logging Directory Access (${logDir})`, canWriteLogs, 'Cannot write to logs folder');

// 7. Session Directory Permissions Check
const sessionDir = process.env.WA_SESSION_PATH || 'C:\\MKES_CARE_PLUS\\wa_session';
let canWriteSession = false;
try {
  if (!fs.existsSync(sessionDir)) {
    fs.mkdirSync(sessionDir, { recursive: true });
  }
  const testFile = path.join(sessionDir, '.test_write_perm');
  fs.writeFileSync(testFile, 'test');
  fs.unlinkSync(testFile);
  canWriteSession = true;
} catch (e) {
  canWriteSession = false;
}
check(`Session Directory Access (${sessionDir})`, canWriteSession, `Cannot write to ${sessionDir}. Verify Windows permissions.`);

// 8. Mode Verification (DRY_RUN status)
const dryRunStr = String(process.env.DRY_RUN || 'true').trim().toLowerCase();
const isDryRun = dryRunStr !== 'false';
check('Operational Mode Configured (DRY_RUN valid boolean)', ['true', 'false'].includes(dryRunStr), 'DRY_RUN must be "true" or "false"');
if (isDryRun) {
  console.log('  [INFO] Safe Simulation Mode (DRY_RUN): ENABLED (Safe for testing - real dispatch blocked)');
} else {
  console.log('  [WARN] Safe Simulation Mode (DRY_RUN): DISABLED (LIVE PRODUCTION DISPATCH ARMED)');
}

// 9. Environment Variables Check
const hasUrl = !!process.env.SUPABASE_URL;
const hasKey = !!process.env.SUPABASE_SERVICE_ROLE_KEY && process.env.SUPABASE_SERVICE_ROLE_KEY !== 'your_supabase_service_role_key_here';

if (hasUrl) {
  check('SUPABASE_URL configured', true);
} else {
  warn('SUPABASE_URL', 'Not set in environment (using default localhost:54321 until production deployment)');
}

if (hasKey) {
  check('SUPABASE_SERVICE_ROLE_KEY configured', true);
} else {
  warn('SUPABASE_SERVICE_ROLE_KEY', 'Awaiting production secret provisioning (safely deferred until explicit admin approval)');
}

console.log('\n----------------------------------------------------');
console.log(`Validation Completed: ${passedChecks} / ${totalChecks} infrastructure checks passed.`);
if (warnings.length > 0) {
  console.log(`Deferred Gated Items (${warnings.length}):`);
  warnings.forEach(w => console.log(`  - ${w}`));
}
console.log('----------------------------------------------------');

// If all infrastructure checks passed, local readiness is confirmed.
const localReady = passedChecks === totalChecks;
if (localReady) {
  console.log('Local Host Status: READY for safe testing & Windows background service deployment.\n');
  process.exit(0);
} else {
  console.warn('Status: Local infrastructure defects detected. Please review failed checks.\n');
  process.exit(1);
}
