import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../admin/providers/users_provider.dart';
import '../../staff/providers/attendance_provider.dart';

class AdminAttendanceScreen extends ConsumerWidget {
  const AdminAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const AdminPerformanceScreen();
  }
}

class AdminPerformanceScreen extends ConsumerStatefulWidget {
  const AdminPerformanceScreen({super.key});

  @override
  ConsumerState<AdminPerformanceScreen> createState() => _AdminPerformanceScreenState();
}

class _AdminPerformanceScreenState extends ConsumerState<AdminPerformanceScreen> {
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final usersState = ref.watch(usersProvider);
    final users = (usersState.valueOrNull ?? const [])
        .where((user) => user.role == 'staff' && user.isActive)
        .toList();
    final attendanceAsync = ref.watch(adminAttendanceForDateProvider(_selectedDate));
    final summaryAsync = ref.watch(adminAttendanceSummaryProvider(_selectedDate));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Management'),
        actions: [
          IconButton(
            tooltip: 'Select date',
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2024),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setState(() => _selectedDate = picked);
              }
            },
            icon: const Icon(Icons.calendar_today_outlined),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Staff Attendance - ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                    style: AppTypography.headlineMd,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            summaryAsync.when(
              data: (summary) {
                final totalStaff = users.length;
                return Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _SummaryChip(label: 'Total', value: '$totalStaff'),
                    _SummaryChip(label: 'Present', value: '${summary['present'] ?? 0}', color: AppColors.primaryContainer),
                    _SummaryChip(label: 'Late', value: '${summary['late'] ?? 0}', color: AppColors.secondary),
                    _SummaryChip(label: 'Absent', value: '${summary['absent'] ?? 0}', color: AppColors.error),
                    _SummaryChip(label: 'Leave', value: '${summary['leave'] ?? 0}', color: AppColors.tertiary),
                  ],
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (e, st) => const SizedBox.shrink(),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: attendanceAsync.when(
                data: (records) {
                  if (records.isEmpty) {
                    return const Center(
                      child: Text('No attendance records found for this date.'),
                    );
                  }

                  final staffMap = {
                    for (final user in users) user.id: user,
                  };

                  final rows = records.map((record) {
                    final staff = staffMap[record.staffId];
                    final name = staff?.fullName ?? record.staffName ?? 'Unknown staff';
                    final statusColor = _statusColor(record.status);
                    return Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: AppTypography.headlineMd),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  staff?.designation ?? 'Staff member',
                                  style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                                decoration: BoxDecoration(
                                  color: statusColor.withAlpha(40),
                                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                                ),
                                child: Text(
                                  record.statusLabel,
                                  style: AppTypography.labelCaps.copyWith(color: statusColor),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                record.checkInTime == null
                                    ? 'No check-in'
                                    : '${record.checkInTime!.hour.toString().padLeft(2, '0')}:${record.checkInTime!.minute.toString().padLeft(2, '0')}',
                                style: AppTypography.bodySm,
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList();

                  return ListView(children: rows);
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(
                  child: Text('Unable to load attendance: $e'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    final normalized = status.toLowerCase();
    switch (normalized) {
      case 'present':
        return AppColors.primaryContainer;
      case 'late':
        return AppColors.secondary;
      case 'absent':
        return AppColors.error;
      case 'leave':
        return AppColors.tertiary;
      case 'holiday':
        return AppColors.outline;
      default:
        return AppColors.onSurfaceVariant;
    }
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppColors.surfaceContainerLow;
    return Container(
      margin: const EdgeInsets.only(right: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: AppTypography.labelCaps),
          Text(value, style: AppTypography.labelCaps.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
