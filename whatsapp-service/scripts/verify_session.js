/**
 * MKES CARE+ WhatsApp Bridge — Session Verification Diagnostic
 * 
 * Safely verifies whether the persistent session in C:\MKES_CARE_PLUS\wa_session
 * is authenticated and connects to WhatsApp Web without requiring a QR scan.
 * 
 * STRICT SAFEGUARDS:
 * - Scheduler: DISABLED
 * - Outbox Worker: DISABLED (0 messages claimed or sent)
 * - Bot Engine: DISABLED
 * - Read-only: Reads connected account info and immediately shuts down cleanly.
 * - Non-destructive: Does not wipe, overwrite, or mutate session tokens on disk.
 */

const path = require('path');
const fs = require('fs');

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

const { Client, LocalAuth } = require('whatsapp-web.js');

const sessionPath = process.env.WA_SESSION_PATH || 'C:\\MKES_CARE_PLUS\\wa_session';

console.log('====================================================');
console.log('  MKES CARE+ WhatsApp Bridge — Session Verification ');
console.log('====================================================');
console.log('  Session Directory: ' + sessionPath);
console.log('  Mode: READ-ONLY DIAGNOSTIC (No messages will be sent)');
console.log('  Timeout: 120 seconds');
console.log('====================================================\n');

if (!fs.existsSync(path.join(sessionPath, 'session'))) {
  console.error('[FAIL] No session directory found at ' + sessionPath);
  process.exit(1);
}

const client = new Client({
  authStrategy: new LocalAuth({
    dataPath: sessionPath,
  }),
  puppeteer: {
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-accelerated-2d-canvas',
      '--no-first-run',
      '--no-zygote',
      '--disable-gpu',
    ],
  },
});

let isResolved = false;
let isCleaningUp = false;

const TIMEOUT_MS = 120000; // 120 seconds bounded timeout (allows IndexedDB store restoration)

async function cleanup(exitCode = 0) {
  if (isCleaningUp) return;
  isCleaningUp = true;
  clearTimeout(timeout);
  try {
    if (client) {
      await client.destroy();
    }
  } catch (_) {}
  process.exit(exitCode);
}

const timeout = setTimeout(async () => {
  if (!isResolved && !isCleaningUp) {
    isResolved = true;
    console.error(`\n[TIMEOUT] Session verification timed out after ${TIMEOUT_MS / 1000} seconds.`);
    console.error('WhatsApp Web did not reach READY, QR_REQUIRED, or AUTH_FAILURE within the window.');
    await cleanup(1);
  }
}, TIMEOUT_MS);

// Diagnostic progress listener (does NOT reset overall timeout)
client.on('loading_screen', (percent, message) => {
  console.log(`>> [PROGRESS] Loading chats: ${percent}% (${message || 'WhatsApp'})`);
});

client.on('qr', async () => {
  isResolved = true;
  console.log('\n====================================================');
  console.log('  [RESULT] QR_REQUIRED: Session Unauthenticated     ');
  console.log('====================================================');
  console.log('  WhatsApp Web requested a QR code scan.');
  console.log('  The saved session has expired, was logged out, or is invalid.');
  console.log('====================================================\n');
  await cleanup(1);
});

client.on('authenticated', () => {
  console.log('>> [EVENT] WhatsApp Web authenticated successfully from saved session!');
});

client.on('auth_failure', async (msg) => {
  isResolved = true;
  console.error('\n====================================================');
  console.error('  [RESULT] AUTH_FAILURE: Authentication Rejected    ');
  console.error('====================================================');
  console.error(`  Error: ${msg}`);
  console.error('====================================================\n');
  await cleanup(1);
});

client.on('ready', async () => {
  isResolved = true;
  console.log('\n====================================================');
  console.log('  [PASS] VERIFIED: WhatsApp Session is ACTIVE & READY!');
  if (client.info) {
    console.log('  Connected Phone Number: +' + (client.info.wid?.user || 'Unknown'));
    console.log('  Connected Account Name: ' + (client.info.pushname || 'N/A'));
    console.log('  Platform:               ' + (client.info.platform || 'WhatsApp Web'));
  }
  console.log('  Session persistence confirmed across restarts.');
  console.log('====================================================\n');
  await cleanup(0);
});

console.log('Initializing client to test saved session...');
client.initialize().catch(async (err) => {
  if (!isCleaningUp && !isResolved) {
    console.error('[ERROR] Failed to initialize client:', err.message);
    await cleanup(1);
  }
});
