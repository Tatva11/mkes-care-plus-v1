import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../appointments/repositories/appointment_repository.dart';
import '../../appointments/widgets/appointment_form_dialog.dart';
import '../../auth/providers/auth_provider.dart';
import '../../inventory/providers/inventory_provider.dart';
import '../../patients/screens/patient_details_screen.dart';
import '../models/eye_surgery_model.dart';
import '../providers/eye_surgery_provider.dart';
import '../widgets/eye_surgery_form_dialog.dart';
import '../widgets/eye_surgery_item_dialogs.dart';
import '../widgets/assign_eye_surgery_staff_dialog.dart';
import '../widgets/eye_surgery_detail_dialog.dart';
import '../widgets/eye_surgery_discharge_dialog.dart';

class EyeSurgeryScreen extends ConsumerStatefulWidget {
  const EyeSurgeryScreen({super.key});

  @override
  ConsumerState<EyeSurgeryScreen> createState() => _EyeSurgeryScreenState();
}

class _EyeSurgeryScreenState extends ConsumerState<EyeSurgeryScreen> {
  String? _selectedSurgeryId;

  static const _filterStatuses = [
    'all',
    'scheduled',
    'in_progress',
    'pre_op',
    'in_surgery',
    'post_op',
    'billing',
    'discharged',
    'cancelled',
    'missed',
  ];

  Future<void> _editSurgery(
    BuildContext context,
    WidgetRef ref,
    EyeSurgeryModel surgery,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => EyeSurgeryFormDialog(existingSurgery: surgery),
    );
    if (saved == true) {
      ref.invalidate(eyeSurgeriesForPatientProvider(surgery.patientId));
    }
  }

  Future<void> _showDetails(
    BuildContext context,
    EyeSurgeryModel surgery, [
    int initialTab = 0,
  ]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => EyeSurgeryDetailDialog(
        surgery: surgery,
        initialTabIndex: initialTab,
      ),
    );
  }

  Future<void> _changeStatus(
    BuildContext context,
    WidgetRef ref,
    EyeSurgeryModel surgery,
    String nextStatus,
  ) async {
    if (nextStatus == 'pre_op') {
      final staffId = surgery.assignedStaffId?.trim();
      if (staffId == null || staffId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'An Admin must assign staff to this surgery before starting Pre-op.',
            ),
          ),
        );
        return;
      }
    }
    if (nextStatus == 'in_surgery' && !surgery.isPreOpChecklistComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complete the pre-op checklist before entering surgery.',
          ),
        ),
      );
      // Automatically open checklist dialog highlighting incomplete items
      await _showChecklist(context, ref, surgery, highlightIncomplete: true);
      return;
    }
    if (nextStatus == 'discharged') {
      final discharged = await showDialog<bool>(
        context: context,
        builder: (_) => EyeSurgeryDischargeDialog(surgery: surgery),
      );
      if (discharged == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Surgery marked as Discharged.')),
        );
      }
      return;
    }
    final remarksController =
        TextEditingController(text: surgery.remarks ?? '');
    final needsRemarks = nextStatus == 'post_op';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Change status to ${_statusLabel(nextStatus)}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                '${surgery.patientName ?? 'Patient'} · ${surgery.displaySurgeryType}'),
            if (nextStatus == 'in_surgery') ...[
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'This will atomically deduct the finalized surgery item quantities from inventory once.',
              ),
            ],
            if (needsRemarks) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: remarksController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Post-op / discharge remarks',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      remarksController.dispose();
      return;
    }

    try {
      final notifier = ref.read(eyeSurgeryListProvider.notifier);
      if (needsRemarks) {
        await notifier.updateDetails(
          id: surgery.id,
          iolDetails: surgery.iolDetails,
          remarks: remarksController.text,
        );
      }
      if (nextStatus == 'in_surgery') {
        await notifier.startSurgery(surgery.id);
        ref.invalidate(inventoryProvider);
      } else {
        await notifier.updateStatus(surgery.id, nextStatus);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Status updated to ${_statusLabel(nextStatus)}.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to update status: $error')),
        );
      }
    } finally {
      remarksController.dispose();
    }
  }

  Future<void> _showChecklist(
    BuildContext context,
    WidgetRef ref,
    EyeSurgeryModel surgery, {
    bool highlightIncomplete = false,
  }) async {
    final updated = await showDialog<Map<String, bool>>(
      context: context,
      builder: (_) => _EyeSurgeryChecklistDialog(
        surgery: surgery,
        highlightIncomplete: highlightIncomplete,
      ),
    );
    if (updated == null) return;
    try {
      await ref
          .read(eyeSurgeryListProvider.notifier)
          .updateChecklist(surgery.id, updated);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to save checklist: $error')),
        );
      }
    }
  }

  Future<void> _scheduleFollowUp(
    BuildContext context,
    WidgetRef ref,
    EyeSurgeryModel surgery,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AppointmentFormDialog(
        initialPatientId: surgery.patientId,
        initialPatientName: surgery.patientName,
        initialAppointmentType: 'follow_up',
      ),
    );
    if (result == true) {
      try {
        final appointments = await ref
            .read(appointmentRepositoryProvider)
            .fetchPatientAppointments(
              patientId: surgery.patientId,
              department: 'eye',
            );
        final latest = appointments.isNotEmpty ? appointments.first : null;
        if (latest != null) {
          await ref
              .read(eyeSurgeryListProvider.notifier)
              .linkFollowUpAppointment(surgery.id, latest.id);
        }
      } catch (_) {}
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Follow-up appointment scheduled successfully.'),
          ),
        );
      }
    }
  }

  Future<void> _rescheduleSurgery(
    BuildContext context,
    WidgetRef ref,
    EyeSurgeryModel surgery,
  ) async {
    final result = await showDialog<({DateTime date, String? time})>(
      context: context,
      builder: (_) => _RescheduleSurgeryDialog(surgery: surgery),
    );
    if (result == null) return;
    try {
      await ref.read(eyeSurgeryListProvider.notifier).rescheduleSurgery(
            id: surgery.id,
            surgeryDate: result.date,
            surgeryTime: result.time,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Surgery rescheduled successfully.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to reschedule surgery: $e')),
        );
      }
    }
  }

  Future<void> _confirmDeleteSurgery(
    BuildContext context,
    WidgetRef ref,
    EyeSurgeryModel surgery,
  ) async {
    final dateStr = DateFormat('d MMM yyyy').format(surgery.surgeryDate);
    final timeStr = surgery.surgeryTime ?? 'Not set';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            SizedBox(width: AppSpacing.xs),
            Expanded(child: Text('Delete Eye Surgery?')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to delete this eye surgery record? This action is permanent and cannot be undone.',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Patient: ${surgery.patientName ?? surgery.patientId}'
                    '${surgery.patientNumber != null ? ' (${surgery.patientNumber})' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text('Procedure: ${surgery.displaySurgeryType}'),
                  const SizedBox(height: 4),
                  Text('Eye: ${_label(surgery.eyeSide)} eye'),
                  const SizedBox(height: 4),
                  Text('Date: $dateStr · Time: $timeStr'),
                  const SizedBox(height: 4),
                  Text('Status: ${_statusLabel(surgery.status)}'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(eyeSurgeryListProvider.notifier).deleteSurgery(surgery.id);
      ref.invalidate(eyeSurgeriesForPatientProvider(surgery.patientId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Surgery record deleted successfully.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete surgery: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _showItems(
    BuildContext context,
    WidgetRef ref,
    EyeSurgeryModel surgery,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => EyeSurgeryItemsDialog(surgery: surgery),
    );
    ref.invalidate(eyeSurgeryItemsProvider(surgery.id));
    ref.invalidate(eyeSurgeryListProvider);
  }

  Future<void> _managePresets(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const SurgeryInventoryPresetsDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surgeriesAsync = ref.watch(eyeSurgeryListProvider);
    final filtered = ref.watch(filteredEyeSurgeriesProvider);
    final search = ref.watch(eyeSurgerySearchQueryProvider);
    final status = ref.watch(eyeSurgeryStatusFilterProvider);
    final selectedDate = ref.watch(eyeSurgerySelectedDateProvider);
    final role = ref.watch(currentUserRoleProvider).valueOrNull;
    final stats = ref.watch(eyeSurgeryStatsProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= 768;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Eye Surgery'),
        actions: [
          if (role == 'admin')
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Tooltip(
                message: 'Surgery Inventory Presets',
                child: FilledButton.tonalIcon(
                  key: const Key('surgery_inventory_presets_button'),
                  onPressed: () => _managePresets(context),
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: Text(isDesktop ? 'Surgery Inventory Presets' : 'Presets'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Refresh surgeries',
            onPressed: () =>
                ref.read(eyeSurgeryListProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog<bool>(
          context: context,
          builder: (_) => const EyeSurgeryFormDialog(),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Schedule surgery'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(eyeSurgeryListProvider.notifier).refresh(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Date Selector Bar (matching Staff Tasks pattern)
            SliverToBoxAdapter(
              child: Container(
            margin: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous Day',
                  onPressed: () {
                    final cur = ref.read(eyeSurgerySelectedDateProvider);
                    ref.read(eyeSurgerySelectedDateProvider.notifier).state =
                        DateTime(cur.year, cur.month, cur.day - 1);
                  },
                ),
                InkWell(
                  onTap: () async {
                    final cur = ref.read(eyeSurgerySelectedDateProvider);
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: cur,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) {
                      ref.read(eyeSurgerySelectedDateProvider.notifier).state =
                          DateTime(picked.year, picked.month, picked.day);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 16, color: AppColors.primary),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          EyeSurgeryModel.isSameCalendarDay(
                                  selectedDate, DateTime.now())
                              ? 'Today (${DateFormat('d MMM').format(selectedDate)})'
                              : DateFormat('EEE, d MMM yyyy')
                                  .format(selectedDate),
                          style: AppTypography.bodyMd.copyWith(
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!EyeSurgeryModel.isSameCalendarDay(
                        selectedDate, DateTime.now()))
                      TextButton(
                        onPressed: () {
                          final now = DateTime.now();
                          ref
                              .read(eyeSurgerySelectedDateProvider.notifier)
                              .state =
                              DateTime(now.year, now.month, now.day);
                        },
                        child: const Text('Today'),
                      ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      tooltip: 'Next Day',
                      onPressed: () {
                        final cur = ref.read(eyeSurgerySelectedDateProvider);
                        ref.read(eyeSurgerySelectedDateProvider.notifier).state =
                            DateTime(cur.year, cur.month, cur.day + 1);
                      },
                    ),
                  ],
                ),
              ],
            ),
              ),
            ),
            // ── KPI Summary Cards (Matching Dental Lab design) ──────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
                child: _buildKpiRow(context, ref, stats, isDesktop, status),
              ),
            ),
            // ── Controls: Search & Status Filter ────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const searchField = _EyeSurgerySearchField();
                    final filter = DropdownButtonFormField<String>(
                      initialValue:
                          _filterStatuses.contains(status) ? status : 'all',
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _filterStatuses
                          .map((value) => DropdownMenuItem(
                                value: value,
                                child: Text(_statusLabel(value),
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          ref
                              .read(eyeSurgeryStatusFilterProvider.notifier)
                              .state = value;
                        }
                      },
                    );
                    if (constraints.maxWidth < 520) {
                      return Column(
                        children: [
                          searchField,
                          const SizedBox(height: AppSpacing.sm),
                          filter
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(flex: 3, child: searchField),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(flex: 2, child: filter),
                      ],
                    );
                  },
                ),
              ),
            ),
            // ── Main Content / Surgeries List ───────────────────────────
            ...surgeriesAsync.when(
              loading: () => [
                const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),
              ],
              error: (error, _) => [
                SliverToBoxAdapter(
                  child: _MessageState(
                    icon: Icons.error_outline,
                    title: 'Unable to load surgeries',
                    detail: '$error',
                    action: FilledButton.icon(
                      onPressed: () =>
                          ref.read(eyeSurgeryListProvider.notifier).refresh(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ),
                ),
              ],
              data: (_) {
                if (filtered.isEmpty) {
                  return [
                    SliverToBoxAdapter(
                      child:
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.lg),
                            child: _MessageState(
                              icon: Icons.calendar_today_outlined,
                              title: search.isEmpty && status == 'all'
                                  ? 'No surgeries scheduled for this date'
                                  : 'No matching surgeries',
                              detail: search.isEmpty && status == 'all'
                                  ? (EyeSurgeryModel.isSameCalendarDay(
                                          selectedDate, DateTime.now())
                                      ? 'No surgeries scheduled for today.'
                                      : 'No surgeries scheduled for ${DateFormat('d MMM yyyy').format(selectedDate)}.')
                                  : 'Adjust the date, search query, or status filter.',
                              action: Wrap(
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.xs,
                                alignment: WrapAlignment.center,
                                children: [
                                  if (!EyeSurgeryModel.isSameCalendarDay(
                                      selectedDate, DateTime.now()))
                                    FilledButton.icon(
                                      onPressed: () {
                                        final now = DateTime.now();
                                        ref
                                            .read(eyeSurgerySelectedDateProvider
                                                .notifier)
                                            .state =
                                            DateTime(
                                                now.year, now.month, now.day);
                                      },
                                      icon: const Icon(Icons.today, size: 16),
                                      label: const Text('Return to Today'),
                                    ),
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: selectedDate,
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime(2035),
                                      );
                                      if (picked != null) {
                                        ref
                                            .read(eyeSurgerySelectedDateProvider
                                                .notifier)
                                            .state =
                                            DateTime(picked.year, picked.month,
                                                picked.day);
                                      }
                                    },
                                    icon: const Icon(Icons.calendar_month,
                                        size: 16),
                                    label: const Text('Select another date'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ];
                    }

                  final selectedSurgery = filtered.firstWhere(
                    (s) => s.id == _selectedSurgeryId,
                    orElse: () => filtered.first,
                  );

                  final screenWidth = MediaQuery.sizeOf(context).width;
                  final isWideDesktop = screenWidth >= 960;

                  if (isWideDesktop) {
                    return [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md, AppSpacing.xs, AppSpacing.md, 96),
                        sliver: SliverToBoxAdapter(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Left: Surgeries List
                              Expanded(
                                flex: 6,
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: AppSpacing.sm),
                                  itemBuilder: (context, index) {
                                    final surgery = filtered[index];
                                    return _SurgeryCard(
                                      surgery: surgery,
                                      role: role,
                                      isDesktop: true,
                                      isSelected:
                                          surgery.id == selectedSurgery.id,
                                      onSelect: () => setState(() =>
                                          _selectedSurgeryId = surgery.id),
                                      onDetails: () =>
                                          _showDetails(context, surgery, 0),
                                      onBilling: () =>
                                          _showDetails(context, surgery, 1),
                                      onEdit: () =>
                                          _editSurgery(context, ref, surgery),
                                      onAssignStaff: () =>
                                          showAssignEyeSurgeryStaffDialog(context, ref, surgery),
                                      onChecklist: () =>
                                          _showChecklist(context, ref, surgery),
                                      onItems: () =>
                                          _showItems(context, ref, surgery),
                                      onAdvance: (next) =>
                                          _changeStatus(context, ref, surgery, next),
                                      onScheduleFollowUp: () =>
                                          _scheduleFollowUp(context, ref, surgery),
                                      onReschedule: () =>
                                          _rescheduleSurgery(context, ref, surgery),
                                      onDelete: () =>
                                          _confirmDeleteSurgery(context, ref, surgery),
                                      onPatient: surgery.patientId.isEmpty
                                          ? null
                                          : () => Navigator.of(context).push(
                                                MaterialPageRoute<void>(
                                                  builder: (_) =>
                                                      PatientDetailsScreen(
                                                          patientId:
                                                              surgery.patientId),
                                                ),
                                              ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              // Right: Surgery Required Supplies & Items Panel (Requirement 10)
                              Expanded(
                                flex: 4,
                                child: _EyeSurgeryRightSidePanel(
                                  surgery: selectedSurgery,
                                  onCustomize: () =>
                                      _showItems(context, ref, selectedSurgery),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ];
                  }

                  return [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md, AppSpacing.xs, AppSpacing.md, 96),
                      sliver: SliverList.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final surgery = filtered[index];
                          return _SurgeryCard(
                            surgery: surgery,
                            role: role,
                            isDesktop: false,
                            isSelected: false,
                            onDetails: () =>
                                _showDetails(context, surgery, 0),
                            onBilling: () =>
                                _showDetails(context, surgery, 1),
                            onEdit: () => _editSurgery(context, ref, surgery),
                            onAssignStaff: () =>
                                showAssignEyeSurgeryStaffDialog(context, ref, surgery),
                            onChecklist: () =>
                                _showChecklist(context, ref, surgery),
                            onItems: () => _showItems(context, ref, surgery),
                            onAdvance: (next) =>
                                _changeStatus(context, ref, surgery, next),
                            onScheduleFollowUp: () =>
                                _scheduleFollowUp(context, ref, surgery),
                            onReschedule: () =>
                                _rescheduleSurgery(context, ref, surgery),
                            onDelete: () =>
                                _confirmDeleteSurgery(context, ref, surgery),
                            onPatient: surgery.patientId.isEmpty
                                ? null
                                : () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => PatientDetailsScreen(
                                            patientId: surgery.patientId),
                                      ),
                                    ),
                          );
                        },
                      ),
                    ),
                  ];
                },
              ),
            ],
          ),
        ),
      );
  }

  static String _statusLabel(String status) {
    if (status == 'all') return 'All statuses';
    if (status == 'in_progress') return 'In Progress';
    if (status == 'missed') return 'Missed';
    return status
        .split('_')
        .map((part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  static String _label(String value) => value
      .split('_')
      .map((part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  Widget _buildKpiRow(
    BuildContext context,
    WidgetRef ref,
    EyeSurgeryStats stats,
    bool isDesktop,
    String currentFilter,
  ) {
    final cards = [
      _KpiCard(
        title: 'Total Surgeries',
        count: '${stats.total}',
        icon: Icons.visibility_outlined,
        color: AppColors.primary,
        onTap: () =>
            ref.read(eyeSurgeryStatusFilterProvider.notifier).state = 'all',
        isActive: currentFilter == 'all',
      ),
      _KpiCard(
        title: 'Scheduled',
        count: '${stats.scheduled}',
        icon: Icons.calendar_today_outlined,
        color: AppColors.secondary,
        onTap: () => ref
            .read(eyeSurgeryStatusFilterProvider.notifier)
            .state = 'scheduled',
        isActive: currentFilter == 'scheduled',
      ),
      _KpiCard(
        title: 'In Progress',
        count: '${stats.inProgress}',
        icon: Icons.hourglass_top_outlined,
        color: Colors.amber.shade800,
        onTap: () => ref
            .read(eyeSurgeryStatusFilterProvider.notifier)
            .state = 'in_progress',
        isActive: currentFilter == 'in_progress',
      ),
      _KpiCard(
        title: 'Discharged',
        count: '${stats.discharged}',
        icon: Icons.check_circle_outline,
        color: Colors.green.shade700,
        onTap: () => ref
            .read(eyeSurgeryStatusFilterProvider.notifier)
            .state = 'discharged',
        isActive: currentFilter == 'discharged',
      ),
    ];

    if (isDesktop) {
      return Row(
        children: cards
            .map((c) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: c,
                  ),
                ))
            .toList(),
      );
    } else {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: cards[0],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: cards[1],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: cards[2],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: cards[3],
                ),
              ),
            ],
          ),
        ],
      );
    }
  }
}

class _SurgeryCard extends StatelessWidget {
  const _SurgeryCard({
    required this.surgery,
    this.role,
    this.isDesktop = false,
    this.isSelected = false,
    this.onSelect,
    required this.onEdit,
    this.onDetails,
    this.onBilling,
    required this.onAssignStaff,
    required this.onChecklist,
    required this.onItems,
    required this.onAdvance,
    required this.onScheduleFollowUp,
    required this.onReschedule,
    this.onDelete,
    this.onPatient,
  });

  final EyeSurgeryModel surgery;
  final String? role;
  final bool isDesktop;
  final bool isSelected;
  final VoidCallback? onSelect;
  final VoidCallback onEdit;
  final VoidCallback? onDetails;
  final VoidCallback? onBilling;
  final VoidCallback onAssignStaff;
  final VoidCallback onChecklist;
  final VoidCallback onItems;
  final ValueChanged<String> onAdvance;
  final VoidCallback onScheduleFollowUp;
  final VoidCallback onReschedule;
  final VoidCallback? onDelete;
  final VoidCallback? onPatient;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('d MMM yyyy').format(surgery.surgeryDate);
    final time = surgery.surgeryTime;
    final next = _nextStatus(surgery.status);
    final completedChecklist =
        surgery.preOpChecklist.values.where((value) => value).length;
    final isAdmin = role?.toLowerCase() == 'admin';

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.outlineVariant,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.xs, AppSpacing.xs, AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      onSelect?.call();
                      onPatient?.call();
                    },
                    child: Text(
                      surgery.patientName ?? 'Patient details unavailable',
                      style: AppTypography.headlineMd.copyWith(fontSize: 18),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                _StatusTag(
                  status: surgery.status,
                  isMissed: surgery.isMissed,
                ),
                PopupMenuButton<String>(
                  tooltip: 'Surgery actions',
                  onSelected: (action) {
                    if (action == 'details') onDetails?.call();
                    if (action == 'billing') onBilling?.call();
                    if (action == 'edit') onEdit();
                    if (action == 'assign_staff' && isAdmin && !surgery.isDischarged) onAssignStaff();
                    if (action == 'checklist') onChecklist();
                    if (action == 'items' || action == 'customize_items') {
                      onItems();
                    }
                    if (action == 'advance' && next != null) onAdvance(next);
                    if (action == 'cancel') onAdvance('cancelled');
                    if (action == 'follow_up') onScheduleFollowUp();
                    if (action == 'reschedule') onReschedule();
                    if (action == 'delete' && onDelete != null) onDelete!();
                  },
                  itemBuilder: (context) {
                    // Critical UI requirement (Section 5): Discharged surgery exposes EXACTLY two actions
                    if (surgery.isDischarged) {
                      return const [
                        PopupMenuItem(
                          value: 'follow_up',
                          child: Text('Schedule follow-up appointment'),
                        ),
                        PopupMenuItem(
                          value: 'billing',
                          child: Text('Billing & Insurance'),
                        ),
                      ];
                    }
                    return [
                      const PopupMenuItem(
                          value: 'details', child: Text('Surgery details')),
                      if (surgery.canAccessBilling)
                        const PopupMenuItem(
                            value: 'billing', child: Text('Billing & Insurance')),
                      const PopupMenuItem(
                          value: 'edit', child: Text('Edit surgery')),
                      if (isAdmin && !surgery.isDischarged)
                        const PopupMenuItem(
                            value: 'assign_staff', child: Text('Assign staff')),
                      const PopupMenuItem(
                          value: 'checklist', child: Text('Pre-op checklist')),
                      const PopupMenuItem(
                          value: 'items', child: Text('Customize items')),
                      if (next != null)
                        PopupMenuItem(
                            value: 'advance',
                            child: Text('Advance to ${_label(next)}')),
                      if (surgery.isMissed)
                        const PopupMenuItem(
                          value: 'reschedule',
                          child: Text('Reschedule surgery'),
                        ),
                      if (const {'scheduled', 'pre_op', 'in_surgery', 'post_op', 'billing'}
                          .contains(surgery.status))
                        const PopupMenuItem(
                            value: 'cancel', child: Text('Cancel surgery')),
                      if (isAdmin)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'Delete surgery',
                            style: TextStyle(color: AppColors.error),
                          ),
                        ),
                    ];
                  },
                  icon: const Icon(Icons.more_vert),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: AppSpacing.sm),
              child: Text(surgery.patientNumber ?? surgery.patientId,
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.onSurfaceVariant)),
            ),
            Text(surgery.displaySurgeryType,
                style:
                    AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                _InfoValue(
                    icon: Icons.visibility_outlined,
                    label: _label(surgery.eyeSide)),
                _InfoValue(
                    icon: Icons.calendar_today_outlined,
                    label: 'Surgery $date'),
                if (time != null)
                  _InfoValue(icon: Icons.access_time_outlined, label: time),
                _InfoValue(
                    icon: Icons.person_outline,
                    label: surgery.assignedStaffName ?? 'Staff unassigned'),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Action Buttons Area
            if (surgery.isDischarged) ...[
              // Section 5 requirement: Exactly Two Actions for Discharged Surgeries
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  if (surgery.followUpAppointmentId == null)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      ),
                      onPressed: onScheduleFollowUp,
                      icon: const Icon(Icons.calendar_month_outlined, size: 16),
                      label: const Text(
                        'Schedule Follow-up Appointment',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        foregroundColor: Colors.green.shade800,
                        side: BorderSide(color: Colors.green.shade600),
                      ),
                      onPressed: onScheduleFollowUp,
                      icon: const Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
                      label: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Follow-up Scheduled',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            ' · Edit',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                    onPressed: onBilling ?? onDetails,
                    icon: const Icon(Icons.receipt_long_outlined, size: 16),
                    label: const Text(
                      'Billing & Insurance',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // Active / Pre-discharge surgery workflow actions
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                    onPressed: onChecklist,
                    icon: Icon(
                      completedChecklist == EyeSurgeryModel.checklistItems.length
                          ? Icons.check_circle
                          : Icons.checklist_outlined,
                      size: 16,
                      color: completedChecklist == EyeSurgeryModel.checklistItems.length
                          ? Colors.green
                          : AppColors.primary,
                    ),
                    label: Text(
                      'Pre-op Checklist ($completedChecklist / ${EyeSurgeryModel.checklistItems.length})',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: completedChecklist == EyeSurgeryModel.checklistItems.length
                            ? Colors.green.shade800
                            : AppColors.primary,
                      ),
                    ),
                  ),
                  if (surgery.canAccessBilling)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      ),
                      onPressed: onBilling ?? onDetails,
                      icon: const Icon(Icons.receipt_long_outlined, size: 16),
                      label: const Text(
                        'Billing & Insurance',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (isAdmin && !surgery.isDischarged)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      ),
                      onPressed: onAssignStaff,
                      icon: const Icon(Icons.person_add_alt_1_outlined, size: 16),
                      label: Text(
                        surgery.assignedStaffName == null ? 'Assign Staff' : 'Reassign Staff',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              // Stage Advance: Post-Op to Billing
              if (surgery.status == 'post_op') ...[
                const SizedBox(height: AppSpacing.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.blue.shade50,
                      foregroundColor: Colors.blue.shade900,
                    ),
                    onPressed: () => onAdvance('billing'),
                    icon: const Icon(Icons.receipt_long, size: 16),
                    label: const Text('Proceed to Billing'),
                  ),
                ),
              ],
              // Stage Advance: Billing to Discharged
              if (surgery.status == 'billing') ...[
                const SizedBox(height: AppSpacing.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.amber.shade50,
                      foregroundColor: Colors.amber.shade900,
                    ),
                    onPressed: () => onAdvance('discharged'),
                    icon: const Icon(Icons.exit_to_app, size: 16),
                    label: const Text('Discharge Patient (Review Billing & Insurance)'),
                  ),
                ),
              ],
              // Missed Surgery handling
              if (surgery.isMissed) ...[
                const SizedBox(height: AppSpacing.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.red.shade50,
                      foregroundColor: Colors.red.shade900,
                    ),
                    onPressed: onReschedule,
                    icon: const Icon(Icons.edit_calendar_outlined, size: 16),
                    label: const Text('Reschedule Surgery'),
                  ),
                ),
              ],
            ],
            if (surgery.iolDetails?.isNotEmpty == true ||
                surgery.remarks?.isNotEmpty == true) ...[
              const SizedBox(height: AppSpacing.xs),
              if (surgery.iolDetails?.isNotEmpty == true)
                Text('IOL: ${surgery.iolDetails}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySm),
              if (surgery.remarks?.isNotEmpty == true)
                Text('Remarks: ${surgery.remarks}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySm),
            ],
            // On mobile / narrow screens, show inline expandable supplies preview (only before discharge)
            if (!isDesktop && !surgery.isDischarged) ...[
              const SizedBox(height: AppSpacing.xs),
              _SurgeryCardSuppliesPreview(
                surgery: surgery,
                onCustomize: onItems,
              ),
            ],
            ],
          ),
        ),
      );
    }

  static String? _nextStatus(String status) => const {
        'scheduled': 'pre_op',
        'pre_op': 'in_surgery',
        'in_surgery': 'post_op',
        'post_op': 'billing',
        'billing': 'discharged',
      }[status];

  static String _label(String value) => value
      .split('_')
      .map((part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
    required this.onTap,
    this.isActive = false,
  });

  final String title;
  final String count;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isActive
              ? color.withValues(alpha: 0.1)
              : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: isActive ? color : AppColors.outlineVariant,
            width: isActive ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count,
                    style: AppTypography.headlineMd.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      color: color,
                    ),
                  ),
                  Text(
                    title,
                    style: AppTypography.labelCaps.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoValue extends StatelessWidget {
  const _InfoValue({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.onSurfaceVariant),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: AppTypography.bodySm),
        ],
      );
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.status, this.isMissed = false});

  final String status;
  final bool isMissed;

  @override
  Widget build(BuildContext context) {
    if (isMissed) {
      return Container(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.red.shade100,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: Colors.red.shade600),
        ),
        child: Text(
          'MISSED',
          style: TextStyle(
            color: Colors.red.shade900,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      );
    }
    if (status == 'billing') {
      return Container(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.amber.shade100,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: Colors.amber.shade700),
        ),
        child: Text(
          'BILLING',
          style: TextStyle(
            color: Colors.amber.shade900,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      );
    }
    final isFinal = status == 'discharged' || status == 'cancelled';
    final color = status == 'cancelled' ? AppColors.error : AppColors.primary;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 5),
      decoration: BoxDecoration(
        color: isFinal
            ? color.withValues(alpha: 0.1)
            : AppColors.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: AppTypography.labelCaps.copyWith(color: color, fontSize: 10),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState(
      {required this.icon,
      required this.title,
      required this.detail,
      this.action});

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: AppColors.onSurfaceVariant),
              const SizedBox(height: AppSpacing.sm),
              Text(title,
                  style: AppTypography.headlineMd, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xs),
              Text(detail,
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.onSurfaceVariant),
                  textAlign: TextAlign.center),
              if (action != null) ...[
                const SizedBox(height: AppSpacing.md),
                action!
              ],
            ],
          ),
        ),
      );
}

class _EyeSurgeryChecklistDialog extends StatefulWidget {
  const _EyeSurgeryChecklistDialog({
    required this.surgery,
    this.highlightIncomplete = false,
  });

  final EyeSurgeryModel surgery;
  final bool highlightIncomplete;

  @override
  State<_EyeSurgeryChecklistDialog> createState() =>
      _EyeSurgeryChecklistDialogState();
}

class _EyeSurgeryChecklistDialogState
    extends State<_EyeSurgeryChecklistDialog> {
  late final Map<String, bool> _checklist =
      Map.of(widget.surgery.preOpChecklist);

  @override
  Widget build(BuildContext context) {
    final completedCount = _checklist.values.where((v) => v).length;
    final totalCount = EyeSurgeryModel.checklistItems.length;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.checklist_outlined, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(child: Text('Pre-op Checklist')),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: completedCount == totalCount
                  ? Colors.green.withValues(alpha: 0.15)
                  : Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$completedCount / $totalCount completed',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: completedCount == totalCount
                    ? Colors.green.shade800
                    : Colors.orange.shade800,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.highlightIncomplete && completedCount < totalCount) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: AppColors.error, size: 20),
                      SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          'Complete all 8 required items before surgery',
                          style: TextStyle(
                            color: AppColors.error,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              ...EyeSurgeryModel.checklistItems.entries.map((item) {
                final isDone = _checklist[item.key] ?? false;
                final isIncomplete = !isDone && widget.highlightIncomplete;

                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    border: isIncomplete
                        ? Border.all(color: AppColors.error.withValues(alpha: 0.4))
                        : null,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Material(
                    color: isIncomplete
                        ? AppColors.error.withValues(alpha: 0.05)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        item.value,
                        style: TextStyle(
                          fontWeight:
                              isIncomplete ? FontWeight.bold : FontWeight.normal,
                          color: isIncomplete ? AppColors.error : null,
                        ),
                      ),
                      value: isDone,
                      onChanged: (checked) => setState(
                        () => _checklist[item.key] = checked ?? false,
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _checklist),
          icon: const Icon(Icons.check, size: 16),
          label: const Text('Save checklist'),
        ),
      ],
    );
  }
}

class _RescheduleSurgeryDialog extends StatefulWidget {
  const _RescheduleSurgeryDialog({required this.surgery});

  final EyeSurgeryModel surgery;

  @override
  State<_RescheduleSurgeryDialog> createState() =>
      _RescheduleSurgeryDialogState();
}

class _RescheduleSurgeryDialogState extends State<_RescheduleSurgeryDialog> {
  late DateTime _newDate;
  TimeOfDay? _newTime;

  @override
  void initState() {
    super.initState();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _newDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    _newTime = const TimeOfDay(hour: 9, minute: 0);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reschedule Surgery'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.surgery.patientName ?? 'Patient'} · ${widget.surgery.displaySurgeryType}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Select a new future date and time for the surgery. Patient, assigned staff, checklist, and items will be preserved.',
              style: TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _newDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(() => _newDate = picked);
                }
              },
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(
                'New Date: ${DateFormat('d MMM yyyy').format(_newDate)}',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _newTime ?? const TimeOfDay(hour: 9, minute: 0),
                );
                if (picked != null) {
                  setState(() => _newTime = picked);
                }
              },
              icon: const Icon(Icons.access_time_outlined),
              label: Text(
                _newTime == null
                    ? 'Select New Time *'
                    : 'New Time *: ${_newTime!.format(context)}',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_newTime == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Surgery time is required.')),
              );
              return;
            }
            final scheduledDateTime = DateTime(
              _newDate.year,
              _newDate.month,
              _newDate.day,
              _newTime!.hour,
              _newTime!.minute,
            );
            if (!scheduledDateTime.isAfter(DateTime.now())) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Rescheduled date and time must be in the future.')),
              );
              return;
            }
            final formattedTime =
                '${_newTime!.hour.toString().padLeft(2, '0')}:${_newTime!.minute.toString().padLeft(2, '0')}:00';
            Navigator.pop(context, (
              date: _newDate,
              time: formattedTime,
            ));
          },
          child: const Text('Confirm Reschedule'),
        ),
      ],
    );
  }
}

class _EyeSurgerySearchField extends ConsumerStatefulWidget {
  const _EyeSurgerySearchField();

  @override
  ConsumerState<_EyeSurgerySearchField> createState() =>
      _EyeSurgerySearchFieldState();
}

class _EyeSurgerySearchFieldState
    extends ConsumerState<_EyeSurgerySearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(eyeSurgerySearchQueryProvider),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(eyeSurgerySearchQueryProvider);
    return TextField(
      controller: _controller,
      onChanged: (value) =>
          ref.read(eyeSurgerySearchQueryProvider.notifier).state = value,
      decoration: InputDecoration(
        labelText: 'Search surgeries',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: search.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  _controller.clear();
                  ref.read(eyeSurgerySearchQueryProvider.notifier).state = '';
                },
                icon: const Icon(Icons.clear),
              ),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

// ── Right Side Panel: Required Surgery Items (Requirement 10) ───────────────

class _EyeSurgeryRightSidePanel extends ConsumerWidget {
  const _EyeSurgeryRightSidePanel({
    required this.surgery,
    required this.onCustomize,
  });

  final EyeSurgeryModel surgery;
  final VoidCallback onCustomize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(eyeSurgeryItemsProvider(surgery.id));

    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        side: const BorderSide(color: AppColors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.inventory_2_outlined,
                      color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'REQUIRED SURGERY ITEMS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        '${surgery.patientName ?? "Patient"} · ${surgery.displaySurgeryType}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (!surgery.isDischarged)
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                    onPressed: onCustomize,
                    icon: const Icon(Icons.tune, size: 15),
                    label:
                        const Text('Customize', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Side: ${surgery.eyeSide.toUpperCase()} · ${DateFormat('d MMM yyyy').format(surgery.surgeryDate)}',
              style: AppTypography.bodySm
                  .copyWith(color: AppColors.onSurfaceVariant, fontSize: 11),
            ),
            const Divider(height: 20),

            // Items List
            itemsAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, _) => Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  children: [
                    Text('Unable to load items: $err',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.error)),
                    TextButton.icon(
                      onPressed: () =>
                          ref.invalidate(eyeSurgeryItemsProvider(surgery.id)),
                      icon: const Icon(Icons.refresh, size: 14),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.lg, horizontal: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(color: AppColors.outlineVariant),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.inventory_outlined,
                            size: 36, color: AppColors.outline),
                        const SizedBox(height: AppSpacing.xs),
                        const Text(
                          'No supplies configured for this surgery.',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          surgery.isDischarged
                              ? 'Surgery has been discharged.'
                              : 'Click Customize to assign items from the surgical preset or catalog.',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                        if (!surgery.isDischarged) ...[
                          const SizedBox(height: AppSpacing.sm),
                          OutlinedButton.icon(
                            onPressed: onCustomize,
                            icon: const Icon(Icons.add, size: 14),
                            label: const Text('Add Surgery Items'),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${items.length} Supplies Configured',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurfaceVariant),
                        ),
                        if (surgery.inventoryConsumedAt != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Inventory Deducted',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ...items.map((item) {
                      final inStock = item.currentStock >= item.plannedQuantity;
                      final outOfStock = item.currentStock <= 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusSm),
                          border: Border.all(color: AppColors.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.inventoryItemName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: item.source == 'template'
                                        ? AppColors.primaryContainer
                                            .withValues(alpha: 0.15)
                                        : Colors.purple.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    item.source == 'template'
                                        ? 'Preset'
                                        : 'Custom',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: item.source == 'template'
                                          ? AppColors.primary
                                          : Colors.purple.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Required: ${item.plannedQuantity} ${item.unit}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: inStock
                                        ? Colors.green.withValues(alpha: 0.12)
                                        : outOfStock
                                            ? AppColors.error
                                                .withValues(alpha: 0.12)
                                            : Colors.orange
                                                .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    inStock
                                        ? 'In Stock (${item.currentStock.toStringAsFixed(item.currentStock.truncateToDouble() == item.currentStock ? 0 : 1)})'
                                        : outOfStock
                                            ? 'Out of Stock'
                                            : 'Low Stock (${item.currentStock.toStringAsFixed(item.currentStock.truncateToDouble() == item.currentStock ? 0 : 1)})',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: inStock
                                          ? Colors.green.shade800
                                          : outOfStock
                                              ? AppColors.error
                                              : Colors.orange.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mobile Inline Supplies Preview (Requirement 10 & 5) ─────────────────────

class _SurgeryCardSuppliesPreview extends ConsumerStatefulWidget {
  const _SurgeryCardSuppliesPreview({
    required this.surgery,
    required this.onCustomize,
  });

  final EyeSurgeryModel surgery;
  final VoidCallback onCustomize;

  @override
  ConsumerState<_SurgeryCardSuppliesPreview> createState() =>
      _SurgeryCardSuppliesPreviewState();
}

class _SurgeryCardSuppliesPreviewState
    extends ConsumerState<_SurgeryCardSuppliesPreview> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(eyeSurgeryItemsProvider(widget.surgery.id));
    final count = itemsAsync.valueOrNull?.length ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Required Supplies ($count items)',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: AppColors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: itemsAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.sm),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                error: (e, _) => Text(
                  'Error loading items: $e',
                  style: const TextStyle(fontSize: 11, color: AppColors.error),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'No supplies configured for this surgery.',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: widget.onCustomize,
                          icon: const Icon(Icons.add, size: 14),
                          label: const Text('Add Items',
                              style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...items.map((item) {
                        final inStock =
                            item.currentStock >= item.plannedQuantity;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '• ${item.inventoryItemName} (${item.plannedQuantity} ${item.unit})',
                                  style: const TextStyle(fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: inStock
                                      ? Colors.green.withValues(alpha: 0.12)
                                      : AppColors.error.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  inStock ? 'In Stock' : 'Low/Out',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: inStock
                                        ? Colors.green.shade800
                                        : AppColors.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: widget.onCustomize,
                          icon: const Icon(Icons.tune, size: 14),
                          label: const Text('Customize Supplies',
                              style: TextStyle(fontSize: 11)),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
