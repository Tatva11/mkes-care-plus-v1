import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../admin/widgets/admin_shell.dart';
import '../models/patient_model.dart';
import '../providers/patients_provider.dart';
import '../widgets/patient_form_dialog.dart';
import 'patient_profile_screen.dart';

class PatientListScreen extends StatelessWidget {
  const PatientListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      selectedItem: AdminNavItem.patients,
      onNavItemSelected: (item) {
        if (item == AdminNavItem.dashboard) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          return;
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
  String _department = 'eye';

  Future<void> _openNewPatientDialog() async {
    final created = await showDialog<PatientModel>(
      context: context,
      builder: (_) => PatientFormDialog(initialDepartment: _department),
    );
    if (created != null && mounted) {
      ref.invalidate(patientsByDepartmentProvider(_department));
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedDepartment = _department;
    final patientsAsync =
        ref.watch(patientsByDepartmentProvider(selectedDepartment));
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 768;
        return SingleChildScrollView(
          padding: EdgeInsets.all(
            isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(isDesktop),
              const SizedBox(height: AppSpacing.lg),
              _buildDepartmentFilter(),
              const SizedBox(height: AppSpacing.md),
              _buildPatientTable(patientsAsync),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDepartmentFilter() {
    return Wrap(
      spacing: AppSpacing.sm,
      children: [
        ChoiceChip(
          label: const Text('Eye'),
          selected: _department == 'eye',
          onSelected: (_) => _selectDepartment('eye'),
        ),
        ChoiceChip(
          label: const Text('Dental'),
          selected: _department == 'dental',
          onSelected: (_) => _selectDepartment('dental'),
        ),
      ],
    );
  }

  void _selectDepartment(String department) {
    if (department != 'eye' && department != 'dental') return;
    setState(() => _department = department);
    ref.invalidate(patientsByDepartmentProvider(department));
  }

  Widget _buildHeader(bool isDesktop) {
    if (isDesktop) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Patients',
                style: AppTypography.displayLg.copyWith(
                  color: AppColors.onBackground,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Manage patient records and clinical history.',
                style: AppTypography.bodyLg.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          FilledButton.icon(
            onPressed: _openNewPatientDialog,
            icon: const Icon(Icons.person_add),
            label: const Text('New Patient'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Patients',
          style: AppTypography.displayLg.copyWith(
            color: AppColors.onBackground,
            fontSize: 26,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Manage patient records and clinical history.',
          style: AppTypography.bodyLg.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.icon(
          onPressed: _openNewPatientDialog,
          icon: const Icon(Icons.person_add),
          label: const Text('New Patient'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPatientTable(AsyncValue<List<PatientModel>> patientsAsync) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.outlineVariant),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 780),
          child: Column(
            children: [
              // Table Header
              Container(
                width: 780,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text('PATIENT ID', style: AppTypography.labelCaps),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text('NAME', style: AppTypography.labelCaps),
                    ),
                    Expanded(
                      flex: 2,
                      child:
                          Text('AGE / GENDER', style: AppTypography.labelCaps),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text('CONTACT', style: AppTypography.labelCaps),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('LAST VISIT', style: AppTypography.labelCaps),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('DEPARTMENT', style: AppTypography.labelCaps),
                    ),
                    const SizedBox(width: 48), // Action button space
                  ],
                ),
              ),
              SizedBox(
                width: 780,
                child: patientsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, stackTrace) => Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      children: [
                        Text('Unable to load patients: $error'),
                        TextButton(
                          onPressed: () => ref.invalidate(
                              patientsByDepartmentProvider(_department)),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                  data: (patients) => patients.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(AppSpacing.lg),
                          child: Center(
                              child:
                                  Text('No patients in this department yet.')),
                        )
                      : Column(children: patients.map(_patientRow).toList()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPatientRow(
    String id,
    String name,
    String ageGender,
    String contact,
    String lastVisit,
    String department,
  ) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const PatientProfileScreen(),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: AppColors.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    id,
                    style: AppTypography.dataMono.copyWith(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                name,
                style:
                    AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                ageGender,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                contact,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                lastVisit,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(
                    department,
                    style: AppTypography.labelCaps
                        .copyWith(color: AppColors.primaryContainer),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              color: AppColors.outline,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PatientProfileScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _patientRow(PatientModel patient) {
    final ageLabel = patient.dob == null
        ? '—'
        : '${DateTime.now().year - patient.dob!.year}';
    final visitDate = patient.visitDate == null
        ? '—'
        : DateFormat('MMM d, yyyy').format(patient.visitDate!.toLocal());
    final departmentLabel = patient.department == 'eye' ? 'Eye' : 'Dental';
    return _buildPatientRow(
      patient.patientNumber,
      patient.name,
      ageLabel,
      patient.mobile ?? '—',
      visitDate,
      departmentLabel,
    );
  }
}
