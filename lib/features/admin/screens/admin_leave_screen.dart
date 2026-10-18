import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../../admin/providers/users_provider.dart';
import '../../staff/models/leave_request.dart';
import '../../staff/models/salary_deduction_config.dart';
import '../../staff/providers/leave_provider.dart';

// ---------------------------------------------------------------------------
// AdminLeaveScreen — tabbed Leave Management for admins.
// Tab 0: Pending requests with approve / reject actions.
// Tab 1: Full leave history (all statuses).
// ---------------------------------------------------------------------------
class AdminLeaveScreen extends ConsumerStatefulWidget {
  const AdminLeaveScreen({super.key});

  @override
  ConsumerState<AdminLeaveScreen> createState() => _AdminLeaveScreenState();
}

class _AdminLeaveScreenState extends ConsumerState<AdminLeaveScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 768.0;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(
          'Leave Management',
          style: AppTypography.headlineMd.copyWith(fontSize: 20),
        ),
        elevation: 0,
        bottom: TabBar(
          controller: _tab,
          labelStyle: AppTypography.labelCaps,
          indicatorColor: AppColors.primaryContainer,
          labelColor: AppColors.primaryContainer,
          unselectedLabelColor: AppColors.onSurfaceVariant,
          tabs: const [
            Tab(text: 'PENDING REQUESTS'),
            Tab(text: 'ALL HISTORY'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _PendingTab(isDesktop: isDesktop),
          _HistoryTab(isDesktop: isDesktop),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pending Requests Tab — only 'pending' items with approve/reject actions.
// ---------------------------------------------------------------------------
class _PendingTab extends ConsumerStatefulWidget {
  const _PendingTab({required this.isDesktop});
  final bool isDesktop;

  @override
  ConsumerState<_PendingTab> createState() => _PendingTabState();
}

class _PendingTabState extends ConsumerState<_PendingTab> {
  final Set<String> _processingIds = {};

  Future<void> _handleApprove(LeaveRequest request) async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;
    if (_processingIds.contains(request.id)) return;

    setState(() => _processingIds.add(request.id));
    try {
      await ref
          .read(pendingAdminLeaveRequestsProvider.notifier)
          .approveRequest(request.id, currentUser.id);
      ref.invalidate(adminAllLeaveRequestsProvider);
      ref.invalidate(staffLeaveRequestsProvider(request.staffId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Leave request for ${request.staffName ?? "staff"} approved.'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to approve leave request: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(request.id));
      }
    }
  }

  Future<void> _handleReject(LeaveRequest request, String reason) async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;
    if (_processingIds.contains(request.id)) return;

    setState(() => _processingIds.add(request.id));
    try {
      await ref
          .read(pendingAdminLeaveRequestsProvider.notifier)
          .rejectRequest(request.id, currentUser.id, reason);
      ref.invalidate(adminAllLeaveRequestsProvider);
      ref.invalidate(staffLeaveRequestsProvider(request.staffId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Leave request for ${request.staffName ?? "staff"} rejected.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reject leave request: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(request.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingAsync = ref.watch(pendingAdminLeaveRequestsProvider);

    return pendingAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading requests: $e')),
      data: (requests) {
        if (requests.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 48,
                  color: AppColors.outline,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'No pending leave requests',
                  style: AppTypography.bodyMd
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref
              .read(pendingAdminLeaveRequestsProvider.notifier)
              .fetchPending(),
          child: ListView.separated(
            padding: EdgeInsets.all(
              widget.isDesktop
                  ? AppSpacing.marginDesktop
                  : AppSpacing.marginMobile,
            ),
            itemCount: requests.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final req = requests[index];
              final isProcessing = _processingIds.contains(req.id);
              return _LeaveCard(
                request: req,
                showActions: true,
                isProcessing: isProcessing,
                onApprove: () => _handleApprove(req),
                onReject: (reason) => _handleReject(req, reason),
              );
            },
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// All History Tab — all statuses, no actions.
// ---------------------------------------------------------------------------
class _HistoryTab extends ConsumerWidget {
  const _HistoryTab({required this.isDesktop});
  final bool isDesktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allAsync = ref.watch(adminAllLeaveRequestsProvider);

    return allAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (requests) {
        if (requests.isEmpty) {
          return Center(
            child: Text(
              'No leave records found.',
              style: AppTypography.bodyMd
                  .copyWith(color: AppColors.onSurfaceVariant),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async =>
              ref.read(adminAllLeaveRequestsProvider.notifier).fetchAll(),
          child: ListView.separated(
            padding: EdgeInsets.all(
              isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
            ),
            itemCount: requests.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) => _LeaveCard(
              request: requests[index],
              showActions: false,
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Shared card widget for one leave request.
// ---------------------------------------------------------------------------
class _LeaveCard extends ConsumerWidget {
  const _LeaveCard({
    required this.request,
    required this.showActions,
    this.isProcessing = false,
    this.onApprove,
    this.onReject,
  });

  final LeaveRequest request;
  final bool showActions;
  final bool isProcessing;
  final VoidCallback? onApprove;
  final void Function(String reason)? onReject;

  Color get _statusColor {
    switch (request.status) {
      case 'approved':
        return AppColors.primaryContainer;
      case 'rejected':
        return AppColors.error;
      case 'cancelled':
        return AppColors.onSurfaceVariant;
      default:
        return AppColors.secondary; // pending
    }
  }

  String get _statusLabel {
    switch (request.status) {
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersState = ref.watch(usersProvider);
    final staff = usersState.valueOrNull
        ?.where((u) => u.id == request.staffId)
        .firstOrNull;
    final salary = staff?.salary;
    final dailyRate = salary != null && salary > 0 ? salary / 30.0 : 0.0;
    final deduction = SalaryDeductionConfig(dailyRate: dailyRate)
        .calculateDeduction(request.leaveDays);

    final dateRange =
        '${DateFormat('MMM d, yyyy').format(request.startDate)} — ${DateFormat('MMM d, yyyy').format(request.endDate)}';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.outlineVariant),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: staff name + status badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar initials
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    (request.staffName ?? 'S')
                        .split(' ')
                        .map((w) => w.isNotEmpty ? w[0] : '')
                        .take(2)
                        .join()
                        .toUpperCase(),
                    style: AppTypography.labelCaps.copyWith(
                      color: AppColors.primaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.staffName ?? 'Staff Member',
                      style: AppTypography.bodyMd
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    Row(
                      children: [
                        Text(
                          '${request.leaveDays.toStringAsFixed(request.leaveDays.truncateToDouble() == request.leaveDays ? 0 : 1)} working day(s)',
                          style: AppTypography.bodySm
                              .copyWith(color: AppColors.onSurfaceVariant),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            request.dutyPeriodDisplayName,
                            style: AppTypography.labelCaps.copyWith(
                              fontSize: 9,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Status badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(
                      color: _statusColor.withValues(alpha: 0.4), width: 1),
                ),
                child: Text(
                  _statusLabel,
                  style: AppTypography.labelCaps.copyWith(
                    color: _statusColor,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.sm),

          // Date range
          Row(
            children: [
              const Icon(Icons.date_range_outlined,
                  size: 16, color: AppColors.outline),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  dateRange,
                  style: AppTypography.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Reason
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.notes_outlined,
                  size: 16, color: AppColors.outline),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  request.reason,
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
              ),
            ],
          ),

          // Salary deduction integration
          if (deduction > 0) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.payments_outlined,
                    size: 16, color: AppColors.error),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    request.status == 'approved'
                        ? 'Salary deduction: ₹${deduction.toStringAsFixed(2)} (${request.leaveDays.toStringAsFixed(0)} days @ ₹${dailyRate.toStringAsFixed(2)}/day)'
                        : 'Est. salary deduction if unpaid: ₹${deduction.toStringAsFixed(2)} (@ ₹${dailyRate.toStringAsFixed(2)}/day)',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],

          // Rejection reason (if rejected)
          if (request.status == 'rejected' &&
              request.rejectionReason != null &&
              request.rejectionReason!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    size: 16, color: AppColors.error),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Rejection reason: ${request.rejectionReason}',
                    style: AppTypography.bodySm.copyWith(
                        color: AppColors.error.withValues(alpha: 0.8)),
                  ),
                ),
              ],
            ),
          ],

          // Action buttons (pending only)
          if (showActions && request.status == 'pending') ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  icon:
                      const Icon(Icons.close, size: 18, color: AppColors.error),
                  label: Text(
                    'Reject',
                    style: AppTypography.labelCaps
                        .copyWith(color: AppColors.error),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.error),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  onPressed:
                      isProcessing ? null : () => _showRejectDialog(context),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  icon: isProcessing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: Text('Approve',
                      style: AppTypography.labelCaps
                          .copyWith(color: Colors.white)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryContainer,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  onPressed: isProcessing ? null : onApprove,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showRejectDialog(BuildContext context) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Leave Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Please provide a reason for rejection.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              final reason = reasonCtrl.text.trim();
              if (reason.isEmpty) return;
              Navigator.of(ctx).pop();
              onReject?.call(reason);
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }
}
