# MKES CARE+ — Clinical Management Platform

An enterprise-grade clinical management, patient administration, and multi-department healthcare operational platform built with Flutter, Riverpod, and Supabase.

[![Flutter Version](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![State Management](https://img.shields.io/badge/State-Riverpod-00599C)](https://riverpod.dev)
[![Backend](https://img.shields.io/badge/Backend-Supabase-3ECF8E?logo=supabase)](https://supabase.com)
[![Branch](https://img.shields.io/badge/Branch-sprint--10-brightgreen)](https://github.com/Tatva11/mkes-care-plus-lovable)

---

## 🌟 Overview & Key Modules

MKES CARE+ provides end-to-end clinical workflow management across ophthalmology, dentistry, staff administration, and inventory operations.

### 1. Multi-Department Clinical Operations
- **Eye Care (Ophthalmology)**: Detailed eye exams (Visual Acuity, Refraction, IOP, Slit Lamp, Fundus), cataract surgery workflows, intraocular lens tracking, pre/post-op records, and specialized prescription management.
- **Dental Care (Odontology)**: Tooth numbering charting, restorative treatments, periodontal evaluations, oral surgery, and dental lab order tracking with status updates.

### 2. Appointment Booking & Collision Prevention
- **Slot Collision Prevention**: Guaranteed conflict checks preventing double-booking the same patient on the same day/time slot or overlapping department slots.
- **Appointment Lifecycle**: Scheduled, Checked-In, In-Progress, Completed, and Rescheduled states with clear audit trails.

### 3. Staff & Attendance Management
- **GPS Geofencing & Verification**: Distance checks verifying staff physical presence at clinic coordinates during check-in, with manager-granted GPS bypass mechanisms.
- **Live Attendance Dashboard**: Real-time **"Staff Checked In Today"** overview replacing rigid shift splits, displaying punctual vs. late check-in badges.
- **Staff Performance & Workload**: Cross-department metrics tracking patient throughput, exam velocity, and clinical tasks.

### 4. Patient Directory & Medical History
- **Automatic Patient ID Generation**: Unique prefixes for Eye (`E-`) and Dental (`D-`) departments.
- **Least-Privilege RLS**: Safe updates guarded by PostgreSQL row-level security (`maybeSingle()`) preventing `PGRSC116` coercion errors.
- **Clinical Records**: Mandatory examination records before billing release to prevent unverified invoicing.

### 5. Billing, Invoicing & Payments
- **Dynamic UPI QR Code**: Instant UPI payment QR code generation with custom amounts, merchant VPA, and clinic reference tags.
- **Invoice Lifecycle**: Itemized procedures, medicine dispensing, partial payments, receipts, and revenue reconciliation.

### 6. Inventory & Purchase Order Lifecycle
- **Critical Inventory Alerts**: Comprehensive monitoring of low-stock thresholds, expired batches, and zero-stock alerts without artificial caps.
- **Purchase Orders (PO)**: Creation, vendor assignment, order tracking, partial/full item receipt, batch/expiry logging, and mobile-adaptive audit views.

### 7. Responsive Mobile UI (320px–430px)
- **Universal Zero-Overflow**: All cards, charts, metric headers, dialogs, drawers, and form fields optimized to render without clipping or horizontal overflow on screens down to 320px.

---

## 🏗️ Architecture & Technology Stack

- **Framework**: [Flutter](https://flutter.dev) (Web & Mobile)
- **State Management**: [Riverpod 2.x](https://riverpod.dev) (`StateNotifierProvider`, `AsyncNotifier`, `FutureProvider`)
- **Backend / Database**: [Supabase](https://supabase.com) (PostgreSQL 15+, Row-Level Security, Auth)
- **Charting & Visualizations**: Custom zero-dependency vector painters (`CustomPainter` for line charts, ratio bars, and donuts)
- **Navigation & Shells**: Responsive shell architecture (`AdminShell`, `StaffShell`) with adaptive drawer/rail navigation

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`>= 3.3.0 < 4.0.0`)
- [Dart SDK](https://dart.dev)
- Active [Supabase](https://supabase.com) project

### Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/Tatva11/mkes-care-plus-lovable.git
   cd mkes-care-plus-lovable
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Configure Environment**:
   Ensure `lib/core/constants/supabase_constants.dart` or `.env` has your valid Supabase URL and anonymous key.

4. **Run locally**:
   ```bash
   # Run on Web Server (port 8085)
   flutter run -d web-server --web-port 8085 --web-hostname 0.0.0.0

   # Or launch in Chrome
   flutter run -d chrome
   ```

---

## 🧪 Testing & Quality Assurance

The codebase includes comprehensive unit, widget, and responsiveness regression tests:

```bash
# 1. Run static analysis
flutter analyze

# 2. Run urgent admin fixes test suite
flutter test test/urgent_admin_fixes_test.dart

# 3. Run urgent patient management test suite
flutter test test/urgent_patient_fixes_test.dart

# 4. Run appointment conflict & department CRUD test suite
flutter test test/appointment_conflict_and_department_test.dart

# 5. Run mobile responsiveness audit (320px-430px)
flutter test test/mobile_responsiveness_audit_test.dart
```

---

## 📦 Production Build

```bash
# Build optimized Web release
flutter build web --release

# Output located at: build/web
```

---

## 📄 License & Ownership
Proprietary software developed for **MKES CARE+ Clinical Management Platform**. All rights reserved.
