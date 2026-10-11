import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/mkes_primary_button.dart';
import '../../../shared/widgets/mkes_text_field.dart';
import '../../department/providers/departments_provider.dart';
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
    this.existingAppointment,
  });

  final DateTime? initialDate;
  final String? initialPatientId;
  final String? initialPatientName;
  final String initialAppointmentType;
  final AppointmentModel? existingAppointment;

  bool get isEditing => existingAppointment != null;

  static const List<({String id, String label})> availableAppointmentTypes = [
    (id: 'regular', label: 'Regular Visit'),
    (id: 'walk_in', label: 'Walk-in'),
    (id: 'follow_up', label: 'Follow-up'),
  ];

  static String normalizeAppointmentType(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'regular';
    final normalized = raw.trim().toLowerCase().replaceAll('-', '_');
    if (normalized == 'follow_up' || normalized == 'followup') {
      return 'follow_up';
    }
    if (normalized == 'walk_in' || normalized == 'walkin') {
      return 'walk_in';
    }
    if (normalized == 'regular') {
      return 'regular';
    }
    return raw.trim();
  }

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
  String? _searchError;
  int _searchRequestId = 0;

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

  static List<({String id, String label})> get availableAppointmentTypes =>
      AppointmentFormDialog.availableAppointmentTypes;

  static String normalizeAppointmentType(String? raw) =>
      AppointmentFormDialog.normalizeAppointmentType(raw);


  @override
  void initState() {
    super.initState();
    if (widget.existingAppointment != null) {
      final existing = widget.existingAppointment!;
      _selectedDepartment = existing.department;
      _selectedDate = existing.appointmentDate;
      _selectedType = normalizeAppointmentType(existing.appointmentType);
      _selectedPatientId = existing.patientId ?? widget.initialPatientId;
      _selectedPatientName = existing.patientName ?? widget.initialPatientName;
      _selectedPatientNumber = existing.patientNumber;
      _selectedDoctorId = existing.doctorId;
      _selectedDoctorName = existing.doctorName;
      _selectedDoctorSpecialty = existing.specialty;
      final parsedTime = _parseTimeOfDay(existing.appointmentTime);
      if (parsedTime != null) _selectedTime = parsedTime;
      _notesController = TextEditingController(text: existing.notes ?? '');
    } else {
      _selectedDate = widget.initialDate ?? DateTime.now();
      _selectedType = normalizeAppointmentType(widget.initialAppointmentType);
      _selectedPatientId = widget.initialPatientId;
      _selectedPatientName = widget.initialPatientName;
      _notesController = TextEditingController();
    }
  }

  TimeOfDay? _parseTimeOfDay(String timeText) {
    final normalized = timeText.trim();
    if (normalized.isEmpty) return null;

    final pieces = normalized.split(':');
    if (pieces.length < 2) return null;

    final hour = int.tryParse(pieces[0]);
    final minute = int.tryParse(pieces[1]);
    if (hour == null || minute == null) return null;

    return TimeOfDay(hour: hour, minute: minute);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ── Dept-filtered patient search (server-side Supabase) ──
  Future<void> _runSearch(String query) async {
    final requestId = ++_searchRequestId;
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      setState(() {
        _searchQuery = '';
        _searchResults = [];
        _searchError = null;
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchQuery = normalizedQuery;
      _searchError = null;
    });
    final department = _selectedDepartment;
    try {
      final repo = ref.read(patientRepositoryProvider);
      final results = await repo.fetchPatients(
        department: department,
        searchQuery: normalizedQuery,
      );
      if (mounted && requestId == _searchRequestId) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
          _searchError = null;
        });
      }
    } catch (error) {
      if (mounted && requestId == _searchRequestId) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
          _searchError = error.toString();
        });
      }
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
      _selectedDoctorId = null;
      _selectedDoctorName = null;
      _selectedDoctorSpecialty = null;
      _searchController.clear();
      _searchQuery = '';
      _searchResults = [];
      _searchError = null;
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
      _searchResults = [];
      _searchError = null;
    });
  }

  void _clearPatient() {
    setState(() {
      _selectedPatientId = null;
      _selectedPatientName = null;
      _selectedPatientNumber = null;
      _searchResults = [];
      _searchError = null;
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
      if (widget.isEditing && widget.existingAppointment != null) {
        final updates = <String, dynamic>{
          'patient_id': _selectedPatientId,
          'department': _selectedDepartment,
          'doctor_id': _selectedDoctorId,
          'appointment_date': _selectedDate.toIso8601String().split('T').first,
          'appointment_time': _formatTimeOfDay(_selectedTime),
          'appointment_type': _selectedType,
          'status': _selectedType == 'walk_in' ? 'waiting' : 'scheduled',
          if (_notesController.text.trim().isNotEmpty) 'notes': _notesController.text.trim(),
          if (_notesController.text.trim().isEmpty) 'notes': null,
        };

        await ref
            .read(appointmentsNotifierProvider.notifier)
            .updateAppointment(widget.existingAppointment!.id, updates);
      } else {
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
      }

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
                    widget.isEditing
                        ? 'Appointment for ${_selectedPatientName ?? "Patient"} updated successfully!'
                        : 'Appointment for ${_selectedPatientName ?? "Patient"} booked successfully!',
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
            content: Text(widget.isEditing
                ? 'Failed to update appointment: $e'
                : 'Failed to create appointment: $e'),
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
    final departmentsAsync = ref.watch(departmentsProvider);
    final matchingDepartments = departmentsAsync.value
            ?.where(
              (department) =>
                  department.isActive &&
                  department.name.toLowerCase().contains(_selectedDepartment),
            )
            .toList() ??
        [];
    final selectedDepartmentId =
        matchingDepartments.length == 1 ? matchingDepartments.single.id : null;
    final candidatesAsync = selectedDepartmentId == null
        ? null
        : ref.watch(
            appointmentStaffCandidatesProvider(selectedDepartmentId),
          );
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final viewInsets = MediaQuery.viewInsetsOf(context);

    final dialogMaxWidth = (screenWidth - 32).clamp(280.0, 580.0);
    final dialogMaxHeight =
        (screenHeight - viewInsets.bottom - 60).clamp(320.0, 780.0);

    final isEditing = widget.isEditing;

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
                          isEditing ? 'Edit Appointment' : 'New Appointment',
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
                              isExpanded: true,
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
                                  child: Text(
                                    'Eye Clinic',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'dental',
                                  child: Text(
                                    'Dental Clinic',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) _onDepartmentChanged(val);
                              },
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final Map<String, String> typesMap = {
                                  for (final item in availableAppointmentTypes)
                                    item.id: item.label,
                                };
                                final canonicalSelected =
                                    normalizeAppointmentType(_selectedType);
                                if (!typesMap.containsKey(canonicalSelected)) {
                                  typesMap[canonicalSelected] = canonicalSelected
                                      .split('_')
                                      .map((w) => w.isEmpty
                                          ? ''
                                          : '${w[0].toUpperCase()}${w.substring(1)}')
                                      .join(' ');
                                }
                                final safeValue = typesMap.containsKey(canonicalSelected)
                                    ? canonicalSelected
                                    : 'regular';

                                return DropdownButtonFormField<String>(
                                  key: ValueKey(safeValue),
                                  initialValue: safeValue,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: 'Type *',
                                    prefixIcon: const Icon(
                                        Icons.medical_services_outlined),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppSpacing.radiusMd),
                                    ),
                                  ),
                                  items: typesMap.entries.map((entry) {
                                    return DropdownMenuItem<String>(
                                      value: entry.key,
                                      child: Text(
                                        entry.value,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => _selectedType =
                                          normalizeAppointmentType(val));
                                    }
                                  },
                                );
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
                              _searchResults = [];
                              _searchError = null;
                            });
                          },
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('+ New Patient'),
                        ),
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // 3. Attending Doctor
                      Text(
                        'Attending Doctor',
                        style: AppTypography.labelCaps
                            .copyWith(color: AppColors.primary),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      if (departmentsAsync.isLoading)
                        const LinearProgressIndicator()
                      else if (departmentsAsync.hasError)
                        Text(
                          'Error loading departments: '
                          '${departmentsAsync.error}',
                        )
                      else if (matchingDepartments.isEmpty)
                        Text(
                          'No active ${_selectedDepartment == 'eye' ? 'Eye' : 'Dental'} department is configured.',
                        )
                      else if (matchingDepartments.length > 1)
                        Text(
                          'More than one active ${_selectedDepartment == 'eye' ? 'Eye' : 'Dental'} department was found.',
                        )
                      else
                        candidatesAsync!.when(
                          loading: () => const LinearProgressIndicator(),
                          error: (error, _) => Text(
                            'Error loading department staff: $error',
                          ),
                          data: (candidates) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DropdownButtonFormField<String?>(
                                initialValue: _selectedDoctorId,
                                decoration: InputDecoration(
                                  labelText: 'Attending Doctor',
                                  prefixIcon:
                                      const Icon(Icons.person_pin_outlined),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppSpacing.radiusMd,
                                    ),
                                  ),
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Unassigned (General Queue)'),
                                  ),
                                  ...candidates.map(
                                    (candidate) => DropdownMenuItem<String?>(
                                      value: candidate.id,
                                      child: Text(
                                        candidate.fullName,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _selectedDoctorId = value;
                                    final match = candidates
                                        .where(
                                          (candidate) => candidate.id == value,
                                        )
                                        .firstOrNull;
                                    _selectedDoctorName = match?.fullName;
                                    _selectedDoctorSpecialty = null;
                                  });
                                },
                              ),
                              if (candidates.isEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(top: AppSpacing.xs),
                                  child: Text(
                                    'No active staff found in this department.',
                                    style: AppTypography.bodySm.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                            ],
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
                      onPressed:
                          _isLoading ? null : () => Navigator.of(context).pop(),
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
                          label: isEditing ? 'Update Appointment' : 'Book Appointment',
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
                  style: AppTypography.bodyMd
                      .copyWith(fontWeight: FontWeight.w600),
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

    if (_searchQuery.isEmpty) return const SizedBox.shrink();

    if (_searchError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(
          'Could not search patients: $_searchError',
          style: AppTypography.bodySm.copyWith(color: AppColors.error),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(
          'No ${_selectedDepartment == "eye" ? "Eye" : "Dental"} patients match "$_searchQuery".',
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
                            style: AppTypography.bodySm
                                .copyWith(color: AppColors.onSurfaceVariant),
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
}
