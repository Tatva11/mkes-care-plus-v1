import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../models/eye_surgery_model.dart';
import '../providers/eye_surgery_provider.dart';
import 'eye_surgery_detail_dialog.dart';

/// Section embedded into Patient Details screen displaying operation & surgery history.
/// Clicking any surgery entry opens the full operation detail dialog.
class EyeSurgeryPatientSection extends ConsumerWidget {
  const EyeSurgeryPatientSection({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surgeriesAsync = ref.watch(eyeSurgeriesForPatientProvider(patientId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'OPERATIONS / SURGERY HISTORY',
              style: AppTypography.labelCaps.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: 'Refresh surgery history',
              onPressed: () =>
                  ref.invalidate(eyeSurgeriesForPatientProvider(patientId)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        surgeriesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: LinearProgressIndicator(),
          ),
          error: (error, _) => _PatientSurgeryMessage(
            text: 'Unable to load surgery history: $error',
            onRetry: () =>
                ref.invalidate(eyeSurgeriesForPatientProvider(patientId)),
          ),
          data: (surgeries) => surgeries.isEmpty
              ? const _PatientSurgeryMessage(
                  text: 'No operations or surgeries recorded for this patient.',
                )
              : Column(
                  children: surgeries
                      .map((surgery) => _PatientSurgeryTile(surgery: surgery))
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class _PatientSurgeryTile extends StatelessWidget {
  const _PatientSurgeryTile({required this.surgery});

  final EyeSurgeryModel surgery;

  @override
  Widget build(BuildContext context) {
    final dateTime = DateFormat('dd/MM/yyyy').format(surgery.surgeryDate) +
        (surgery.surgeryTime == null ? '' : ' · ${surgery.surgeryTime}');

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        side: const BorderSide(color: AppColors.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        leading: CircleAvatar(
          backgroundColor: AppColors.primaryContainer.withValues(alpha: 0.2),
          child: const Icon(
            Icons.visibility_outlined,
            color: AppColors.primary,
            size: 20,
          ),
        ),
        title: Text(
          surgery.displaySurgeryType,
          style: AppTypography.bodyMd.copyWith(
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              '${surgery.eyeSide.toUpperCase()} eye · ${surgery.assignedStaffName ?? 'Staff unassigned'}',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              dateTime,
              style: AppTypography.bodySm.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SurgeryStatusLabel(
              status: surgery.status,
              isMissed: surgery.isMissed,
            ),
            const SizedBox(width: AppSpacing.xs),
            const Icon(
              Icons.chevron_right,
              color: AppColors.outline,
              size: 20,
            ),
          ],
        ),
        onTap: () async {
          await showDialog<void>(
            context: context,
            builder: (_) => EyeSurgeryDetailDialog(surgery: surgery),
          );
        },
      ),
    );
  }
}

class _SurgeryStatusLabel extends StatelessWidget {
  const _SurgeryStatusLabel({required this.status, this.isMissed = false});

  final String status;
  final bool isMissed;

  @override
  Widget build(BuildContext context) {
    if (isMissed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.red.shade100,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Text(
          'MISSED',
          style: AppTypography.labelCaps.copyWith(
            color: Colors.red.shade900,
            fontWeight: FontWeight.bold,
            fontSize: 10,
          ),
        ),
      );
    }

    final isCancelled = status == 'cancelled';
    final isDischarged = status == 'discharged';
    final label = status.replaceAll('_', ' ').toUpperCase();

    Color bg;
    Color fg;
    if (isCancelled) {
      bg = Colors.red.shade100;
      fg = Colors.red.shade900;
    } else if (isDischarged) {
      bg = Colors.green.shade100;
      fg = Colors.green.shade800;
    } else {
      bg = AppColors.primaryContainer.withValues(alpha: 0.3);
      fg = AppColors.primary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        label,
        style: AppTypography.labelCaps.copyWith(
          color: fg,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _PatientSurgeryMessage extends StatelessWidget {
  const _PatientSurgeryMessage({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(child: Text(text, style: AppTypography.bodySm)),
            if (onRetry != null)
              IconButton(
                tooltip: 'Retry loading surgeries',
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
      );
}
