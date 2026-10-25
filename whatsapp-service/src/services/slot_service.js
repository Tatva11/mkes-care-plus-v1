const { supabase } = require('../config/supabase');
const logger = require('../utils/logger');
const { CLINIC } = require('../config/constants');

class SlotService {
  /**
   * Fetches genuine free slots from Supabase RPC get_available_appointment_slots.
   * Handles 15-minute grid, clinic operating hours (09:00 - 20:00), and overlap prevention.
   */
  /**
   * Fetches genuine free slots from Supabase RPC get_available_appointment_slots,
   * with resilient direct calendar computation fallback.
   * Handles 15-minute grid, clinic operating hours (09:00 - 20:00), and overlap prevention.
   */
  static async getAvailableSlots(department, dateStr, slotDurationMinutes = CLINIC.CHAT_SLOT_DURATION_MINUTES, doctorId = null) {
    try {
      logger.info(`Fetching available slots for dept=${department}, date=${dateStr}, duration=${slotDurationMinutes}m, doc=${doctorId || 'any'}`);

      const params = {
        p_department: department.toLowerCase().trim(),
        p_date: dateStr,
        p_slot_duration_minutes: slotDurationMinutes,
        p_interval_minutes: 15,
      };
      if (doctorId) {
        params.p_doctor_id = doctorId;
      }

      const { data, error } = await supabase.rpc('get_available_appointment_slots', params);

      if (!error && Array.isArray(data) && data.length > 0) {
        return data.map((row) => {
          const rawTime = row.slot_time;
          return {
            raw: rawTime,
            formatted: this.formatTime12Hour(rawTime),
          };
        });
      }

      // If RPC is unavailable or returns empty (e.g. empty department_doctors config table),
      // seamlessly execute direct calendar capacity computation
      logger.info(`Using direct calendar computation fallback for dept=${department}, date=${dateStr}`);
      return await this._getAvailableSlotsFallback(department, dateStr, slotDurationMinutes, doctorId);
    } catch (err) {
      logger.error(`Exception in getAvailableSlots: ${err.message}`, err);
      return await this._getAvailableSlotsFallback(department, dateStr, slotDurationMinutes, doctorId);
    }
  }

  /**
   * Direct calendar computation fallback checking booked appointments and operating hours.
   */
  static async _getAvailableSlotsFallback(department, dateStr, slotDurationMinutes = 15, doctorId = null) {
    try {
      const dept = (department || 'dental').toLowerCase().trim();
      const openingHour = CLINIC.OPENING_HOUR || 9;
      const closingHour = CLINIC.CLOSING_HOUR || 20;

      // 1. Fetch booked appointments for this date and department/doctor
      let apptQuery = supabase
        .from('appointments')
        .select('appointment_time, duration_minutes, doctor_id')
        .eq('appointment_date', dateStr)
        .in('status', ['scheduled', 'confirmed']);

      if (doctorId) {
        apptQuery = apptQuery.eq('doctor_id', doctorId);
      } else {
        apptQuery = apptQuery.eq('department', dept);
      }

      const { data: bookedAppts } = await apptQuery;

      // 2. Fetch pending whatsapp requests for same date
      let reqQuery = supabase
        .from('whatsapp_appointment_requests')
        .select('requested_time, duration_minutes, doctor_id')
        .eq('requested_date', dateStr)
        .eq('status', 'pending_review')
        .is('promoted_appointment_id', null);

      if (doctorId) {
        reqQuery = reqQuery.eq('doctor_id', doctorId);
      } else {
        reqQuery = reqQuery.eq('department', dept);
      }

      const { data: bookedReqs } = await reqQuery;

      const busyIntervals = [];
      const addBusy = (timeStr, duration = 15) => {
        if (!timeStr) return;
        const [h, m] = timeStr.split(':').map(Number);
        const startMin = h * 60 + (m || 0);
        const endMin = startMin + (duration || 15);
        busyIntervals.push({ start: startMin, end: endMin });
      };

      (bookedAppts || []).forEach((a) => addBusy(a.appointment_time, a.duration_minutes));
      (bookedReqs || []).forEach((r) => addBusy(r.requested_time, r.duration_minutes));

      // Calculate same-day buffer (at least 75 min from current time if date is today)
      const todayIso = this.getTodayIST();
      let minStartMin = openingHour * 60;
      if (dateStr === todayIso) {
        const istNow = this.getISTDate();
        minStartMin = Math.max(minStartMin, istNow.getHours() * 60 + istNow.getMinutes() + 75);
      }

      const freeSlots = [];
      const endOfDayMin = closingHour * 60;

      for (let currMin = openingHour * 60; currMin + slotDurationMinutes <= endOfDayMin; currMin += 15) {
        if (currMin < minStartMin) continue;

        const slotEnd = currMin + slotDurationMinutes;
        const isOverlap = busyIntervals.some((b) => currMin < b.end && slotEnd > b.start);

        if (!isOverlap) {
          const h = Math.floor(currMin / 60);
          const m = currMin % 60;
          const raw = `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:00`;
          freeSlots.push({
            raw,
            formatted: this.formatTime12Hour(raw),
          });
        }
      }

      return freeSlots;
    } catch (e) {
      logger.error(`Error calculating fallback slots: ${e.message}`);
      return [];
    }
  }

  /**
   * Extracts requested date from natural language text (e.g. "tomorrow", "today", "friday", "2026-10-27").
   */
  static parseRequestedDate(text) {
    if (!text) return null;
    const lower = text.toLowerCase().trim();

    if (/\btoday\b/.test(lower)) {
      return this.getTodayIST();
    }
    if (/\btomorrow\b/.test(lower)) {
      return this.getTomorrowIST();
    }

    // Days of the week
    const days = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
    for (let dayIndex = 0; dayIndex < days.length; dayIndex++) {
      if (new RegExp(`\\b${days[dayIndex]}\\b`).test(lower)) {
        const istNow = this.getISTDate();
        let diff = dayIndex - istNow.getDay();
        if (diff <= 0) diff += 7; // Next occurrence
        const target = new Date(istNow);
        target.setDate(target.getDate() + diff);
        return this.formatDateIso(target);
      }
    }

    // YYYY-MM-DD
    const isoMatch = lower.match(/\b(20\d\d)-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])\b/);
    if (isoMatch) return isoMatch[0];

    // DD/MM/YYYY or DD-MM-YYYY
    const dmyMatch = lower.match(/\b(0?[1-9]|[12]\d|3[01])[\/-](0?[1-9]|1[0-2])[\/-](20\d\d)\b/);
    if (dmyMatch) {
      const day = dmyMatch[1].padStart(2, '0');
      const month = dmyMatch[2].padStart(2, '0');
      const year = dmyMatch[3];
      return `${year}-${month}-${day}`;
    }

    return null;
  }

  /**
   * Extracts requested time from natural language text (e.g. "11:00 am", "4pm", "10:30", "14:00").
   */
  static parseRequestedTime(text) {
    if (!text) return null;
    const lower = text.toLowerCase().trim();

    // 12-hour format: e.g. "11:30 am", "11am", "4:15pm", "4 pm"
    const match12 = lower.match(/\b(1[0-2]|0?[1-9])(?::([0-5]\d))?\s*(am|pm)\b/);
    if (match12) {
      let hour = parseInt(match12[1], 10);
      const minute = match12[2] ? match12[2] : '00';
      const ampm = match12[3];

      if (ampm === 'pm' && hour < 12) hour += 12;
      if (ampm === 'am' && hour === 12) hour = 0;

      return `${String(hour).padStart(2, '0')}:${minute}:00`;
    }

    // 24-hour format: e.g. "14:30", "10:00", "09:15"
    const match24 = lower.match(/\b([01]?\d|2[0-3]):([0-5]\d)\b/);
    if (match24) {
      const hour = parseInt(match24[1], 10);
      const minute = match24[2];
      return `${String(hour).padStart(2, '0')}:${minute}:00`;
    }

    return null;
  }

  /**
   * Converts 24-hour time "14:30:00" to "02:30 PM".
   */
  static formatTime12Hour(timeStr) {
    if (!timeStr) return '';
    const parts = timeStr.split(':');
    let hour = parseInt(parts[0], 10);
    const minute = parts[1] || '00';
    const ampm = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour === 0) hour = 12;
    const hourStr = hour < 10 ? `0${hour}` : `${hour}`;
    return `${hourStr}:${minute} ${ampm}`;
  }

  /**
   * Helper to format a Date object as YYYY-MM-DD using its local calendar components.
   */
  static formatDateIso(d) {
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  /**
   * Helper to get current Date object in Indian Standard Time (IST, UTC+5:30).
   */
  static getISTDate(date = new Date()) {
    const utc = date.getTime() + date.getTimezoneOffset() * 60000;
    return new Date(utc + 3600000 * 5.5);
  }

  /**
   * Returns today's ISO date string (YYYY-MM-DD) in IST.
   */
  static getTodayIST() {
    return this.formatDateIso(this.getISTDate());
  }

  /**
   * Returns tomorrow's ISO date string (YYYY-MM-DD) in IST.
   */
  static getTomorrowIST() {
    const tomorrow = this.getISTDate();
    tomorrow.setDate(tomorrow.getDate() + 1);
    return this.formatDateIso(tomorrow);
  }

  /**
   * Generates up to 3 upcoming working dates starting from the day after tomorrow (Day+2),
   * in Indian Standard Time (IST), skipping Sundays.
   */
  static getEligibleUpcomingDates(startDate = null, count = 3) {
    const dates = [];
    const current = startDate ? this.getISTDate(new Date(startDate)) : this.getISTDate();
    // Option 1 is Today, Option 2 is Tomorrow, so "Another Date" starts from Day+2
    current.setDate(current.getDate() + 2);

    while (dates.length < count) {
      // Clinic operates Mon-Sat (skip Sunday 0)
      if (current.getDay() !== 0) {
        const dateIso = this.formatDateIso(current);
        const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        
        dates.push({
          dateIso,
          display: `${dayNames[current.getDay()]}, ${current.getDate()} ${monthNames[current.getMonth()]}`,
        });
      }
      current.setDate(current.getDate() + 1);
    }

    return dates;
  }
}

module.exports = SlotService;
