import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../admin/screens/admin_patient_attendance_screen.dart';
import '../../admin/widgets/admin_shell.dart';
import '../models/patient.dart';
import '../providers/patient_provider.dart';
import '../widgets/patient_form_dialog.dart';
import 'patient_details_screen.dart';

class PatientListScreen extends StatelessWidget {
  const PatientListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      selectedItem: AdminNavItem.patients,
      onNavItemSelected: (item) {
        if (item == AdminNavItem.dashboard) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      },
      body: const PatientListContent(),
    );
  }
}

class PatientListContent extends ConsumerStatefulWidget {
  const PatientListContent({super.key});

  @override
  ConsumerState<PatientListContent> createState() => _PatientListContentState();
}

class _PatientListContentState extends ConsumerState<PatientListContent> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final patientsAsync = ref.watch(patientsProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= 768;

    return Padding(
      padding: EdgeInsets.all(
          isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(isDesktop),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _searchController,
            onChanged: (value) =>
                ref.read(patientsProvider.notifier).search(value),
            decoration: InputDecoration(
              hintText:
                  'Search patients by name, phone, or registration number',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        ref.read(patientsProvider.notifier).search('');
                        setState(() {});
                      },
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: patientsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => _ErrorRetry(
                error: error,
                onRetry: () =>
                    ref.read(patientsProvider.notifier).fetchPatients(),
              ),
              data: (patients) => patients.isEmpty
                  ? const Center(child: Text('No registered patients found.'))
                  : ListView.separated(
                      itemCount: patients.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) =>
                          _PatientTile(patient: patients[index]),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDesktop) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        Text(
          'Patients',
          style: AppTypography.displayLg.copyWith(
            color: AppColors.onBackground,
            fontSize: isDesktop ? null : 26,
          ),
        ),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const AdminPatientAttendanceScreen()),
              ),
              icon: const Icon(Icons.how_to_reg),
              label: const Text("Today's Attendance"),
            ),
            FilledButton.icon(
              onPressed: () => _openPatientDialog(),
              icon: const Icon(Icons.person_add),
              label: const Text('New Patient'),
            ),
          ],
        ),
      ],
    );
  }

  /// Opens [PatientFormDialog] for creating a new patient, or editing [patient]
  /// when provided. The dialog is a fully self-contained [ConsumerStatefulWidget]
  /// and handles all its own lifecycle, async safety, and controller disposal.
  void _openPatientDialog({Patient? patient}) {
    showDialog<void>(
      context: context,
      // Prevent accidental dismissal while a save is in flight.
      barrierDismissible: !_dialogSaving,
      builder: (_) => PatientFormDialog(patient: patient),
    );
  }

  /// The dialog manages its own loading state. We keep [barrierDismissible]
  /// true so the user can always tap outside to cancel even if this flag
  /// is stale; the dialog's own Cancel button is the reliable escape path.
  final bool _dialogSaving = false;
}

// ── Patient tile ─────────────────────────────────────────────────────────────

class _PatientTile extends ConsumerWidget {
  const _PatientTile({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        title: Text(patient.fullName),
        subtitle: Text(
          '${patient.patientNumber} • ${patient.departmentName ?? 'No department'}\n'
          '${patient.mobile ?? '—'}',
        ),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: 'Edit patient',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () {
            final listState = context
                .findAncestorStateOfType<_PatientListContentState>();
            listState?._openPatientDialog(patient: patient);
          },
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => PatientDetailsScreen(patientId: patient.id)),
        ),
      ),
    );
  }
}

// ── Error/retry widget ────────────────────────────────────────────────────────

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
          const Text('Unable to load patients.'),
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
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
