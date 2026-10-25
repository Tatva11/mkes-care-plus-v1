const path = require('path');
const fs = require('fs');

try {
  const dotenv = require('dotenv');
  const localEnv = path.join(__dirname, '.env');
  const rootEnv = path.join(__dirname, '../.env');
  if (fs.existsSync(localEnv)) {
    dotenv.config({ path: localEnv });
  } else if (fs.existsSync(rootEnv)) {
    dotenv.config({ path: rootEnv });
  }
  dotenv.config();
} catch (_) {}

const whatsappClient = require('./src/services/whatsapp_client');
const outboxWorker = require('./src/services/outbox_worker');
const botEngine = require('./src/services/bot_engine');
const automationScheduler = require('./src/services/scheduler');
const notificationWatcher = require('./src/services/notification_watcher');
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
logger.info('====================================================');

// 1. Initialize WhatsApp Web Client only when live mode is explicitly enabled
if (!isDryRun) {
  whatsappClient.initialize();
} else {
  logger.info('WhatsApp client not initialized: DRY_RUN safe mode is enabled.');
}

// 2. Wire Inbound Message Event to Bot Engine
whatsappClient.onMessage(async (msg) => {
  try {
    await botEngine.handleIncomingMessage(msg);
  } catch (err) {
    logger.error(`Unhandled error processing message: ${err.message}`, err);
  }
});

// 3. Start Outbox Poller Worker
if (String(process.env.DRY_RUN || 'true').trim().toLowerCase() === 'false') {
    outboxWorker.start();
} else {
    logger.info('Outbox worker not started: DRY_RUN safe mode is enabled.');
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
