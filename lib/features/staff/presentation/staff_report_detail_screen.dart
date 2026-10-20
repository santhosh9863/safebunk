import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../models/auth/staff_account.dart';
import '../../../providers/auth_provider.dart';
import '../../notifications/application/notification_providers.dart'
    show pulseBackendServiceProvider;
import '../../reports/data/models/report_model.dart';
import '../../reports/domain/report_enums.dart';
import '../../reports/presentation/report_format.dart';
import '../../reports/presentation/widgets/report_history.dart';
import '../../reports/presentation/widgets/report_image.dart';
import '../../reports/presentation/widgets/report_status_chip.dart';
import '../application/staff_providers.dart';

class StaffReportDetailScreen extends ConsumerStatefulWidget {
  final String reportId;
  final ReportModel? initial;

  const StaffReportDetailScreen({
    super.key,
    required this.reportId,
    this.initial,
  });

  @override
  ConsumerState<StaffReportDetailScreen> createState() =>
      _StaffReportDetailScreenState();
}

class _StaffReportDetailScreenState
    extends ConsumerState<StaffReportDetailScreen> {
  ReportModel? _latest;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final asyncReport = ref.watch(staffReportDetailProvider(widget.reportId));
    final auth = ref.watch(authProvider);
    final fallback = _latest ?? widget.initial;
    final imageHeaders = ref.watch(staffReportImageHeadersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(fallback?.code ?? 'Report'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => _refresh(),
          ),
        ],
      ),
      body: Stack(
        children: [
          asyncReport.when(
            loading: () => fallback != null
                ? _DetailBody(
                    report: fallback,
                    isAdmin: auth.isAdmin,
                    busy: _busy,
                    imageHeaders: imageHeaders,
                    onAssign: _assign,
                    onReject: _reject,
                    onAccept: _accept,
                    onProgress: _addProgressNote,
                    onResolve: _resolve,
                  )
                : const Center(child: CircularProgressIndicator()),
            error: (error, _) => _DetailError(
              message: error is ApiException ? error.message : error.toString(),
              onRetry: () => _refresh(),
            ),
            data: (report) => _DetailBody(
              report: report,
              isAdmin: auth.isAdmin,
              busy: _busy,
              imageHeaders: imageHeaders,
              onAssign: _assign,
              onReject: _reject,
              onAccept: _accept,
              onProgress: _addProgressNote,
              onResolve: _resolve,
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(staffReportDetailProvider(widget.reportId));
    try {
      final report = await ref.read(
        staffReportDetailProvider(widget.reportId).future,
      );
      if (mounted) setState(() => _latest = report);
    } catch (_) {
      // The provider error state renders the actionable message.
    }
  }

  Future<void> _accept(ReportModel report) {
    return _runAction(
      (token) => ref
          .read(pulseBackendServiceProvider)
          .acceptStaffReport(token, report.id),
      'Issue accepted. Work is now in progress.',
    );
  }

  Future<void> _addProgressNote(ReportModel report) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => const _TextEntryDialog(
        title: 'Add progress note',
        label: 'Progress note',
        hint: 'Parts ordered, access arranged, repair scheduled…',
        confirmLabel: 'Add note',
        minLength: 1,
      ),
    );
    if (note == null || !mounted) return;
    await _runAction(
      (token) => ref
          .read(pulseBackendServiceProvider)
          .addStaffProgressNote(token, report.id, note),
      'Progress note added.',
    );
  }

  Future<void> _resolve(ReportModel report) async {
    final notes = await showDialog<String>(
      context: context,
      builder: (_) => const _TextEntryDialog(
        title: 'Mark issue resolved',
        label: 'Resolution notes',
        hint: 'Describe the work completed and how the issue was verified.',
        confirmLabel: 'Mark resolved',
        minLength: 3,
      ),
    );
    if (notes == null || !mounted) return;
    await _runAction(
      (token) => ref
          .read(pulseBackendServiceProvider)
          .resolveStaffReport(token, report.id, notes),
      'Issue marked resolved.',
    );
  }

  Future<void> _reject(ReportModel report) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _TextEntryDialog(
        title: 'Reject report',
        label: 'Reason',
        hint:
            'Explain why this report is being rejected. The student will see this reason.',
        confirmLabel: 'Reject report',
        minLength: 3,
      ),
    );
    if (reason == null || !mounted) return;
    await _runAction(
      (token) => ref
          .read(pulseBackendServiceProvider)
          .rejectStaffReport(token, report.id, reason),
      'Report rejected.',
    );
  }

  Future<void> _assign(ReportModel report) async {
    final choice = await showDialog<_AssignmentChoice>(
      context: context,
      builder: (_) => _AssignStaffDialog(report: report),
    );
    if (choice == null || !mounted) return;
    await _runAction(
      (token) => ref
          .read(pulseBackendServiceProvider)
          .assignStaffReport(
            token,
            report.id,
            staffId: choice.staffId,
            department: choice.department,
          ),
      report.assignedStaff == null ? 'Report assigned.' : 'Report reassigned.',
    );
  }

  Future<void> _runAction(
    Future<ReportModel> Function(String token) action,
    String successMessage,
  ) async {
    if (_busy) return;
    final token = ref.read(authProvider).staffSession?.accessToken;
    if (token == null || token.trim().isEmpty) {
      unawaited(ref.read(authProvider.notifier).handleSessionExpired());
      return;
    }

    setState(() => _busy = true);
    try {
      final updated = await action(token);
      if (!mounted) return;
      setState(() => _latest = updated);
      ref.invalidate(staffReportsProvider);
      ref.invalidate(staffReportDetailProvider(widget.reportId));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } on SessionExpiredException {
      unawaited(ref.read(authProvider.notifier).handleSessionExpired());
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _DetailBody extends StatelessWidget {
  final ReportModel report;
  final bool isAdmin;
  final bool busy;
  final AsyncValue<Map<String, String>?> imageHeaders;
  final ValueChanged<ReportModel> onAssign;
  final ValueChanged<ReportModel> onReject;
  final ValueChanged<ReportModel> onAccept;
  final ValueChanged<ReportModel> onProgress;
  final ValueChanged<ReportModel> onResolve;

  const _DetailBody({
    required this.report,
    required this.isAdmin,
    required this.busy,
    required this.imageHeaders,
    required this.onAssign,
    required this.onReject,
    required this.onAccept,
    required this.onProgress,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final status = report.statusEnum;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _HeaderCard(report: report),
        if ((report.imageUrl ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          ReportImage(
            path: report.imageUrl!,
            height: 220,
            authHeaders: imageHeaders,
          ),
        ],
        const SizedBox(height: 12),
        _AssignmentCard(
          report: report,
          isAdmin: isAdmin,
          busy: busy,
          onAssign: onAssign,
        ),
        if (isAdmin && !status.isTerminal) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: busy ? null : () => onReject(report),
              icon: const Icon(Icons.block, size: 18),
              label: const Text('Reject report'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
        if (!isAdmin && status == ReportStatus.assigned) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy ? null : () => onAccept(report),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Accept issue'),
          ),
        ],
        if (!isAdmin && status == ReportStatus.inProgress) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : () => onProgress(report),
                icon: const Icon(Icons.notes_outlined, size: 18),
                label: const Text('Add progress note'),
              ),
              FilledButton.icon(
                onPressed: busy ? null : () => onResolve(report),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Mark resolved'),
              ),
            ],
          ),
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
        _DetailsCard(report: report),
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
        ReportHistory(events: report.events),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final ReportModel report;

  const _HeaderCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = report.statusEnum;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
            cs.surfaceContainerLow,
          ],
        ),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
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
              ReportStatusChip(status: status),
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
                report.category ?? 'Uncategorised',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  final ReportModel report;
  final bool isAdmin;
  final bool busy;
  final ValueChanged<ReportModel> onAssign;

  const _AssignmentCard({
    required this.report,
    required this.isAdmin,
    required this.busy,
    required this.onAssign,
  });

  @override
  Widget build(BuildContext context) {
    final assignee = report.assignedStaff?.displayLabel;
    final canAssign = isAdmin && !report.statusEnum.isTerminal;

    return _SectionCard(
      title: 'Assignment',
      child: Column(
        children: [
          _DetailRow(
            icon: Icons.person_outline,
            label: 'Assigned staff',
            value: assignee ?? 'Unassigned',
          ),
          _DetailRow(
            icon: Icons.apartment_outlined,
            label: 'Department',
            value: report.assignedDepartment ?? '—',
          ),
          if (report.assignedAt != null)
            _DetailRow(
              icon: Icons.event_available_outlined,
              label: 'Assigned',
              value: formatDateTime(report.assignedAt!),
            ),
          if (canAssign) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: busy ? null : () => onAssign(report),
                icon: const Icon(Icons.assignment_ind_outlined, size: 18),
                label: Text(
                  report.assignedStaff == null
                      ? 'Assign to staff'
                      : 'Reassign issue',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  final ReportModel report;

  const _DetailsCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Details',
      child: Column(
        children: [
          _DetailRow(
            icon: Icons.local_offer_outlined,
            label: 'Category',
            value: report.category ?? '—',
          ),
          _DetailRow(
            icon: Icons.place_outlined,
            label: 'Location',
            value: report.location ?? '—',
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
              letterSpacing: 1,
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

class _AssignmentChoice {
  final String staffId;
  final String? department;

  const _AssignmentChoice({required this.staffId, required this.department});
}

class _AssignStaffDialog extends ConsumerStatefulWidget {
  final ReportModel report;

  const _AssignStaffDialog({required this.report});

  @override
  ConsumerState<_AssignStaffDialog> createState() => _AssignStaffDialogState();
}

class _AssignStaffDialogState extends ConsumerState<_AssignStaffDialog> {
  String? _staffId;
  late final TextEditingController _department;

  @override
  void initState() {
    super.initState();
    _staffId = widget.report.assignedStaff?.id;
    _department = TextEditingController(
      text: widget.report.assignedDepartment ?? '',
    );
  }

  @override
  void dispose() {
    _department.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(assignableStaffProvider);
    final available = accounts.valueOrNull ?? const <StaffAccount>[];
    final selected = available.any((account) => account.id == _staffId)
        ? _staffId
        : null;

    return AlertDialog(
      title: Text(
        widget.report.assignedStaff == null ? 'Assign issue' : 'Reassign issue',
      ),
      content: SizedBox(
        width: 420,
        child: accounts.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, _) => Text(
            error is ApiException
                ? error.message
                : 'Could not load staff accounts.',
          ),
          data: (items) {
            if (items.isEmpty) {
              return const Text(
                'No active STAFF accounts are available. Provision a STAFF account before assigning issues.',
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  decoration: const InputDecoration(
                    labelText: 'Staff member',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final account in items)
                      DropdownMenuItem(
                        value: account.id,
                        child: Text(
                          account.displayLabel,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _staffId = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _department,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Department (optional)',
                    hintText: 'e.g. Maintenance',
                    prefixIcon: Icon(Icons.apartment_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (available.isNotEmpty)
          FilledButton(
            onPressed: selected == null
                ? null
                : () => Navigator.of(context).pop(
                    _AssignmentChoice(
                      staffId: selected,
                      department: _department.text.trim(),
                    ),
                  ),
            child: const Text('Assign'),
          ),
      ],
    );
  }
}

class _TextEntryDialog extends StatefulWidget {
  final String title;
  final String label;
  final String hint;
  final String confirmLabel;
  final int minLength;

  const _TextEntryDialog({
    required this.title,
    required this.label,
    required this.hint,
    required this.confirmLabel,
    required this.minLength,
  });

  @override
  State<_TextEntryDialog> createState() => _TextEntryDialogState();
}

class _TextEntryDialogState extends State<_TextEntryDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.text.trim();
    final valid = value.length >= widget.minLength;

    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        maxLength: 4000,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          alignLabelWithHint: true,
          border: const OutlineInputBorder(),
          helperText: widget.minLength > 1
              ? 'At least ${widget.minLength} characters'
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: valid ? () => Navigator.of(context).pop(value) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
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
              'Could not load this issue',
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
