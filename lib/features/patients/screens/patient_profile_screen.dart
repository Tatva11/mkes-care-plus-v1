import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../admin/widgets/admin_shell.dart';
import '../../admin/screens/administration_screen.dart';
import '../../department/screens/department_management_screen.dart';
import '../../staff/screens/staff_management_screen.dart';
import '../widgets/patient_copilot_summary_card.dart';

class PatientProfileScreen extends StatefulWidget {
  const PatientProfileScreen({super.key});

  @override
  State<PatientProfileScreen> createState() => _PatientProfileScreenState();
}

class _PatientProfileScreenState extends State<PatientProfileScreen> {
  int _selectedTabIndex = 0;

  final List<String> _tabs = [
    'Overview & AI Summary',
    'Patient Information',
    'Contact Details',
    'Medical History',
    'Appointments',
    'Prescriptions',
    'Lab Reports',
    'Billing History',
    'Documents & Timeline',
  ];

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      selectedItem: AdminNavItem.patients,
      onNavItemSelected: (item) {
        if (item == AdminNavItem.dashboard) {
          Navigator.of(context).popUntil((route) => route.isFirst);
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
        if (item == AdminNavItem.operations) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const DepartmentManagementScreen(),
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 768;
          return SingleChildScrollView(
            padding: EdgeInsets.all(
              isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const SizedBox(height: AppSpacing.lg),
                if (isDesktop)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _buildSideNav(),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        flex: 9,
                        child: _buildTabContent(),
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      _buildMobileTabs(),
                      const SizedBox(height: AppSpacing.md),
                      _buildTabContent(),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'Sarah Jenkins',
                      style: AppTypography.displayLg.copyWith(
                        color: AppColors.onBackground,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Text(
                      'Active',
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.primaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Patient ID: P-4092 • Female, 34 yrs • DOB: 12/05/1989',
                style: AppTypography.bodyMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.edit),
          label: const Text('Edit Profile'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.surfaceContainerHigh,
            foregroundColor: AppColors.onSurface,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSideNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _tabs.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final isSelected = index == _selectedTabIndex;
          return ListTile(
            title: Text(
              _tabs[index],
              style: AppTypography.bodyMd.copyWith(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppColors.primary : AppColors.onSurface,
              ),
            ),
            selected: isSelected,
            selectedTileColor: AppColors.surfaceContainerLow,
            onTap: () {
              setState(() => _selectedTabIndex = index);
            },
          );
        },
      ),
    );
  }

  Widget _buildMobileTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(_tabs.length, (index) {
          final isSelected = index == _selectedTabIndex;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: ChoiceChip(
              label: Text(_tabs[index]),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _selectedTabIndex = index);
                }
              },
              backgroundColor: AppColors.surfaceContainerLowest,
              selectedColor: AppColors.primaryContainer.withValues(alpha: 0.2),
              labelStyle: AppTypography.bodyMd.copyWith(
                color: isSelected ? AppColors.primary : AppColors.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTabContent() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tabs[_selectedTabIndex],
            style: AppTypography.headlineMd,
          ),
          const SizedBox(height: AppSpacing.md),
          if (_selectedTabIndex == 0) ...[
            const PatientCopilotSummaryCard(),
            const SizedBox(height: AppSpacing.md),
            _buildInfoGrid('Basic Details', [
              _infoRow('Blood Group', 'O+ (Positive)'),
              _infoRow('Height / Weight', '168 cm / 62 kg'),
              _infoRow('Primary Physician', 'Dr. Alex Morgan'),
              _infoRow('Emergency Contact', 'Mark Jenkins (Spouse) - +1 555 901 2345'),
            ]),
          ] else if (_selectedTabIndex == 1) ...[
            _buildInfoGrid('Patient Information', [
              _infoRow('Full Name', 'Sarah Jenkins'),
              _infoRow('Patient ID', 'P-4092'),
              _infoRow('Date of Birth', '12 May 1989 (34 Years)'),
              _infoRow('Gender', 'Female'),
              _infoRow('Marital Status', 'Married'),
              _infoRow('Insurance Provider', 'Blue Cross Healthcare #BC-99201'),
            ]),
          ] else if (_selectedTabIndex == 2) ...[
            _buildInfoGrid('Contact Details', [
              _infoRow('Phone Number', '+1 (555) 234-5678'),
              _infoRow('Email Address', 'sarah.jenkins@example.com'),
              _infoRow('Residential Address', '742 Evergreen Terrace, Springfield, OR 97477'),
              _infoRow('Preferred Contact', 'Email & SMS Notifications'),
            ]),
          ] else if (_selectedTabIndex == 3) ...[
            _buildInfoGrid('Medical History', [
              _infoRow('Known Allergies', 'Penicillin (Severe Reaction - Anaphylaxis)'),
              _infoRow('Chronic Conditions', 'Recurrent Migraine with Aura, Mild Hypertension'),
              _infoRow('Past Surgeries', 'Appendectomy (2018)'),
              _infoRow('Family History', 'Type 2 Diabetes (Maternal)'),
            ]),
          ] else if (_selectedTabIndex == 4) ...[
            _buildInfoGrid('Appointments History', [
              _infoRow('Upcoming Visit', 'Oct 28, 2023 at 10:30 AM - Optometry Consultation'),
              _infoRow('Last Visit', 'Oct 12, 2023 at 02:00 PM - Routine Follow-up'),
              _infoRow('Attending Doctor', 'Dr. Sarah Smith (Optometry)'),
            ]),
          ] else if (_selectedTabIndex == 5) ...[
            _buildInfoGrid('Prescriptions & Medications', [
              _infoRow('Sumatriptan 50mg', 'Oral Tablet • Take 1 at onset of migraine. Max 200mg/day.'),
              _infoRow('Propranolol 40mg', 'Oral Tablet • Take 1 tablet daily every morning.'),
              _infoRow('Prescribing Doctor', 'Dr. Alex Morgan (Neurology)'),
            ]),
          ] else if (_selectedTabIndex == 6) ...[
            _buildInfoGrid('Lab & Diagnostic Reports', [
              _infoRow('Blood Panel Report', 'Normal - Hemoglobin 13.5 g/dL, WBC 6.8k (Oct 10, 2023)'),
              _infoRow('Intraoral Scan', 'Completed - Zirconia Shade Match #A2 (Oct 12, 2023)'),
            ]),
          ] else if (_selectedTabIndex == 7) ...[
            _buildInfoGrid('Billing & Invoices', [
              _infoRow('Invoice #INV-2023-089', '\$240.00 • Paid via Visa ending in 4092 (Oct 12, 2023)'),
              _infoRow('Outstanding Balance', '\$0.00 (Account in Good Standing)'),
            ]),
          ] else ...[
            _buildInfoGrid('Documents & Activity Log', [
              _infoRow('Uploaded Documents', 'Patient_Consent_Form.pdf, ID_Card_Scan.jpg'),
              _infoRow('Recent Activity', 'Profile updated by Dr. Alex Morgan at 11:30 AM Today'),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoGrid(String title, List<Map<String, String>> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.headlineMd.copyWith(color: AppColors.primary),
        ),
        const SizedBox(height: AppSpacing.sm),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final entry = items[index];
            final key = entry.keys.first;
            final val = entry.values.first;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      key,
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 7,
                    child: Text(
                      val,
                      style: AppTypography.bodyMd.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Map<String, String> _infoRow(String label, String value) {
    return {label: value};
  }
}
