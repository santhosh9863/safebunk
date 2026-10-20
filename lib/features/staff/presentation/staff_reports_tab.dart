import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../providers/auth_provider.dart';
import '../../reports/data/models/report_model.dart';
import '../../reports/domain/report_enums.dart';
import '../../reports/presentation/widgets/report_card.dart';
import '../application/staff_providers.dart';
import 'staff_report_detail_screen.dart';

class _ReportFilter {
  final String label;
  final ReportStatus? status;

  const _ReportFilter(this.label, this.status);
}

const _staffFilters = [
  _ReportFilter('Assigned', ReportStatus.assigned),
  _ReportFilter('In Progress', ReportStatus.inProgress),
  _ReportFilter('Resolved', ReportStatus.resolved),
];

const _adminFilters = [
  _ReportFilter('All', null),
  _ReportFilter('Submitted', ReportStatus.submitted),
  _ReportFilter('Assigned', ReportStatus.assigned),
  _ReportFilter('In Progress', ReportStatus.inProgress),
  _ReportFilter('Resolved', ReportStatus.resolved),
  _ReportFilter('Rejected', ReportStatus.rejected),
];

/// Assignment-aware report queue for STAFF and ADMIN identities.
///
/// The backend scopes STAFF requests to the logged-in staffId; ADMIN receives
/// every campus report. Filters are presentation-only and never widen access.
class StaffReportsTab extends ConsumerWidget {
  const StaffReportsTab({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(staffReportsProvider);
    try {
      await ref.read(staffReportsProvider.future);
    } catch (_) {
      // The provider's error state renders the actionable message.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final isAdmin = auth.isAdmin;
    final filters = isAdmin ? _adminFilters : _staffFilters;
    final reports = ref.watch(staffReportsProvider);

    return DefaultTabController(
      length: filters.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(isAdmin ? 'Campus Reports' : 'My Assigned Issues'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => _refresh(ref),
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final filter in filters)
                Tab(
                  text: reports.maybeWhen(
                    data: (items) {
                      final count = filter.status == null
                          ? items.length
                          : items
                                .where((r) => r.statusEnum == filter.status)
                                .length;
                      return count == 0
                          ? filter.label
                          : '${filter.label} ($count)';
                    },
                    orElse: () => filter.label,
                  ),
                ),
            ],
          ),
        ),
        body: reports.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _StaffReportsError(
            message: error is ApiException ? error.message : error.toString(),
            onRetry: () => _refresh(ref),
          ),
          data: (items) => TabBarView(
            children: [
              for (final filter in filters)
                _ReportList(
                  items: filter.status == null
                      ? items
                      : items
                            .where((r) => r.statusEnum == filter.status)
                            .toList(growable: false),
                  filter: filter,
                  isAdmin: isAdmin,
                  onRefresh: () => _refresh(ref),
                  onOpen: (report) => _openReport(context, report),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openReport(BuildContext context, ReportModel report) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            StaffReportDetailScreen(reportId: report.id, initial: report),
      ),
    );
  }
}

class _ReportList extends StatelessWidget {
  final List<ReportModel> items;
  final _ReportFilter filter;
  final bool isAdmin;
  final Future<void> Function() onRefresh;
  final ValueChanged<ReportModel> onOpen;

  const _ReportList({
    required this.items,
    required this.filter,
    required this.isAdmin,
    required this.onRefresh,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _QueueBanner(isAdmin: isAdmin),
          if (items.isEmpty)
            _EmptyReports(filter: filter, isAdmin: isAdmin)
          else
            for (final report in items)
              ReportCard(
                report: report,
                showAssignee: isAdmin,
                onTap: () => onOpen(report),
              ),
        ],
      ),
    );
  }
}

class _QueueBanner extends StatelessWidget {
  final bool isAdmin;

  const _QueueBanner({required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              isAdmin ? Icons.assignment_outlined : Icons.handyman_outlined,
              size: 18,
              color: cs.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isAdmin
                    ? 'All campus reports. Assign or reassign work to active STAFF accounts.'
                    : 'Issues assigned to you. Accept work, add progress notes, and resolve completed repairs.',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyReports extends StatelessWidget {
  final _ReportFilter filter;
  final bool isAdmin;

  const _EmptyReports({required this.filter, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = filter.status == null
        ? 'No reports yet'
        : 'No ${filter.label.toLowerCase()} reports';
    final message = isAdmin
        ? 'Reports matching this filter will appear here.'
        : 'Reports assigned to you will appear here once an administrator assigns them.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 32),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 52, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _StaffReportsError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _StaffReportsError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 48),
        Icon(Icons.cloud_off, size: 48, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        const Text(
          'Could not load reports',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}
