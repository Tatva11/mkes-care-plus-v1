/**
 * MKES CARE+ WhatsApp Integration — Read-Only Chat Retrieval Diagnostic
 * 
 * STRICT SAFEGUARDS:
 * - Read-only: Zero calls to client.sendMessage(). No messages will ever be sent.
 * - Schedulers, Outbox Workers, Bot Engines: All DISABLED.
 * - Non-destructive: Does not mutate session tokens, database records, or Supabase.
 * - Inspects supported lookup methods and in-memory vs store chat retrieval.
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

const sessionPath = process.env.WA_SESSION_PATH || 'C:\\MKES_CARE_PLUS\\wa_session';
const targetPhone = '8080030111';
const prep = RecipientValidator.prepareLookupNumber(targetPhone);
const { e164, expectedJid } = prep;
const targetLid = '170141321052179@lid';

console.log('====================================================');
console.log('  MKES CARE+ — Read-Only Chat Retrieval Diagnostic  ');
console.log('====================================================');
console.log('  Mode:           STRICTLY READ-ONLY (Zero Messages)');
console.log('  Target Phone:   +' + e164);
console.log('  Expected JID:   ' + expectedJid);
console.log('  Expected LID:   ' + targetLid);
console.log('  Session Path:   ' + sessionPath);
console.log('  Timeout:        90 seconds');
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

const watchdog = setTimeout(async () => {
  if (!isCompleted && !isCleaningUp) {
    console.error('\n[TIMEOUT] Diagnostic timed out after 90 seconds.');
    await cleanup(1);
  }
}, 90000);

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

client.on('loading_screen', (percent, message) => {
  console.log(`>> [PROGRESS] Loading chats: ${percent}% (${message || 'WhatsApp'})`);
});

client.on('qr', async () => {
  isCompleted = true;
  console.error('\n[ERROR] QR code requested.');
  await cleanup(1);
});

client.on('auth_failure', async (msg) => {
  isCompleted = true;
  console.error(`\n[AUTH FAILURE] ${msg}`);
  await cleanup(1);
});

client.on('ready', async () => {
  console.log('>> WhatsApp Web client emitted READY event.');
  const connectedUser = client.info?.wid?.user;
  const connectedSerialized = client.info?.wid?._serialized;
  console.log(`>> Connected Account: +${connectedUser || 'Unknown'} (${connectedSerialized || 'N/A'})`);

  try {
    // 1. Wait briefly for offline progress to reach 100% if still progressing
    console.log('>> Waiting 5 seconds post-ready to allow store synchronization...');
    await new Promise((r) => setTimeout(r, 5000));

    // 2. Supported Library API: getChats()
    console.log('\n--- Supported Library API: client.getChats() ---');
    let loadedChats = [];
    try {
      loadedChats = await client.getChats();
      console.log(`>> client.getChats() returned ${loadedChats.length} chat(s).`);
      if (loadedChats.length > 0) {
        console.log('>> First 5 chat IDs in memory:');
        loadedChats.slice(0, 5).forEach((c, idx) => {
          console.log(`   [${idx + 1}] ID: ${c.id?._serialized} | Name: ${c.name} | isGroup: ${c.isGroup}`);
        });
      }
    } catch (chatsErr) {
      console.log(`>> client.getChats() error: ${chatsErr.message}`);
    }

    // 3. Supported Library API: getChatById(phoneJid) & getChatById(lidJid)
    console.log('\n--- Supported Library API: client.getChatById() ---');
    try {
      const phoneChat = await client.getChatById(expectedJid);
      console.log(`>> getChatById('${expectedJid}'): ${phoneChat ? `FOUND (Name: ${phoneChat.name}, ID: ${phoneChat.id?._serialized})` : 'undefined (Not in store)'}`);
    } catch (err) {
      console.log(`>> getChatById('${expectedJid}') threw: ${err.message}`);
    }

    try {
      const lidChat = await client.getChatById(targetLid);
      console.log(`>> getChatById('${targetLid}'): ${lidChat ? `FOUND (Name: ${lidChat.name}, ID: ${lidChat.id?._serialized})` : 'undefined (Not in store)'}`);
    } catch (err) {
      console.log(`>> getChatById('${targetLid}') threw: ${err.message}`);
    }

    // 4. Supported Library API: getContacts() & getContactById()
    console.log('\n--- Supported Library API: client.getContactById() ---');
    try {
      const phoneContact = await client.getContactById(expectedJid);
      console.log(`>> getContactById('${expectedJid}'):`);
      console.log(`   - Name:     ${phoneContact?.name || phoneContact?.pushname || 'N/A'}`);
      console.log(`   - isMe:     ${phoneContact?.isMe}`);
      console.log(`   - isUser:   ${phoneContact?.isUser}`);
      console.log(`   - isGroup:  ${phoneContact?.isGroup}`);
      console.log(`   - isWAContact: ${phoneContact?.isWAContact}`);
    } catch (err) {
      console.log(`>> getContactById('${expectedJid}') threw: ${err.message}`);
    }

    try {
      const lidContact = await client.getContactById(targetLid);
      console.log(`>> getContactById('${targetLid}'):`);
      console.log(`   - Name:     ${lidContact?.name || lidContact?.pushname || 'N/A'}`);
      console.log(`   - isMe:     ${lidContact?.isMe}`);
      console.log(`   - isUser:   ${lidContact?.isUser}`);
    } catch (err) {
      console.log(`>> getContactById('${targetLid}') threw: ${err.message}`);
    }

    // 5. In-Depth Read-Only Store Inspection (DOM evaluate)
    console.log('\n--- WhatsApp Web In-Depth Store Inspection (Read-Only) ---');
    const storeInspection = await client.pupPage.evaluate(async (expectedJid, targetLid) => {
      const report = {};

      try {
        const Collections = window.require('WAWebCollections');
        const WidFactory = window.require('WAWebWidFactory');

        // Chat Collection inspection
        const chatModels = Collections.Chat.getModelsArray();
        report.chatModelsCount = chatModels.length;
        report.chatModelIds = chatModels.slice(0, 10).map((c) => c.id?._serialized);

        // Contact Collection inspection
        const contactModels = Collections.Contact.getModelsArray();
        report.contactModelsCount = contactModels.length;

        // Me user info
        const MeUser = window.require('WAWebUserPrefsMeUser');
        report.mePnUser = MeUser.getMaybeMePnUser()?.toString?.() || null;
        report.meLidUser = MeUser.getMaybeMeLidUser()?.toString?.() || null;

        // Synchronous Chat.get vs Asynchronous Chat.find
        const phoneWid = WidFactory.createWid(expectedJid);
        const lidWid = WidFactory.createWid(targetLid);

        report.chatGetPhone = Boolean(Collections.Chat.get(phoneWid));
        report.chatGetLid = Boolean(Collections.Chat.get(lidWid));

        // Asynchronous Chat.find (queries IndexedDB)
        try {
          const findPhone = await Collections.Chat.find(phoneWid);
          report.chatFindPhone = Boolean(findPhone);
          report.chatFindPhoneId = findPhone?.id?._serialized || null;
        } catch (e) {
          report.chatFindPhoneError = e.message;
        }

        try {
          const findLid = await Collections.Chat.find(lidWid);
          report.chatFindLid = Boolean(findLid);
          report.chatFindLidId = findLid?.id?._serialized || null;
        } catch (e) {
          report.chatFindLidError = e.message;
        }

        // findOrCreateLatestChat
        const FindChatAction = window.require('WAWebFindChatAction');
        try {
          const findOrCreatedPhone = await FindChatAction.findOrCreateLatestChat(phoneWid);
          report.findOrCreatePhoneResult = Boolean(findOrCreatedPhone?.chat);
          report.findOrCreatePhoneChatId = findOrCreatedPhone?.chat?.id?._serialized || null;
        } catch (e) {
          report.findOrCreatePhoneError = e.message;
        }

        try {
          const findOrCreatedLid = await FindChatAction.findOrCreateLatestChat(lidWid);
          report.findOrCreateLidResult = Boolean(findOrCreatedLid?.chat);
          report.findOrCreateLidChatId = findOrCreatedLid?.chat?.id?._serialized || null;
        } catch (e) {
          report.findOrCreateLidError = e.message;
        }

        // Offline progress check
        const OfflineHandler = window.AuthStore?.OfflineMessageHandler;
        report.offlineDeliveryProgress = OfflineHandler?.getOfflineDeliveryProgress?.() ?? null;

        // Step-by-step tracing of getChatModel on lidChat
        const lidChatRaw = Collections.Chat.get(lidWid);
        report.lidChatRawFound = Boolean(lidChatRaw);
        if (lidChatRaw) {
          report.lidChatSteps = {};
          try {
            const s = lidChatRaw.serialize();
            report.lidChatSteps.serialize = 'OK (keys: ' + Object.keys(s).length + ')';
          } catch (e) {
            report.lidChatSteps.serialize = e.stack || e.message || String(e);
          }
          try {
            report.lidChatSteps.formattedTitle = lidChatRaw.formattedTitle;
          } catch (e) {
            report.lidChatSteps.formattedTitle = e.stack || e.message || String(e);
          }
          try {
            report.lidChatSteps.isGroup = Boolean(lidChatRaw.groupMetadata);
          } catch (e) {
            report.lidChatSteps.isGroup = e.stack || e.message || String(e);
          }
          try {
            report.lidChatSteps.isNewsletter = Boolean(lidChatRaw.newsletterMetadata);
          } catch (e) {
            report.lidChatSteps.isNewsletter = e.stack || e.message || String(e);
          }
          try {
            const lrk = lidChatRaw.lastReceivedKey;
            report.lidChatSteps.lastReceivedKey = lrk ? (lrk._serialized || 'exists') : 'null';
          } catch (e) {
            report.lidChatSteps.lastReceivedKey = e.stack || e.message || String(e);
          }
          try {
            await window.WWebJS.getChatModel(lidChatRaw);
            report.lidChatSteps.getChatModel = 'OK';
          } catch (e) {
            report.lidChatSteps.getChatModel = {
              message: e?.message || String(e),
              name: e?.name,
              stack: e?.stack,
              type: typeof e,
              constructor: e?.constructor?.name,
            };
          }
        }

        // Test raw WWebJS.getChat with getAsModel: false
        try {
          const rawLid = await window.WWebJS.getChat(targetLid, { getAsModel: false });
          report.rawGetChatLid = rawLid ? { id: rawLid.id?._serialized, title: rawLid.name || rawLid.formattedTitle } : null;
        } catch (e) {
          report.rawGetChatLidError = e.message || String(e);
        }

        try {
          const rawPhone = await window.WWebJS.getChat(expectedJid, { getAsModel: false });
          report.rawGetChatPhone = rawPhone ? { id: rawPhone.id?._serialized, title: rawPhone.name || rawPhone.formattedTitle } : null;
        } catch (e) {
          report.rawGetChatPhoneError = e.message || String(e);
        }

        // Test getChatModel across all chats to see failure rate
        let chatModelSuccessCount = 0;
        const failures = [];
        for (let i = 0; i < chatModels.length; i++) {
          const c = chatModels[i];
          try {
            await window.WWebJS.getChatModel(c);
            chatModelSuccessCount++;
          } catch (err) {
            if (failures.length < 5) {
              failures.push({
                id: c.id?._serialized,
                isGroup: Boolean(c.groupMetadata),
                isNewsletter: Boolean(c.newsletterMetadata),
                error: err?.message || String(err),
                stack: err?.stack?.split('\n').slice(0, 3).join(' | '),
              });
            }
          }
        }
        report.chatModelSuccessCount = chatModelSuccessCount;
        report.chatModelFailureCount = chatModels.length - chatModelSuccessCount;
        report.chatModelFailuresSample = failures;

      } catch (err) {
        report.evalError = err.message;
      }

      return report;
    }, expectedJid, targetLid);

    console.log('>> In-Memory Chat Models Count:    ', storeInspection.chatModelsCount);
    console.log('>> In-Memory Contact Models Count: ', storeInspection.contactModelsCount);
    console.log('>> Sample Chat Model IDs (First 5):', storeInspection.chatModelIds?.slice(0, 5));
    console.log('>> WhatsApp Me PN User:            ', storeInspection.mePnUser);
    console.log('>> WhatsApp Me LID User:           ', storeInspection.meLidUser);
    console.log('>> Chat.get(phoneJid) (Sync):      ', storeInspection.chatGetPhone ? 'FOUND' : 'null');
    console.log('>> Chat.get(lidJid) (Sync):        ', storeInspection.chatGetLid ? 'FOUND' : 'null');
    console.log('>> Chat.find(lidJid) (IndexedDB):  ', storeInspection.chatFindLid ? `FOUND (${storeInspection.chatFindLidId})` : `null (err: ${storeInspection.chatFindLidError || 'none'})`);
    console.log('>> findOrCreateLatestChat(phone):  ', storeInspection.findOrCreatePhoneResult ? `RESOLVED (${storeInspection.findOrCreatePhoneChatId})` : `FAILED (err: ${storeInspection.findOrCreatePhoneError || 'none'})`);
    console.log('>> findOrCreateLatestChat(lid):    ', storeInspection.findOrCreateLidResult ? `RESOLVED (${storeInspection.findOrCreateLidChatId})` : `FAILED (err: ${storeInspection.findOrCreateLidError || 'none'})`);
    console.log('>> Offline Delivery Progress:      ', storeInspection.offlineDeliveryProgress !== null ? `${storeInspection.offlineDeliveryProgress}%` : 'N/A');
    console.log('\n--- Step-by-Step getChatModel Diagnostic for Self-Chat (LID) ---');
    console.log('>> lidChatRawFound:                ', storeInspection.lidChatRawFound);
    console.log('>> Steps:', JSON.stringify(storeInspection.lidChatSteps, null, 2));
    console.log('\n--- Raw WWebJS.getChat(chatId, { getAsModel: false }) ---');
    console.log('>> rawGetChat(lidJid):             ', JSON.stringify(storeInspection.rawGetChatLid));
    console.log('>> rawGetChat(phoneJid):           ', JSON.stringify(storeInspection.rawGetChatPhone));
    console.log('\n--- Overall Chat Model Serialization Statistics ---');
    console.log(`>> Total Chats in Memory:          ${storeInspection.chatModelsCount}`);
    console.log(`>> Successfully Serialized:        ${storeInspection.chatModelSuccessCount}`);
    console.log(`>> Failed Serialization:           ${storeInspection.chatModelFailureCount}`);
    if (storeInspection.chatModelFailuresSample?.length > 0) {
      console.log('>> Sample Serialization Failures:');
      storeInspection.chatModelFailuresSample.forEach((f, i) => {
        console.log(`   [${i + 1}] ID: ${f.id} | Group: ${f.isGroup} | Newsletter: ${f.isNewsletter}`);
        console.log(`       Error: ${f.error}`);
        console.log(`       Stack: ${f.stack}`);
      });
    }

    isCompleted = true;

    console.log('\n====================================================');
    console.log('  [COMPLETE] Read-Only Diagnostic Finished           ');
    console.log('  Zero messages dispatched. Shutting down cleanly.   ');
    console.log('====================================================\n');

    await cleanup(0);
  } catch (err) {
    isCompleted = true;
    console.error('[ERROR] Diagnostic execution failed:', err.message);
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
