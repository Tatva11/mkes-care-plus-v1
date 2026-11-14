import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../auth/providers/auth_provider.dart';

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
  Timer? _debounceTimer;
  int _currentPage = 0;
  static const int _pageSize = 50;

  @override
  void dispose() {
    _debounceTimer?.cancel();
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
      setState(() {
        _department = targetDept;
        _currentPage = 0;
      });
      ref.invalidate(patientSearchProvider);
      ref.invalidate(paginatedPatientSearchProvider);
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
    final patientsAsync = ref.watch(paginatedPatientSearchProvider((
      department: _department,
      query: _searchQuery,
      page: _currentPage,
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
              _buildPaginationControls(patientsAsync.valueOrNull?.length ?? 0),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPaginationControls(int currentCount) {
    if (currentCount == 0 && _currentPage == 0) return const SizedBox.shrink();

    final hasNext = currentCount >= _pageSize;
    final hasPrev = _currentPage > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          Text(
            'Showing $currentCount patients (Page ${_currentPage + 1})',
            style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: hasPrev
                    ? () => setState(() => _currentPage--)
                    : null,
                icon: const Icon(Icons.chevron_left, size: 18),
                label: const Text('Previous'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: hasNext
                    ? () => setState(() => _currentPage++)
                    : null,
                icon: const Icon(Icons.chevron_right, size: 18),
                label: const Text('Next'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
            ],
          ),
        ],
      ),
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
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  _debounceTimer?.cancel();
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                    _currentPage = 0;
                  });
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
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 350), () {
          if (mounted) {
            final trimmed = val.trim();
            if (_searchQuery != trimmed) {
              setState(() {
                _searchQuery = trimmed;
                _currentPage = 0;
              });
            }
          }
        });
      },
      onSubmitted: (val) {
        _debounceTimer?.cancel();
        final trimmed = val.trim();
        if (_searchQuery != trimmed) {
          setState(() {
            _searchQuery = trimmed;
            _currentPage = 0;
          });
        }
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
    _debounceTimer?.cancel();
    setState(() {
      _department = department;
      _currentPage = 0;
    });
    ref.invalidate(patientSearchProvider);
    ref.invalidate(paginatedPatientSearchProvider);
    ref.invalidate(patientsByDepartmentProvider(department));
  }

  Future<void> _confirmDeletePatient(PatientModel patient) async {
    final profile = ref.read(currentProfileProvider).valueOrNull;
    final isAdmin = profile?.role == 'admin';
    final userDept = profile?.department?.toLowerCase().trim();
    final patientDept = patient.department?.toLowerCase().trim();

    if (!isAdmin &&
        (userDept == null || userDept.isEmpty || userDept != patientDept)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Access denied: Staff can only delete patients belonging to their assigned department.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Patient Record'),
        content: Text(
          'Are you sure you want to permanently delete patient ${patient.name} (${patient.patientNumber})?\n\n'
          'This will remove the patient record and associated clinic appointments. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await ref.read(patientsProvider.notifier).deletePatient(patient.id);

        ref.invalidate(patientSearchProvider);
        ref.invalidate(paginatedPatientSearchProvider);
        ref.invalidate(patientsByDepartmentProvider('eye'));
        ref.invalidate(patientsByDepartmentProvider('dental'));
        ref.invalidate(patientsProvider);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Patient ${patient.name} (${patient.patientNumber}) deleted successfully.',
              ),
              backgroundColor: AppColors.primaryContainer,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error deleting patient: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}',
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Widget _buildHeader(bool isDesktop) {
    if (isDesktop) {
      return Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Patients',
                style: AppTypography.displayLg.copyWith(
                  color: AppColors.onBackground,
                  fontSize: 36,
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
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
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
              onPressed: () => ref.invalidate(paginatedPatientSearchProvider),
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
                                  ref.invalidate(paginatedPatientSearchProvider);
                                  ref.invalidate(
                                      patientsByDepartmentProvider('eye'));
                                  ref.invalidate(
                                      patientsByDepartmentProvider('dental'));
                                  ref.invalidate(patientsProvider);
                                }
                              },
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              color: AppColors.error,
                              tooltip: 'Delete Patient',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _confirmDeletePatient(patient),
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
                              ref.invalidate(paginatedPatientSearchProvider),
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
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
                        ref.invalidate(paginatedPatientSearchProvider);
                        ref.invalidate(patientsByDepartmentProvider('eye'));
                        ref.invalidate(patientsByDepartmentProvider('dental'));
                        ref.invalidate(patientsProvider);
                      }
                    },
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
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
