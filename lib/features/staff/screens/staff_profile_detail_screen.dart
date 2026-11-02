import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../admin/models/user_profile.dart';
import '../../admin/providers/users_provider.dart';
import '../../admin/screens/user_form_dialog.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/salary_deduction_config.dart';
import '../models/task_item.dart';
import '../providers/attendance_provider.dart';
import '../providers/leave_provider.dart';
import '../providers/task_provider.dart';

class StaffProfileDetailScreen extends ConsumerStatefulWidget {
  const StaffProfileDetailScreen({super.key, required this.user});

  final UserProfile user;

  @override
  ConsumerState<StaffProfileDetailScreen> createState() =>
      _StaffProfileDetailScreenState();
}

class _StaffProfileDetailScreenState
    extends ConsumerState<StaffProfileDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isBypassLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  UserProfile _resolveUser() {
    final usersState = ref.watch(usersProvider);
    final current = usersState.valueOrNull
        ?.where((u) => u.id == widget.user.id)
        .firstOrNull;
    return current ?? widget.user;
  }

  void _openEditDialog(UserProfile user) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => UserFormDialog(user: user),
    );
  }

  Future<void> _toggleStatus(UserProfile user) async {
    final newStatus = !user.isActive;
    final action = newStatus ? 'activate' : 'deactivate';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${action[0].toUpperCase()}${action.substring(1)} Staff'),
        content: Text(
          'Are you sure you want to $action ${user.fullName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  newStatus ? AppColors.primaryContainer : AppColors.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action[0].toUpperCase() + action.substring(1)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref
            .read(usersProvider.notifier)
            .toggleStatus(user.id, newStatus);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Staff member ${action}d successfully.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  void _openCreateTaskDialog(UserProfile user) {
    final currentAdmin = ref.read(currentUserProvider);
    if (currentAdmin == null) return;

    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String priority = 'medium';
    DateTime? dueDate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text('Assign Task to ${user.fullName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Task Title *'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                    DropdownMenuItem(value: 'critical', child: Text('Critical')),
                  ],
                  onChanged: (val) {
                    if (val != null) setModalState(() => priority = val);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(
                    dueDate != null
                        ? DateFormat('MMM d, yyyy').format(dueDate!)
                        : 'Select Due Date (Optional)',
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setModalState(() => dueDate = picked);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;

                try {
                  await ref.read(adminTasksProvider.notifier).createTask(
                        title: title,
                        description: descCtrl.text.trim().isEmpty
                            ? null
                            : descCtrl.text.trim(),
                        assignedTo: user.id,
                        adminId: currentAdmin.id,
                        dueDate: dueDate,
                        priority: priority,
                      );
                  // Refresh staff tasks notifier too
                  ref
                      .read(staffTasksProvider(user.id).notifier)
                      .fetchTasks();
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showGrantBypassDialog(UserProfile user) async {
    int selectedDuration = 4; // default 4 hours
    final reasonCtrl = TextEditingController();
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.location_off, color: Colors.orange),
              SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text('Temporarily Disable GPS Restriction'),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Grant temporary GPS bypass for ${user.fullName}?',
                  style: AppTypography.headlineMd.copyWith(fontSize: 16),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'This will allow ${user.fullName} to sign in and access clinical data remotely without physical presence inside the 200-metre clinic radius. Other staff will remain geofenced.',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Bypass Duration *',
                  style: AppTypography.labelCaps.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: 8,
                  children: [1, 4, 8, 24].map((hours) {
                    final isSelected = selectedDuration == hours;
                    return ChoiceChip(
                      label: Text('$hours ${hours == 1 ? "Hour" : "Hours"}'),
                      selected: isSelected,
                      onSelected: isSubmitting
                          ? null
                          : (selected) {
                              if (selected) {
                                setModalState(() {
                                  selectedDuration = hours;
                                });
                              }
                            },
                      selectedColor: AppColors.primaryContainer,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppColors.onSurface,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: reasonCtrl,
                  enabled: !isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'Reason (Optional)',
                    hintText: 'e.g., remote shift, off-site outreach',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  isSubmitting ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade800,
                foregroundColor: Colors.white,
              ),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      setModalState(() {
                        isSubmitting = true;
                      });
                      setState(() {
                        _isBypassLoading = true;
                      });
                      try {
                        await ref
                            .read(usersProvider.notifier)
                            .grantGpsBypass(
                              staffId: user.id,
                              durationHours: selectedDuration,
                              reason: reasonCtrl.text.trim().isNotEmpty
                                  ? reasonCtrl.text.trim()
                                  : null,
                            );
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop();
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'GPS restriction disabled for ${user.fullName} for $selectedDuration ${selectedDuration == 1 ? "hour" : "hours"}.',
                              ),
                              backgroundColor: Colors.green.shade700,
                            ),
                          );
                        }
                      } catch (e) {
                        setModalState(() {
                          isSubmitting = false;
                        });
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to grant GPS bypass: $e'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() {
                            _isBypassLoading = false;
                          });
                        }
                      }
                    },
              icon: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.check, size: 18),
              label: Text(
                isSubmitting ? 'Granting...' : 'Confirm & Disable GPS',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRevokeBypassDialog(UserProfile user) async {
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.location_on, color: AppColors.primary),
              SizedBox(width: AppSpacing.xs),
              Expanded(child: Text('Enable GPS Restriction')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Restore 200m GPS restriction for ${user.fullName}?',
                style: AppTypography.headlineMd.copyWith(fontSize: 16),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'This will immediately revoke the active GPS bypass and terminate any remote access. ${user.fullName} will be required to be within 200 metres of the clinic to access protected clinical data.',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed:
                  isSubmitting ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
              ),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      setModalState(() {
                        isSubmitting = true;
                      });
                      setState(() {
                        _isBypassLoading = true;
                      });
                      try {
                        await ref
                            .read(usersProvider.notifier)
                            .revokeGpsBypass(
                              staffId: user.id,
                              reason: 'Revoked by administrator',
                            );
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop();
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'GPS restriction restored for ${user.fullName}. Normal 200m geofence is now enforced.',
                              ),
                              backgroundColor: Colors.green.shade700,
                            ),
                          );
                        }
                      } catch (e) {
                        setModalState(() {
                          isSubmitting = false;
                        });
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to revoke GPS bypass: $e'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() {
                            _isBypassLoading = false;
                          });
                        }
                      }
                    },
              icon: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.lock, size: 18),
              label: Text(
                isSubmitting ? 'Restoring...' : 'Enable GPS Restriction',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGpsGeofenceCard(UserProfile user) {
    final isBypassActive = user.isGpsBypassActive;
    final bypassUntil = user.gpsBypassUntil;

    String expiryText = '';
    if (isBypassActive && bypassUntil != null) {
      final remaining = bypassUntil.difference(DateTime.now());
      final hours = remaining.inHours;
      final mins = remaining.inMinutes % 60;
      final remainingStr = hours > 0
          ? '${hours}h ${mins}m remaining'
          : '${mins}m remaining';
      final formattedTime =
          DateFormat('MMM d, yyyy • h:mm a').format(bypassUntil);
      expiryText = '$formattedTime ($remainingStr)';
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isBypassActive
            ? const Color(0xFFFFF8E1)
            : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: isBypassActive
              ? Colors.orange.shade300
              : AppColors.outlineVariant,
          width: isBypassActive ? 1.5 : 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isBypassActive
                      ? Colors.orange.shade100
                      : AppColors.primaryContainer.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isBypassActive ? Icons.location_off : Icons.near_me,
                  color: isBypassActive
                      ? Colors.orange.shade800
                      : AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GPS Geofence Restriction',
                      style: AppTypography.headlineMd.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Clinic radius: 200 metres',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isBypassActive
                        ? Colors.orange.shade800
                        : AppColors.primaryContainer.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isBypassActive ? Icons.lock_open : Icons.lock_outline,
                        size: 14,
                        color: isBypassActive
                            ? Colors.white
                            : AppColors.primaryContainer,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          isBypassActive ? 'BYPASS ACTIVE' : '200M ENFORCED',
                          style: AppTypography.labelCaps.copyWith(
                            color: isBypassActive
                                ? Colors.white
                                : AppColors.primaryContainer,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1, color: AppColors.outlineVariant),
          const SizedBox(height: AppSpacing.md),
          if (isBypassActive) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.timer_outlined,
                    size: 18, color: Colors.orange),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bypass Expiry Date/Time',
                        style: AppTypography.labelCaps.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        expiryText,
                        style: AppTypography.bodyMd.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                      ),
                      if (user.gpsBypassReason != null &&
                          user.gpsBypassReason!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Reason: ${user.gpsBypassReason}',
                          style: AppTypography.bodySm.copyWith(
                            fontStyle: FontStyle.italic,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              icon: _isBypassLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.lock_rounded, size: 18),
              label: Text(_isBypassLoading
                  ? 'Processing...'
                  : 'Enable GPS Restriction'),
              onPressed: _isBypassLoading
                  ? null
                  : () => _showRevokeBypassDialog(user),
            ),
          ] else ...[
            Text(
              'This staff account is currently subject to the 200m clinic geofence restriction. Staff must be physically near the clinic to access protected clinical data.',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange.shade800,
                side: BorderSide(color: Colors.orange.shade400),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              icon: _isBypassLoading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.orange.shade800),
                      ),
                    )
                  : const Icon(Icons.location_off, size: 18),
              label: Text(_isBypassLoading
                  ? 'Processing...'
                  : 'Temporarily Disable GPS Restriction'),
              onPressed: _isBypassLoading
                  ? null
                  : () => _showGrantBypassDialog(user),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _resolveUser();
    final isDesktop = MediaQuery.sizeOf(context).width >= 768.0;

    final initials = user.fullName
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();

    final monthlySalary = user.salary;
    final dailyRate =
        monthlySalary != null && monthlySalary > 0 ? monthlySalary / 30.0 : 0.0;
    final deductionConfig = SalaryDeductionConfig(dailyRate: dailyRate);

    return Scaffold(
      appBar: AppBar(
        title: Text(user.fullName, overflow: TextOverflow.ellipsis),
        actions: isDesktop
            ? [
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit Profile'),
                  onPressed: () => _openEditDialog(user),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.tonalIcon(
                  icon: Icon(
                    user.isActive
                        ? Icons.person_off_outlined
                        : Icons.person_outline,
                    size: 18,
                  ),
                  label: Text(user.isActive ? 'Deactivate' : 'Activate'),
                  style: FilledButton.styleFrom(
                    foregroundColor:
                        user.isActive ? AppColors.error : AppColors.primary,
                  ),
                  onPressed: () => _toggleStatus(user),
                ),
                const SizedBox(width: AppSpacing.md),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit Profile',
                  onPressed: () => _openEditDialog(user),
                ),
                IconButton(
                  icon: Icon(
                    user.isActive
                        ? Icons.person_off_outlined
                        : Icons.person_outline,
                  ),
                  tooltip: user.isActive ? 'Deactivate' : 'Activate',
                  color: user.isActive ? AppColors.error : AppColors.primary,
                  onPressed: () => _toggleStatus(user),
                ),
              ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(
          isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top Summary Header Card ──
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                border: Border.all(color: AppColors.outlineVariant),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor:
                        AppColors.primaryContainer.withValues(alpha: 0.15),
                    child: Text(
                      initials,
                      style: AppTypography.headlineMd.copyWith(
                        color: AppColors.primaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                user.fullName,
                                style: AppTypography.headlineMd,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: user.isActive
                                    ? AppColors.primaryContainer
                                        .withValues(alpha: 0.15)
                                    : AppColors.error.withValues(alpha: 0.15),
                                borderRadius:
                                    BorderRadius.circular(AppSpacing.radiusSm),
                              ),
                              child: Text(
                                user.isActive ? 'Active' : 'Inactive',
                                style: AppTypography.labelCaps.copyWith(
                                  color: user.isActive
                                      ? AppColors.primaryContainer
                                      : AppColors.error,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${user.designation ?? 'Staff Member'} • ${user.departmentName ?? user.department ?? 'Unassigned Department'}',
                          style: AppTypography.bodyMd.copyWith(
                            color: AppColors.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.md,
                          runSpacing: AppSpacing.xs,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.email_outlined,
                                    size: 16, color: AppColors.outline),
                                const SizedBox(width: 4),
                                Text(user.email, style: AppTypography.bodySm),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.phone_outlined,
                                    size: 16, color: AppColors.outline),
                                const SizedBox(width: 4),
                                Text(
                                  user.phoneNumber ?? 'No phone provided',
                                  style: AppTypography.bodySm,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // ── Employment & Salary Metrics Grid ──
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 600;
                final items = [
                  _InfoCard(
                    icon: Icons.business_outlined,
                    label: 'Department',
                    value: user.departmentName ??
                        user.department ??
                        'Unassigned',
                  ),
                  _InfoCard(
                    icon: Icons.badge_outlined,
                    label: 'Designation',
                    value: user.designation ?? 'Not specified',
                  ),
                  _InfoCard(
                    icon: Icons.event_available_outlined,
                    label: 'Joining Date',
                    value: user.joiningDate != null
                        ? DateFormat('MMMM d, yyyy').format(user.joiningDate!)
                        : 'Not recorded',
                  ),
                  _InfoCard(
                    icon: Icons.payments_outlined,
                    label: 'Monthly Salary',
                    value: monthlySalary != null
                        ? '₹${monthlySalary.toStringAsFixed(2)}'
                        : 'Not configured',
                    subValue: dailyRate > 0
                        ? 'Est. daily rate: ₹${dailyRate.toStringAsFixed(2)}'
                        : null,
                    valueColor: AppColors.primaryContainer,
                  ),
                ];

                if (isWide) {
                  return Row(
                    children: items
                        .map(
                          (item) => Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4.0),
                              child: item,
                            ),
                          ),
                        )
                        .toList(),
                  );
                }
                return Column(
                  children: items
                      .map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: item,
                        ),
                      )
                      .toList(),
                );
              },
            ),

            if (user.role.toLowerCase() != 'admin') ...[
              const SizedBox(height: AppSpacing.md),
              _buildGpsGeofenceCard(user),
            ],

            const SizedBox(height: AppSpacing.lg),

            // ── Tabs for Tasks, Attendance, Leave ──
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.outlineVariant),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: AppColors.primaryContainer,
                labelColor: AppColors.primaryContainer,
                unselectedLabelColor: AppColors.onSurfaceVariant,
                tabs: const [
                  Tab(icon: Icon(Icons.assignment_outlined), text: 'Tasks'),
                  Tab(icon: Icon(Icons.history_outlined), text: 'Attendance'),
                  Tab(icon: Icon(Icons.beach_access_outlined), text: 'Leave History'),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            SizedBox(
              height: 480,
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Tasks
                  _StaffTasksTab(
                    staffId: user.id,
                    onAssignTask: () => _openCreateTaskDialog(user),
                  ),

                  // Tab 2: Attendance
                  _StaffAttendanceTab(staffId: user.id),

                  // Tab 3: Leave History & Deductions
                  _StaffLeaveTab(
                    staffId: user.id,
                    deductionConfig: deductionConfig,
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

// ─────────────────────────────────────────────────────────────────────────────
// Information Card Widget
// ─────────────────────────────────────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
    this.subValue,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subValue;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
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
              Icon(icon, size: 16, color: AppColors.outline),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: AppTypography.labelCaps.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTypography.bodyMd.copyWith(
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppColors.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          if (subValue != null) ...[
            const SizedBox(height: 2),
            Text(
              subValue!,
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 1: Staff Tasks Tab
// ─────────────────────────────────────────────────────────────────────────────
class _StaffTasksTab extends ConsumerWidget {
  const _StaffTasksTab({
    required this.staffId,
    required this.onAssignTask,
  });

  final String staffId;
  final VoidCallback onAssignTask;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(staffTasksProvider(staffId));

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Assigned Tasks', style: AppTypography.headlineMd),
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Assign Task'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryContainer,
              ),
              onPressed: onAssignTask,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: tasksAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error loading tasks: $e')),
            data: (tasks) {
              if (tasks.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.task_alt,
                          size: 40, color: AppColors.outline),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'No tasks assigned to this staff member.',
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }

              final completed =
                  tasks.where((t) => t.status == 'completed').length;
              final overdue = tasks.where((t) => t.isOverdue).length;
              final pending = tasks.length - completed;

              return Column(
                children: [
                  // Task counters
                  Row(
                    children: [
                      _StatChip(label: 'Total', count: tasks.length),
                      _StatChip(
                          label: 'Pending',
                          count: pending,
                          color: AppColors.secondary),
                      _StatChip(
                          label: 'Completed',
                          count: completed,
                          color: AppColors.primaryContainer),
                      _StatChip(
                          label: 'Overdue',
                          count: overdue,
                          color: AppColors.error),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Expanded(
                    child: ListView.separated(
                      itemCount: tasks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        return _TaskTile(task: task);
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.count,
    this.color,
  });

  final String label;
  final int count;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (color ?? AppColors.outline).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        '$label: $count',
        style: AppTypography.labelCaps.copyWith(
          color: color ?? AppColors.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});

  final TaskItem task;

  Color get _priorityColor {
    switch (task.priority.toLowerCase()) {
      case 'critical':
        return AppColors.error;
      case 'high':
        return AppColors.secondary;
      case 'medium':
        return AppColors.primary;
      default:
        return AppColors.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDone = task.status == 'completed';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: task.isOverdue
              ? AppColors.error.withValues(alpha: 0.5)
              : AppColors.outlineVariant,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isDone ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isDone ? AppColors.primaryContainer : AppColors.outline,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: AppTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration:
                        isDone ? TextDecoration.lineThrough : TextDecoration.none,
                  ),
                ),
                if (task.description != null &&
                    task.description!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    task.description!,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _priorityColor.withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                      child: Text(
                        task.priority.toUpperCase(),
                        style: AppTypography.labelCaps.copyWith(
                          color: _priorityColor,
                          fontSize: 9,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (task.dueDate != null)
                      Text(
                        'Due: ${DateFormat('MMM d, yyyy').format(task.dueDate!)}',
                        style: AppTypography.bodySm.copyWith(
                          color: task.isOverdue
                              ? AppColors.error
                              : AppColors.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: task.isOverdue
                              ? FontWeight.w700
                              : FontWeight.normal,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isDone
                  ? AppColors.primaryContainer.withValues(alpha: 0.12)
                  : AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Text(
              task.statusLabel,
              style: AppTypography.labelCaps.copyWith(
                color: isDone
                    ? AppColors.primaryContainer
                    : AppColors.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 2: Staff Attendance Tab
// ─────────────────────────────────────────────────────────────────────────────
class _StaffAttendanceTab extends ConsumerWidget {
  const _StaffAttendanceTab({required this.staffId});

  final String staffId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceAsync = ref.watch(attendanceProvider(staffId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Monthly Attendance History', style: AppTypography.headlineMd),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: attendanceAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text('Error loading attendance: $e')),
            data: (records) {
              if (records.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.history_toggle_off,
                          size: 40, color: AppColors.outline),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'No attendance records found for this period.',
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                itemCount: records.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final rec = records[index];
                  final checkInStr = rec.checkInTime != null
                      ? DateFormat('hh:mm a').format(rec.checkInTime!)
                      : '—';
                  final checkOutStr = rec.checkOutTime != null
                      ? DateFormat('hh:mm a').format(rec.checkOutTime!)
                      : '—';

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(color: AppColors.outlineVariant),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('EEEE, MMM d, yyyy')
                                  .format(rec.recordDate),
                              style: AppTypography.bodyMd.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'In: $checkInStr  •  Out: $checkOutStr  •  Hours: ${rec.workingHours != null ? "${rec.workingHours!.toStringAsFixed(1)} hrs" : "—"}',
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _statusColor(rec.status)
                                .withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                          ),
                          child: Text(
                            rec.statusLabel,
                            style: AppTypography.labelCaps.copyWith(
                              color: _statusColor(rec.status),
                              fontSize: 11,
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
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return AppColors.primaryContainer;
      case 'late':
        return AppColors.secondary;
      case 'absent':
        return AppColors.error;
      case 'leave':
        return AppColors.tertiary;
      default:
        return AppColors.outline;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 3: Staff Leave Tab with Salary Deduction Integration
// ─────────────────────────────────────────────────────────────────────────────
class _StaffLeaveTab extends ConsumerWidget {
  const _StaffLeaveTab({
    required this.staffId,
    required this.deductionConfig,
  });

  final String staffId;
  final SalaryDeductionConfig deductionConfig;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaveAsync = ref.watch(staffLeaveRequestsProvider(staffId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Leave History & Deductions', style: AppTypography.headlineMd),
            if (deductionConfig.dailyRate > 0)
              Text(
                'Rate: ₹${deductionConfig.dailyRate.toStringAsFixed(2)}/day',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: leaveAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error loading leave: $e')),
            data: (requests) {
              if (requests.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.beach_access_outlined,
                          size: 40, color: AppColors.outline),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'No leave requests found.',
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                itemCount: requests.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final req = requests[index];
                  final isApproved = req.status == 'approved';
                  final deduction =
                      deductionConfig.calculateDeduction(req.leaveDays);

                  return Container(
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${DateFormat('MMM d, yyyy').format(req.startDate)} - ${DateFormat('MMM d, yyyy').format(req.endDate)}',
                              style: AppTypography.bodyMd.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _leaveStatusColor(req.status)
                                    .withValues(alpha: 0.12),
                                borderRadius:
                                    BorderRadius.circular(AppSpacing.radiusSm),
                              ),
                              child: Text(
                                req.status.toUpperCase(),
                                style: AppTypography.labelCaps.copyWith(
                                  color: _leaveStatusColor(req.status),
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${req.leaveDays.toStringAsFixed(0)} working day(s)  •  Reason: ${req.reason}',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        if (isApproved && deduction > 0) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.08),
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusSm),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.money_off,
                                    size: 14, color: AppColors.error),
                                const SizedBox(width: 4),
                                Text(
                                  'Salary deduction: ₹${deduction.toStringAsFixed(2)} (${req.leaveDays.toStringAsFixed(0)} days @ ₹${deductionConfig.dailyRate.toStringAsFixed(2)}/day)',
                                  style: AppTypography.bodySm.copyWith(
                                    color: AppColors.error,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (req.status == 'rejected' &&
                            req.rejectionReason != null &&
                            req.rejectionReason!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Rejection Reason: ${req.rejectionReason}',
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.error,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Color _leaveStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return AppColors.primaryContainer;
      case 'rejected':
        return AppColors.error;
      case 'pending':
        return AppColors.secondary;
      default:
        return AppColors.outline;
    }
  }
}
