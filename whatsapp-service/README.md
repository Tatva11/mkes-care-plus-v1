# MKES CARE+ — WhatsApp Integration Service

**Version:** 1.0.0  
**Target Environments:** Development / Test Host (Personal Phone & PC) & Production Clinic Host (Clinic Reception PC & WhatsApp)  
**Target Departments:** Eye Clinic & Dental Care (*Optical strictly excluded*)

---

## 1. Overview & Dual Account Architecture

The MKES CARE+ WhatsApp Bridge Daemon is a dedicated Node.js microservice powered by `whatsapp-web.js` that integrates WhatsApp messaging with Supabase while strictly enforcing patient privacy.

### Configurable Operating Modes:
- **`development` (Active Development Mode):**  
  Uses the developer's personal WhatsApp account on their personal phone and computer. In this mode:
  - The connected WhatsApp account is treated as a temporary development/test account, **NOT** the permanent clinic account.
  - No clinic phone numbers are hardcoded or assumed.
  - Strict in-memory privacy filtering ensures the developer's personal chats, groups, and family contacts are never mirrored or logged into Supabase.
- **`clinic_production` (Eventual Production Mode):**  
  Switches the service to the dedicated clinic phone number and reception Windows PC simply by setting `WA_ACCOUNT_MODE=clinic_production` in `.env`.

---

## 2. Strict Patient Privacy & Ingestion Boundaries

MKES CARE+ enforces an in-memory privacy pipeline before any database operation:

1. **Patient-Only Ingestion:**
   - Inbound and device-sent messages are accepted **only** if the sender or recipient matches a verified, registered patient in the Supabase `patients` table.
   - Phone numbers are normalized to 10 national digits before matching.
   - Personal contacts, unknown senders, groups (`@g.us`), broadcasts (`@broadcast`), and channels (`@newsletter`) are dropped in memory before reaching the database.
   - Unmatched senders never trigger automatic patient creation.
2. **Safe LID Handling:**
   - WhatsApp Linked Identity (`@lid`) chats are resolved through the client phone mapping. If unresolvable, the message is dropped rather than guessing patient identity.
3. **New Messages Only (Zero Historical Backfill):**
   - Only messages received after the session startup or pairing timestamp (`WA_CAPTURE_START_TIMESTAMP`) are captured.
   - Past personal or business chats are never imported or backfilled.
4. **Message Deduplication:**
   - In-memory message ID cache and database idempotency guards prevent duplicate processing across reconnects.
5. **Opt-Out vs Staff Visibility:**
   - Patients who send `STOP`, `UNSUBSCRIBE`, or `OPTOUT` are registered as opted out. Automated reminder outbox dispatches and conversational bot replies are suppressed.
   - Subsequent inbound messages from opted-out patients remain visible to authorized clinic staff in the Flutter inbox for manual clinical follow-up.
   - Staff replies in Flutter and SQL RPCs are strictly restricted to registered patients.

---

## 3. Environment Configuration

Copy `.env.example` to `.env` and configure:

```ini
# Supabase Backend Configuration
SUPABASE_URL=https://mfalgfodhsszyxnfiofi.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your_supabase_service_role_key_here

# Persistent WhatsApp Web Session Directory
WA_SESSION_PATH=C:\MKES_CARE_PLUS\wa_session

# Account Operating Mode: 'development' or 'clinic_production'
WA_ACCOUNT_MODE=development
WA_ACCOUNT_LABEL=Developer Test Account

# Privacy Guard (Strict Patient-Only Inbox)
PATIENT_ONLY_INBOX=true
WA_CAPTURE_START_TIMESTAMP=0

# Safety Guard: DRY_RUN=true simulates dispatch without sending real messages
DRY_RUN=true
TEST_PHONE_WHITELIST=8080030111
```

---

## 4. Pairing & Live QR Server

To link your phone for development or production:

1. Launch the dedicated pairing daemon:
   ```cmd
   npm run pair
   ```
2. Open the zero-cache live pairing server:
   - Navigate to [http://127.0.0.1:3900](http://127.0.0.1:3900) in your web browser.
3. On your mobile phone:
   - Open **WhatsApp** &rarr; **Settings / Menu ⋮** &rarr; **Linked Devices** &rarr; **Link a Device**.
   - Scan the QR code displayed on the screen.
4. Once linked, the daemon automatically settles and closes cleanly.
5. Verify session persistence at any time:
   ```cmd
   npm run verify-session
   ```

---

## 5. Running the Service

Start the full WhatsApp service:
```cmd
npm start
```

### Production Windows Service (Clinic Reception Host)
To register the service to auto-start on Windows boot:
```cmd
scripts\install_windows_service.bat
```
PM2 commands:
- `pm2 status`
- `pm2 logs mkes-wa-bridge`
- `pm2 restart mkes-wa-bridge`
- `pm2 stop mkes-wa-bridge`

---

## 6. Testing & Verification

Run the comprehensive test suites:
```cmd
# Patient Inbox Privacy & Account Configuration (34 tests)
node tests/patient_inbox_privacy_and_account_tests.js

# Consolidated Security & Concurrency (16 tests)
node tests/consolidated_security_and_concurrency_tests.js

# Session Persistence & Locking (19 tests)
node tests/session_persistence_tests.js

# Sprint 10 Functional Verification (17 tests)
node tests/sprint10_five_issues_verification_test.js
```
