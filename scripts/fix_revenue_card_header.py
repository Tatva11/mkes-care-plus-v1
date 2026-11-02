with open('lib/features/admin/widgets/revenue_growth_card.dart', 'r', encoding='utf-8') as f:
    text = f.read()

target = '''          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xs,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.trending_up,
                    color: AppColors.primaryContainer,
                    size: 22,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      'Revenue Growth',
                      style: AppTypography.headlineMd,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDateSelector(context, ref, selectedDate),
                  const SizedBox(width: AppSpacing.xs),
                  TextButton(
                    onPressed: () {
                      ref.read(adminReportsSectionProvider.notifier).state =
                          ReportsSection.financial;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AdminReportsScreen(),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View Reports',
                          style: AppTypography.labelCaps.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),'''

replacement = '''          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xs,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.trending_up,
                    color: AppColors.primaryContainer,
                    size: 22,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Revenue Growth',
                    style: AppTypography.headlineMd,
                  ),
                ],
              ),
              _buildDateSelector(context, ref, selectedDate),
              TextButton(
                onPressed: () {
                  ref.read(adminReportsSectionProvider.notifier).state =
                      ReportsSection.financial;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminReportsScreen(),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View Reports',
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),'''

if target in text:
    text = text.replace(target, replacement)
elif target.replace('\n', '\r\n') in text:
    text = text.replace(target.replace('\n', '\r\n'), replacement.replace('\n', '\r\n'))
else:
    print('Target not found directly, checking')

with open('lib/features/admin/widgets/revenue_growth_card.dart', 'w', encoding='utf-8') as f:
    f.write(text)

print('Updated header wrap in revenue_growth_card.dart!')

