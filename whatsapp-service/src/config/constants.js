/**
 * MKES CARE+ WhatsApp Service Constants
 * Strictly reflects verified clinic configuration and schedules.
 */

module.exports = {
  // Authoritative Clinic Operating Hours
  CLINIC: {
    NAME: 'MKES CARE+ Hospital',
    LOCATION: 'MKES Campus, Bhadran Nagar, Off Relief Road, Malad West, Mumbai 400064',
    OPENING_HOUR: 9, // 09:00 AM
    CLOSING_HOUR: 20, // 08:00 PM
    DEFAULT_SLOT_INTERVAL_MINUTES: 15, // Internal scheduling grid
    CHAT_SLOT_DURATION_MINUTES: 15, // Chat booking duration
  },

  // Confirmed Department Scope (Optical strictly excluded)
  DEPARTMENTS: {
    EYE: 'eye',
    DENTAL: 'dental',
  },

  // Confirmed Doctor Rosters (Matches DepartmentDoctorConfig)
  CONFIRMED_DOCTORS: {
    eye: [
      { name: 'Dr Mitesh Jain', specialty: 'Ophthalmology' },
      { name: 'Dr Varun', specialty: 'Ophthalmology' },
    ],
    dental: [
      { name: 'Dr Nimisha', specialty: 'General Dentistry' },
      { name: 'Dr Vikas', specialty: 'Dental Surgery' },
    ],
  },

  // Conversational State Machine Steps
  BOT_STEPS: {
    IDLE: 'IDLE',
    AWAITING_DATE_CHOICE: 'AWAITING_DATE_CHOICE',
    AWAITING_CUSTOM_DATE: 'AWAITING_CUSTOM_DATE',
    AWAITING_SLOT_CHOICE: 'AWAITING_SLOT_CHOICE',
    CONFIRMATION_PENDING: 'CONFIRMATION_PENDING',
    // Rescheduling Steps
    AWAITING_RESCHEDULE_APPOINTMENT_SELECTION: 'AWAITING_RESCHEDULE_APPOINTMENT_SELECTION',
    AWAITING_RESCHEDULE_DATE_CHOICE: 'AWAITING_RESCHEDULE_DATE_CHOICE',
    AWAITING_RESCHEDULE_CUSTOM_DATE: 'AWAITING_RESCHEDULE_CUSTOM_DATE',
    AWAITING_RESCHEDULE_SLOT_CHOICE: 'AWAITING_RESCHEDULE_SLOT_CHOICE',
    AWAITING_AMBIGUOUS_CLARIFICATION: 'AWAITING_AMBIGUOUS_CLARIFICATION',
  },

  // Opt-out trigger commands (DPDP Act Compliance)
  OPT_OUT_COMMANDS: ['STOP', 'UNSUBSCRIBE', 'OPTOUT', 'CANCEL_ALL', 'STOP ALL'],

  // Complete Operational Message Categories
  MESSAGE_TYPES: {
    REMINDER_24H: 'reminder_24h',
    REMINDER_2H: 'reminder_2h',
    ANNUAL_EYE: 'annual_eye',
    DENTAL_CLEANING: 'dental_cleaning',
    DENTAL_RCT: 'dental_rct',
    DENTAL_IMPLANT: 'dental_implant',
    LAB_READY: 'lab_ready',
    BIRTHDAY: 'birthday',
    FESTIVAL: 'festival',
    REVIEW_REQUEST: 'review_request',
    PAYMENT_RECEIPT: 'payment_receipt',
    PAYMENT_REMINDER: 'payment_reminder',
    VENDOR_PO: 'vendor_po',
    RESCHEDULED: 'rescheduled',
    STAFF_REPLY: 'staff_reply',
    CUSTOM: 'custom',
  },
};
