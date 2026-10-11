import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../models/eye_surgery_model.dart';
import '../providers/eye_surgery_provider.dart';
import 'assign_eye_surgery_staff_dialog.dart';

/// Modal dialog displaying full details of an operation / eye surgery.
/// This is a read-only inspection dialog that guarantees zero side effects
/// (no status changes, no inventory deduction, and no appointment booking).
class EyeSurgeryDetailDialog extends ConsumerWidget {
  const EyeSurgeryDetailDialog({
    super.key,
    required this.surgery,
  });

  final EyeSurgeryModel surgery;

  static const Color _successColor = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(eyeSurgeryItemsProvider(surgery.id));

    final completedChecklist = EyeSurgeryModel.checklistItems.keys
        .where((k) => surgery.preOpChecklist[k] == true)
        .length;

    final dateFormatted =
        DateFormat('dd MMM yyyy').format(surgery.surgeryDate);
    final preOpFormatted =
        DateFormat('dd MMM yyyy').format(surgery.preOpDate);
    final timeFormatted = surgery.surgeryTime;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: const Icon(
                      Icons.visibility_outlined,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          surgery.displaySurgeryType,
                          style: AppTypography.headlineMd.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Patient: ${surgery.patientName ?? surgery.patientId}'
                          '${surgery.patientNumber != null ? " (${surgery.patientNumber})" : ""}',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusChip(surgery.status, surgery.isMissed),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1, color: AppColors.outlineVariant),
              const SizedBox(height: AppSpacing.md),

              // Scrollable body
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Overview / Schedule details card
                      _buildSectionCard(
                        title: 'SCHEDULE & CLINICAL OVERVIEW',
                        icon: Icons.calendar_today_outlined,
                        child: Column(
                          children: [
                            _buildInfoRow(
                              label: 'Surgery Date & Time',
                              value: '$dateFormatted${timeFormatted != null ? " at $timeFormatted" : ""}',
                              icon: Icons.schedule_outlined,
                            ),
                            _buildInfoRow(
                              label: 'Eye Side',
                              value: '${surgery.eyeSide.toUpperCase()} EYE',
                              icon: Icons.remove_red_eye_outlined,
                            ),
                            _buildInfoRow(
                              label: 'Assigned Staff',
                              value: surgery.assignedStaffName ?? 'Unassigned',
                              icon: Icons.person_outline,
                              trailing: TextButton.icon(
                                onPressed: () async {
                                  await showAssignEyeSurgeryStaffDialog(
                                      context, ref, surgery);
                                },
                                icon: const Icon(Icons.person_add_alt_1, size: 14),
                                label: Text(
                                  surgery.assignedStaffName == null
                                      ? 'Assign Staff'
                                      : 'Change',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                ),
                              ),
                            ),
                            _buildInfoRow(
                              label: 'Pre-operative Date',
                              value: preOpFormatted,
                              icon: Icons.event_available_outlined,
                            ),
                            if (surgery.dischargedAt != null)
                              _buildInfoRow(
                                label: 'Discharged On',
                                value: DateFormat('dd MMM yyyy, h:mm a')
                                    .format(surgery.dischargedAt!.toLocal()),
                                icon: Icons.exit_to_app_outlined,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Pre-operative Checklist card
                      _buildSectionCard(
                        title:
                            'PRE-OP CHECKLIST ($completedChecklist / ${EyeSurgeryModel.checklistItems.length})',
                        icon: Icons.checklist_outlined,
                        trailingBadge: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: completedChecklist ==
                                    EyeSurgeryModel.checklistItems.length
                                ? _successColor.withValues(alpha: 0.15)
                                : Colors.amber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            completedChecklist ==
                                    EyeSurgeryModel.checklistItems.length
                                ? 'ALL VERIFIED'
                                : '$completedChecklist PENDING',
                            style: AppTypography.labelCaps.copyWith(
                              color: completedChecklist ==
                                      EyeSurgeryModel.checklistItems.length
                                  ? _successColor
                                  : Colors.amber.shade900,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        child: Column(
                          children: EyeSurgeryModel.checklistItems.entries
                              .map((entry) {
                            final isDone =
                                surgery.preOpChecklist[entry.key] == true;
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    isDone
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    size: 18,
                                    color: isDone
                                        ? _successColor
                                        : AppColors.outlineVariant,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      entry.value,
                                      style: AppTypography.bodySm.copyWith(
                                        color: isDone
                                            ? AppColors.onSurface
                                            : AppColors.onSurfaceVariant,
                                        fontWeight: isDone
                                            ? FontWeight.w500
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Clinical Details (IOL and Remarks)
                      if ((surgery.iolDetails != null &&
                              surgery.iolDetails!.trim().isNotEmpty) ||
                          (surgery.remarks != null &&
                              surgery.remarks!.trim().isNotEmpty)) ...[
                        _buildSectionCard(
                          title: 'CLINICAL DETAILS & NOTES',
                          icon: Icons.notes_outlined,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (surgery.iolDetails != null &&
                                  surgery.iolDetails!.trim().isNotEmpty) ...[
                                Text(
                                  'IOL Details (Lens Model & Power)',
                                  style: AppTypography.bodySm.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  surgery.iolDetails!,
                                  style: AppTypography.bodyMd,
                                ),
                                const SizedBox(height: AppSpacing.sm),
                              ],
                              if (surgery.remarks != null &&
                                  surgery.remarks!.trim().isNotEmpty) ...[
                                Text(
                                  'Clinical Remarks / Post-Op Notes',
                                  style: AppTypography.bodySm.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  surgery.remarks!,
                                  style: AppTypography.bodyMd,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],

                      // Follow-up Appointment Linkage
                      if (surgery.followUpAppointmentId != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: _successColor.withValues(alpha: 0.08),
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusMd),
                            border: Border.all(
                              color: _successColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_outline,
                                  color: _successColor, size: 20),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  'Follow-up appointment scheduled (Appointment #${surgery.followUpAppointmentId!.length > 8 ? surgery.followUpAppointmentId!.substring(0, 8) : surgery.followUpAppointmentId})',
                                  style: AppTypography.bodySm.copyWith(
                                    color: _successColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],

                      // Recorded Surgery Inventory Items
                      _buildSectionCard(
                        title: 'SURGERY INVENTORY ITEMS',
                        icon: Icons.inventory_2_outlined,
                        child: itemsAsync.when(
                          loading: () => const Center(
                            child: Padding(
                              padding: EdgeInsets.all(AppSpacing.md),
                              child: CircularProgressIndicator(),
                            ),
                          ),
                          error: (e, _) => Text(
                            'Unable to load surgery inventory items: $e',
                            style: AppTypography.bodySm
                                .copyWith(color: AppColors.error),
                          ),
                          data: (items) {
                            if (items.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.sm),
                                child: Text(
                                  'No inventory items recorded or consumed for this surgery.',
                                  style: AppTypography.bodySm.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              );
                            }

                            return ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: items.length,
                              separatorBuilder: (_, __) => const Divider(
                                height: 1,
                                color: AppColors.outlineVariant,
                              ),
                              itemBuilder: (context, i) {
                                final item = items[i];
                                final isConsumed = item.consumedAt != null;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: AppSpacing.xs),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.inventoryItemName,
                                              style: AppTypography.bodyMd
                                                  .copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              'Required: ${item.requiredQuantity} ${item.unit}',
                                              style:
                                                  AppTypography.bodySm.copyWith(
                                                color:
                                                    AppColors.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isConsumed
                                              ? _successColor
                                                  .withValues(alpha: 0.1)
                                              : Colors.blue
                                                  .withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(
                                              AppSpacing.radiusSm),
                                        ),
                                        child: Text(
                                          isConsumed ? 'CONSUMED' : 'ALLOCATED',
                                          style:
                                              AppTypography.labelCaps.copyWith(
                                            color: isConsumed
                                                ? _successColor
                                                : Colors.blue.shade800,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailingBadge,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.labelCaps.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              if (trailingBadge != null) trailingBadge,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1, color: AppColors.outlineVariant),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required String label,
    required String value,
    required IconData icon,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: AppColors.onSurfaceVariant),
          const SizedBox(width: AppSpacing.xs),
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.bodySm.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status, bool isMissed) {
    Color bg;
    Color fg;
    String label = status.replaceAll('_', ' ').toUpperCase();

    if (isMissed) {
      bg = Colors.red.shade100;
      fg = Colors.red.shade900;
      label = 'MISSED';
    } else {
      switch (status) {
        case 'scheduled':
          bg = Colors.blue.shade100;
          fg = Colors.blue.shade900;
          break;
        case 'pre_op':
          bg = Colors.amber.shade100;
          fg = Colors.amber.shade900;
          break;
        case 'in_surgery':
          bg = Colors.purple.shade100;
          fg = Colors.purple.shade900;
          break;
        case 'post_op':
          bg = Colors.teal.shade100;
          fg = Colors.teal.shade900;
          break;
        case 'discharged':
          bg = Colors.green.shade100;
          fg = Colors.green.shade800;
          break;
        case 'cancelled':
          bg = Colors.red.shade100;
          fg = Colors.red.shade900;
          break;
        default:
          bg = AppColors.surfaceVariant;
          fg = AppColors.onSurfaceVariant;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        label,
        style: AppTypography.labelCaps.copyWith(
          color: fg,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }
}
