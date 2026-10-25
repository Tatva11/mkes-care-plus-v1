import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../admin/screens/admin_patient_attendance_screen.dart';
import '../../admin/widgets/admin_shell.dart';
import '../models/patient_model.dart';
import '../providers/patients_provider.dart';
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
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openNewPatientDialog() async {
    final created = await showDialog<PatientModel>(
      context: context,
      builder: (_) => PatientFormDialog(initialDepartment: _department),
    );
    if (created != null && mounted) {
      final targetDept =
          (created.department == 'eye' || created.department == 'dental')
              ? created.department!
              : _department;
      setState(() => _department = targetDept);
      ref.invalidate(patientSearchProvider);
      ref.invalidate(patientsByDepartmentProvider('eye'));
      ref.invalidate(patientsByDepartmentProvider('dental'));
      ref.invalidate(patientsProvider);

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PatientDetailsScreen(patientId: created.id),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientsAsync = ref.watch(patientSearchProvider((
      department: _department,
      query: _searchQuery,
    )));

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
              _buildFilterAndSearch(isDesktop),
              const SizedBox(height: AppSpacing.md),
              isDesktop
                  ? _buildPatientTable(patientsAsync)
                  : _buildPatientCards(patientsAsync),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterAndSearch(bool isDesktop) {
    if (isDesktop) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildDepartmentFilter(),
          SizedBox(
            width: 340,
            child: _buildSearchBar(),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDepartmentFilter(),
        const SizedBox(height: AppSpacing.sm),
        _buildSearchBar(),
      ],
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Search by name, ID, or mobile...',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.outlineVariant),
        ),
      ),
      onChanged: (val) {
        setState(() => _searchQuery = val.trim());
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
    ref.invalidate(patientSearchProvider);
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
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AdminPatientAttendanceScreen(),
                  ),
                ),
                icon: const Icon(Icons.how_to_reg_outlined),
                label: const Text('Attendance'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
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
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AdminPatientAttendanceScreen(),
                ),
              ),
              icon: const Icon(Icons.how_to_reg_outlined),
              label: const Text('Attendance'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
              ),
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
        ),
      ],
    );
  }

  Widget _buildPatientCards(AsyncValue<List<PatientModel>> patientsAsync) {
    return patientsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Column(
          children: [
            Text('Unable to load patients: $error'),
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: () => ref.invalidate(patientSearchProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (patients) {
        if (patients.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Center(
              child: Text(
                _searchQuery.isNotEmpty
                    ? 'No patients found matching "$_searchQuery".'
                    : 'No patients in this department yet.',
                style: AppTypography.bodyMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          );
        }

        return Column(
          children: patients.map((patient) {
            final ageLabel = patient.dob == null
                ? '—'
                : '${DateTime.now().year - patient.dob!.year} yrs';
            final visitDate = patient.visitDate == null
                ? '—'
                : DateFormat('MMM d, yyyy')
                    .format(patient.visitDate!.toLocal());
            final departmentLabel =
                patient.department == 'eye' ? 'Eye' : 'Dental';

            return Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
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
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            PatientDetailsScreen(patientId: patient.id),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top row: ID badge, Department badge, Edit button, Chevron
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: AppColors.outlineVariant
                                        .withValues(alpha: 0.5)),
                              ),
                              child: Text(
                                patient.patientNumber,
                                style: AppTypography.dataMono.copyWith(
                                  color: AppColors.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryContainer
                                    .withValues(alpha: 0.1),
                                borderRadius:
                                    BorderRadius.circular(AppSpacing.radiusSm),
                              ),
                              child: Text(
                                departmentLabel,
                                style: AppTypography.labelCaps.copyWith(
                                  color: AppColors.primaryContainer,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              color: AppColors.primary,
                              tooltip: 'Edit Patient',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () async {
                                final updated = await showDialog<PatientModel>(
                                  context: context,
                                  builder: (_) =>
                                      PatientFormDialog(patient: patient),
                                );
                                if (updated != null && mounted) {
                                  ref.invalidate(patientSearchProvider);
                                  ref.invalidate(
                                      patientsByDepartmentProvider('eye'));
                                  ref.invalidate(
                                      patientsByDepartmentProvider('dental'));
                                  ref.invalidate(patientsProvider);
                                }
                              },
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            const Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: AppColors.outline,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),

                        // Patient Name
                        Text(
                          patient.name,
                          style: AppTypography.headlineMd.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),

                        // Age, Mobile, Last Visit
                        Wrap(
                          spacing: AppSpacing.md,
                          runSpacing: 4,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.cake_outlined,
                                    size: 13, color: AppColors.outline),
                                const SizedBox(width: 4),
                                Text(
                                  ageLabel,
                                  style: AppTypography.bodySm.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            if (patient.mobile != null &&
                                patient.mobile!.isNotEmpty)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.phone_outlined,
                                      size: 13, color: AppColors.outline),
                                  const SizedBox(width: 4),
                                  Text(
                                    patient.mobile!,
                                    style: AppTypography.bodySm.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.calendar_today_outlined,
                                    size: 13, color: AppColors.outline),
                                const SizedBox(width: 4),
                                Text(
                                  'Visit: $visitDate',
                                  style: AppTypography.bodySm.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
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
          constraints: const BoxConstraints(minWidth: 820),
          child: Column(
            children: [
              // Table Header
              Container(
                width: 820,
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
                    const SizedBox(width: 80), // Action button space
                  ],
                ),
              ),
              SizedBox(
                width: 820,
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
                          onPressed: () =>
                              ref.invalidate(patientSearchProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                  data: (patients) => patients.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Center(
                            child: Text(
                              _searchQuery.isNotEmpty
                                  ? 'No patients found matching "$_searchQuery".'
                                  : 'No patients in this department yet.',
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      : Column(
                          children: patients.map(_buildPatientRow).toList()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPatientRow(PatientModel patient) {
    final ageLabel = patient.dob == null
        ? '—'
        : '${DateTime.now().year - patient.dob!.year}';
    final visitDate = patient.visitDate == null
        ? '—'
        : DateFormat('MMM d, yyyy').format(patient.visitDate!.toLocal());
    final departmentLabel = patient.department == 'eye' ? 'Eye' : 'Dental';

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PatientDetailsScreen(patientId: patient.id),
          ),
        );
      },
      child: Container(
        width: 820,
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
                    patient.patientNumber,
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
                patient.name,
                style:
                    AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                ageLabel,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                patient.mobile ?? '—',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                visitDate,
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
                    departmentLabel,
                    style: AppTypography.labelCaps
                        .copyWith(color: AppColors.primaryContainer),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 80,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    color: AppColors.primary,
                    tooltip: 'Edit Patient',
                    onPressed: () async {
                      final updated = await showDialog<PatientModel>(
                        context: context,
                        builder: (_) => PatientFormDialog(patient: patient),
                      );
                      if (updated != null && mounted) {
                        ref.invalidate(patientSearchProvider);
                        ref.invalidate(patientsByDepartmentProvider('eye'));
                        ref.invalidate(patientsByDepartmentProvider('dental'));
                        ref.invalidate(patientsProvider);
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 20),
                    color: AppColors.outline,
                    tooltip: 'View Details',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              PatientDetailsScreen(patientId: patient.id),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
