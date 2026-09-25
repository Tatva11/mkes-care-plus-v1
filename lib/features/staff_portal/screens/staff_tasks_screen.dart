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
    if (currentUser == null) return const Center(child: CircularProgressIndicator());

    final tasksAsync = ref.watch(staffTasksProvider(currentUser.id));

    return SingleChildScrollView(
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
              ],
            )
          else ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('My Shift Tasks', style: AppTypography.displayLg.copyWith(color: AppColors.onBackground, fontSize: 26)),
                const SizedBox(height: AppSpacing.xs),
                Text('Clinical checklist and patient care duties', style: AppTypography.bodyLg.copyWith(color: AppColors.onSurfaceVariant)),
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
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Text('No tasks assigned to you right now.'),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final priorityColor = switch (item.priority.toLowerCase()) {
                          'critical' || 'high' => AppColors.error,
                          'medium' => AppColors.primaryContainer,
                          _ => AppColors.onSurfaceVariant,
                        };
                        final isCompleted = item.status == 'completed';

                        return Container(
                          decoration: BoxDecoration(
                            color: isCompleted
                                ? AppColors.surfaceContainerLow.withValues(alpha: 0.5)
                                : AppColors.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                            border: Border.all(color: AppColors.outlineVariant),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.title,
                                        style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    Container(
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
                                  ],
                                ),
                                if (item.description != null && item.description!.trim().isNotEmpty) ...[
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(item.description!, style: AppTypography.bodySm),
                                ],
                                const SizedBox(height: AppSpacing.sm),
                                if (item.dueDate != null)
                                  Text(
                                    'Due: ${DateFormat('MMM d, yyyy').format(item.dueDate!)}',
                                    style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                                  ),
                                const SizedBox(height: AppSpacing.sm),
                                Row(
                                  children: [
                                    Text(
                                      'Status: ${isCompleted ? 'Completed' : 'Pending'}',
                                      style: AppTypography.bodySm.copyWith(
                                        color: isCompleted ? Colors.green : AppColors.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (isCompleted) ...[
                                      const SizedBox(width: AppSpacing.sm),
                                      const Icon(Icons.check_circle, color: Colors.green, size: 18),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.md),
                                if (!isCompleted)
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      onPressed: () async {
                                        try {
                                          await ref.read(staffTasksProvider(currentUser.id).notifier).completeTask(
                                            item.id,
                                            item.status,
                                          );
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Task marked as completed.')),
                                            );
                                          }
                                        } catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Error updating task: $e')),
                                            );
                                          }
                                        }
                                      },
                                      child: const Text('Complete'),
                                    ),
                                  )
                                else
                                  const SizedBox(
                                    width: double.infinity,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text('Completed', style: TextStyle(fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                              ],
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
