import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/mkes_text_field.dart';
import '../../../shared/widgets/mkes_primary_button.dart';
import '../models/user_profile.dart';
import '../providers/users_provider.dart';
import '../../../shared/widgets/adaptive_dialog_shell.dart';
import '../../department/models/department.dart';
import '../../department/providers/departments_provider.dart';
import '../../notifications/repositories/notification_repository.dart';

class UserFormDialog extends ConsumerStatefulWidget {
  const UserFormDialog({super.key, this.user});
  final UserProfile? user;

  @override
  ConsumerState<UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends ConsumerState<UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _designationController;
  late final TextEditingController _salaryController;
  late final TextEditingController _joiningDateController;
  late final TextEditingController _passwordController;
  late final TextEditingController _confirmPasswordController;

  String _selectedRole = 'staff';
  String _assignedShift = 'morning';
  String? _selectedDepartmentId;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  bool get _isCreating => widget.user == null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user?.fullName);
    _emailController = TextEditingController(text: widget.user?.email);
    _phoneController = TextEditingController(text: widget.user?.phoneNumber);
    _designationController =
        TextEditingController(text: widget.user?.designation);
    _salaryController =
        TextEditingController(text: widget.user?.salary?.toString() ?? '');
    _joiningDateController = TextEditingController(
        text:
            widget.user?.joiningDate?.toIso8601String().split('T').first ?? '');
    _passwordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    if (widget.user != null) {
      _selectedRole = widget.user!.role;
      final shift = widget.user!.assignedShift.toLowerCase();
      _assignedShift = shift == 'night' ? 'afternoon' : shift;
      _selectedDepartmentId = widget.user!.departmentId;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _designationController.dispose();
    _salaryController.dispose();
    _joiningDateController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      if (_isCreating) {
        // Create new user
        await ref.read(usersProvider.notifier).createUser(
              fullName: _nameController.text.trim(),
              email: _emailController.text.trim(),
              password: _passwordController.text,
              phoneNumber: _phoneController.text.trim().isEmpty
                  ? null
                  : _phoneController.text.trim(),
              departmentId: _selectedDepartmentId,
              designation: _designationController.text.trim().isEmpty
                  ? null
                  : _designationController.text.trim(),
              role: _selectedRole,
              salary: _salaryController.text.trim().isEmpty
                  ? null
                  : double.tryParse(_salaryController.text.trim()),
              joiningDate: _joiningDateController.text.trim().isEmpty
                  ? null
                  : DateTime.tryParse(_joiningDateController.text.trim()),
            );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User created successfully.')),
          );
        }
      } else {
        // Edit existing user
        final oldShift = widget.user!.assignedShift.toLowerCase();
        final newShift = _assignedShift.toLowerCase();

        await ref.read(usersProvider.notifier).updateUser(widget.user!.id, {
          'full_name': _nameController.text.trim(),
          'phone_number': _phoneController.text.trim(),
          'department_id': _selectedDepartmentId,
          'designation': _designationController.text.trim(),
          'role': _selectedRole,
          'assigned_shift': _assignedShift,
          'salary': _salaryController.text.trim().isEmpty
              ? null
              : double.tryParse(_salaryController.text.trim()),
          'joining_date': _joiningDateController.text.trim().isEmpty
              ? null
              : _joiningDateController.text.trim(),
        });

        // Notify affected staff if duty changed
        if (widget.user!.role == 'staff' && oldShift != newShift) {
          try {
            final now = DateTime.now();
            final tomorrow = now.add(const Duration(days: 1));
            final effStr = DateFormat('d MMMM yyyy').format(tomorrow);
            final shiftLabel = newShift == 'both'
                ? 'Both (Morning & Evening)'
                : (newShift == 'afternoon' || newShift == 'evening'
                    ? 'Evening'
                    : 'Morning');

            await ref.read(notificationRepositoryProvider).insertNotification(
                  userId: widget.user!.id,
                  title: 'Duty Assignment Updated',
                  message:
                      'Your shift effective $effStr has been changed to $shiftLabel.',
                  type: 'duty_assignment',
                  idempotent: true,
                );
          } catch (notifErr) {
            debugPrint('Failed to send duty change notification: $notifErr');
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User updated.')),
          );
        }
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()), backgroundColor: AppColors.error),
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
    final departmentsState = ref.watch(departmentsProvider);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final dialogConstraints = AdaptiveDialogConstraints.getConstraints(
      context: context,
      maxPhoneWidth: 460,
      maxTabletWidth: 500,
      maxDesktopWidth: 520,
    );

    return Dialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
      // insetPadding keeps the dialog from touching screen edges on small phones.
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: dialogConstraints,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isCreating ? 'Add New User' : 'Edit User',
                  style: AppTypography.headlineMd,
                ),
                const SizedBox(height: AppSpacing.md),
                MkesTextField(
                  controller: _nameController,
                  label: 'Full Name',
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                MkesTextField(
                  controller: _emailController,
                  label: 'Email Address',
                  keyboardType: TextInputType.emailAddress,
                  enabled:
                      _isCreating, // Prevent editing email for existing users
                  validator: (v) {
                    if (v!.isEmpty) return 'Required';
                    final emailRegex =
                        RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                    if (!emailRegex.hasMatch(v)) return 'Invalid email format';
                    return null;
                  },
                ),
                // Password fields — only shown when creating a new user
                if (_isCreating) ...[
                  const SizedBox(height: AppSpacing.md),
                  MkesTextField(
                    controller: _passwordController,
                    label: 'Password',
                    hintText: 'Minimum 6 characters',
                    prefixIcon: Icons.lock_outlined,
                    obscureText: _obscurePassword,
                    suffix: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.onSurfaceVariant,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Password is required';
                      if (v.length < 6) return 'Minimum 6 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  MkesTextField(
                    controller: _confirmPasswordController,
                    label: 'Confirm Password',
                    hintText: 'Re-enter password',
                    prefixIcon: Icons.lock_outlined,
                    obscureText: _obscureConfirmPassword,
                    suffix: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.onSurfaceVariant,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() =>
                            _obscureConfirmPassword = !_obscureConfirmPassword);
                      },
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Please confirm the password';
                      }
                      if (v != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                // On narrow screens (< 440 px), stack Phone + Role vertically
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 440;
                    final phoneField = MkesTextField(
                      controller: _phoneController,
                      label: 'Phone Number',
                      keyboardType: TextInputType.phone,
                      validator: (v) {
                        if (v != null && v.isNotEmpty && v.length < 10) {
                          return 'Enter a valid phone number (min 10 digits)';
                        }
                        return null;
                      },
                    );
                    final roleField = DropdownButtonFormField<String>(
                      initialValue: _selectedRole,
                      decoration: InputDecoration(
                        labelText: 'Role',
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusMd),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'staff', child: Text('Staff')),
                        DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedRole = val!);
                      },
                    );

                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          phoneField,
                          const SizedBox(height: AppSpacing.md),
                          roleField,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: phoneField),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: roleField),
                      ],
                    );
                  },
                ),
                if (_selectedRole == 'staff') ...[
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    initialValue: _assignedShift,
                    decoration: InputDecoration(
                      labelText: 'Assigned Duty',
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'morning', child: Text('Morning Shift')),
                      DropdownMenuItem(
                          value: 'afternoon', child: Text('Evening Shift')),
                      DropdownMenuItem(
                          value: 'both',
                          child: Text('Both (Morning & Evening)')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _assignedShift = val);
                    },
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 440;
                    final deptField = departmentsState.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (error, stackTrace) =>
                          Text('Unable to load departments: $error'),
                      data: (departments) => DropdownButtonFormField<String?>(
                        initialValue: _selectedDepartmentId,
                        decoration: InputDecoration(
                          labelText: 'Department',
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusMd),
                          ),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Unassigned'),
                          ),
                          ...departments
                              .where((department) =>
                                  department.isActive ||
                                  department.id == _selectedDepartmentId)
                              .map(
                                (Department department) =>
                                    DropdownMenuItem<String?>(
                                  value: department.id,
                                  child: Text(department.name),
                                ),
                              ),
                        ],
                        onChanged: (value) =>
                            setState(() => _selectedDepartmentId = value),
                      ),
                    );
                    final desigField = MkesTextField(
                      controller: _designationController,
                      label: 'Designation',
                    );

                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          deptField,
                          const SizedBox(height: AppSpacing.md),
                          desigField,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: deptField),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: desigField),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 440;
                    final salaryField = MkesTextField(
                      controller: _salaryController,
                      label: 'Salary',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    );
                    final joiningField = MkesTextField(
                      controller: _joiningDateController,
                      label: 'Joining Date (YYYY-MM-DD)',
                      keyboardType: TextInputType.datetime,
                    );

                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          salaryField,
                          const SizedBox(height: AppSpacing.md),
                          joiningField,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: salaryField),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: joiningField),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
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
                          label: _isCreating ? 'Create User' : 'Save Changes',
                          onPressed: _submit,
                        ),
                      ),
                  ],
                ),
                // Extra bottom padding so last button is never hidden behind keyboard
                SizedBox(height: viewInsets.bottom > 0 ? AppSpacing.md : 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
