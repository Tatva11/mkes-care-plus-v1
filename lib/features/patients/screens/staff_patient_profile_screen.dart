import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../staff_portal/widgets/staff_shell.dart';
import '../widgets/patient_copilot_summary_card.dart';

class StaffPatientProfileScreen extends StatelessWidget {
  const StaffPatientProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StaffShell(
      selectedItem: StaffNavItem.patients,
      onNavItemSelected: (item) {
        if (item == StaffNavItem.schedule) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          return;
        }
      },
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Sarah Jenkins',
                              style: AppTypography.headlineMd),
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Active Patient',
                              style: AppTypography.labelCaps
                                  .copyWith(color: AppColors.primaryContainer),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'ID: #E1 • 34 yrs, Female • Room 204',
                        style: AppTypography.bodySm
                            .copyWith(color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.md),

            // AI Clinical Alert Banner
            const PatientCopilotSummaryCard(),

            const SizedBox(height: AppSpacing.md),

            // Patient Visit History Section
            _buildVisitHistoryCard(context),

            const SizedBox(height: AppSpacing.md),

            // Clinical Notes Action Card
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Staff Shift Notes',
                          style: AppTypography.headlineMd),
                      IconButton(
                        icon: const Icon(Icons.add_comment_outlined),
                        onPressed: () {},
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '"Patient rested comfortably post-consultation at 09:30 AM. Accompanied to waiting lounge B. Patient history updated for attending specialist."',
                    style: AppTypography.bodyMd.copyWith(
                        fontStyle: FontStyle.italic,
                        color: AppColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text('— Nurse Jane Doe, 10:15 AM Today',
                      style: AppTypography.labelCaps
                          .copyWith(color: AppColors.outline)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisitHistoryCard(BuildContext context) {
    final visits = [
      {
        'date': 'July 18, 2026',
        'doctor': 'Dr. Sarah Vance, O.D. (Optometry)',
        'procedure': 'Comprehensive Refraction & Corneal Topography',
        'diagnosis': 'Mild Astigmatism; early presbyopia flags noted.',
        'notes':
            'Prescribed anti-reflective blue-light lenses. Scheduled 3-month corneal monitoring check.',
        'badgeColor': AppColors.primaryContainer,
      },
      {
        'date': 'May 04, 2026',
        'doctor': 'Dr. Robert Sterling (Visiting Retina Specialist)',
        'procedure': 'Dilated Macular Exam & OCT Scan',
        'diagnosis':
            'Normal retinal nerve fiber layer thickness. No diabetic retinopathy.',
        'notes':
            'Maintain routine annual screening. Advised UV protective outdoor eyewear.',
        'badgeColor': AppColors.secondary,
      },
      {
        'date': 'January 12, 2026',
        'doctor': 'Dr. Elena Rostova (Dental Surgeon)',
        'procedure': 'Crown Prep & Intraoral 3D Impression',
        'diagnosis': 'Tooth #14 distal caries, crown indicated.',
        'notes':
            'Permanent crown fitting completed cleanly. Zero post-op sensitivity reported.',
        'badgeColor': AppColors.tertiary,
      },
    ];

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.history_edu,
                      color: AppColors.primary, size: 22),
                  const SizedBox(width: AppSpacing.xs),
                  Text('Patient Visit History',
                      style: AppTypography.headlineMd),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Text(
                  '3 Previous Visits',
                  style: AppTypography.labelCaps.copyWith(
                      color: AppColors.onSurfaceVariant, fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: visits.length,
            separatorBuilder: (_, __) => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Divider(height: 1, color: AppColors.surfaceVariant),
            ),
            itemBuilder: (context, index) {
              final v = visits[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              size: 14, color: AppColors.outline),
                          const SizedBox(width: 6),
                          Text(
                            v['date'] as String,
                            style: AppTypography.dataMono.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AppColors.primary),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (v['badgeColor'] as Color)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Verified Visit',
                          style: AppTypography.labelCaps.copyWith(
                              color: v['badgeColor'] as Color, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      const Icon(Icons.medical_information,
                          size: 14, color: AppColors.secondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          v['doctor'] as String,
                          style: AppTypography.bodySm.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurface),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _buildVisitField('Treatment / Procedure',
                      v['procedure'] as String, Icons.healing),
                  const SizedBox(height: 4),
                  _buildVisitField('Diagnosis / Observations',
                      v['diagnosis'] as String, Icons.biotech),
                  if ((v['notes'] as String).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _buildVisitField('Follow-up Notes', v['notes'] as String,
                        Icons.note_alt_outlined,
                        isItalic: true),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildVisitField(String label, String value, IconData icon,
      {bool isItalic = false}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
                      color: isItalic
                          ? AppColors.onSurface
                          : AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
