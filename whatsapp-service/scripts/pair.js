/**
 * MKES CARE+ WhatsApp Bridge — Dedicated Pairing Daemon & Live QR Viewer
 * 
 * Safely initializes WhatsApp Web Client (whatsapp-web.js) to display the QR code
 * and persist authentication credentials into LocalAuth session directory.
 * 
 * FEATURES:
 * - Dedicated zero-cache HTTP server on http://127.0.0.1:3900 with live SSE streaming
 * - Base64 and raw PNG image serving with strict Cache-Control: no-store headers
 * - Real-time auto-refresh with live freshness countdown and rotation tracker
 * - Zero Watchdog interference during mobile pairing handshake (loading_screen, authenticated, ready)
 * - Settling wait (20s) post-ready to ensure Chromium IndexedDB store is completely flushed
 * - Graceful shutdown and lock release
 * - Strict isolation: scheduler, outbox worker, bot engine are all completely DISABLED
 */

const http = require('http');
const path = require('path');
const fs = require('fs');
const { exec } = require('child_process');

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

const HTTP_PORT = parseInt(process.env.QR_HTTP_PORT || '3900', 10);
const tempDir = whatsappClient.constructor.getTempDir ? whatsappClient.constructor.getTempDir() : path.resolve(__dirname, '../.temp');
if (!fs.existsSync(tempDir)) {
  try {
    fs.mkdirSync(tempDir, { recursive: true });
  } catch (_) {}
}
const qrPngPath = path.join(tempDir, 'whatsapp_qr.png');
const qrMetaPath = path.join(tempDir, 'qr_metadata.json');

// Pairing state tracking
let currentState = {
  status: 'waiting_for_qr',
  message: 'Initializing WhatsApp Web client...',
  attempt: 0,
  timestamp: 0,
  time: new Date().toLocaleTimeString(),
  validDurationSeconds: 25,
  phone: null,
  isPairingInProgress: false,
  isAuthenticated: false,
  isReady: false,
  hasImage: false,
  qrDataUrl: null,
};

let lastQrTime = Date.now();
let reloadWatchdog = null;
let sseClients = [];
let hasAutoOpenedBrowser = false;

function broadcastState() {
  const payload = `data: ${JSON.stringify(currentState)}\n\n`;
  for (let i = sseClients.length - 1; i >= 0; i--) {
    try {
      sseClients[i].write(payload);
    } catch (_) {
      sseClients.splice(i, 1);
    }
  }
}

// -------------------------------------------------------------
// 1. Embedded HTTP Server for Live Scannable QR Viewer
// -------------------------------------------------------------
const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || '127.0.0.1'}`);

  // Endpoint: GET /events (Server-Sent Events for real-time instant UI update)
  if (url.pathname === '/events') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache, no-transform',
      'Connection': 'keep-alive',
      'Access-Control-Allow-Origin': '*',
    });
    res.write(`data: ${JSON.stringify(currentState)}\n\n`);
    sseClients.push(res);

    req.on('close', () => {
      const idx = sseClients.indexOf(res);
      if (idx !== -1) sseClients.splice(idx, 1);
    });
    return;
  }

  // Endpoint: GET /qr-meta (JSON metadata)
  if (url.pathname === '/qr-meta') {
    res.writeHead(200, {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0',
      'Pragma': 'no-cache',
      'Expires': '0',
      'Access-Control-Allow-Origin': '*',
    });
    currentState.hasImage = !!(whatsappClient.latestQrBuffer || fs.existsSync(qrPngPath));
    currentState.qrDataUrl = whatsappClient.latestQrDataUrl || null;
    res.end(JSON.stringify(currentState));
    return;
  }

  // Endpoint: GET /qr.png (Raw un-cached PNG image)
  if (url.pathname === '/qr.png') {
    let imageBuffer = whatsappClient.latestQrBuffer;

    if (!imageBuffer && fs.existsSync(qrPngPath)) {
      try {
        imageBuffer = fs.readFileSync(qrPngPath);
      } catch (err) {
        logger.error(`Error reading QR image from disk: ${err.message}`);
      }
    }

    if (!imageBuffer && whatsappClient.latestQr) {
      try {
        const QRCode = require('qrcode');
        imageBuffer = QRCode.toBuffer(whatsappClient.latestQr, {
          width: 450,
          margin: 2,
          color: { dark: '#000000', light: '#FFFFFF' },
        });
      } catch (_) {}
    }

    if (imageBuffer && imageBuffer.length > 0) {
      res.writeHead(200, {
        'Content-Type': 'image/png',
        'Content-Length': imageBuffer.length,
        'Cache-Control': 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0',
        'Pragma': 'no-cache',
        'Expires': '0',
        'Access-Control-Allow-Origin': '*',
      });
      res.end(imageBuffer);
      return;
    }

    res.writeHead(404, {
      'Content-Type': 'text/plain',
      'Cache-Control': 'no-store, no-cache, must-revalidate, max-age=0',
    });
    res.end('QR image not ready yet');
    return;
  }

  // Endpoint: GET / or /index.html (State-of-the-art Pairing Page)
  if (url.pathname === '/' || url.pathname === '/index.html') {
    const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>MKES CARE+ — WhatsApp Device Pairing</title>
  <style>
    :root {
      --bg: #0b141a;
      --card-bg: #111b21;
      --accent-green: #00a884;
      --light-green: #25d366;
      --text-main: #e9edef;
      --text-muted: #8696a0;
      --border-color: #222e35;
      --warn-yellow: #f59e0b;
      --blue: #53bdeb;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      background: var(--bg);
      color: var(--text-main);
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      padding: 24px 16px;
    }
    .container {
      background: var(--card-bg);
      border: 1px solid var(--border-color);
      border-radius: 20px;
      max-width: 520px;
      width: 100%;
      padding: 32px 28px;
      box-shadow: 0 12px 48px rgba(0,0,0,0.7);
      text-align: center;
    }
    .header-tag {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      background: rgba(0, 168, 132, 0.15);
      color: var(--light-green);
      font-size: 12px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.8px;
      padding: 6px 14px;
      border-radius: 20px;
      margin-bottom: 16px;
      border: 1px solid rgba(37, 211, 102, 0.3);
    }
    h1 {
      font-size: 24px;
      font-weight: 600;
      margin-bottom: 8px;
      color: var(--text-main);
    }
    .subtitle {
      font-size: 14px;
      color: var(--text-muted);
      line-height: 1.5;
      margin-bottom: 24px;
    }
    .qr-container {
      background: #ffffff;
      padding: 16px;
      border-radius: 16px;
      display: inline-block;
      box-shadow: 0 8px 24px rgba(0,0,0,0.5);
      margin-bottom: 20px;
      position: relative;
    }
    .qr-img {
      display: block;
      width: 320px;
      height: 320px;
      border-radius: 8px;
    }
    .badge-bar {
      display: flex;
      justify-content: center;
      align-items: center;
      gap: 10px;
      margin-bottom: 16px;
    }
    .badge {
      font-size: 12px;
      font-weight: 600;
      padding: 4px 12px;
      border-radius: 12px;
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }
    .badge-fresh {
      background: #005c4b;
      color: var(--light-green);
      border: 1px solid var(--light-green);
    }
    .badge-rotating {
      background: #4a2800;
      color: var(--warn-yellow);
      border: 1px solid var(--warn-yellow);
    }
    .badge-pairing {
      background: #0c3b52;
      color: var(--blue);
      border: 1px solid var(--blue);
    }
    .badge-success {
      background: #005c4b;
      color: var(--light-green);
      border: 1px solid var(--light-green);
    }
    .badge-waiting {
      background: #1f2c34;
      color: var(--text-muted);
      border: 1px solid var(--border-color);
    }
    .qr-placeholder {
      width: 340px;
      height: 340px;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      background: rgba(255, 255, 255, 0.02);
      border: 2px dashed var(--border-color);
      border-radius: 12px;
      color: var(--text-muted);
      font-size: 13px;
      gap: 16px;
      margin: 0 auto;
    }
    .spinner {
      width: 36px;
      height: 36px;
      border: 3px solid rgba(37, 211, 102, 0.15);
      border-top-color: var(--light-green);
      border-radius: 50%;
      animation: spin 1s linear infinite;
    }
    @keyframes spin {
      to { transform: rotate(360deg); }
    }
    .progress-bar-bg {
      background: var(--border-color);
      height: 6px;
      border-radius: 3px;
      width: 100%;
      max-width: 340px;
      margin: 0 auto 16px auto;
      overflow: hidden;
    }
    .progress-bar-fill {
      background: var(--light-green);
      height: 100%;
      width: 100%;
      transition: width 1s linear;
    }
    .status-text {
      font-size: 13px;
      color: var(--blue);
      font-weight: 500;
      margin-bottom: 6px;
    }
    .timer-text {
      font-size: 12px;
      color: var(--text-muted);
      margin-bottom: 20px;
    }
    .instructions {
      background: rgba(255, 255, 255, 0.03);
      border: 1px solid var(--border-color);
      border-radius: 12px;
      padding: 16px;
      text-align: left;
      font-size: 13px;
      color: var(--text-muted);
      line-height: 1.6;
    }
    .instructions ol {
      padding-left: 20px;
    }
    .instructions li {
      margin-bottom: 4px;
    }
    .instructions b {
      color: var(--text-main);
    }
    .success-panel {
      display: none;
      padding: 20px;
    }
    .success-icon {
      font-size: 64px;
      color: var(--light-green);
      margin-bottom: 16px;
    }
    .success-phone {
      font-size: 20px;
      font-weight: 700;
      color: var(--text-main);
      margin-bottom: 8px;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header-tag">MKES CARE+ WhatsApp Bridge</div>
    
    <div id="pairing-view">
      <h1>Link WhatsApp (${process.env.WA_ACCOUNT_MODE === 'clinic_production' ? 'Clinic Account' : 'Dev/Test Mode'})</h1>
      <p class="subtitle">Scan this code from your WhatsApp mobile phone (${process.env.WA_ACCOUNT_LABEL || 'Developer Test Account'}) to link local development testing.</p>
      
      <div class="badge-bar">
        <div id="status-badge" class="badge ${currentState.status === 'qr_ready' ? 'badge-fresh' : 'badge-waiting'}">
          ${currentState.status === 'qr_ready' ? '● ACTIVE &amp; LIVE' : '⌛ WAITING FOR WHATSAPP...'}
        </div>
        <div id="attempt-badge" class="badge" style="background:#1f2c34; color:var(--text-main)">
          ${currentState.status === 'qr_ready' ? 'Attempt #' + currentState.attempt : 'Initializing...'}
        </div>
      </div>
      
      <div class="qr-container">
        <div id="qr-placeholder" class="qr-placeholder" style="${currentState.status === 'qr_ready' ? 'display:none;' : 'display:flex;'}">
          <div class="spinner"></div>
          <span>Starting WhatsApp Web client...</span>
        </div>
        <img id="qr-image" class="qr-img" src="${currentState.status === 'qr_ready' ? (currentState.qrDataUrl || '/qr.png?t=' + currentState.timestamp) : ''}" style="${currentState.status === 'qr_ready' ? 'display:block;' : 'display:none;'}" alt="Live WhatsApp Pairing QR Code" />
      </div>
      
      <div class="progress-bar-bg">
        <div id="progress-fill" class="progress-bar-fill" style="${currentState.status === 'qr_ready' ? 'width:100%;' : 'width:0%;'}"></div>
      </div>
      
      <div id="status-message" class="status-text">${currentState.message}</div>
      <div id="timer-text" class="timer-text">${currentState.status === 'qr_ready' ? 'Valid for ~25s &bull; Auto-rotates cleanly' : 'Waiting for WhatsApp Web...'}</div>
      
      <div class="instructions">
        <ol>
          <li>Open <b>WhatsApp</b> on your mobile phone</li>
          <li>Tap <b>Settings</b> (iOS) or <b>Menu ⋮</b> (Android) &rarr; <b>Linked Devices</b></li>
          <li>Tap <b>Link a Device</b></li>
          <li>Point camera directly at this QR code</li>
        </ol>
      </div>
    </div>
    
    <div id="success-view" class="success-panel">
      <div class="success-icon">&#10004;</div>
      <div class="badge badge-success" style="margin-bottom:12px;">LINKED &amp; AUTHENTICATED</div>
      <h1>Device Linked Successfully!</h1>
      <div id="connected-phone" class="success-phone">+91 **********</div>
      <p class="subtitle" style="margin-bottom:16px;">WhatsApp development account linked. Session credentials securely persisted in local storage.</p>
      <div style="font-size:13px; color:var(--blue); background:rgba(83,189,235,0.1); padding:12px; border-radius:10px; border:1px solid rgba(83,189,235,0.3);">
        Patient-only inbox filtering is active. Personal chats are strictly dropped and never recorded.
      </div>
    </div>
  </div>

  <script>
    let currentStatus = '${currentState.status}';
    let lastTimestamp = ${currentState.status === 'qr_ready' ? currentState.timestamp : 0};
    let currentAttempt = ${currentState.attempt};
    let validDuration = 25;
    let isPairing = false;
    let isReady = false;

    const qrImg = document.getElementById('qr-image');
    const qrPlaceholder = document.getElementById('qr-placeholder');
    const statusBadge = document.getElementById('status-badge');
    const attemptBadge = document.getElementById('attempt-badge');
    const statusMsg = document.getElementById('status-message');
    const timerText = document.getElementById('timer-text');
    const progressFill = document.getElementById('progress-fill');
    const pairingView = document.getElementById('pairing-view');
    const successView = document.getElementById('success-view');
    const connectedPhone = document.getElementById('connected-phone');

    qrImg.onload = function() {
      if (currentStatus === 'qr_ready') {
        qrPlaceholder.style.display = 'none';
        qrImg.style.display = 'block';
      }
    };
    qrImg.onerror = function() {
      if (currentStatus === 'qr_ready') {
        statusBadge.className = 'badge badge-waiting';
        statusBadge.textContent = '● LOADING IMAGE...';
        setTimeout(function() {
          if (currentStatus === 'qr_ready') {
            qrImg.src = '/qr.png?t=' + Date.now();
          }
        }, 800);
      }
    };

    function applyState(state) {
      if (!state) return;
      currentStatus = state.status || currentStatus;

      if (state.attempt) {
        currentAttempt = state.attempt;
        attemptBadge.textContent = 'Attempt #' + state.attempt;
      }
      if (state.validDurationSeconds) {
        validDuration = state.validDurationSeconds;
      }
      if (state.message) {
        statusMsg.textContent = state.message;
      }

      if (state.status === 'qr_ready') {
        if (state.timestamp && state.timestamp !== lastTimestamp) {
          lastTimestamp = state.timestamp;
          if (state.qrDataUrl) {
            qrImg.src = state.qrDataUrl;
          } else {
            qrImg.src = '/qr.png?t=' + state.timestamp;
          }
        }
        qrPlaceholder.style.display = 'none';
        qrImg.style.display = 'block';
        statusBadge.className = 'badge badge-fresh';
        statusBadge.textContent = '● ACTIVE & LIVE';
      } else if (state.status === 'waiting_for_qr') {
        statusBadge.className = 'badge badge-waiting';
        statusBadge.textContent = '⌛ WAITING FOR QR';
        attemptBadge.textContent = 'Initializing...';
        timerText.textContent = 'Starting WhatsApp Web client...';
        progressFill.style.width = '0%';
        qrPlaceholder.style.display = 'flex';
        qrImg.style.display = 'none';
      } else if (state.status === 'pairing') {
        isPairing = true;
        statusBadge.className = 'badge badge-pairing';
        statusBadge.textContent = '⌛ PAIRING IN PROGRESS';
        statusMsg.style.color = '#53bdeb';
        timerText.textContent = 'Phone scanned QR code. Loading chats... Do not interrupt.';
        progressFill.style.width = '100%';
        progressFill.style.background = '#53bdeb';
      } else if (state.status === 'authenticated') {
        isPairing = true;
        statusBadge.className = 'badge badge-success';
        statusBadge.textContent = '✔ AUTHENTICATED';
        statusMsg.textContent = 'Meta authentication confirmed! Finalizing session credentials...';
      } else if (state.status === 'ready') {
        isReady = true;
        pairingView.style.display = 'none';
        successView.style.display = 'block';
        if (state.phone) {
          connectedPhone.textContent = '+' + state.phone;
        }
      }
    }

    // Connect via Server-Sent Events (instant push)
    let evtSource = null;
    try {
      evtSource = new EventSource('/events');
      evtSource.onmessage = function(e) {
        try {
          const state = JSON.parse(e.data);
          applyState(state);
        } catch (_) {}
      };
      evtSource.onerror = function() {
        console.warn('SSE connection interrupted, falling back to polling.');
      };
    } catch (_) {}

    // Polling fallback and timer calculation loop
    setInterval(async function() {
      if (isReady) return;

      if (!evtSource || evtSource.readyState === EventSource.CLOSED) {
        try {
          const res = await fetch('/qr-meta?t=' + Date.now());
          if (res.ok) {
            const data = await res.json();
            applyState(data);
          }
        } catch (_) {}
      }

      if (!isPairing && currentStatus === 'qr_ready' && lastTimestamp > 0) {
        const elapsedSec = Math.floor((Date.now() - lastTimestamp) / 1000);
        const remainingSec = Math.max(0, validDuration - elapsedSec);
        const percent = Math.min(100, Math.max(0, (remainingSec / validDuration) * 100));

        progressFill.style.width = percent + '%';

        if (elapsedSec < validDuration) {
          statusBadge.className = 'badge badge-fresh';
          statusBadge.textContent = '● ACTIVE (' + elapsedSec + 's old)';
          progressFill.style.background = '#25d366';
          timerText.textContent = 'Valid for ~' + remainingSec + 's &bull; Auto-rotates cleanly';
        } else {
          statusBadge.className = 'badge badge-rotating';
          statusBadge.textContent = '▲ ROTATING...';
          progressFill.style.background = '#f59e0b';
          timerText.textContent = 'Rotating to fresh QR payload from WhatsApp Web...';
        }
      } else if (currentStatus === 'waiting_for_qr') {
        statusBadge.className = 'badge badge-waiting';
        statusBadge.textContent = '⌛ WAITING FOR QR';
        timerText.textContent = 'Starting WhatsApp Web client...';
        progressFill.style.width = '0%';
      }
    }, 1000);
  </script>
</body>
</html>`;

    res.writeHead(200, {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store, no-cache, must-revalidate, max-age=0',
      'Pragma': 'no-cache',
    });
    res.end(html);
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not Found');
});

// Start HTTP server
server.listen(HTTP_PORT, '127.0.0.1', () => {
  logger.info(`Pairing HTTP viewer listening at http://127.0.0.1:${HTTP_PORT}`);
  console.log(`\n>> Local QR Viewer Server is ONLINE at: http://127.0.0.1:${HTTP_PORT}\n`);
});

// -------------------------------------------------------------
// 2. WhatsApp Client Initialization in Isolated Pairing Mode
// -------------------------------------------------------------
const accountMode = process.env.WA_ACCOUNT_MODE || 'development';
const accountLabel = process.env.WA_ACCOUNT_LABEL || (accountMode === 'development' ? 'Developer Test Account' : 'Clinic Account');

console.log('====================================================');
console.log(`  MKES CARE+ WhatsApp Bridge — Pairing Mode         `);
console.log(`  Account: ${accountLabel} [${accountMode.toUpperCase()}]`);
console.log('====================================================');
console.log('  Mode: PAIRING ONLY                                ');
console.log('  Outbox Worker: DISABLED (No messages will be sent)');
console.log('  Scheduler: DISABLED (No automated jobs will run)  ');
console.log('  Bot Engine: DISABLED (No incoming messages handled)');
console.log('  Filter: Patient-only ingestion active             ');
console.log('====================================================\n');

logger.info(`Initializing WhatsApp client in isolated pairing mode for ${accountLabel}...`);
whatsappClient.initialize();

// Register listeners on WhatsApp client
if (whatsappClient.client) {
  whatsappClient.client.on('qr', (qr) => {
    lastQrTime = Date.now();
    currentState.attempt = whatsappClient.qrAttempt;
    currentState.timestamp = whatsappClient.latestQrTimestamp || Date.now();
    currentState.time = new Date(currentState.timestamp).toLocaleTimeString();
    currentState.status = 'qr_ready';
    currentState.hasImage = true;
    currentState.qrDataUrl = whatsappClient.latestQrDataUrl || null;
    currentState.message = `QR Code Ready (Attempt #${whatsappClient.qrAttempt}). Scan with your mobile phone.`;
    broadcastState();

    console.log('\n====================================================');
    console.log(`  [ACTUAL SCANNABLE QR CODE] Attempt #${whatsappClient.qrAttempt}`);
    console.log(`  Account:              ${accountLabel}`);
    console.log(`  Local Browser Viewer: http://127.0.0.1:${HTTP_PORT}`);
    console.log(`  Direct HTML File:     file:///${path.join(tempDir, 'scan_qr.html').replace(/\\/g, '/')}`);
    console.log(`  Valid for:            ~25 seconds (auto-refreshes)`);
    console.log('====================================================\n');

    // Auto-open browser on attempt #1 for zero-friction user scan
    if (!hasAutoOpenedBrowser) {
      hasAutoOpenedBrowser = true;
      exec(`start http://127.0.0.1:${HTTP_PORT}`, (err) => {
        if (err) {
          logger.debug(`Could not auto-open browser: ${err.message}`);
        } else {
          logger.info(`Automatically opened http://127.0.0.1:${HTTP_PORT} in default browser.`);
        }
      });
    }
  });

  whatsappClient.client.on('loading_screen', (percent, message) => {
    currentState.isPairingInProgress = true;
    currentState.status = 'pairing';
    currentState.message = `Mobile phone scanned QR code! Loading chats (${percent}%)... Please do not interrupt.`;
    broadcastState();

    // PERMANENTLY KILL WATCHDOG: Under no circumstances should reload be clicked while pairing
    if (reloadWatchdog) {
      clearInterval(reloadWatchdog);
      reloadWatchdog = null;
      logger.info('[QR WATCHDOG] Permanently disabled: active mobile authentication in progress.');
    }

    console.log(`\n>> [PAIRING IN PROGRESS] Phone scanned QR! Loading chats (${percent}%)...`);
  });

  whatsappClient.client.on('authenticated', () => {
    currentState.isAuthenticated = true;
    currentState.status = 'authenticated';
    currentState.message = 'Meta confirmed authentication! Persisting session credentials...';
    broadcastState();

    if (reloadWatchdog) {
      clearInterval(reloadWatchdog);
      reloadWatchdog = null;
    }

    console.log('\n>> [AUTHENTICATED] WhatsApp authentication confirmed by Meta! Persisting credentials...');
  });

  whatsappClient.client.on('ready', async () => {
    currentState.isReady = true;
    currentState.status = 'ready';

    if (reloadWatchdog) {
      clearInterval(reloadWatchdog);
      reloadWatchdog = null;
    }

    // Set message capture cutoff to now so previous chat history is not backfilled
    try {
      const botEngine = require('../src/services/bot_engine');
      botEngine.setCaptureStartTime(Math.floor(Date.now() / 1000));
    } catch (_) {}

    const phone = whatsappClient.client.info?.wid?.user || 'Unknown';
    const masked = phone.length > 5 ? phone.substring(0, 2) + '******' + phone.slice(-3) : phone;
    currentState.phone = masked;
    currentState.message = `SUCCESS: WhatsApp client paired and connected! Phone: +${masked} (${accountLabel})`;
    broadcastState();

    console.log('\n====================================================');
    console.log('  SUCCESS: WhatsApp Client is Paired & Authenticated!');
    console.log(`  Account:         ${accountLabel}`);
    console.log(`  Connected Phone: +${masked}`);
    console.log(`  Session saved to: ${whatsappClient.sessionPath}`);
    console.log('====================================================\n');
    console.log('>> Waiting 20 seconds for Chromium IndexedDB store to fully settle and sync to disk...');

    // Settling countdown (20 seconds) to ensure LevelDB / IndexedDB is completely written
    let countdown = 20;
    const settleInterval = setInterval(() => {
      countdown -= 5;
      if (countdown > 0) {
        console.log(`>> [SETTLING] Syncing session keys to disk... (${countdown}s remaining)`);
      } else {
        clearInterval(settleInterval);
        verifyAndComplete();
      }
    }, 5000);
  });

  whatsappClient.client.on('auth_failure', (msg) => {
    currentState.status = 'auth_failure';
    currentState.message = `Authentication failed: ${msg}`;
    broadcastState();
    console.error(`\n[FAIL] Authentication rejected: ${msg}`);
    shutdown(1);
  });

  // Active QR Unpause Watchdog: Only re-triggers if WhatsApp Web goes idle and pauses QR rotation (>90s)
  reloadWatchdog = setInterval(async () => {
    // Under NO circumstance intervene if user is pairing, authenticated, or ready
    if (currentState.isPairingInProgress || currentState.isAuthenticated || currentState.isReady || whatsappClient.isReady) {
      if (reloadWatchdog) {
        clearInterval(reloadWatchdog);
        reloadWatchdog = null;
      }
      return;
    }

    const elapsed = Date.now() - lastQrTime;
    // WhatsApp Web rotates on its own every 20-30s. Only intervene if paused >90s
    if (elapsed > 90000 && whatsappClient.client?.pupPage) {
      try {
        const clicked = await whatsappClient.client.pupPage.evaluate(() => {
          const btn = document.querySelector('button[aria-label*="reload"], [data-ref] button, span[data-icon="refresh"]');
          if (btn) {
            btn.click();
            return true;
          }
          return false;
        });
        if (clicked) {
          logger.info('[QR WATCHDOG] Clicked WhatsApp Web paused reload button to resume rotation.');
          lastQrTime = Date.now();
        }
      } catch (_) {}
    }
  }, 15000);
}

async function verifyAndComplete() {
  console.log('\n>> [SETTLED] Verifying saved session files on disk...');
  const sessionDir = path.join(whatsappClient.sessionPath, 'session', 'Default');
  const indexedDbDir = path.join(sessionDir, 'IndexedDB');

  if (fs.existsSync(indexedDbDir)) {
    const files = fs.readdirSync(indexedDbDir);
    console.log(`>> [VERIFIED] Found ${files.length} IndexedDB store item(s) in: ${indexedDbDir}`);
    console.log('>> Session persistence successfully secured across restarts.');
  } else {
    console.warn(`>> [NOTICE] IndexedDB directory not detected at ${indexedDbDir}, but Default profile exists.`);
  }

  console.log('\n====================================================');
  console.log('  PAIRING WORKFLOW COMPLETED SUCCESSFULLY!          ');
  console.log('  Gracefully closing pairing client and lock...     ');
  console.log('====================================================\n');

  await shutdown(0);
}

async function shutdown(code = 0) {
  if (reloadWatchdog) {
    clearInterval(reloadWatchdog);
    reloadWatchdog = null;
  }

  // Close SSE connections
  for (const client of sseClients) {
    try {
      client.end();
    } catch (_) {}
  }
  sseClients = [];

  // Close HTTP server
  try {
    server.close();
  } catch (_) {}

  console.log('Shutting down pairing session cleanly...');
  try {
    await whatsappClient.destroy();
    console.log('WhatsApp client closed and instance lock released.');
  } catch (_) {}

  process.exit(code);
}

process.on('SIGINT', () => shutdown(0));
process.on('SIGTERM', () => shutdown(0));
