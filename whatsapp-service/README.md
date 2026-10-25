# MKES CARE+ — WhatsApp Integration Service (Windows PC Host)

**Version:** 1.0.0  
**Host Platform:** Windows 10/11 Pro / Windows Server (Clinic Reception Host)  
**Target Departments:** Eye Clinic & Dental Care (*Optical strictly excluded*)

---

## 1. Overview

The MKES CARE+ WhatsApp Bridge Daemon is a dedicated Node.js microservice that runs locally on the clinic reception Windows PC. It connects the clinic's **existing WhatsApp number** using `whatsapp-web.js` and communicates with the Supabase database via the elevated service-role key.

### Key Capabilities
- **Transactional Outbox Worker:** Dispatches automated clinical reminders, dental lab notifications, and payment receipts with 6–14s humanized delays and exponential backoff.
- **In-Chat Conversational Booking:** Patients book consultations directly within WhatsApp by replying to numbered menus (`1`=Today, `2`=Tomorrow, `3`=Upcoming date).
- **Double-Booking Prevention:** True slot availability is checked dynamically against real clinic appointments using the `get_available_appointment_slots` database RPC.
- **Patient Consent & Opt-Outs:** Receiving `STOP`, `UNSUBSCRIBE`, or `OPTOUT` immediately marks the patient as opted out and cancels any pending messages.
- **Persistent Session Storage:** Session tokens and IndexedDB are preserved in `C:\MKES_CARE_PLUS\wa_session` using `LocalAuth`.
- **Windows Service Resilience:** Managed by PM2 or NSSM with automatic restart upon system reboot.

---

## 2. Windows PC Setup Instructions

### Prerequisites
1. **Windows 10/11 Pro** with Administrator access.
2. **Node.js LTS (v18 or v20)** installed from [nodejs.org](https://nodejs.org).
3. **Google Chrome** installed on the Windows PC.

### Installation Steps
1. Navigate to the `whatsapp-service` directory in Command Prompt (or PowerShell):
   ```cmd
   cd C:\MKES PRO\mkes-care-plus-lovable\whatsapp-service
   ```
2. Copy `.env.example` to `.env`:
   ```cmd
   copy .env.example .env
   ```
3. Open `.env` and fill in your Supabase Service Role Key:
   ```ini
   SUPABASE_URL=https://mfalgfodhsszyxnfiofi.supabase.co
   SUPABASE_SERVICE_ROLE_KEY=your_actual_service_role_key_here
   WA_SESSION_PATH=C:\MKES_CARE_PLUS\wa_session
   ```
4. Install Node dependencies:
   ```cmd
   npm install
   ```
5. Run pre-flight validation:
   ```cmd
   npm run validate
   ```

---

## 3. Pairing the Clinic's Existing WhatsApp Number

1. Start the service manually in a terminal to complete initial QR code pairing:
   ```cmd
   npm start
   ```
2. A QR code will be displayed in the terminal window (and simultaneously synced to the `whatsapp_settings` table in Supabase).
3. Open WhatsApp on the clinic reception smartphone:
   - Tap **Settings** (or three dots) → **Linked Devices** → **Link a Device**.
   - Point the camera at the terminal QR code.
4. Once paired, the terminal will log:
   ```
   [INFO] WhatsApp Web client is READY and connected!
   ```
5. Future reboots will automatically re-authenticate using the cached session in `C:\MKES_CARE_PLUS\wa_session` without needing a QR scan.

---

## 4. Installing as an Auto-Starting Windows Service

To ensure the service runs continuously in the background whenever the Windows PC boots:
1. Right-click `scripts\install_windows_service.bat` and select **Run as Administrator**.
2. Useful PM2 commands:
   - Check status: `pm2 status`
   - View live logs: `pm2 logs mkes-wa-bridge`
   - Restart service: `pm2 restart mkes-wa-bridge`
   - Stop service: `pm2 stop mkes-wa-bridge`

---

## 5. Security & DPDP Compliance

- **Key Isolation:** The `SUPABASE_SERVICE_ROLE_KEY` resides strictly within `.env` on this local Windows machine and is never deployed to Flutter web clients.
- **Opt-Out Compliance:** Any patient who replies `STOP` is permanently exempted from automated reminders until they re-subscribe.
- **Data Minimization:** Messages contain only scheduling details (dates, times, doctor names, clinic location); medical records and sensitive diagnoses are never sent via WhatsApp.
