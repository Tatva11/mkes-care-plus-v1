# MKES CARE+ Mobile Application Screenshots Documentation

This directory contains high-fidelity mobile format screenshots of every accessible screen, tab, and modal view in the MKES CARE+ healthcare management system.

---

## 1. Device Preset & Emulation Specifications

All screenshots were captured adhering strictly to the mobile portrait viewport guidelines:

- **Device Emulation Preset**: Apple iPhone 14 Pro
- **CSS Viewport Dimensions**: `390px` (Width) × `844px` (Height)
- **Device Pixel Ratio (DPR)**: `2.0` (Retina resolution)
- **Orientation**: Portrait
- **Capture Mode**: Initial visible viewport only (strictly no full-page expansion, no scrolling down for below-the-fold content)
- **Image Format**: PNG (lossless)

---

## 2. Directory Structure & Complete Screenshot Inventory

Total Screenshots Captured: **45**

```text
screenshots/
├── login/                        (3 screenshots)
│   ├── 01_role_selection.png
│   ├── 02_admin_login.png
│   └── 03_staff_login.png
├── staff/                        (16 screenshots)
│   ├── 01_staff_schedule.png
│   ├── 02_whatsapp_booking_requests.png
│   ├── 03_patient_management.png
│   ├── 04_patient_details.png
│   ├── 05_task_management.png
│   ├── 06_inventory_management.png
│   ├── 07_vendor_management.png
│   ├── 08_purchase_orders.png
│   ├── 09_dental_lab.png
│   ├── 10_eye_surgery.png
│   ├── 11_attendance.png
│   ├── 12_leave_management.png
│   ├── 13_billing_and_invoices.png
│   ├── 14_shared_whatsapp_inbox.png
│   ├── 15_notifications.png
│   └── 16_my_profile.png
├── admin/                        (26 screenshots)
│   ├── 01_admin_dashboard.png
│   ├── 02_staff_management.png
│   ├── 03_leave_management.png
│   ├── 04_task_management.png
│   ├── 05_staff_performance.png
│   ├── 06_attendance_management.png
│   ├── 07_patient_management.png
│   ├── 08_patient_details.png
│   ├── 09_inventory_management.png
│   ├── 10_department_management.png
│   ├── 11_vendor_management.png
│   ├── 12_purchase_orders.png
│   ├── 13_dental_lab.png
│   ├── 14_eye_surgery.png
│   ├── 15_whatsapp_booking_requests.png
│   ├── 16_administration_hub.png
│   ├── 17_billing_and_invoices.png
│   ├── 18_reports_and_analytics.png
│   ├── 19_doctor_management.png
│   ├── 20_user_management.png
│   ├── 21_shift_management.png
│   ├── 22_clinic_settings.png
│   ├── 23_shared_whatsapp_inbox.png
│   ├── 24_notifications.png
│   ├── 25_global_search.png
│   └── 26_my_profile.png
└── README.md
```

---

## 3. Screenshot Catalog & Details

### 3.1 Authentication & Login Screens (`screenshots/login/`)

| Filename | Screen / View Name | Description |
|---|---|---|
| `01_role_selection.png` | Role Selection Screen | Initial landing screen presenting portal choices ("Admin Portal" and "Staff Portal"). |
| `02_admin_login.png` | Admin Sign In | Dedicated Admin portal login screen with email, password, and secure sign-in controls. |
| `03_staff_login.png` | Staff Sign In | Dedicated Staff portal login screen with credentials input and shift sign-in controls. |

### 3.2 Staff Portal Screens (`screenshots/staff/`)

| Filename | Screen / View Name | Description |
|---|---|---|
| `01_staff_schedule.png` | Staff Schedule & Appointments | Daily appointment calendar, timeline view, and today's clinical schedule. |
| `02_whatsapp_booking_requests.png` | WhatsApp Booking Requests | Incoming patient appointment booking requests received via WhatsApp automation. |
| `03_patient_management.png` | Staff Patient Directory | Searchable patient list with department filters (Eye Clinic, Dental Clinic). |
| `04_patient_details.png` | Patient Details Screen | Comprehensive patient profile showing demographics, contact, and WhatsApp opt-in status. |
| `05_task_management.png` | My Shift Tasks | Clinical checklist, operational duties, and pending tasks assigned for the shift. |
| `06_inventory_management.png` | Clinical Inventory | Stock level tracker, consumables, frames, medicines, and reorder warnings. |
| `07_vendor_management.png` | Clinical Vendors | Vendor contact directory, lab partners, and optical supplier profiles. |
| `08_purchase_orders.png` | Purchase Orders | PO register, order tracking, and receipt verification for clinic supplies. |
| `09_dental_lab.png` | Dental Lab Tracking | Dental lab work order tracker, case statuses (crowns, bridges, dentures). |
| `10_eye_surgery.png` | Eye Surgery Tracker | Pre-op, post-op, cataract surgery scheduling, and surgical pipeline management. |
| `11_attendance.png` | Staff Attendance & Shift Log | Clock-in / clock-out recording, current shift status, and daily hours logger. |
| `12_leave_management.png` | Staff Leave Portal | Leave balance inquiry, pending leave requests, and leave application interface. |
| `13_billing_and_invoices.png` | Billing & Invoices | Quick patient invoice generation, payment collection, and recent receipts. |
| `14_shared_whatsapp_inbox.png` | Shared WhatsApp Inbox | Real-time omnichannel chat inbox connecting clinic staff directly to patients. |
| `15_notifications.png` | Notification Center | Alert center showing operational reminders, low stock warnings, and task updates. |
| `16_my_profile.png` | Staff Profile & Settings | Staff member contact details, shift schedule overview, and account security. |

### 3.3 Admin Portal Screens (`screenshots/admin/`)

| Filename | Screen / View Name | Description |
|---|---|---|
| `01_admin_dashboard.png` | Executive Admin Dashboard | Revenue growth analytics, hourly collections chart, and patient volume statistics. |
| `02_staff_management.png` | Staff Management Hub | Overview of clinical personnel, active shifts, and staff directory navigation. |
| `03_leave_management.png` | Admin Leave Approvals | Administrative review for staff leave requests, approval actions, and quota tracker. |
| `04_task_management.png` | Admin Task Management | Clinic-wide task delegation, shift assignment monitor, and duty status board. |
| `05_staff_performance.png` | Performance & Workload (Tab 0) | Task completion metrics, active workload breakdown, and staff capacity analytics. |
| `06_attendance_management.png` | Attendance Management (Tab 1) | Daily attendance audit log, late arrival flags, and absent staff records. |
| `07_patient_management.png` | Admin Patient Management | Master patient database, departmental segmentation, and registration records. |
| `08_patient_details.png` | Admin Patient Details | Detailed clinical dossier, appointment history, WhatsApp status, and edit actions. |
| `09_inventory_management.png` | Operations: Inventory (Tab 0) | Clinic inventory management, category breakdown, and stock replenishment. |
| `10_department_management.png` | Operations: Departments (Tab 1) | Department configuration (Eye Clinic, Dental Clinic), rooms, and capacity settings. |
| `11_vendor_management.png` | Operations: Vendors (Tab 2) | Supplier database, terms of payment, and procurement vendor profiles. |
| `12_purchase_orders.png` | Operations: Purchase Orders (Tab 3) | Administrative PO approvals, order tracking, and invoice matching. |
| `13_dental_lab.png` | Operations: Dental Lab (Tab 4) | Laboratory case monitor, fabrication progress, and delivery schedule. |
| `14_eye_surgery.png` | Operations: Eye Surgery (Tab 5) | Surgical case schedule, surgeon allocation, OT readiness, and patient statuses. |
| `15_whatsapp_booking_requests.png` | Operations: WhatsApp Requests (Tab 6) | Operational queue for unassigned WhatsApp booking requests and triage. |
| `16_administration_hub.png` | Administration Settings Hub | Central administration portal for billing, analytics, and system configurations. |
| `17_billing_and_invoices.png` | Admin Billing & Financials | Revenue tracking, payment mode analytics (Cash, UPI), and invoice ledger. |
| `18_reports_and_analytics.png` | Reports & Business Analytics | Clinical KPIs, revenue reports, Excel export engine, and departmental audits. |
| `19_doctor_management.png` | Doctor Management | Doctor directory, consulting schedules, OPD timings, and department assignments. |
| `20_user_management.png` | User & Role Management | User directory, role-based access control (Admin, Staff, Doctor), and account statuses. |
| `21_shift_management.png` | Shift Management & Rosters | Shift roster planning, timing configurations (Morning, Evening), and assignments. |
| `22_clinic_settings.png` | Clinic Settings & Configurations | Clinic profile, branding, contact numbers, and operational configurations. |
| `23_shared_whatsapp_inbox.png` | Admin WhatsApp Inbox | Clinic-wide WhatsApp conversation oversight, chatbot status, and conversation logs. |
| `24_notifications.png` | Admin Notification Center | System-wide alerts, inventory warnings, missed shift notifications, and requests. |
| `25_global_search.png` | Global Copilot Search Modal | Omnisearch overlay for instant retrieval of patients, staff, inventory, and actions. |
| `26_my_profile.png` | Admin Profile & Security | Administrator personal details, security credentials, and system role information. |

---

## 4. UI / Layout Observations

During the mobile capture process, all pages rendered faithfully to their initial viewport. The following minor layout behavior was observed on mobile viewports:

- **Staff Patient Directory Header (`screenshots/staff/03_patient_management.png`)**:
  On a 390px mobile viewport, placing the "WhatsApp Inbox" and "New Patient" buttons in the same horizontal Row as the "Patient Directory" title causes the header text to wrap into a narrow column. As instructed, no modifications were made to the UI; it was captured authentically as-is.

---

## 5. Inaccessible Pages

- **None**. Every single page, tab, sheet modal, and dialog across the Staff Portal and Admin Portal was accessible and successfully captured.

---

## 6. Safety & Verification Summary

- **Authentication**: Used authorized credentials with temporary local sessions.
- **Data Protection**: No patient records, appointments, or invoices were altered or created.
- **WhatsApp Protection**: No live WhatsApp messages were triggered; no session resets were performed.
- **Repository Integrity**: No Flutter source code, Supabase schemas, migrations, or git branches were modified. Branch `sprint-10` remains completely clean.
