import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../../staff/models/salary_deduction_config.dart';
import '../../staff/providers/leave_provider.dart';
import '../../staff/repositories/leave_repository.dart';

class StaffLeaveScreen extends ConsumerStatefulWidget {
  const StaffLeaveScreen({super.key});

  @override
  ConsumerState<StaffLeaveScreen> createState() => _StaffLeaveScreenState();
}

class _StaffLeaveScreenState extends ConsumerState<StaffLeaveScreen> {
  final _reasonController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  String _dutyPeriod = 'full_day'; // 'morning' | 'afternoon' | 'full_day'
  bool _isSubmitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest(String staffId) async {
    if (_startDate == null ||
        _endDate == null ||
        _reasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    if (_endDate!.isBefore(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date cannot be before start date')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(staffLeaveRequestsProvider(staffId).notifier)
          .createRequest(
            startDate: _startDate!,
            endDate: _endDate!,
            reason: _reasonController.text.trim(),
            dutyPeriod: _dutyPeriod,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Leave request submitted successfully')),
      );
      _reasonController.clear();
      setState(() {
        _startDate = null;
        _endDate = null;
        _dutyPeriod = 'full_day';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final leaveAsync = ref.watch(staffLeaveRequestsProvider(currentUser.id));
    final isDesktop = MediaQuery.sizeOf(context).width >= 768.0;

    final profileAsync = ref.watch(currentProfileProvider);
    final profile = profileAsync.valueOrNull;

    final workingDays = (_startDate != null && _endDate != null)
        ? LeaveRepository.calculateLeaveDays(_startDate!, _endDate!, dutyPeriod: _dutyPeriod)
        : 0.0;

    final salary = profile?.salary;
    final dailyRate = salary != null && salary > 0 ? salary / 30.0 : 0.0;
    final estimatedDeduction =
        SalaryDeductionConfig(dailyRate: dailyRate).calculateDeduction(workingDays);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leave Management'),
        backgroundColor: AppColors.surface,
      ),
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: EdgeInsets.all(
          isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Apply for Leave', style: AppTypography.headlineMd),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _startDate ?? DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 365)),
                            );
                            if (date != null) {
                              setState(() {
                                _startDate = date;
                                if (_endDate != null && _endDate!.isBefore(date)) {
                                  _endDate = date;
                                }
                              });
                            }
                          },
                          icon: const Icon(Icons.calendar_today),
                          label: Text(
                            _startDate != null
                                ? DateFormat('MMM d, yyyy').format(_startDate!)
                                : 'Start Date',
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final initial = _endDate ?? _startDate ?? DateTime.now();
                            final date = await showDatePicker(
                              context: context,
                              initialDate: initial,
                              firstDate: _startDate ?? DateTime.now(),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 365)),
                            );
                            if (date != null) setState(() => _endDate = date);
                          },
                          icon: const Icon(Icons.calendar_today),
                          label: Text(
                            _endDate != null
                                ? DateFormat('MMM d, yyyy').format(_endDate!)
                                : 'End Date',
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.md),
                  Text('DUTY PERIOD', style: AppTypography.labelCaps.copyWith(color: AppColors.onSurfaceVariant)),
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'full_day', label: Text('Full Day')),
                        ButtonSegment(value: 'morning', label: Text('Morning Only')),
                        ButtonSegment(value: 'afternoon', label: Text('Evening Only')),
                      ],
                      selected: {_dutyPeriod},
                      onSelectionChanged: (newSelection) {
                        setState(() => _dutyPeriod = newSelection.first);
                      },
                    ),
                  ),

                  // Live Leave Days & Salary Deduction preview
                  if (_startDate != null && _endDate != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.event_note,
                                  size: 16, color: AppColors.primaryContainer),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${workingDays.toStringAsFixed(workingDays.truncateToDouble() == workingDays ? 0 : 1)} working day(s) requested (${_dutyPeriod == 'full_day' ? 'Full Day' : _dutyPeriod == 'morning' ? 'Morning Only' : 'Evening Only'}, Sundays excluded)',
                                  style: AppTypography.bodySm.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (estimatedDeduction > 0) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.payments_outlined,
                                    size: 16, color: AppColors.error),
                                const SizedBox(width: 6),
                                Text(
                                  'Est. salary deduction if unpaid: ₹${estimatedDeduction.toStringAsFixed(2)} (@ ₹${dailyRate.toStringAsFixed(2)}/day)',
                                  style: AppTypography.bodySm.copyWith(
                                    color: AppColors.error,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Reason for Leave *',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => _submitRequest(currentUser.id),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Submit Request'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Leave History', style: AppTypography.headlineMd),
            const SizedBox(height: AppSpacing.md),
            leaveAsync.when(
              data: (requests) {
                if (requests.isEmpty) {
                  return const Text('No leave requests found.');
                }
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    final req = requests[index];
                    final isApproved = req.status == 'approved';
                    final deduction =
                        SalaryDeductionConfig(dailyRate: dailyRate)
                            .calculateDeduction(req.leaveDays);

                    Color statusColor;
                    switch (req.status) {
                      case 'approved':
                        statusColor = AppColors.primaryContainer;
                        break;
                      case 'rejected':
                        statusColor = AppColors.error;
                        break;
                      default:
                        statusColor = AppColors.secondary;
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      color: AppColors.surfaceContainerLowest,
                      child: ListTile(
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      '${DateFormat('MMM d, yyyy').format(req.startDate)} — ${DateFormat('MMM d, yyyy').format(req.endDate)}',
                                      style: AppTypography.bodyMd
                                          .copyWith(fontWeight: FontWeight.w700),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      req.dutyPeriodDisplayName,
                                      style: AppTypography.labelCaps.copyWith(
                                        fontSize: 9,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius:
                                    BorderRadius.circular(AppSpacing.radiusSm),
                              ),
                              child: Text(
                                req.status.toUpperCase(),
                                style: AppTypography.labelCaps.copyWith(
                                  color: statusColor,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${req.leaveDays.toStringAsFixed(req.leaveDays.truncateToDouble() == req.leaveDays ? 0 : 1)} working day(s) (${req.dutyPeriodDisplayName})  •  ${req.reason}',
                                style: AppTypography.bodySm.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              if (isApproved && deduction > 0) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Salary deduction: ₹${deduction.toStringAsFixed(2)}',
                                  style: AppTypography.bodySm.copyWith(
                                    color: AppColors.error,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (req.status == 'rejected' &&
                                  req.rejectionReason != null &&
                                  req.rejectionReason!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Reason: ${req.rejectionReason}',
                                  style: AppTypography.bodySm.copyWith(
                                    color: AppColors.error,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        trailing: req.status == 'pending'
                            ? IconButton(
                                icon: const Icon(Icons.cancel,
                                    color: AppColors.error),
                                tooltip: 'Cancel request',
                                onPressed: () {
                                  ref
                                      .read(staffLeaveRequestsProvider(
                                              currentUser.id)
                                          .notifier)
                                      .cancelRequest(req.id);
                                },
                              )
                            : null,
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Text('Error: $e'),
            ),
          ],
        ),
      ),
    );
  }
}
