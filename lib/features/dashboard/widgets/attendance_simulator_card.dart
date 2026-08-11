import 'package:flutter/material.dart';

import 'attendance_simulation_helper.dart';

enum _ActionType { attend, miss }

class AttendanceSimulatorCard extends StatefulWidget {
  final List<SubjectEntry> subjects;
  final int totalPresent;
  final int totalHours;
  final double target;

  const AttendanceSimulatorCard({
    super.key,
    required this.subjects,
    required this.totalPresent,
    required this.totalHours,
    required this.target,
  });

  @override
  State<AttendanceSimulatorCard> createState() =>
      _AttendanceSimulatorCardState();
}

class _AttendanceSimulatorCardState extends State<AttendanceSimulatorCard> {
  int _selectedSubjectIndex = 0;
  int _hours = 1;
  _ActionType _action = _ActionType.miss;

  _SimulationOutput? _output;

  @override
  void initState() {
    super.initState();
    _selectedSubjectIndex = widget.subjects.isNotEmpty ? 0 : -1;
    _compute();
  }

  @override
  void didUpdateWidget(AttendanceSimulatorCard old) {
    super.didUpdateWidget(old);
    if (widget.subjects.isEmpty) {
      _selectedSubjectIndex = -1;
    } else if (_selectedSubjectIndex >= widget.subjects.length) {
      _selectedSubjectIndex = widget.subjects.length - 1;
    }
    _compute();
  }

  void _compute() {
    if (_selectedSubjectIndex < 0 ||
        _selectedSubjectIndex >= widget.subjects.length) {
      setState(() => _output = null);
      return;
    }

    final subject = widget.subjects[_selectedSubjectIndex];
    final additionalPresent = _action == _ActionType.attend ? _hours : 0;
    final additionalTotal = _hours;

    final subjectPct =
        PercentageComputer.compute(subject.presentHours, subject.totalHours);
    final subjectPredicted =
        PercentageComputer.compute(
            subject.presentHours + additionalPresent,
            subject.totalHours + additionalTotal);
    final overallPct =
        PercentageComputer.compute(widget.totalPresent, widget.totalHours);
    final overallPredicted =
        PercentageComputer.compute(
            widget.totalPresent + additionalPresent,
            widget.totalHours + additionalTotal);

    final predictedBunks =
        SafeBunksComputer.compute(
            widget.totalPresent + additionalPresent,
            widget.totalHours + additionalTotal);
    final (danger, safe, _) = ThresholdComputer.compute(widget.target);

    setState(() {
      _output = _SimulationOutput(
        subjectCurrentPct: subjectPct,
        subjectPredictedPct: subjectPredicted,
        overallCurrentPct: overallPct,
        overallPredictedPct: overallPredicted,
        predictedSafeBunks: predictedBunks,
        isDanger: overallPredicted < danger,
        isWarning: overallPredicted >= danger && overallPredicted < safe,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Attendance Simulator',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Preview attendance impact for any subject',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (widget.subjects.isEmpty)
              _buildEmptyState(cs)
            else ...[
              _buildSubjectDropdown(cs),
              const SizedBox(height: 16),
              _buildActionToggle(cs),
              const SizedBox(height: 16),
              _buildHoursStepper(cs),
              const SizedBox(height: 16),
              if (_output != null) _buildResultSection(cs),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'No subject data available for simulation',
        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
      ),
    );
  }

  Widget _buildSubjectDropdown(ColorScheme cs) {
    return DropdownButtonFormField<int>(
      initialValue: _selectedSubjectIndex >= 0 &&
              _selectedSubjectIndex < widget.subjects.length
          ? _selectedSubjectIndex
          : 0,
      menuMaxHeight: MediaQuery.of(context).size.height * 0.35,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Subject',
        labelStyle: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: cs.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: cs.primary),
        ),
        isDense: true,
      ),
      style: TextStyle(fontSize: 13, color: cs.onSurface),
      dropdownColor: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(10),
      items: List.generate(widget.subjects.length, (i) {
        final s = widget.subjects[i];
        return DropdownMenuItem(
          value: i,
          child: Text(
            s.displayName,
            style: TextStyle(color: cs.onSurface),
            overflow: TextOverflow.ellipsis,
          ),
        );
      }),
      onChanged: (v) {
        if (v != null) {
          setState(() => _selectedSubjectIndex = v);
          _compute();
        }
      },
    );
  }

  Widget _buildActionToggle(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Action',
            style:
                TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        SegmentedButton<_ActionType>(
          segments: const [
            ButtonSegment(
              value: _ActionType.attend,
              label: Text('Attend Classes',
                  style: TextStyle(fontSize: 12)),
            ),
            ButtonSegment(
              value: _ActionType.miss,
              label: Text('Miss Classes',
                  style: TextStyle(fontSize: 12)),
            ),
          ],
          selected: {_action},
          onSelectionChanged: (v) {
            setState(() => _action = v.first);
            _compute();
          },
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  Widget _buildHoursStepper(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Number of hours',
            style:
                TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.remove_circle_outline,
                    size: 22, color: cs.onSurfaceVariant),
                onPressed: _hours > 1
                    ? () {
                        setState(() => _hours--);
                        _compute();
                      }
                    : null,
                visualDensity: VisualDensity.compact,
                tooltip: 'Decrease',
              ),
              SizedBox(
                width: 56,
                child: Text(
                  '$_hours hrs',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.add_circle_outline,
                    size: 22, color: cs.onSurfaceVariant),
                onPressed: _hours < 24
                    ? () {
                        setState(() => _hours++);
                        _compute();
                      }
                    : null,
                visualDensity: VisualDensity.compact,
                tooltip: 'Increase',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultSection(ColorScheme cs) {
    final o = _output!;
    final statusColor = o.isSafe
        ? Colors.green
        : o.isWarning
            ? Colors.orange
            : Colors.red;
    final statusLabel = o.isSafe
        ? 'SAFE'
        : o.isWarning
            ? 'WARNING'
            : 'CRITICAL';

    final overallDiff = PercentageComputer.diff(
        o.overallCurrentPct, o.overallPredictedPct);
    final subjectDiff = PercentageComputer.diff(
        o.subjectCurrentPct, o.subjectPredictedPct);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Prediction Results',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildResultStat('Current', '${o.overallCurrentPct.toStringAsFixed(1)}%', cs),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward, size: 14, color: cs.onSurfaceVariant),
              ),
              _buildResultStat('Predicted', '${o.overallPredictedPct.toStringAsFixed(1)}%', cs,
                  valueColor: overallDiff < 0 ? Colors.red : Colors.green),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildResultStat('Subject (${_action == _ActionType.attend ? "now" : "then"})',
                  '${_action == _ActionType.attend ? o.subjectCurrentPct.toStringAsFixed(1) : o.subjectPredictedPct.toStringAsFixed(1)}%',
                  cs),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward, size: 14, color: cs.onSurfaceVariant),
              ),
              _buildResultStat('Subject (${_action == _ActionType.attend ? "then" : "now"})',
                  '${_action == _ActionType.attend ? o.subjectPredictedPct.toStringAsFixed(1) : o.subjectCurrentPct.toStringAsFixed(1)}%',
                  cs,
                  valueColor: _action == _ActionType.attend
                      ? (subjectDiff >= 0 ? Colors.green : Colors.red)
                      : (subjectDiff <= 0 ? Colors.red : Colors.green)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildResultStat('Change',
                  '${overallDiff >= 0 ? '+' : ''}${overallDiff.toStringAsFixed(1)}%',
                  cs,
                  valueColor: overallDiff < 0 ? Colors.red : Colors.green),
              const SizedBox(width: 20),
              _buildResultStat('Safe leaves left', '${o.predictedSafeBunks}', cs),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultStat(
      String label, String value, ColorScheme cs,
      {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: valueColor ?? cs.onSurface,
          ),
        ),
      ],
    );
  }
}

class _SimulationOutput {
  final double subjectCurrentPct;
  final double subjectPredictedPct;
  final double overallCurrentPct;
  final double overallPredictedPct;
  final int predictedSafeBunks;
  final bool isDanger;
  final bool isWarning;

  const _SimulationOutput({
    required this.subjectCurrentPct,
    required this.subjectPredictedPct,
    required this.overallCurrentPct,
    required this.overallPredictedPct,
    required this.predictedSafeBunks,
    required this.isDanger,
    required this.isWarning,
  });

  bool get isSafe => !isDanger && !isWarning;
}
