import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/calculations/attendance_utils.dart';
import '../../../models/api/subject_wise_attendance_model.dart';
import '../../settings/providers/settings_providers.dart';

class AttendanceBarChart extends StatelessWidget {
  final List<SubjectWiseAttendanceModel> subjects;
  final double target;

  const AttendanceBarChart({super.key, required this.subjects, required this.target});

  @override
  Widget build(BuildContext context) {
    if (subjects.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final (danger, safe, _) = computeThresholds(target);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'Attendance Comparison',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'Subject-wise attendance percentages',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 260,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 100,
                  minY: 0,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      tooltipMargin: 8,
                      getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                        getTooltipItem: (group, _, rod, _) {
                        final index = group.x;
                        if (index < 0 || index >= subjects.length) return null;
                        final subject = subjects[index];
                        return BarTooltipItem(
                          '${AttendanceUtils.cleanSubjectName(subject.subjectName)}\n',
                          TextStyle(
                            color: theme.colorScheme.onInverseSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          children: [
                            TextSpan(
                              text: '${rod.toY.toStringAsFixed(1)}%',
                              style: TextStyle(
                                color: _barColor(rod.toY),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 38,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= subjects.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              _shortenSubjectName(subjects[index].subjectName),
                              style: const TextStyle(fontSize: 9),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        interval: 25,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(
                              '${value.toInt()}%',
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    horizontalInterval: 25,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) {
                      final (_, safe, _) = computeThresholds(target);
                      if (value == safe) {
                        return FlLine(
                          color: Colors.red.withValues(alpha: 0.6),
                          strokeWidth: 2,
                          dashArray: [6, 4],
                        );
                      }
                      return FlLine(
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: subjects.asMap().entries.map((entry) {
                    final pct = entry.value.finalPercentage;
                    return BarChartGroupData(
                      x: entry.key,
                      barRods: [
                        BarChartRodData(
                          toY: pct.clamp(0, 100),
                          color: _barColor(pct),
                          width: 22,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(4),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
                swapAnimationDuration: const Duration(milliseconds: 400),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LegendDot(color: Colors.red, label: '<$danger'),
                  const SizedBox(width: 16),
                  _LegendDot(color: Colors.orange, label: '$danger-$safe%'),
                  const SizedBox(width: 16),
                  _LegendDot(color: Colors.green, label: '≥$safe%'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _barColor(double pct) {
    final (danger, safe, _) = computeThresholds(target);
    if (pct < danger) return Colors.red;
    if (pct < safe) return Colors.orange;
    return Colors.green;
  }
}

const _subjectLabelMap = <String, String>{
  'artificial intelligence': 'AI',
  'artificial intelligence lab': 'AIL',
  'design and analysis of algorithms': 'DAA',
  'design and analysis of algorithms lab': 'DAL',
  'internet technologies': 'IT',
  'internet technologies lab': 'ITL',
  'ethical hacking': 'EH',
  'probability and statistics': 'PS',
  'general english': 'ENG',
  'kannada': 'KAN',
};

String _shortenSubjectName(String name) {
  final cleaned = name.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
  return _subjectLabelMap[cleaned.toLowerCase()] ?? cleaned;
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
