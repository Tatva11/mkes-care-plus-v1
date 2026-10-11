import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../models/dental_lab_model.dart';

class DentalLabWhatsAppDialog extends StatelessWidget {
  const DentalLabWhatsAppDialog({super.key, required this.caseItem});

  final DentalLabModel caseItem;

  static void show(BuildContext context, DentalLabModel item) {
    showDialog(
      context: context,
      builder: (_) => DentalLabWhatsAppDialog(caseItem: item),
    );
  }

  /// Normalizes a phone number for the WhatsApp wa.me API format (digits only, no '+' or special characters).
  /// For 10-digit Indian numbers without country code, automatically prefixes '91'.
  static String? normalizePhoneNumber(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 7) return null;
    return digits.length == 10 ? '91$digits' : digits;
  }

  /// Builds the pre-composed WhatsApp message including case and scheduled appointment information.
  static String buildMessage(DentalLabModel caseItem) {
    final patientName = caseItem.patientName ?? 'Valued Patient';
    final caseType = caseItem.caseType;
    final caseNum = caseItem.caseNumber;

    String apptText;
    if (caseItem.appointmentDate != null) {
      final dateStr = DateFormat('d MMM yyyy').format(caseItem.appointmentDate!);
      final timeStr = caseItem.formattedAppointmentTime;
      apptText = timeStr != null && timeStr.isNotEmpty
          ? '📅 *Scheduled Fitting Appointment:* $dateStr at $timeStr'
          : '📅 *Scheduled Fitting Appointment:* $dateStr';
    } else {
      apptText = 'Please contact us to confirm your appointment time for insertion.';
    }

    return '🦷 *MKES CARE+ DENTAL CLINIC*\n\n'
        'Dear $patientName,\n\n'
        'Your custom dental lab restoration (*$caseType*, Ref: #$caseNum) is now *READY* for fitting at MKES CARE+ Dental Clinic.\n\n'
        '$apptText\n\n'
        'Fitting Instructions:\n'
        '• Please bring your previous records or prosthesis if applicable.\n'
        '• Please arrive 10 minutes prior to your scheduled time.\n\n'
        'Thank you,\nMKES CARE+ Clinical Team';
  }

  /// Builds a fully valid, properly encoded WhatsApp URL for wa.me.
  static Uri? generateWhatsAppUri({required String? phone, required DentalLabModel caseItem}) {
    final clean = normalizePhoneNumber(phone);
    if (clean == null) return null;
    return Uri.https('wa.me', '/$clean', {'text': buildMessage(caseItem)});
  }

  Future<void> _openWhatsApp(BuildContext context, String rawPhone) async {
    final clean = normalizePhoneNumber(rawPhone);
    if (clean == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.error,
          content: Text('No valid mobile number is available for this patient. Please update their WhatsApp contact first.'),
        ),
      );
      return;
    }

    final uri = generateWhatsAppUri(phone: clean, caseItem: caseItem);
    if (uri == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    bool launched = false;
    try {
      final canOpen = await canLaunchUrl(uri);
      if (!canOpen) {
        throw StateError('WhatsApp is not installed or URL cannot be opened');
      }
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (_) {
        launched = false;
      }
    }

    if (navigator.canPop()) {
      navigator.pop();
    }

    if (!launched) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: Text(
            'Could not open WhatsApp for +$clean. Please verify WhatsApp is installed or open https://wa.me/$clean in your browser.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = caseItem.patientMobile ?? caseItem.patient?.mobile;
    final normalizedPhone = normalizePhoneNumber(phone);
    final hasValidPhone = normalizedPhone != null;
    final messagePreview = buildMessage(caseItem);

    final content = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!hasValidPhone) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: AppColors.error),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.phone_disabled_outlined, color: AppColors.error, size: 24),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'No valid WhatsApp contact number is registered for patient "${caseItem.patientName ?? "Unknown"}". Please update their mobile number in Patient Details.',
                        style: AppTypography.bodySm.copyWith(color: AppColors.error),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person, color: Color(0xFF128C7E), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Recipient: ${caseItem.patientName ?? "Patient"} • +$normalizedPhone',
                        style: AppTypography.bodySm.copyWith(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF128C7E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'PREPARED MESSAGE PREVIEW',
                style: AppTypography.labelCaps.copyWith(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: const Color(0xFFECE5DD),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Text(
                  messagePreview,
                  style: AppTypography.bodySm.copyWith(
                    color: const Color(0xFF111B21),
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Note: Clicking "Open in WhatsApp" will open WhatsApp with this message prefilled. You review and send it manually. Nothing is sent automatically.',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: EdgeInsets.zero,
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFF25D366),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.message, color: Colors.white, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Patient WhatsApp Notification',
              style: AppTypography.headlineMd.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: content,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (hasValidPhone)
          FilledButton.icon(
            onPressed: () => _openWhatsApp(context, phone!),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Open in WhatsApp'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
            ),
          ),
      ],
    );
  }
}
