import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
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
                      color: isSelected ? Colors.white : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                    ),
                    label: Text(section.displayName),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) {
                        ref.read(adminReportsSectionProvider.notifier).state = section;
                      }
                    },
                    selectedColor: const Color(0xFF0D9488),
                    backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: isSelected ? const Color(0xFF0D9488) : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
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
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                          initialDateRange: filter.customStartDate != null && filter.customEndDate != null
                              ? DateTimeRange(start: filter.customStartDate!, end: filter.customEndDate!)
                              : DateTimeRange(
                                  start: DateTime.now().subtract(const Duration(days: 30)),
                                  end: DateTime.now(),
                                ),
                        );
                        if (picked != null) {
                          ref.read(adminReportsFilterProvider.notifier).state = filter.copyWith(
                            datePreset: ReportsDatePreset.custom,
                            customStartDate: picked.start,
                            customEndDate: picked.end,
                          );
                        }
                      } else {
                        ref.read(adminReportsFilterProvider.notifier).state = filter.copyWith(
                          datePreset: preset,
                          customStartDate: null,
                          customEndDate: null,
                        );
                      }
                    },
                    selectedColor: const Color(0xFF0D9488).withValues(alpha: 0.15),
                    checkmarkColor: const Color(0xFF0D9488),
                    backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? const Color(0xFF0D9488)
                          : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isSelected
                            ? const Color(0xFF0D9488)
                            : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                      ),
                    ),
                  );
                }).toList(),
              ),

              // Department Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: filter.department,
                    icon: const Icon(Icons.arrow_drop_down, size: 20),
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontWeight: FontWeight.w500,
                    ),
                    dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Departments')),
                      DropdownMenuItem(value: 'eye', child: Text('Eye Clinic')),
                      DropdownMenuItem(value: 'dental', child: Text('Dental Clinic')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(adminReportsFilterProvider.notifier).state = filter.copyWith(department: val);
                      }
                    },
                  ),
                ),
              ),

              // Active Date Range Indicator
              if (filter.effectiveStartDate != null || filter.effectiveEndDate != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D9488).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 14, color: Color(0xFF0D9488)),
                      const SizedBox(width: 6),
                      Text(
                        _formatDateRange(filter.effectiveStartDate, filter.effectiveEndDate),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF0D9488),
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
