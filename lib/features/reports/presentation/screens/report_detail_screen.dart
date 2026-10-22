import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exceptions.dart';
import '../../application/reports_providers.dart';
import '../../data/models/report_model.dart';
import '../../domain/report_enums.dart';
import '../report_format.dart';
import '../report_style.dart';
import '../widgets/duplicate_suggestions_card.dart';
import '../widgets/report_history.dart';
import '../widgets/report_image.dart';
import '../widgets/report_status_chip.dart';

class ReportDetailScreen extends ConsumerWidget {
  final String reportId;
  final ReportModel? initial;

  const ReportDetailScreen({super.key, required this.reportId, this.initial});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncReport = ref.watch(reportDetailProvider(reportId));

    return Scaffold(
      appBar: AppBar(
        title: Text(initial?.code ?? 'Report'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(reportDetailProvider(reportId)),
          ),
        ],
      ),
      body: asyncReport.when(
        loading: () => initial != null
            ? _ReportBody(report: initial!)
            : const Center(child: CircularProgressIndicator()),
        error: (e, _) => _DetailError(
          message: e is ApiException ? e.message : e.toString(),
          onRetry: () => ref.invalidate(reportDetailProvider(reportId)),
        ),
        data: (report) => _ReportBody(report: report),
      ),
    );
  }
}

class _ReportBody extends ConsumerWidget {
  final ReportModel report;

  const _ReportBody({required this.report});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _HeaderCard(report: report),
        if (report.imageUrl != null && report.imageUrl!.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          ReportImage(path: report.imageUrl!, height: 220),
        ],
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Description',
          child: Text(
            report.description.isEmpty
                ? 'No description provided.'
                : report.description,
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
        const SizedBox(height: 12),
        _StatusProgress(status: report.statusEnum),
        if (report.resolutionNotes != null) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Resolution',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 20,
                  color: Color(0xFF2E7D32),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    report.resolutionNotes!,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (report.rejectionReason != null) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Rejection reason',
            child: Text(
              report.rejectionReason!,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Details',
          child: Column(
            children: [
              _DetailRow(
                icon: Icons.local_offer_outlined,
                label: 'Category',
                value: _orDash(report.category),
              ),
              _DetailRow(
                icon: Icons.place_outlined,
                label: 'Location',
                value: _orDash(report.location),
              ),
              _DetailRow(
                icon: Icons.apartment_outlined,
                label: 'Assigned department',
                value: _orDash(report.assignedDepartment),
              ),
              _DetailRow(
                icon: Icons.schedule,
                label: 'Reported',
                value: formatDateTime(report.createdAt),
              ),
              _DetailRow(
                icon: Icons.update,
                label: 'Last updated',
                value: formatDateTime(report.updatedAt),
              ),
              if (report.resolvedAt != null)
                _DetailRow(
                  icon: Icons.check_circle_outline,
                  label: 'Resolved',
                  value: formatDateTime(report.resolvedAt!),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        DuplicateSuggestionsCard(
          description:
              'Optional ML check against your other reports. This is only a '
              'suggestion and never changes or merges a report.',
          checkLabel: 'Check possible duplicates',
          load: () =>
              ref.read(reportsRepositoryProvider).suggestDuplicates(report.id),
        ),
        const SizedBox(height: 12),
        ReportHistory(events: report.events),
        const SizedBox(height: 16),
        Center(
          child: Text(
            report.code,
            style: tt.labelSmall?.copyWith(
              letterSpacing: 1.2,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  static String _orDash(String? value) =>
      (value == null || value.trim().isEmpty) ? '—' : value;
}

class _HeaderCard extends StatelessWidget {
  final ReportModel report;

  const _HeaderCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = ReportStyle.statusColor(report.statusEnum);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [statusColor.withValues(alpha: 0.16), cs.surfaceContainerLow],
        ),
        border: Border.all(color: statusColor.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  report.code,
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              ReportStatusChip(status: report.statusEnum),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            report.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ReportPriorityTag(priority: report.priorityEnum),
              const SizedBox(width: 12),
              Text(
                'Priority',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusProgress extends StatelessWidget {
  final ReportStatus status;

  const _StatusProgress({required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == ReportStatus.rejected) {
      return _SectionCard(
        title: 'Status',
        child: Row(
          children: [
            Icon(Icons.cancel_outlined, color: ReportStyle.statusColor(status)),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'This report was rejected. Contact campus administration if '
                'you believe this was a mistake.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    const steps = [
      ReportStatus.submitted,
      ReportStatus.assigned,
      ReportStatus.inProgress,
      ReportStatus.resolved,
    ];
    final currentIndex = steps.indexOf(status);

    return _SectionCard(
      title: 'Progress',
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            _StepRow(
              label: steps[i].label,
              isDone: i < currentIndex,
              isCurrent: i == currentIndex,
              isLast: i == steps.length - 1,
            ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String label;
  final bool isDone;
  final bool isCurrent;
  final bool isLast;

  const _StepRow({
    required this.label,
    required this.isDone,
    required this.isCurrent,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeColor = cs.primary;
    final reached = isDone || isCurrent;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: reached ? activeColor : Colors.transparent,
                border: Border.all(
                  color: reached ? activeColor : cs.outlineVariant,
                  width: 2,
                ),
              ),
              child: isDone
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 22,
                color: isDone ? activeColor : cs.outlineVariant,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              color: reached ? cs.onSurface : cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

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
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _DetailError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 44, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            const Text(
              'Could not load this report',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
