import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../../patients/models/patient.dart';
import '../../patients/models/patient_attendance.dart';
import '../../patients/providers/patient_attendance_provider.dart';
import '../../patients/providers/patient_provider.dart';
import '../../patients/screens/patient_details_screen.dart';

class StaffPatientsScreen extends ConsumerWidget {
  const StaffPatientsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null) return const Center(child: CircularProgressIndicator());

    final patientsAsync = ref.watch(patientsProvider);
    final attendanceAsync = ref.watch(staffPatientAttendanceProvider(currentUser.id));
    final isDesktop = MediaQuery.sizeOf(context).width >= 768;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Shift Patients', style: AppTypography.displayLg.copyWith(color: AppColors.onBackground, fontSize: isDesktop ? null : 26)),
          const SizedBox(height: AppSpacing.xs),
          Text('Record the patients you attend today.', style: AppTypography.bodyLg.copyWith(color: AppColors.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.lg),
          patientsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Text('Unable to load patients: $error'),
            data: (patients) => attendanceAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Text('Unable to load attendance: $error'),
              data: (records) {
                final recordByPatient = {for (final record in records) record.patientId: record};
                if (patients.isEmpty) return const Text('No patients are available today.');
                return Column(
                  children: patients.map((patient) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _PatientAttendanceCard(
                        patient: patient,
                        record: recordByPatient[patient.id],
                        onAttend: () async {
                          try {
                            await ref.read(staffPatientAttendanceProvider(currentUser.id).notifier).markAttended(patient.id);
                            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Patient marked as attended.')));
                          } catch (error) {
                            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to record attendance: $error')));
                          }
                        },
                        onOpen: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientDetailsScreen(patientId: patient.id))),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientAttendanceCard extends StatelessWidget {
  const _PatientAttendanceCard({required this.patient, required this.record, required this.onAttend, required this.onOpen});

  final Patient patient;
  final PatientAttendance? record;
  final VoidCallback onAttend;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final attended = record != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onOpen,
              child: Row(
                children: [
                  CircleAvatar(child: Text(patient.fullName.split(' ').map((part) => part[0]).join())),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(patient.fullName, style: AppTypography.headlineMd),
                        Text('${patient.departmentName ?? 'No department'} • ${patient.registrationNumber}', style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(attended ? '✓ Attended' : 'Status: Pending', style: AppTypography.bodyMd.copyWith(color: attended ? Colors.green : Colors.orange, fontWeight: FontWeight.w600)),
            if (attended) ...[
              const SizedBox(height: AppSpacing.xs),
              Text('Attended by: ${record!.staffName ?? 'Current staff'}'),
              Text('Time: ${DateFormat('h:mm a').format(record!.attendedAt.toLocal())}'),
            ] else ...[
              const SizedBox(height: AppSpacing.md),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: onAttend, child: const Text('I ATTENDED'))),
            ],
          ],
        ),
      ),
    );
  }
}
