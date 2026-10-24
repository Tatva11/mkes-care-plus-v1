import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../../staff/models/attendance_record.dart';
import '../../staff/providers/attendance_provider.dart';
import '../../staff/providers/task_provider.dart';

class StaffPerformanceScreen extends ConsumerWidget {
  const StaffPerformanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null) return const Center(child: CircularProgressIndicator());

    final tasksAsync = ref.watch(staffTasksProvider(currentUser.id));
    final attendanceAsync = ref.watch(attendanceProvider(currentUser.id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Performance'),
        backgroundColor: AppColors.surface,
      ),
      backgroundColor: AppColors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 560;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Performance Dashboard',
                  style: isMobile
                      ? AppTypography.headlineMd
                      : AppTypography.displayLg.copyWith(fontSize: 26),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Tasks Overview', style: AppTypography.headlineMd),
                const SizedBox(height: AppSpacing.md),
                tasksAsync.when(
                  data: (tasks) {
                    final completed =
                        tasks.where((t) => t.status == 'completed').length;
                    final pending = tasks
                        .where((t) =>
                            t.status != 'completed' && t.status != 'cancelled')
                        .length;
                    final overdue = tasks.where((t) => t.isOverdue).length;

                    return _buildMetricsGrid(
                      [
                        _buildMetricCard(
                            'Completed Tasks', completed.toString(), Colors.green, isMobile),
                        _buildMetricCard(
                            'Pending Tasks', pending.toString(), Colors.orange, isMobile),
                        _buildMetricCard(
                            'Overdue Tasks', overdue.toString(), Colors.red, isMobile),
                      ],
                      isMobile,
                    );
                  },
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (e, st) => Text('Error loading tasks: $e'),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('Attendance Overview (This Month)',
                    style: AppTypography.headlineMd),
                const SizedBox(height: AppSpacing.md),
                attendanceAsync.when(
                  data: (records) {
                    final dailySummaries = records.groupIntoDailySummaries();
                    final present = dailySummaries
                        .where((d) => d.dailyStatus == 'present' || d.dailyStatus == 'late')
                        .length;
                    final late = dailySummaries.where((d) => d.isLate).length;
                    final absent =
                        dailySummaries.where((d) => d.dailyStatus == 'absent').length;

                    return _buildMetricsGrid(
                      [
                        _buildMetricCard(
                            'Days Present', present.toString(), Colors.blue, isMobile),
                        _buildMetricCard(
                            'Days Late', late.toString(), Colors.orange, isMobile),
                        _buildMetricCard(
                            'Days Absent', absent.toString(), Colors.red, isMobile),
                      ],
                      isMobile,
                    );
                  },
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (e, st) => Text('Error loading attendance: $e'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetricsGrid(List<Widget> cards, bool isMobile) {
    if (isMobile) {
      return Column(
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            SizedBox(width: double.infinity, child: cards[i]),
          ],
        ],
      );
    }
    return Row(
      children: [
        for (int i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, Color color, bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? AppSpacing.sm : AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: (isMobile ? AppTypography.headlineMd : AppTypography.displayLg)
                .copyWith(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: isMobile ? 26 : 36,
            ),
          ),
          const SizedBox(height: 4),
          Text(title, style: AppTypography.labelCaps, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
