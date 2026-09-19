import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import 'department_stat_cards.dart';
import 'dental_lab_queue_card.dart';

class DentalLabDashboardView extends StatelessWidget {
  const DentalLabDashboardView({super.key, required this.isDesktop});

  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // KPI Row
        if (isDesktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Expanded(
                child: DepartmentStatCard(
                  title: 'Active Dental Cases',
                  icon: Icons.biotech,
                  iconColor: AppColors.secondary,
                  value: '14',
                  subtitle: '4 Due Today',
                  subtitleColor: AppColors.primaryContainer,
                ),
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: DepartmentStatCard(
                  title: 'QA Inspection',
                  icon: Icons.verified_outlined,
                  iconColor: AppColors.primaryContainer,
                  value: '3',
                  subtitle: '2 Ready for Glaze',
                  subtitleColor: AppColors.onSurfaceVariant,
                ),
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: DepartmentCopilotInsightCard(
                  insightText:
                      'Zirconia shade matching for #DEN-4013 has a 12% opacity variance flag.',
                  highlightedText: '12% opacity variance',
                ),
              ),
            ],
          )
        else
          Column(
            children: const [
              DepartmentStatCard(
                title: 'Active Dental Cases',
                icon: Icons.biotech,
                iconColor: AppColors.secondary,
                value: '14',
                subtitle: '4 Due Today',
                subtitleColor: AppColors.primaryContainer,
              ),
              SizedBox(height: AppSpacing.md),
              DepartmentStatCard(
                title: 'QA Inspection',
                icon: Icons.verified_outlined,
                iconColor: AppColors.primaryContainer,
                value: '3',
                subtitle: '2 Ready for Glaze',
                subtitleColor: AppColors.onSurfaceVariant,
              ),
              SizedBox(height: AppSpacing.md),
              DepartmentCopilotInsightCard(
                insightText:
                    'Zirconia shade matching for #DEN-4013 has a 12% opacity variance flag.',
                highlightedText: '12% opacity variance',
              ),
            ],
          ),

        const SizedBox(height: AppSpacing.md),

        // Main Bento Section
        if (isDesktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Expanded(
                flex: 8,
                child: DentalLabQueueCard(),
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    _TechnicianWorkloadCard(),
                    SizedBox(height: AppSpacing.md),
                    _DentalCopilotActionCard(),
                  ],
                ),
              ),
            ],
          )
        else
          const Column(
            children: [
              DentalLabQueueCard(),
              SizedBox(height: AppSpacing.md),
              _TechnicianWorkloadCard(),
              SizedBox(height: AppSpacing.md),
              _DentalCopilotActionCard(),
            ],
          ),
      ],
    );
  }
}

class _TechnicianWorkloadCard extends StatelessWidget {
  const _TechnicianWorkloadCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Technician Allocation', style: AppTypography.headlineMd),
              const Icon(Icons.people_outline,
                  color: AppColors.secondary, size: 20),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _buildTechRow('Tech Alex Vance', '5 Active Cases', 0.85,
              AppColors.primaryContainer),
          const SizedBox(height: AppSpacing.sm),
          _buildTechRow(
              'Tech Maria Lopez', '4 Active Cases', 0.65, AppColors.secondary),
          const SizedBox(height: AppSpacing.sm),
          _buildTechRow(
              'Tech Sam Rivera', '2 Active Cases', 0.35, AppColors.tertiary),
        ],
      ),
    );
  }

  Widget _buildTechRow(String name, String status, double load, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                name,
                style:
                    AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(status,
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: load,
          backgroundColor: AppColors.surfaceContainerLow,
          color: color,
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
      ],
    );
  }
}

class _DentalCopilotActionCard extends StatelessWidget {
  const _DentalCopilotActionCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.secondaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  color: AppColors.secondary, size: 18),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  'AI CAD/CAM Suggestion',
                  style: AppTypography.labelCaps
                      .copyWith(color: AppColors.secondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Re-assign #DEN-4014 to Tech Sam Rivera for faster 3D printing throughput.',
            style: AppTypography.bodySm.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () {},
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 4),
              ),
              child: const Text('Auto-Assign'),
            ),
          ),
        ],
      ),
    );
  }
}
