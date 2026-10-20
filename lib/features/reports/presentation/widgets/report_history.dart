import 'package:flutter/material.dart';

import '../../data/models/report_event.dart';
import '../report_format.dart';

/// Read-only activity/status timeline shown on student and staff report details.
class ReportHistory extends StatelessWidget {
  final List<ReportEventModel> events;

  const ReportHistory({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ACTIVITY',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (events.isEmpty)
            Text(
              'No activity recorded yet.',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            )
          else
            for (var i = 0; i < events.length; i++)
              _HistoryRow(event: events[i], isLast: i == events.length - 1),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final ReportEventModel event;
  final bool isLast;

  const _HistoryRow({required this.event, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _eventColor(context, event.typeEnum);
    final remark = event.remark;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(_eventIcon(event.typeEnum), size: 17, color: color),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: cs.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.typeEnum.label,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        formatDateTime(event.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _actorLabel(event.actorRole),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  if (remark != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      remark,
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _actorLabel(String role) {
    return switch (role.trim().toUpperCase()) {
      'STUDENT' => 'Reported by student',
      'STAFF' => 'Campus staff',
      'ADMIN' => 'Campus administration',
      _ => 'PULSE',
    };
  }

  static IconData _eventIcon(ReportEventType type) {
    return switch (type) {
      ReportEventType.submitted => Icons.upload_file_outlined,
      ReportEventType.assigned => Icons.person_add_alt_1_outlined,
      ReportEventType.reassigned => Icons.swap_horiz,
      ReportEventType.inProgress => Icons.build_outlined,
      ReportEventType.progressNote => Icons.notes_outlined,
      ReportEventType.resolved => Icons.check_circle_outline,
      ReportEventType.rejected => Icons.cancel_outlined,
      ReportEventType.unknown => Icons.history,
    };
  }

  static Color _eventColor(BuildContext context, ReportEventType type) {
    final cs = Theme.of(context).colorScheme;
    return switch (type) {
      ReportEventType.submitted => cs.primary,
      ReportEventType.assigned || ReportEventType.reassigned => cs.tertiary,
      ReportEventType.inProgress => const Color(0xFFE08A00),
      ReportEventType.progressNote => cs.secondary,
      ReportEventType.resolved => const Color(0xFF2E7D32),
      ReportEventType.rejected => cs.error,
      ReportEventType.unknown => cs.onSurfaceVariant,
    };
  }
}
