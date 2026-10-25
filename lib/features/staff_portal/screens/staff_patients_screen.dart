import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../../inventory/utils/phone_dialer_util.dart';
import '../../patients/models/patient_model.dart';
import '../../patients/providers/patients_provider.dart';
import '../../patients/screens/patient_details_screen.dart';
import '../../patients/widgets/patient_form_dialog.dart';

/// Staff-facing patient directory & search.
///
/// Features:
/// - Displays all patients accessible to the logged-in staff member based on role & department permissions.
/// - Department filtering (All, Eye, Dental) when allowed by permissions.
/// - Real-time search by name, patient number, or mobile.
/// - Preserves direct dial via Call button (with validation & feedback).
/// - Clean navigation to [PatientDetailsScreen].
/// - Avoids duplicate patient rows and removes misplaced attendance ("I Attended") controls.
class StaffPatientsScreen extends ConsumerStatefulWidget {
  const StaffPatientsScreen({super.key});

  @override
  ConsumerState<StaffPatientsScreen> createState() =>
      _StaffPatientsScreenState();
}

class _StaffPatientsScreenState extends ConsumerState<StaffPatientsScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedDepartment = 'all'; // 'all', 'eye', 'dental'

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final currentProfile = ref.watch(currentProfileProvider).valueOrNull;
    final isDesktop = MediaQuery.sizeOf(context).width >= 768;

    // Check staff role and department restriction
    final staffDept = currentProfile?.department?.trim().toLowerCase();
    final isRestrictedToDept = currentProfile != null &&
        currentProfile.role.toLowerCase() != 'admin' &&
        staffDept != null &&
        (staffDept == 'eye' || staffDept == 'dental');

    // Effective department passed to patient repository
    final effectiveDept = isRestrictedToDept
        ? staffDept
        : (_selectedDepartment == 'all' ? '' : _selectedDepartment);

    final patientsAsync = ref.watch(patientSearchProvider((
      department: effectiveDept,
      query: _searchQuery,
    )));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(patientSearchProvider);
        ref.invalidate(patientsProvider);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(
          isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Patient Directory',
                        style: AppTypography.displayLg.copyWith(
                          color: AppColors.onBackground,
                          fontSize: isDesktop ? null : 24,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        isRestrictedToDept
                            ? '${staffDept.toUpperCase()} Department patient records.'
                            : 'All accessible clinic patient records.',
                        style: AppTypography.bodyLg
                            .copyWith(color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final defaultDept = isRestrictedToDept
                        ? staffDept
                        : (_selectedDepartment == 'all' ? 'eye' : _selectedDepartment);
                    final created = await showDialog<PatientModel>(
                      context: context,
                      builder: (_) => PatientFormDialog(initialDepartment: defaultDept),
                    );
                    if (created != null) {
                      if (!context.mounted) return;
                      ref.invalidate(patientSearchProvider);
                      ref.invalidate(patientsProvider);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PatientDetailsScreen(patientId: created.id),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.person_add_outlined, size: 18),
                  label: const Text('New Patient'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Search Bar ──────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                decoration: InputDecoration(
                  hintText: 'Search patients by name, ID, or mobile...',
                  prefixIcon:
                      const Icon(Icons.search, color: AppColors.primary),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Department Filter (only if not restricted to single dept) ────
            if (!isRestrictedToDept) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      selected: _selectedDepartment == 'all',
                      label: const Text('All Departments'),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedDepartment = 'all');
                        }
                      },
                      selectedColor:
                          AppColors.primaryContainer.withValues(alpha: 0.2),
                      checkmarkColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: _selectedDepartment == 'all'
                            ? AppColors.primary
                            : AppColors.onSurfaceVariant,
                        fontWeight: _selectedDepartment == 'all'
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    FilterChip(
                      selected: _selectedDepartment == 'eye',
                      label: const Text('Eye Clinic'),
                      onSelected: (selected) {
                        setState(() =>
                            _selectedDepartment = selected ? 'eye' : 'all');
                      },
                      selectedColor:
                          AppColors.primaryContainer.withValues(alpha: 0.2),
                      checkmarkColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: _selectedDepartment == 'eye'
                            ? AppColors.primary
                            : AppColors.onSurfaceVariant,
                        fontWeight: _selectedDepartment == 'eye'
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    FilterChip(
                      selected: _selectedDepartment == 'dental',
                      label: const Text('Dental Clinic'),
                      onSelected: (selected) {
                        setState(() =>
                            _selectedDepartment = selected ? 'dental' : 'all');
                      },
                      selectedColor:
                          AppColors.primaryContainer.withValues(alpha: 0.2),
                      checkmarkColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: _selectedDepartment == 'dental'
                            ? AppColors.primary
                            : AppColors.onSurfaceVariant,
                        fontWeight: _selectedDepartment == 'dental'
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // ── Patient List View ──────────────────────────────────────────
            patientsAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) => _ErrorRetry(
                error: e,
                onRetry: () => ref.invalidate(patientSearchProvider),
              ),
              data: (patients) {
                // Ensure unique patient rows by patient.id to avoid duplicate rows
                final seenIds = <String>{};
                final uniquePatients = <PatientModel>[];
                for (final p in patients) {
                  if (seenIds.add(p.id)) {
                    uniquePatients.add(p);
                  }
                }

                if (uniquePatients.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.people_outline,
                              size: 48, color: AppColors.outline),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'No patients matching "$_searchQuery"'
                                : 'No patients found',
                            style: AppTypography.headlineMd
                                .copyWith(color: AppColors.onSurfaceVariant),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'Try checking the spelling or search by phone number.'
                                : 'Patients registered in the clinic will appear here.',
                            style: AppTypography.bodySm
                                .copyWith(color: AppColors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionHeader(
                      title: _searchQuery.isNotEmpty
                          ? 'SEARCH RESULTS'
                          : 'ALL PATIENTS',
                      count: uniquePatients.length,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ...uniquePatients.map((patient) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: _StaffPatientCard(patient: patient),
                      );
                    }),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.color,
  });

  final String title;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Text(
            title,
            style: AppTypography.labelCaps.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: AppTypography.dataMono.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Staff Patient Card ────────────────────────────────────────────────────────

class _StaffPatientCard extends StatelessWidget {
  const _StaffPatientCard({required this.patient});

  final PatientModel patient;

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final deptLabel = patient.department == 'eye'
        ? 'Eye'
        : patient.department == 'dental'
            ? 'Dental'
            : (patient.department?.toUpperCase() ?? 'GENERAL');

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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Avatar & Info Clickable Area ───────────────────────
              Expanded(
                child: InkWell(
                  key: Key('staff_patient_card_${patient.id}'),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            PatientDetailsScreen(patientId: patient.id),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      // ── Avatar ─────────────────────────────────────
                      CircleAvatar(
                        backgroundColor:
                            AppColors.primaryContainer.withValues(alpha: 0.2),
                        radius: 26,
                        child: Text(
                          _initials(patient.name),
                          style: AppTypography.labelCaps.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),

                      // ── Patient Info ───────────────────────────────
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              children: [
                                Text(
                                  patient.name,
                                  style: AppTypography.headlineMd
                                      .copyWith(fontSize: 17),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    patient.patientNumber,
                                    style: AppTypography.dataMono.copyWith(
                                      fontSize: 12,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.base),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.secondaryContainer
                                        .withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    deptLabel,
                                    style: AppTypography.labelCaps.copyWith(
                                      color: AppColors.secondary,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                                if (patient.dob != null) ...[
                                  const SizedBox(width: AppSpacing.xs),
                                  Text(
                                    '${DateTime.now().year - patient.dob!.year}y',
                                    style: AppTypography.bodySm.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                                if (patient.mobile != null &&
                                    patient.mobile!.isNotEmpty) ...[
                                  const SizedBox(width: AppSpacing.xs),
                                  const Icon(Icons.phone_outlined,
                                      size: 13, color: AppColors.outline),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      patient.mobile!,
                                      style: AppTypography.bodySm.copyWith(
                                        color: AppColors.onSurfaceVariant,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: AppSpacing.sm),

              // ── Call button ─────────────────────────────────────────
              _PatientCallButton(patient: patient),

              const SizedBox(width: AppSpacing.xs),

              // ── Chevron ─────────────────────────────────────────────
              IconButton(
                icon: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: AppColors.outline,
                ),
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
      ),
    );
  }
}

// ── Patient Call Button ───────────────────────────────────────────────────────

class _PatientCallButton extends StatelessWidget {
  const _PatientCallButton({required this.patient});

  final PatientModel patient;

  @override
  Widget build(BuildContext context) {
    final hasValidPhone = PhoneDialerUtil.isValidPhoneNumber(patient.mobile);

    return FilledButton.icon(
      key: Key('staff_patient_call_${patient.id}'),
      onPressed: hasValidPhone
          ? () => PhoneDialerUtil.openDialer(context, patient.mobile)
          : () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  backgroundColor: AppColors.error,
                  content: Text('Phone number unavailable or invalid.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
      icon: const Icon(Icons.phone, size: 16),
      label: const Text('Call'),
      style: FilledButton.styleFrom(
        backgroundColor:
            hasValidPhone ? AppColors.primary : AppColors.outlineVariant,
        foregroundColor: hasValidPhone ? Colors.white : AppColors.outline,
        textStyle: AppTypography.labelCaps.copyWith(fontSize: 11),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
          const Text('Unable to load patients.'),
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
