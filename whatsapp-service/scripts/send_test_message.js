/**
 * MKES CARE+ WhatsApp Bridge — Controlled Single-Message Delivery Tool
 * 
 * MODES:
 * 1. LOOKUP-ONLY MODE (--lookup-only / -l):
 *    - Connects to WhatsApp Web with saved session.
 *    - Queries directory registration for input phone number.
 *    - Validates resolved recipient against authenticated session.
 *    - STRUCTURALLY IMPOSSIBLE to send messages; exits immediately after reporting.
 * 
 * 2. CONTROLLED DISPATCH MODE:
 *    - Sends at most ONE message only after strict recipient verification.
 *    - Rejects unverified @lid results and number mismatches.
 *    - Validates genuine message ID (no misleading 'delivered' fallback).
 *    - Bounded 15s wait for WhatsApp server acknowledgement (ACK >= 1).
 *    - Immediately destroys client and exits cleanly.
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

// 1. Parse Command Line Arguments
const args = process.argv.slice(2);
let targetPhone = null;
let customMessage = null;
let isLookupOnly = false;

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--phone' || args[i] === '-p') {
    targetPhone = args[i + 1];
    i++;
  } else if (args[i] === '--message' || args[i] === '-m') {
    customMessage = args[i + 1];
    i++;
  } else if (args[i] === '--lookup-only' || args[i] === '-l') {
    isLookupOnly = true;
  }
}

console.log('====================================================');
console.log('  MKES CARE+ — Single Test Message Delivery Tool     ');
console.log('====================================================');
console.log('  Scheduler:      DISABLED');
console.log('  Outbox Worker:  DISABLED (0 queued records touched)');
console.log('  Bot Engine:     DISABLED');
if (isLookupOnly) {
  console.log('  Execution Mode: LOOKUP-ONLY (Read-Only Diagnostic)');
  console.log('  Hard Limit:     ZERO (0) MESSAGES DISPATCHED');
} else {
  console.log('  Execution Mode: CONTROLLED SINGLE-MESSAGE DISPATCH');
  console.log('  Hard Limit:     AT MOST ONE (1) MESSAGE');
}
console.log('====================================================\n');

if (!targetPhone) {
  console.error('[ABORTED] Missing target phone number.');
  console.error('Usage: node scripts/send_test_message.js --phone <10-DIGIT_PHONE> [--lookup-only] [--message "text"]');
  console.error('Examples:');
  console.error('  Lookup only:  node scripts/send_test_message.js --phone 8080030111 --lookup-only');
  console.error('  Send message: node scripts/send_test_message.js --phone 8080030111');
  process.exit(1);
}

// 2. Prepare Lookup Number (Strict E.164 with 91 prefix)
const prepResult = RecipientValidator.prepareLookupNumber(targetPhone);
if (!prepResult.success) {
  console.error(`[ABORTED] ${prepResult.error}`);
  process.exit(1);
}

const { e164, expectedJid, tenDigits } = prepResult;

const sessionPath = process.env.WA_SESSION_PATH || 'C:\\MKES_CARE_PLUS\\wa_session';
if (!fs.existsSync(path.join(sessionPath, 'session'))) {
  console.error(`[FAIL] No authenticated session found at: ${sessionPath}`);
  console.error('Please verify session first using: npm run verify-session');
  process.exit(1);
}

// 3. Prepare Controlled Test Payload
const istTimestamp = new Date().toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' });
const approvedTestMessage =
  'MKES CARE+ — Single WhatsApp delivery test. This message confirms the Sprint 10 WhatsApp bridge is being tested. No patient data is included.';
const messageBody = customMessage || approvedTestMessage;

console.log(`Target Phone:      +${e164}`);
console.log(`Expected JID:      ${expectedJid}`);
console.log(`Session Path:      ${sessionPath}`);
if (!isLookupOnly) {
  console.log(`Payload Preview:\n----------------------------------------------------\n${messageBody}\n----------------------------------------------------\n`);
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
let messageSent = false;
let isCleaningUp = false;

// 120-Second Failsafe Watchdog (allows cold start sync + 30s bounded ACK wait + safe teardown)
const watchdog = setTimeout(async () => {
  if (!isCompleted && !isCleaningUp) {
    console.error('\n[TIMEOUT] Operation timed out after 120 seconds.');
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

// Progress listener for chat sync
client.on('loading_screen', (percent, message) => {
  console.log(`>> [PROGRESS] Loading chats: ${percent}% (${message || 'WhatsApp'})`);
});

client.on('qr', async () => {
  isCompleted = true;
  console.error('\n[ERROR] WhatsApp Web requested QR code scan. Saved session is unauthenticated or invalidated.');
  await cleanup(1);
});

client.on('auth_failure', async (msg) => {
  isCompleted = true;
  console.error(`\n[AUTH FAILURE] Authentication error: ${msg}`);
  await cleanup(1);
});

client.on('ready', async () => {
  if (messageSent && !isLookupOnly) return; // Strict guard: never execute twice

  console.log('>> WhatsApp Web client is READY and connected.');
  const connectedUser = client.info?.wid?.user;
  console.log(`>> Connected Account: +${connectedUser || 'Unknown'} (${client.info?.pushname || 'Clinic'})`);

  try {
    // Step 1: Directory Lookup with full E.164 format (91XXXXXXXXXX)
    console.log(`>> Step 1: Looking up directory registration for +${e164}...`);
    let resolvedNumberId = null;
    try {
      resolvedNumberId = await client.getNumberId(e164);
    } catch (lookupErr) {
      console.error(`>> [LOOKUP ERROR] getNumberId failed: ${lookupErr.message}`);
    }

    // Step 2: Query internal LID <-> Phone mapping if directory returned an @lid or if in lookup-only mode
    let verifiedMapping = null;
    const resolvedSerialized = resolvedNumberId?._serialized || '';
    if (resolvedSerialized.endsWith('@lid') || isLookupOnly) {
      const lidToInspect = resolvedSerialized.endsWith('@lid') ? resolvedSerialized : '170141321052179@lid';
      console.log(`>> Step 2a: Directory returned @lid (${resolvedSerialized || 'N/A'}). Querying internal LID <-> Phone mapping for ${lidToInspect} and ${expectedJid}...`);
      verifiedMapping = await RecipientValidator.inspectLidAndPhoneMapping({
        client,
        lidId: lidToInspect,
        phoneId: expectedJid,
        connectedWid: client.info?.wid,
      });
      console.log(`>> Mapping verdict: ${verifiedMapping.conclusion} (Matches Session: ${verifiedMapping.matchesAuthSession ? 'YES' : 'NO'})`);
    }

    // Step 3: Validate Resolved Recipient Identity against authenticated session
    console.log('>> Step 2b: Validating recipient identity against authenticated session...');
    const validation = RecipientValidator.validateResolvedRecipient({
      expectedE164: e164,
      expectedJid,
      resolvedNumberId,
      connectedWid: client.info?.wid,
      verifiedMapping,
    });

    // -------------------------------------------------------------------------
    // STRUCTURAL GUARD: LOOKUP-ONLY MODE
    // Completely terminates here. It is structurally impossible to reach sendMessage.
    // -------------------------------------------------------------------------
    if (isLookupOnly) {
      isCompleted = true;
      const lidToInspect = (resolvedNumberId?._serialized?.endsWith('@lid'))
        ? resolvedNumberId._serialized
        : '170141321052179@lid';

      const mapping = verifiedMapping || await RecipientValidator.inspectLidAndPhoneMapping({
        client,
        lidId: lidToInspect,
        phoneId: expectedJid,
        connectedWid: client.info?.wid,
      });

      console.log('\n====================================================');
      console.log('  [LOOKUP-ONLY REPORT] Recipient Identity Analysis   ');
      console.log('====================================================');
      console.log(`  Input Phone:        +${e164}`);
      console.log(`  Expected Phone JID: ${expectedJid}`);
      console.log(`  Authenticated User: +${connectedUser || 'Unknown'} (${client.info?.wid?._serialized || 'N/A'})`);
      console.log(`  Directory WID:      ${resolvedNumberId?._serialized || 'null (unregistered)'}`);
      console.log(`  Validation Status:  ${validation.valid ? 'VERIFIED' : 'UNVERIFIED'}`);
      if (!validation.valid) {
        console.log(`  Rejection Reason:   ${validation.reason}`);
        console.log(`  Detail:             ${validation.error}`);
      }
      console.log('----------------------------------------------------');
      console.log('  [INTERNAL LID MAPPING CHECK (getContactLidAndPhone)]');
      console.log('----------------------------------------------------');
      console.log(`  1. Reverse Query (${lidToInspect}):`);
      console.log(`     - Returned LID:   ${mapping.lidLookup?.lid ?? 'null'}`);
      console.log(`     - Returned Phone: ${mapping.lidLookup?.pn ?? 'null'}`);
      if (mapping.lidLookupError) console.log(`     - Error:          ${mapping.lidLookupError}`);
      console.log(`  2. Forward Query (${expectedJid}):`);
      console.log(`     - Returned LID:   ${mapping.phoneLookup?.lid ?? 'null'}`);
      console.log(`     - Returned Phone: ${mapping.phoneLookup?.pn ?? 'null'}`);
      if (mapping.phoneLookupError) console.log(`     - Error:          ${mapping.phoneLookupError}`);
      console.log('----------------------------------------------------');
      console.log(`  Mapping Verdict:    ${mapping.conclusion}`);
      console.log(`  Session Match:      ${mapping.matchesAuthSession ? 'YES (consistent with connected account)' : 'NO'}`);
      console.log(`  Analysis Detail:    ${mapping.detail}`);
      console.log('====================================================');
      console.log('  Lookup-only mode: Structural guard active.');
      console.log('  Zero messages dispatched. Disconnecting client.');
      console.log('====================================================\n');
      await cleanup(validation.valid ? 0 : 1);
      return; // Absolute return: sendMessage below is completely unreachable
    }

    // -------------------------------------------------------------------------
    // CONTROLLED DISPATCH PATH (Only reached when isLookupOnly === false)
    // -------------------------------------------------------------------------
    if (!validation.valid) {
      console.error(`\n[ABORTED] Recipient identity validation failed:`);
      console.error(`  Reason: ${validation.reason}`);
      console.error(`  Detail: ${validation.error}`);
      console.error('Dispatch cancelled before sending to prevent misrouting.');
      await cleanup(1);
      return;
    }

    if (!validation.isSelf) {
      console.error(`\n[ABORTED] Security guard: Recipient is NOT the authenticated user's own account.`);
      console.error('Only the authenticated account is authorized for live test dispatch.');
      await cleanup(1);
      return;
    }

    const targetJid = validation.targetJid;
    if (targetJid.endsWith('@lid') || targetJid !== expectedJid) {
      console.error(`\n[CRITICAL ERROR] Target JID is not the canonical phone JID: ${targetJid}`);
      await cleanup(1);
      return;
    }

    console.log(`>> Recipient verified: ${targetJid} (Canonical Phone JID, matches authenticated account +${e164})`);

    // Step 3: Natural typing state simulation (non-fatal, skipped for self)
    console.log('>> Step 3/6: Simulating presence...');
    try {
      await client.sendPresenceAvailable();
      if (!validation.isSelf) {
        const chat = await client.getChatById(targetJid);
        if (chat && typeof chat.sendStateTyping === 'function') {
          await chat.sendStateTyping();
          await new Promise((r) => setTimeout(r, 1500));
          await chat.clearState();
        }
      } else {
        console.log('>> Recipient is connected account (self); skipping typing state simulation.');
      }
    } catch (presenceErr) {
      console.log(`>> Presence simulation skipped: ${presenceErr.message}`);
    }

    // Step 4: Verify chat store readiness for target chat before dispatching
    console.log(`>> Step 4/6: Verifying chat store readiness for ${targetJid} (bounded wait)...`);
    const chatReadiness = await RecipientValidator.waitForChatReadiness(client, targetJid, {
      timeoutMs: 30000,
      pollIntervalMs: 1500,
      verifiedMapping,
      openChatWindow: true,
    });

    if (!chatReadiness.ready) {
      console.error(`\n[ABORTED] Chat store readiness check failed:`);
      console.error(`  Status:          ${chatReadiness.status}`);
      console.error(`  Target JID:      ${targetJid}`);
      console.error(`  Offline Progress:${chatReadiness.offlineProgress !== null ? `${chatReadiness.offlineProgress}%` : 'N/A'}`);
      console.error(`  Chats in Store:  ${chatReadiness.chatCount}`);
      console.error(`  Detail:          ${chatReadiness.error || 'Chat object not available in memory store'}`);
      console.error('Dispatch cancelled before sending to prevent unverified message drops.');
      await cleanup(1);
      return;
    }

    console.log(`>> Chat store verified READY: ${targetJid} is active and ready in memory.`);
    console.log(`   (Chats in store: ${chatReadiness.chatCount}, Offline Progress: ${chatReadiness.offlineProgress !== null ? `${chatReadiness.offlineProgress}%` : 'Complete'})`);

    // Step 5: Register acknowledgement and message-resolution listeners BEFORE dispatch
    console.log('>> Step 5/6: Registering pre-dispatch acknowledgement and message-resolution listeners (bounded wait)...');
    const ackTracker = RecipientValidator.createAckTracker(client, {
      timeoutMs: 30000,
      requiredAck: 1,
    });
    const resolutionTracker = RecipientValidator.createMessageResolutionTracker(client, targetJid, {
      messageBody,
      timeoutMs: 5000,
      verifiedMapping,
    });

    // Step 6: Dispatch exactly ONE message (with internal transmission wait and stable stream)
    console.log(`>> Step 6/6: Dispatching exactly ONE message to ${targetJid}...`);
    let sendResult = await client.sendMessage(targetJid, messageBody, {
      waitUntilMsgSent: true,
      sendSeen: false,
    });
    messageSent = true;

    // Multi-strategy model resolution if direct library return is undefined (e.g. self-chat key mismatch)
    if (!sendResult) {
      console.log('>> Direct sendMessage return was undefined. Resolving genuine message model via resolution tracker...');
      sendResult = await resolutionTracker.resolveMessage(sendResult);
    } else {
      resolutionTracker.cancel();
    }

    // Validate Message ID (no misleading fallback string)
    const idValidation = RecipientValidator.validateMessageSendResult(sendResult);
    if (!idValidation.verified) {
      ackTracker.cancel();
      resolutionTracker.cancel();
      console.error(`\n[UNVERIFIED SEND] Message dispatch returned no valid WhatsApp message ID.`);
      console.error(`  Detail: ${idValidation.error}`);
      console.error('Cannot confirm whether message was accepted by WhatsApp.');
      await cleanup(1);
      return;
    }

    const messageId = idValidation.messageId;
    console.log(`>> Message dispatched with valid ID: ${messageId}`);
    console.log('>> Awaiting WhatsApp server / device acknowledgement (bounded 30s wait)...');

    // Wait for real WhatsApp acknowledgement using pre-registered tracker
    const ackResult = await ackTracker.waitForAck(messageId, sendResult?.ack);

    isCompleted = true;

    console.log('\n====================================================');
    console.log('  MKES CARE+ — Live Test Delivery Report             ');
    console.log('====================================================');
    console.log(`  Recipient Phone:      +${e164}`);
    console.log(`  Target Canonical JID: ${targetJid}`);
    console.log(`  Authenticated User:   +${connectedUser || 'Unknown'} (${client.info?.wid?._serialized || 'N/A'})`);
    console.log(`  Send Attempts:        1 (Hard limit enforced)`);
    console.log(`  Send Call Status:     SUCCESS (Promise resolved)`);
    console.log(`  Actual Message ID:    ${messageId}`);
    console.log(`  Highest ACK Level:    ACK ${ackResult.highestAck ?? ackResult.ack}`);
    console.log(`  ACK Status / Meaning: ${ackResult.status === 'ACK_DEVICE' ? 'ACK_DEVICE (2) — Device Delivered (Double Tick)' : ackResult.status === 'ACK_READ' ? 'ACK_READ (3) — Read by Recipient (Blue Tick)' : ackResult.status === 'ACK_SERVER' ? 'ACK_SERVER (1) — Server Acknowledged (Single Tick)' : ackResult.status === 'TIMEOUT' ? 'TIMEOUT (0) — No ACK received within 30s' : ackResult.status}`);
    console.log(`  Timeout / Error:      ${ackResult.error || 'None'}`);
    console.log(`  Timestamp:            ${istTimestamp} IST`);
    console.log('====================================================\n');

    if (!ackResult.acknowledged) {
      console.warn('[WARNING] No server or device acknowledgement observed within 30s timeout.');
      await cleanup(1);
      return;
    }

    console.log('Delivery confirmed. Safely disconnecting client.');
    await cleanup(0);
  } catch (err) {
    isCompleted = true;
    console.error(`\n[SEND FAILED] Execution error:`, err.stack || err);
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
