const path = require('path');
const fs = require('fs');

let admin = null;
let isConfigured = false;
let serviceAccountData = null;

// Resolve service account key:
// 1. Check raw JSON string or file path from FIREBASE_SERVICE_ACCOUNT_KEY
const envKey = process.env.FIREBASE_SERVICE_ACCOUNT_KEY;
if (envKey) {
  const trimmed = envKey.trim();
  if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
    try {
      serviceAccountData = JSON.parse(trimmed);
    } catch (_) {}
  } else if (fs.existsSync(trimmed)) {
    try {
      serviceAccountData = JSON.parse(fs.readFileSync(trimmed, 'utf8'));
    } catch (_) {}
  }
}

// 2. Check GOOGLE_APPLICATION_CREDENTIALS path
if (!serviceAccountData && process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  const gPath = process.env.GOOGLE_APPLICATION_CREDENTIALS.trim();
  if (fs.existsSync(gPath)) {
    try {
      serviceAccountData = JSON.parse(fs.readFileSync(gPath, 'utf8'));
    } catch (_) {}
  }
}

// 3. Check default path: config/firebase-service-account.json
const defaultPath = path.join(__dirname, '../../config/firebase-service-account.json');
if (!serviceAccountData && fs.existsSync(defaultPath)) {
  try {
    serviceAccountData = JSON.parse(fs.readFileSync(defaultPath, 'utf8'));
  } catch (_) {}
}

if (serviceAccountData && serviceAccountData.project_id) {
  try {
    admin = require('firebase-admin');
    if (!admin.apps || admin.apps.length === 0) {
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccountData),
      });
    }
    isConfigured = true;
  } catch (err) {
    admin = null;
    isConfigured = false;
  }
}

module.exports = {
  firebaseAdmin: admin,
  isConfigured,
  serviceAccountPath: fs.existsSync(defaultPath) ? defaultPath : null,
};
