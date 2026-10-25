/**
 * MKES CARE+ WhatsApp Bridge — Dedicated Pairing Mode
 * 
 * Safely initializes WhatsApp Web Client (whatsapp-web.js) to display the QR code
 * and persist authentication credentials into LocalAuth session directory.
 * 
 * STRICT SAFEGUARDS:
 * - Scheduler is NOT started (zero scheduled jobs).
 * - Outbox worker is NOT started (zero messages polled, claimed, or sent).
 * - Bot engine is NOT wired (inbound messages are not processed).
 * - Purely executes the client authentication handshake.
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

const whatsappClient = require('../src/services/whatsapp_client');
const logger = require('../src/utils/logger');

console.log('====================================================');
console.log('  MKES CARE+ WhatsApp Bridge — Safe Pairing Mode    ');
console.log('====================================================');
console.log('  Mode: PAIRING ONLY                                ');
console.log('  Outbox Worker: DISABLED (No messages will be sent)');
console.log('  Scheduler: DISABLED (No automated jobs will run)  ');
console.log('  Bot Engine: DISABLED (No incoming messages handled)');
console.log('====================================================\n');

logger.info('Starting WhatsApp client in isolated pairing mode...');

// Initialize WhatsApp Web Client
whatsappClient.initialize();

// Listen for authentication and ready states to notify the user
if (whatsappClient.client) {
  whatsappClient.client.on('authenticated', () => {
    console.log('\n>> WhatsApp authentication confirmed! Finalizing session credentials...');
  });

  whatsappClient.client.on('ready', () => {
    console.log('\n====================================================');
    console.log('  SUCCESS: WhatsApp Client is Paired & Authenticated!');
    console.log('  Session saved to: ' + whatsappClient.sessionPath);
    console.log('  You can now safely press Ctrl+C to exit.');
    console.log('====================================================\n');
  });
}

// Graceful exit
const shutdown = () => {
  console.log('\nShutting down pairing session...');
  if (whatsappClient.client) {
    whatsappClient.client.destroy().then(() => {
      console.log('WhatsApp client closed.');
      process.exit(0);
    });
  } else {
    process.exit(0);
  }
};

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
