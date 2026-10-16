import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/eye_surgery_model.dart';
import '../providers/eye_surgery_provider.dart';

/// Shows a dialog to assign/reassign eligible Eye department staff to an eye surgery.
Future<EyeSurgeryModel?> showAssignEyeSurgeryStaffDialog(
  BuildContext context,
  WidgetRef ref,
  EyeSurgeryModel surgery,
) {
  if (surgery.isDischarged) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Staff assignment is not permitted for discharged surgeries.'),
        backgroundColor: AppColors.error,
      ),
    );
    return Future.value(null);
  }

  final role = ref.read(currentUserRoleProvider).valueOrNull;
  if (role?.toLowerCase() != 'admin') {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Access restricted: Only administrators can assign staff to surgeries.'),
        backgroundColor: AppColors.error,
      ),
    );
    return Future.value(null);
  }

  return showDialog<EyeSurgeryModel>(
    context: context,
    builder: (_) => _AssignEyeSurgeryStaffDialog(surgery: surgery),
  );
}

class _AssignEyeSurgeryStaffDialog extends ConsumerStatefulWidget {
  const _AssignEyeSurgeryStaffDialog({required this.surgery});

  final EyeSurgeryModel surgery;

  @override
  ConsumerState<_AssignEyeSurgeryStaffDialog> createState() =>
      _AssignEyeSurgeryStaffDialogState();
}

class _AssignEyeSurgeryStaffDialogState
    extends ConsumerState<_AssignEyeSurgeryStaffDialog> {
  String? _selectedStaffId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedStaffId = widget.surgery.assignedStaffId;
  }

  Future<void> _submit() async {
    final role = ref.read(currentUserRoleProvider).valueOrNull;
    if (role?.toLowerCase() != 'admin') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Access restricted: Only administrators can assign staff.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    setState(() => _saving = true);
    try {
      final updated = await ref
          .read(eyeSurgeryListProvider.notifier)
          .assignStaff(widget.surgery.id, _selectedStaffId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Staff assignment updated successfully.'),
            backgroundColor: AppColors.primary,
          ),
        );
        Navigator.of(context).pop(updated);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to assign staff: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidatesAsync = ref.watch(eyeSurgeryStaffCandidatesProvider);
    final surgery = widget.surgery;
    final dateStr = DateFormat('d MMM yyyy').format(surgery.surgeryDate);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.person_add_alt_1, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(child: Text('Assign Surgery Staff')),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Surgery summary preview
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    surgery.patientName ?? 'Patient #${surgery.patientId}',
                    style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${surgery.displaySurgeryType} · ${surgery.eyeSide.toUpperCase()} EYE · $dateStr ${surgery.surgeryTime ?? ""}',
                    style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                  ),
                  if (surgery.assignedStaffName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Currently Assigned: ${surgery.assignedStaffName}',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'SELECT ELIGIBLE EYE STAFF',
              style: AppTypography.labelCaps.copyWith(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xs),

            candidatesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text('Unable to load staff: $err', style: const TextStyle(color: AppColors.error)),
              ),
              data: (candidates) {
                return DropdownButtonFormField<String?>(
                  initialValue: _selectedStaffId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('— Unassigned (No staff) —', style: TextStyle(fontStyle: FontStyle.italic)),
                    ),
                    ...candidates.map((c) => DropdownMenuItem<String?>(
                          value: c.id,
                          child: Text(
                            '${c.fullName}${c.department != null ? " (${c.department})" : ""}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                  ],
                  onChanged: _saving
                      ? null
                      : (val) {
                          setState(() => _selectedStaffId = val);
                        },
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Assign Staff'),
        ),
      ],
    );
  }
}
