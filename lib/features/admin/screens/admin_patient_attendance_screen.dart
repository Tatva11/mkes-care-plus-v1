import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../patients/models/patient_attendance.dart';
import '../../patients/providers/patient_attendance_provider.dart';

/// Admin-facing screen showing all patient attendance records for today.
///
/// Displays a summary of how many patients each staff member has attended,
/// followed by individual attendance record cards.
///
/// Navigated to via a button on [PatientListScreen].
/// Does NOT use AdminShell — it is a pushed Scaffold on top of the admin nav.
class AdminPatientAttendanceScreen extends ConsumerWidget {
  const AdminPatientAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceAsync = ref.watch(adminPatientAttendanceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's Patient Attendance"),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(adminPatientAttendanceProvider),
          ),
        ],
      ),
      body: attendanceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorRetry(
          error: error,
          onRetry: () => ref.invalidate(adminPatientAttendanceProvider),
        ),
        data: (records) => _AttendanceBody(records: records),
      ),
    );
  }
}

// ── Body (data state) ─────────────────────────────────────────────────────────

class _AttendanceBody extends StatelessWidget {
  const _AttendanceBody({required this.records});

  final List<PatientAttendance> records;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const _EmptyState();
    }

    // Build a staff-name → count summary for the header summary row.
    final Map<String, int> staffCounts = {};
    for (final r in records) {
      final key = r.staffName ?? r.staffId;
      staffCounts[key] = (staffCounts[key] ?? 0) + 1;
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        // ── Summary header ────────────────────────────────────────────────
        Text(
          'Summary',
          style: AppTypography.headlineMd,
        ),
        const SizedBox(height: AppSpacing.sm),
        _SummaryChip(
          icon: Icons.how_to_reg_outlined,
          label:
              '${records.length} patient${records.length == 1 ? '' : 's'} attended',
          color: AppColors.primary,
        ),
        const SizedBox(height: AppSpacing.sm),
        ...staffCounts.entries.map(
          (entry) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              backgroundColor: AppColors.surfaceContainerLow,
              child: Icon(Icons.person_outline, color: AppColors.primary),
            ),
            title: Text(entry.key, style: AppTypography.bodyMd),
            trailing: Chip(
              label:
                  Text('${entry.value} patient${entry.value == 1 ? '' : 's'}'),
              padding: EdgeInsets.zero,
              backgroundColor:
                  AppColors.primaryContainer.withValues(alpha: 0.15),
              labelStyle: AppTypography.labelCaps
                  .copyWith(color: AppColors.primary, fontSize: 11),
            ),
          ),
        ),

        // ── Attendance records ────────────────────────────────────────────
        const SizedBox(height: AppSpacing.md),
        Text('Attendance Records', style: AppTypography.headlineMd),
        const SizedBox(height: AppSpacing.sm),
        ...records.map((record) => _AttendanceCard(record: record)),
      ],
    );
  }
}

// ── Single attendance record card ─────────────────────────────────────────────

class _AttendanceCard extends StatelessWidget {
  const _AttendanceCard({required this.record});

  final PatientAttendance record;

  @override
  Widget build(BuildContext context) {
    final patientLabel = record.patientName ?? 'Unknown patient';
    final patientSub = [
      if (record.patientNumber != null) record.patientNumber!,
      if (record.patientDepartment != null)
        _deptLabel(record.patientDepartment!),
    ].join(' • ');

    final staffLabel = record.staffName ?? 'Staff';
    final timeLabel = DateFormat('h:mm a').format(record.attendedAt.toLocal());

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Attended badge ────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle,
                  color: Colors.green.shade600, size: 22),
            ),
            const SizedBox(width: AppSpacing.md),

            // ── Patient + staff info ──────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(patientLabel, style: AppTypography.headlineMd),
                  if (patientSub.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.base),
                    Text(
                      patientSub,
                      style: AppTypography.bodySm
                          .copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      const Icon(Icons.person_outline,
                          size: 14, color: AppColors.outline),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          staffLabel,
                          style: AppTypography.bodyMd
                              .copyWith(color: AppColors.onSurface),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Time ─────────────────────────────────────────────────────
            Text(
              timeLabel,
              style: AppTypography.dataMono.copyWith(
                color: AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _deptLabel(String dept) => dept == 'eye'
      ? 'Eye'
      : dept == 'dental'
          ? 'Dental'
          : dept;
}

// ── Summary chip ──────────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: AppTypography.labelCaps.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.how_to_reg_outlined,
            size: 72,
            color: AppColors.outline.withValues(alpha: 0.4),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No attendance recorded yet today.',
            style: AppTypography.headlineMd
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Staff attendance will appear here as patients are seen.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMd
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ── Error / retry ─────────────────────────────────────────────────────────────

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: AppSpacing.sm),
          const Text('Unable to load patient attendance.'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$error',
            textAlign: TextAlign.center,
            style: AppTypography.bodySm
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
