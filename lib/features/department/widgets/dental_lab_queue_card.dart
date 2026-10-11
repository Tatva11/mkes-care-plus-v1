import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../dental/models/dental_lab_model.dart';
import '../../dental/providers/dental_lab_provider.dart';
import '../../dental/widgets/dental_lab_form_dialog.dart';
import '../../dental/widgets/dental_lab_whatsapp_dialog.dart';

class DentalLabQueueCard extends ConsumerWidget {
  const DentalLabQueueCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final casesAsync = ref.watch(dentalLabListProvider);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: AppColors.outlineVariant),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Card Header ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: const BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              border: Border(
                bottom: BorderSide(color: AppColors.surfaceVariant),
              ),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppSpacing.radiusXl),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Dental Lab Tracking Queue',
                    style: AppTypography.headlineMd,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => ref.read(dentalLabListProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh),
                  color: AppColors.onSurfaceVariant,
                  tooltip: 'Refresh Queue',
                  iconSize: 20,
                ),
              ],
            ),
          ),

          // ── Table Content ────────────────────────────────────────
          casesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                'Unable to load cases: $err',
                style: AppTypography.bodySm.copyWith(color: AppColors.error),
              ),
            ),
            data: (cases) {
              if (cases.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Center(
                    child: Text(
                      'No dental lab cases logged yet.',
                      style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ),
                );
              }

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 780,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Column headers
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.xs,
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 4),
                            Expanded(flex: 2, child: _HeaderCell('Case ID')),
                            Expanded(flex: 3, child: _HeaderCell('Patient')),
                            Expanded(flex: 3, child: _HeaderCell('Restoration')),
                            Expanded(flex: 2, child: _HeaderCell('Sent Date')),
                            Expanded(flex: 2, child: _HeaderCell('Appointment')),
                            Expanded(
                              flex: 2,
                              child: _HeaderCell('Status', alignRight: true),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: AppColors.surfaceVariant),

                      // Data rows
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: cases.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: AppColors.surfaceVariant),
                        itemBuilder: (context, index) {
                          return _RealDentalRow(item: cases[index]);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text, {this.alignRight = false});
  final String text;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
      style: AppTypography.labelCaps.copyWith(
        color: AppColors.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _RealDentalRow extends ConsumerWidget {
  const _RealDentalRow({required this.item});
  final DentalLabModel item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFormat = DateFormat('dd MMM');

    Color badgeBg;
    Color badgeFg;
    if (item.isProcessing) {
      badgeBg = Colors.amber.shade100;
      badgeFg = Colors.amber.shade900;
    } else if (item.isReady) {
      badgeBg = AppColors.secondaryContainer.withValues(alpha: 0.3);
      badgeFg = AppColors.secondary;
    } else {
      badgeBg = Colors.green.shade100;
      badgeFg = Colors.green.shade800;
    }

    return Container(
      color: AppColors.surfaceContainerLowest,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.sm,
        horizontal: AppSpacing.md,
      ),
      child: Row(
        children: [
          // Case ID
          Expanded(
            flex: 2,
            child: Text(
              item.caseNumber,
              style: AppTypography.dataMono.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),

          // Patient
          Expanded(
            flex: 3,
            child: Text(
              item.patientName ?? 'Unknown',
              style: AppTypography.bodySm.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Restoration
          Expanded(
            flex: 3,
            child: Text(
              item.caseType,
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Sent Date
          Expanded(
            flex: 2,
            child: Text(
              dateFormat.format(item.sentDate),
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),

          // Appointment
          Expanded(
            flex: 2,
            child: Text(
              item.appointmentDate != null
                  ? (item.formattedAppointmentDateTime ??
                      item.formattedAppointmentDate ??
                      '-')
                  : '-',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.primary,
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Status & Quick Action
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.isReady)
                    IconButton(
                      icon: const Icon(Icons.message, color: Color(0xFF25D366), size: 16),
                      tooltip: 'WhatsApp Ready Notice',
                      onPressed: () => DentalLabWhatsAppDialog.show(context, item),
                    ),
                  InkWell(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => DentalLabFormDialog(initialCase: item),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        item.statusLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: badgeFg,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
