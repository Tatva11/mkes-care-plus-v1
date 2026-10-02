import 'package:flutter/material.dart';
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

  String _buildMessage() {
    final patientName = caseItem.patientName ?? 'Valued Patient';
    final caseType = caseItem.caseType;
    final caseNum = caseItem.caseNumber;

    return '🦷 *MKES CARE+ DENTAL CLINIC*\n\n'
        'Dear $patientName,\n\n'
        'Your custom dental lab restoration (*$caseType*, Ref: #$caseNum) is now *READY* for fitting at MKES CARE+ Dental Clinic.\n\n'
        'Please reply or call to confirm your appointment time for insertion.\n\n'
        'Thank you,\nMKES CARE+ Clinical Team';
  }

  Future<void> _openWhatsApp(BuildContext context, String phoneNumber) async {
    final cleaned = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    final message = Uri.encodeComponent(_buildMessage());
    final url = 'https://wa.me/$cleaned?text=$message';
    final uri = Uri.parse(url);

    Navigator.of(context).pop();

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open WhatsApp for $cleaned')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error launching WhatsApp: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = caseItem.patientMobile ?? caseItem.patient?.mobile;
    final hasPhone = phone != null && phone.trim().isNotEmpty;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!hasPhone) ...[
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
                        'No WhatsApp contact number is registered for patient "${caseItem.patientName ?? "Unknown"}". Please update their mobile number in Patient Details.',
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
                        'Recipient: ${caseItem.patientName} • $phone',
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
                  _buildMessage(),
                  style: AppTypography.bodySm.copyWith(
                    color: const Color(0xFF111B21),
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Note: Clicking "Open in WhatsApp" will open your WhatsApp app/web with this message prefilled. You review and send it manually.',
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (hasPhone)
          FilledButton.icon(
            onPressed: () => _openWhatsApp(context, phone),
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
