const path = require('path');
const fs = require('fs');

try {
  const dotenv = require('dotenv');
  const candidateEnvPaths = [
    path.resolve(__dirname, '../api.env'),
    path.resolve(__dirname, '../.env'),
    path.resolve(__dirname, '.env'),
  ];
  for (const envPath of candidateEnvPaths) {
    if (fs.existsSync(envPath)) {
      dotenv.config({ path: envPath });
    }
  }
  dotenv.config();
} catch (_) {}

const whatsappClient = require('./src/services/whatsapp_client');
const outboxWorker = require('./src/services/outbox_worker');
const botEngine = require('./src/services/bot_engine');
const automationScheduler = require('./src/services/scheduler');
const notificationWatcher = require('./src/services/notification_watcher');
const { hasServiceRole } = require('./src/config/supabase');
const logger = require('./src/utils/logger');

logger.info('====================================================');
logger.info('  MKES CARE+ WhatsApp Bridge Daemon Starting...     ');
logger.info('  Host: Windows PC Local Service                   ');
logger.info('  Clinical Scope: Eye & Dental (Optical Excluded)   ');
const isDryRun = String(process.env.DRY_RUN || 'true').trim().toLowerCase() !== 'false';
if (isDryRun) {
  logger.warn('  [SAFE MODE] DRY_RUN active by default: Real messages cannot be sent.');
} else {
  logger.warn('  [CAUTION] DRY_RUN=false: LIVE PRODUCTION DISPATCH IS ARMED.');
}
if (!hasServiceRole) {
  logger.warn('  [CONFIG NOTICE] SUPABASE_SERVICE_ROLE_KEY is not provisioned.');
  logger.warn('  Outbox worker and batch schedulers are paused until provisioned.');
}
logger.info('====================================================');

// 1. Initialize WhatsApp Web Client (unless explicitly disabled in test harnesses)
const disableClient = String(process.env.DISABLE_WHATSAPP_CLIENT || 'false').trim().toLowerCase() === 'true';
if (!disableClient) {
  whatsappClient.initialize();
} else {
  logger.info('WhatsApp client initialization skipped: DISABLE_WHATSAPP_CLIENT=true.');
}

// 2. Wire Inbound Message Event to Bot Engine
whatsappClient.onMessage(async (msg) => {
  try {
    await botEngine.handleIncomingMessage(msg);
  } catch (err) {
    logger.error(`Unhandled error processing inbound message: ${err.message}`, err);
  }
});

// 2b. Wire Device Sent Message Event (captures replies sent from physical clinic phone)
whatsappClient.onMessageCreate(async (msg) => {
  try {
    if (msg.fromMe) {
      await botEngine.handleDeviceSentMessage(msg);
    }
  } catch (err) {
    logger.error(`Unhandled error processing device sent message: ${err.message}`, err);
  }
});

// 2c. Wire WhatsApp Message Acknowledgement Event (sent -> delivered -> read -> failed)
whatsappClient.onMessageAck(async (msg, ack, messageId) => {
  try {
    await outboxWorker.handleMessageAck(msg, ack, messageId);
  } catch (err) {
    logger.error(`Unhandled error processing message ack: ${err.message}`, err);
  }
});

// 3. Start Outbox Poller Worker
const disableOutbox = String(process.env.DISABLE_OUTBOX_WORKER || 'false').trim().toLowerCase() === 'true';
if (!disableOutbox) {
  outboxWorker.start();
} else {
  logger.info('Outbox worker not started: DISABLE_OUTBOX_WORKER=true.');
}

// 4. Start Automation Scheduler (resilient host-level cron)
automationScheduler.start();

// 5. Start Notification Watcher (bridges in-app events to FCM push notifications)
notificationWatcher.start();

// 6. Standby Heartbeat (Keeps container alive in safe idle simulation mode)
let standbyHeartbeat = null;
if (isDryRun && (process.env.SCHEDULER_MODE || 'disabled').toLowerCase() === 'disabled') {
  logger.info('WhatsApp service is running in STANDBY safe simulation mode (DRY_RUN=true, SCHEDULER_MODE=disabled).');
  standbyHeartbeat = setInterval(() => {
    logger.debug('Standby heartbeat tick...');
  }, 30000);
}

// 7. Graceful Shutdown Handling
const shutdown = () => {
  logger.info('Graceful shutdown initiated...');
  if (standbyHeartbeat) clearInterval(standbyHeartbeat);
  outboxWorker.stop();
  automationScheduler.stop();
  notificationWatcher.stop();
  if (whatsappClient.client) {
    whatsappClient.client.destroy().then(() => {
      logger.info('WhatsApp client destroyed cleanly.');
      process.exit(0);
    });
  } else {
    process.exit(0);
  }
};

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
process.on('uncaughtException', (err) => {
  logger.error(`Uncaught Exception: ${err.message}`, err);
});
process.on('unhandledRejection', (reason) => {
  logger.error(`Unhandled Rejection: ${reason}`);
});
