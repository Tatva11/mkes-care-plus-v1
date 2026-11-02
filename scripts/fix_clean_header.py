with open('lib/features/admin/widgets/revenue_growth_card.dart', 'r', encoding='utf-8') as f:
    text = f.read()

import re
old_header_pattern = re.compile(r'// Header: Title and View Reports.*?const SizedBox\(height: AppSpacing\.sm\),\s*_buildDateSelector\(context, ref, selectedDate\),\s*const SizedBox\(height: AppSpacing\.sm\),', re.DOTALL)

clean_header = '''Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xs,
            runSpacing: 4,
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
                  padding: EdgeInsets.zero,
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
          const SizedBox(height: AppSpacing.xs),
          _buildDateSelector(context, ref, selectedDate),
          const SizedBox(height: AppSpacing.sm),'''

text = old_header_pattern.sub(clean_header, text)

with open('lib/features/admin/widgets/revenue_growth_card.dart', 'w', encoding='utf-8') as f:
    f.write(text)

print('Updated clean header in revenue_growth_card.dart!')

