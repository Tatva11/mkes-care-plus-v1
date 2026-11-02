const { Client, LocalAuth, MessageMedia } = require('whatsapp-web.js');
const qrcodeTerminal = require('qrcode-terminal');
const QRCode = require('qrcode');
const path = require('path');
const fs = require('fs');
const logger = require('../utils/logger');
const { supabase } = require('../config/supabase');
const RecipientValidator = require('../utils/recipient_validator');
const PhoneNormalizer = require('../utils/phone_normalizer');
const instanceLock = require('../utils/instance_lock');

class WhatsAppClientManager {
  constructor() {
    this.client = null;
    this.isReady = false;
    this.sessionPath = process.env.WA_SESSION_PATH || 'C:\\MKES_CARE_PLUS\\wa_session';
    this.qrAttempt = 0;
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = 5;
    this.reconnectTimer = null;
    this._messageListeners = [];
    this._messageCreateListeners = [];
    this._messageAckListeners = [];
    this.accountMode = process.env.WA_ACCOUNT_MODE || 'development';
    this.accountLabel = process.env.WA_ACCOUNT_LABEL || 'Developer Test Account';
    this.latestQr = null;
    this.latestQrBuffer = null;
    this.latestQrDataUrl = null;
    this.latestQrTimestamp = 0;
  }

  static getTempDir() {
    return path.resolve(__dirname, '../../.temp');
  }

  static getQrPngPath() {
    return path.join(WhatsAppClientManager.getTempDir(), 'whatsapp_qr.png');
  }

  static getQrMetaPath() {
    return path.join(WhatsAppClientManager.getTempDir(), 'qr_metadata.json');
  }

  static getQrHtmlPath() {
    return path.join(WhatsAppClientManager.getTempDir(), 'scan_qr.html');
  }

  onMessageCreate(callback) {
    if (typeof callback === 'function') {
      this._messageCreateListeners.push(callback);
    }
  }

  onMessageAck(callback) {
    if (typeof callback === 'function') {
      this._messageAckListeners.push(callback);
    }
  }

  onMessage(callback) {
    if (typeof callback === 'function') {
      this._messageListeners.push(callback);
    }
  }

  initialize() {
    logger.info(`[ACCOUNT MODE] Operating in ${this.accountMode.toUpperCase()} mode (${this.accountLabel}). Patient-only inbox guard active.`);
    logger.info(`Initializing WhatsApp Web Client with LocalAuth at ${this.sessionPath}`);

    // 1. Acquire exclusive single-instance lock to prevent concurrent process profile corruption
    const lockRes = instanceLock.acquireLock(this.sessionPath, 'WhatsAppDaemon');
    if (!lockRes.success) {
      logger.error(`[LOCK CONFLICT] WhatsApp client initialization aborted: ${lockRes.error}`);
      this._updateStatusInDb('error');
      return;
    }

    // 2. Clean up stale Chromium lock artifacts (SingletonLock, SingletonCookie, SingletonSocket, DevToolsActivePort)
    instanceLock.cleanupChromiumLocks(this.sessionPath);

    // 3. Inspect existing session persistence state
    const sessionDefaultDir = path.join(this.sessionPath, 'session', 'Default');
    if (fs.existsSync(sessionDefaultDir)) {
      logger.info(`[SESSION FOUND] Existing authenticated Chromium session detected at ${this.sessionPath}. Reusing session data without re-pairing.`);
      this._updateStatusInDb('connecting');
    } else {
      logger.info(`[NEW SESSION] No saved session found at ${this.sessionPath}. QR pairing will be required.`);
    }

    this.client = new Client({
      authStrategy: new LocalAuth({
        dataPath: this.sessionPath,
      }),
      authTimeoutMs: 120000,
      userAgent: process.env.WA_USER_AGENT || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36',
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
          '--disable-blink-features=AutomationControlled',
          '--ignore-certificate-errors',
        ],
      },
    });

    this._registerEvents();
    this.client.initialize().catch((err) => {
      logger.error(`Fatal error initializing WhatsApp client: ${err?.message || err}`, err);
      this._updateStatusInDb('error');
    });
  }

  async _saveQrImage(qr) {
    try {
      const tempDir = WhatsAppClientManager.getTempDir();
      if (!fs.existsSync(tempDir)) {
        fs.mkdirSync(tempDir, { recursive: true });
      }
      const pngPath = WhatsAppClientManager.getQrPngPath();
      const htmlPath = WhatsAppClientManager.getQrHtmlPath();
      const metaPath = WhatsAppClientManager.getQrMetaPath();

      const now = Date.now();
      const timeStr = new Date(now).toLocaleTimeString();

      this.latestQr = qr;
      this.latestQrTimestamp = now;

      // Write QR metadata for real-time freshness tracking
      const metaData = {
        attempt: this.qrAttempt,
        timestamp: now,
        time: timeStr,
        validDurationSeconds: 25,
      };
      fs.writeFileSync(metaPath, JSON.stringify(metaData, null, 2), 'utf8');

      // Generate 450x450 high-contrast QR PNG buffer in memory and write to disk
      const pngBuffer = await QRCode.toBuffer(qr, {
        width: 450,
        margin: 2,
        color: {
          dark: '#000000',
          light: '#FFFFFF',
        },
      });
      this.latestQrBuffer = pngBuffer;
      fs.writeFileSync(pngPath, pngBuffer);

      // Generate base64 Data URL for standalone zero-CORS viewer rendering
      const qrDataUrl = await QRCode.toDataURL(qr, {
        width: 450,
        margin: 2,
        color: {
          dark: '#000000',
          light: '#FFFFFF',
        },
      });
      this.latestQrDataUrl = qrDataUrl;

      // Generate self-refreshing HTML viewer with live freshness counter and Base64 embed
      const htmlContent = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>MKES CARE+ — Live WhatsApp Pairing QR</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; text-align: center; background: #0b141a; color: #e9edef; padding: 30px 16px; margin: 0; }
    .card { background: #111b21; max-width: 480px; margin: 0 auto; border-radius: 16px; padding: 24px; box-shadow: 0 8px 32px rgba(0,0,0,0.6); border: 1px solid #222e35; }
    h1 { font-size: 22px; margin: 8px 0 4px 0; color: #25d366; }
    p { color: #8696a0; font-size: 14px; margin-bottom: 16px; line-height: 1.4; }
    .badge-bar { display: flex; justify-content: center; gap: 8px; margin-bottom: 14px; }
    .badge { background: #005c4b; color: #25d366; padding: 4px 12px; border-radius: 20px; font-weight: bold; font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; }
    .freshness-badge { padding: 4px 12px; border-radius: 20px; font-weight: bold; font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; transition: all 0.3s ease; }
    .freshness-fresh { background: #1b4d3e; color: #4ade80; border: 1px solid #22c55e; }
    .freshness-stale { background: #5c3811; color: #fbbf24; border: 1px solid #f59e0b; }
    .qr-box { background: #ffffff; padding: 12px; border-radius: 12px; display: inline-block; box-shadow: 0 4px 16px rgba(0,0,0,0.4); margin-bottom: 12px; position: relative; }
    img { display: block; width: 340px; height: 340px; border-radius: 4px; }
    .status { font-size: 13px; color: #53bdeb; margin-top: 8px; font-weight: 500; }
    .timer { font-size: 12px; color: #8696a0; margin-top: 4px; }
    .footer { margin-top: 16px; font-size: 12px; color: #667781; line-height: 1.4; border-top: 1px solid #222e35; padding-top: 12px; }
    .server-link { color: #25d366; text-decoration: none; font-weight: 600; }
    .server-link:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge-bar">
      <div class="badge">MKES CARE+ WhatsApp Bridge [${this.accountMode === 'clinic_production' ? 'CLINIC ACCOUNT' : 'DEVELOPMENT / TEST'}]</div>
      <div id="freshness-indicator" class="freshness-badge freshness-fresh">● LIVE & FRESH</div>
    </div>
    <h1>Scan to Link Device</h1>
    <p>Open <b>WhatsApp</b> on your mobile phone (${this.accountLabel}) &rarr; <b>Linked Devices</b> &rarr; <b>Link a Device</b> &rarr; Scan this code.<br><span style="font-size:12px; color:#53bdeb;">Patient-only inbox filtering active. Personal chats are strictly dropped.</span></p>
    <div class="qr-box">
      <img id="qr" src="${qrDataUrl}" alt="WhatsApp QR Code" />
    </div>
    <div class="status" id="status-text">Attempt #${this.qrAttempt} &bull; Generated ${timeStr}</div>
    <div class="timer" id="timer-text">Age: 0s &bull; Valid for ~25s</div>
    <div class="footer">
      Live Pairing Server: <a class="server-link" href="http://127.0.0.1:3900" target="_blank">http://127.0.0.1:3900</a><br>
      Zero-cache auto-refreshing payload from active WhatsApp Web client.
    </div>
  </div>
  <script>
    let lastTimestamp = ${now};
    let currentAttempt = ${this.qrAttempt};

    async function checkFreshness() {
      if (window.location.protocol === 'http:' || window.location.protocol === 'https:') {
        try {
          const res = await fetch('/qr-meta?t=' + Date.now());
          if (res.ok) {
            const meta = await res.json();
            if (meta.timestamp && meta.timestamp !== lastTimestamp) {
              lastTimestamp = meta.timestamp;
              currentAttempt = meta.attempt;
              document.getElementById('qr').src = '/qr.png?t=' + Date.now();
              document.getElementById('status-text').innerHTML = 'Attempt #' + meta.attempt + ' &bull; Generated ' + meta.time;
            }
          }
        } catch (_) {}
      }

      const ageSec = Math.floor((Date.now() - lastTimestamp) / 1000);
      const indicator = document.getElementById('freshness-indicator');
      const timer = document.getElementById('timer-text');

      if (ageSec < 25) {
        indicator.className = 'freshness-badge freshness-fresh';
        indicator.innerHTML = '● ACTIVE (' + ageSec + 's old)';
        timer.innerHTML = 'Status: Fresh & Valid &bull; Time Remaining: ~' + Math.max(0, 25 - ageSec) + 's';
      } else {
        indicator.className = 'freshness-badge freshness-stale';
        indicator.innerHTML = '▲ ROTATING...';
        timer.innerHTML = 'Status: Rotating to fresh code... please wait a second';
      }
    }

    if (window.location.protocol === 'file:') {
      // In offline file viewing, reload after 25 seconds to pull new file content
      setTimeout(function() { window.location.reload(); }, 25000);
    } else {
      setInterval(checkFreshness, 1000);
    }
  </script>
</body>
</html>`;
      fs.writeFileSync(htmlPath, htmlContent, 'utf8');

      return { pngPath, htmlPath, metaPath, buffer: pngBuffer, dataUrl: qrDataUrl };
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
        console.log(`  Live Server: http://127.0.0.1:3900`);
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

    this.client.on('loading_screen', (percent, message) => {
      logger.info(`WhatsApp Web loading chats: ${percent}% (${message || 'syncing'})`);
    });

    this.client.on('change_state', (state) => {
      logger.info(`WhatsApp Web state changed: ${state}`);
    });

    this.client.on('authenticated', () => {
      this.reconnectAttempts = 0;
      logger.info('WhatsApp Web authenticated successfully from persistent LocalAuth store.');
    });

    this.client.on('ready', async () => {
      this.isReady = true;
      this.reconnectAttempts = 0;
      const accountMode = process.env.WA_ACCOUNT_MODE || 'development';
      const defaultLabel = accountMode === 'development' ? 'Developer Test Account' : 'Clinic Account';
      const pushName = this.client.info?.pushname || process.env.WA_ACCOUNT_LABEL || defaultLabel;
      const connectedPhone = this.client.info?.wid?.user || null;
      logger.info(`WhatsApp Web client is READY and connected! Account: +${connectedPhone || 'Unknown'} (${pushName}) [${accountMode.toUpperCase()}]`);
      await this._updateStatusInDb('authenticated', null, connectedPhone);

      // Start active message capture window now: ignore historical backfill
      try {
        const botEngine = require('./bot_engine');
        botEngine.setCaptureStartTime(Math.floor(Date.now() / 1000));
      } catch (_) {}

      // Setup periodic database heartbeat while connected
      if (this.heartbeatTimer) clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = setInterval(async () => {
        if (this.isReady) {
          await this._updateStatusInDb('authenticated', null, connectedPhone);
        }
      }, 60000);

      // Render persistent success confirmation in scan_qr.html
      try {
        const tempDir = path.join(__dirname, '../../.temp');
        const htmlPath = path.join(tempDir, 'scan_qr.html');
        const masked = connectedPhone && connectedPhone.length > 5 ? connectedPhone.substring(0, 2) + '******' + connectedPhone.slice(-3) : (connectedPhone || defaultLabel);
        const successHtml = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>MKES CARE+ — WhatsApp Connected</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; text-align: center; background: #0b141a; color: #e9edef; padding: 40px 16px; margin: 0; }
    .card { background: #111b21; max-width: 480px; margin: 0 auto; border-radius: 16px; padding: 32px 24px; box-shadow: 0 8px 32px rgba(0,0,0,0.6); border: 1px solid #222e35; }
    .icon { font-size: 56px; color: #25d366; margin-bottom: 12px; }
    h1 { font-size: 24px; margin: 0 0 8px 0; color: #25d366; }
    p { color: #8696a0; font-size: 14px; margin-bottom: 20px; line-height: 1.5; }
    .badge { background: #005c4b; color: #25d366; padding: 6px 16px; border-radius: 20px; font-weight: bold; font-size: 12px; display: inline-block; margin-bottom: 20px; }
    .phone { font-size: 18px; color: #e9edef; font-weight: bold; margin-bottom: 16px; }
    .info { font-size: 13px; color: #53bdeb; line-height: 1.6; }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">&#10004;</div>
    <div class="badge">DEVICE PAIRED & AUTHENTICATED</div>
    <h1>WhatsApp Connected</h1>
    <div class="phone">+${masked} (${pushName})</div>
    <p>Your WhatsApp development device has been linked successfully. Session credentials are securely persisted in local storage.</p>
    <div class="info">Patient-only inbox filtering is active. Personal chats are strictly dropped and never recorded.</div>
  </div>
</body>
</html>`;
        fs.writeFileSync(htmlPath, successHtml, 'utf8');
      } catch (_) {}
    });

    this.client.on('disconnected', async (reason) => {
      this.isReady = false;
      if (this.heartbeatTimer) {
        clearInterval(this.heartbeatTimer);
        this.heartbeatTimer = null;
      }
      logger.warn(`WhatsApp client disconnected: ${reason}`);

      if (reason === 'LOGOUT') {
        logger.warn('WhatsApp session was explicitly unlinked from physical device. Reauthentication required.');
        await this._updateStatusInDb('qr_ready');
      } else {
        // Transient network disconnection or sleep - preserve session data!
        await this._updateStatusInDb('disconnected');
        this._scheduleAutoReconnect(reason);
      }
    });

    this.client.on('auth_failure', async (msg) => {
      this.isReady = false;
      logger.error(`WhatsApp authentication failure: ${msg}. Session credentials may be invalid.`);
      await this._updateStatusInDb('error');
    });

    this.client.on('message', async (msg) => {
      if (!msg.fromMe) {
        for (const listener of this._messageListeners) {
          try {
            await listener(msg);
          } catch (err) {
            logger.error(`Unhandled error in WhatsApp message listener: ${err.message}`, err);
          }
        }
      }
    });

    this.client.on('message_create', async (msg) => {
      for (const listener of this._messageCreateListeners) {
        try {
          await listener(msg);
        } catch (err) {
          logger.error(`Unhandled error in WhatsApp message_create listener: ${err.message}`, err);
        }
      }
    });

    this.client.on('message_ack', async (msg, ack) => {
      const messageId = RecipientValidator.extractMessageId(msg);
      for (const listener of this._messageAckListeners) {
        try {
          await listener(msg, ack, messageId);
        } catch (err) {
          logger.error(`Unhandled error in WhatsApp message_ack listener: ${err.message}`, err);
        }
      }
    });
  }

  _scheduleAutoReconnect(reason) {
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      logger.error(`Exceeded maximum auto-reconnection attempts (${this.maxReconnectAttempts}). Daemon remains standby.`);
      return;
    }

    this.reconnectAttempts += 1;
    const delaySec = Math.min(10 * Math.pow(2, this.reconnectAttempts - 1), 60);
    logger.info(`Scheduling auto-reconnection attempt #${this.reconnectAttempts} in ${delaySec}s (reason: ${reason})...`);

    this.reconnectTimer = setTimeout(async () => {
      try {
        logger.info(`Executing auto-reconnection attempt #${this.reconnectAttempts}...`);
        if (this.client) {
          try {
            await this.client.destroy();
          } catch (_) {}
        }
        this.initialize();
      } catch (err) {
        logger.error(`Auto-reconnection failed: ${err.message}`);
      }
    }, delaySec * 1000);
  }

  async destroy() {
    this.isReady = false;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
    if (this.client) {
      try {
        await this.client.destroy();
        logger.info('WhatsApp client destroyed cleanly.');
      } catch (err) {
        logger.debug(`Client destroy error: ${err.message}`);
      }
    }
    instanceLock.releaseLock();
  }

  async _updateStatusInDb(status, qrData = null, connectedPhone = null) {
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
      if (connectedPhone) {
        payload.connected_phone = connectedPhone;
      }

      const { error } = await supabase
        .from('whatsapp_settings')
        .update(payload)
        .eq('id', '00000000-0000-0000-0000-000000000001');

      if (error) {
        // Silently handle if columns do not exist yet before pending migration
        if (error.code === 'PGRST204' || error.message?.includes('column')) {
          logger.debug(`Session status update note: ${error.message}`);
        } else {
          logger.warn(`Failed to update session status in DB: ${error.message}`);
        }
      }
    } catch (err) {
      logger.debug(`DB session status update skipped: ${err.message}`);
    }
  }

  /**
   * Humanized Message Dispatcher.
   * Simulates realistic presence and typing duration before sending message.
   */
  async sendMessageWithHumanizedDelay(toJid, messageText) {
    const isDryRun = String(process.env.DRY_RUN || 'true').trim().toLowerCase() !== 'false';

    // DRY_RUN safeguard: Simulate send when DRY_RUN=true
    if (isDryRun) {
      logger.info(`[DRY RUN SIMULATED] Outgoing message to ${toJid} safely simulated (DRY_RUN=true): "${messageText.replace(/\n/g, ' ').substring(0, 80)}..."`);
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

  /**
   * Humanized Document/Media Dispatcher.
   * Sends PDFs, images, or documents with optional caption and humanized delay.
   */
  async sendMediaWithHumanizedDelay(toJid, media, caption = '') {
    const isDryRun = String(process.env.DRY_RUN || 'true').trim().toLowerCase() !== 'false';

    // DRY_RUN safeguard: Simulate media send when DRY_RUN=true
    if (isDryRun) {
      logger.info(`[DRY RUN SIMULATED] Outgoing media to ${toJid} safely simulated (DRY_RUN=true): filename="${media?.filename || 'invoice.pdf'}", caption="${caption.replace(/\n/g, ' ').substring(0, 60)}..."`);
      return {
        id: { _serialized: `dry-run-media-${Date.now()}` },
        simulated: true,
        to: toJid,
        timestamp: Math.floor(Date.now() / 1000),
      };
    }

    if (!this.isReady) {
      throw new Error('WhatsApp client is not ready or authenticated.');
    }

    try {
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
            targetJid = prep.expectedJid;
          }
        }
      } catch (_) {}

      try {
        await this.client.sendPresenceAvailable();
      } catch (_) {}

      const options = {};
      if (caption) options.caption = caption;

      const response = await this.client.sendMessage(targetJid, media, options);
      return response;
    } catch (err) {
      logger.error(`Failed to send media to ${toJid}: ${err.message}`, err);
      throw err;
    }
  }

  /**
   * Attempts to resolve an opaque WhatsApp LID (e.g. 123456789012345@lid) to a verified phone number.
   * Returns standard WhatsApp phone JID (e.g. "919820012345@c.us") or null if unresolvable.
   */
  async resolveLidToPhone(lid) {
    if (!lid || typeof lid !== 'string' || !lid.endsWith('@lid')) {
      return null;
    }

    // 1. WhatsApp Web Client native resolution via getContactLidAndPhone
    if (this.client && typeof this.client.getContactLidAndPhone === 'function') {
      try {
        const results = await this.client.getContactLidAndPhone([lid]);
        if (Array.isArray(results) && results.length > 0 && results[0]?.pn) {
          const pn = results[0].pn;
          if (pn && typeof pn === 'string' && !pn.endsWith('@lid')) {
            return pn;
          }
        }
      } catch (err) {
        logger.debug(`Client getContactLidAndPhone failed for ${lid}: ${err.message}`);
      }
    }

    // 2. WhatsApp Web Client contact lookup
    if (this.client && typeof this.client.getContactById === 'function') {
      try {
        const contact = await this.client.getContactById(lid);
        if (contact && contact.number && typeof contact.number === 'string') {
          const clean = contact.number.replace(/[^0-9]/g, '');
          if (clean.length >= 10 && clean.length <= 13 && !contact.number.endsWith('@lid')) {
            return `${clean}@c.us`;
          }
        }
      } catch (_) {}
    }

    // 3. Database stored mapping in previous audit logs
    try {
      const { data: logEntry } = await supabase
        .from('whatsapp_message_logs')
        .select('phone_number, raw_payload')
        .eq('raw_payload->>sender_lid', lid)
        .neq('phone_number', lid)
        .limit(1)
        .maybeSingle();

      if (logEntry && logEntry.phone_number && !logEntry.phone_number.endsWith('@lid')) {
        return logEntry.phone_number;
      }
    } catch (_) {}

    return null;
  }
}

module.exports = new WhatsAppClientManager();
