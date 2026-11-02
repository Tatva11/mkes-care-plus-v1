# Script to remove all Copilot touchpoints cleanly across all 11 files

# 1. admin_dashboard_screen.dart
with open('lib/features/admin/screens/admin_dashboard_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read()

text = text.replace("import '../widgets/copilot_insights_card.dart';\n", "")
text = text.replace("const CopilotInsightsCard(),\n        const SizedBox(height: AppSpacing.lg),", "const SizedBox(height: AppSpacing.sm),")
text = text.replace("const CopilotInsightsCard(),\n", "")
text = text.replace("CopilotInsightsCard(),\n        SizedBox(height: AppSpacing.lg),", "SizedBox(height: AppSpacing.sm),")
text = text.replace("CopilotInsightsCard(),\n", "")

with open('lib/features/admin/screens/admin_dashboard_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)

# 2. copilot_insights_card.dart - stub as SizedBox.shrink()
stub_copilot = '''import 'package:flutter/material.dart';

/// Legacy placeholder - Copilot has been completely removed from MKES CARE+.
class CopilotInsightsCard extends StatelessWidget {
  const CopilotInsightsCard({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
'''
with open('lib/features/admin/widgets/copilot_insights_card.dart', 'w', encoding='utf-8') as f:
    f.write(stub_copilot)

# 3. staff_management_screen.dart
with open('lib/features/staff/screens/staff_management_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read()

text = text.replace("import '../widgets/staff_copilot_insights_card.dart';\n", "")
text = text.replace("              StaffCopilotInsightsCard(),\n", "")
text = text.replace("        StaffCopilotInsightsCard(),\n        const SizedBox(height: AppSpacing.md),\n", "")
text = text.replace("        StaffCopilotInsightsCard(),\n", "")

with open('lib/features/staff/screens/staff_management_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)

# 4. staff_copilot_insights_card.dart - stub
stub_staff_copilot = '''import 'package:flutter/material.dart';

/// Legacy placeholder - Copilot has been completely removed from MKES CARE+.
class StaffCopilotInsightsCard extends StatelessWidget {
  const StaffCopilotInsightsCard({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
'''
with open('lib/features/staff/widgets/staff_copilot_insights_card.dart', 'w', encoding='utf-8') as f:
    f.write(stub_staff_copilot)

# 5. patient_profile_screen.dart
with open('lib/features/patients/screens/patient_profile_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read()

text = text.replace("import '../widgets/patient_copilot_summary_card.dart';\n", "")
text = text.replace("const PatientCopilotSummaryCard(),\n            const SizedBox(height: AppSpacing.md),\n", "")
text = text.replace("const PatientCopilotSummaryCard(),\n", "")

with open('lib/features/patients/screens/patient_profile_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)

# 6. staff_patient_profile_screen.dart
with open('lib/features/patients/screens/staff_patient_profile_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read()

text = text.replace("import '../widgets/patient_copilot_summary_card.dart';\n", "")
text = text.replace("// AI Clinical Alert Banner\n            const PatientCopilotSummaryCard(),\n\n            const SizedBox(height: AppSpacing.md),\n", "")
text = text.replace("const PatientCopilotSummaryCard(),\n", "")

with open('lib/features/patients/screens/staff_patient_profile_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)

# 7. patient_copilot_summary_card.dart - stub
stub_patient_copilot = '''import 'package:flutter/material.dart';

/// Legacy placeholder - Copilot has been completely removed from MKES CARE+.
class PatientCopilotSummaryCard extends StatelessWidget {
  const PatientCopilotSummaryCard({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
'''
with open('lib/features/patients/widgets/patient_copilot_summary_card.dart', 'w', encoding='utf-8') as f:
    f.write(stub_patient_copilot)

# 8. dental_lab_dashboard_view.dart
with open('lib/features/department/widgets/dental_lab_dashboard_view.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# Replace 3-card desktop row with 2-card desktop row
old_desktop_block = '''              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: DepartmentCopilotInsightCard(
                  insightText:
                      'Dental lab tracking is synchronized with Supabase live queue.',
                  highlightedText: 'synchronized',
                ),
              ),'''
text = text.replace(old_desktop_block, "")

# Replace mobile column 3rd card
old_mobile_block = '''              const SizedBox(height: AppSpacing.md),
              const DepartmentCopilotInsightCard(
                insightText:
                    'Dental lab tracking is synchronized with Supabase live queue.',
                highlightedText: 'synchronized',
              ),'''
text = text.replace(old_mobile_block, "")

with open('lib/features/department/widgets/dental_lab_dashboard_view.dart', 'w', encoding='utf-8') as f:
    f.write(text)

# 9. department_side_cards.dart
with open('lib/features/department/widgets/department_side_cards.dart', 'r', encoding='utf-8') as f:
    text = f.read()

stub_side = '''class DepartmentCopilotActionCard extends StatelessWidget {
  const DepartmentCopilotActionCard({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}'''

import re
text = re.sub(r'class DepartmentCopilotActionCard extends StatelessWidget\s*\{.*?\n\}', stub_side, text, flags=re.DOTALL)
with open('lib/features/department/widgets/department_side_cards.dart', 'w', encoding='utf-8') as f:
    f.write(text)

# 10. department_stat_cards.dart
with open('lib/features/department/widgets/department_stat_cards.dart', 'r', encoding='utf-8') as f:
    text = f.read()

stub_stat = '''class DepartmentCopilotInsightCard extends StatelessWidget {
  const DepartmentCopilotInsightCard({
    super.key,
    required String insightText,
    String? highlightedText,
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}'''
text = re.sub(r'class DepartmentCopilotInsightCard extends StatelessWidget\s*\{.*?\n\}', stub_stat, text, flags=re.DOTALL)
with open('lib/features/department/widgets/department_stat_cards.dart', 'w', encoding='utf-8') as f:
    f.write(text)

# 11. global_search_modal.dart
with open('lib/shared/widgets/global_search_modal.dart', 'r', encoding='utf-8') as f:
    text = f.read()

text = text.replace("'Search powered by MKES Copilot'", "'Search powered by MKES CARE+'")
with open('lib/shared/widgets/global_search_modal.dart', 'w', encoding='utf-8') as f:
    f.write(text)

# Update test files expecting Copilot
with open('test/sprint11_today_dashboard_test.dart', 'r', encoding='utf-8') as f:
    t_text = f.read()
t_text = t_text.replace("expect(find.text('Copilot Insights'), findsOneWidget);", "expect(find.text('Copilot Insights'), findsNothing);")
with open('test/sprint11_today_dashboard_test.dart', 'w', encoding='utf-8') as f:
    f.write(t_text)

with open('test/step2e_remaining_responsive_test.dart', 'r', encoding='utf-8') as f:
    t2_text = f.read()
t2_text = t2_text.replace("'Search powered by MKES Copilot'", "'Search powered by MKES CARE+'")
with open('test/step2e_remaining_responsive_test.dart', 'w', encoding='utf-8') as f:
    f.write(t2_text)

print('All 11 Copilot touchpoint files updated successfully!')

