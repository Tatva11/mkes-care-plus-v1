import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/responsive_page_header.dart';
import '../../appointments/models/department_doctor_config.dart';
import '../widgets/admin_shell.dart';

class DoctorManagementScreen extends StatelessWidget {
  const DoctorManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      selectedItem: AdminNavItem.administration,
      onNavItemSelected: (item) {
        if (item == AdminNavItem.dashboard) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          return;
        }
      },
      body: const DoctorManagementContent(),
    );
  }
}

class DoctorManagementContent extends ConsumerStatefulWidget {
  const DoctorManagementContent({super.key});

  @override
  ConsumerState<DoctorManagementContent> createState() =>
      _DoctorManagementContentState();
}

class _DoctorManagementContentState
    extends ConsumerState<DoctorManagementContent> {
  String _selectedDepartmentFilter = 'all'; // 'all' | 'eye' | 'dental'
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showDoctorDialog({DepartmentDoctor? doctor}) {
    showDialog(
      context: context,
      builder: (ctx) => _DoctorFormDialog(
        doctor: doctor,
        initialDepartment: _selectedDepartmentFilter == 'all'
            ? 'eye'
            : _selectedDepartmentFilter,
      ),
    );
  }

  void _confirmToggleDoctor(DepartmentDoctor doctor) {
    final willDeactivate = doctor.isActive;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(willDeactivate ? 'Deactivate Doctor' : 'Activate Doctor'),
        content: Text(
          willDeactivate
              ? 'Deactivating "${doctor.fullName}" will prevent them from being selected for new appointments.\n\nExisting and historical appointments will continue to display this doctor\'s name.'
              : 'Activating "${doctor.fullName}" will make them immediately available for new ${doctor.department == "eye" ? "Eye" : "Dental"} appointment bookings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await ref
                    .read(adminDoctorsProvider.notifier)
                    .toggleDoctorActive(doctor);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        willDeactivate
                            ? '${doctor.fullName} deactivated.'
                            : '${doctor.fullName} activated.',
                      ),
                      backgroundColor: willDeactivate
                          ? AppColors.onSurfaceVariant
                          : AppColors.primaryContainer,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to update doctor: $e'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor:
                  willDeactivate ? AppColors.error : AppColors.primary,
            ),
            child: Text(willDeactivate ? 'Deactivate' : 'Activate'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 768;
    final doctorsAsync = ref.watch(adminDoctorsProvider);

    return SingleChildScrollView(
      padding: EdgeInsets.all(
        isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header & Breadcrumbs ─────────────────────────────────────────
          ResponsivePageHeader(
            title: 'Doctor Management',
            subtitle:
                'Configure department static doctors for appointment booking. No Auth accounts required.',
            showBackButton: true,
            onBack: () => Navigator.of(context).pop(),
            actions: [
              FilledButton.icon(
                onPressed: () => _showDoctorDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Doctor'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Filters & Search Bar ─────────────────────────────────────────
          if (isDesktop)
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('All Departments'),
                  selected: _selectedDepartmentFilter == 'all',
                  onSelected: (_) =>
                      setState(() => _selectedDepartmentFilter = 'all'),
                ),
                ChoiceChip(
                  label: const Text('Eye Department'),
                  selected: _selectedDepartmentFilter == 'eye',
                  onSelected: (_) =>
                      setState(() => _selectedDepartmentFilter = 'eye'),
                ),
                ChoiceChip(
                  label: const Text('Dental Department'),
                  selected: _selectedDepartmentFilter == 'dental',
                  onSelected: (_) =>
                      setState(() => _selectedDepartmentFilter = 'dental'),
                ),
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 280,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) =>
                        setState(() => _searchQuery = val.trim()),
                    decoration: InputDecoration(
                      hintText: 'Search doctor name or specialty...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('All Departments'),
                        selected: _selectedDepartmentFilter == 'all',
                        onSelected: (_) =>
                            setState(() => _selectedDepartmentFilter = 'all'),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      ChoiceChip(
                        label: const Text('Eye Department'),
                        selected: _selectedDepartmentFilter == 'eye',
                        onSelected: (_) =>
                            setState(() => _selectedDepartmentFilter = 'eye'),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      ChoiceChip(
                        label: const Text('Dental Department'),
                        selected: _selectedDepartmentFilter == 'dental',
                        onSelected: (_) => setState(
                            () => _selectedDepartmentFilter = 'dental'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search doctor name or specialty...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.lg),

          // ── Doctor List ──────────────────────────────────────────────────
          doctorsAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.error, size: 36),
                    const SizedBox(height: AppSpacing.sm),
                    Text('Failed to load doctors: $e'),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton(
                      onPressed: () =>
                          ref.read(adminDoctorsProvider.notifier).loadDoctors(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
            data: (allDoctors) {
              var filtered = allDoctors;

              if (_selectedDepartmentFilter != 'all') {
                filtered = filtered
                    .where((d) =>
                        d.department.toLowerCase().trim() ==
                        _selectedDepartmentFilter)
                    .toList();
              }

              if (_searchQuery.isNotEmpty) {
                final q = _searchQuery.toLowerCase();
                filtered = filtered.where((d) {
                  final nameMatch = d.fullName.toLowerCase().contains(q);
                  final specMatch =
                      (d.specialty ?? '').toLowerCase().contains(q);
                  return nameMatch || specMatch;
                }).toList();
              }

              if (filtered.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_off_outlined,
                            size: 48, color: AppColors.outline),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'No doctors found',
                          style: AppTypography.headlineMd
                              .copyWith(color: AppColors.onSurfaceVariant),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'No doctors match "$_searchQuery".'
                              : 'No doctors configured for this department.',
                          style: AppTypography.bodySm
                              .copyWith(color: AppColors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Column(
                children: filtered.map((doctor) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      side: const BorderSide(color: AppColors.outlineVariant),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: doctor.department == 'eye'
                            ? AppColors.primaryContainer.withValues(alpha: 0.15)
                            : AppColors.secondaryContainer
                                .withValues(alpha: 0.2),
                        child: Icon(
                          doctor.department == 'eye'
                              ? Icons.visibility_outlined
                              : Icons.medical_services_outlined,
                          color: doctor.department == 'eye'
                              ? AppColors.primary
                              : AppColors.secondary,
                          size: 20,
                        ),
                      ),
                      title: Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            doctor.fullName,
                            style: AppTypography.bodyLg.copyWith(
                              fontWeight: FontWeight.bold,
                              decoration: doctor.isActive
                                  ? null
                                  : TextDecoration.lineThrough,
                              color: doctor.isActive
                                  ? AppColors.onSurface
                                  : AppColors.onSurfaceVariant,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: doctor.department == 'eye'
                                  ? AppColors.primary.withValues(alpha: 0.1)
                                  : AppColors.secondary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              doctor.department == 'eye' ? 'EYE' : 'DENTAL',
                              style: AppTypography.labelCaps.copyWith(
                                color: doctor.department == 'eye'
                                    ? AppColors.primary
                                    : AppColors.secondary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: doctor.isActive
                                  ? Colors.green.withValues(alpha: 0.12)
                                  : AppColors.errorContainer
                                      .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              doctor.isActive ? 'ACTIVE' : 'INACTIVE',
                              style: AppTypography.labelCaps.copyWith(
                                color: doctor.isActive
                                    ? Colors.green.shade800
                                    : AppColors.error,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        doctor.specialty ??
                            (doctor.department == 'eye'
                                ? 'Ophthalmology'
                                : 'Dentistry'),
                        style: AppTypography.bodySm
                            .copyWith(color: AppColors.onSurfaceVariant),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            tooltip: 'Edit doctor',
                            onPressed: () => _showDoctorDialog(doctor: doctor),
                          ),
                          IconButton(
                            icon: Icon(
                              doctor.isActive
                                  ? Icons.toggle_on
                                  : Icons.toggle_off_outlined,
                              size: 28,
                              color: doctor.isActive
                                  ? Colors.green
                                  : AppColors.outline,
                            ),
                            tooltip: doctor.isActive
                                ? 'Deactivate doctor'
                                : 'Activate doctor',
                            onPressed: () => _confirmToggleDoctor(doctor),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DoctorFormDialog extends ConsumerStatefulWidget {
  const _DoctorFormDialog({
    this.doctor,
    this.initialDepartment = 'eye',
  });

  final DepartmentDoctor? doctor;
  final String initialDepartment;

  @override
  ConsumerState<_DoctorFormDialog> createState() => _DoctorFormDialogState();
}

class _DoctorFormDialogState extends ConsumerState<_DoctorFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _specialtyController;
  late String _selectedDepartment;
  bool _isActive = true;
  bool _isSaving = false;

  bool get isEditing => widget.doctor != null;

  @override
  void initState() {
    super.initState();
    final d = widget.doctor;
    _nameController = TextEditingController(text: d?.fullName ?? '');
    _specialtyController = TextEditingController(text: d?.specialty ?? '');
    _selectedDepartment = d?.department ?? widget.initialDepartment;
    _isActive = d?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _specialtyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final name = _nameController.text.trim();
      final specialty = _specialtyController.text.trim().isNotEmpty
          ? _specialtyController.text.trim()
          : null;

      if (isEditing) {
        await ref.read(adminDoctorsProvider.notifier).editDoctor(
              id: widget.doctor!.id,
              fullName: name,
              department: _selectedDepartment,
              specialty: specialty,
              isActive: _isActive,
            );
      } else {
        await ref.read(adminDoctorsProvider.notifier).addDoctor(
              fullName: name,
              department: _selectedDepartment,
              specialty: specialty,
            );
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEditing
                ? 'Doctor updated successfully.'
                : 'Doctor added successfully.'),
            backgroundColor: AppColors.primaryContainer,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save doctor: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isEditing ? 'Edit Doctor' : 'Add New Doctor'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Doctor Name *',
                    hintText: 'e.g. Dr Mitesh Jain',
                    prefixIcon: const Icon(Icons.person_pin_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter doctor name';
                    }
                    if (!val.trim().toLowerCase().startsWith('dr')) {
                      // Optional gentle suggestion but allow standard entry
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _selectedDepartment,
                  decoration: InputDecoration(
                    labelText: 'Department *',
                    prefixIcon: const Icon(Icons.local_hospital_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'eye', child: Text('Eye Department')),
                    DropdownMenuItem(
                        value: 'dental', child: Text('Dental Department')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedDepartment = val);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _specialtyController,
                  decoration: InputDecoration(
                    labelText: 'Specialty (Optional)',
                    hintText: 'e.g. Ophthalmology, Dental Surgery',
                    prefixIcon: const Icon(Icons.medical_services_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                  ),
                ),
                if (isEditing) ...[
                  const SizedBox(height: AppSpacing.md),
                  SwitchListTile(
                    title: const Text('Active for Bookings'),
                    subtitle: const Text(
                        'When inactive, doctor cannot be chosen for new appointments.'),
                    value: _isActive,
                    onChanged: (val) => setState(() => _isActive = val),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Static doctors appear in the booking dropdown without creating user accounts or auth logins.',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEditing ? 'Save Changes' : 'Add Doctor'),
        ),
      ],
    );
  }
}
