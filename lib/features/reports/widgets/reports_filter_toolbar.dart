import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../models/reports_filter_model.dart';
import '../providers/reports_provider.dart';

class ReportsFilterToolbar extends ConsumerWidget {
  const ReportsFilterToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(adminReportsFilterProvider);
    final activeSection = ref.watch(adminReportsSectionProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceContainerHigh
            : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: isDark ? AppColors.outline : AppColors.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ReportsSection.values.map((section) {
                final isSelected = activeSection == section;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: Icon(
                      section.icon,
                      size: 16,
                      color: isSelected
                          ? Colors.white
                          : (isDark
                              ? AppColors.outlineVariant
                              : AppColors.onSurfaceVariant),
                    ),
                    label: Text(section.displayName),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) {
                        ref.read(adminReportsSectionProvider.notifier).state =
                            section;
                      }
                    },
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.surfaceContainerLow,
                    labelStyle: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : (isDark
                              ? AppColors.outlineVariant
                              : AppColors.onSurfaceVariant),
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      side: BorderSide(
                        color: isSelected
                            ? AppColors.primary
                            : (isDark
                                ? AppColors.outline
                                : AppColors.outlineVariant),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          Divider(
            height: 1,
            color: isDark
                ? AppColors.outline.withValues(alpha: 0.3)
                : AppColors.outlineVariant,
          ),
          const SizedBox(height: 16),

          // Filters row: Date Presets + Department + Custom Date Range
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Date Presets
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: ReportsDatePreset.values.map((preset) {
                  final isSelected = filter.datePreset == preset;
                  return FilterChip(
                    label: Text(preset.displayName),
                    selected: isSelected,
                    onSelected: (val) async {
                      if (preset == ReportsDatePreset.custom) {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                          initialDateRange: filter.customStartDate != null &&
                                  filter.customEndDate != null
                              ? DateTimeRange(
                                  start: filter.customStartDate!,
                                  end: filter.customEndDate!)
                              : DateTimeRange(
                                  start: DateTime.now()
                                      .subtract(const Duration(days: 30)),
                                  end: DateTime.now(),
                                ),
                        );
                        if (picked != null) {
                          ref.read(adminReportsFilterProvider.notifier).state =
                              filter.copyWith(
                            datePreset: ReportsDatePreset.custom,
                            customStartDate: picked.start,
                            customEndDate: picked.end,
                          );
                        }
                      } else {
                        ref.read(adminReportsFilterProvider.notifier).state =
                            filter.copyWith(
                          datePreset: preset,
                          customStartDate: null,
                          customEndDate: null,
                        );
                      }
                    },
                    selectedColor:
                        AppColors.primaryContainer.withValues(alpha: 0.15),
                    checkmarkColor: AppColors.primary,
                    backgroundColor: AppColors.surfaceContainerLow,
                    labelStyle: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : (isDark
                              ? AppColors.outlineVariant
                              : AppColors.onSurfaceVariant),
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      side: BorderSide(
                        color: isSelected
                            ? AppColors.primary
                            : (isDark
                                ? AppColors.outline
                                : AppColors.outlineVariant),
                      ),
                    ),
                  );
                }).toList(),
              ),

              // Department Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: Border.all(
                    color:
                        isDark ? AppColors.outline : AppColors.outlineVariant,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: filter.department,
                    icon: const Icon(Icons.arrow_drop_down, size: 20),
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white : AppColors.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                    dropdownColor: isDark
                        ? AppColors.surfaceContainerHigh
                        : AppColors.surfaceContainerLowest,
                    items: const [
                      DropdownMenuItem(
                          value: 'all', child: Text('All Departments')),
                      DropdownMenuItem(value: 'eye', child: Text('Eye Clinic')),
                      DropdownMenuItem(
                          value: 'dental', child: Text('Dental Clinic')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(adminReportsFilterProvider.notifier).state =
                            filter.copyWith(department: val);
                      }
                    },
                  ),
                ),
              ),

              // Active Date Range Indicator
              if (filter.effectiveStartDate != null ||
                  filter.effectiveEndDate != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 14, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        _formatDateRange(
                            filter.effectiveStartDate, filter.effectiveEndDate),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDateRange(DateTime? start, DateTime? end) {
    final df = DateFormat('dd MMM yyyy');
    if (start != null && end != null) {
      return '${df.format(start)} - ${df.format(end)}';
    } else if (start != null) {
      return 'From ${df.format(start)}';
    } else if (end != null) {
      return 'Until ${df.format(end)}';
    }
    return 'All time';
  }
}
