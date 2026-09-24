import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../admin/widgets/admin_shell.dart';
import '../widgets/patient_form_dialog.dart';
import 'patient_profile_screen.dart';

class PatientListScreen extends StatelessWidget {
  const PatientListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      selectedItem: AdminNavItem.patients,
      onNavItemSelected: (item) {
        if (item == AdminNavItem.dashboard) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          return;
        }
      },
      body: const PatientListContent(),
    );
  }
}

class PatientListContent extends StatefulWidget {
  const PatientListContent({super.key});

  @override
  State<PatientListContent> createState() => _PatientListContentState();
}

class _PatientListContentState extends State<PatientListContent> {
  Future<void> _openNewPatientDialog() async {
    await showDialog(
      context: context,
      builder: (_) => const PatientFormDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              _buildPatientTable(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(bool isDesktop) {
    if (isDesktop) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Patients',
                style: AppTypography.displayLg.copyWith(
                  color: AppColors.onBackground,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Manage patient records and clinical history.',
                style: AppTypography.bodyLg.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          FilledButton.icon(
            onPressed: _openNewPatientDialog,
            icon: const Icon(Icons.person_add),
            label: const Text('New Patient'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Patients',
          style: AppTypography.displayLg.copyWith(
            color: AppColors.onBackground,
            fontSize: 26,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Manage patient records and clinical history.',
          style: AppTypography.bodyLg.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.icon(
          onPressed: _openNewPatientDialog,
          icon: const Icon(Icons.person_add),
          label: const Text('New Patient'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPatientTable() {
    return Container(
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 780),
          child: Column(
            children: [
              // Table Header
              Container(
                width: 780,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text('PATIENT ID', style: AppTypography.labelCaps),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text('NAME', style: AppTypography.labelCaps),
                    ),
                    Expanded(
                      flex: 2,
                      child:
                          Text('AGE / GENDER', style: AppTypography.labelCaps),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text('CONTACT', style: AppTypography.labelCaps),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('LAST VISIT', style: AppTypography.labelCaps),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('STATUS', style: AppTypography.labelCaps),
                    ),
                    const SizedBox(width: 48), // Action button space
                  ],
                ),
              ),
              // Table Body (Mock Data)
              SizedBox(
                width: 780,
                child: Column(
                  children: [
                    _buildPatientRow('E1', 'Sarah Jenkins', '34 / Female',
                        '+1 (555) 234-5678', 'Oct 12, 2023', 'Active'),
                    _buildPatientRow('E2', 'Michael Chen', '42 / Male',
                        '+1 (555) 876-5432', 'Oct 15, 2023', 'Active'),
                    _buildPatientRow('E3', 'Elena Rodriguez', '29 / Female',
                        '+1 (555) 345-6789', 'Sep 28, 2023', 'Inactive'),
                    _buildPatientRow('E4', 'James Wilson', '58 / Male',
                        '+1 (555) 987-6543', 'Oct 20, 2023', 'Active'),
                    _buildPatientRow('D1', 'Amanda Taylor', '31 / Female',
                        '+1 (555) 456-7890', 'Oct 22, 2023', 'Active'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPatientRow(
    String id,
    String name,
    String ageGender,
    String contact,
    String lastVisit,
    String status,
  ) {
    final isActive = status == 'Active';

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const PatientProfileScreen(),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: AppColors.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    id,
                    style: AppTypography.dataMono.copyWith(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                name,
                style: AppTypography.bodyMd.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                ageGender,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                contact,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                lastVisit,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.primaryContainer.withValues(alpha: 0.1)
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(
                    status,
                    style: AppTypography.labelCaps.copyWith(
                      color: isActive
                          ? AppColors.primaryContainer
                          : AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              color: AppColors.outline,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PatientProfileScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
