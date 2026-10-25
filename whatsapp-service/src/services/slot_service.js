const { supabase } = require('../config/supabase');
const logger = require('../utils/logger');
const { CLINIC } = require('../config/constants');

class SlotService {
  /**
   * Fetches genuine free slots from Supabase RPC get_available_appointment_slots.
   * Handles 15-minute grid, clinic operating hours (09:00 - 20:00), and overlap prevention.
   */
  static async getAvailableSlots(department, dateStr, slotDurationMinutes = CLINIC.CHAT_SLOT_DURATION_MINUTES) {
    try {
      logger.info(`Fetching available slots for dept=${department}, date=${dateStr}, duration=${slotDurationMinutes}m`);

      const { data, error } = await supabase.rpc('get_available_appointment_slots', {
        p_department: department.toLowerCase().trim(),
        p_date: dateStr,
        p_slot_duration_minutes: slotDurationMinutes,
        p_interval_minutes: 15,
      });

      if (error) {
        if (error.code === 'PGRST202' || error.message?.includes('does not exist') || error.code === '42883') {
          logger.warn(`Slot query skipped: Database RPC 'get_available_appointment_slots' not yet applied to database.`);
        } else {
          logger.error(`Error fetching slots from RPC: ${error.message}`, error);
        }
        return [];
      }

      if (!data || !Array.isArray(data)) {
        return [];
      }

      // Format time values for patient display (e.g. "10:30:00" -> "10:30 AM")
      return data.map((row) => {
        const rawTime = row.slot_time;
        return {
          raw: rawTime,
          formatted: this.formatTime12Hour(rawTime),
        };
      });
    } catch (err) {
      logger.error(`Exception in getAvailableSlots: ${err.message}`, err);
      return [];
    }
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
