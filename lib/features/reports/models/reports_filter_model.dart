import 'package:flutter/material.dart';

enum ReportsDatePreset {
  allTime,
  today,
  thisWeek,
  thisMonth,
  thisYear,
  custom;

  String get displayName {
    switch (this) {
      case ReportsDatePreset.allTime:
        return 'All Time';
      case ReportsDatePreset.today:
        return 'Today';
      case ReportsDatePreset.thisWeek:
        return 'This Week';
      case ReportsDatePreset.thisMonth:
        return 'This Month';
      case ReportsDatePreset.thisYear:
        return 'This Year';
      case ReportsDatePreset.custom:
        return 'Custom Range';
    }
  }
}

enum ReportsSection {
  overview,
  patients,
  appointments,
  staff,
  clinical,
  financial,
  inventory;

  String get displayName {
    switch (this) {
      case ReportsSection.overview:
        return 'Overview';
      case ReportsSection.patients:
        return 'Patients';
      case ReportsSection.appointments:
        return 'Appointments';
      case ReportsSection.staff:
        return 'Staff & Tasks';
      case ReportsSection.clinical:
        return 'Clinical / Procedures';
      case ReportsSection.financial:
        return 'Billing & Financial';
      case ReportsSection.inventory:
        return 'Inventory & Stock';
    }
  }

  IconData get icon {
    switch (this) {
      case ReportsSection.overview:
        return Icons.dashboard_outlined;
      case ReportsSection.patients:
        return Icons.people_alt_outlined;
      case ReportsSection.appointments:
        return Icons.calendar_month_outlined;
      case ReportsSection.staff:
        return Icons.badge_outlined;
      case ReportsSection.clinical:
        return Icons.medical_services_outlined;
      case ReportsSection.financial:
        return Icons.account_balance_wallet_outlined;
      case ReportsSection.inventory:
        return Icons.inventory_2_outlined;
    }
  }
}

class AdminReportsFilter {
  final ReportsSection section;
  final String department; // 'all', 'eye', 'dental'
  final ReportsDatePreset datePreset;
  final DateTime? customStartDate;
  final DateTime? customEndDate;

  const AdminReportsFilter({
    this.section = ReportsSection.overview,
    this.department = 'all',
    this.datePreset = ReportsDatePreset.thisMonth,
    this.customStartDate,
    this.customEndDate,
  });

  DateTime? get effectiveStartDate {
    final now = DateTime.now();
    switch (datePreset) {
      case ReportsDatePreset.today:
        return DateTime(now.year, now.month, now.day, 0, 0, 0);
      case ReportsDatePreset.thisWeek:
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        return DateTime(
            startOfWeek.year, startOfWeek.month, startOfWeek.day, 0, 0, 0);
      case ReportsDatePreset.thisMonth:
        return DateTime(now.year, now.month, 1, 0, 0, 0);
      case ReportsDatePreset.thisYear:
        return DateTime(now.year, 1, 1, 0, 0, 0);
      case ReportsDatePreset.custom:
        if (customStartDate != null) {
          return DateTime(customStartDate!.year, customStartDate!.month,
              customStartDate!.day, 0, 0, 0);
        }
        return null;
      case ReportsDatePreset.allTime:
        return null;
    }
  }

  DateTime? get effectiveEndDate {
    final now = DateTime.now();
    switch (datePreset) {
      case ReportsDatePreset.today:
        return DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      case ReportsDatePreset.thisWeek:
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        final endOfWeek = startOfWeek.add(const Duration(days: 6));
        return DateTime(
            endOfWeek.year, endOfWeek.month, endOfWeek.day, 23, 59, 59, 999);
      case ReportsDatePreset.thisMonth:
        final nextMonth = DateTime(now.year, now.month + 1, 1);
        return nextMonth.subtract(const Duration(milliseconds: 1));
      case ReportsDatePreset.thisYear:
        return DateTime(now.year, 12, 31, 23, 59, 59, 999);
      case ReportsDatePreset.custom:
        if (customEndDate != null) {
          return DateTime(customEndDate!.year, customEndDate!.month,
              customEndDate!.day, 23, 59, 59, 999);
        }
        return null;
      case ReportsDatePreset.allTime:
        return null;
    }
  }

  String get datePresetLabel => datePreset.displayName;

  /// Returns the standard prefix for report file naming according to section.
  static String sectionFilenamePrefix(ReportsSection sec) {
    switch (sec) {
      case ReportsSection.overview:
        return 'Overview';
      case ReportsSection.patients:
        return 'Patients';
      case ReportsSection.appointments:
        return 'Appointments';
      case ReportsSection.staff:
        return 'Staff_Tasks';
      case ReportsSection.clinical:
        return 'Clinical_Procedures';
      case ReportsSection.financial:
        return 'Billing';
      case ReportsSection.inventory:
        return 'Inventory';
    }
  }

  /// Returns the standard period suffix for report file naming according to preset.
  String get datePresetFilenameSuffix {
    switch (datePreset) {
      case ReportsDatePreset.allTime:
        return 'All_Time';
      case ReportsDatePreset.today:
        return 'Today';
      case ReportsDatePreset.thisWeek:
        return 'This_Week';
      case ReportsDatePreset.thisMonth:
        return 'This_Month';
      case ReportsDatePreset.thisYear:
        return 'This_Year';
      case ReportsDatePreset.custom:
        return 'Custom_Range';
    }
  }

  /// Generates the standard Excel export filename for a given report section.
  String getReportFileName(ReportsSection sec) {
    return '${sectionFilenamePrefix(sec)}_$datePresetFilenameSuffix.xlsx';
  }

  AdminReportsFilter copyWith({
    ReportsSection? section,
    String? department,
    ReportsDatePreset? datePreset,
    DateTime? customStartDate,
    DateTime? customEndDate,
    bool clearCustomDates = false,
  }) {
    return AdminReportsFilter(
      section: section ?? this.section,
      department: department ?? this.department,
      datePreset: datePreset ?? this.datePreset,
      customStartDate:
          clearCustomDates ? null : (customStartDate ?? this.customStartDate),
      customEndDate:
          clearCustomDates ? null : (customEndDate ?? this.customEndDate),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdminReportsFilter &&
          runtimeType == other.runtimeType &&
          section == other.section &&
          department == other.department &&
          datePreset == other.datePreset &&
          customStartDate == other.customStartDate &&
          customEndDate == other.customEndDate;

  @override
  int get hashCode => Object.hash(
        section,
        department,
        datePreset,
        customStartDate,
        customEndDate,
      );
}
