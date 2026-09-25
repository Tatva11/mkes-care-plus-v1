import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../../staff/providers/leave_provider.dart';

class AdminLeaveScreen extends ConsumerWidget {
  const AdminLeaveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingAdminLeaveRequestsProvider);
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Leave Requests (Admin)')),
      body: pendingAsync.when(
        data: (requests) {
          if (requests.isEmpty) {
            return const Center(child: Text('No pending leave requests.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final req = requests[index];
              final isPending = req.status.toLowerCase() == 'pending';
              final staffName = req.staffName ?? 'Unknown staff';

              return Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Staff: $staffName',
                              style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                            decoration: BoxDecoration(
                              color: req.status == 'approved'
                                  ? Colors.green.withValues(alpha: 0.12)
                                  : req.status == 'rejected'
                                      ? Colors.red.withValues(alpha: 0.12)
                                      : Colors.orange.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                            ),
                            child: Text(
                              req.statusLabel,
                              style: AppTypography.labelCaps.copyWith(
                                color: req.status == 'approved'
                                    ? Colors.green.shade700
                                    : req.status == 'rejected'
                                        ? Colors.red.shade700
                                        : Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Dates: ${DateFormat('MMM d, yyyy').format(req.startDate)} - ${DateFormat('MMM d, yyyy').format(req.endDate)} (${req.leaveDays.toStringAsFixed(req.leaveDays % 1 == 0 ? 0 : 1)} days)',
                      ),
                      const SizedBox(height: 4),
                      Text('Reason: ${req.reason}'),
                      if (req.rejectionReason != null && req.rejectionReason!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Rejection reason: ${req.rejectionReason!}'),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      if (isPending)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: currentUser == null
                                  ? null
                                  : () {
                                      ref.read(pendingAdminLeaveRequestsProvider.notifier).rejectRequest(
                                        req.id,
                                        currentUser.id,
                                        'Rejected by admin',
                                      );
                                    },
                              child: const Text('Reject', style: TextStyle(color: AppColors.error)),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            FilledButton(
                              onPressed: currentUser == null
                                  ? null
                                  : () {
                                      ref.read(pendingAdminLeaveRequestsProvider.notifier).approveRequest(
                                        req.id,
                                        currentUser.id,
                                      );
                                    },
                              child: const Text('Approve'),
                            ),
                          ],
                        )
                      else
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Reviewed',
                            style: AppTypography.labelCaps.copyWith(color: AppColors.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
