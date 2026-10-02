import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../features/inventory/screens/inventory_screen.dart';
import '../../../shared/widgets/mkes_text_field.dart';

Future<void> showGlobalSearchModal(BuildContext context) {
  return showDialog(
    context: context,
    builder: (context) => const _GlobalSearchDialog(),
  );
}

class _GlobalSearchDialog extends StatefulWidget {
  const _GlobalSearchDialog();

  @override
  State<_GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<_GlobalSearchDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 768.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 0 : AppSpacing.sm,
        vertical: AppSpacing.xl,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          width: 600,
          constraints: const BoxConstraints(maxHeight: 500),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 32,
                offset: Offset(0, 16),
              ),
            ],
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: MkesTextField(
                  controller: _controller,
                  hintText: 'Search patients, staff, tasks, or settings...',
                  prefixIcon: Icons.search,
                  suffix: IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  children: [
                    _SearchGroupHeading('Recent Searches'),
                    _SearchResultItem(
                      icon: Icons.personal_injury_outlined,
                      title: 'Sarah Jenkins',
                      subtitle: 'Patient • ID: E1',
                      onTap: () {},
                    ),
                    _SearchResultItem(
                      icon: Icons.inventory_2_outlined,
                      title: 'Progressive Lenses (CR-39)',
                      subtitle: 'Inventory • Low Stock',
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const InventoryManagementScreen(),
                          ),
                        );
                      },
                    ),
                    _SearchGroupHeading('Suggested Actions'),
                    _SearchResultItem(
                      icon: Icons.calendar_today_outlined,
                      title: 'Schedule Appointment',
                      subtitle: 'Quick Action',
                      onTap: () {},
                    ),
                    _SearchResultItem(
                      icon: Icons.receipt_long_outlined,
                      title: 'Generate Revenue Report',
                      subtitle: 'Reports',
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Text(
                      'Search powered by MKES Copilot',
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.outline,
                        fontSize: 10,
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.keyboard_arrow_down,
                      size: 16,
                      color: AppColors.outline,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const Icon(
                      Icons.keyboard_arrow_up,
                      size: 16,
                      color: AppColors.outline,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'to navigate',
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.outline,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    const Icon(
                      Icons.keyboard_return,
                      size: 14,
                      color: AppColors.outline,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'to select',
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.outline,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchGroupHeading extends StatelessWidget {
  const _SearchGroupHeading(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Text(
        title,
        style: AppTypography.labelCaps.copyWith(
          color: AppColors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SearchResultItem extends StatelessWidget {
  const _SearchResultItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.outline, size: 20),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.bodyMd),
                  Text(
                    subtitle,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
