import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../dental/providers/dental_lab_provider.dart';
import 'department_stat_cards.dart';
import 'dental_lab_queue_card.dart';

class DentalLabDashboardView extends ConsumerWidget {
  const DentalLabDashboardView({super.key, required this.isDesktop});

  final bool isDesktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dentalLabStatsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // KPI Row
        if (isDesktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DepartmentStatCard(
                  title: 'Active Dental Cases',
                  icon: Icons.biotech,
                  iconColor: AppColors.secondary,
                  value: '${stats.total}',
                  subtitle: '${stats.processing} In Processing',
                  subtitleColor: AppColors.primaryContainer,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: DepartmentStatCard(
                  title: 'Ready for Fit',
                  icon: Icons.verified_outlined,
                  iconColor: AppColors.primaryContainer,
                  value: '${stats.ready}',
                  subtitle: '${stats.delivered} Delivered',
                  subtitleColor: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: DepartmentCopilotInsightCard(
                  insightText:
                      'Dental lab tracking is synchronized with Supabase live queue.',
                  highlightedText: 'synchronized',
                ),
              ),
            ],
          )
        else
          Column(
            children: [
              DepartmentStatCard(
                title: 'Active Dental Cases',
                icon: Icons.biotech,
                iconColor: AppColors.secondary,
                value: '${stats.total}',
                subtitle: '${stats.processing} In Processing',
                subtitleColor: AppColors.primaryContainer,
              ),
              const SizedBox(height: AppSpacing.md),
              DepartmentStatCard(
                title: 'Ready for Fit',
                icon: Icons.verified_outlined,
                iconColor: AppColors.primaryContainer,
                value: '${stats.ready}',
                subtitle: '${stats.delivered} Delivered',
                subtitleColor: AppColors.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.md),
              const DepartmentCopilotInsightCard(
                insightText:
                    'Dental lab tracking is synchronized with Supabase live queue.',
                highlightedText: 'synchronized',
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
              Text('Dental Clinic Workload', style: AppTypography.headlineMd),
              const Icon(Icons.people_outline,
                  color: AppColors.secondary, size: 20),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Dental cases are tracked in real-time. Use the Dental Lab Screen to transition cases to Ready and Delivered.',
            style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
