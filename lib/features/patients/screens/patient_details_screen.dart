import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../providers/patient_attendance_provider.dart';
import '../providers/patient_provider.dart';

class PatientDetailsScreen extends ConsumerWidget {
  const PatientDetailsScreen({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientAsync = ref.watch(patientDetailsProvider(patientId));
    final historyAsync = ref.watch(patientAttendanceHistoryProvider(patientId));

    return Scaffold(
      appBar: AppBar(title: const Text('Patient Details')),
      body: patientAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Unable to load patient: $error')),
        data: (patient) => ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text(patient.fullName, style: AppTypography.displayLg),
            const SizedBox(height: AppSpacing.sm),
            Text('Registration: ${patient.patientNumber}'),
            Text('Phone: ${patient.mobile}'),
            Text('Department: ${patient.departmentName ?? 'Not assigned'}'),
            if (patient.dateOfBirth != null) Text('Date of birth: ${DateFormat('MMM d, yyyy').format(patient.dateOfBirth!)}'),
            if (patient.address != null) Text('Address: ${patient.address}'),
            const SizedBox(height: AppSpacing.lg),
            Text('Patient Attendance History', style: AppTypography.headlineMd),
            const SizedBox(height: AppSpacing.sm),
            historyAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Text('Unable to load attendance history: $error'),
              data: (records) => records.isEmpty
                  ? const Text('No attendance records found.')
                  : Column(
                      children: records
                          .map((record) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(record.staffName ?? record.staffId),
                                subtitle: Text(DateFormat('MMM d, yyyy, h:mm a').format(record.attendedAt.toLocal())),
                                trailing: Text(record.status),
                              ))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
