import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_footer.dart';
import '../../admin/widgets/admin_shell.dart';
import '../../admin/screens/administration_screen.dart';
import '../../patients/screens/patient_list_screen.dart';
import '../../staff/screens/staff_management_screen.dart';
import '../models/department.dart';
import '../providers/departments_provider.dart';

class DepartmentManagementScreen extends StatelessWidget {
  const DepartmentManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      selectedItem: AdminNavItem.operations,
      onNavItemSelected: (item) {
        if (item == AdminNavItem.dashboard) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          return;
        }
        if (item == AdminNavItem.patients) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const PatientListScreen(),
            ),
          );
          return;
        }
        if (item == AdminNavItem.staff) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const StaffManagementScreen(),
            ),
          );
          return;
        }
        if (item == AdminNavItem.administration) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const AdministrationScreen(),
            ),
          );
          return;
        }
      },
      body: const DepartmentManagementContent(),
    );
  }
}

class DepartmentManagementContent extends ConsumerStatefulWidget {
  const DepartmentManagementContent({super.key});

  @override
  ConsumerState<DepartmentManagementContent> createState() =>
      _DepartmentManagementContentState();
}

class _DepartmentManagementContentState
    extends ConsumerState<DepartmentManagementContent> {
  Future<void> _openDepartmentDialog({Department? department}) async {
    final result = await showDialog<_DepartmentFormResult>(
      context: context,
      builder: (_) => _DepartmentDialog(department: department),
    );
    if (result == null || !mounted) return;

    try {
      final notifier = ref.read(departmentsProvider.notifier);
      if (department == null) {
        await notifier.createDepartment(
          name: result.name,
          description: result.description,
        );
      } else {
        await notifier.updateDepartment(
          id: department.id,
          name: result.name,
          description: result.description,
          isActive: result.isActive,
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to save department: $error')),
        );
      }
    }
  }

  Future<void> _deleteDepartment(Department department) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete department'),
        content: Text(
            'Delete ${department.name}? Staff assigned to it must be reassigned first.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(departmentsProvider.notifier)
          .deleteDepartment(department.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to delete department: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final departmentsState = ref.watch(departmentsProvider);
    final isDesktop = MediaQuery.sizeOf(context).width > 768;
    return SingleChildScrollView(
      padding: EdgeInsets.all(
          isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildHeaderTexts()),
              const SizedBox(width: AppSpacing.md),
              FilledButton.icon(
                onPressed: () => _openDepartmentDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Add Department'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          departmentsState.when(
            loading: () => const Center(
                child: Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: CircularProgressIndicator(),
            )),
            error: (error, stackTrace) => _StateMessage(
              message: 'Unable to load departments: $error',
              action: TextButton(
                onPressed: () =>
                    ref.read(departmentsProvider.notifier).fetchDepartments(),
                child: const Text('Retry'),
              ),
            ),
            data: (departments) => departments.isEmpty
                ? const _StateMessage(message: 'No departments found.')
                : Column(
                    children: departments.map(_buildDepartmentTile).toList(),
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const AppFooter(),
        ],
      ),
    );
  }

  Widget _buildDepartmentTile(Department department) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.business_outlined, color: AppColors.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(department.name, style: AppTypography.headlineMd),
                if (department.description?.isNotEmpty == true)
                  Text(department.description!, style: AppTypography.bodyMd),
              ],
            ),
          ),
          Text(department.isActive ? 'Active' : 'Inactive',
              style: AppTypography.labelCaps),
          IconButton(
            tooltip: 'Edit department',
            onPressed: () => _openDepartmentDialog(department: department),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete department',
            onPressed: () => _deleteDepartment(department),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderTexts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Department Management',
          style: AppTypography.displayLg.copyWith(
            color: AppColors.onBackground,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Track active orders and manage inventory across specialized departments.',
          style: AppTypography.bodyLg.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [Text(message), if (action != null) action!],
        ),
      ),
    );
  }
}

class _DepartmentFormResult {
  const _DepartmentFormResult(
      {required this.name, this.description, required this.isActive});

  final String name;
  final String? description;
  final bool isActive;
}

class _DepartmentDialog extends StatefulWidget {
  const _DepartmentDialog({this.department});

  final Department? department;

  @override
  State<_DepartmentDialog> createState() => _DepartmentDialogState();
}

class _DepartmentDialogState extends State<_DepartmentDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.department?.name);
    _descriptionController =
        TextEditingController(text: widget.department?.description);
    _isActive = widget.department?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
          widget.department == null ? 'Add Department' : 'Edit Department'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name')),
          TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description')),
          if (widget.department != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              value: _isActive,
              onChanged: (value) => setState(() => _isActive = value),
            ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              _DepartmentFormResult(
                name: name,
                description: _descriptionController.text.trim().isEmpty
                    ? null
                    : _descriptionController.text.trim(),
                isActive: _isActive,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
