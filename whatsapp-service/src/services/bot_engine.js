const { supabase } = require('../config/supabase');
const whatsappClient = require('./whatsapp_client');
const SlotService = require('./slot_service');
const PhoneNormalizer = require('../utils/phone_normalizer');
const logger = require('../utils/logger');
const { pushNotificationBackend } = require('./push_notification_backend');
const { BOT_STEPS, OPT_OUT_COMMANDS, CLINIC, DEPARTMENTS } = require('../config/constants');

const RESTART_COMMANDS = ['HI', 'HELLO', 'HEY', 'START', 'RESTART', 'MENU', 'RESET', 'CANCEL', '0'];

class BotEngine {
  /**
   * Main entry point for all incoming WhatsApp messages.
   */
  static async handleIncomingMessage(msg) {
    if (!PhoneNormalizer.isIndividualChat(msg.from)) {
      return; // Ignore group chats or system broadcasts
    }

    const rawPhone = msg.from.replace(/@(c\.us|s\.whatsapp\.net|lid)$/, '');
    const cleanTen = PhoneNormalizer.extractTenDigits(rawPhone);
    let body = (msg.body || '').trim();
    if (!body && msg.hasMedia) {
      const mediaType = (msg.type || 'media').toUpperCase();
      body = `[${mediaType}]`;
    } else if (!body) {
      body = '[Message]';
    }

    logger.info(`Received inbound message from ${msg.from}: "${body}"`);

    // 1. Lookup Patient Record in Database (Handle unambiguous vs ambiguous match safely)
    let patient = null;
    let isAmbiguous = false;
    let candidatePatients = [];

    if (cleanTen) {
      try {
        const { data: patientRows } = await supabase
          .from('patients')
          .select('*')
          .ilike('mobile', `%${cleanTen}`);

        if (patientRows && patientRows.length === 1) {
          patient = patientRows[0];
        } else if (patientRows && patientRows.length > 1) {
          isAmbiguous = true;
          candidatePatients = patientRows;
          logger.warn(`Ambiguous phone number ${cleanTen}: Matches ${patientRows.length} distinct patient profiles.`);
        }
      } catch (e) {
        logger.error(`Error looking up patient for ${cleanTen}: ${e.message}`);
      }
    }

    // 2. Audit log incoming message with matched patient association
    await this._logInboundMessage(rawPhone, body, msg, patient?.id);

    // 3. Check Opt-Out Command (DPDP Act Compliance)
    const upperBody = body.toUpperCase();
    if (OPT_OUT_COMMANDS.includes(upperBody)) {
      logger.info(`Processing opt-out request for phone: ${rawPhone}`);
      try {
        await supabase.rpc('register_patient_whatsapp_opt_out', {
          p_phone_number: rawPhone,
        });
      } catch (optErr) {
        logger.error(`Error in register_patient_whatsapp_opt_out RPC: ${optErr.message}`);
      }
      await whatsappClient.sendMessageWithHumanizedDelay(
        msg.from,
        '🛑 You have successfully unsubscribed from MKES CARE+ automated WhatsApp notifications. You will receive no further messages.\nTo resume, please contact our reception.'
      );
      return;
    }

    // Check if patient previously opted out
    if (patient && patient.whatsapp_opt_out) {
      logger.info(`Incoming message from opted-out patient ${patient.id}. Ignoring automated reply.`);
      return;
    }

    // 4. Retrieve or Create Conversation Session
    const session = await this._getOrCreateSession(rawPhone, patient);

    // 5. Repeated / duplicate message debounce check (within 2 seconds)
    const now = Date.now();
    if (
      session.last_message_body === body &&
      session.last_message_time &&
      now - session.last_message_time < 2000
    ) {
      logger.warn(`Debouncing duplicate inbound message from ${rawPhone}: "${body}"`);
      return;
    }

    // Update last message debounce tracking
    await this._updateSession(rawPhone, {
      last_message_body: body,
      last_message_time: now,
    });

    // 6. Notify Clinic Staff of New Inbound Message (In-App Notification)
    await this._notifyStaffOfInboundMessage(patient, rawPhone, body);

    // 7. Handle Optical Department exclusion guard
    if (upperBody.includes('OPTICAL') || upperBody.includes('GLASSES') || upperBody.includes('SPECTACLES')) {
      await whatsappClient.sendMessageWithHumanizedDelay(
        msg.from,
        '⚠️ Optical retail is not available for online scheduling. MKES CARE+ WhatsApp booking is available exclusively for *Eye* and *Dental* clinics.\n\nReply *EYE* for Ophthalmology or *DENTAL* for Dental Care.'
      );
      return;
    }

    // 8. Handle Ambiguous Identity Guard (Do NOT guess patient identity)
    if (isAmbiguous && session.current_step === BOT_STEPS.IDLE) {
      const namesList = candidatePatients.map((p, idx) => `• ${p.name || 'Patient'} (${p.patient_number || 'Record #' + (idx + 1)})`).join('\n');
      await whatsappClient.sendMessageWithHumanizedDelay(
        msg.from,
        `👋 *MKES CARE+ Verification Notice*\n\n` +
        `We found multiple patient profiles registered under this mobile number:\n` +
        `${namesList}\n\n` +
        `To ensure medical privacy and accurate scheduling, please reply with the patient's *Full Name* or *Patient Number* so our reception team can verify your record.\n\n` +
        `_Reply STOP to unsubscribe._`
      );
      await this._updateSession(rawPhone, {
        current_step: BOT_STEPS.AWAITING_AMBIGUOUS_CLARIFICATION,
        candidate_patient_ids: candidatePatients.map((p) => p.id),
      });
      return;
    }

    // Handle Ambiguous Identity Clarification Response
    if (session.current_step === BOT_STEPS.AWAITING_AMBIGUOUS_CLARIFICATION) {
      if (RESTART_COMMANDS.includes(upperBody)) {
        await this._resetSession(rawPhone);
        await this._handleIdleState(session, body, msg.from, 'Valued Patient', 'dental');
        return;
      }
      // Attempt to resolve patient name from input
      const matched = (candidatePatients.length > 0 ? candidatePatients : []).find(
        (p) => p.name && p.name.toLowerCase().includes(body.toLowerCase())
      );
      if (matched) {
        patient = matched;
        logger.info(`Patient clarified identity from ambiguous group: ${patient.id} (${patient.name})`);
        await this._updateSession(rawPhone, {
          patient_id: patient.id,
          current_step: BOT_STEPS.IDLE,
        });
        session.current_step = BOT_STEPS.IDLE;
      } else {
        await whatsappClient.sendMessageWithHumanizedDelay(
          msg.from,
          `Thank you. Our clinic reception has been notified and will verify your file shortly.\n\nTo view general booking options, reply *RESTART*.`
        );
        return;
      }
    }

    // 9. Handle Department switching keywords
    if (upperBody === 'EYE' || upperBody === 'DENTAL') {
      const targetDept = upperBody.toLowerCase();
      await this._updateSession(rawPhone, {
        selected_department: targetDept,
        current_step: BOT_STEPS.AWAITING_DATE_CHOICE,
        selected_date: null,
        selected_slot: null,
        presented_options: [],
      });
      session.selected_department = targetDept;
      session.current_step = BOT_STEPS.AWAITING_DATE_CHOICE;
      await this._handleIdleState(session, '', msg.from, patient?.name || 'Valued Patient', targetDept);
      return;
    }

    // 10. Check Rescheduling Intent in IDLE or Initial Messages
    if (this._isReschedulingIntent(body)) {
      logger.info(`Rescheduling intent detected from ${rawPhone}: "${body}"`);
      await this._initiateReschedulingWorkflow(session, msg.from, patient, body);
      return;
    }

    // 10b. Check if patient is replying to a Ready Lab Case notification (Option 1, 2, 3 or custom slot)
    if (patient?.id) {
      const readyCase = await this._getPendingReadyDentalLabCase(patient.id);
      if (readyCase) {
        const handled = await this._handleDentalLabCaseReply(session, body, msg.from, patient, readyCase);
        if (handled) return;
      }
    }

    // 11. Universal Restart / Menu command check
    if (RESTART_COMMANDS.includes(upperBody)) {
      if (session.current_step === BOT_STEPS.CONFIRMATION_PENDING && upperBody !== 'RESTART') {
        await whatsappClient.sendMessageWithHumanizedDelay(
          msg.from,
          `Hello ${patient?.name || 'Valued Patient'}, your appointment request is currently under review by our clinic staff.\n\nTo cancel this request and book a new time, reply *RESTART*.\nReply STOP to unsubscribe.`
        );
        return;
      }
      await this._resetSession(rawPhone);
      session.current_step = BOT_STEPS.IDLE;
      await this._handleIdleState(session, body, msg.from, patient?.name || 'Valued Patient', session.selected_department || 'dental');
      return;
    }

    // 12. Route through State Machine
    await this._routeState(session, body, msg.from, patient);
  }

  /**
   * Evaluates if incoming text conveys intent to change or reschedule an existing appointment.
   */
  static _isReschedulingIntent(text) {
    if (!text) return false;
    const rescheduleRegex = /\b(reschedule|re-schedule|change\s+time|change\s+date|change\s+appointment|change\s+my\s+visit|postpone|shift\s+appointment|different\s+time|another\s+time|can\s+i\s+come|resched)\b/i;
    return rescheduleRegex.test(text);
  }

  /**
   * Initiates the automated rescheduling workflow.
   */
  static async _initiateReschedulingWorkflow(session, fromJid, patient, initialText = '') {
    const todayIso = SlotService.getTodayIST();

    if (!patient || !patient.id) {
      await whatsappClient.sendMessageWithHumanizedDelay(
        fromJid,
        `📋 *MKES CARE+ Appointment Rescheduling*\n\n` +
        `We could not find an existing patient file matching your phone number to reschedule.\n\n` +
        `Would you like to schedule a new appointment?\n` +
        `*1* — Eye Clinic\n` +
        `*2* — Dental Care\n\n` +
        `_Or contact reception directly for assistance._`
      );
      return;
    }

    // Fetch active upcoming appointments for this patient
    const { data: appointments, error } = await supabase
      .from('appointments')
      .select('*')
      .eq('patient_id', patient.id)
      .in('status', ['scheduled', 'confirmed'])
      .gte('appointment_date', todayIso)
      .order('appointment_date', { ascending: true })
      .order('appointment_time', { ascending: true });

    if (error || !appointments || appointments.length === 0) {
      await whatsappClient.sendMessageWithHumanizedDelay(
        fromJid,
        `Hello ${patient.name || 'Valued Patient'}, we could not find any active upcoming appointments under your record to reschedule.\n\n` +
        `Would you like to schedule a new visit? Reply:\n` +
        `*1* — Eye Clinic\n` +
        `*2* — Dental Care\n\n` +
        `_Reply STOP to unsubscribe._`
      );
      return;
    }

    if (appointments.length === 1) {
      const appt = appointments[0];
      const dept = (appt.department || 'dental').toLowerCase();
      const formattedTime = SlotService.formatTime12Hour(appt.appointment_time);
      const doctor = appt.doctor_name || 'Attending Specialist';

      // Record in whatsapp_appointment_requests so Staff Portal -> My Schedule -> WhatsApp Requests displays it immediately!
      let requestId = null;
      try {
        const { data: reqRow } = await supabase
          .from('whatsapp_appointment_requests')
          .insert({
            patient_id: patient.id,
            patient_name: patient.name || 'Valued Patient',
            patient_phone: session.phone_number,
            department: dept,
            doctor_id: appt.doctor_id || null,
            doctor_name: doctor,
            requested_date: appt.appointment_date,
            requested_time: appt.appointment_time,
            status: 'pending_review',
            notes: `Reschedule requested for appointment #${appt.id}. Patient input: "${initialText || 'Reschedule request'}"`,
          })
          .select('id')
          .maybeSingle();
        if (reqRow) requestId = reqRow.id;
      } catch (err) {
        logger.warn(`Could not insert into whatsapp_appointment_requests: ${err.message}`);
      }

      // Notify staff of incoming reschedule request
      await this._notifyStaffOfRescheduleRequest(patient, appt, dept);

      // Check if patient specified requested new date and/or time in their message
      const parsedDate = SlotService.parseRequestedDate(initialText);
      const parsedTime = SlotService.parseRequestedTime(initialText);

      if (parsedDate) {
        const availableSlots = await SlotService.getAvailableSlots(dept, parsedDate, appt.doctor_id);

        if (parsedTime) {
          const matchingSlot = availableSlots.find(
            (s) => s.raw === parsedTime || s.formatted.toLowerCase() === parsedTime.toLowerCase() || s.raw.startsWith(parsedTime.slice(0, 5))
          );

          if (matchingSlot) {
            // Requested slot is genuinely available!
            await this._updateSession(session.phone_number, {
              current_step: BOT_STEPS.AWAITING_RESCHEDULE_CONFIRMATION,
              reschedule_appointment_id: appt.id,
              reschedule_request_id: requestId,
              selected_date: parsedDate,
              selected_slot: matchingSlot.raw,
              reschedule_target_slot: matchingSlot,
              selected_department: dept,
            });

            const confirmMsg =
              `🔄 *Confirm Reschedule*\n\n` +
              `Dear ${patient.name},\n` +
              `We found your requested slot with Doctor ${doctor}:\n\n` +
              `📅 *Date:* ${parsedDate}\n` +
              `⏰ *Time:* ${matchingSlot.formatted}\n\n` +
              `Reply *1* to CONFIRM this new appointment time.\n` +
              `Reply *0* to cancel and keep your current appointment.`;

            await whatsappClient.sendMessageWithHumanizedDelay(fromJid, confirmMsg);
            return;
          } else {
            // Requested time is unavailable; offer genuinely available alternatives
            const topSlots = availableSlots.slice(0, 5);
            if (topSlots.length > 0) {
              await this._updateSession(session.phone_number, {
                current_step: BOT_STEPS.AWAITING_RESCHEDULE_SLOT_CHOICE,
                reschedule_appointment_id: appt.id,
                reschedule_request_id: requestId,
                selected_date: parsedDate,
                presented_options: topSlots,
                selected_department: dept,
              });

              let optMsg =
                `⚠️ The requested time (${parsedTime}) on *${parsedDate}* is unavailable with Doctor ${doctor}.\n\n` +
                `Here are genuinely available alternative slots on *${parsedDate}*:\n\n`;
              topSlots.forEach((s, idx) => {
                optMsg += `*${idx + 1}* — ${s.formatted}\n`;
              });
              optMsg += `\nReply with a number (*1* to *${topSlots.length}*), or reply *0* to pick another date.`;

              await whatsappClient.sendMessageWithHumanizedDelay(fromJid, optMsg);
              return;
            }
          }
        } else {
          // Date given, but no time; present available slots for that date
          await this._updateSession(session.phone_number, {
            reschedule_appointment_id: appt.id,
            reschedule_request_id: requestId,
            selected_department: dept,
          });
          await this._presentRescheduleSlots(session, parsedDate, fromJid, dept);
          return;
        }
      }

      // Ambiguous or generic request - prompt patient clearly
      await this._updateSession(session.phone_number, {
        current_step: BOT_STEPS.AWAITING_RESCHEDULE_DATE_CHOICE,
        reschedule_appointment_id: appt.id,
        reschedule_request_id: requestId,
        reschedule_original_date: appt.appointment_date,
        reschedule_original_time: appt.appointment_time,
        selected_department: dept,
      });

      const promptText =
        `🔄 *Reschedule Your Appointment*\n\n` +
        `Hello ${patient.name}, you are rescheduling your *${dept.toUpperCase()}* appointment currently booked for *${appt.appointment_date}* at *${formattedTime}* (Doctor: ${doctor}).\n\n` +
        `Please select your preferred *new date*:\n` +
        `*1* — Today\n` +
        `*2* — Tomorrow\n` +
        `*3* — Choose from upcoming dates\n\n` +
        `Or reply with your requested date and time (e.g. 'Tomorrow at 4pm').\n\n` +
        `_Reply 0 to cancel and keep your current appointment._`;

      await whatsappClient.sendMessageWithHumanizedDelay(fromJid, promptText);
    } else {
      // Multiple upcoming appointments - ask patient to choose which one
      let listMsg = `📋 *You have multiple upcoming appointments:*\n\n`;
      appointments.forEach((a, idx) => {
        const timeStr = SlotService.formatTime12Hour(a.appointment_time);
        listMsg += `*${idx + 1}* — ${a.department.toUpperCase()} on ${a.appointment_date} at ${timeStr}\n`;
      });
      listMsg += `\nReply with *1* to *${appointments.length}* to select which one to reschedule (or *0* to cancel):`;

      await this._updateSession(session.phone_number, {
        current_step: BOT_STEPS.AWAITING_RESCHEDULE_APPOINTMENT_SELECTION,
        presented_appointments: appointments,
      });

      await whatsappClient.sendMessageWithHumanizedDelay(fromJid, listMsg);
    }
  }

  static async _routeState(session, input, fromJid, patient) {
    const step = session.current_step;
    const patientName = patient?.name || 'Valued Patient';
    const dept = session.selected_department || patient?.department || 'dental';

    switch (step) {
      case BOT_STEPS.IDLE:
        await this._handleIdleState(session, input, fromJid, patientName, dept);
        break;

      case BOT_STEPS.AWAITING_DATE_CHOICE:
        await this._handleDateChoiceState(session, input, fromJid, patientName, dept);
        break;

      case BOT_STEPS.AWAITING_CUSTOM_DATE:
        await this._handleCustomDateState(session, input, fromJid, patientName, dept);
        break;

      case BOT_STEPS.AWAITING_SLOT_CHOICE:
        await this._handleSlotChoiceState(session, input, fromJid, patientName, dept, patient);
        break;

      case BOT_STEPS.CONFIRMATION_PENDING:
        await whatsappClient.sendMessageWithHumanizedDelay(
          fromJid,
          `Hello ${patientName}, your appointment request is currently under review by our clinic staff. You will receive a confirmation message once approved.\nTo cancel and choose another time, reply *RESTART*.\nReply STOP to unsubscribe.`
        );
        break;

      // Rescheduling States
      case BOT_STEPS.AWAITING_RESCHEDULE_APPOINTMENT_SELECTION:
        await this._handleRescheduleAppointmentSelection(session, input, fromJid, patientName);
        break;

      case BOT_STEPS.AWAITING_RESCHEDULE_DATE_CHOICE:
        await this._handleRescheduleDateChoice(session, input, fromJid, patientName, dept);
        break;

      case BOT_STEPS.AWAITING_RESCHEDULE_CUSTOM_DATE:
        await this._handleRescheduleCustomDate(session, input, fromJid, patientName, dept);
        break;

      case BOT_STEPS.AWAITING_RESCHEDULE_SLOT_CHOICE:
        await this._handleRescheduleSlotChoice(session, input, fromJid, patientName, dept, patient);
        break;

      case BOT_STEPS.AWAITING_RESCHEDULE_CONFIRMATION:
        await this._handleRescheduleConfirmation(session, input, fromJid, patientName, dept, patient);
        break;

      default:
        await this._resetSession(session.phone_number);
        await this._handleIdleState(session, input, fromJid, patientName, dept);
        break;
    }
  }

  static async _handleIdleState(session, input, fromJid, patientName, dept) {
    const deptLabel = dept.toLowerCase() === 'eye' ? 'Eye Clinic' : 'Dental Care';

    const menuText =
      `👋 *Welcome to MKES CARE+ Hospital!*\n\n` +
      `Hello ${patientName}, would you like to schedule an appointment with our *${deptLabel}* department?\n\n` +
      `Please reply with a number:\n` +
      `*1* — Today\n` +
      `*2* — Tomorrow\n` +
      `*3* — Choose from upcoming dates\n\n` +
      `_Reply RESCHEDULE to change an existing booking._\n` +
      `_Reply EYE or DENTAL to switch clinic._\n` +
      `_Reply STOP to unsubscribe at any time._`;

    await whatsappClient.sendMessageWithHumanizedDelay(fromJid, menuText);

    await this._updateSession(session.phone_number, {
      current_step: BOT_STEPS.AWAITING_DATE_CHOICE,
      selected_department: dept,
    });
  }

  static async _handleDateChoiceState(session, input, fromJid, patientName, dept) {
    const trimmed = input.trim();

    if (trimmed === '1') {
      const todayIso = SlotService.getTodayIST();
      await this._presentAvailableSlots(session, todayIso, fromJid, dept);
    } else if (trimmed === '2') {
      const tomorrowIso = SlotService.getTomorrowIST();
      await this._presentAvailableSlots(session, tomorrowIso, fromJid, dept);
    } else if (trimmed === '3') {
      const upcoming = SlotService.getEligibleUpcomingDates();
      if (!upcoming || upcoming.length === 0) {
        await whatsappClient.sendMessageWithHumanizedDelay(
          fromJid,
          `Sorry, no upcoming schedule dates are currently available. Please reply *1* for Today or *2* for Tomorrow.`
        );
        return;
      }

      let msg = `📅 *Select an upcoming date for ${dept.toUpperCase()}:*\n\n`;
      upcoming.forEach((item, index) => {
        msg += `*${index + 1}* — ${item.display}\n`;
      });
      msg += `\nReply with *1*, *2*, or *3* (or *0* to return to main menu):`;

      await whatsappClient.sendMessageWithHumanizedDelay(fromJid, msg);

      await this._updateSession(session.phone_number, {
        current_step: BOT_STEPS.AWAITING_CUSTOM_DATE,
        presented_options: upcoming,
      });
    } else {
      await whatsappClient.sendMessageWithHumanizedDelay(
        fromJid,
        `Invalid selection. Please reply:\n*1* — Today\n*2* — Tomorrow\n*3* — Choose from upcoming dates\n\n_Reply STOP to unsubscribe._`
      );
    }
  }

  static async _handleCustomDateState(session, input, fromJid, patientName, dept) {
    const trimmed = input.trim();
    if (trimmed === '0') {
      await this._resetSession(session.phone_number);
      await this._handleIdleState(session, input, fromJid, patientName, dept);
      return;
    }

    const choice = parseInt(trimmed, 10);
    const options = session.presented_options || [];

    if (choice >= 1 && choice <= options.length) {
      const selectedDate = options[choice - 1];
      await this._presentAvailableSlots(session, selectedDate.dateIso, fromJid, dept);
    } else {
      await whatsappClient.sendMessageWithHumanizedDelay(
        fromJid,
        `Invalid selection. Please reply with *1*, *2*, or *3* to choose a date (or *0* to return to main menu).`
      );
    }
  }

  static async _presentAvailableSlots(session, dateIso, fromJid, dept) {
    const slots = await SlotService.getAvailableSlots(dept, dateIso, CLINIC.CHAT_SLOT_DURATION_MINUTES);

    if (slots.length === 0) {
      await whatsappClient.sendMessageWithHumanizedDelay(
        fromJid,
        `Sorry, there are no available slots for ${dateIso} in the *${dept.toUpperCase()}* department.\n\nPlease reply *3* to choose another date, or reply *RESTART* for the main menu.`
      );
      await this._updateSession(session.phone_number, {
        current_step: BOT_STEPS.AWAITING_DATE_CHOICE,
        selected_date: null,
        presented_options: [],
      });
      return;
    }

    const selectedSlots = slots.slice(0, 4);

    let msg = `⏰ *Available ${dept.toUpperCase()} slots for ${dateIso}:*\n\n`;
    selectedSlots.forEach((s, idx) => {
      msg += `*${idx + 1}* — ${s.formatted}\n`;
    });
    msg += `\nReply with the number of your preferred slot (1-${selectedSlots.length}) or *0* to pick another date:`;

    await whatsappClient.sendMessageWithHumanizedDelay(fromJid, msg);

    await this._updateSession(session.phone_number, {
      current_step: BOT_STEPS.AWAITING_SLOT_CHOICE,
      selected_date: dateIso,
      presented_options: selectedSlots,
    });
  }

  static async _handleSlotChoiceState(session, input, fromJid, patientName, dept, patient) {
    const trimmed = input.trim();
    if (trimmed === '0') {
      await this._updateSession(session.phone_number, {
        current_step: BOT_STEPS.AWAITING_DATE_CHOICE,
        selected_slot: null,
      });
      await this._handleIdleState(session, input, fromJid, patientName, dept);
      return;
    }

    const choice = parseInt(trimmed, 10);
    const options = session.presented_options || [];

    if (choice >= 1 && choice <= options.length) {
      const chosenSlot = options[choice - 1];
      const selectedDate = session.selected_date;

      logger.info(`Patient ${patientName} selected slot ${chosenSlot.raw} on ${selectedDate}`);

      // Check for existing pending request to avoid duplicates
      const { data: existingPending } = await supabase
        .from('whatsapp_appointment_requests')
        .select('id, requested_date, requested_time')
        .eq('patient_phone', session.phone_number)
        .eq('department', dept)
        .eq('requested_date', selectedDate)
        .eq('requested_time', chosenSlot.raw)
        .eq('status', 'pending_review')
        .maybeSingle();

      if (existingPending) {
        logger.info(`Duplicate pending request detected for ${session.phone_number}.`);
        await whatsappClient.sendMessageWithHumanizedDelay(
          fromJid,
          `📋 You already have a pending request for *${dept.toUpperCase()}* on *${selectedDate}* at *${chosenSlot.formatted}*.\n\nOur clinic staff is reviewing it now. You will receive confirmation shortly.\nReply STOP to unsubscribe.`
        );
        await this._updateSession(session.phone_number, {
          current_step: BOT_STEPS.CONFIRMATION_PENDING,
          selected_slot: chosenSlot.raw,
        });
        return;
      }

      // Insert Pending Appointment Request into Database for Staff Approval
      const { data: requestRow, error } = await supabase
        .from('whatsapp_appointment_requests')
        .insert({
          patient_id: patient?.id,
          patient_name: patientName,
          patient_phone: session.phone_number,
          department: dept,
          requested_date: selectedDate,
          requested_time: chosenSlot.raw,
          duration_minutes: CLINIC.CHAT_SLOT_DURATION_MINUTES,
          status: 'pending_review',
          notes: 'Requested via WhatsApp conversational booking.',
        })
        .select()
        .single();

      if (error) {
        logger.error(`Failed to create appointment request: ${error.message}`);
        await whatsappClient.sendMessageWithHumanizedDelay(
          fromJid,
          'An error occurred while submitting your request. Please contact the clinic reception directly.'
        );
        return;
      }

      const ackText =
        `📋 *Request Submitted to Reception!*\n\n` +
        `Dear ${patientName},\n` +
        `Your request for a *${dept.toUpperCase()}* appointment on *${selectedDate}* at *${chosenSlot.formatted}* has been received.\n\n` +
        `Our clinic staff is verifying doctor availability and will send your formal confirmation shortly.\n\n` +
        `_Reply STOP to unsubscribe._`;

      await whatsappClient.sendMessageWithHumanizedDelay(fromJid, ackText);

      await this._updateSession(session.phone_number, {
        current_step: BOT_STEPS.CONFIRMATION_PENDING,
        selected_slot: chosenSlot.raw,
      });
    } else {
      await whatsappClient.sendMessageWithHumanizedDelay(
        fromJid,
        `Invalid choice. Please reply with a valid slot number (1 to ${options.length}) or *0* to pick another date.`
      );
    }
  }

  // --------------------------------------------------------------------------
  // Automated Rescheduling Handlers
  // --------------------------------------------------------------------------

  static async _handleRescheduleAppointmentSelection(session, input, fromJid, patientName) {
    const trimmed = input.trim();
    if (trimmed === '0') {
      await this._resetSession(session.phone_number);
      await whatsappClient.sendMessageWithHumanizedDelay(fromJid, 'Rescheduling cancelled. Your existing appointment remains unchanged.');
      return;
    }

    const choice = parseInt(trimmed, 10);
    const appts = session.presented_appointments || [];

    if (choice >= 1 && choice <= appts.length) {
      const selectedAppt = appts[choice - 1];
      const dept = (selectedAppt.department || 'dental').toLowerCase();
      const formattedTime = SlotService.formatTime12Hour(selectedAppt.appointment_time);

      await this._updateSession(session.phone_number, {
        current_step: BOT_STEPS.AWAITING_RESCHEDULE_DATE_CHOICE,
        reschedule_appointment_id: selectedAppt.id,
        reschedule_original_date: selectedAppt.appointment_date,
        reschedule_original_time: selectedAppt.appointment_time,
        selected_department: dept,
      });

      const promptText =
        `🔄 *Rescheduling ${dept.toUpperCase()} Appointment*\n\n` +
        `Current: *${selectedAppt.appointment_date}* at *${formattedTime}*\n\n` +
        `Please select your preferred *new date*:\n` +
        `*1* — Today\n` +
        `*2* — Tomorrow\n` +
        `*3* — Choose from upcoming dates\n\n` +
        `_Reply 0 to cancel and keep your current appointment._`;

      await whatsappClient.sendMessageWithHumanizedDelay(fromJid, promptText);
    } else {
      await whatsappClient.sendMessageWithHumanizedDelay(
        fromJid,
        `Invalid selection. Please reply with a number between 1 and ${appts.length} (or *0* to cancel):`
      );
    }
  }

  static async _handleRescheduleDateChoice(session, input, fromJid, patientName, dept) {
    const trimmed = input.trim();
    if (trimmed === '0') {
      await this._resetSession(session.phone_number);
      await whatsappClient.sendMessageWithHumanizedDelay(
        fromJid,
        'Rescheduling cancelled. Your original appointment remains active and unchanged.'
      );
      return;
    }

    let targetDate = null;
    if (trimmed === '1') {
      targetDate = SlotService.getTodayIST();
    } else if (trimmed === '2') {
      targetDate = SlotService.getTomorrowIST();
    } else if (trimmed === '3') {
      const upcoming = SlotService.getEligibleUpcomingDates();
      if (!upcoming || upcoming.length === 0) {
        await whatsappClient.sendMessageWithHumanizedDelay(
          fromJid,
          `Sorry, no upcoming schedule dates are currently available. Please reply *1* for Today or *2* for Tomorrow.`
        );
        return;
      }

      let msg = `📅 *Select a new date for rescheduling:*\n\n`;
      upcoming.forEach((item, index) => {
        msg += `*${index + 1}* — ${item.display}\n`;
      });
      msg += `\nReply with *1*, *2*, or *3* (or *0* to cancel):`;

      await whatsappClient.sendMessageWithHumanizedDelay(fromJid, msg);

      await this._updateSession(session.phone_number, {
        current_step: BOT_STEPS.AWAITING_RESCHEDULE_CUSTOM_DATE,
        presented_options: upcoming,
      });
      return;
    } else {
      await whatsappClient.sendMessageWithHumanizedDelay(
        fromJid,
        `Invalid selection. Reply:\n*1* — Today\n*2* — Tomorrow\n*3* — Choose from upcoming dates\n\n_Reply 0 to cancel._`
      );
      return;
    }

    await this._presentRescheduleSlots(session, targetDate, fromJid, dept);
  }

  static async _handleRescheduleCustomDate(session, input, fromJid, patientName, dept) {
    const trimmed = input.trim();
    if (trimmed === '0') {
      await this._resetSession(session.phone_number);
      await whatsappClient.sendMessageWithHumanizedDelay(
        fromJid,
        'Rescheduling cancelled. Your original appointment remains active and unchanged.'
      );
      return;
    }

    const choice = parseInt(trimmed, 10);
    const options = session.presented_options || [];

    if (choice >= 1 && choice <= options.length) {
      const selectedDate = options[choice - 1];
      await this._presentRescheduleSlots(session, selectedDate.dateIso, fromJid, dept);
    } else {
      await whatsappClient.sendMessageWithHumanizedDelay(
        fromJid,
        `Invalid selection. Reply with *1*, *2*, or *3* to choose a date (or *0* to cancel).`
      );
    }
  }

  static async _presentRescheduleSlots(session, dateIso, fromJid, dept) {
    const slots = await SlotService.getAvailableSlots(dept, dateIso, CLINIC.CHAT_SLOT_DURATION_MINUTES);

    if (slots.length === 0) {
      await whatsappClient.sendMessageWithHumanizedDelay(
        fromJid,
        `Sorry, there are no available slots for ${dateIso} in ${dept.toUpperCase()}.\n\nYour original appointment remains active. Reply *3* to pick another date or *0* to cancel.`
      );
      await this._updateSession(session.phone_number, {
        current_step: BOT_STEPS.AWAITING_RESCHEDULE_DATE_CHOICE,
        selected_date: null,
      });
      return;
    }

    const selectedSlots = slots.slice(0, 4);

    let msg = `⏰ *Available slots for ${dateIso}:*\n\n`;
    selectedSlots.forEach((s, idx) => {
      msg += `*${idx + 1}* — ${s.formatted}\n`;
    });
    msg += `\nReply with your preferred slot number (1-${selectedSlots.length}) or *0* to choose another date:`;

    await whatsappClient.sendMessageWithHumanizedDelay(fromJid, msg);

    await this._updateSession(session.phone_number, {
      current_step: BOT_STEPS.AWAITING_RESCHEDULE_SLOT_CHOICE,
      selected_date: dateIso,
      presented_options: selectedSlots,
    });
  }

  static async _handleRescheduleSlotChoice(session, input, fromJid, patientName, dept, patient) {
    const trimmed = input.trim();
    if (trimmed === '0') {
      await this._updateSession(session.phone_number, {
        current_step: BOT_STEPS.AWAITING_RESCHEDULE_DATE_CHOICE,
        selected_slot: null,
      });
      await this._handleRescheduleDateChoice(session, '3', fromJid, patientName, dept);
      return;
    }

    const choice = parseInt(trimmed, 10);
    const options = session.presented_options || [];

    if (choice >= 1 && choice <= options.length) {
      const chosenSlot = options[choice - 1];
      const newDate = session.selected_date;
      await this._executeRescheduleCommit(session, newDate, chosenSlot, fromJid, patientName, dept, patient);
    } else {
      await whatsappClient.sendMessageWithHumanizedDelay(
        fromJid,
        `Invalid choice. Reply with a valid slot number (1 to ${options.length}) or *0* to pick another date.`
      );
    }
  }

  static async _handleRescheduleConfirmation(session, input, fromJid, patientName, dept, patient) {
    const trimmed = input.trim().toLowerCase();
    if (trimmed === '0' || trimmed === 'cancel') {
      await this._resetSession(session.phone_number);
      await whatsappClient.sendMessageWithHumanizedDelay(
        fromJid,
        'Rescheduling cancelled. Your original appointment remains active and unchanged.'
      );
      return;
    }

    if (trimmed === '1' || trimmed === 'yes' || trimmed === 'confirm') {
      const chosenSlot = session.reschedule_target_slot;
      const targetDate = session.selected_date;
      if (!chosenSlot || !targetDate) {
        await whatsappClient.sendMessageWithHumanizedDelay(
          fromJid,
          'Rescheduling session expired. Please reply *RESCHEDULE* to start again.'
        );
        await this._resetSession(session.phone_number);
        return;
      }
      await this._executeRescheduleCommit(session, targetDate, chosenSlot, fromJid, patientName, dept, patient);
    } else {
      await whatsappClient.sendMessageWithHumanizedDelay(
        fromJid,
        'Please reply *1* to confirm your rescheduled appointment time, or *0* to cancel and keep your current appointment.'
      );
    }
  }

  static async _executeRescheduleCommit(session, newDate, chosenSlot, fromJid, patientName, dept, patient) {
    const apptId = session.reschedule_appointment_id;

    if (!apptId) {
      logger.error('Missing reschedule_appointment_id in session.');
      await whatsappClient.sendMessageWithHumanizedDelay(fromJid, 'An error occurred during rescheduling. Please contact reception.');
      await this._resetSession(session.phone_number);
      return;
    }

    logger.info(`Executing reschedule for appt ${apptId} -> ${newDate} at ${chosenSlot.raw}`);

    // Prevent double booking before committing
    const { data: conflicts } = await supabase
      .from('appointments')
      .select('id')
      .eq('appointment_date', newDate)
      .eq('appointment_time', chosenSlot.raw)
      .eq('department', dept)
      .neq('id', apptId)
      .in('status', ['scheduled', 'confirmed']);

    if (conflicts && conflicts.length > 0) {
      logger.warn(`Reschedule collision detected: slot ${newDate} ${chosenSlot.raw} already booked.`);
      await whatsappClient.sendMessageWithHumanizedDelay(
        fromJid,
        `⚠️ The slot on *${newDate}* at *${chosenSlot.formatted}* was just booked by another patient.\n\n` +
        `Please reply *RESCHEDULE* to view remaining available times.`
      );
      await this._resetSession(session.phone_number);
      return;
    }

    // Attempt atomic stored procedure
    let rpcSuccess = false;
    let rpcError = null;

    try {
      const { data: res, error } = await supabase.rpc('reschedule_appointment_via_whatsapp', {
        p_appointment_id: apptId,
        p_new_date: newDate,
        p_new_time: chosenSlot.raw,
        p_duration_minutes: CLINIC.CHAT_SLOT_DURATION_MINUTES,
      });

      if (error) {
        rpcError = error.message;
      } else if (res && res.success) {
        rpcSuccess = true;
      } else if (res && !res.success) {
        rpcError = res.message;
      }
    } catch (callErr) {
      rpcError = callErr.message;
    }

    // Safe fallback if RPC not deployed or needs direct atomic update
    if (!rpcSuccess && (rpcError?.includes('does not exist') || rpcError?.includes('42883'))) {
      try {
        const { error: updErr } = await supabase
          .from('appointments')
          .update({
            appointment_date: newDate,
            appointment_time: chosenSlot.raw,
            status: 'confirmed',
            notes: `[Rescheduled via WhatsApp on ${new Date().toISOString()}]`,
            updated_at: new Date().toISOString(),
          })
          .eq('id', apptId);

        if (!updErr) {
          rpcSuccess = true;
        } else {
          rpcError = updErr.message;
        }
      } catch (fbErr) {
        rpcError = fbErr.message;
      }
    }

    if (rpcSuccess) {
      // Mark request in whatsapp_appointment_requests as approved so My Schedule shows it resolved
      if (session.reschedule_request_id) {
        try {
          await supabase
            .from('whatsapp_appointment_requests')
            .update({
              status: 'approved',
              requested_date: newDate,
              requested_time: chosenSlot.raw,
              promoted_appointment_id: apptId,
              reviewed_at: new Date().toISOString(),
              staff_remarks: 'Rescheduled directly via WhatsApp conversational interaction',
            })
            .eq('id', session.reschedule_request_id);
        } catch (_) {}
      }

      // Insert outbox confirmation - STRICTLY NO CLINIC LOCATION TEXT OR LINKS
      await supabase.from('whatsapp_messages_outbox').insert({
        recipient_phone: session.phone_number,
        patient_id: patient?.id,
        appointment_id: apptId,
        department: dept,
        message_type: 'rescheduled',
        template_key: `reschedule_conf_${apptId}_${newDate}`,
        message_text: `🔄 *MKES CARE+ Appointment Rescheduled!*\n\nDear ${patientName}, your ${dept.toUpperCase()} appointment is now confirmed for *${newDate}* at *${chosenSlot.formatted}*.\n\nReply STOP to unsubscribe.`,
      });

      // Generate staff notification for department staff & admins
      await this._notifyStaffOfReschedule(patientName, dept, newDate, chosenSlot.formatted, apptId);

      // User confirmation message - STRICTLY NO LOCATION TEXT OR LINKS
      const successMsg =
        `✅ *Appointment Successfully Rescheduled!*\n\n` +
        `Dear ${patientName},\n` +
        `Your *${dept.toUpperCase()}* appointment at MKES CARE+ has been successfully updated:\n\n` +
        `📅 *New Date:* ${newDate}\n` +
        `⏰ *New Time:* ${chosenSlot.formatted}\n\n` +
        `_Please arrive 10 minutes prior to your time._\n` +
        `_Reply STOP to unsubscribe._`;

      await whatsappClient.sendMessageWithHumanizedDelay(fromJid, successMsg);
      await this._resetSession(session.phone_number);
    } else {
      logger.error(`Rescheduling failed for ${apptId}: ${rpcError}`);
      await whatsappClient.sendMessageWithHumanizedDelay(
        fromJid,
        `⚠️ The requested slot (${chosenSlot.formatted}) could not be reserved (${rpcError || 'Slot unavailable'}).\n\n` +
        `Your original appointment remains active. Please reply with another slot number or *0* to pick another date.`
      );
    }
  }

  static async _getPendingReadyDentalLabCase(patientId) {
    if (!patientId) return null;
    try {
      const { data, error } = await supabase
        .from('dental_lab')
        .select('*')
        .eq('patient_id', patientId)
        .eq('status', 'ready')
        .is('appointment_id', null)
        .order('ready_date', { ascending: false })
        .limit(1);

      if (error || !data || data.length === 0) return null;
      return data[0];
    } catch (_) {
      return null;
    }
  }

  static async _handleDentalLabCaseReply(session, body, fromJid, patient, labCase) {
    const trimmed = body.trim();
    const choiceNum = parseInt(trimmed, 10);
    const parsedDate = SlotService.parseRequestedDate(trimmed);
    const parsedTime = SlotService.parseRequestedTime(trimmed);

    if ((isNaN(choiceNum) || choiceNum < 1 || choiceNum > 3) && !parsedDate && !parsedTime) {
      return false;
    }

    let targetDate = null;
    let targetTime = null;
    let timeFormatted = '';

    const today = new Date();
    if (choiceNum === 1) {
      let d = new Date(today);
      d.setDate(d.getDate() + 2);
      if (d.getDay() === 0) d.setDate(d.getDate() + 1);
      targetDate = d.toISOString().split('T')[0];
      targetTime = '10:30:00';
      timeFormatted = '10:30 AM';
    } else if (choiceNum === 2) {
      let d = new Date(today);
      d.setDate(d.getDate() + 3);
      if (d.getDay() === 0) d.setDate(d.getDate() + 1);
      targetDate = d.toISOString().split('T')[0];
      targetTime = '14:00:00';
      timeFormatted = '02:00 PM';
    } else if (choiceNum === 3) {
      let d = new Date(today);
      d.setDate(d.getDate() + 4);
      if (d.getDay() === 0) d.setDate(d.getDate() + 1);
      targetDate = d.toISOString().split('T')[0];
      targetTime = '11:30:00';
      timeFormatted = '11:30 AM';
    } else if (parsedDate || parsedTime) {
      targetDate = parsedDate || SlotService.getTomorrowIST();
      targetTime = parsedTime || '11:00:00';
      timeFormatted = SlotService.formatTime12Hour(targetTime);
    } else {
      return false;
    }

    // Recheck availability before booking
    const isAvail = await SlotService.isSlotAvailable('dental', targetDate, targetTime);
    if (!isAvail) {
      const altSlots = await SlotService.getAvailableSlots('dental', targetDate);
      let altMsg = `⚠️ The requested slot on *${targetDate}* at *${timeFormatted}* is no longer available.\n\n` +
        `Here are available alternative slots:\n`;
      (altSlots.slice(0, 3)).forEach((s, idx) => {
        altMsg += `*${idx + 1}* — ${s.formatted}\n`;
      });
      altMsg += `\nPlease reply with your preferred slot number or contact dental reception.`;
      await whatsappClient.sendMessageWithHumanizedDelay(fromJid, altMsg);
      return true;
    }

    try {
      const { data: newAppt, error: apptErr } = await supabase
        .from('appointments')
        .insert({
          patient_id: patient.id,
          department: 'dental',
          appointment_date: targetDate,
          appointment_time: targetTime,
          appointment_type: 'follow_up',
          status: 'scheduled',
          notes: `Follow-up fitting for Dental Lab Case #${labCase.case_number} (${labCase.case_type}) confirmed via WhatsApp`,
        })
        .select('id')
        .single();

      if (apptErr || !newAppt) {
        logger.error(`Failed to book lab fitting appointment: ${apptErr?.message}`);
        await whatsappClient.sendMessageWithHumanizedDelay(
          fromJid,
          'An error occurred while booking your fitting appointment. Our dental reception has been notified to assist you.'
        );
        return true;
      }

      await supabase
        .from('dental_lab')
        .update({ appointment_id: newAppt.id })
        .eq('id', labCase.id);

      const confText =
        `✅ *Dental Fitting Appointment Confirmed!*\n\n` +
        `Dear ${patient.name || 'Valued Patient'},\n` +
        `Your fitting appointment for *${labCase.case_type}* (Ref: #${labCase.case_number}) has been scheduled:\n\n` +
        `📅 *Date:* ${targetDate}\n` +
        `⏰ *Time:* ${timeFormatted}\n\n` +
        `_Please arrive 10 minutes prior to your time._\n` +
        `_Reply STOP to unsubscribe._`;

      await whatsappClient.sendMessageWithHumanizedDelay(fromJid, confText);

      const { data: staffList } = await supabase
        .from('profiles')
        .select('id')
        .eq('is_active', true)
        .or(`role.eq.admin,and(role.eq.staff,department.ilike.%dental%)`);

      if (staffList && staffList.length > 0) {
        for (const s of staffList) {
          await supabase.from('notifications').insert({
            user_id: s.id,
            title: 'Dental Lab Fitting Booked (WhatsApp)',
            message: `${patient.name || 'Patient'} confirmed fitting for Case #${labCase.case_number} on ${targetDate} at ${timeFormatted}.`,
            type: 'dental_lab_ready',
            related_id: labCase.id,
            is_read: false,
          });
        }
      }

      logger.info(`Fitting appointment ${newAppt.id} successfully booked for Dental Lab Case ${labCase.id}`);
      return true;
    } catch (err) {
      logger.error(`Exception in _handleDentalLabCaseReply: ${err.message}`, err);
      return false;
    }
  }

  // --------------------------------------------------------------------------
  // Notification & Audit Helpers
  // --------------------------------------------------------------------------

  static async _notifyStaffOfInboundMessage(patient, phone, body) {
    try {
      const patientTitle = patient?.name ? `WhatsApp from ${patient.name}` : `WhatsApp from +91 ${phone}`;
      const snippet = body.length > 80 ? body.substring(0, 80) + '...' : body;
      const dept = (patient?.department || 'dental').toLowerCase();

      // Optical Exclusion
      if (dept === 'optical') return;

      const { data: admins } = await supabase
        .from('profiles')
        .select('id')
        .eq('is_active', true)
        .or(`role.eq.admin,and(role.eq.staff,department.ilike.%${dept}%)`);

      if (admins && admins.length > 0) {
        for (const admin of admins) {
          await supabase.from('notifications').insert({
            user_id: admin.id,
            title: patientTitle,
            message: snippet,
            type: 'whatsapp_reply',
            related_id: patient?.id || null,
            is_read: false,
          });
        }
      }

      // Dispatch push notification to department staff & admins
      await pushNotificationBackend.dispatchToDepartmentStaff({
        department: dept,
        type: 'whatsapp_reply',
        title: 'New Patient Message',
        body: `Message received from ${patient?.name || ('+91 ' + phone)}.`,
        patientName: patient?.name,
        relatedId: patient?.id || null,
        idempotencyKey: `inbound_${phone}_${Date.now()}`,
      });
    } catch (err) {
      logger.debug(`Staff in-app notification skipped: ${err.message}`);
    }
  }

  static async _notifyStaffOfRescheduleRequest(patient, appt, dept) {
    try {
      const deptNormalized = (dept || appt?.department || 'dental').toLowerCase();
      if (deptNormalized === 'optical') return;

      const patientName = patient?.name || 'A patient';
      const prompt = `${patientName} requested to reschedule their ${deptNormalized.toUpperCase()} appointment.`;

      const { data: staffList } = await supabase
        .from('profiles')
        .select('id, role, department')
        .eq('is_active', true)
        .or(`role.eq.admin,and(role.eq.staff,department.ilike.%${deptNormalized}%)`);

      if (staffList && staffList.length > 0) {
        for (const staff of staffList) {
          await supabase.from('notifications').insert({
            user_id: staff.id,
            title: 'Reschedule Requested (WhatsApp)',
            message: prompt,
            type: 'appointment_rescheduled',
            related_id: appt?.id || null,
            is_read: false,
          });
        }
      }

      await pushNotificationBackend.dispatchToDepartmentStaff({
        department: deptNormalized,
        type: 'appointment_rescheduled',
        title: 'Reschedule Requested',
        body: prompt,
        patientName: patient?.name,
        relatedId: appt?.id || null,
        idempotencyKey: `resched_req_${patient?.mobile || ''}_${appt?.id || ''}_${new Date().toISOString().slice(0, 13)}`,
      });
    } catch (e) {
      logger.debug(`Staff reschedule request notification skipped: ${e.message}`);
    }
  }

  static async _notifyStaffOfReschedule(patientName, dept, newDate, newTime, apptId) {
    try {
      const deptNormalized = (dept || 'dental').toLowerCase();
      if (deptNormalized === 'optical') return;

      const { data: staffList } = await supabase
        .from('profiles')
        .select('id')
        .eq('is_active', true)
        .or(`role.eq.admin,and(role.eq.staff,department.ilike.%${deptNormalized}%)`);

      if (staffList && staffList.length > 0) {
        for (const staff of staffList) {
          await supabase.from('notifications').insert({
            user_id: staff.id,
            title: 'Appointment Rescheduled via WhatsApp',
            message: `${patientName} rescheduled their ${deptNormalized.toUpperCase()} appointment to ${newDate} at ${newTime}.`,
            type: 'appointment_rescheduled',
            related_id: apptId,
            is_read: false,
          });
        }
      }

      // Dispatch push notification to department staff & admins
      await pushNotificationBackend.dispatchToDepartmentStaff({
        department: deptNormalized,
        type: 'appointment_rescheduled',
        title: 'Appointment Rescheduled',
        body: `${patientName} rescheduled their consultation.`,
        patientName,
        relatedId: apptId,
        idempotencyKey: `resched_success_${apptId}_${newDate}_${newTime}`,
      });
    } catch (e) {
      logger.debug(`Staff reschedule notification skipped: ${e.message}`);
    }
  }

  static async _getOrCreateSession(phone, patient) {
    const { data: existing } = await supabase
      .from('whatsapp_chat_sessions')
      .select('*')
      .eq('phone_number', phone)
      .maybeSingle();

    const now = Date.now();
    const expiryMs = 30 * 60 * 1000; // 30 minutes

    if (existing) {
      const lastInteraction = existing.last_interaction ? new Date(existing.last_interaction).getTime() : 0;
      const isExpired = (now - lastInteraction) > expiryMs;

      if (isExpired) {
        logger.info(`Session for ${phone} expired (last interaction > 30m). Resetting.`);
        await this._resetSession(phone);
        return {
          phone_number: phone,
          patient_id: patient?.id,
          current_step: BOT_STEPS.IDLE,
          selected_department: patient?.department || 'dental',
          selected_date: null,
          selected_slot: null,
          presented_options: [],
          last_interaction: new Date().toISOString(),
          last_message_body: null,
          last_message_time: null,
        };
      }

      const sData = existing.session_data || {};
      return {
        phone_number: phone,
        patient_id: sData.patient_id || patient?.id,
        current_step: existing.current_state || BOT_STEPS.IDLE,
        selected_department: sData.selected_department || patient?.department || 'dental',
        selected_date: sData.selected_date || null,
        selected_slot: sData.selected_slot || null,
        presented_options: sData.presented_options || [],
        presented_appointments: sData.presented_appointments || [],
        reschedule_appointment_id: sData.reschedule_appointment_id || null,
        last_interaction: existing.last_interaction,
        last_message_body: sData.last_message_body || null,
        last_message_time: sData.last_message_time || null,
      };
    }

    const defaultSessionData = {
      patient_id: patient?.id,
      selected_department: patient?.department || 'dental',
      selected_date: null,
      selected_slot: null,
      presented_options: [],
      presented_appointments: [],
    };

    await supabase
      .from('whatsapp_chat_sessions')
      .upsert({
        phone_number: phone,
        current_state: BOT_STEPS.IDLE,
        session_data: defaultSessionData,
        last_interaction: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }, { onConflict: 'phone_number' });

    return {
      phone_number: phone,
      current_step: BOT_STEPS.IDLE,
      ...defaultSessionData,
      last_interaction: new Date().toISOString(),
      last_message_body: null,
      last_message_time: null,
    };
  }

  static async _updateSession(phone, updates) {
    const { data: existing } = await supabase
      .from('whatsapp_chat_sessions')
      .select('*')
      .eq('phone_number', phone)
      .maybeSingle();

    const prevData = existing?.session_data || {};
    const nextState = updates.current_step || existing?.current_state || BOT_STEPS.IDLE;
    const nextData = {
      ...prevData,
      ...updates,
    };
    delete nextData.current_step;

    await supabase
      .from('whatsapp_chat_sessions')
      .upsert({
        phone_number: phone,
        current_state: nextState,
        session_data: nextData,
        last_interaction: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }, { onConflict: 'phone_number' });
  }

  static async _resetSession(phone) {
    await supabase
      .from('whatsapp_chat_sessions')
      .upsert({
        phone_number: phone,
        current_state: BOT_STEPS.IDLE,
        session_data: {
          selected_date: null,
          selected_slot: null,
          presented_options: [],
          presented_appointments: [],
          reschedule_appointment_id: null,
        },
        last_interaction: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }, { onConflict: 'phone_number' });
  }

  static async _logInboundMessage(phone, body, msg, patientId = null) {
    try {
      const cleanTen = PhoneNormalizer.extractTenDigits(phone);
      const normalizedPhone = cleanTen || phone;
      await supabase.from('whatsapp_message_logs').insert({
        direction: 'inbound',
        phone_number: normalizedPhone,
        patient_id: patientId || null,
        message_body: body || '[Message]',
        raw_payload: {
          id: msg.id?._serialized,
          timestamp: msg.timestamp,
          from: msg.from,
          type: msg.type,
          hasMedia: msg.hasMedia,
        },
      });
    } catch (e) {
      logger.error(`Error logging inbound message: ${e.message}`);
    }
  }
}

module.exports = BotEngine;
