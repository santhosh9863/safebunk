import 'package:flutter/material.dart';

import '../../domain/report_enums.dart';
import '../report_style.dart';

/// Compact color-coded status pill for a report.
class ReportStatusChip extends StatelessWidget {
  final ReportStatus status;
  final bool dense;

  const ReportStatusChip({super.key, required this.status, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final color = ReportStyle.statusColor(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ReportStyle.statusIcon(status), size: dense ? 12 : 14, color: color),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: dense ? 11 : 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small priority indicator with a colored dot and label.
class ReportPriorityTag extends StatelessWidget {
  final ReportPriority priority;

  const ReportPriorityTag({super.key, required this.priority});

  @override
  Widget build(BuildContext context) {
    final color = ReportStyle.priorityColor(priority);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          priority.label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
