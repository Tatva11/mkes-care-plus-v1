import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../appointments/models/appointment_model.dart';
import '../../appointments/repositories/appointment_repository.dart';
import '../../patients/models/patient_model.dart';
import '../models/eye_examination_model.dart';
import '../providers/eye_examination_provider.dart';

/// Modal dialog for recording or editing an eye clinical examination.
class EyeExaminationFormDialog extends ConsumerStatefulWidget {
  const EyeExaminationFormDialog({
    super.key,
    required this.patient,
    this.initialRecord,
  });

  final PatientModel patient;
  final EyeExaminationModel? initialRecord;

  @override
  ConsumerState<EyeExaminationFormDialog> createState() =>
      _EyeExaminationFormDialogState();
}

class _EyeExaminationFormDialogState
    extends ConsumerState<EyeExaminationFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late DateTime _examinationDate;
  TimeOfDay? _examinationTime;

  String? _selectedAppointmentId;
  List<AppointmentModel> _patientAppointments = [];
  bool _isLoadingAppointments = true;

  late TextEditingController _vaOdController;
  late TextEditingController _vaOsController;
  late TextEditingController _vaNotesController;

  late TextEditingController _iopOdController;
  late TextEditingController _iopOsController;
  late TextEditingController _iopNotesController;

  late TextEditingController _slitLampController;
  late TextEditingController _diagnosisController;
  late TextEditingController _clinicalNotesController;

  bool _isSaving = false;
  String? _errorMessage;

  static const Color _successColor = Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    final init = widget.initialRecord;

    _examinationDate = init?.examinationDate ?? DateTime.now();

    if (init?.examinationTime != null && init!.examinationTime!.isNotEmpty) {
      final parts = init.examinationTime!.split(':');
      if (parts.length >= 2) {
        final h = int.tryParse(parts[0]) ?? 9;
        final m = int.tryParse(parts[1]) ?? 0;
        _examinationTime = TimeOfDay(hour: h, minute: m);
      }
    } else if (init == null) {
      _examinationTime = TimeOfDay.now();
    }

    _selectedAppointmentId = init?.appointmentId;

    _vaOdController =
        TextEditingController(text: init?.visualAcuityOd ?? '');
    _vaOsController =
        TextEditingController(text: init?.visualAcuityOs ?? '');
    _vaNotesController =
        TextEditingController(text: init?.visualAcuity ?? '');

    _iopOdController =
        TextEditingController(text: init?.intraocularPressureOd ?? '');
    _iopOsController =
        TextEditingController(text: init?.intraocularPressureOs ?? '');
    _iopNotesController =
        TextEditingController(text: init?.intraocularPressure ?? '');

    _slitLampController =
        TextEditingController(text: init?.slitLampExamination ?? '');
    _diagnosisController =
        TextEditingController(text: init?.diagnosis ?? '');
    _clinicalNotesController =
        TextEditingController(text: init?.clinicalNotes ?? '');

    _loadAppointments();
  }

  Future<void> _loadAppointments() async {
    try {
      final aptRepo = ref.read(appointmentRepositoryProvider);
      final list = await aptRepo.fetchPatientAppointments(
        patientId: widget.patient.id,
        department: 'eye',
      );
      if (mounted) {
        setState(() {
          _patientAppointments = list;
          _isLoadingAppointments = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingAppointments = false);
      }
    }
  }

  @override
  void dispose() {
    _vaOdController.dispose();
    _vaOsController.dispose();
    _vaNotesController.dispose();
    _iopOdController.dispose();
    _iopOsController.dispose();
    _iopNotesController.dispose();
    _slitLampController.dispose();
    _diagnosisController.dispose();
    _clinicalNotesController.dispose();
    super.dispose();
  }

  String? get _formattedTimeOfDay {
    if (_examinationTime == null) return null;
    final h = _examinationTime!.hour.toString().padLeft(2, '0');
    final m = _examinationTime!.minute.toString().padLeft(2, '0');
    return '$h:$m:00';
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _examinationDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _examinationDate = picked);
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _examinationTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _examinationTime = picked);
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    final hasDiagnosis = _diagnosisController.text.trim().isNotEmpty;
    final hasNotes = _clinicalNotesController.text.trim().isNotEmpty;
    final hasVA = _vaOdController.text.trim().isNotEmpty ||
        _vaOsController.text.trim().isNotEmpty ||
        _vaNotesController.text.trim().isNotEmpty;
    final hasIOP = _iopOdController.text.trim().isNotEmpty ||
        _iopOsController.text.trim().isNotEmpty ||
        _iopNotesController.text.trim().isNotEmpty;
    final hasSlit = _slitLampController.text.trim().isNotEmpty;

    if (!hasDiagnosis && !hasNotes && !hasVA && !hasIOP && !hasSlit) {
      setState(() {
        _errorMessage =
            'Please fill at least one clinical section (Diagnosis, Visual Acuity, IOP, Slit Lamp, or Notes).';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final isEdit = widget.initialRecord != null;
      final controller = ref.read(eyeExaminationControllerProvider.notifier);

      final record = EyeExaminationModel(
        id: widget.initialRecord?.id ?? '',
        patientId: widget.patient.id,
        appointmentId: _selectedAppointmentId,
        eyeSurgeryId: widget.initialRecord?.eyeSurgeryId,
        examinationDate: _examinationDate,
        examinationTime: _formattedTimeOfDay,
        visualAcuityOd: _vaOdController.text.trim().isEmpty
            ? null
            : _vaOdController.text.trim(),
        visualAcuityOs: _vaOsController.text.trim().isEmpty
            ? null
            : _vaOsController.text.trim(),
        visualAcuity: _vaNotesController.text.trim().isEmpty
            ? null
            : _vaNotesController.text.trim(),
        intraocularPressureOd: _iopOdController.text.trim().isEmpty
            ? null
            : _iopOdController.text.trim(),
        intraocularPressureOs: _iopOsController.text.trim().isEmpty
            ? null
            : _iopOsController.text.trim(),
        intraocularPressure: _iopNotesController.text.trim().isEmpty
            ? null
            : _iopNotesController.text.trim(),
        slitLampExamination: _slitLampController.text.trim().isEmpty
            ? null
            : _slitLampController.text.trim(),
        diagnosis: _diagnosisController.text.trim().isEmpty
            ? null
            : _diagnosisController.text.trim(),
        clinicalNotes: _clinicalNotesController.text.trim().isEmpty
            ? null
            : _clinicalNotesController.text.trim(),
        createdBy: widget.initialRecord?.createdBy,
        createdAt: widget.initialRecord?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
        patientName: widget.patient.name,
        patientNumber: widget.patient.patientNumber,
      );

      EyeExaminationModel result;
      if (isEdit) {
        result = await controller.updateExamination(record);
      } else {
        result = await controller.createExamination(record);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEdit
                  ? 'Examination record updated successfully.'
                  : 'Clinical examination recorded successfully.',
            ),
            backgroundColor: _successColor,
          ),
        );
        Navigator.of(context).pop<EyeExaminationModel>(result);
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
                        Icons.visibility_outlined,
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
                                ? 'Edit Eye Clinical Examination'
                                : 'Record Eye Clinical Examination',
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

                // Date & Time row
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _selectDate,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Examination Date *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.calendar_today_outlined),
                          ),
                          child: Text(
                            DateFormat('dd MMM yyyy').format(_examinationDate),
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
                            labelText: 'Examination Time',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.access_time_outlined),
                          ),
                          child: Text(
                            _examinationTime != null
                                ? _examinationTime!.format(context)
                                : 'Select Time',
                            style: AppTypography.bodyMd,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // Related Appointment Dropdown
                if (!_isLoadingAppointments && _patientAppointments.isNotEmpty) ...[
                  DropdownButtonFormField<String?>(
                    initialValue: _selectedAppointmentId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Linked Appointment (Optional)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.event_note_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('None / Unlinked Examination'),
                      ),
                      ..._patientAppointments.map((apt) {
                        final formattedDate =
                            DateFormat('dd MMM yyyy').format(apt.appointmentDate);
                        return DropdownMenuItem<String?>(
                          value: apt.id,
                          child: Text(
                            '$formattedDate at ${apt.appointmentTime} (${apt.appointmentType})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
                    onChanged: (val) => setState(() => _selectedAppointmentId = val),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // Diagnosis field
                TextFormField(
                  controller: _diagnosisController,
                  decoration: const InputDecoration(
                    labelText: 'Clinical Diagnosis',
                    border: OutlineInputBorder(),
                    hintText: 'e.g. Cataract, Primary Open-Angle Glaucoma, Refractive Error',
                    prefixIcon: Icon(Icons.healing_outlined),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Visual Acuity Section
                _buildSectionHeader('Visual Acuity (VA)', Icons.remove_red_eye_outlined),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _vaOdController,
                        decoration: const InputDecoration(
                          labelText: 'Right Eye (OD)',
                          border: OutlineInputBorder(),
                          hintText: 'e.g. 6/6, 20/20',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextFormField(
                        controller: _vaOsController,
                        decoration: const InputDecoration(
                          labelText: 'Left Eye (OS)',
                          border: OutlineInputBorder(),
                          hintText: 'e.g. 6/9, 20/30',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                TextFormField(
                  controller: _vaNotesController,
                  decoration: const InputDecoration(
                    labelText: 'VA Remarks / Refraction Notes',
                    border: OutlineInputBorder(),
                    hintText: 'e.g. With pinhole 6/6, near vision N6 with +2.00D',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Intraocular Pressure (IOP) Section
                _buildSectionHeader('Intraocular Pressure (IOP)', Icons.speed_outlined),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _iopOdController,
                        decoration: const InputDecoration(
                          labelText: 'OD IOP (mmHg)',
                          border: OutlineInputBorder(),
                          hintText: 'e.g. 14',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextFormField(
                        controller: _iopOsController,
                        decoration: const InputDecoration(
                          labelText: 'OS IOP (mmHg)',
                          border: OutlineInputBorder(),
                          hintText: 'e.g. 16',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                TextFormField(
                  controller: _iopNotesController,
                  decoration: const InputDecoration(
                    labelText: 'Tonometry Method / Remarks',
                    border: OutlineInputBorder(),
                    hintText: 'e.g. Goldmann Applanation, Non-Contact Tonometry',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Slit Lamp Examination Section
                _buildSectionHeader('Slit-Lamp Examination Notes', Icons.biotech_outlined),
                const SizedBox(height: AppSpacing.xs),
                TextFormField(
                  controller: _slitLampController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        'Cornea clear, anterior chamber deep and quiet, iris normal, lens status, fundus / disc evaluation...',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Clinical Notes & Management Plan
                _buildSectionHeader('Clinical Notes & Management Plan', Icons.assignment_outlined),
                const SizedBox(height: AppSpacing.xs),
                TextFormField(
                  controller: _clinicalNotesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        'Prescribed eye drops, advised cataract surgery evaluation, follow-up in 2 weeks...',
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
                      label: Text(_isSaving ? 'Saving...' : (isEdit ? 'Update Record' : 'Save Examination')),
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

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: AppSpacing.xs),
        Text(
          title,
          style: AppTypography.bodyMd.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
