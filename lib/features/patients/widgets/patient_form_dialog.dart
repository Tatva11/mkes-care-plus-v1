import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/mkes_primary_button.dart';
import '../../../shared/widgets/mkes_text_field.dart';
import '../models/patient_model.dart';
import '../providers/patients_provider.dart';

class PatientFormDialog extends ConsumerStatefulWidget {
  const PatientFormDialog({
    super.key,
    this.initialDepartment = 'eye',
  });

  final String initialDepartment;

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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _mobileController = TextEditingController();
    _addressController = TextEditingController();
    _referenceController = TextEditingController();
    _selectedDepartment = widget.initialDepartment;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final newPatient = PatientModel(
        id: '', // Will be assigned by Supabase
        patientNumber: '',
        name: _nameController.text.trim(),
        mobile: _mobileController.text.trim().isNotEmpty
            ? _mobileController.text.trim()
            : null,
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to register patient: $e'),
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                          ),
                          child: const Icon(
                            Icons.person_add_alt_1,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'Register New Patient',
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
                          Text('ASSIGNED IDENTIFIER',
                              style: AppTypography.labelCaps),
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
                              '${_selectedDepartment == 'eye' ? 'E' : 'D'} (assigned on save)',
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
                      Row(
                        children: [
                          Expanded(
                            child: MkesTextField(
                              controller: _mobileController,
                              label: 'Phone Number',
                              hintText: '+1 (555) 000-0000',
                              keyboardType: TextInputType.phone,
                              prefixIcon: Icons.phone_outlined,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
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
                                if (val != null) {
                                  setState(() => _selectedDepartment = val);
                                }
                              },
                            ),
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
                          label: 'Register Patient',
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
