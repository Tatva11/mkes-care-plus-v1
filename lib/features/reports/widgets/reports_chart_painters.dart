import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Data point for line charts
class ChartDataPoint {
  final String label;
  final double value;
  final double? secondaryValue;

  const ChartDataPoint({
    required this.label,
    required this.value,
    this.secondaryValue,
  });
}

/// 1. Custom Smooth Line Trend Chart
class ReportsLineChart extends StatelessWidget {
  final List<ChartDataPoint> data;
  final String? primaryLabel;
  final String? secondaryLabel;
  final Color primaryColor;
  final Color secondaryColor;
  final double height;
  final String Function(double)? valueFormatter;

  const ReportsLineChart({
    super.key,
    required this.data,
    this.primaryLabel,
    this.secondaryLabel,
    this.primaryColor = const Color(0xFF0D9488),
    this.secondaryColor = const Color(0xFF6366F1),
    this.height = 220,
    this.valueFormatter,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text('No trend data for selected period', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          if (primaryLabel != null || secondaryLabel != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (primaryLabel != null) ...[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      primaryLabel!,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  if (secondaryLabel != null) ...[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: secondaryColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      secondaryLabel!,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: _LineChartPainter(
                data: data,
                primaryColor: primaryColor,
                secondaryColor: secondaryColor,
                isDark: isDark,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // X-Axis labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: _buildXAxisLabels(isDark),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildXAxisLabels(bool isDark) {
    if (data.isEmpty) return [];
    final step = math.max(1, (data.length / 6).floor());
    final List<Widget> labels = [];
    for (int i = 0; i < data.length; i += step) {
      labels.add(
        Text(
          data[i].label,
          style: TextStyle(
            fontSize: 10,
            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
          ),
        ),
      );
    }
    return labels;
  }
}

class _LineChartPainter extends CustomPainter {
  final List<ChartDataPoint> data;
  final Color primaryColor;
  final Color secondaryColor;
  final bool isDark;

  _LineChartPainter({
    required this.data,
    required this.primaryColor,
    required this.secondaryColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final gridPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Draw horizontal grid lines
    const gridLines = 4;
    for (int i = 0; i <= gridLines; i++) {
      final y = size.height * (i / gridLines);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    double maxValue = 1.0;
    for (final p in data) {
      if (p.value > maxValue) maxValue = p.value;
      if (p.secondaryValue != null && p.secondaryValue! > maxValue) {
        maxValue = p.secondaryValue!;
      }
    }
    // Add 15% headroom
    maxValue *= 1.15;

    // Draw Secondary line if present
    final hasSecondary = data.any((p) => p.secondaryValue != null);
    if (hasSecondary) {
      _drawLineAndArea(
        canvas: canvas,
        size: size,
        color: secondaryColor,
        maxValue: maxValue,
        getValue: (p) => p.secondaryValue ?? 0.0,
      );
    }

    // Draw Primary line
    _drawLineAndArea(
      canvas: canvas,
      size: size,
      color: primaryColor,
      maxValue: maxValue,
      getValue: (p) => p.value,
    );
  }

  void _drawLineAndArea({
    required Canvas canvas,
    required Size size,
    required Color color,
    required double maxValue,
    required double Function(ChartDataPoint) getValue,
  }) {
    final points = <Offset>[];
    final dx = data.length > 1 ? size.width / (data.length - 1) : size.width / 2;

    for (int i = 0; i < data.length; i++) {
      final val = getValue(data[i]);
      final normalizedY = size.height - (val / maxValue * size.height);
      final x = data.length == 1 ? size.width / 2 : i * dx;
      points.add(Offset(x, normalizedY.clamp(0.0, size.height)));
    }

    if (points.isEmpty) return;

    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final controlX = (p0.dx + p1.dx) / 2;
      path.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
    }

    // Gradient Area
    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.25),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);

    // Stroke
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, linePaint);

    // Points
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final dotBorderPaint = Paint()
      ..color = isDark ? const Color(0xFF1E293B) : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final p in points) {
      canvas.drawCircle(p, 4, dotPaint);
      canvas.drawCircle(p, 4, dotBorderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) => true;
}

/// 2. Bar Chart for Comparisons
class ReportsBarChart extends StatelessWidget {
  final List<ChartDataPoint> data;
  final Color barColor;
  final double height;

  const ReportsBarChart({
    super.key,
    required this.data,
    this.barColor = const Color(0xFF0D9488),
    this.height = 180,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text('No comparison data available', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    double maxVal = 1.0;
    for (final d in data) {
      if (d.value > maxVal) maxVal = d.value;
    }

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: data.map((item) {
          final ratio = (item.value / maxVal).clamp(0.02, 1.0);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    item.value.toStringAsFixed(0),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: (height - 45) * ratio,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Segment item for Donut Chart
class DonutSegment {
  final String label;
  final double value;
  final Color color;

  const DonutSegment({
    required this.label,
    required this.value,
    required this.color,
  });
}

/// 3. Donut Composition Chart
class ReportsDonutChart extends StatelessWidget {
  final List<DonutSegment> segments;
  final String centerTitle;
  final String centerSubtitle;
  final double size;

  const ReportsDonutChart({
    super.key,
    required this.segments,
    this.centerTitle = '',
    this.centerSubtitle = '',
    this.size = 170,
  });

  @override
  Widget build(BuildContext context) {
    final double total = segments.fold(0.0, (sum, s) => sum + s.value);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (total == 0) {
      return SizedBox(
        height: size,
        child: const Center(
          child: Text('No breakdown data', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(size, size),
                painter: _DonutPainter(
                  segments: segments,
                  total: total,
                  strokeWidth: 20,
                  isDark: isDark,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    centerTitle,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  if (centerSubtitle.isNotEmpty)
                    Text(
                      centerSubtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: segments.map((seg) {
            final pct = (seg.value / total * 100).toStringAsFixed(1);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: seg.color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    seg.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$pct% (${seg.value.toInt()})',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<DonutSegment> segments;
  final double total;
  final double strokeWidth;
  final bool isDark;

  _DonutPainter({
    required this.segments,
    required this.total,
    required this.strokeWidth,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    double startAngle = -math.pi / 2;

    for (final seg in segments) {
      if (seg.value <= 0) continue;
      final sweepAngle = (seg.value / total) * 2 * math.pi;

      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle - 0.04, // slight segment gap
        false,
        paint,
      );

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}

/// 4. Department Proportion Bar
class DepartmentRatioBar extends StatelessWidget {
  final double eyePercentage;
  final double dentalPercentage;
  final int eyeCount;
  final int dentalCount;

  const DepartmentRatioBar({
    super.key,
    required this.eyePercentage,
    required this.dentalPercentage,
    required this.eyeCount,
    required this.dentalCount,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = eyeCount + dentalCount;
    final effectiveEyePct = total > 0 ? (eyeCount / total) : 0.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.remove_red_eye_outlined, size: 16, color: Color(0xFF0D9488)),
                const SizedBox(width: 6),
                Text(
                  'Eye Care: ${eyeCount.toString()} (${eyePercentage.toStringAsFixed(1)}%)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.medical_services_outlined, size: 16, color: Color(0xFF6366F1)),
                const SizedBox(width: 6),
                Text(
                  'Dental Care: ${dentalCount.toString()} (${dentalPercentage.toStringAsFixed(1)}%)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 12,
            width: double.infinity,
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            child: Row(
              children: [
                Flexible(
                  flex: (effectiveEyePct * 1000).toInt(),
                  child: Container(color: const Color(0xFF0D9488)),
                ),
                Flexible(
                  flex: ((1.0 - effectiveEyePct) * 1000).toInt(),
                  child: Container(color: const Color(0xFF6366F1)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
