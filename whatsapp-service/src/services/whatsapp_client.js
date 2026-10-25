const { Client, LocalAuth } = require('whatsapp-web.js');
const qrcodeTerminal = require('qrcode-terminal');
const QRCode = require('qrcode');
const path = require('path');
const fs = require('fs');
const logger = require('../utils/logger');
const { supabase } = require('../config/supabase');
const RecipientValidator = require('../utils/recipient_validator');

class WhatsAppClientManager {
  constructor() {
    this.client = null;
    this.isReady = false;
    this.sessionPath = process.env.WA_SESSION_PATH || 'C:\\MKES_CARE_PLUS\\wa_session';
    this.qrAttempt = 0;
    this._messageListeners = [];
  }

  onMessage(callback) {
    if (typeof callback === 'function') {
      this._messageListeners.push(callback);
    }
  }

  initialize() {
    logger.info(`Initializing WhatsApp Web Client with LocalAuth at ${this.sessionPath}`);

    // Clean up stale Chromium SingletonLock files from previous container restarts/crashes
    try {
      const sessionSubdir = path.join(this.sessionPath, 'session');
      ['SingletonLock', 'SingletonCookie', 'SingletonSocket'].forEach((file) => {
        const filePath = path.join(sessionSubdir, file);
        if (fs.existsSync(filePath)) {
          try {
            fs.unlinkSync(filePath);
            logger.info(`Removed stale Chromium lock: ${file}`);
          } catch (_) {}
        }
      });
    } catch (_) {}

    this.client = new Client({
      authStrategy: new LocalAuth({
        dataPath: this.sessionPath,
      }),
      puppeteer: {
        headless: true,
        executablePath: process.env.PUPPETEER_EXECUTABLE_PATH || undefined,
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

    this._registerEvents();
    this.client.initialize().catch((err) => {
      logger.error(`Fatal error initializing WhatsApp client: ${err.message}`, err);
      this._updateStatusInDb('error');
    });
  }

  async _saveQrImage(qr) {
    try {
      const tempDir = path.join(__dirname, '../../.temp');
      if (!fs.existsSync(tempDir)) {
        fs.mkdirSync(tempDir, { recursive: true });
      }
      const pngPath = path.join(tempDir, 'whatsapp_qr.png');
      const htmlPath = path.join(tempDir, 'scan_qr.html');

      // Generate 450x450 high-contrast QR PNG
      await QRCode.toFile(pngPath, qr, {
        width: 450,
        margin: 2,
        color: {
          dark: '#000000',
          light: '#FFFFFF',
        },
      });

      // Generate self-refreshing HTML viewer for local browser
      const htmlContent = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>MKES CARE+ — WhatsApp Pairing QR</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; text-align: center; background: #0b141a; color: #e9edef; padding: 40px 20px; margin: 0; }
    .card { background: #111b21; max-width: 480px; margin: 0 auto; border-radius: 16px; padding: 28px; box-shadow: 0 8px 24px rgba(0,0,0,0.5); border: 1px solid #222e35; }
    h1 { font-size: 20px; margin: 8px 0; color: #25d366; }
    p { color: #8696a0; font-size: 14px; margin-bottom: 20px; line-height: 1.5; }
    .qr-box { background: #ffffff; padding: 14px; border-radius: 12px; display: inline-block; box-shadow: 0 4px 12px rgba(0,0,0,0.3); }
    img { display: block; width: 360px; height: 360px; }
    .footer { margin-top: 20px; font-size: 12px; color: #8696a0; }
    .badge { background: #005c4b; color: #25d366; padding: 4px 12px; border-radius: 20px; font-weight: bold; font-size: 11px; display: inline-block; text-transform: uppercase; letter-spacing: 0.5px; }
    .status { margin-top: 10px; font-size: 12px; color: #53bdeb; }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">MKES CARE+ Clinical WhatsApp</div>
    <h1>Scan to Link Device</h1>
    <p>Open <b>WhatsApp</b> on your phone &rarr; <b>Linked Devices</b> &rarr; <b>Link a Device</b>, then scan this QR code.</p>
    <div class="qr-box">
      <img id="qr" src="whatsapp_qr.png?t=${Date.now()}" alt="WhatsApp QR Code" />
    </div>
    <div class="status" id="status-text">Attempt #${this.qrAttempt} &bull; Generated ${new Date().toLocaleTimeString()}</div>
    <div class="footer">This page automatically updates when WhatsApp rotates the QR code.</div>
  </div>
  <script>
    setInterval(() => {
      document.getElementById('qr').src = 'whatsapp_qr.png?t=' + Date.now();
    }, 2500);
  </script>
</body>
</html>`;
      fs.writeFileSync(htmlPath, htmlContent, 'utf8');

      return { pngPath, htmlPath };
    } catch (err) {
      logger.error(`Failed to save QR image: ${err.message}`);
      return null;
    }
  }

  _registerEvents() {
    this.client.on('qr', async (qr) => {
      this.qrAttempt += 1;
      logger.info(`WhatsApp QR Code generated (attempt #${this.qrAttempt}).`);

      const qrPaths = await this._saveQrImage(qr);
      if (qrPaths) {
        console.log('\n====================================================');
        console.log(`  [QR CODE READY] Attempt #${this.qrAttempt}`);
        console.log(`  PNG Image:   ${qrPaths.pngPath}`);
        console.log(`  HTML Viewer: ${qrPaths.htmlPath}`);
        console.log('====================================================\n');
      }

      // Also render fallback terminal display using qrcode package
      try {
        const terminalQr = await QRCode.toString(qr, { type: 'terminal', small: true });
        console.log(terminalQr + '\n');
      } catch (_) {
        qrcodeTerminal.generate(qr, { small: true });
      }

      // Save to Supabase so Admin dashboard can display it live
      await this._updateStatusInDb('qr_ready', qr);
    });

    this.client.on('authenticated', () => {
      logger.info('WhatsApp Web authenticated successfully.');
    });

    this.client.on('ready', async () => {
      this.isReady = true;
      logger.info('WhatsApp Web client is READY and connected!');
      await this._updateStatusInDb('authenticated');

      // Clean up temporary QR files upon successful authentication
      try {
        const tempDir = path.join(__dirname, '../../.temp');
        const pngPath = path.join(tempDir, 'whatsapp_qr.png');
        const htmlPath = path.join(tempDir, 'scan_qr.html');
        if (fs.existsSync(pngPath)) fs.unlinkSync(pngPath);
        if (fs.existsSync(htmlPath)) fs.unlinkSync(htmlPath);
      } catch (_) {}
    });

    this.client.on('disconnected', async (reason) => {
      this.isReady = false;
      logger.warn(`WhatsApp client disconnected: ${reason}`);
      await this._updateStatusInDb('disconnected');
    });

    this.client.on('auth_failure', async (msg) => {
      this.isReady = false;
      logger.error(`WhatsApp authentication failure: ${msg}`);
      await this._updateStatusInDb('error');
    });

    this.client.on('message', async (msg) => {
      for (const listener of this._messageListeners) {
        try {
          await listener(msg);
        } catch (err) {
          logger.error(`Unhandled error in WhatsApp message listener: ${err.message}`, err);
        }
      }
    });
  }

  async _updateStatusInDb(status, qrData = null) {
    try {
      const payload = {
        session_status: status,
        last_heartbeat: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      };
      if (qrData) {
        payload.qr_code_data = qrData;
      } else if (status === 'authenticated') {
        payload.qr_code_data = null;
      }

      await supabase
        .from('whatsapp_settings')
        .update(payload)
        .eq('id', '00000000-0000-0000-0000-000000000001');
    } catch (err) {
      logger.error(`Failed to update session status in DB: ${err.message}`);
    }
  }

  /**
   * Humanized Message Dispatcher.
   * Simulates realistic presence and typing duration before sending message.
   */
  async sendMessageWithHumanizedDelay(toJid, messageText) {
    // HARD SAFEGUARD: Dry-run is active by default unless explicitly configured to 'false'
    const isDryRun = String(process.env.DRY_RUN || 'true').trim().toLowerCase() !== 'false';
    if (isDryRun) {
      logger.info(`[DRY RUN INTERCEPTED] Real dispatch blocked by default safe mode. Simulated send to ${toJid}: "${messageText.replace(/\n/g, ' ').substring(0, 80)}..."`);
      return {
        id: { _serialized: `dry-run-${Date.now()}` },
        simulated: true,
        to: toJid,
        timestamp: Math.floor(Date.now() / 1000),
      };
    }

    if (!this.isReady) {
      throw new Error('WhatsApp client is not ready or authenticated.');
    }

    try {
      // Validate and resolve target JID using strict E.164 (+91) format
      let targetJid = toJid;
      try {
        const prep = RecipientValidator.prepareLookupNumber(toJid);
        if (prep.success) {
          const numberId = await this.client.getNumberId(prep.e164);
          const validation = RecipientValidator.validateResolvedRecipient({
            expectedE164: prep.e164,
            expectedJid: prep.expectedJid,
            resolvedNumberId: numberId,
            connectedUser: this.client.info?.wid?.user,
          });
          if (validation.valid) {
            targetJid = validation.targetJid;
          } else {
            logger.warn(`Recipient verification warning for ${toJid}: ${validation.error}. Proceeding with normalized JID: ${prep.expectedJid}`);
            targetJid = prep.expectedJid;
          }
        }
      } catch (lookupErr) {
        logger.debug(`Directory lookup skipped: ${lookupErr.message}`);
      }

      // 1. Send Presence Available & Typing State Simulation (non-fatal)
      try {
        await this.client.sendPresenceAvailable();
        const typingMs = Math.floor(Math.random() * (3000 - 1500 + 1)) + 1500;
        const chat = await this.client.getChatById(targetJid);
        if (chat && typeof chat.sendStateTyping === 'function') {
          await chat.sendStateTyping();
          await new Promise((r) => setTimeout(r, typingMs));
          await chat.clearState();
        }
      } catch (presenceErr) {
        logger.debug(`Presence/typing simulation skipped: ${presenceErr.message}`);
      }

      // 2. Send Message
      const response = await this.client.sendMessage(targetJid, messageText);
      return response;
    } catch (err) {
      logger.error(`Failed to send message to ${toJid}: ${err.message}`, err);
      throw err;
    }
  }
}

module.exports = new WhatsAppClientManager();
