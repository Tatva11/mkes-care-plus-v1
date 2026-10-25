# MKES CARE+ — Production Deployment & Operations Guide
## WhatsApp Automation & Conversational Appointment Booking

**Authoritative Target**: MKES CARE+ Hospital, Malad West, Mumbai  
**Clinical Scope**: Eye Clinic (Ophthalmology) & Dental Care (*Optical strictly excluded*)  
**Architecture**: Cloud Supabase Database (PostgreSQL 15+) + Clinic Windows PC Host (Node.js 18+ Daemon with `whatsapp-web.js`) + Flutter Cross-Platform Client

---

## 1. Architecture & Technology Confirmation

### Confirmed WhatsApp Library
- **Library**: `whatsapp-web.js` (version `^1.26.0`) with Chromium/Puppeteer and `LocalAuth`.
- **Clarification**: Early development notes occasionally mentioned alternative headless protocols (such as Baileys). The actual codebase, dependency definitions, and source files (`package.json`, `src/services/whatsapp_client.js`) have always utilized **`whatsapp-web.js`**. There is no dependency on Baileys, and no library switch is needed or recommended.
- **Session Strategy**: Puppeteer operates in headless mode with persistent session storage managed by `LocalAuth` located at `C:\MKES_CARE_PLUS\wa_session`.

---

## 2. Pre-Deployment Verification Summary (Local)

The entire backend and client implementation has been verified in local isolated environments:
- **Compiled PostgreSQL WASM 18.6**: 9/9 database test suites passed (migration execution, table constraints, direct update trigger guard, dynamic slot generator, dual advisory lock approval RPC, outbox batch claims, opt-out cancellation, scheduled batch enqueuers, and chat session JSONB persistence).
- **Node.js Integration Suite**: 93/93 unit tests passed across 17 test suites (phone normalization, collision math, crash recovery, status guard, doctor eligibility, opt-out races, slot inputs, privilege matrix, DRY_RUN lifecycle, IST date choice 1/2/3, debouncing, optical exclusion, and duplicate request prevention).
- **Flutter Codebase**: `flutter analyze` reports **0 issues found** across all models, providers, and dashboard screens.
- **Node.js Syntax**: 12/12 JavaScript files compile with zero syntax errors.

---

## 3. Production Deployment Checklist (Step-by-Step)

> [!IMPORTANT]
> **Safety Notice:** Do NOT perform these steps until you receive separate, explicit user approval to touch the live Supabase database or pair the clinic WhatsApp account.

```mermaid
graph TD
    A[Step 1: Database Backup Snapshot] --> B[Step 2: Apply Migration to Supabase]
    B --> C[Step 3: Windows PC Host Node.js Setup]
    C --> D[Step 4: Configure .env with Service Role Key]
    D --> E[Step 5: Run Preflight Validation]
    E --> F[Step 6: First-Time QR Code Device Pairing]
    F --> G[Step 7: Controlled DRY_RUN Testing]
    G --> H[Step 8: Live Production Go-Live]
```

### Step 1: Database Backup Snapshot
1. Log in to the [Supabase Dashboard](https://supabase.com/dashboard/project/mfalgfodhsszyxnfiofi).
2. Navigate to **Database** → **Backups**.
3. Create a manual point-in-time backup or export a schema/data dump:
   ```bash
   supabase db dump -f mkes_care_plus_pre_whatsapp_backup.sql
   ```

### Step 2: Apply Database Migration
1. Review the migration file:
   [`supabase/migrations/20261019000000_whatsapp_automation_foundation.sql`](file:///c:/MKES%20PRO/mkes-care-plus-lovable/supabase/migrations/20261019000000_whatsapp_automation_foundation.sql)
2. Apply the migration using Supabase CLI:
   ```bash
   supabase db push
   ```
   *Or* copy the contents into the Supabase Dashboard **SQL Editor** and run.
3. Confirm tables created:
   - `public.whatsapp_settings`
   - `public.whatsapp_templates`
   - `public.whatsapp_messages_outbox`
   - `public.whatsapp_message_logs`
   - `public.whatsapp_chat_sessions`
   - `public.whatsapp_appointment_requests`
4. Confirm columns added:
   - `public.appointments.duration_minutes` (default 15)
   - `public.appointments.ai_booked` (default false)
   - `public.patients.whatsapp_opt_out` (default false)

### Step 3: Clinic Windows PC Setup
1. Host requirements:
   - Windows 10/11 Pro or Windows Server on clinic reception PC.
   - Node.js LTS (v18.x or v20.x) installed from [nodejs.org](https://nodejs.org).
   - Google Chrome installed (for Puppeteer browser engine).
   - PM2 process manager installed globally:
     ```cmd
     npm install -g pm2
     ```
2. Create persistent session folder:
   ```cmd
   mkdir C:\MKES_CARE_PLUS\wa_session
   ```
3. Secure folder permissions:
   - Restrict read/write permissions to the Administrator and the local Windows user account running the clinic reception desktop.

### Step 4: Configure Production Secrets (`.env`)
1. In `whatsapp-service/`:
   ```cmd
   copy .env.example .env
   ```
2. Edit `.env` with actual production secrets:
   ```ini
   SUPABASE_URL=https://mfalgfodhsszyxnfiofi.supabase.co
   SUPABASE_SERVICE_ROLE_KEY=<production_service_role_secret>
   WA_SESSION_PATH=C:\MKES_CARE_PLUS\wa_session
   MIN_SEND_DELAY_MS=6000
   MAX_SEND_DELAY_MS=14000
   TYPING_SIMULATION_MS=2500
   DAILY_SEND_LIMIT=200
   OUTBOX_POLL_INTERVAL_MS=5000
   SCHEDULER_MODE=host
   DRY_RUN=true
   TEST_PHONE_WHITELIST=9876543210
   LOG_LEVEL=info
   ```
   > [!WARNING]
   > Ensure `.env` is listed in `.gitignore` and NEVER committed to GitHub or embedded in Flutter client builds.

### Step 5: Install Dependencies & Run Preflight Validation
1. Install Node.js dependencies:
   ```cmd
   npm install
   ```
2. Execute the preflight diagnostic:
   ```cmd
   npm run validate
   ```
3. Confirm output: **14 / 14 checks passed (READY for Windows background service deployment)**.

### Step 6: Initial WhatsApp Device Pairing
1. Start the service interactively:
   ```cmd
   npm start
   ```
2. A QR code will display in the terminal window:
   ```
   [INFO] WhatsApp QR Code generated. Scan with clinic smartphone to pair:
   ```
3. On the clinic reception smartphone:
   - Open WhatsApp.
   - Tap **Linked Devices** → **Link a Device**.
   - Point the camera at the terminal QR code.
4. When connected, the terminal logs:
   ```
   [INFO] WhatsApp Web client is READY and connected!
   ```
5. Press `Ctrl + C` to stop the interactive session. All credentials are now securely cached in `C:\MKES_CARE_PLUS\wa_session`.

### Step 7: Controlled Staging Test (`DRY_RUN=true`)
1. Keep `DRY_RUN=true` and `TEST_PHONE_WHITELIST=<clinic_admin_phone>`.
2. Start the service with PM2:
   ```cmd
   pm2 start index.js --name mkes-wa-bridge
   pm2 save
   ```
3. Send a test message from the whitelisted smartphone:
   - Send: `Hi`
   - Bot replies: `👋 Welcome to MKES CARE+ Hospital! Would you like to schedule an appointment with our Eye Clinic or Dental Care? 1 — Today, 2 — Tomorrow, 3 — Choose from upcoming dates`
   - Reply: `1`
   - Bot presents available 15-minute slots: `1 — 10:00 AM, 2 — 10:15 AM, 3 — 10:30 AM...`
   - Reply: `1`
   - Bot confirms request submission: `📋 Request Submitted to Reception!`
4. Open the MKES CARE+ Flutter Staff Portal:
   - Check the **WhatsApp Requests** badge in the Schedule screen.
   - Click **Approve & Book**, assign doctor, and confirm.
   - Verify appointment appears immediately in the clinical schedule (`ai_booked = true`).
5. Send opt-out test:
   - Send: `STOP`
   - Bot replies: `🛑 You have successfully unsubscribed from MKES CARE+ automated WhatsApp notifications...`
   - Verify `whatsapp_opt_out = true` in Supabase.

### Step 8: Full Production Launch
1. Edit `whatsapp-service/.env`:
   - Set `DRY_RUN=false`
   - Comment out or clear `TEST_PHONE_WHITELIST`
2. Restart the PM2 service:
   ```cmd
   pm2 restart mkes-wa-bridge
   ```
3. Configure PM2 Windows service autostart on system boot:
   ```cmd
   npm install -g pm2-windows-service
   pm2-service-install
   ```

---

## 4. Operator Troubleshooting & Routine Operations

| Symptom | Probable Cause | Action Required |
| :--- | :--- | :--- |
| Terminal shows `[ERROR] Protocol error: Target closed` | Chrome/Puppeteer process crashed | Restart service: `pm2 restart mkes-wa-bridge`. |
| Disconnected from WhatsApp (`session_status: disconnected`) | Clinic phone logged out from WhatsApp Mobile | Delete session folder `C:\MKES_CARE_PLUS\wa_session`, run `npm start` interactively, and re-scan the QR code. |
| Inbound messages not triggering replies | Patient is opted out (`whatsapp_opt_out = true`) | Check `whatsapp_settings.is_enabled` and verify patient row in database. |
| Appointment slots not showing | Clinic hours closed, or all doctors occupied | Verify `operating_hours_start` and `operating_hours_end` in `whatsapp_settings`. |
| Duplicate reminder prevention | 20-hour deduplication window active | Normal behavior; the system intentionally prevents sending more than one 24h reminder to the same patient. |

---

## 5. Non-Destructive Staged Rollback Procedure

If the migration ever needs to be rolled back, execute this **6-stage plan**:

```sql
-- Stage 1: Unschedule pg_cron jobs (if active)
DO $$ DECLARE r RECORD; BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    FOR r IN SELECT jobname FROM cron.job WHERE jobname LIKE 'mkes-wa-%' LOOP
      PERFORM cron.unschedule(r.jobname);
    END LOOP;
  END IF;
END $$;

-- Stage 2: Archive Audit Trails (Safe Idempotent Anti-Join)
CREATE TABLE IF NOT EXISTS public._archive_whatsapp_message_logs (
  LIKE public.whatsapp_message_logs INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING INDEXES
);
INSERT INTO public._archive_whatsapp_message_logs
SELECT src.* FROM public.whatsapp_message_logs src
WHERE NOT EXISTS (
  SELECT 1 FROM public._archive_whatsapp_message_logs arc WHERE arc.id = src.id
);

CREATE TABLE IF NOT EXISTS public._archive_whatsapp_messages_outbox (
  LIKE public.whatsapp_messages_outbox INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING INDEXES
);
INSERT INTO public._archive_whatsapp_messages_outbox
SELECT src.* FROM public.whatsapp_messages_outbox src
WHERE NOT EXISTS (
  SELECT 1 FROM public._archive_whatsapp_messages_outbox arc WHERE arc.id = src.id
);

CREATE TABLE IF NOT EXISTS public._archive_whatsapp_appointment_requests (
  LIKE public.whatsapp_appointment_requests INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING INDEXES
);
INSERT INTO public._archive_whatsapp_appointment_requests
SELECT src.* FROM public.whatsapp_appointment_requests src
WHERE NOT EXISTS (
  SELECT 1 FROM public._archive_whatsapp_appointment_requests arc WHERE arc.id = src.id
);

-- Stage 3: Drop Triggers on Core Tables
DROP TRIGGER IF EXISTS trg_dental_lab_ready_wa ON public.dental_lab;
DROP TRIGGER IF EXISTS trg_billing_payment_wa ON public.billing_payments;
DROP TRIGGER IF EXISTS trg_vendor_po_wa ON public.purchase_orders;
DROP TRIGGER IF EXISTS trg_guard_appointment_request_status ON public.whatsapp_appointment_requests;

-- Stage 4: Drop Functions (Reverse Dependency Order)
DROP FUNCTION IF EXISTS public.trg_fn_dental_lab_ready_wa();
DROP FUNCTION IF EXISTS public.trg_fn_billing_payment_wa();
DROP FUNCTION IF EXISTS public.trg_fn_vendor_po_wa();
DROP FUNCTION IF EXISTS public.trg_fn_guard_appointment_request_status();
DROP FUNCTION IF EXISTS public.approve_whatsapp_appointment_request(UUID, UUID, TEXT);
DROP FUNCTION IF EXISTS public.reject_whatsapp_appointment_request(UUID, TEXT);
DROP FUNCTION IF EXISTS public.get_available_appointment_slots(TEXT, DATE, INT, INT, UUID);
DROP FUNCTION IF EXISTS public.claim_whatsapp_outbox_batch(UUID, INT, INT);
DROP FUNCTION IF EXISTS public.register_patient_whatsapp_opt_out(TEXT);
DROP FUNCTION IF EXISTS public.set_patient_whatsapp_opt_out(UUID, BOOLEAN);
DROP FUNCTION IF EXISTS public.enqueue_appointment_reminders_batch();
DROP FUNCTION IF EXISTS public.enqueue_annual_eye_reminders_batch();
DROP FUNCTION IF EXISTS public.enqueue_dental_followups_batch();
DROP FUNCTION IF EXISTS public.enqueue_birthday_greetings_batch();
DROP FUNCTION IF EXISTS public.enqueue_google_review_requests_batch();
DROP FUNCTION IF EXISTS public.enqueue_billing_payment_reminders_batch();
DROP FUNCTION IF EXISTS public.enqueue_festival_greeting_broadcast(TEXT, TEXT);

-- Stage 5: Drop WhatsApp Tables in Dependency Order (Child to Parent, NO CASCADE)
DROP TABLE IF EXISTS public.whatsapp_message_logs;
DROP TABLE IF EXISTS public.whatsapp_messages_outbox;
DROP TABLE IF EXISTS public.whatsapp_appointment_requests;
DROP TABLE IF EXISTS public.whatsapp_chat_sessions;
DROP TABLE IF EXISTS public.whatsapp_templates;
DROP TABLE IF EXISTS public.whatsapp_settings;

-- Stage 6: Reload PostgREST Cache
NOTIFY pgrst, 'reload schema';

-- PRESERVED IN CORE PERMANENTLY:
-- 1. public.appointments (clinical bookings are never deleted)
-- 2. public.appointments.duration_minutes
-- 3. public.appointments.ai_booked
-- 4. public.patients.whatsapp_opt_out (DPDP consent compliance)
-- 5. public.patients.dob
-- 6. public.dental_treatments.procedure_status
-- 7. public._archive_whatsapp_* (audit evidence)
```
