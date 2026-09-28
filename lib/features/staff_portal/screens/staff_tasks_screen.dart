import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../../staff/providers/task_provider.dart';
import 'staff_task_history_screen.dart';

class StaffTasksScreen extends ConsumerStatefulWidget {
  const StaffTasksScreen({super.key});

  @override
  ConsumerState<StaffTasksScreen> createState() => _StaffTasksScreenState();
}

class _StaffTasksScreenState extends ConsumerState<StaffTasksScreen> {
  int _filterIndex = 0; // 0: All, 1: Pending, 2: Completed

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 768.0;
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null) return const Center(child: CircularProgressIndicator());

    final tasksAsync = ref.watch(staffTasksProvider(currentUser.id));

    return RefreshIndicator(
      onRefresh: () => ref.read(staffTasksProvider(currentUser.id).notifier).fetchTasks(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isDesktop)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('My Shift Tasks', style: AppTypography.displayLg.copyWith(color: AppColors.onBackground)),
                        const SizedBox(height: AppSpacing.xs),
                        Text('Clinical checklist and patient care duties', style: AppTypography.bodyLg.copyWith(color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh tasks',
                        onPressed: () => ref.read(staffTasksProvider(currentUser.id).notifier).fetchTasks(),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const StaffTaskHistoryScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.history, size: 18),
                        label: const Text('History'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                ],
              )
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('My Shift Tasks', style: AppTypography.displayLg.copyWith(color: AppColors.onBackground, fontSize: 26)),
                        const SizedBox(height: AppSpacing.xs),
                        Text('Clinical checklist and patient care duties', style: AppTypography.bodyLg.copyWith(color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh tasks',
                        onPressed: () => ref.read(staffTasksProvider(currentUser.id).notifier).fetchTasks(),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const StaffTaskHistoryScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.history, size: 16),
                        label: const Text('History'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],

            const SizedBox(height: AppSpacing.lg),

            tasksAsync.when(
              data: (tasks) {
                final pendingCount = tasks.where((t) => t.status != 'completed' && t.status != 'cancelled').length;
                final completedCount = tasks.where((t) => t.status == 'completed').length;
                
                final filtered = tasks.where((t) {
                  final isCompleted = t.status == 'completed';
                  if (_filterIndex == 1) return !isCompleted && t.status != 'cancelled';
                  if (_filterIndex == 2) return isCompleted;
                  return t.status != 'cancelled';
                }).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('All (${pendingCount + completedCount})', 0),
                          const SizedBox(width: AppSpacing.sm),
                          _buildFilterChip('Pending ($pendingCount)', 1),
                          const SizedBox(width: AppSpacing.sm),
                          _buildFilterChip('Completed ($completedCount)', 2),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.task_alt, size: 48, color: AppColors.outline),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                _filterIndex == 1
                                    ? 'No pending tasks. Great job!'
                                    : _filterIndex == 2
                                        ? 'No completed tasks yet.'
                                        : 'No tasks assigned to you right now.',
                                style: AppTypography.bodyLg.copyWith(color: AppColors.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final isCompleted = item.status == 'completed';
                          
                          Color priorityColor;
                          if (item.priority == 'critical' || item.priority == 'high') {
                            priorityColor = AppColors.error;
                          } else if (item.priority == 'medium') {
                            priorityColor = AppColors.primaryContainer;
                          } else {
                            priorityColor = AppColors.onSurfaceVariant;
                          }

                          return Container(
                            decoration: BoxDecoration(
                              color: isCompleted ? AppColors.surfaceContainerLow.withValues(alpha: 0.5) : AppColors.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                              border: Border.all(color: AppColors.outlineVariant),
                            ),
                            child: CheckboxListTile(
                              value: isCompleted,
                              onChanged: (val) async {
                                final newStatus = (val ?? false) ? 'completed' : 'pending';
                                try {
                                  await ref.read(staffTasksProvider(currentUser.id).notifier).updateStatus(item.id, newStatus, item.status);
                                  // Refresh admin provider in background so admin sees updated task
                                  ref.read(adminTasksProvider.notifier).fetchTasks(silent: true);
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating task: $e')));
                                  }
                                }
                              },
                              activeColor: AppColors.primary,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                item.title,
                                style: AppTypography.bodyMd.copyWith(
                                  fontWeight: FontWeight.w600,
                                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                                  color: isCompleted ? AppColors.outline : AppColors.onSurface,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    if (item.dueDate != null) ...[
                                      const Icon(Icons.access_time, size: 12, color: AppColors.outline),
                                      const SizedBox(width: 4),
                                      Text(
                                        DateFormat('MMM d, h:mm a').format(item.dueDate!),
                                        style: AppTypography.dataMono.copyWith(
                                          fontSize: 11,
                                          color: item.isOverdue ? AppColors.error : AppColors.outline,
                                        ),
                                      ),
                                    ],
                                    if (item.description != null && item.description!.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          item.description!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              secondary: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: priorityColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  item.priority.toUpperCase(),
                                  style: AppTypography.labelCaps.copyWith(color: priorityColor, fontSize: 10),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, st) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                      const SizedBox(height: AppSpacing.sm),
                      Text('Error loading tasks: $e', textAlign: TextAlign.center),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                        onPressed: () => ref.read(staffTasksProvider(currentUser.id).notifier).fetchTasks(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final isSelected = _filterIndex == index;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _filterIndex = index);
      },
      selectedColor: AppColors.primaryContainer.withValues(alpha: 0.2),
      backgroundColor: AppColors.surfaceContainerLowest,
      labelStyle: AppTypography.bodyMd.copyWith(
        color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}
