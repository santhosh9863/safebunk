import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exceptions.dart';
import '../../application/reports_providers.dart';
import '../../data/models/report_model.dart';
import '../../domain/report_enums.dart';
import '../widgets/report_card.dart';
import '../report_style.dart';
import 'create_report_screen.dart';
import 'report_detail_screen.dart';

/// The Reports tab: the authenticated student's own reports with status
/// filtering, pull-to-refresh and a create-report entry point.
class ReportsTab extends ConsumerStatefulWidget {
  const ReportsTab({super.key});

  @override
  ConsumerState<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<ReportsTab> {
  Future<void> _refresh() async {
    ref.invalidate(reportsListProvider);
    await ref.read(reportsListProvider.future);
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<ReportModel>(
      MaterialPageRoute(builder: (_) => const CreateReportScreen()),
    );
    if (created == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Report ${created.code} submitted'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReportDetailScreen(reportId: created.id, initial: created),
      ),
    );
  }

  void _openDetail(ReportModel report) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReportDetailScreen(reportId: report.id, initial: report),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncAll = ref.watch(reportsListProvider);
    final asyncFiltered = ref.watch(filteredReportsProvider);
    final filter = ref.watch(reportStatusFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Report'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: asyncFiltered.when(
          loading: () => _scrollable([const _LoadingState()]),
          error: (e, _) => _scrollable([
            _ErrorState(
              message: e is ApiException ? e.message : e.toString(),
              onRetry: _refresh,
            ),
          ]),
          data: (reports) {
            final all = asyncAll.valueOrNull ?? reports;
            return _scrollable([
              _SummaryHeader(reports: all),
              const SizedBox(height: 16),
              _FilterBar(selected: filter),
              const SizedBox(height: 14),
              if (reports.isEmpty)
                _EmptyState(
                  hasAnyReports: all.isNotEmpty,
                  filter: filter,
                  onCreate: _openCreate,
                  onClearFilter: () =>
                      ref.read(reportStatusFilterProvider.notifier).state = null,
                )
              else
                ...reports.map(
                  (r) => ReportCard(report: r, onTap: () => _openDetail(r)),
                ),
              const SizedBox(height: 80),
            ]);
          },
        ),
      ),
    );
  }

  Widget _scrollable(List<Widget> children) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: children,
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  final List<ReportModel> reports;

  const _SummaryHeader({required this.reports});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final open = reports.where((r) => r.statusEnum.isOpen).length;
    final resolved = reports
        .where((r) => r.statusEnum == ReportStatus.resolved)
        .length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withValues(alpha: 0.16),
            cs.surfaceContainerLow,
          ],
        ),
        border: Border.all(color: cs.primary.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.campaign_outlined, color: cs.primary),
              const SizedBox(width: 8),
              const Text(
                'My Reports',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Track the campus issues you have reported.',
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _Stat(label: 'Total', value: '${reports.length}'),
              const SizedBox(width: 10),
              _Stat(label: 'Open', value: '$open'),
              const SizedBox(width: 10),
              _Stat(label: 'Resolved', value: '$resolved'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  final ReportStatus? selected;

  const _FilterBar({required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(
            context,
            label: 'All',
            isSelected: selected == null,
            onTap: () =>
                ref.read(reportStatusFilterProvider.notifier).state = null,
          ),
          for (final status in ReportStatus.values)
            _chip(
              context,
              label: status.label,
              isSelected: selected == status,
              color: ReportStyle.statusColor(status),
              onTap: () =>
                  ref.read(reportStatusFilterProvider.notifier).state = status,
            ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    Color? color,
  }) {
    final cs = Theme.of(context).colorScheme;
    final accent = color ?? cs.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onTap(),
        selectedColor: accent.withValues(alpha: 0.18),
        labelStyle: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: isSelected ? accent : cs.onSurfaceVariant,
        ),
        side: BorderSide(
          color: isSelected ? accent.withValues(alpha: 0.5) : cs.outlineVariant,
        ),
        showCheckmark: false,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasAnyReports;
  final ReportStatus? filter;
  final VoidCallback onCreate;
  final VoidCallback onClearFilter;

  const _EmptyState({
    required this.hasAnyReports,
    required this.filter,
    required this.onCreate,
    required this.onClearFilter,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = hasAnyReports && filter != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Column(
        children: [
          Icon(
            filtered ? Icons.filter_alt_off_outlined : Icons.report_gmailerrorred_outlined,
            size: 56,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(height: 14),
          Text(
            filtered ? 'No ${filter!.label.toLowerCase()} reports' : 'No reports yet',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            filtered
                ? 'Try a different status filter.'
                : 'Spotted a campus issue? Report it and track it here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          if (filtered)
            OutlinedButton.icon(
              onPressed: onClearFilter,
              icon: const Icon(Icons.clear, size: 18),
              label: const Text('Clear filter'),
            )
          else
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Report an issue'),
            ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 120),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.cloud_off, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            const Text(
              'Could not load reports',
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
