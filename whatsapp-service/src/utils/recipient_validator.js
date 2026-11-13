/**
 * MKES CARE+ WhatsApp Integration — Recipient Validator & Ack Verifier
 * 
 * Ensures strict identity verification, E.164 normalization,
 * read-only lookup-only diagnostics, and reliable message acknowledgement tracking.
 */

const PhoneNormalizer = require('./phone_normalizer');

class RecipientValidator {
  /**
   * Prepares and normalizes input phone number for WhatsApp directory lookup.
   * Strictly enforces +91 country prefix for Indian mobile numbers before calling getNumberId().
   *
   * @param {string} rawPhone
   * @returns {{ success: boolean, e164?: string, expectedJid?: string, tenDigits?: string, error?: string }}
   */
  static prepareLookupNumber(rawPhone) {
    if (!rawPhone) {
      return { success: false, error: 'Phone number cannot be empty.' };
    }

    const tenDigits = PhoneNormalizer.extractTenDigits(rawPhone);
    if (!tenDigits || tenDigits.length !== 10) {
      return {
        success: false,
        error: `Invalid Indian phone number: "${rawPhone}". Must contain at least 10 valid digits.`,
      };
    }

    // In India, mobile numbers start with 6, 7, 8, or 9
    const firstDigit = tenDigits[0];
    if (!['6', '7', '8', '9'].includes(firstDigit)) {
      return {
        success: false,
        error: `Invalid Indian mobile number: "${tenDigits}". Mobile numbers in India start with 6, 7, 8, or 9.`,
      };
    }

    const e164 = `91${tenDigits}`;
    const expectedJid = `${e164}@c.us`;

    return {
      success: true,
      e164,
      expectedJid,
      tenDigits,
    };
  }

  /**
   * Validates the result from WhatsApp Web's getNumberId() against expected identity.
   * REJECTS unverified @lid identifiers and number mismatches.
   * Confirms `isSelf` by checking against authenticated client.info.wid object.
   *
   * @param {object} params
   * @param {string} params.expectedE164 - e.g. "918080030111"
   * @param {string} params.expectedJid  - e.g. "918080030111@c.us"
   * @param {object|null} params.resolvedNumberId - result from client.getNumberId()
   * @param {object|string} [params.connectedWid] - e.g. client.info?.wid or string
   * @param {string} [params.connectedUser] - fallback string e.g. client.info?.wid?.user
   * @param {object|null} [params.verifiedMapping] - output from inspectLidAndPhoneMapping()
   * @returns {{ valid: boolean, targetJid?: string, serialized?: string, isSelf?: boolean, reason?: string, error?: string, mappingVerified?: boolean }}
   */
  static validateResolvedRecipient({ expectedE164, expectedJid, resolvedNumberId, connectedWid, connectedUser, verifiedMapping }) {
    if (!expectedE164 || !expectedJid) {
      return {
        valid: false,
        reason: 'MISSING_EXPECTATION',
        error: 'Missing expected E.164 or JID for recipient verification.',
      };
    }

    // 1. Not registered on WhatsApp
    if (!resolvedNumberId) {
      return {
        valid: false,
        reason: 'NOT_REGISTERED',
        error: `Phone number +${expectedE164} is not registered on WhatsApp.`,
      };
    }

    const serialized = resolvedNumberId._serialized || resolvedNumberId.id || (typeof resolvedNumberId === 'string' ? resolvedNumberId : '');
    const user = resolvedNumberId.user || (serialized.includes('@') ? serialized.split('@')[0] : '');

    // 2. Reject unverified @lid identifiers unless verified bidirectional mapping exists
    if (serialized.endsWith('@lid')) {
      const isVerifiedMapping = Boolean(
        verifiedMapping &&
        verifiedMapping.conclusion === 'VERIFIED_BIDIRECTIONAL_MATCH' &&
        verifiedMapping.matchesAuthSession === true &&
        verifiedMapping.lidLookup?.lid === serialized &&
        verifiedMapping.lidLookup?.pn === expectedJid &&
        verifiedMapping.phoneLookup?.lid === serialized &&
        verifiedMapping.phoneLookup?.pn === expectedJid
      );

      if (!isVerifiedMapping) {
        return {
          valid: false,
          reason: 'UNVERIFIED_LID',
          error: `Unverified recipient identity: WhatsApp directory returned an opaque LID (${serialized}) instead of the expected E.164 phone JID (${expectedJid}). Dispatch aborted for patient safety.`,
        };
      }

      // Verified mapping confirmed: Target JID is ALWAYS the canonical phone JID, NEVER the @lid
      let authWidSerialized = null;
      let authWidUser = null;
      if (connectedWid && typeof connectedWid === 'object') {
        authWidSerialized = connectedWid._serialized || null;
        authWidUser = connectedWid.user || null;
      } else if (typeof connectedWid === 'string') {
        authWidSerialized = connectedWid;
        authWidUser = connectedWid.split('@')[0];
      } else if (connectedUser) {
        authWidUser = PhoneNormalizer.extractTenDigits(connectedUser);
        authWidSerialized = authWidUser ? `91${authWidUser}@c.us` : null;
      }

      const isSelf = Boolean(
        authWidSerialized &&
        expectedJid === authWidSerialized &&
        authWidUser &&
        (expectedE164 === authWidUser || expectedE164 === `91${authWidUser}`)
      );

      return {
        valid: true,
        targetJid: expectedJid, // Canonical phone JID strictly enforced, NEVER @lid!
        serialized,
        isSelf,
        mappingVerified: true,
      };
    }

    // 3. Verify user portion matches expected E.164 number
    if (user !== expectedE164 || serialized !== expectedJid) {
      return {
        valid: false,
        reason: 'NUMBER_MISMATCH',
        error: `Recipient identity mismatch: Expected ${expectedJid} but WhatsApp resolved to ${serialized}.`,
      };
    }

    // 4. Trustworthy Identity Check for Self-Account:
    // Compares the resolved recipient's verified serialized JID against the authenticated client's WID
    let authWidSerialized = null;
    let authWidUser = null;
    if (connectedWid && typeof connectedWid === 'object') {
      authWidSerialized = connectedWid._serialized || null;
      authWidUser = connectedWid.user || null;
    } else if (typeof connectedWid === 'string') {
      authWidSerialized = connectedWid;
      authWidUser = connectedWid.split('@')[0];
    } else if (connectedUser) {
      authWidUser = PhoneNormalizer.extractTenDigits(connectedUser);
      authWidSerialized = authWidUser ? `91${authWidUser}@c.us` : null;
    }

    const isSelf = Boolean(
      authWidSerialized &&
      serialized === authWidSerialized &&
      authWidUser &&
      (user === authWidUser || user === `91${authWidUser}`)
    );

    return {
      valid: true,
      targetJid: expectedJid,
      serialized,
      isSelf,
    };
  }

  /**
   * Performs a safe, read-only recipient lookup and identity verification.
   * STRUCTURAL SAFETY: Contains zero calls to client.sendMessage().
   *
   * @param {object} params
   * @param {object} params.client - WhatsApp Web client instance
   * @param {string} params.targetPhone - Input phone number to lookup
   * @returns {Promise<{ success: boolean, status: string, inputPhone?: string, expectedJid?: string, resolvedWid?: string, targetJid?: string, isSelf?: boolean, error?: string, sendMessageCalled: false }>}
   */
  static async performLookupOnly({ client, targetPhone }) {
    // 1. Prepare lookup number
    const prep = this.prepareLookupNumber(targetPhone);
    if (!prep.success) {
      return {
        success: false,
        status: 'INVALID_INPUT',
        error: prep.error,
        sendMessageCalled: false,
      };
    }

    const { e164, expectedJid } = prep;
    let resolvedNumberId = null;
    try {
      resolvedNumberId = await client.getNumberId(e164);
    } catch (err) {
      return {
        success: false,
        status: 'LOOKUP_ERROR',
        error: `Directory lookup failed: ${err.message}`,
        sendMessageCalled: false,
      };
    }

    // 2. Validate resolved recipient against authenticated session
    const validation = this.validateResolvedRecipient({
      expectedE164: e164,
      expectedJid,
      resolvedNumberId,
      connectedWid: client?.info?.wid,
    });

    // 3. Inspect LID mapping if client supports getContactLidAndPhone
    let mappingReport = null;
    const resolvedSerialized = resolvedNumberId?._serialized || '';
    const lidToInspect = resolvedSerialized.endsWith('@lid') ? resolvedSerialized : '170141321052179@lid';
    if (client && typeof client.getContactLidAndPhone === 'function') {
      mappingReport = await this.inspectLidAndPhoneMapping({
        client,
        lidId: lidToInspect,
        phoneId: expectedJid,
        connectedWid: client?.info?.wid,
      });
    }

    return {
      success: validation.valid,
      status: validation.valid ? 'VERIFIED' : validation.reason,
      inputPhone: `+${e164}`,
      expectedJid,
      resolvedWid: resolvedNumberId?._serialized || null,
      targetJid: validation.targetJid || null,
      isSelf: validation.isSelf || false,
      error: validation.error || null,
      mappingReport,
      sendMessageCalled: false, // Structurally guaranteed zero dispatch
    };
  }

  /**
   * Performs read-only inspection of LID-to-Phone and Phone-to-LID mappings
   * using client.getContactLidAndPhone().
   *
   * @param {object} params
   * @param {object} params.client
   * @param {string} params.lidId - e.g. "170141321052179@lid"
   * @param {string} params.phoneId - e.g. "918080030111@c.us"
   * @param {object|string} [params.connectedWid] - client.info.wid
   * @returns {Promise<object>}
   */
  static async inspectLidAndPhoneMapping({ client, lidId, phoneId, connectedWid }) {
    const report = {
      lidQuery: lidId,
      phoneQuery: phoneId,
      lidLookup: null,
      phoneLookup: null,
      lidLookupError: null,
      phoneLookupError: null,
      conclusion: 'INCONCLUSIVE',
      matchesAuthSession: false,
      detail: '',
    };

    if (!client || typeof client.getContactLidAndPhone !== 'function') {
      report.conclusion = 'API_NOT_SUPPORTED';
      report.detail = 'client.getContactLidAndPhone is not available on this client instance.';
      return report;
    }

    // 1. Reverse lookup: LID -> Phone
    try {
      const res = await client.getContactLidAndPhone(lidId);
      const entry = Array.isArray(res) ? res[0] : res;
      report.lidLookup = {
        lid: entry?.lid || null,
        pn: entry?.pn || null,
      };
    } catch (err) {
      report.lidLookupError = err.message;
    }

    // 2. Forward lookup: Phone -> LID
    try {
      const res = await client.getContactLidAndPhone(phoneId);
      const entry = Array.isArray(res) ? res[0] : res;
      report.phoneLookup = {
        lid: entry?.lid || null,
        pn: entry?.pn || null,
      };
    } catch (err) {
      report.phoneLookupError = err.message;
    }

    // 3. Compare with Authenticated Session
    const authWid = connectedWid?._serialized || (typeof connectedWid === 'string' ? connectedWid : null);
    const authUser = connectedWid?.user || (authWid ? authWid.split('@')[0] : null);
    const expectedUser = phoneId.includes('@') ? phoneId.split('@')[0] : phoneId;
    report.matchesAuthSession = Boolean(
      authUser &&
      (authUser === expectedUser || `91${authUser}` === expectedUser || authWid === phoneId)
    );

    // 4. Determine Evaluation
    const lidPn = report.lidLookup?.pn;
    const phoneLid = report.phoneLookup?.lid;

    if (report.lidLookupError || report.phoneLookupError) {
      report.conclusion = 'LOOKUP_ERROR';
      report.detail = `Lookup error encountered: LID query: ${report.lidLookupError || 'none'}; PN query: ${report.phoneLookupError || 'none'}`;
    } else if (!lidPn && !phoneLid) {
      report.conclusion = 'MISSING_MAPPING';
      report.detail = 'WhatsApp internal store returned no mapping for either LID or Phone JID.';
    } else if (lidPn && lidPn !== phoneId) {
      report.conclusion = 'CONTRADICTORY_MISMATCH';
      report.detail = `LID ${lidId} mapped to unexpected phone ${lidPn} (expected: ${phoneId}).`;
    } else if (phoneLid && phoneLid !== lidId) {
      report.conclusion = 'CONTRADICTORY_MISMATCH';
      report.detail = `Phone ${phoneId} mapped to unexpected LID ${phoneLid} (expected: ${lidId}).`;
    } else if (lidPn === phoneId && phoneLid === lidId) {
      report.conclusion = report.matchesAuthSession ? 'VERIFIED_BIDIRECTIONAL_MATCH' : 'EXTERNAL_BIDIRECTIONAL_MATCH';
      report.detail = report.matchesAuthSession
        ? `LID ${lidId} and Phone ${phoneId} are bidirectionally verified and match the authenticated session (+${authUser}).`
        : `LID ${lidId} and Phone ${phoneId} are bidirectionally verified, but do NOT match the authenticated session.`;
    } else if (lidPn === phoneId) {
      report.conclusion = 'UNIDIRECTIONAL_LID_MATCH';
      report.detail = `Reverse lookup confirmed LID ${lidId} maps to ${phoneId}, but forward lookup did not confirm reverse LID.`;
    } else if (phoneLid === lidId) {
      report.conclusion = 'UNIDIRECTIONAL_PN_MATCH';
      report.detail = `Forward lookup confirmed Phone ${phoneId} maps to ${lidId}, but reverse lookup did not confirm reverse Phone.`;
    }

    return report;
  }

  /**
   * Extracts the serialized WhatsApp message ID from a Message model or raw ID object.
   * Handles standard _serialized strings, modern WhatsApp Web minified serializer ($1),
   * string IDs, and structured MsgKey components.
   *
   * @param {object|string} msgOrResult
   * @returns {string|null}
   */
  static extractMessageId(msgOrResult) {
    if (!msgOrResult) return null;

    // 1. Direct string ID
    if (typeof msgOrResult === 'string' && msgOrResult.trim().length > 0) {
      return msgOrResult.trim();
    }
    if (typeof msgOrResult.id === 'string' && msgOrResult.id.trim().length > 0) {
      return msgOrResult.id.trim();
    }

    // 2. Standard _serialized property
    if (msgOrResult.id && typeof msgOrResult.id._serialized === 'string' && msgOrResult.id._serialized.trim().length > 0) {
      return msgOrResult.id._serialized.trim();
    }

    // 3. Modern WhatsApp Web minified serializer ($1 contains serialized key)
    if (msgOrResult.id && typeof msgOrResult.id.$1 === 'string' && msgOrResult.id.$1.trim().length > 0) {
      return msgOrResult.id.$1.trim();
    }

    // 4. Construct canonical serialized string from MsgKey components if id exists
    if (
      msgOrResult.id &&
      typeof msgOrResult.id === 'object' &&
      typeof msgOrResult.id.id === 'string' &&
      msgOrResult.id.id.trim().length > 0
    ) {
      const fromMe = Boolean(msgOrResult.id.fromMe);
      const remote = msgOrResult.id.remote?._serialized || msgOrResult.id.remote || '';
      const id = msgOrResult.id.id;
      const selfSuffix = msgOrResult.id.self ? `_${msgOrResult.id.self}` : '';
      if (remote) {
        return `${fromMe}_${remote}_${id}${selfSuffix}`;
      }
      return id;
    }

    return null;
  }

  /**
   * Verifies whether client.sendMessage() or resolution tracker returned a valid, genuine WhatsApp message model.
   * Replaces misleading "delivered" string fallbacks.
   *
   * @param {object} sendResult
   * @returns {{ verified: boolean, messageId?: string, error?: string }}
   */
  static validateMessageSendResult(sendResult) {
    const messageId = RecipientValidator.extractMessageId(sendResult);
    if (messageId && messageId.length > 0) {
      // Ensure sendResult.id._serialized is populated for downstream compatibility
      if (sendResult && sendResult.id && typeof sendResult.id === 'object' && !sendResult.id._serialized) {
        try {
          sendResult.id._serialized = messageId;
        } catch (_) {}
      }
      return {
        verified: true,
        messageId,
      };
    }

    return {
      verified: false,
      error: 'Message dispatch returned no valid WhatsApp message ID. Send result could not be verified.',
    };
  }

  /**
   * Waits for WhatsApp server or device acknowledgement event (message_ack) with a bounded timeout.
   *
   * @param {object} client - whatsapp-web.js Client instance
   * @param {string} messageId - The serialized WhatsApp message ID
   * @param {object} options
   * @param {number} [options.timeoutMs=15000] - Timeout in milliseconds
   * @param {number} [options.requiredAck=1] - 1 = Server ACK (single tick), 2 = Device ACK (double tick)
   * @returns {Promise<{ acknowledged: boolean, ack: number, status: string, error?: string }>}
   */
  static waitForMessageAck(client, messageId, { timeoutMs = 15000, requiredAck = 1 } = {}) {
    return new Promise((resolve) => {
      let timer = null;

      const ackHandler = (msg, ack) => {
        const msgId = msg?.id?._serialized || msg?.id?.id || (typeof msg?.id === 'string' ? msg.id : null);
        if (msgId === messageId) {
          if (ack === -1) {
            cleanup();
            resolve({
              acknowledged: false,
              ack: -1,
              status: 'ACK_ERROR',
              error: `WhatsApp server reported ACK_ERROR (-1) for message ${messageId}. Delivery failed.`,
            });
          } else if (ack >= requiredAck) {
            cleanup();
            resolve({
              acknowledged: true,
              ack,
              status: ack >= 2 ? 'ACK_DEVICE' : 'ACK_SERVER',
            });
          }
        }
      };

      const cleanup = () => {
        if (timer) clearTimeout(timer);
        try {
          if (typeof client.off === 'function') {
            client.off('message_ack', ackHandler);
          } else if (typeof client.removeListener === 'function') {
            client.removeListener('message_ack', ackHandler);
          }
        } catch (_) {}
      };

      timer = setTimeout(() => {
        cleanup();
        resolve({
          acknowledged: false,
          ack: 0,
          status: 'TIMEOUT',
          error: `Timed out after ${timeoutMs}ms waiting for WhatsApp server acknowledgement (message ID: ${messageId}).`,
        });
      }, timeoutMs);

      try {
        client.on('message_ack', ackHandler);
      } catch (err) {
        cleanup();
        resolve({
          acknowledged: false,
          ack: 0,
          status: 'LISTENER_ERROR',
          error: `Failed to register message_ack listener: ${err.message}`,
        });
      }
    });
  }

  /**
   * Creates an ACK tracker that registers a 'message_ack' listener on client BEFORE message dispatch.
   * This prevents missing early server or device ACKs that arrive while sendMessage() is in-flight.
   *
   * @param {object} client - WhatsApp Web Client instance
   * @param {object} [options]
   * @param {number} [options.timeoutMs=30000] - Total timeout in milliseconds
   * @param {number} [options.requiredAck=1] - 1 for server ACK, 2 for device delivery
   * @returns {{
   *   waitForAck: (messageId: string, initialAck?: number) => Promise<{ acknowledged: boolean, ack: number, highestAck: number, status: string, error?: string }>,
   *   cancel: () => void
   * }}
   */
  static createAckTracker(client, { timeoutMs = 30000, requiredAck = 1 } = {}) {
    const receivedAcks = new Map();
    let targetMsgId = null;
    let resolvePromise = null;
    let timer = null;
    let cleanedUp = false;

    const cleanup = () => {
      if (cleanedUp) return;
      cleanedUp = true;
      if (timer) clearTimeout(timer);
      try {
        if (typeof client.off === 'function') {
          client.off('message_ack', ackHandler);
        } else if (typeof client.removeListener === 'function') {
          client.removeListener('message_ack', ackHandler);
        }
      } catch (_) {}
    };

    const ackHandler = (msg, ack) => {
      const msgId = RecipientValidator.extractMessageId(msg);
      if (!msgId) return;

      const stanzaId = msgId.includes('_') ? msgId.split('_')[2] : null;

      const current = Math.max(
        receivedAcks.get(msgId) || 0,
        stanzaId ? receivedAcks.get(stanzaId) || 0 : 0
      );
      if (ack > current || ack === -1) {
        receivedAcks.set(msgId, ack);
        if (stanzaId) receivedAcks.set(stanzaId, ack);
      }

      const matchesTarget =
        Boolean(targetMsgId) &&
        (msgId === targetMsgId ||
          (stanzaId && targetMsgId.includes('_') && stanzaId === targetMsgId.split('_')[2]));

      if (matchesTarget && resolvePromise) {
        if (ack === -1) {
          cleanup();
          resolvePromise({
            acknowledged: false,
            ack: -1,
            highestAck: -1,
            status: 'ACK_ERROR',
            error: `WhatsApp server reported ACK_ERROR (-1) for message ${targetMsgId}. Delivery failed.`,
          });
        } else if (ack >= 2) {
          cleanup();
          resolvePromise({
            acknowledged: true,
            ack,
            highestAck: ack,
            status: ack >= 3 ? 'ACK_READ' : 'ACK_DEVICE',
          });
        }
      }
    };

    try {
      if (client && typeof client.on === 'function') {
        client.on('message_ack', ackHandler);
      }
    } catch (_) {}

    return {
      waitForAck: (messageId, initialAck = 0) => {
        targetMsgId = messageId;
        const targetStanza = messageId && messageId.includes('_') ? messageId.split('_')[2] : null;

        return new Promise((resolve) => {
          resolvePromise = resolve;

          // Check if device delivery already observed
          const existingAck = Math.max(
            initialAck || 0,
            receivedAcks.get(messageId) || 0,
            targetStanza ? receivedAcks.get(targetStanza) || 0 : 0
          );
          if (existingAck >= 2) {
            cleanup();
            return resolve({
              acknowledged: true,
              ack: existingAck,
              highestAck: existingAck,
              status: existingAck >= 3 ? 'ACK_READ' : 'ACK_DEVICE',
            });
          }

          timer = setTimeout(() => {
            cleanup();
            const finalAck = Math.max(
              initialAck || 0,
              receivedAcks.get(messageId) || 0,
              targetStanza ? receivedAcks.get(targetStanza) || 0 : 0
            );
            if (finalAck >= 2) {
              resolve({
                acknowledged: true,
                ack: finalAck,
                highestAck: finalAck,
                status: finalAck >= 3 ? 'ACK_READ' : 'ACK_DEVICE',
              });
            } else if (finalAck >= 1) {
              resolve({
                acknowledged: true,
                ack: finalAck,
                highestAck: finalAck,
                status: 'ACK_SERVER',
              });
            } else if (finalAck === -1) {
              resolve({
                acknowledged: false,
                ack: -1,
                highestAck: -1,
                status: 'ACK_ERROR',
                error: `WhatsApp server reported ACK_ERROR (-1) for message ${messageId}. Delivery failed.`,
              });
            } else {
              resolve({
                acknowledged: false,
                ack: 0,
                highestAck: 0,
                status: 'TIMEOUT',
                error: `Timed out after ${timeoutMs}ms waiting for WhatsApp acknowledgement (message ID: ${messageId}).`,
              });
            }
          }, timeoutMs);
        });
      },
      cancel: () => cleanup(),
    };
  }

  /**
   * Creates a message resolution tracker that captures genuine message models emitted
   * during message dispatch, particularly when sending to self-chat where
   * window.WWebJS.sendMessage's internal Msg.get(newMsgKey._serialized) returns undefined
   * due to self-chat key serialization mismatch.
   *
   * SAFEGUARDS:
   * 1. Never re-dispatches: ZERO duplicate-send risk.
   * 2. Pre-registers client.on('message_create') listener before client.sendMessage().
   * 3. Fallback to in-memory chat.msgs inspection if message_create has not fired.
   * 4. Enforces strict message ID validation on any resolved model.
   *
   * @param {object} client - whatsapp-web.js Client instance
   * @param {string} targetJid - e.g. "918080030111@c.us"
   * @param {object} [options]
   * @param {string} [options.messageBody] - Expected body of the sent message
   * @param {number} [options.timeoutMs=5000] - Bounded timeout for event capture
   * @param {object|null} [options.verifiedMapping] - Verified LID mapping
   * @returns {{
   *   resolveMessage: (initialSendResult: any) => Promise<any>,
   *   cancel: () => void,
   *   getCapturedMessage: () => any
   * }}
   */
  static createMessageResolutionTracker(client, targetJid, { messageBody = '', timeoutMs = 5000, verifiedMapping = null } = {}) {
    let capturedMessage = null;
    let resolveListener = null;
    let cleanedUp = false;

    const lidTarget = verifiedMapping?.lidLookup?.lid || (targetJid && targetJid.endsWith('@lid') ? targetJid : null);
    const phoneTarget = verifiedMapping?.phoneLookup?.pn || (targetJid && targetJid.endsWith('@c.us') ? targetJid : null);

    const messageCreateHandler = (msg) => {
      if (!msg) return;

      const isOutbound = Boolean(
        msg.fromMe ||
        msg.id?.fromMe ||
        msg.self === 'out' ||
        (typeof msg.id === 'string' && msg.id.startsWith('true_')) ||
        (msg.id?._serialized && msg.id._serialized.startsWith('true_')) ||
        (msg.id?.$1 && msg.id.$1.startsWith('true_'))
      );
      if (!isOutbound) return;

      const resolvedId = RecipientValidator.extractMessageId(msg);
      if (!resolvedId) return;

      // Destination matching: target phone JID, target LID, self-directed (from == to), or ID contains target
      const toJid = msg.to?._serialized || msg.to;
      const fromJid = msg.from?._serialized || msg.from;
      const matchesDestination =
        toJid === targetJid ||
        (lidTarget && toJid === lidTarget) ||
        (phoneTarget && toJid === phoneTarget) ||
        (fromJid && toJid && fromJid === toJid) ||
        (resolvedId.includes(targetJid) || (lidTarget && resolvedId.includes(lidTarget)));

      if (!matchesDestination) return;

      // Body matching (supports exact or prefix matching to handle formatting differences)
      const msgBody = msg.body || msg.__x_body || '';
      if (messageBody && msgBody && !msgBody.includes(messageBody.slice(0, 30)) && !messageBody.includes(msgBody.slice(0, 30))) {
        return;
      }

      capturedMessage = msg;
      if (resolveListener) {
        resolveListener(msg);
      }
    };

    try {
      if (client && typeof client.on === 'function') {
        client.on('message_create', messageCreateHandler);
      }
    } catch (_) {}

    const cleanup = () => {
      if (cleanedUp) return;
      cleanedUp = true;
      try {
        if (client && typeof client.off === 'function') {
          client.off('message_create', messageCreateHandler);
        } else if (client && typeof client.removeListener === 'function') {
          client.removeListener('message_create', messageCreateHandler);
        }
      } catch (_) {}
    };

    return {
      getCapturedMessage: () => capturedMessage,
      resolveMessage: async (initialSendResult) => {
        // Strategy 1: Direct library return value is already valid
        const initialCheck = RecipientValidator.validateMessageSendResult(initialSendResult);
        if (initialCheck.verified) {
          cleanup();
          return initialSendResult;
        }

        // Strategy 2: Pre-registered message_create event captured during dispatch
        if (capturedMessage) {
          cleanup();
          return capturedMessage;
        }

        // Strategy 3: Bounded wait for message_create event in-flight
        const eventPromise = new Promise((resolve) => {
          resolveListener = resolve;
          setTimeout(() => resolve(null), Math.min(timeoutMs, 4000));
        });

        const eventResult = await eventPromise;
        if (eventResult) {
          cleanup();
          return eventResult;
        }

        // Strategy 4: Direct in-memory chat.msgs query via Puppeteer evaluate
        try {
          if (client?.pupPage && typeof client.pupPage.evaluate === 'function') {
            const rawMsg = await client.pupPage.evaluate(async (chatId, expectedBody) => {
              try {
                const chat = await window.WWebJS.getChat(chatId, { getAsModel: false });
                if (!chat || !chat.msgs) return null;
                const models = chat.msgs.getModelsArray ? chat.msgs.getModelsArray() : (chat.msgs.models || []);
                for (let i = models.length - 1; i >= 0; i--) {
                  const m = models[i];
                  if (!m) continue;
                  const isOut = Boolean(
                    m.id?.fromMe ||
                    (m.id?._serialized && m.id._serialized.startsWith('true_')) ||
                    (m.id?.$1 && m.id.$1.startsWith('true_')) ||
                    m.self === 'out' ||
                    m.fromMe
                  );
                  if (isOut) {
                    const body = m.body || m.__x_body || '';
                    if (!expectedBody || body === expectedBody || body.includes(expectedBody.slice(0, 30)) || expectedBody.includes(body.slice(0, 30))) {
                      const model = window.WWebJS.getMessageModel(m);
                      const extractedId = m.id?._serialized || m.id?.$1 || (model?.id?.$1 ? model.id.$1 : null);
                      if (model && model.id && extractedId) {
                        model.id._serialized = extractedId;
                      }
                      return model;
                    }
                  }
                }
              } catch (_) {}
              return null;
            }, targetJid, messageBody);

            if (rawMsg) {
              cleanup();
              try {
                const { Message } = require('whatsapp-web.js/src/structures');
                return new Message(client, rawMsg);
              } catch (_) {
                return rawMsg;
              }
            }
          }
        } catch (_) {}

        cleanup();
        return initialSendResult;
      },
      cancel: cleanup,
    };
  }

  /**
   * Bounded diagnostic readiness checker.
   * Waits for WhatsApp Web chat-store restoration and confirms whether the target chat is loaded and available.
   * Does NOT assume readiness merely because the client 'ready' event fired.
   * Uses raw chat retrieval ({ getAsModel: false }) to avoid IndexedDB serialization DataErrors in whatsapp-web.js,
   * validates self-chat against verified bidirectional LID mapping, and safely counts chats.
   *
   * @param {object} client - whatsapp-web.js Client instance
   * @param {string} targetJid - e.g. "918080030111@c.us"
   * @param {object} [options]
   * @param {number} [options.timeoutMs=45000] - Total bounded timeout
   * @param {number} [options.pollIntervalMs=1000] - Interval between chat store polls
   * @param {object|null} [options.verifiedMapping] - Verified LID mapping from inspectLidAndPhoneMapping
   * @param {boolean} [options.openChatWindow=false] - Whether to open the chat window in the UI once ready
   * @returns {Promise<{
   *   ready: boolean,
   *   status: 'CHAT_READY' | 'TIMEOUT' | 'DISCONNECTED' | 'QR_REQUIRED' | 'AUTH_FAILURE',
   *   authenticatedUser: string | null,
   *   targetJid: string,
   *   chatFound: boolean,
   *   chatDetails: { id: string, name?: string, isGroup?: boolean, isLid?: boolean, windowOpened?: boolean } | null,
   *   chatCount: number,
   *   offlineProgress: number | null,
   *   durationMs: number,
   *   error?: string
   * }>}
   */
  static async waitForChatReadiness(client, targetJid, { timeoutMs = 45000, pollIntervalMs = 1000, verifiedMapping = null, openChatWindow = false } = {}) {
    const startTime = Date.now();
    let offlineProgress = null;
    let terminalStatus = null;
    let terminalError = null;

    const onProgress = (percent) => {
      offlineProgress = percent;
    };
    const onDisconnect = (reason) => {
      terminalStatus = 'DISCONNECTED';
      terminalError = `Client disconnected: ${reason}`;
    };
    const onQr = () => {
      terminalStatus = 'QR_REQUIRED';
      terminalError = 'Session invalidated; QR code required';
    };
    const onAuthFail = (msg) => {
      terminalStatus = 'AUTH_FAILURE';
      terminalError = `Auth failure: ${msg}`;
    };

    try {
      if (client && typeof client.on === 'function') {
        client.on('loading_screen', onProgress);
        client.on('disconnected', onDisconnect);
        client.on('qr', onQr);
        client.on('auth_failure', onAuthFail);
      }
    } catch (_) {}

    const cleanupListeners = () => {
      try {
        if (client && typeof client.off === 'function') {
          client.off('loading_screen', onProgress);
          client.off('disconnected', onDisconnect);
          client.off('qr', onQr);
          client.off('auth_failure', onAuthFail);
        } else if (client && typeof client.removeListener === 'function') {
          client.removeListener('loading_screen', onProgress);
          client.removeListener('disconnected', onDisconnect);
          client.removeListener('qr', onQr);
          client.removeListener('auth_failure', onAuthFail);
        }
      } catch (_) {}
    };

    const getChatCountSafe = async () => {
      // 1. In real browser session: query in-memory ChatCollection directly
      if (client?.pupPage && typeof client.pupPage.evaluate === 'function') {
        try {
          const count = await client.pupPage.evaluate(() => {
            const ChatCollection = window.require?.('WAWebCollections')?.Chat;
            return ChatCollection?.getModelsArray?.()?.length ?? 0;
          });
          if (typeof count === 'number' && count > 0) return count;
        } catch (_) {}
      }
      // 2. Fallback for mock environments: client.getChats()
      if (typeof client?.getChats === 'function') {
        try {
          const allChats = await client.getChats();
          return Array.isArray(allChats) ? allChats.length : 0;
        } catch (_) {}
      }
      return 0;
    };

    while (Date.now() - startTime < timeoutMs) {
      if (terminalStatus) {
        cleanupListeners();
        return {
          ready: false,
          status: terminalStatus,
          authenticatedUser: client?.info?.wid?.user || null,
          targetJid,
          chatFound: false,
          chatDetails: null,
          chatCount: 0,
          offlineProgress,
          durationMs: Date.now() - startTime,
          error: terminalError,
        };
      }

      // 1. Raw chat retrieval: bypass failing WWebJS.getChatModel (DataError on IndexedDB)
      let chat = null;
      if (client?.pupPage && typeof client.pupPage.evaluate === 'function') {
        try {
          chat = await client.pupPage.evaluate(async (jid) => {
            if (window.WWebJS && typeof window.WWebJS.getChat === 'function') {
              const raw = await window.WWebJS.getChat(jid, { getAsModel: false });
              if (!raw) return null;
              return {
                id: raw.id?._serialized || (typeof raw.id === 'string' ? raw.id : null),
                name: raw.name || raw.formattedTitle || null,
                isGroup: Boolean(raw.isGroup),
              };
            }
            return null;
          }, targetJid);
        } catch (_) {}
      }

      // Fallback for mock environments or when pupPage is not present
      if (!chat) {
        try {
          if (client && typeof client.getChatById === 'function') {
            const modelChat = await client.getChatById(targetJid);
            if (modelChat) {
              chat = {
                id: modelChat.id?._serialized || (typeof modelChat.id === 'string' ? modelChat.id : null),
                name: modelChat.name || null,
                isGroup: Boolean(modelChat.isGroup),
              };
            }
          }
        } catch (_) {}
      }

      // 2. Validate chat match (Canonical JID or verified self LID)
      let isMatchingChat = false;
      let isLidMatch = false;

      if (chat && chat.id) {
        if (chat.id === targetJid) {
          isMatchingChat = true;
        } else if (chat.id.endsWith('@lid')) {
          const isValidLidMapping = Boolean(
            verifiedMapping &&
            verifiedMapping.conclusion === 'VERIFIED_BIDIRECTIONAL_MATCH' &&
            verifiedMapping.matchesAuthSession === true &&
            verifiedMapping.lidLookup?.lid === chat.id &&
            verifiedMapping.lidLookup?.pn === targetJid &&
            verifiedMapping.phoneLookup?.lid === chat.id &&
            verifiedMapping.phoneLookup?.pn === targetJid
          );
          if (isValidLidMapping) {
            isMatchingChat = true;
            isLidMatch = true;
          }
        }
      }

      if (isMatchingChat) {
        const chatCount = await getChatCountSafe();

        // If requested, open chat window in UI via supported client.interface
        let windowOpened = false;
        if (openChatWindow && client?.interface && typeof client.interface.openChatWindow === 'function') {
          try {
            await client.interface.openChatWindow(chat.id);
            windowOpened = true;
          } catch (_) {}
        }

        cleanupListeners();
        return {
          ready: true,
          status: 'CHAT_READY',
          authenticatedUser: client?.info?.wid?.user || null,
          targetJid,
          chatFound: true,
          chatDetails: {
            id: chat.id,
            name: chat.name || null,
            isGroup: chat.isGroup,
            isLid: isLidMatch,
            windowOpened,
          },
          chatCount,
          offlineProgress,
          durationMs: Date.now() - startTime,
        };
      }

      // Wait pollIntervalMs before next check
      await new Promise((r) => setTimeout(r, pollIntervalMs));
    }

    cleanupListeners();
    if (terminalStatus) {
      return {
        ready: false,
        status: terminalStatus,
        authenticatedUser: client?.info?.wid?.user || null,
        targetJid,
        chatFound: false,
        chatDetails: null,
        chatCount: 0,
        offlineProgress,
        durationMs: Date.now() - startTime,
        error: terminalError,
      };
    }

    const finalChatCount = await getChatCountSafe();

    return {
      ready: false,
      status: 'TIMEOUT',
      authenticatedUser: client?.info?.wid?.user || null,
      targetJid,
      chatFound: false,
      chatDetails: null,
      chatCount: finalChatCount,
      offlineProgress,
      durationMs: Date.now() - startTime,
      error: `Timed out after ${timeoutMs}ms waiting for chat ${targetJid} to be restored in WhatsApp Web chat store.`,
    };
  }
}

module.exports = RecipientValidator;
