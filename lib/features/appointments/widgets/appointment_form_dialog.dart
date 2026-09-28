import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/mkes_primary_button.dart';
import '../../../shared/widgets/mkes_text_field.dart';
import '../../admin/models/user_profile.dart';
import '../../admin/providers/users_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../patients/models/patient_model.dart';
import '../../patients/repositories/patient_repository.dart';
import '../../patients/widgets/patient_form_dialog.dart';
import '../models/appointment_model.dart';
import '../providers/appointment_provider.dart';

class AppointmentFormDialog extends ConsumerStatefulWidget {
  const AppointmentFormDialog({
    super.key,
    this.initialDate,
    this.initialPatientId,
    this.initialPatientName,
    this.initialAppointmentType = 'regular',
  });

  final DateTime? initialDate;
  final String? initialPatientId;
  final String? initialPatientName;
  final String initialAppointmentType;

  @override
  ConsumerState<AppointmentFormDialog> createState() =>
      _AppointmentFormDialogState();
}

class _AppointmentFormDialogState extends ConsumerState<AppointmentFormDialog> {
  final _formKey = GlobalKey<FormState>();

  // ── patient ──
  String? _selectedPatientId;
  String? _selectedPatientName;
  String? _selectedPatientNumber;

  // ── search ──
  final _searchController = TextEditingController();
  String _searchQuery = '';
  List<PatientModel> _searchResults = [];
  bool _isSearching = false;

  // ── department / type ──
  String _selectedDepartment = 'eye';
  String? _selectedDoctorId;
  String? _selectedDoctorName;
  String? _selectedDoctorSpecialty;
  late DateTime _selectedDate;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 9, minute: 0);
  late String _selectedType;
  late final TextEditingController _notesController;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _selectedType = widget.initialAppointmentType;
    _selectedPatientId = widget.initialPatientId;
    _selectedPatientName = widget.initialPatientName;
    _notesController = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runSearch('');
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ── Dept-filtered patient search (server-side Supabase) ──
  Future<void> _runSearch(String query) async {
    setState(() {
      _isSearching = true;
      _searchQuery = query;
    });
    try {
      final repo = ref.read(patientRepositoryProvider);
      final results = await repo.fetchPatients(
        department: _selectedDepartment,
        searchQuery: query.trim().isEmpty ? null : query.trim(),
      );
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  // ── When department changes: clear mismatched patient & reload search ──
  void _onDepartmentChanged(String newDept) {
    setState(() {
      if (_selectedPatientId != null) {
        final patientDept = _searchResults
            .where((p) => p.id == _selectedPatientId)
            .firstOrNull
            ?.department
            ?.toLowerCase();
        if (patientDept != newDept) {
          _selectedPatientId = null;
          _selectedPatientName = null;
          _selectedPatientNumber = null;
        }
      }
      _selectedDepartment = newDept;
      _searchController.clear();
      _searchQuery = '';
    });
    _runSearch('');
  }

  void _selectPatient(PatientModel patient) {
    setState(() {
      _selectedPatientId = patient.id;
      _selectedPatientName = patient.name;
      _selectedPatientNumber = patient.patientNumber;
      if (patient.department == 'eye' || patient.department == 'dental') {
        _selectedDepartment = patient.department!;
      }
      _searchController.clear();
      _searchQuery = '';
    });
  }

  void _clearPatient() {
    setState(() {
      _selectedPatientId = null;
      _selectedPatientName = null;
      _selectedPatientNumber = null;
    });
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute:00';
  }

  String _formatDisplayTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final newAppointment = AppointmentModel(
        id: '',
        patientId: _selectedPatientId,
        patientName: _selectedPatientName ?? 'Walk-in Patient',
        patientNumber: _selectedPatientNumber ?? 'Unknown ID',
        department: _selectedDepartment,
        doctorId: _selectedDoctorId,
        doctorName: _selectedDoctorName,
        specialty: _selectedDoctorSpecialty,
        appointmentDate: _selectedDate,
        appointmentTime: _formatTimeOfDay(_selectedTime),
        appointmentType: _selectedType,
        status: _selectedType == 'walk_in' ? 'waiting' : 'scheduled',
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
        aiBooked: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await ref
          .read(appointmentsNotifierProvider.notifier)
          .createAppointment(newAppointment);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.primaryContainer,
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Appointment for ${_selectedPatientName ?? "Patient"} booked successfully!',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create appointment: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(usersProvider);
    final profileAsync = ref.watch(currentProfileProvider);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final viewInsets = MediaQuery.viewInsetsOf(context);

    final dialogMaxWidth = (screenWidth - 32).clamp(280.0, 580.0);
    final dialogMaxHeight =
        (screenHeight - viewInsets.bottom - 60).clamp(320.0, 780.0);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogMaxWidth,
          maxHeight: dialogMaxHeight,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ──
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.outlineVariant),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer
                                .withValues(alpha: 0.15),
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                          ),
                          child: const Icon(
                            Icons.calendar_month,
                            color: AppColors.primaryContainer,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'New Appointment',
                          style: AppTypography.headlineMd,
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      color: AppColors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),

              // ── Form Body ──
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Department & Type (FIRST so patient list is filtered by dept)
                      Text(
                        'Department & Type',
                        style: AppTypography.labelCaps
                            .copyWith(color: AppColors.primary),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedDepartment,
                              decoration: InputDecoration(
                                labelText: 'Department *',
                                prefixIcon:
                                    const Icon(Icons.local_hospital_outlined),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppSpacing.radiusMd),
                                ),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'eye',
                                  child: Text('Eye Clinic'),
                                ),
                                DropdownMenuItem(
                                  value: 'dental',
                                  child: Text('Dental Clinic'),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) _onDepartmentChanged(val);
                              },
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedType,
                              decoration: InputDecoration(
                                labelText: 'Type *',
                                prefixIcon:
                                    const Icon(Icons.medical_services_outlined),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppSpacing.radiusMd),
                                ),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'regular',
                                  child: Text('Regular Visit'),
                                ),
                                DropdownMenuItem(
                                  value: 'walk_in',
                                  child: Text('Walk-in'),
                                ),
                                DropdownMenuItem(
                                  value: 'follow_up',
                                  child: Text('Follow-up'),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedType = val);
                                }
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // 2. Patient Search & Selection (department-filtered, server-side)
                      Text(
                        'Patient Information',
                        style: AppTypography.labelCaps
                            .copyWith(color: AppColors.primary),
                      ),
                      const SizedBox(height: AppSpacing.xs),

                      if (_selectedPatientId != null)
                        _buildSelectedPatientChip()
                      else ...[
                        TextFormField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            labelText: 'Search Patient *',
                            hintText:
                                '${_selectedDepartment == "eye" ? "Eye" : "Dental"} patient — name, number, or mobile',
                            prefixIcon:
                                const Icon(Icons.person_search_outlined),
                            suffixIcon: _isSearching
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: Padding(
                                      padding: EdgeInsets.all(12),
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  )
                                : (_searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          _searchController.clear();
                                          _runSearch('');
                                        },
                                      )
                                    : null),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusMd),
                            ),
                          ),
                          onChanged: _runSearch,
                          validator: (_) => _selectedPatientId == null
                              ? 'Please select a patient'
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        _buildSearchResults(),
                      ],

                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () async {
                            final created = await showDialog<PatientModel>(
                              context: context,
                              builder: (_) => PatientFormDialog(
                                initialDepartment: _selectedDepartment,
                              ),
                            );
                            if (created == null || !mounted) return;
                            setState(() {
                              _selectedPatientId = created.id;
                              _selectedPatientName = created.name;
                              _selectedPatientNumber = created.patientNumber;
                              if (created.department == 'eye' ||
                                  created.department == 'dental') {
                                _selectedDepartment = created.department!;
                              }
                              _searchController.clear();
                              _searchQuery = '';
                            });
                            _runSearch('');
                          },
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('+ New Patient'),
                        ),
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // 3. Attending Doctor / Clinical Staff
                      Text(
                        'Clinical Staff Assignment',
                        style: AppTypography.labelCaps
                            .copyWith(color: AppColors.primary),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      usersAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (e, _) => Text('Error loading staff: $e'),
                        data: (users) {
                          final staffMembers =
                              users.where((u) => u.isActive).toList();
                          return DropdownButtonFormField<String?>(
                            initialValue: _selectedDoctorId,
                            decoration: InputDecoration(
                              labelText: 'Attending Doctor / Specialist',
                              prefixIcon: const Icon(Icons.person_pin_outlined),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppSpacing.radiusMd),
                              ),
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Unassigned (General Queue)'),
                              ),
                              ...staffMembers.map(
                                (UserProfile u) => DropdownMenuItem<String?>(
                                  value: u.id,
                                  child: Text(
                                    '${u.fullName} (${u.designation ?? u.role})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (val) {
                              setState(() {
                                _selectedDoctorId = val;
                                final match = staffMembers
                                    .where((u) => u.id == val)
                                    .firstOrNull;
                                if (match != null) {
                                  _selectedDoctorName = match.fullName;
                                  _selectedDoctorSpecialty = match.designation;
                                } else {
                                  _selectedDoctorName = null;
                                  _selectedDoctorSpecialty = null;
                                }
                              });
                            },
                          );
                        },
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // 4. Created By — auto-resolved from authenticated profile (read-only)
                      Text(
                        'Created By',
                        style: AppTypography.labelCaps
                            .copyWith(color: AppColors.primary),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      profileAsync.when(
                        loading: () => _createdByContainer(
                          child: const Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Text('Loading staff info...'),
                            ],
                          ),
                        ),
                        error: (e, _) => _createdByContainer(
                          isError: true,
                          child: Text(
                            'Could not resolve staff: $e',
                            style: const TextStyle(color: AppColors.error),
                          ),
                        ),
                        data: (profile) => _createdByContainer(
                          child: Row(
                            children: [
                              const Icon(
                                Icons.verified_user_outlined,
                                color: AppColors.primary,
                                size: 20,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  profile?.fullName ?? 'Unknown Staff',
                                  style: AppTypography.bodyMd,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryContainer
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Auto',
                                  style: AppTypography.labelCaps.copyWith(
                                    color: AppColors.primaryContainer,
                                    fontSize: 9,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // 5. Date & Time Selection
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _selectedDate,
                                  firstDate: DateTime.now()
                                      .subtract(const Duration(days: 30)),
                                  lastDate: DateTime.now()
                                      .add(const Duration(days: 365)),
                                );
                                if (picked != null) {
                                  setState(() => _selectedDate = picked);
                                }
                              },
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Date *',
                                  prefixIcon:
                                      const Icon(Icons.calendar_today_outlined),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusMd),
                                  ),
                                ),
                                child: Text(
                                  '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                                  style: AppTypography.bodyMd,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: _selectedTime,
                                );
                                if (picked != null) {
                                  setState(() => _selectedTime = picked);
                                }
                              },
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Time Slot *',
                                  prefixIcon:
                                      const Icon(Icons.access_time_outlined),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusMd),
                                  ),
                                ),
                                child: Text(
                                  _formatDisplayTime(_selectedTime),
                                  style: AppTypography.bodyMd,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // 6. Clinical Notes  (Room / Suite field removed entirely)
                      MkesTextField(
                        controller: _notesController,
                        label: 'Clinical Notes / Chief Complaint',
                        hintText:
                            'e.g., Routine vision screening, IOP check, follow-up',
                        maxLines: 3,
                        prefixIcon: Icons.note_alt_outlined,
                      ),
                    ],
                  ),
                ),
              ),

              // ── Footer ──
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppColors.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    if (_isLoading)
                      const Expanded(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      Expanded(
                        child: MkesPrimaryButton(
                          label: 'Book Appointment',
                          onPressed: _submit,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widget helpers ──

  Widget _buildSelectedPatientChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
            color: AppColors.primaryContainer.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.person, color: AppColors.primaryContainer, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedPatientName ?? '',
                  style:
                      AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
                ),
                if (_selectedPatientNumber != null)
                  Text(
                    _selectedPatientNumber!,
                    style: AppTypography.labelCaps
                        .copyWith(color: AppColors.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: _clearPatient,
            color: AppColors.onSurfaceVariant,
            tooltip: 'Change patient',
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_isSearching) return const SizedBox.shrink();

    if (_searchResults.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(
          _searchQuery.isEmpty
              ? 'No ${_selectedDepartment == "eye" ? "Eye" : "Dental"} patients found. Use "+ New Patient" to register one.'
              : 'No ${_selectedDepartment == "eye" ? "Eye" : "Dental"} patients match "$_searchQuery".',
          style:
              AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
        ),
      );
    }

    final visible = _searchResults.take(6).toList();

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        children: [
          for (int i = 0; i < visible.length; i++) ...[
            InkWell(
              borderRadius: BorderRadius.vertical(
                top: i == 0
                    ? const Radius.circular(AppSpacing.radiusMd)
                    : Radius.zero,
                bottom: i == visible.length - 1
                    ? const Radius.circular(AppSpacing.radiusMd)
                    : Radius.zero,
              ),
              onTap: () => _selectPatient(visible[i]),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor:
                          AppColors.primaryContainer.withValues(alpha: 0.15),
                      child: Text(
                        visible[i].name.isNotEmpty
                            ? visible[i].name[0].toUpperCase()
                            : '?',
                        style: AppTypography.labelCaps
                            .copyWith(color: AppColors.primaryContainer),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(visible[i].name, style: AppTypography.bodyMd),
                          Text(
                            '${visible[i].patientNumber}'
                            '${visible[i].mobile != null ? " \u00b7 ${visible[i].mobile}" : ""}',
                            style: AppTypography.bodySm.copyWith(
                                color: AppColors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: AppColors.onSurfaceVariant, size: 18),
                  ],
                ),
              ),
            ),
            if (i < visible.length - 1)
              const Divider(height: 1, color: AppColors.outlineVariant),
          ],
          if (_searchResults.length > 6)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Text(
                '+${_searchResults.length - 6} more \u2014 refine your search.',
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _createdByContainer({
    required Widget child,
    bool isError = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: isError
            ? AppColors.errorContainer.withValues(alpha: 0.2)
            : AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: isError
              ? AppColors.error.withValues(alpha: 0.3)
              : AppColors.outlineVariant,
        ),
      ),
      child: child,
    );
  }
}
