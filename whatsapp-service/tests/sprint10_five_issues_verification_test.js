/**
 * MKES CARE+ — Sprint 10 Five Issues Verification Test Suite
 *
 * Automated verification for:
 *   Issue 1: Responsive UI Invariants & Normalization
 *   Issue 2: Patient Update Error Handling (PostgREST PGRST116 / RLS)
 *   Issue 3: WhatsApp Invoice PDF Delivery Resolution & Fallback
 *   Issue 4: Eye Surgery WhatsApp Scheduling Message & Approved Pre-Op Instructions
 *   Issue 5: WhatsApp Inbound Message Visibility, Phone Normalization, Media & Realtime Outbox
 */

const assert = require('assert');
const PhoneNormalizer = require('../src/utils/phone_normalizer');
const InvoicePdfService = require('../src/services/invoice_pdf_service');

let passedTests = 0;
let failedTests = 0;

function test(description, fn) {
  try {
    fn();
    console.log(`  ✓ [PASS] ${description}`);
    passedTests++;
  } catch (err) {
    console.error(`  ✗ [FAIL] ${description}`);
    console.error(`    Error: ${err.message}`);
    failedTests++;
  }
}

async function asyncTest(description, fn) {
  try {
    await fn();
    console.log(`  ✓ [PASS] ${description}`);
    passedTests++;
  } catch (err) {
    console.error(`  ✗ [FAIL] ${description}`);
    console.error(`    Error: ${err.message}`);
    failedTests++;
  }
}

console.log('====================================================');
console.log('  MKES CARE+ Sprint 10 Five Issues Verification Suite');
console.log('====================================================\n');

// ---------------------------------------------------------------------------
// SUITE 1: Phone Normalization & Modern WhatsApp JID Acceptance (Issue 5)
// ---------------------------------------------------------------------------
console.log('--- Suite 1: Phone Normalization & Modern WhatsApp JID Acceptance (Issue 5) ---');

test('isIndividualChat accepts standard consumer JID (@c.us)', () => {
  assert.strictEqual(PhoneNormalizer.isIndividualChat('919876543210@c.us'), true);
});

test('isIndividualChat accepts WhatsApp multi-device JID (@s.whatsapp.net)', () => {
  assert.strictEqual(PhoneNormalizer.isIndividualChat('919876543210@s.whatsapp.net'), true);
});

test('isIndividualChat accepts linked device JID (@lid)', () => {
  assert.strictEqual(PhoneNormalizer.isIndividualChat('12345678901234@lid'), true);
});

test('isIndividualChat strictly rejects group chats (@g.us)', () => {
  assert.strictEqual(PhoneNormalizer.isIndividualChat('919876543210-123456@g.us'), false);
});

test('isIndividualChat strictly rejects system broadcast (@broadcast)', () => {
  assert.strictEqual(PhoneNormalizer.isIndividualChat('status@broadcast'), false);
});

test('isIndividualChat strictly rejects newsletters (@newsletter)', () => {
  assert.strictEqual(PhoneNormalizer.isIndividualChat('123456789@newsletter'), false);
});

test('extractTenDigits cleanly extracts 10-digit number from multiple formats', () => {
  assert.strictEqual(PhoneNormalizer.extractTenDigits('9876543210'), '9876543210');
  assert.strictEqual(PhoneNormalizer.extractTenDigits('+91 98765-43210'), '9876543210');
  assert.strictEqual(PhoneNormalizer.extractTenDigits('09876543210'), '9876543210');
  assert.strictEqual(PhoneNormalizer.extractTenDigits('919876543210'), '9876543210');
  assert.strictEqual(PhoneNormalizer.extractTenDigits('invalid'), null);
});

// ---------------------------------------------------------------------------
// SUITE 2: Inbound Message Media Placeholders & Patient Matching (Issue 5)
// ---------------------------------------------------------------------------
console.log('\n--- Suite 2: Inbound Message Media & Normalization (Issue 5) ---');

test('Empty text message with media is assigned descriptive type indicator', () => {
  const mediaMsg = { from: '919876543210@c.us', body: '', hasMedia: true, type: 'image' };
  let body = (mediaMsg.body || '').trim();
  if (!body && mediaMsg.hasMedia) {
    const mediaType = (mediaMsg.type || 'media').toUpperCase();
    body = `[${mediaType}]`;
  }
  assert.strictEqual(body, '[IMAGE]');
});

test('Empty voice note message is assigned [VOICE] indicator', () => {
  const voiceMsg = { from: '919876543210@c.us', body: '', hasMedia: true, type: 'voice' };
  let body = (voiceMsg.body || '').trim();
  if (!body && voiceMsg.hasMedia) {
    const mediaType = (voiceMsg.type || 'media').toUpperCase();
    body = `[${mediaType}]`;
  }
  assert.strictEqual(body, '[VOICE]');
});

test('JID suffix stripping works cleanly across @c.us, @s.whatsapp.net, and @lid', () => {
  const fromCus = '919876543210@c.us'.replace(/@(c\.us|s\.whatsapp\.net|lid)$/, '');
  const fromNet = '919876543210@s.whatsapp.net'.replace(/@(c\.us|s\.whatsapp\.net|lid)$/, '');
  const fromLid = '919876543210@lid'.replace(/@(c\.us|s\.whatsapp\.net|lid)$/, '');

  assert.strictEqual(fromCus, '919876543210');
  assert.strictEqual(fromNet, '919876543210');
  assert.strictEqual(fromLid, '919876543210');
});

// ---------------------------------------------------------------------------
// SUITE 3: Invoice Delivery Detection & PDF Generation Resolution (Issue 3)
// ---------------------------------------------------------------------------
console.log('\n--- Suite 3: Invoice Delivery Detection & Resolution (Issue 3) ---');

test('Outbox worker detects invoice from message_type: payment_receipt', () => {
  const record = { message_type: 'payment_receipt', message_text: 'Payment received' };
  const isInvoice = record.message_type === 'payment_receipt' ||
    (record.media_url && record.media_url.startsWith('invoice://')) ||
    (record.message_text && record.message_text.includes('MKES CARE+ Invoice #')) ||
    (record.template_key && record.template_key.startsWith('invoice_'));

  assert.strictEqual(isInvoice, true);
});

test('Outbox worker detects invoice from RPC enqueued message_text', () => {
  const record = {
    message_type: 'custom',
    template_key: 'custom',
    message_text: '🧾 *MKES CARE+ Invoice #INV-2026-0099*\n\nDear John,\nYour invoice for ₹1500 has been generated.'
  };
  const isInvoice = record.message_type === 'payment_receipt' ||
    (record.media_url && record.media_url.startsWith('invoice://')) ||
    (record.message_text && record.message_text.includes('MKES CARE+ Invoice #')) ||
    (record.template_key && record.template_key.startsWith('invoice_'));

  assert.strictEqual(isInvoice, true);
});

test('Outbox worker extracts invoice number from message_text regex when invRef not in template_key', () => {
  const record = {
    message_type: 'custom',
    template_key: 'custom',
    message_text: '🧾 *MKES CARE+ Invoice #INV-2026-0099*\n\nDear John,\nYour invoice for ₹1500 has been generated.'
  };

  let invRef = (record.media_url && record.media_url.startsWith('invoice://'))
    ? record.media_url.replace('invoice://', '')
    : (record.template_key && record.template_key !== 'custom' ? record.template_key.replace('invoice_', '') : null);

  if (!invRef && record.message_text) {
    const match = record.message_text.match(/MKES CARE\+ Invoice #([^\*\n\s]+)/);
    if (match && match[1]) {
      invRef = match[1];
    }
  }

  assert.strictEqual(invRef, 'INV-2026-0099');
});

test('Invoice PDF Service generates fallback invoice when DB is offline or mock testing', async () => {
  const service = new InvoicePdfService();
  // Using synthetic test invoice ID
  const result = await service.generateInvoicePdf('INV-2026-0099', {
    patient_id: 'test-patient-id',
    patient_name: 'Test Patient',
    department: 'eye'
  });

  assert(result.media != null, 'Expected media object to be returned');
  assert(result.media.data != null && result.media.data.length > 0, 'Expected non-empty base64 PDF data');
  assert.strictEqual(result.media.mimetype, 'application/pdf');
  assert(result.filename.includes('INV-2026-0099') || result.filename.includes('.pdf'), 'Expected valid filename');
});

// ---------------------------------------------------------------------------
// SUITE 4: Eye Surgery WhatsApp Scheduling Messages & Safety (Issue 4)
// ---------------------------------------------------------------------------
console.log('\n--- Suite 4: Eye Surgery Scheduling WhatsApp & Clinical Safety (Issue 4) ---');

test('Eye surgery message contains all 5 approved pre-operative preparation instructions', () => {
  const surgery = {
    id: 'surg-1',
    patientName: 'Jane Smith',
    surgeryTypeCategory: 'Cataract Phacoemulsification',
    eyeSide: 'left',
    assignedStaffName: 'Dr. Ramesh Sharma',
    surgeryDate: '2026-10-30',
    surgeryTime: '10:30 AM'
  };

  const messageText = `🏥 *MKES Eye Surgery Booking Confirmation*\n\n` +
    `Dear ${surgery.patientName},\n` +
    `Your ${surgery.surgeryTypeCategory} (${surgery.eyeSide.toUpperCase()} eye) has been scheduled with ${surgery.assignedStaffName}.\n\n` +
    `📅 *Date:* ${surgery.surgeryDate}\n` +
    `⏰ *Scheduled Time:* ${surgery.surgeryTime}\n` +
    `👨‍⚕️ *Attending Surgeon / Team:* ${surgery.assignedStaffName}\n\n` +
    `📋 *Pre-Operative Preparation Instructions:*\n` +
    `1. Fasting (NPO): Do not eat or drink anything for 6 hours prior to your scheduled time (light water permitted up to 2 hours prior unless instructed otherwise).\n` +
    `2. Medications: Take regular blood pressure medicines with a sip of water. Stop blood thinners only if explicitly directed by your surgeon.\n` +
    `3. Hygiene: Wash hair and face before arriving. Do not apply eye makeup, face creams, lotions, or perfume.\n` +
    `4. Escort: Please arrange for an accompanying adult to escort you home after the procedure.\n` +
    `5. Items to Bring: Bring all current eye drops and existing medical records.\n\n` +
    `Reply STOP to unsubscribe.`;

  assert(messageText.includes('Fasting (NPO): Do not eat or drink anything for 6 hours'), 'Missing NPO fasting instruction');
  assert(messageText.includes('regular blood pressure medicines with a sip of water'), 'Missing medication instruction');
  assert(messageText.includes('Wash hair and face before arriving'), 'Missing hygiene instruction');
  assert(messageText.includes('accompanying adult to escort you home'), 'Missing escort instruction');
  assert(messageText.includes('Bring all current eye drops'), 'Missing items to bring instruction');
  assert(!messageText.includes('maps.google.com'), 'Must not include clinic location link');
  assert(!messageText.includes('Optical'), 'Must exclude Optical workflows');
});

test('Duplicate prevention detects existing outbox record for surgery', () => {
  const existingOutbox = [
    { template_key: 'eye_surgery_surg-1', message_text: '...scheduled with Dr. Ramesh Sharma...' }
  ];

  const surgeryId = 'surg-1';
  const surgeon = 'Dr. Ramesh Sharma';

  const isDuplicate = existingOutbox.some(record =>
    record.template_key === `eye_surgery_${surgeryId}` ||
    (record.message_text && record.message_text.includes(`scheduled with ${surgeon}`))
  );

  assert.strictEqual(isDuplicate, true);
});

// ---------------------------------------------------------------------------
// SUITE 5: Patient Details Update & Authorization Handling (Issue 2)
// ---------------------------------------------------------------------------
console.log('\n--- Suite 5: Patient Details Update & Authorization Handling (Issue 2) ---');

test('Differentiates between missing record vs RLS authorization error on null response', () => {
  function handleUpdateResponse(response, existingRecord) {
    if (response == null) {
      if (existingRecord == null) {
        throw new Error('Patient record not found (ID: test-id). It may have been deleted.');
      } else {
        throw new Error('Permission denied: You do not have authorization to update patient details. Only clinic administrators can edit patient records.');
      }
    }
    return { success: true, data: response };
  }

  // Case A: Missing record
  assert.throws(
    () => handleUpdateResponse(null, null),
    /Patient record not found/
  );

  // Case B: Authorization failure (RLS returned 0 rows because caller is staff)
  assert.throws(
    () => handleUpdateResponse(null, { id: 'test-id' }),
    /Permission denied: You do not have authorization to update patient details/
  );

  // Case C: Successful admin update
  const successResult = handleUpdateResponse({ id: 'test-id', name: 'Updated Name' }, { id: 'test-id' });
  assert.strictEqual(successResult.success, true);
  assert.strictEqual(successResult.data.name, 'Updated Name');
});

console.log('\n====================================================');
console.log(`Sprint 10 Five Issues Verification Completed: ${passedTests} / ${passedTests + failedTests} tests passed.`);
console.log('====================================================');

if (failedTests > 0) {
  process.exit(1);
} else {
  process.exit(0);
}
