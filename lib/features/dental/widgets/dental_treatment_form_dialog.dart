import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../appointments/models/appointment_model.dart';
import '../../appointments/repositories/appointment_repository.dart';
import '../../patients/models/patient_model.dart';
import '../models/dental_lab_model.dart';
import '../models/dental_treatment_model.dart';
import '../providers/dental_lab_provider.dart';
import '../providers/dental_treatment_provider.dart';

/// Modal dialog for recording or editing a dental clinical treatment record.
class DentalTreatmentFormDialog extends ConsumerStatefulWidget {
  const DentalTreatmentFormDialog({
    super.key,
    required this.patient,
    this.initialRecord,
  });

  final PatientModel patient;
  final DentalTreatmentModel? initialRecord;

  @override
  ConsumerState<DentalTreatmentFormDialog> createState() =>
      _DentalTreatmentFormDialogState();
}

class _DentalTreatmentFormDialogState
    extends ConsumerState<DentalTreatmentFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late DateTime _treatmentDate;
  TimeOfDay? _treatmentTime;

  String? _selectedAppointmentId;
  String? _selectedDentalLabCaseId;

  List<AppointmentModel> _patientAppointments = [];
  List<DentalLabModel> _patientLabCases = [];
  bool _isLoadingDropdowns = true;

  late TextEditingController _toothNumberController;
  late TextEditingController _procedureController;
  late TextEditingController _diagnosisController;
  late TextEditingController _treatmentNotesController;

  String _procedureStatus = 'completed';
  bool _isSaving = false;
  String? _errorMessage;

  static const Color _successColor = Color(0xFF2E7D32);

  static const List<String> _suggestedProcedures = [
    'Scaling & Polishing',
    'Composite Restoration (Filling)',
    'Root Canal Treatment (RCT)',
    'Simple Tooth Extraction',
    'Surgical Extraction / Impaction',
    'Crown Preparation & Impression',
    'Bridge Placement',
    'Denture Delivery & Adjustment',
    'Fluoride Application',
    'Dental Pit & Fissure Sealant',
    'Gingival Curettage',
  ];

  @override
  void initState() {
    super.initState();
    final init = widget.initialRecord;

    _treatmentDate = init?.treatmentDate ?? DateTime.now();

    if (init?.treatmentTime != null && init!.treatmentTime!.isNotEmpty) {
      final parts = init.treatmentTime!.split(':');
      if (parts.length >= 2) {
        final h = int.tryParse(parts[0]) ?? 9;
        final m = int.tryParse(parts[1]) ?? 0;
        _treatmentTime = TimeOfDay(hour: h, minute: m);
      }
    } else if (init == null) {
      _treatmentTime = TimeOfDay.now();
    }

    _selectedAppointmentId = init?.appointmentId;
    _selectedDentalLabCaseId = init?.dentalLabCaseId;
    _procedureStatus = init?.procedureStatus ?? 'completed';

    _toothNumberController =
        TextEditingController(text: init?.toothNumber ?? '');
    _procedureController =
        TextEditingController(text: init?.procedurePerformed ?? '');
    _diagnosisController =
        TextEditingController(text: init?.diagnosis ?? '');
    _treatmentNotesController =
        TextEditingController(text: init?.treatmentNotes ?? '');

    _loadRelatedEntities();
  }

  Future<void> _loadRelatedEntities() async {
    try {
      final aptRepo = ref.read(appointmentRepositoryProvider);
      final labRepo = ref.read(dentalLabRepositoryProvider);

      final aptFuture = aptRepo.fetchPatientAppointments(
        patientId: widget.patient.id,
        department: 'dental',
      );
      final labFuture = labRepo.fetchCases(patientId: widget.patient.id);

      final results = await Future.wait([aptFuture, labFuture]);

      if (mounted) {
        setState(() {
          _patientAppointments = results[0] as List<AppointmentModel>;
          _patientLabCases = results[1] as List<DentalLabModel>;
          _isLoadingDropdowns = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingDropdowns = false);
      }
    }
  }

  @override
  void dispose() {
    _toothNumberController.dispose();
    _procedureController.dispose();
    _diagnosisController.dispose();
    _treatmentNotesController.dispose();
    super.dispose();
  }

  String? get _formattedTimeOfDay {
    if (_treatmentTime == null) return null;
    final h = _treatmentTime!.hour.toString().padLeft(2, '0');
    final m = _treatmentTime!.minute.toString().padLeft(2, '0');
    return '$h:$m:00';
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _treatmentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _treatmentDate = picked);
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _treatmentTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _treatmentTime = picked);
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    final procedure = _procedureController.text.trim();
    if (procedure.isEmpty) {
      setState(() => _errorMessage = 'Procedure performed is required.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final isEdit = widget.initialRecord != null;
      final controller = ref.read(dentalTreatmentControllerProvider.notifier);

      final record = DentalTreatmentModel(
        id: widget.initialRecord?.id ?? '',
        patientId: widget.patient.id,
        appointmentId: _selectedAppointmentId,
        dentalLabCaseId: _selectedDentalLabCaseId,
        treatmentDate: _treatmentDate,
        treatmentTime: _formattedTimeOfDay,
        toothNumber: _toothNumberController.text.trim().isEmpty
            ? null
            : _toothNumberController.text.trim(),
        procedurePerformed: procedure,
        treatmentNotes: _treatmentNotesController.text.trim().isEmpty
            ? null
            : _treatmentNotesController.text.trim(),
        diagnosis: _diagnosisController.text.trim().isEmpty
            ? null
            : _diagnosisController.text.trim(),
        procedureStatus: _procedureStatus,
        createdBy: widget.initialRecord?.createdBy,
        createdAt: widget.initialRecord?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
        patientName: widget.patient.name,
        patientNumber: widget.patient.patientNumber,
      );

      DentalTreatmentModel result;
      if (isEdit) {
        result = await controller.updateTreatment(record);
      } else {
        result = await controller.createTreatment(record);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEdit
                  ? 'Dental treatment record updated successfully.'
                  : 'Dental treatment recorded successfully.',
            ),
            backgroundColor: _successColor,
          ),
        );
        Navigator.of(context).pop<DentalTreatmentModel>(result);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = e.toString().replaceAll('Exception:', '').trim();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialRecord != null;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                      child: const Icon(
                        Icons.medical_services_outlined,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEdit
                                ? 'Edit Dental Clinical Treatment'
                                : 'Record Dental Clinical Treatment',
                            style: AppTypography.headlineMd.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Patient: ${widget.patient.name} (${widget.patient.patientNumber})',
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.errorContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.error, size: 20),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // Date & Time
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _selectDate,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Treatment Date *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.calendar_today_outlined),
                          ),
                          child: Text(
                            DateFormat('dd MMM yyyy').format(_treatmentDate),
                            style: AppTypography.bodyMd,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: InkWell(
                        onTap: _selectTime,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Treatment Time',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.access_time_outlined),
                          ),
                          child: Text(
                            _treatmentTime != null
                                ? _treatmentTime!.format(context)
                                : 'Select Time',
                            style: AppTypography.bodyMd,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // Procedure Performed (with suggestions autocomplete or text field)
                TextFormField(
                  controller: _procedureController,
                  decoration: InputDecoration(
                    labelText: 'Procedure Performed *',
                    border: const OutlineInputBorder(),
                    hintText: 'e.g. Root Canal Treatment, Composite Restoration',
                    prefixIcon: const Icon(Icons.healing_outlined),
                    suffixIcon: PopupMenuButton<String>(
                      icon: const Icon(Icons.arrow_drop_down),
                      tooltip: 'Select common procedure',
                      onSelected: (val) =>
                          setState(() => _procedureController.text = val),
                      itemBuilder: (_) => _suggestedProcedures
                          .map((p) => PopupMenuItem(value: p, child: Text(p)))
                          .toList(),
                    ),
                  ),
                  validator: (val) =>
                      val == null || val.trim().isEmpty ? 'Enter procedure' : null,
                ),
                const SizedBox(height: AppSpacing.md),

                // Tooth Number / Quadrant and Procedure Status row
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _toothNumberController,
                        decoration: const InputDecoration(
                          labelText: 'Tooth No. / Quadrant',
                          border: OutlineInputBorder(),
                          hintText: 'e.g. 16, 21, UR4, Upper Right',
                          prefixIcon: Icon(Icons.tag_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _procedureStatus,
                        decoration: const InputDecoration(
                          labelText: 'Procedure Status *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.task_alt_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'completed',
                            child: Text('Completed'),
                          ),
                          DropdownMenuItem(
                            value: 'in_progress',
                            child: Text('In Progress'),
                          ),
                          DropdownMenuItem(
                            value: 'planned',
                            child: Text('Planned'),
                          ),
                          DropdownMenuItem(
                            value: 'cancelled',
                            child: Text('Cancelled'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _procedureStatus = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // Diagnosis field
                TextFormField(
                  controller: _diagnosisController,
                  decoration: const InputDecoration(
                    labelText: 'Dental Diagnosis',
                    border: OutlineInputBorder(),
                    hintText: 'e.g. Deep Dental Caries, Irreversible Pulpitis, Periapical Abscess',
                    prefixIcon: Icon(Icons.local_hospital_outlined),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Related Appointment Dropdown
                if (_isLoadingDropdowns) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Text(
                          'Loading patient dental appointments...',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ] else ...[
                  DropdownButtonFormField<String?>(
                    initialValue: _selectedAppointmentId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Linked Dental Appointment (Optional)',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.event_note_outlined),
                      helperText: _patientAppointments.isEmpty
                          ? (_selectedAppointmentId != null
                              ? 'Preserving previously linked appointment'
                              : 'No dental appointments on record for this patient')
                          : 'Select an appointment for ${widget.patient.name}',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('None / Unlinked Appointment'),
                      ),
                      if (_selectedAppointmentId != null &&
                          !_patientAppointments.any((a) => a.id == _selectedAppointmentId))
                        DropdownMenuItem<String?>(
                          value: _selectedAppointmentId,
                          child: Text(
                            widget.initialRecord?.appointmentDate != null
                                ? 'Linked: ${DateFormat('dd MMM yyyy').format(widget.initialRecord!.appointmentDate!)}${widget.initialRecord?.appointmentTime != null ? " at ${widget.initialRecord!.appointmentTime}" : ""}${widget.initialRecord?.appointmentStatus != null ? " • ${widget.initialRecord!.appointmentStatus!.toUpperCase()}" : ""}'
                                : 'Linked Appointment (${_selectedAppointmentId!.length > 8 ? _selectedAppointmentId!.substring(0, 8) : _selectedAppointmentId})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ..._patientAppointments.map((apt) {
                        final formattedDate =
                            DateFormat('dd MMM yyyy').format(apt.appointmentDate);
                        final statusLabel = apt.status.toUpperCase();
                        return DropdownMenuItem<String?>(
                          value: apt.id,
                          child: Text(
                            '$formattedDate at ${apt.appointmentTime} • $statusLabel (${apt.appointmentType})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
                    onChanged: (val) => setState(() => _selectedAppointmentId = val),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // Related Dental Lab Case Dropdown
                if (!_isLoadingDropdowns && (_patientLabCases.isNotEmpty || _selectedDentalLabCaseId != null)) ...[
                  DropdownButtonFormField<String?>(
                    initialValue: _selectedDentalLabCaseId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Linked Dental Lab Case (Optional)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.science_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('None / No Lab Case'),
                      ),
                      if (_selectedDentalLabCaseId != null &&
                          !_patientLabCases.any((l) => l.id == _selectedDentalLabCaseId))
                        DropdownMenuItem<String?>(
                          value: _selectedDentalLabCaseId,
                          child: Text(
                            widget.initialRecord?.dentalLabCaseNumber != null
                                ? 'Case #${widget.initialRecord!.dentalLabCaseNumber} (${widget.initialRecord?.dentalLabCaseType ?? "Lab"})'
                                : 'Linked Lab Case (${_selectedDentalLabCaseId!.length > 8 ? _selectedDentalLabCaseId!.substring(0, 8) : _selectedDentalLabCaseId})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ..._patientLabCases.map((lab) {
                        return DropdownMenuItem<String?>(
                          value: lab.id,
                          child: Text(
                            'Case #${lab.caseNumber} - ${lab.caseType} (${lab.status.toUpperCase()})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
                    onChanged: (val) => setState(() => _selectedDentalLabCaseId = val),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // Treatment Notes
                Text(
                  'Treatment Notes & Observations',
                  style: AppTypography.bodyMd.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                TextFormField(
                  controller: _treatmentNotesController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        'Anaesthesia administered (2% Lignocaine with Adrenaline), cavity excavated, pulp capping done, composite shaded A2 cured, occlusion checked...',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check),
                      label: Text(_isSaving ? 'Saving...' : (isEdit ? 'Update Record' : 'Save Treatment')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
