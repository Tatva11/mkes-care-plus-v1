import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

enum OrderStatus { inProgress, review, blocked }

class OpticalOrder {
  final String orderId;
  final String patient;
  final String lensType;
  final String stepName;
  final double progressPercent;
  final OrderStatus status;
  final bool hasAiHighlight;

  const OpticalOrder({
    required this.orderId,
    required this.patient,
    required this.lensType,
    required this.stepName,
    required this.progressPercent,
    required this.status,
    this.hasAiHighlight = false,
  });
}

class OpticalProductionQueueCard extends StatelessWidget {
  const OpticalProductionQueueCard({super.key});

  static const _orders = [
    OpticalOrder(
      orderId: '#OPT-8832',
      patient: 'Sarah Jenkins',
      lensType: 'Single Vision • Poly',
      stepName: 'Lens Cutting',
      progressPercent: 0.6,
      status: OrderStatus.inProgress,
    ),
    OpticalOrder(
      orderId: '#OPT-8833',
      patient: 'Michael Chang',
      lensType: 'Progressive',
      stepName: 'Quality Check',
      progressPercent: 0.9,
      status: OrderStatus.review,
      hasAiHighlight: true,
    ),
    OpticalOrder(
      orderId: '#OPT-8834',
      patient: 'Emily Davis',
      lensType: 'Bifocal • Glass',
      stepName: 'Frame Fitting',
      progressPercent: 0.3,
      status: OrderStatus.inProgress,
    ),
    OpticalOrder(
      orderId: '#OPT-8835',
      patient: 'Robert Wilson',
      lensType: 'Single Vision • High Index',
      stepName: 'Pending Blanks',
      progressPercent: 0.0,
      status: OrderStatus.blocked,
    ),
  ];

  // Builds interleaved order rows with dividers between them.
  List<Widget> _buildOrderRows() {
    final rows = <Widget>[];
    for (int i = 0; i < _orders.length; i++) {
      rows.add(_OrderRow(order: _orders[i]));
      if (i < _orders.length - 1) {
        rows.add(const Divider(height: 1, color: AppColors.surfaceVariant));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
                    'Optical Production Queue',
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
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.more_vert),
                      color: AppColors.onSurfaceVariant,
                      iconSize: 22,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
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
              width: 600,
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
                        Expanded(flex: 2, child: _HeaderCell('Order ID')),
                        Expanded(flex: 3, child: _HeaderCell('Patient')),
                        Expanded(flex: 3, child: _HeaderCell('Lens Type')),
                        Expanded(flex: 3, child: _HeaderCell('Progress')),
                        Expanded(
                          flex: 2,
                          child: _HeaderCell('Status', alignRight: true),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.surfaceVariant),
                  // Data rows with dividers
                  ..._buildOrderRows(),
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

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});
  final OpticalOrder order;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: order.hasAiHighlight
            ? AppColors.surfaceContainerLow.withValues(alpha: 0.3)
            : const Color(0xFFFEFEFD),
        border: Border(
          left: BorderSide(
            width: 4,
            color: order.hasAiHighlight
                ? AppColors.primaryContainer
                : Colors.transparent,
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
                order.orderId,
                style: AppTypography.dataMono.copyWith(
                  color: AppColors.outline,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                order.patient,
                style: AppTypography.bodySm.copyWith(
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurface,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      order.lensType,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (order.hasAiHighlight) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: AppColors.primaryContainer,
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: _ProgressCell(
                stepName: order.stepName,
                percent: order.progressPercent,
                status: order.status,
              ),
            ),
            Expanded(
              flex: 2,
              child: _StatusBadge(status: order.status),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressCell extends StatelessWidget {
  const _ProgressCell({
    required this.stepName,
    required this.percent,
    required this.status,
  });

  final String stepName;
  final double percent;
  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    Color progressColor;
    if (status == OrderStatus.review) {
      progressColor = AppColors.tertiary; // muted-rose (#B3659A)
    } else if (status == OrderStatus.blocked) {
      progressColor = AppColors.error;
    } else {
      progressColor = AppColors.primaryContainer;
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                stepName.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${(percent * 100).toInt()}%',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: progressColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 6,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(3),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: percent,
            child: Container(
              decoration: BoxDecoration(
                color: progressColor,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case OrderStatus.inProgress:
        bgColor = AppColors.surfaceContainerHigh;
        textColor = AppColors.onSurfaceVariant;
        label = 'In Progress';
        break;
      case OrderStatus.review:
        bgColor = AppColors.tertiaryContainer.withValues(alpha: 0.2);
        textColor = AppColors.onTertiaryContainer;
        label = 'Review';
        break;
      case OrderStatus.blocked:
        bgColor = AppColors.errorContainer;
        textColor = AppColors.onErrorContainer;
        label = 'Blocked';
        break;
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
    );
  }
}
