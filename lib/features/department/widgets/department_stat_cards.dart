import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

class DepartmentStatCard extends StatelessWidget {
  const DepartmentStatCard({
    super.key,
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.subtitle,
    required this.subtitleColor,
    this.subtitleIcon,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final String value;
  final String subtitle;
  final Color subtitleColor;
  final IconData? subtitleIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: const Color(0xFFFEFEFD),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: const Color(0xFFE8E4E2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.labelCaps.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 20, color: iconColor),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: AppTypography.displayLg.copyWith(
                  height: 1.0,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(bottom: 2.0),
                child: Row(
                  children: [
                    if (subtitleIcon != null) ...[
                      Icon(subtitleIcon, size: 16, color: subtitleColor),
                      const SizedBox(width: 2),
                    ],
                    Text(
                      subtitle,
                      style: AppTypography.bodySm.copyWith(
                        color: subtitleColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DepartmentCopilotInsightCard extends StatelessWidget {
  const DepartmentCopilotInsightCard({
    super.key,
    required this.insightText,
    required this.highlightedText,
  });

  final String insightText;
  final String highlightedText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: const Color(0xFFFEFEFD),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: AppColors.outlineVariant),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFFDBC8).withValues(alpha: 0.2), // primary-fixed
            const Color(0xFFFFD8EB).withValues(alpha: 0.2), // secondary-fixed
          ],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  size: 14, color: AppColors.primary),
              const SizedBox(width: 4),
              Text(
                'Copilot Insight',
                style: AppTypography.labelCaps.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          RichText(
            overflow: TextOverflow.fade,
            softWrap: true,
            text: TextSpan(
              style: AppTypography.bodySm.copyWith(color: AppColors.onSurface),
              children: _buildTextSpans(),
            ),
          ),
        ],
      ),
    );
  }

  List<TextSpan> _buildTextSpans() {
    final parts = insightText.split(highlightedText);
    if (parts.length != 2) {
      return [TextSpan(text: insightText)];
    }
    return [
      TextSpan(text: parts[0]),
      TextSpan(
        text: highlightedText,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      TextSpan(text: parts[1]),
    ];
  }
}
