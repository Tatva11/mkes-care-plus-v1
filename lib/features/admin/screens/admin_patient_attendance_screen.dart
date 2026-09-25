import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../patients/providers/patient_attendance_provider.dart';
import '../../patients/providers/patient_provider.dart';

class AdminPatientAttendanceScreen extends ConsumerWidget {
  const AdminPatientAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientsAsync = ref.watch(patientsProvider);
    final attendanceAsync = ref.watch(adminPatientAttendanceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text("Today's Patient Attendance")),
      body: patientsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorRetry(error: error, onRetry: () => ref.read(patientsProvider.notifier).fetchPatients()),
        data: (patients) => attendanceAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => _ErrorRetry(error: error, onRetry: () => ref.invalidate(adminPatientAttendanceProvider)),
          data: (records) {
            final recordByPatient = {for (final record in records) record.patientId: record};
            final counts = <String, int>{};
            for (final record in records) {
              counts[record.staffName ?? record.staffId] = (counts[record.staffName ?? record.staffId] ?? 0) + 1;
            }
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Text("Today's Patient Handling", style: AppTypography.headlineMd),
                const SizedBox(height: AppSpacing.sm),
                if (counts.isEmpty) const Text('No patient attendance recorded yet.') else ...counts.entries.map((entry) => ListTile(contentPadding: EdgeInsets.zero, title: Text(entry.key), trailing: Text('${entry.value} patients'))),
                const SizedBox(height: AppSpacing.md),
                Text("Today's Patients", style: AppTypography.headlineMd),
                const SizedBox(height: AppSpacing.sm),
                if (patients.isEmpty) const Text('No registered patients found.') else ...patients.map((patient) {
                  final record = recordByPatient[patient.id];
                  final attended = record != null;
                  return Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: ListTile(
                      title: Text(patient.fullName),
                      subtitle: Text('${patient.registrationNumber} • ${patient.departmentName ?? 'No department'}\n${attended ? 'Attended by ${record.staffName ?? record.staffId} at ${DateFormat('h:mm a').format(record.attendedAt.toLocal())}' : 'Pending'}'),
                      isThreeLine: true,
                      trailing: Text(attended ? 'Attended' : 'Pending', style: AppTypography.labelCaps.copyWith(color: attended ? Colors.green : Colors.orange)),
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Unable to load patient attendance.'), Text('$error', textAlign: TextAlign.center), const SizedBox(height: AppSpacing.sm), FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry'))]));
}
