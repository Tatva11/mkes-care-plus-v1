import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_footer.dart';
import '../../staff/models/shift_configuration.dart';
import '../../staff/providers/attendance_provider.dart';
import '../../staff/repositories/attendance_repository.dart';
import '../models/user_profile.dart';
import '../providers/users_provider.dart';
import '../widgets/admin_shell.dart';
import 'administration_screen.dart';
import '../../staff/screens/staff_management_screen.dart';
import '../../patients/screens/patient_list_screen.dart';
import '../../inventory/screens/inventory_screen.dart';
import '../../notifications/repositories/notification_repository.dart';

class ShiftManagementScreen extends StatelessWidget {
  const ShiftManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      selectedItem: AdminNavItem.administration,
      onNavItemSelected: (item) {
        if (item == AdminNavItem.dashboard) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          return;
        }
        if (item == AdminNavItem.administration) {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const AdministrationScreen()),
            );
          }
          return;
        }
        if (item == AdminNavItem.staff) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const StaffManagementScreen()),
          );
          return;
        }
        if (item == AdminNavItem.patients) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const PatientListScreen()),
          );
          return;
        }
        if (item == AdminNavItem.operations) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
                builder: (_) => const InventoryManagementScreen()),
          );
          return;
        }
      },
      body: const ShiftManagementContent(),
    );
  }
}

class ShiftManagementContent extends ConsumerStatefulWidget {
  const ShiftManagementContent({super.key});

  @override
  ConsumerState<ShiftManagementContent> createState() =>
      _ShiftManagementContentState();
}

class _ShiftManagementContentState
    extends ConsumerState<ShiftManagementContent> {
  final _searchController = TextEditingController();
  String _filterShift = 'all'; // 'all' | 'morning' | 'afternoon' | 'both'
  String _searchQuery = '';
  final Set<String> _updatingStaffIds = {};

  // Track failed notification for safe retry mechanism
  Map<String, dynamic>? _failedNotification;
  bool _isRetryingNotification = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _editShiftTimings(ShiftConfiguration config) async {
    final startTod = config.startHourMinute;
    final endTod = config.endHourMinute;

    TimeOfDay currentStart = startTod;
    TimeOfDay currentEnd = endTod;
    final graceController =
        TextEditingController(text: '${config.gracePeriodMinutes}');

    final updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          String formatTod(TimeOfDay tod) {
            final period = tod.hour >= 12 ? 'PM' : 'AM';
            final h =
                tod.hour == 0 ? 12 : (tod.hour > 12 ? tod.hour - 12 : tod.hour);
            return '${h.toString().padLeft(2, '0')}:${tod.minute.toString().padLeft(2, '0')} $period';
          }

          final isAft = config.name == 'afternoon' || config.name == 'night';

          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  isAft ? Icons.wb_twilight_outlined : Icons.wb_sunny_outlined,
                  color: isAft ? AppColors.secondary : AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text('Edit ${config.displayName} Timings'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Configure standard shift start and end times for ${config.displayName}.',
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      side: const BorderSide(color: AppColors.outlineVariant),
                    ),
                    title: const Text('Start Time'),
                    trailing: OutlinedButton(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: ctx,
                          initialTime: currentStart,
                        );
                        if (picked != null) {
                          setDialogState(() => currentStart = picked);
                        }
                      },
                      child: Text(formatTod(currentStart)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      side: const BorderSide(color: AppColors.outlineVariant),
                    ),
                    title: const Text('End Time'),
                    trailing: OutlinedButton(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: ctx,
                          initialTime: currentEnd,
                        );
                        if (picked != null) {
                          setDialogState(() => currentEnd = picked);
                        }
                      },
                      child: Text(formatTod(currentEnd)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: graceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Late Grace Period (Minutes)',
                      helperText:
                          'Minutes after shift start before attendance is marked late.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final grace = int.tryParse(graceController.text.trim()) ?? 15;
                  final startStr =
                      '${currentStart.hour.toString().padLeft(2, '0')}:${currentStart.minute.toString().padLeft(2, '0')}';
                  final endStr =
                      '${currentEnd.hour.toString().padLeft(2, '0')}:${currentEnd.minute.toString().padLeft(2, '0')}';

                  final newConfig = config.copyWith(
                    startTime: startStr,
                    endTime: endStr,
                    gracePeriodMinutes: grace,
                  );

                  try {
                    await ref
                        .read(attendanceRepositoryProvider)
                        .updateShiftConfiguration(newConfig);
                    ref.invalidate(shiftConfigurationsProvider);

                    // Notify affected staff members whose duty is this shift or 'both'
                    try {
                      final allUsers =
                          ref.read(usersProvider).valueOrNull ?? [];
                      final affectedStaff = allUsers.where((u) =>
                          u.role == 'staff' &&
                          (u.assignedShift == config.name ||
                              u.assignedShift == 'both'));
                      for (final s in affectedStaff) {
                        await ref
                            .read(notificationRepositoryProvider)
                            .insertNotification(
                              userId: s.id,
                              title: 'Shift Timings Updated',
                              message:
                                  '${config.displayName} timings have been updated to ${newConfig.formattedTiming}.',
                              type: 'duty_assignment',
                            );
                      }
                    } catch (notifErr) {
                      debugPrint('Notification dispatch error: $notifErr');
                    }

                    if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                  } catch (e) {
                    if (dialogCtx.mounted) {
                      ScaffoldMessenger.of(dialogCtx).showSnackBar(
                        SnackBar(content: Text('Failed to update shift: $e')),
                      );
                    }
                  }
                },
                child: const Text('Save Timings'),
              ),
            ],
          );
        },
      ),
    );

    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('${config.displayName} configuration updated successfully.'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  static String _formatShiftName(String shift) {
    final s = shift.toLowerCase();
    if (s == 'both') return 'Both (Morning & Evening)';
    if (s == 'afternoon' || s == 'evening' || s == 'night') return 'Evening';
    return 'Morning';
  }

  Future<void> _confirmAndChangeShift(UserProfile user, String newShift) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime effectiveDate =
        today.add(const Duration(days: 1)); // Default: tomorrow

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final targetShiftLabel = _formatShiftName(newShift);
          final isTomorrow = effectiveDate.year == today.year &&
              effectiveDate.month == today.month &&
              effectiveDate.day == today.day + 1;

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.calendar_month_outlined,
                    color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                const Text('Schedule Shift Change'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Assign ${user.fullName} to $targetShiftLabel.',
                    style: AppTypography.bodyMd
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Current Shift: ${user.shiftDisplayName} (Active Today)',
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.onSurfaceVariant),
                  ),
                  if (user.hasScheduledShift) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.1),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusSm),
                        border: Border.all(
                            color: AppColors.secondary.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              size: 16, color: AppColors.secondary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Will replace pending scheduled shift: ${user.scheduledShiftDisplayName} effective ${DateFormat('d MMMM yyyy').format(user.shiftEffectiveDate!)}.',
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.secondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  const Divider(height: 1),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'EFFECTIVE DATE',
                    style: AppTypography.labelCaps
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      side: const BorderSide(color: AppColors.outlineVariant),
                    ),
                    leading: const Icon(Icons.event, color: AppColors.primary),
                    title: Text(
                      isTomorrow
                          ? 'Tomorrow (${DateFormat('d MMMM yyyy').format(effectiveDate)})'
                          : DateFormat('d MMMM yyyy').format(effectiveDate),
                      style: AppTypography.bodyMd
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      isTomorrow
                          ? 'Effective from next calendar day by default'
                          : 'Custom effective date selected',
                      style: AppTypography.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant, fontSize: 11),
                    ),
                    trailing: OutlinedButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: effectiveDate,
                          firstDate: today,
                          lastDate: today.add(const Duration(days: 365)),
                          helpText: 'SELECT EFFECTIVE DATE',
                        );
                        if (picked != null) {
                          setDialogState(() => effectiveDate = picked);
                        }
                      },
                      child: const Text('Change Date'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Note: Today\'s working shift (${user.shiftDisplayName}) and any existing attendance records will not be overwritten.',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogCtx, true),
                child: const Text('Confirm & Schedule Shift'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true && mounted) {
      await _executeStaffShiftUpdate(user, newShift, effectiveDate);
    }
  }

  Future<void> _executeStaffShiftUpdate(
    UserProfile user,
    String newShift,
    DateTime effectiveDate,
  ) async {
    if (_updatingStaffIds.contains(user.id)) return;
    setState(() => _updatingStaffIds.add(user.id));

    final targetShiftName = _formatShiftName(newShift);
    final formattedDate = DateFormat('d MMMM yyyy').format(effectiveDate);
    final notifMessage =
        'Your shift effective $formattedDate has been changed to $targetShiftName.';

    try {
      // 1. Save shift change to database first
      await ref.read(attendanceRepositoryProvider).updateStaffShiftAssignment(
          user.id, newShift,
          effectiveDate: effectiveDate);

      ref.invalidate(usersProvider);
      ref.invalidate(staffAssignedShiftProvider(user.id));

      // 2. Send in-app notification only after change is successfully saved
      bool notificationDelivered = false;
      try {
        await ref.read(notificationRepositoryProvider).insertNotification(
              userId: user.id,
              title: 'Duty Assignment Updated',
              message: notifMessage,
              type: 'duty_assignment',
              idempotent: true,
            );
        notificationDelivered = true;
        setState(() => _failedNotification = null);
      } catch (notifErr) {
        debugPrint('Failed to deliver duty change notification: $notifErr');
        // Do not silently claim notification was sent; record failure for safe retry
        setState(() {
          _failedNotification = {
            'user': user,
            'newShift': newShift,
            'effectiveDate': effectiveDate,
            'message': notifMessage,
            'error': notifErr.toString(),
          };
        });
      }

      if (mounted) {
        if (notificationDelivered) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${user.fullName} assigned to $targetShiftName effective $formattedDate. Notification sent.',
              ),
              backgroundColor: AppColors.primary,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Shift saved for ${user.fullName}, but notification delivery failed. Please use Retry.',
              ),
              backgroundColor: const Color(0xFFE65100),
              duration: const Duration(seconds: 6),
              action: SnackBarAction(
                label: 'Retry Notification',
                textColor: Colors.white,
                onPressed: _retryFailedNotification,
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update shift assignment: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _updatingStaffIds.remove(user.id));
      }
    }
  }

  Future<void> _retryFailedNotification() async {
    final failed = _failedNotification;
    if (failed == null || _isRetryingNotification) return;

    setState(() => _isRetryingNotification = true);
    final user = failed['user'] as UserProfile;
    final message = failed['message'] as String;

    try {
      await ref.read(notificationRepositoryProvider).insertNotification(
            userId: user.id,
            title: 'Duty Assignment Updated',
            message: message,
            type: 'duty_assignment',
            idempotent: true,
          );

      setState(() {
        _failedNotification = null;
        _isRetryingNotification = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Notification successfully sent to ${user.fullName}.'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      debugPrint(
          '[ShiftManagement ERROR] Retry notification failed for ${user.fullName}: $e');
      setState(() => _isRetryingNotification = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Unable to deliver notification to ${user.fullName}. Please retry.'),
            backgroundColor: const Color(0xFFE65100),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Retry Notification',
              textColor: Colors.white,
              onPressed: _retryFailedNotification,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 768.0;
    final configsAsync = ref.watch(shiftConfigurationsProvider);
    final usersAsync = ref.watch(usersProvider);

    return SingleChildScrollView(
      padding: EdgeInsets.all(
        isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Shift Management',
                      style: AppTypography.displayLg.copyWith(
                        color: AppColors.onBackground,
                        fontSize: isDesktop ? null : 24,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Administer Morning and Evening shift timings, grace periods, and individual staff roster assignments.',
                      style: AppTypography.bodyLg
                          .copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Section 1: Configured Shift Timings ─────────────────────────────
          Text('Shift Configurations & Working Hours',
              style: AppTypography.headlineMd),
          const SizedBox(height: AppSpacing.sm),
          configsAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (err, _) => Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.errorContainer,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Unable to load shift configurations: $err'),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        ref.invalidate(shiftConfigurationsProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
            data: (configs) {
              final morningConfig = configs.firstWhere(
                (c) => c.shift == 'morning',
                orElse: () => ShiftConfiguration.defaultMorning,
              );
              final afternoonConfig = configs.firstWhere(
                (c) => c.shift == 'afternoon' || c.shift == 'night',
                orElse: () => ShiftConfiguration.defaultAfternoon,
              );

              return isDesktop
                  ? Row(
                      children: [
                        Expanded(child: _buildConfigCard(morningConfig, true)),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                            child: _buildConfigCard(afternoonConfig, false)),
                      ],
                    )
                  : Column(
                      children: [
                        _buildConfigCard(morningConfig, true),
                        const SizedBox(height: AppSpacing.md),
                        _buildConfigCard(afternoonConfig, false),
                      ],
                    );
            },
          ),
          const SizedBox(height: AppSpacing.xl),

          // ── Section 2: Staff Shift Assignments ─────────────────────────────
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              Text('Staff Shift Assignments', style: AppTypography.headlineMd),
              // Filter segment
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(value: 'morning', label: Text('Morning')),
                    ButtonSegment(value: 'afternoon', label: Text('Evening')),
                    ButtonSegment(value: 'both', label: Text('Both')),
                  ],
                  selected: {_filterShift},
                  onSelectionChanged: (set) =>
                      setState(() => _filterShift = set.first),
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Search bar
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search staff by name or email...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (val) =>
                setState(() => _searchQuery = val.trim().toLowerCase()),
          ),
          const SizedBox(height: AppSpacing.md),

          // Staff List
          usersAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (err, _) => Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.errorContainer,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Unable to load staff users: $err'),
                  ),
                  TextButton.icon(
                    onPressed: () => ref.invalidate(usersProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
            data: (allUsers) {
              final staffUsers = allUsers.where((u) {
                if (u.role != 'staff') return false;
                if (_filterShift != 'all') {
                  final s = u.assignedShift.toLowerCase();
                  if (_filterShift == 'both' && s != 'both') {
                    return false;
                  }
                  if (_filterShift == 'morning' &&
                      s != 'morning' &&
                      s != 'both') {
                    return false;
                  }
                  if (_filterShift == 'afternoon' &&
                      s != 'afternoon' &&
                      s != 'evening' &&
                      s != 'night' &&
                      s != 'both') {
                    return false;
                  }
                }
                if (_searchQuery.isNotEmpty) {
                  final nameMatches =
                      u.fullName.toLowerCase().contains(_searchQuery);
                  final emailMatches =
                      u.email.toLowerCase().contains(_searchQuery);
                  return nameMatches || emailMatches;
                }
                return true;
              }).toList();

              if (staffUsers.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: Text(
                    'No staff members found matching criteria.',
                    style: AppTypography.bodyLg
                        .copyWith(color: AppColors.onSurfaceVariant),
                  ),
                );
              }

              return Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: staffUsers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final staff = staffUsers[index];
                    final shift = staff.assignedShift.toLowerCase();
                    final isBoth = shift == 'both';
                    final isAft = shift == 'afternoon' || shift == 'night';
                    final chipColor = isBoth
                        ? AppColors.tertiary
                        : (isAft ? AppColors.secondary : AppColors.primary);
                    final chipIcon = isBoth
                        ? Icons.schedule
                        : (isAft ? Icons.wb_twilight : Icons.wb_sunny);
                    final shiftLabel = isBoth
                        ? 'Both Duties'
                        : (isAft ? 'Evening Shift' : 'Morning Shift');

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: chipColor.withValues(alpha: 0.15),
                        child: Icon(
                          chipIcon,
                          color: chipColor,
                          size: 20,
                        ),
                      ),
                      title: Text(staff.fullName,
                          style: AppTypography.bodyMd
                              .copyWith(fontWeight: FontWeight.w600)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${staff.email}${staff.departmentName != null ? ' · ${staff.departmentName}' : ''}',
                            style: AppTypography.bodySm
                                .copyWith(color: AppColors.onSurfaceVariant),
                          ),
                          if (staff.hasScheduledShift)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Row(
                                children: [
                                  const Icon(Icons.schedule_send_outlined,
                                      size: 14, color: AppColors.secondary),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Effective ${DateFormat('d MMM yyyy').format(staff.shiftEffectiveDate!)}: ${staff.scheduledShiftDisplayName}',
                                    style: AppTypography.bodySm.copyWith(
                                      color: AppColors.secondary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: chipColor.withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusSm),
                              border: Border.all(
                                color: chipColor,
                              ),
                            ),
                            child: Text(
                              shiftLabel,
                              style: AppTypography.labelCaps.copyWith(
                                color: chipColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          if (_updatingStaffIds.contains(staff.id))
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            PopupMenuButton<String>(
                              tooltip: 'Schedule Shift Change',
                              icon: const Icon(Icons.more_vert),
                              onSelected: (newShift) =>
                                  _confirmAndChangeShift(staff, newShift),
                              itemBuilder: (ctx) => [
                                PopupMenuItem(
                                  value: 'morning',
                                  enabled: staff.assignedShift != 'morning',
                                  child: const Row(
                                    children: [
                                      Icon(Icons.wb_sunny_outlined, size: 18),
                                      SizedBox(width: 8),
                                      Text('Assign Morning Shift'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'afternoon',
                                  enabled: staff.assignedShift != 'afternoon' &&
                                      staff.assignedShift != 'evening' &&
                                      staff.assignedShift != 'night',
                                  child: const Row(
                                    children: [
                                      Icon(Icons.wb_twilight_outlined,
                                          size: 18),
                                      SizedBox(width: 8),
                                      Text('Assign Evening Shift'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'both',
                                  enabled: staff.assignedShift != 'both',
                                  child: const Row(
                                    children: [
                                      Icon(Icons.all_inclusive, size: 18),
                                      SizedBox(width: 8),
                                      Text('Assign Both (Morning & Evening)'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          const AppFooter(),
        ],
      ),
    );
  }

  Widget _buildConfigCard(ShiftConfiguration config, bool isMorning) {
    final themeColor = isMorning ? AppColors.primary : AppColors.secondary;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: themeColor.withValues(alpha: 0.3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isMorning
                        ? Icons.wb_sunny_outlined
                        : Icons.wb_twilight_outlined,
                    color: themeColor,
                    size: 24,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    config.displayName,
                    style: AppTypography.headlineMd.copyWith(color: themeColor),
                  ),
                ],
              ),
              OutlinedButton.icon(
                onPressed: () => _editShiftTimings(config),
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Edit Timings'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: themeColor,
                  side: BorderSide(color: themeColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SCHEDULED HOURS', style: AppTypography.labelCaps),
                    const SizedBox(height: 2),
                    Text(
                      config.formattedTiming,
                      style: AppTypography.headlineMd
                          .copyWith(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LATE GRACE PERIOD', style: AppTypography.labelCaps),
                    const SizedBox(height: 2),
                    Text(
                      '${config.gracePeriodMinutes} Minutes',
                      style: AppTypography.headlineMd
                          .copyWith(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
