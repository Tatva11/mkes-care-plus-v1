import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_boundaries.dart';
import '../../inventory/models/inventory_item.dart';
import '../../inventory/providers/inventory_provider.dart';
import '../../patients/providers/patients_provider.dart';
import '../../reports/screens/admin_reports_screen.dart';
import '../../staff/providers/attendance_provider.dart';
import '../../staff/providers/task_provider.dart';

/// Live Copilot Insights Card grounded strictly in today's live operational data:
/// patient schedule, inventory alerts, staff attendance, and today's tasks.
/// Fabricated static insights and fake metrics are completely removed.
class CopilotInsightsCard extends ConsumerStatefulWidget {
  const CopilotInsightsCard({
    super.key,
    this.onViewFullAnalysis,
  });

  /// Optional navigation callback for "View Full Analysis".
  /// Defaults to navigating to [AdminReportsScreen].
  final VoidCallback? onViewFullAnalysis;

  @override
  ConsumerState<CopilotInsightsCard> createState() =>
      _CopilotInsightsCardState();
}

class _CopilotInsightsCardState extends ConsumerState<CopilotInsightsCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _navigateToReports() {
    if (widget.onViewFullAnalysis != null) {
      widget.onViewFullAnalysis!();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const AdminReportsScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateBoundaries.startOfDay(now);

    final scheduledAsync = ref.watch(todayScheduledPatientsProvider);
    final inventoryAsync = ref.watch(inventoryProvider);
    final tasksAsync = ref.watch(adminTasksProvider);
    final attendanceAsync = ref.watch(adminAttendanceForDateProvider(today));

    // Synthesize live operational insights from today's real data
    final List<_InsightData> liveInsights = [];

    // 1. Critical inventory alerts needing attention today
    final inventory = inventoryAsync.valueOrNull ?? [];
    final criticalInventory = inventory.where((item) {
      return item.isLowStock ||
          item.expiryStatus == ExpiryStatus.expiringSoon ||
          item.expiryStatus == ExpiryStatus.expired;
    }).toList();

    if (criticalInventory.isNotEmpty) {
      final expiredCount = criticalInventory
          .where((i) => i.expiryStatus == ExpiryStatus.expired)
          .length;
      final lowStockCount = criticalInventory.where((i) => i.isLowStock).length;

      if (expiredCount > 0) {
        liveInsights.add(
          _InsightData(
            borderColor: AppColors.error,
            text:
                '$expiredCount inventory item(s) are expired and require replacement today.',
            highlight: '$expiredCount expired',
            highlightColor: AppColors.error,
          ),
        );
      } else if (lowStockCount > 0) {
        liveInsights.add(
          _InsightData(
            borderColor: AppColors.secondary,
            text:
                '$lowStockCount item(s) are below threshold stock. Check procurement reorders.',
            highlight: '$lowStockCount low stock',
            highlightColor: AppColors.secondary,
          ),
        );
      }
    }

    // 2. Today's task deadlines and overdue items
    final tasks = tasksAsync.valueOrNull ?? [];
    final todayTasks = tasks.where((t) {
      if (t.dueDate == null) return false;
      return DateBoundaries.isToday(t.dueDate!);
    }).toList();

    final overdueToday = todayTasks.where((t) {
      final s = t.status.toLowerCase();
      if (s == 'completed' || s == 'cancelled') return false;
      if (s == 'overdue') return true;
      return t.dueDate != null && t.dueDate!.isBefore(now);
    }).length;

    if (overdueToday > 0) {
      liveInsights.add(
        _InsightData(
          borderColor: AppColors.error,
          text:
              '$overdueToday scheduled task(s) are overdue today. Follow up with assigned staff.',
          highlight: '$overdueToday overdue',
          highlightColor: AppColors.error,
        ),
      );
    } else if (todayTasks.isNotEmpty) {
      final pendingCount = todayTasks
          .where((t) =>
              t.status.toLowerCase() != 'completed' &&
              t.status.toLowerCase() != 'cancelled')
          .length;
      if (pendingCount > 0) {
        liveInsights.add(
          _InsightData(
            borderColor: AppColors.primaryContainer,
            text:
                '$pendingCount task(s) scheduled for completion today across departments.',
            highlight: '$pendingCount scheduled',
          ),
        );
      }
    }

    // 3. Today's scheduled patient volume
    final scheduledPatients = scheduledAsync.valueOrNull ?? [];
    if (scheduledPatients.isNotEmpty) {
      final totalAppts = scheduledPatients.fold<int>(
        0,
        (sum, entry) => sum + entry.todayAppointments.length,
      );
      liveInsights.add(
        _InsightData(
          borderColor: AppColors.primaryContainer,
          text:
              '${scheduledPatients.length} patient(s) ($totalAppts appointments) scheduled across clinics today.',
          highlight: '${scheduledPatients.length} patients',
        ),
      );
    }

    // 4. Staff attendance status today
    final attendance = attendanceAsync.valueOrNull ?? [];
    final presentCount = attendance.where((a) {
      final s = a.status.toLowerCase();
      return s == 'present' || s == 'late' || a.checkInTime != null;
    }).length;

    if (attendance.isNotEmpty && presentCount > 0 && liveInsights.length < 2) {
      liveInsights.add(
        _InsightData(
          borderColor: AppColors.secondary,
          text:
              '$presentCount staff member(s) checked in for today\'s clinical operations.',
          highlight: '$presentCount active',
          highlightColor: AppColors.secondary,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryContainer, AppColors.secondary],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg - 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.psychology,
                      color: AppColors.secondary,
                      size: 24,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'Copilot Insights',
                        style: AppTypography.headlineMd,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    FadeTransition(
                      opacity: Tween<double>(begin: 0.4, end: 1).animate(
                        CurvedAnimation(
                          parent: _pulseController,
                          curve: Curves.easeInOut,
                        ),
                      ),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.secondary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (liveInsights.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          color: Color(0xFF2E7D32),
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            'No critical operational alerts for today. Clinic running smoothly.',
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  for (int i = 0; i < liveInsights.take(2).length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.sm),
                    _InsightItem(
                      borderColor: liveInsights[i].borderColor,
                      text: liveInsights[i].text,
                      highlight: liveInsights[i].highlight,
                      highlightColor: liveInsights[i].highlightColor,
                    ),
                  ],
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: _navigateToReports,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.secondaryContainer,
                    foregroundColor: const Color(0xFF7B2460),
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          'View Full Analysis',
                          style: AppTypography.labelCaps.copyWith(
                            color: const Color(0xFF7B2460),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      const Icon(Icons.arrow_forward, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InsightData {
  final Color borderColor;
  final String text;
  final String highlight;
  final Color? highlightColor;

  const _InsightData({
    required this.borderColor,
    required this.text,
    required this.highlight,
    this.highlightColor,
  });
}

class _InsightItem extends StatelessWidget {
  const _InsightItem({
    required this.borderColor,
    required this.text,
    required this.highlight,
    this.highlightColor,
  });

  final Color borderColor;
  final String text;
  final String highlight;
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border(
          left: BorderSide(
            color: borderColor,
            width: 3.5,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Text.rich(
        _buildSpans(
            text, highlight, highlightColor ?? AppColors.primaryContainer),
        style: AppTypography.bodySm.copyWith(
          color: AppColors.onSurface,
          fontSize: 12,
          height: 1.35,
        ),
      ),
    );
  }

  TextSpan _buildSpans(String fullText, String highlightText, Color hColor) {
    if (!fullText.contains(highlightText)) {
      return TextSpan(text: fullText);
    }

    final parts = fullText.split(highlightText);
    final spans = <InlineSpan>[];

    for (int i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) {
        spans.add(TextSpan(text: parts[i]));
      }
      if (i < parts.length - 1) {
        spans.add(
          TextSpan(
            text: highlightText,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: hColor,
            ),
          ),
        );
      }
    }

    return TextSpan(children: spans);
  }
}
