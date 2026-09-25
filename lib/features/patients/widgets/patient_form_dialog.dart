import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../department/providers/departments_provider.dart';
import '../models/patient.dart';
import '../providers/patient_provider.dart';

/// Allowed department values as enforced by the DB check constraint
/// `patients_department_check`.  The dropdown is populated from the live
/// departments table, but this list acts as a compile-time guard for direct
/// usages.
const _kAllowedDepartments = Patient.allowedDepartments;

/// A self-contained dialog for creating or editing a Patient.
///
/// Lifecycle is fully owned by this widget:
/// * All [TextEditingController]s are created in [initState] and disposed in
///   [dispose].
/// * Every `await` is followed by an `if (!mounted) return` guard.
/// * Cancel is a plain synchronous [Navigator.pop] — no async work, no
///   setState, no provider calls.
/// * On error, the form stays open and displays an inline error banner.
class PatientFormDialog extends ConsumerStatefulWidget {
  const PatientFormDialog({super.key, this.patient});

  /// When [patient] is non-null the dialog operates in Edit mode.
  final Patient? patient;

  @override
  ConsumerState<PatientFormDialog> createState() => _PatientFormDialogState();
}

class _PatientFormDialogState extends ConsumerState<PatientFormDialog> {
  // ── Form key ────────────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();

  // ── Controllers ─────────────────────────────────────────────────────────────
  late final TextEditingController _nameController;
  late final TextEditingController _mobileController;
  late final TextEditingController _addressController;
  late final TextEditingController _referenceController;

  // ── Non-text state ───────────────────────────────────────────────────────────
  String? _selectedDepartment;
  DateTime? _dateOfBirth;

  // ── UI state ─────────────────────────────────────────────────────────────────
  bool _isLoading = false;
  String? _errorMessage;

  bool get _isCreating => widget.patient == null;

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    final p = widget.patient;
    _nameController = TextEditingController(text: p?.fullName ?? '');
    _mobileController = TextEditingController(text: p?.mobile ?? '');
    _addressController = TextEditingController(text: p?.address ?? '');
    _referenceController = TextEditingController(text: p?.reference ?? '');
    _selectedDepartment = Patient.normalizeDepartment(p?.departmentName);
    _dateOfBirth = p?.dateOfBirth;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  // ── Save logic ────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    // 1. Validate form fields.
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // 2. Department is validated separately (it's a dropdown, not a text field).
    if (_selectedDepartment == null) {
      setState(() => _errorMessage = 'Please select a department.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isCreating) {
        await ref.read(patientsProvider.notifier).createPatient(
              fullName: _nameController.text.trim(),
              mobile: _mobileController.text.trim(),
              department: _selectedDepartment!,
              dateOfBirth: _dateOfBirth,
              address: _addressController.text.trim(),
              reference: _referenceController.text.trim(),
            );
      } else {
        await ref.read(patientsProvider.notifier).updatePatient(
              id: widget.patient!.id,
              fullName: _nameController.text.trim(),
              mobile: _mobileController.text.trim(),
              department: _selectedDepartment!,
              dateOfBirth: _dateOfBirth,
              address: _addressController.text.trim(),
              reference: _referenceController.text.trim(),
            );
      }

      // ── Only reach here on success ──────────────────────────────────────────
      if (!mounted) return;

      // Close the dialog and show a success snackbar on the underlying page.
      Navigator.of(context).pop();

      // Show success via the root scaffold messenger (survives dialog pop).
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              _isCreating ? 'Patient created successfully.' : 'Patient updated.'),
          backgroundColor: AppColors.primary,
        ),
      );
    } catch (e) {
      // ── Keep form open, show readable error ────────────────────────────────
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _friendlyError(e);
      });
    }
  }

  /// Converts raw Supabase / Dart errors to something user-friendly.
  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('patients_department_check')) {
      return 'Invalid department. Allowed values: ${_kAllowedDepartments.join(', ')}.';
    }
    if (msg.contains('patients_patient_number_key') ||
        msg.contains('unique constraint')) {
      return 'A patient with this registration number already exists.';
    }
    if (msg.contains('network') || msg.contains('SocketException')) {
      return 'Network error. Please check your connection and try again.';
    }
    // Strip Dart exception class prefix if present.
    if (msg.startsWith('Exception: ')) return msg.substring(11);
    return msg;
  }

  // ── Date pickers ──────────────────────────────────────────────────────────────

  Future<void> _pickDateOfBirth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(1990),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: 'Select Date of Birth',
    );
    if (!mounted) return;
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final departmentsState = ref.watch(departmentsProvider);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final viewInsets = MediaQuery.viewInsetsOf(context);

    final dialogMaxWidth = (screenWidth - 32).clamp(300.0, 560.0);
    final dialogMaxHeight =
        (screenHeight - viewInsets.bottom - 64).clamp(400.0, 700.0);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogMaxWidth,
          maxHeight: dialogMaxHeight,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Title ──────────────────────────────────────────────────
                Text(
                  _isCreating ? 'Add Patient' : 'Edit Patient',
                  style: AppTypography.headlineMd,
                ),
                const SizedBox(height: AppSpacing.md),

                // ── Inline error banner ────────────────────────────────────
                if (_errorMessage != null) ...[
                  _ErrorBanner(message: _errorMessage!),
                  const SizedBox(height: AppSpacing.sm),
                ],

                // ── Patient Name (required) ────────────────────────────────
                _buildField(
                  label: 'Patient Name *',
                  child: TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration:
                        _decoration('Full name', Icons.person_outline),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Name is required.' : null,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                // ── Mobile (required) ──────────────────────────────────────
                _buildField(
                  label: 'Mobile *',
                  child: TextFormField(
                    controller: _mobileController,
                    keyboardType: TextInputType.phone,
                    decoration:
                        _decoration('Phone number', Icons.phone_outlined),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Mobile number is required.';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                // ── Department (required) ──────────────────────────────────
                _buildField(
                  label: 'Department *',
                  child: departmentsState.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (err, _) => Text(
                      'Unable to load departments: $err',
                      style:
                          AppTypography.bodySm.copyWith(color: AppColors.error),
                    ),
                    data: (departments) {
                        final activeItems = departments
                          .where((d) =>
                            (d.isActive || d.name == _selectedDepartment) &&
                            Patient.normalizeDepartment(d.name) != null)
                          .toList();

                      // If the current value is not in the list, reset it.
                      if (_selectedDepartment != null &&
                          !activeItems
                              .any((d) =>
                                Patient.normalizeDepartment(d.name) ==
                                _selectedDepartment)) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            setState(() => _selectedDepartment = null);
                          }
                        });
                      }

                      return DropdownButtonFormField<String>(
                        initialValue: activeItems.any((d) =>
                            Patient.normalizeDepartment(d.name) ==
                            _selectedDepartment)
                          ? _selectedDepartment
                          : null,
                        decoration: InputDecoration(
                          hintText: 'Select department',
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusMd),
                            borderSide: const BorderSide(
                                color: AppColors.outlineVariant),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusMd),
                            borderSide: const BorderSide(
                                color: AppColors.outlineVariant),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusMd),
                            borderSide: const BorderSide(
                              color: AppColors.primaryContainer,
                              width: 1.5,
                            ),
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceContainerLow,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.sm,
                          ),
                          prefixIcon:
                              const Icon(Icons.business_outlined, size: 20),
                        ),
                        items: activeItems
                            .map((d) {
                              final value = Patient.normalizeDepartment(d.name)!;
                              return DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              );
                            })
                            .fold(<String, DropdownMenuItem<String>>{},
                                (items, item) {
                              items[item.value!] = item;
                              return items;
                            })
                            .values
                            .toList(),
                        onChanged: _isLoading
                            ? null
                            : (v) => setState(() =>
                              _selectedDepartment =
                                Patient.normalizeDepartment(v)),
                        validator: (v) =>
                            v == null ? 'Please select a department.' : null,
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                // ── Address (optional) ─────────────────────────────────────
                _buildField(
                  label: 'Address',
                  child: TextFormField(
                    controller: _addressController,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration:
                        _decoration('Street, city, etc.', Icons.home_outlined),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                // ── Reference (optional) ───────────────────────────────────
                _buildField(
                  label: 'Reference',
                  child: TextFormField(
                    controller: _referenceController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: _decoration(
                        'Referring doctor / source', Icons.info_outline),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                // ── Date of Birth (optional) ───────────────────────────────
                _buildField(
                  label: 'Date of Birth',
                  child: _DatePickerButton(
                    icon: Icons.cake_outlined,
                    placeholder: 'Select date of birth',
                    value: _dateOfBirth,
                    enabled: !_isLoading,
                    onTap: _pickDateOfBirth,
                    onClear: () => setState(() => _dateOfBirth = null),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                const SizedBox(height: AppSpacing.md),

                // ── Action buttons ─────────────────────────────────────────
                Row(
                  children: [
                    // Cancel — synchronous, zero async work.
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _isLoading
                          ? const Center(
                              child: SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : FilledButton(
                              onPressed: _save,
                              child: Text(
                                  _isCreating ? 'Add Patient' : 'Save Changes'),
                            ),
                    ),
                  ],
                ),

                // Extra space so the bottom button isn't hidden by the keyboard.
                SizedBox(height: viewInsets.bottom > 0 ? AppSpacing.md : 0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  Widget _buildField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelCaps.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }

  InputDecoration _decoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: const BorderSide(color: AppColors.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: const BorderSide(color: AppColors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: const BorderSide(
          color: AppColors.primaryContainer,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      filled: true,
      fillColor: AppColors.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
    );
  }
}

// ── Sub-widgets ─────────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.onErrorContainer,
              size: 20),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySm
                  .copyWith(color: AppColors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatePickerButton extends StatelessWidget {
  const _DatePickerButton({
    required this.icon,
    required this.placeholder,
    required this.value,
    required this.enabled,
    required this.onTap,
    required this.onClear,
  });

  final IconData icon;
  final String placeholder;
  final DateTime? value;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    final label = hasValue
        ? DateFormat('d MMM yyyy').format(value!)
        : placeholder;

    return OutlinedButton.icon(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 18),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMd.copyWith(
                color: hasValue
                    ? AppColors.onSurface
                    : AppColors.onSurfaceVariant,
              ),
            ),
          ),
          if (hasValue) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: enabled ? onClear : null,
              child: const Icon(Icons.close, size: 16),
            ),
          ],
        ],
      ),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        side: const BorderSide(color: AppColors.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        backgroundColor: AppColors.surfaceContainerLow,
        foregroundColor: AppColors.onSurface,
      ),
    );
  }
}
