import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/mkes_primary_button.dart';
import '../../../shared/widgets/mkes_text_field.dart';
import '../../../shared/widgets/responsive_form_row.dart';
import '../models/patient_model.dart';
import '../providers/patients_provider.dart';

class PatientFormDialog extends ConsumerStatefulWidget {
  const PatientFormDialog({
    super.key,
    this.initialDepartment = 'eye',
    this.patient,
  });

  final String initialDepartment;
  final PatientModel? patient;

  @override
  ConsumerState<PatientFormDialog> createState() => _PatientFormDialogState();
}

class _PatientFormDialogState extends ConsumerState<PatientFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _mobileController;
  late final TextEditingController _addressController;
  late final TextEditingController _referenceController;

  late String _selectedDepartment;
  DateTime? _selectedDob;
  bool _isLoading = false;

  bool get _isEditing => widget.patient != null;

  @override
  void initState() {
    super.initState();
    final p = widget.patient;
    _nameController = TextEditingController(text: p?.name ?? '');
    _mobileController = TextEditingController(text: p?.mobile ?? '');
    _addressController = TextEditingController(text: p?.address ?? '');
    _referenceController = TextEditingController(text: p?.reference ?? '');
    _selectedDepartment = p?.department ?? widget.initialDepartment;
    _selectedDob = p?.dob;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
    _referenceController.dispose();
    super.dispose();
  }


  String _sanitizeMobile(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('91') && digits.length == 12) {
      digits = digits.substring(2);
    } else if (digits.startsWith('0') && digits.length == 11) {
      digits = digits.substring(1);
    }
    return digits;
  }

  /// Validates a standard Indian 10-digit mobile number.
  /// Valid: starts with 6, 7, 8, or 9 and is exactly 10 digits after sanitization.
  String? _validateIndianMobile(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // Mobile is optional — only validate if provided.
    }
    final digits = _sanitizeMobile(value.trim());
    if (digits.length != 10) {
      return 'Mobile number must be exactly 10 digits';
    }
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) {
      return 'Enter a valid Indian mobile number (starts with 6, 7, 8, or 9)';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final rawMobile = _mobileController.text.trim();
      final sanitizedMobile =
          rawMobile.isNotEmpty ? _sanitizeMobile(rawMobile) : null;

      if (_isEditing) {
        final existing = widget.patient!;
        final updatedPatient = existing.copyWith(
          name: _nameController.text.trim(),
          mobile: sanitizedMobile,
          department: _selectedDepartment,
          dob: _selectedDob,
          address: _addressController.text.trim().isNotEmpty
              ? _addressController.text.trim()
              : null,
          reference: _referenceController.text.trim().isNotEmpty
              ? _referenceController.text.trim()
              : null,
          updatedAt: DateTime.now(),
        );

        final saved = await ref
            .read(patientsProvider.notifier)
            .updatePatient(updatedPatient);

        ref.invalidate(patientDetailsProvider(saved.id));
        ref.invalidate(patientsByDepartmentProvider('eye'));
        ref.invalidate(patientsByDepartmentProvider('dental'));
        ref.invalidate(patientSearchProvider);

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
                      'Patient ${saved.name} (${saved.patientNumber}) updated successfully!',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          );
          Navigator.of(context).pop(saved);
        }
      } else {
        final newPatient = PatientModel(
          id: '', // Will be assigned by Supabase
          patientNumber: '',
          name: _nameController.text.trim(),
          mobile: sanitizedMobile,
          department: _selectedDepartment,
          dob: _selectedDob,
          address: _addressController.text.trim().isNotEmpty
              ? _addressController.text.trim()
              : null,
          reference: _referenceController.text.trim().isNotEmpty
              ? _referenceController.text.trim()
              : null,
          visitDate: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final created =
            await ref.read(patientsProvider.notifier).createPatient(newPatient);

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
                      'Patient ${created.name} (${created.patientNumber}) registered successfully!',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          );
          Navigator.of(context).pop(created);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing
                ? 'Failed to update patient: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}'
                : 'Failed to register patient: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final viewInsets = MediaQuery.viewInsetsOf(context);

    final dialogMaxWidth = (screenWidth - 32).clamp(280.0, 520.0);
    final dialogMaxHeight =
        (screenHeight - viewInsets.bottom - 60).clamp(320.0, 680.0);

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
              // Dialog Header
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
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusSm),
                            ),
                            child: Icon(
                              _isEditing
                                  ? Icons.edit_outlined
                                  : Icons.person_add_alt_1,
                              color: AppColors.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              _isEditing ? 'Edit Patient' : 'Register New Patient',
                              style: AppTypography.headlineMd,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      color: AppColors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),

              // Form Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Patient ID Badge preview
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _isEditing
                                ? 'PATIENT NUMBER'
                                : 'ASSIGNED IDENTIFIER',
                            style: AppTypography.labelCaps,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(4),
                              border:
                                  Border.all(color: AppColors.outlineVariant),
                            ),
                            child: Text(
                              _isEditing
                                  ? widget.patient!.patientNumber
                                  : '${_selectedDepartment == 'eye' ? 'E' : 'D'} (assigned on save)',
                              style: AppTypography.dataMono.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // Full Name
                      MkesTextField(
                        controller: _nameController,
                        label: 'Full Name *',
                        hintText: 'e.g. Alexander Graham',
                        prefixIcon: Icons.badge_outlined,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Full Name is required'
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Contact & Department
                      ResponsiveFormRow(
                        breakpoint: 440,
                        children: [
                          MkesTextField(
                            controller: _mobileController,
                            label: 'Mobile Number',
                            hintText: '9876543210',
                            keyboardType: TextInputType.number,
                            prefixIcon: Icons.phone_outlined,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[\d\s+\-]')),
                              LengthLimitingTextInputFormatter(16),
                            ],
                            validator: _validateIndianMobile,
                          ),
                          DropdownButtonFormField<String>(
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
                              if (val != null) {
                                setState(() => _selectedDepartment = val);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // DOB Picker
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime(1995, 1, 1),
                            firstDate: DateTime(1900),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setState(() => _selectedDob = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Date of Birth (Optional)',
                            prefixIcon: const Icon(Icons.cake_outlined),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusMd),
                            ),
                          ),
                          child: Text(
                            _selectedDob != null
                                ? '${_selectedDob!.day}/${_selectedDob!.month}/${_selectedDob!.year}'
                                : 'Select Date of Birth',
                            style: AppTypography.bodyMd.copyWith(
                              color: _selectedDob != null
                                  ? AppColors.onSurface
                                  : AppColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Address
                      MkesTextField(
                        controller: _addressController,
                        label: 'Residential Address',
                        hintText: 'Street, City, State / Region',
                        prefixIcon: Icons.home_outlined,
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Reference
                      MkesTextField(
                        controller: _referenceController,
                        label: 'Referred By / Reference',
                        hintText: 'Self / Dr. Vance / Walk-in',
                        prefixIcon: Icons.connect_without_contact_outlined,
                      ),
                    ],
                  ),
                ),
              ),

              // Dialog Footer
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
                          label: _isEditing ? 'Save Changes' : 'Register Patient',
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
}
