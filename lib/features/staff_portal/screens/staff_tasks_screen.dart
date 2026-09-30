import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../../staff/providers/task_provider.dart';

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
    if (currentUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final tasksAsync = ref.watch(staffTasksProvider(currentUser.id));

    return SingleChildScrollView(
      padding: EdgeInsets.all(
          isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile),
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
                      Text('My Shift Tasks',
                          style: AppTypography.displayLg
                              .copyWith(color: AppColors.onBackground)),
                      const SizedBox(height: AppSpacing.xs),
                      Text('Clinical checklist and patient care duties',
                          style: AppTypography.bodyLg
                              .copyWith(color: AppColors.onSurfaceVariant)),
                    ],
                  ),
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
                      Text('My Shift Tasks',
                          style: AppTypography.displayLg.copyWith(
                              color: AppColors.onBackground, fontSize: 26)),
                      const SizedBox(height: AppSpacing.xs),
                      Text('Clinical checklist and patient care duties',
                          style: AppTypography.bodyLg
                              .copyWith(color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          tasksAsync.when(
            data: (tasks) {
              final pendingCount = tasks
                  .where(
                      (t) => t.status != 'completed' && t.status != 'cancelled')
                  .length;
              final completedCount =
                  tasks.where((t) => t.status == 'completed').length;

              final filtered = tasks.where((t) {
                final isCompleted = t.status == 'completed';
                if (_filterIndex == 1) {
                  return !isCompleted && t.status != 'cancelled';
                }
                if (_filterIndex == 2) {
                  return isCompleted;
                }
                return t.status != 'cancelled';
              }).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip(
                            'All (${pendingCount + completedCount})', 0),
                        const SizedBox(width: AppSpacing.sm),
                        _buildFilterChip('Pending ($pendingCount)', 1),
                        const SizedBox(width: AppSpacing.sm),
                        _buildFilterChip('Completed ($completedCount)', 2),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Text('No tasks found for this category.'),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final isCompleted = item.status == 'completed';

                        Color priorityColor;
                        if (item.priority == 'critical' ||
                            item.priority == 'high') {
                          priorityColor = AppColors.error;
                        } else if (item.priority == 'medium') {
                          priorityColor = AppColors.primaryContainer;
                        } else {
                          priorityColor = AppColors.onSurfaceVariant;
                        }

                        return Container(
                          decoration: BoxDecoration(
                            color: isCompleted
                                ? AppColors.surfaceContainerLow
                                    .withValues(alpha: 0.5)
                                : AppColors.surfaceContainerLowest,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusLg),
                            border: Border.all(color: AppColors.outlineVariant),
                          ),
                          child: CheckboxListTile(
                            value: isCompleted,
                            onChanged: (val) async {
                              final newStatus =
                                  (val ?? false) ? 'completed' : 'pending';
                              try {
                                await ref
                                    .read(staffTasksProvider(currentUser.id)
                                        .notifier)
                                    .updateStatus(
                                        item.id, newStatus, item.status);
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content:
                                              Text('Error updating task: $e')));
                                }
                              }
                            },
                            activeColor: AppColors.primary,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              item.title,
                              style: AppTypography.bodyMd.copyWith(
                                fontWeight: FontWeight.w600,
                                decoration: isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: isCompleted
                                    ? AppColors.outline
                                    : AppColors.onSurface,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  if (item.dueDate != null) ...[
                                    const Icon(Icons.access_time,
                                        size: 12, color: AppColors.outline),
                                    const SizedBox(width: 4),
                                    Text(
                                        DateFormat('MMM d, h:mm a')
                                            .format(item.dueDate!),
                                        style: AppTypography.dataMono.copyWith(
                                            fontSize: 11,
                                            color: item.isOverdue
                                                ? AppColors.error
                                                : AppColors.outline)),
                                  ],
                                ],
                              ),
                            ),
                            secondary: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: priorityColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                item.priority.toUpperCase(),
                                style: AppTypography.labelCaps.copyWith(
                                    color: priorityColor, fontSize: 10),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => Center(child: Text('Error: $e')),
          ),
        ],
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
