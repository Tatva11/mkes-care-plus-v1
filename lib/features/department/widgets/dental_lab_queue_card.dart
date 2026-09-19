import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

enum DentalCaseStatus { inProduction, qaReview, pendingImpression, completed }

class DentalCaseOrder {
  final String caseId;
  final String patient;
  final String restorationType;
  final String technician;
  final String stageName;
  final double progressPercent;
  final DentalCaseStatus status;
  final bool hasAiHighlight;

  const DentalCaseOrder({
    required this.caseId,
    required this.patient,
    required this.restorationType,
    required this.technician,
    required this.stageName,
    required this.progressPercent,
    required this.status,
    this.hasAiHighlight = false,
  });
}

class DentalLabQueueCard extends StatelessWidget {
  const DentalLabQueueCard({super.key});

  static const _cases = [
    DentalCaseOrder(
      caseId: '#DEN-4012',
      patient: 'David Miller',
      restorationType: 'Zirconia Crown #14',
      technician: 'Tech Alex Vance',
      stageName: 'CAM Milling',
      progressPercent: 0.65,
      status: DentalCaseStatus.inProduction,
    ),
    DentalCaseOrder(
      caseId: '#DEN-4013',
      patient: 'Sophia Martinez',
      restorationType: '3-Unit Porc. Bridge',
      technician: 'Tech Maria Lopez',
      stageName: 'Shade & Glaze QC',
      progressPercent: 0.90,
      status: DentalCaseStatus.qaReview,
      hasAiHighlight: true,
    ),
    DentalCaseOrder(
      caseId: '#DEN-4014',
      patient: 'Ethan Wright',
      restorationType: 'Implant Abutment #19',
      technician: 'Unassigned',
      stageName: 'Intraoral Scan Review',
      progressPercent: 0.15,
      status: DentalCaseStatus.pendingImpression,
    ),
    DentalCaseOrder(
      caseId: '#DEN-4015',
      patient: 'Olivia Taylor',
      restorationType: 'Full Upper Denture',
      technician: 'Tech Alex Vance',
      stageName: 'Final Inspection',
      progressPercent: 1.0,
      status: DentalCaseStatus.completed,
    ),
  ];

  // Builds interleaved case rows with dividers between them.
  List<Widget> _buildCaseRows() {
    final rows = <Widget>[];
    for (int i = 0; i < _cases.length; i++) {
      rows.add(_DentalRow(item: _cases[i]));
      if (i < _cases.length - 1) {
        rows.add(const Divider(height: 1, color: AppColors.surfaceVariant));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: AppColors.outlineVariant),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Card Header ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: const BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              border: Border(
                bottom: BorderSide(color: AppColors.surfaceVariant),
              ),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppSpacing.radiusXl),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Dental Lab Tracking Queue',
                    style: AppTypography.headlineMd,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.filter_list),
                      color: AppColors.onSurfaceVariant,
                      iconSize: 22,
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.more_vert),
                      color: AppColors.onSurfaceVariant,
                      iconSize: 22,
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ── Table (horizontally scrollable on narrow screens) ────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 650,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Column headers
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 4),
                        Expanded(flex: 2, child: _HeaderCell('Case ID')),
                        Expanded(flex: 3, child: _HeaderCell('Patient')),
                        Expanded(flex: 3, child: _HeaderCell('Restoration')),
                        Expanded(flex: 3, child: _HeaderCell('Technician')),
                        Expanded(flex: 3, child: _HeaderCell('Stage')),
                        Expanded(
                          flex: 2,
                          child: _HeaderCell('Status', alignRight: true),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.surfaceVariant),
                  // Data rows with dividers
                  ..._buildCaseRows(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text, {this.alignRight = false});
  final String text;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
      style: AppTypography.labelCaps.copyWith(
        color: AppColors.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _DentalRow extends StatelessWidget {
  const _DentalRow({required this.item});
  final DentalCaseOrder item;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: item.hasAiHighlight
            ? AppColors.secondaryContainer.withValues(alpha: 0.15)
            : AppColors.surfaceContainerLowest,
        border: Border(
          left: BorderSide(
            width: 4,
            color:
                item.hasAiHighlight ? AppColors.secondary : Colors.transparent,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
          horizontal: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                item.caseId,
                style: AppTypography.dataMono.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                item.patient,
                style: AppTypography.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                item.restorationType,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                item.technician,
                style: AppTypography.bodySm.copyWith(
                  color: item.technician == 'Unassigned'
                      ? AppColors.error
                      : AppColors.onSurfaceVariant,
                  fontWeight: item.technician == 'Unassigned'
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    item.stageName.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: item.progressPercent,
                    backgroundColor: AppColors.surfaceVariant,
                    color: item.status == DentalCaseStatus.qaReview
                        ? AppColors.secondary
                        : AppColors.primaryContainer,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: _StatusBadge(status: item.status),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final DentalCaseStatus status;

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case DentalCaseStatus.inProduction:
        bgColor = AppColors.primaryContainer.withValues(alpha: 0.15);
        textColor = AppColors.primaryContainer;
        label = 'Production';
        break;
      case DentalCaseStatus.qaReview:
        bgColor = AppColors.secondaryContainer.withValues(alpha: 0.2);
        textColor = AppColors.secondary;
        label = 'QA Review';
        break;
      case DentalCaseStatus.pendingImpression:
        bgColor = AppColors.errorContainer;
        textColor = AppColors.onErrorContainer;
        label = 'Impression';
        break;
      case DentalCaseStatus.completed:
        bgColor = AppColors.surfaceContainerHigh;
        textColor = AppColors.onSurface;
        label = 'Completed';
        break;
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
      ),
    );
  }
}
