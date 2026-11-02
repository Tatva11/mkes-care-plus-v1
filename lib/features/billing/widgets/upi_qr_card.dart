import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// Displays clinic UPI payment information with QR code and copy button.
class UpiPaymentQrCard extends StatelessWidget {
  final String upiId;
  final String assetPath;

  const UpiPaymentQrCard({
    super.key,
    this.upiId = '9004706625@fam',
    this.assetPath = 'assets/images/qr.jpeg',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // QR Code Card Container
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(color: AppColors.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.asset(
                assetPath,
                key: const Key('upi_qr_image'),
                width: 200,
                height: 200,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (context, error, stackTrace) {
                  return Image.asset(
                    'assets/images/qr.png',
                    key: const Key('upi_qr_image_fallback'),
                    width: 200,
                    height: 200,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (context2, error2, stack2) {
                      return Image.asset(
                        'qr.jpeg',
                        width: 200,
                        height: 200,
                        fit: BoxFit.contain,
                        errorBuilder: (context3, error3, stack3) {
                          return Container(
                            width: 200,
                            height: 200,
                            color: Colors.grey[100],
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.qr_code_2, size: 54, color: Colors.grey),
                                  SizedBox(height: 6),
                                  Text(
                                    'QR Code Unavailable',
                                    style: TextStyle(color: Colors.grey, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Clinic UPI ID Display
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'UPI ID: ',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SelectableText(
                upiId,
                key: const Key('clinic_upi_id_text'),
                style: AppTypography.bodyMd.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),

          // Copy UPI ID Button
          OutlinedButton.icon(
            key: const Key('copy_upi_id_button'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: upiId));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('UPI ID copied to clipboard'),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 15),
            label: const Text('Copy UPI ID'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),

          // Instruction Text
          Text(
            'Scan this QR code using any UPI application to complete your payment.',
            key: const Key('upi_instruction_text'),
            textAlign: TextAlign.center,
            style: AppTypography.bodySm.copyWith(
              fontSize: 12,
              color: AppColors.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
