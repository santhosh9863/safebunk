import 'package:flutter/material.dart';

import '../../data/models/report_model.dart';
import '../report_format.dart';
import 'report_status_chip.dart';

/// A tappable report summary card used in the Reports list.
class ReportCard extends StatelessWidget {
  final ReportModel report;
  final VoidCallback onTap;
  final bool showAssignee;

  const ReportCard({
    super.key,
    required this.report,
    required this.onTap,
    this.showAssignee = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      report.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ReportStatusChip(status: report.statusEnum, dense: true),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  ReportPriorityTag(priority: report.priorityEnum),
                  const SizedBox(width: 14),
                  if ((report.category ?? '').isNotEmpty)
                    Flexible(
                      child: _MetaItem(
                        icon: Icons.local_offer_outlined,
                        text: report.category!,
                      ),
                    ),
                ],
              ),
              if ((report.location ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                _MetaItem(icon: Icons.place_outlined, text: report.location!),
              ],
              if (showAssignee && report.assignedStaff != null) ...[
                const SizedBox(height: 8),
                _MetaItem(
                  icon: Icons.person_outline,
                  text: 'Assigned to ${report.assignedStaff!.displayLabel}',
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      report.code,
                      style: tt.labelSmall?.copyWith(
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    formatRelativeTime(report.createdAt),
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
