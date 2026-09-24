import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../patients/screens/staff_patient_profile_screen.dart';

class StaffPatientsScreen extends StatelessWidget {
  const StaffPatientsScreen({super.key});

  static const _patients = [
    {
      'id': 'E1',
      'name': 'Sarah Jenkins',
      'lastVisit': 'July 18, 2026 • Dr. Vance (Optometry)',
      'room': 'Room 102',
      'status': 'Awaiting Doctor',
    },
    {
      'id': 'E2',
      'name': 'Michael Chen',
      'lastVisit': 'May 04, 2026 • Dr. Sterling (Visiting Retina)',
      'room': 'Dental Suite 3',
      'status': 'In Procedure',
    },
    {
      'id': 'E3',
      'name': 'Elena Rodriguez',
      'lastVisit': 'June 22, 2026 • Dr. Patel (Post-op)',
      'room': 'Waiting Lounge B',
      'status': 'Checked In',
    },
    {
      'id': 'D1',
      'name': 'James Wilson',
      'lastVisit': 'April 15, 2026 • Dr. Vance (Glaucoma)',
      'room': 'Room 105',
      'status': 'Scheduled',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 768.0;

    return SingleChildScrollView(
      padding: EdgeInsets.all(
          isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('My Shift Patients',
                          style: AppTypography.displayLg
                              .copyWith(color: AppColors.onBackground)),
                      const SizedBox(height: AppSpacing.xs),
                      Text('Active patients assigned to your care today',
                          style: AppTypography.bodyLg
                              .copyWith(color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.history_edu),
                  label: const Text('View Visit Records'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            )
          else ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('My Shift Patients',
                    style: AppTypography.displayLg
                        .copyWith(color: AppColors.onBackground, fontSize: 26)),
                const SizedBox(height: AppSpacing.xs),
                Text('Active patients assigned to your care today',
                    style: AppTypography.bodyLg
                        .copyWith(color: AppColors.onSurfaceVariant)),
                const SizedBox(height: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.history_edu),
                  label: const Text('View Visit Records'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _patients.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) {
              final p = _patients[index];

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
                child: ListTile(
                  contentPadding: const EdgeInsets.all(AppSpacing.md),
                  leading: CircleAvatar(
                    backgroundColor:
                        AppColors.primaryContainer.withValues(alpha: 0.2),
                    radius: 24,
                    child: Text(
                      p['name']!.split(' ').map((e) => e[0]).join(),
                      style: AppTypography.labelCaps.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(p['name']!,
                          style:
                              AppTypography.headlineMd.copyWith(fontSize: 18)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(p['id']!,
                            style: AppTypography.dataMono.copyWith(
                                fontSize: 12, color: AppColors.primary)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.secondaryContainer
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          p['status']!,
                          style: AppTypography.labelCaps.copyWith(
                              color: AppColors.secondary, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.history_outlined,
                            size: 14, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Previous Visit: ${p['lastVisit']!}',
                            style: AppTypography.bodySm
                                .copyWith(color: AppColors.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Icon(Icons.meeting_room,
                            size: 14, color: AppColors.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(p['room']!,
                            style: AppTypography.bodySm
                                .copyWith(color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  trailing:
                      const Icon(Icons.chevron_right, color: AppColors.outline),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const StaffPatientProfileScreen(),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
