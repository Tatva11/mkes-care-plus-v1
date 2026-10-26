/**
 * Phone Number Normalization Utility
 * Specifically optimized for Indian mobile numbers (+91, 10 digits, leading zero).
 */

class PhoneNormalizer {
  /**
   * Extracts clean numeric digits only.
   */
  static cleanDigits(raw) {
    if (!raw) return '';
    return String(raw).replace(/[^0-9]/g, '');
  }

  /**
   * Extracts the authoritative 10-digit national number.
   * Handles: 9876543210, 09876543210, 919876543210, +91-9876543210
   */
  static extractTenDigits(raw) {
    const digits = this.cleanDigits(raw);
    if (digits.length < 10) return null;
    return digits.slice(-10);
  }

  /**
   * Normalizes to standard 12-digit Indian format (e.g. 919876543210).
   */
  static toIndianE164(raw) {
    const ten = this.extractTenDigits(raw);
    if (!ten) return null;
    return `91${ten}`;
  }

  /**
   * Normalizes to WhatsApp JID (e.g. 919876543210@c.us).
   */
  static toWhatsAppJid(raw) {
    const formatted = this.toIndianE164(raw);
    if (!formatted) return null;
    return `${formatted}@c.us`;
  }

  /**
   * Checks if an incoming sender JID is an individual WhatsApp chat (not a group).
   */
  static isIndividualChat(jid) {
    if (typeof jid !== 'string') return false;
    if (jid.endsWith('@g.us') || jid.includes('@broadcast') || jid.endsWith('@newsletter')) {
      return false;
    }
    return jid.endsWith('@c.us') || jid.endsWith('@s.whatsapp.net') || jid.endsWith('@lid');
  }
}

module.exports = PhoneNormalizer;
