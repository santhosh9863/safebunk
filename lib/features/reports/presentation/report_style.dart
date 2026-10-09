import 'package:flutter/material.dart';

import '../domain/report_enums.dart';

/// Presentation mapping for report status/priority. Kept in the presentation
/// layer so the domain enums stay Flutter-free.
class ReportStyle {
  ReportStyle._();

  static Color statusColor(ReportStatus status) {
    switch (status) {
      case ReportStatus.submitted:
        return const Color(0xFF2563EB); // blue
      case ReportStatus.assigned:
        return const Color(0xFF7C3AED); // violet
      case ReportStatus.inProgress:
        return const Color(0xFFEA580C); // orange
      case ReportStatus.resolved:
        return const Color(0xFF16A34A); // green
      case ReportStatus.rejected:
        return const Color(0xFFDC2626); // red
    }
  }

  static IconData statusIcon(ReportStatus status) {
    switch (status) {
      case ReportStatus.submitted:
        return Icons.mark_email_unread_outlined;
      case ReportStatus.assigned:
        return Icons.assignment_ind_outlined;
      case ReportStatus.inProgress:
        return Icons.autorenew;
      case ReportStatus.resolved:
        return Icons.check_circle_outline;
      case ReportStatus.rejected:
        return Icons.cancel_outlined;
    }
  }

  static Color priorityColor(ReportPriority priority) {
    switch (priority) {
      case ReportPriority.low:
        return const Color(0xFF64748B); // slate
      case ReportPriority.medium:
        return const Color(0xFF0EA5E9); // sky
      case ReportPriority.high:
        return const Color(0xFFF59E0B); // amber
      case ReportPriority.critical:
        return const Color(0xFFDC2626); // red
    }
  }

  static IconData priorityIcon(ReportPriority priority) {
    switch (priority) {
      case ReportPriority.low:
        return Icons.keyboard_arrow_down;
      case ReportPriority.medium:
        return Icons.remove;
      case ReportPriority.high:
        return Icons.keyboard_arrow_up;
      case ReportPriority.critical:
        return Icons.priority_high;
    }
  }
}
