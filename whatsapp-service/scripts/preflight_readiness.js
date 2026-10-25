/**
 * MKES CARE+ WhatsApp Integration — Bounded Read-Only Preflight Diagnostic
 * 
 * STRICT SAFEGUARDS:
 * - Read-only: ZERO calls to client.sendMessage(). No messages will ever be sent.
 * - Schedulers, Outbox Workers, Bot Engines: All DISABLED.
 * - Non-destructive: Does not mutate session tokens, database records, or Supabase.
 * - Confirms whether WhatsApp Web chat store has finished restoring.
 * - Confirms whether the target canonical phone chat (918080030111@c.us) is ready in memory.
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
const RecipientValidator = require('../src/utils/recipient_validator');

// 1. Target recipient parameters
const args = process.argv.slice(2);
let targetPhone = '8080030111'; // Default to user account

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--phone' || args[i] === '-p') {
    targetPhone = args[i + 1];
    i++;
  }
}

const prep = RecipientValidator.prepareLookupNumber(targetPhone);
if (!prep.success) {
  console.error(`[ABORTED] ${prep.error}`);
  process.exit(1);
}

const { e164, expectedJid } = prep;
const sessionPath = process.env.WA_SESSION_PATH || 'C:\\MKES_CARE_PLUS\\wa_session';

console.log('====================================================');
console.log('  MKES CARE+ — Read-Only Chat Readiness Preflight   ');
console.log('====================================================');
console.log('  Mode:           STRICTLY READ-ONLY (Zero Messages)');
console.log('  Target Phone:   +' + e164);
console.log('  Target JID:     ' + expectedJid);
console.log('  Session Path:   ' + sessionPath);
console.log('  Timeout:        60 seconds');
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

let isCompleted = false;
let isCleaningUp = false;

// 120-second failsafe watchdog
const watchdog = setTimeout(async () => {
  if (!isCompleted && !isCleaningUp) {
    console.error('\n[TIMEOUT] Preflight diagnostic timed out after 120 seconds.');
    await cleanup(1);
  }
}, 120000);

async function cleanup(exitCode = 0) {
  if (isCleaningUp) return;
  isCleaningUp = true;
  clearTimeout(watchdog);
  try {
    if (client) {
      await client.destroy();
    }
  } catch (_) {}
  process.exit(exitCode);
}

// Progress listener for offline sync
client.on('loading_screen', (percent, message) => {
  console.log(`>> [PROGRESS] Loading chats: ${percent}% (${message || 'WhatsApp'})`);
});

client.on('qr', async () => {
  isCompleted = true;
  console.error('\n[ERROR] QR code requested. Saved session is invalid or logged out.');
  await cleanup(1);
});

client.on('auth_failure', async (msg) => {
  isCompleted = true;
  console.error(`\n[AUTH FAILURE] Authentication error: ${msg}`);
  await cleanup(1);
});

client.on('ready', async () => {
  console.log('>> WhatsApp Web client emitted READY event.');
  const connectedUser = client.info?.wid?.user;
  const connectedSerialized = client.info?.wid?._serialized;
  console.log(`>> Authenticated Account: +${connectedUser || 'Unknown'} (${client.info?.pushname || 'Clinic'})`);

  try {
    // 1. Confirm authenticated account
    if (connectedUser !== e164 && `91${connectedUser}` !== e164) {
      console.warn(`[WARNING] Connected account (+${connectedUser}) does not match target phone (+${e164}).`);
    }

    // 2. Directory & Mapping Check
    console.log(`>> Checking directory lookup for +${e164}...`);
    let numberId = null;
    try {
      numberId = await client.getNumberId(e164);
      console.log(`>> Directory result: ${numberId?._serialized || 'null'}`);
    } catch (lookupErr) {
      console.warn(`>> Directory lookup error: ${lookupErr.message}`);
    }

    // 3. Inspect LID Mapping
    const lidToInspect = numberId?._serialized?.endsWith('@lid') ? numberId._serialized : '170141321052179@lid';
    console.log(`>> Checking internal LID mapping for ${lidToInspect}...`);
    const mapping = await RecipientValidator.inspectLidAndPhoneMapping({
      client,
      lidId: lidToInspect,
      phoneId: expectedJid,
      connectedWid: client.info?.wid,
    });
    console.log(`>> Mapping verdict: ${mapping.conclusion} (Session Match: ${mapping.matchesAuthSession ? 'YES' : 'NO'})`);

    // 4. Bounded Chat Store Readiness Wait (Does not rely on ready event alone)
    console.log(`>> Awaiting chat store restoration for target chat ${expectedJid}...`);
    const chatReadiness = await RecipientValidator.waitForChatReadiness(client, expectedJid, {
      timeoutMs: 75000,
      pollIntervalMs: 1500,
      verifiedMapping: mapping,
      openChatWindow: true,
    });

    isCompleted = true;

    console.log('\n====================================================');
    console.log('  [PREFLIGHT REPORT] Chat Store Readiness Diagnostic ');
    console.log('====================================================');
    console.log(`  Target Phone:        +${e164}`);
    console.log(`  Expected JID:        ${expectedJid}`);
    console.log(`  Authenticated User:  +${connectedUser || 'Unknown'} (${connectedSerialized || 'N/A'})`);
    console.log(`  Directory WID:       ${numberId?._serialized || 'null'}`);
    console.log(`  LID Mapping:         ${mapping.conclusion}`);
    console.log('----------------------------------------------------');
    console.log(`  Chat Store Ready:    ${chatReadiness.ready ? 'YES' : 'NO'}`);
    console.log(`  Readiness Status:    ${chatReadiness.status}`);
    console.log(`  Target Chat Found:   ${chatReadiness.chatFound ? 'YES' : 'NO'}`);
    if (chatReadiness.chatDetails) {
      console.log(`  Chat ID:             ${chatReadiness.chatDetails.id}`);
      console.log(`  Chat Name:           ${chatReadiness.chatDetails.name || '(Self/Direct)'}`);
      console.log(`  Is Group:            ${chatReadiness.chatDetails.isGroup ? 'YES' : 'NO'}`);
      console.log(`  Is Verified Self LID:${chatReadiness.chatDetails.isLid ? 'YES' : 'NO'}`);
      console.log(`  Chat Window Opened:  ${chatReadiness.chatDetails.windowOpened ? 'YES' : 'NO'}`);
    }
    console.log(`  Chats in Store:      ${chatReadiness.chatCount}`);
    console.log(`  Offline Sync:        ${chatReadiness.offlineProgress !== null ? `${chatReadiness.offlineProgress}%` : 'Complete / N/A'}`);
    console.log(`  Elapsed Time:        ${chatReadiness.durationMs}ms`);
    if (chatReadiness.error) {
      console.log(`  Diagnostic Detail:   ${chatReadiness.error}`);
    }
    console.log('====================================================');
    if (chatReadiness.ready) {
      console.log('  PREFLIGHT VERDICT: PASS (Chat is verified ready in store)');
    } else {
      console.log('  PREFLIGHT VERDICT: FAIL (Chat not available in store)');
    }
    console.log('  Zero messages dispatched. Shutting down cleanly.');
    console.log('====================================================\n');

    await cleanup(chatReadiness.ready ? 0 : 1);
  } catch (err) {
    isCompleted = true;
    console.error('[ERROR] Preflight failed:', err.message);
    await cleanup(1);
  }
});

console.log('Connecting to WhatsApp Web using saved session...');
client.initialize().catch(async (err) => {
  if (!isCleaningUp && !isCompleted) {
    console.error('[ERROR] Failed to initialize client:', err.message);
    await cleanup(1);
  }
});
