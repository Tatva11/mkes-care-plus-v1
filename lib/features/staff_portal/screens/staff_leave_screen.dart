import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../../staff/models/leave_request.dart';
import '../../staff/providers/leave_provider.dart';

class StaffLeaveScreen extends ConsumerStatefulWidget {
  const StaffLeaveScreen({super.key});

  @override
  ConsumerState<StaffLeaveScreen> createState() => _StaffLeaveScreenState();
}

class _StaffLeaveScreenState extends ConsumerState<StaffLeaveScreen> {
  final _reasonController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest(String staffId) async {
    final messenger = ScaffoldMessenger.maybeOf(context);

    try {
      LeaveRequest.validateSubmission(
        startDate: _startDate,
        endDate: _endDate,
        reason: _reasonController.text,
      );
    } on ArgumentError catch (error) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(content: Text(error.message)),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref.read(staffLeaveRequestsProvider(staffId).notifier).createRequest(
        startDate: _startDate!,
        endDate: _endDate!,
        reason: _reasonController.text.trim(),
      );
      if (!mounted) return;
      messenger?.showSnackBar(const SnackBar(content: Text('Leave request submitted')));
      _reasonController.clear();
      setState(() {
        _startDate = null;
        _endDate = null;
      });
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final leaveAsync = ref.watch(staffLeaveRequestsProvider(currentUser.id));
    final isDesktop = MediaQuery.sizeOf(context).width >= 768.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leave Management'),
        backgroundColor: AppColors.surface,
      ),
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile),
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
                              initialDate: DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (date != null) {
                              setState(() {
                                _startDate = date;
                                if (_endDate != null && _endDate!.isBefore(date)) {
                                  _endDate = null;
                                }
                              });
                            }
                          },
                          icon: const Icon(Icons.calendar_today),
                          label: Text(_startDate != null ? DateFormat('MMM d, yyyy').format(_startDate!) : 'Start Date'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.maybeOf(context);
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _startDate ?? DateTime.now(),
                              firstDate: _startDate ?? DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (date != null) {
                              if (_startDate != null && date.isBefore(_startDate!)) {
                                if (!mounted) return;
                                messenger?.showSnackBar(
                                  const SnackBar(content: Text('End date cannot be before the start date.')),
                                );
                                return;
                              }
                              setState(() => _endDate = date);
                            }
                          },
                          icon: const Icon(Icons.calendar_today),
                          label: Text(_endDate != null ? DateFormat('MMM d, yyyy').format(_endDate!) : 'End Date'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Reason for Leave',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSubmitting ? null : () => _submitRequest(currentUser.id),
                      child: _isSubmitting ? const CircularProgressIndicator() : const Text('Submit Request'),
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
                    return Card(
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      color: AppColors.surfaceContainerLowest,
                      child: ListTile(
                        title: Text('${DateFormat('MMM d, yyyy').format(req.startDate)} - ${DateFormat('MMM d, yyyy').format(req.endDate)}'),
                        subtitle: Text(req.reason),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              req.status.toUpperCase(),
                              style: AppTypography.labelCaps.copyWith(
                                color: req.status == 'approved' ? Colors.green : (req.status == 'rejected' ? Colors.red : Colors.orange),
                              ),
                            ),
                            if (req.status == 'pending')
                              IconButton(
                                icon: const Icon(Icons.cancel, color: Colors.red),
                                onPressed: () {
                                  ref.read(staffLeaveRequestsProvider(currentUser.id).notifier).cancelRequest(req.id);
                                },
                              )
                          ],
                        ),
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
