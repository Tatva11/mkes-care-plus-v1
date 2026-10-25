import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/mkes_text_field.dart';
import '../../admin/widgets/admin_shell.dart';
import '../../admin/screens/administration_screen.dart';
import '../../department/screens/department_management_screen.dart';
import '../../patients/screens/patient_list_screen.dart';
import '../../staff/screens/staff_management_screen.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/user_profile.dart';
import '../providers/users_provider.dart';
import 'user_form_dialog.dart';

class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdministrationScreen()),
        );
      },
      child: AdminShell(
        selectedItem: AdminNavItem.administration,
        onNavItemSelected: (item) {
          if (item == AdminNavItem.dashboard) {
            Navigator.of(context).popUntil((route) => route.isFirst);
            return;
          }
          if (item == AdminNavItem.staff) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const StaffManagementScreen()),
            );
            return;
          }
          if (item == AdminNavItem.patients) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const PatientListScreen()),
            );
            return;
          }
          if (item == AdminNavItem.operations) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                  builder: (_) => const DepartmentManagementScreen()),
            );
            return;
          }
          if (item == AdminNavItem.administration) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const AdministrationScreen()),
            );
            return;
          }
        },
        body: const UserManagementContent(),
      ),
    );
  }
}

class UserManagementContent extends ConsumerStatefulWidget {
  const UserManagementContent({super.key});

  @override
  ConsumerState<UserManagementContent> createState() =>
      _UserManagementContentState();
}

class _UserManagementContentState extends ConsumerState<UserManagementContent> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openAddUserDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const UserFormDialog(),
    );
  }

  void _openEditUserDialog(UserProfile user) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => UserFormDialog(user: user),
    );
  }

  final Set<String> _deletingUserIds = {};

  Future<void> _confirmDelete(UserProfile user) async {
    final currentUserId = ref.read(currentUserProvider)?.id;
    if (currentUserId != null && user.id == currentUserId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You cannot delete your own admin account.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    if (_deletingUserIds.contains(user.id)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove User'),
        content: Text(
          'Are you sure you want to permanently remove ${user.fullName}? '
          'This will remove their login access while preserving all clinical, attendance, and audit history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _deletingUserIds.add(user.id));
      try {
        await ref.read(usersProvider.notifier).deleteUser(user.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${user.fullName} removed successfully.'),
              backgroundColor: AppColors.primaryContainer,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error removing user: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _deletingUserIds.remove(user.id));
        }
      }
    }
  }

  Future<void> _toggleActive(UserProfile user) async {
    try {
      await ref
          .read(usersProvider.notifier)
          .toggleStatus(user.id, !user.isActive);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error updating status: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersState = ref.watch(usersProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 768;
        return SingleChildScrollView(
          padding: EdgeInsets.all(
            isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(isDesktop),
              const SizedBox(height: AppSpacing.lg),
              _buildSearchBar(),
              const SizedBox(height: AppSpacing.md),
              usersState.when(
                data: (users) =>
                    isDesktop ? _buildUserTable(users) : _buildUserCards(users),
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, st) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Center(child: Text('Error loading users: $e')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(bool isDesktop) {
    final titleRow = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const AdministrationScreen()),
              );
            }
          },
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'User Management',
                style: (isDesktop
                        ? AppTypography.displayLg
                        : AppTypography.displayLg.copyWith(fontSize: 26))
                    .copyWith(color: AppColors.onBackground),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Add, remove, or modify user accounts and login access.',
                style: AppTypography.bodyLg
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );

    final addButton = FilledButton.icon(
      onPressed: _openAddUserDialog,
      icon: const Icon(Icons.person_add_alt_1),
      label: const Text('Add User'),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primaryContainer,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
      ),
    );

    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: titleRow),
          const SizedBox(width: AppSpacing.md),
          addButton,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        titleRow,
        const SizedBox(height: AppSpacing.sm),
        addButton,
      ],
    );
  }

  Widget _buildSearchBar() {
    return MkesTextField(
      controller: _searchController,
      hintText: 'Search by name, email, role, or department...',
      prefixIcon: Icons.search,
      onChanged: (value) => ref.read(usersProvider.notifier).search(value),
    );
  }

  Widget _buildUserTable(List<UserProfile> users) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.outlineVariant),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 1)),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 860),
          child: Column(
            children: [
              Container(
                width: 860,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                decoration: const BoxDecoration(
                  border: Border(
                      bottom: BorderSide(color: AppColors.outlineVariant)),
                ),
                child: Row(
                  children: [
                    Expanded(
                        flex: 3,
                        child: Text('NAME', style: AppTypography.labelCaps)),
                    Expanded(
                        flex: 3,
                        child: Text('EMAIL', style: AppTypography.labelCaps)),
                    Expanded(
                        flex: 2,
                        child: Text('ROLE', style: AppTypography.labelCaps)),
                    Expanded(
                        flex: 2,
                        child:
                            Text('DEPARTMENT', style: AppTypography.labelCaps)),
                    Expanded(
                        flex: 2,
                        child: Text('STATUS', style: AppTypography.labelCaps)),
                    const SizedBox(width: 96),
                  ],
                ),
              ),
              if (users.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text('No users found.'),
                )
              else
                SizedBox(
                  width: 860,
                  child: Column(
                    children: users.map((u) => _buildUserRow(u)).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserCards(List<UserProfile> users) {
    if (users.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: const Center(child: Text('No users found.')),
      );
    }

    return Column(
      children: users.map((user) {
        final isAdmin = user.role == 'admin';
        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.outlineVariant),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 8,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: Name, Role badge, & Actions ─────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.fullName,
                          style: AppTypography.bodyMd.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isAdmin
                                    ? AppColors.secondaryContainer
                                        .withValues(alpha: 0.2)
                                    : AppColors.primaryContainer
                                        .withValues(alpha: 0.1),
                                borderRadius:
                                    BorderRadius.circular(AppSpacing.radiusSm),
                              ),
                              child: Text(
                                isAdmin ? 'Admin' : 'Staff',
                                style: AppTypography.labelCaps.copyWith(
                                  color: isAdmin
                                      ? AppColors.secondary
                                      : AppColors.primaryContainer,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: Text(
                                user.departmentName ?? user.department ?? '—',
                                style: AppTypography.bodySm.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    color: AppColors.onSurfaceVariant,
                    tooltip: 'Edit user',
                    onPressed: () => _openEditUserDialog(user),
                  ),
                  if (_deletingUserIds.contains(user.id))
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      color: AppColors.error,
                      tooltip: 'Remove user',
                      onPressed: () => _confirmDelete(user),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              // ── Email ───────────────────────────────────────────────────
              Row(
                children: [
                  const Icon(Icons.email_outlined,
                      size: 14, color: AppColors.outline),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      user.email,
                      style: AppTypography.bodySm
                          .copyWith(color: AppColors.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              // ── Active / Inactive Status Toggle ─────────────────────────
              Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: () => _toggleActive(user),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: user.isActive
                          ? AppColors.primaryContainer.withValues(alpha: 0.1)
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          user.isActive
                              ? Icons.check_circle_outline
                              : Icons.pause_circle_outline,
                          size: 14,
                          color: user.isActive
                              ? AppColors.primaryContainer
                              : AppColors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          user.isActive ? 'Active' : 'Inactive',
                          style: AppTypography.labelCaps.copyWith(
                            color: user.isActive
                                ? AppColors.primaryContainer
                                : AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildUserRow(UserProfile user) {
    final isAdmin = user.role == 'admin';
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              user.fullName,
              style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              user.email,
              style: AppTypography.bodySm
                  .copyWith(color: AppColors.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isAdmin
                      ? AppColors.secondaryContainer.withValues(alpha: 0.2)
                      : AppColors.primaryContainer.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  isAdmin ? 'Admin' : 'Staff',
                  style: AppTypography.labelCaps.copyWith(
                    color: isAdmin
                        ? AppColors.secondary
                        : AppColors.primaryContainer,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              user.departmentName ?? user.department ?? '—',
              style: AppTypography.bodySm
                  .copyWith(color: AppColors.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: () => _toggleActive(user),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: user.isActive
                        ? AppColors.primaryContainer.withValues(alpha: 0.1)
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(
                    user.isActive ? 'Active' : 'Inactive',
                    style: AppTypography.labelCaps.copyWith(
                      color: user.isActive
                          ? AppColors.primaryContainer
                          : AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 96,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  color: AppColors.onSurfaceVariant,
                  tooltip: 'Edit user',
                  onPressed: () => _openEditUserDialog(user),
                ),
                if (_deletingUserIds.contains(user.id))
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: AppColors.error,
                    tooltip: 'Remove user',
                    onPressed: () => _confirmDelete(user),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
