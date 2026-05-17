import 'package:flutter/material.dart';

import 'attendance_simulation_helper.dart';

class _QAScenario {
  final String question;
  final String subtitle;
  final int hoursMissed;
  final int hoursAttended;

  const _QAScenario({
    required this.question,
    required this.subtitle,
    required this.hoursMissed,
    required this.hoursAttended,
  });
}

const _qaScenarios = [
  _QAScenario(
    question: 'What if I take leave for the full day tomorrow?',
    subtitle: '6 hours missed, 0 attended',
    hoursMissed: 6,
    hoursAttended: 0,
  ),
  _QAScenario(
    question: 'What if I miss only the last hour tomorrow?',
    subtitle: '1 hour missed, 5 attended',
    hoursMissed: 1,
    hoursAttended: 5,
  ),
  _QAScenario(
    question: 'What if I miss the first hour tomorrow?',
    subtitle: '1 hour missed, 5 attended',
    hoursMissed: 1,
    hoursAttended: 5,
  ),
  _QAScenario(
    question: 'What if I miss first and last hour tomorrow?',
    subtitle: '2 hours missed, 4 attended',
    hoursMissed: 2,
    hoursAttended: 4,
  ),
];

class AttendanceQACard extends StatefulWidget {
  final int totalPresent;
  final int totalHours;
  final double target;

  const AttendanceQACard({
    super.key,
    required this.totalPresent,
    required this.totalHours,
    required this.target,
  });

  @override
  State<AttendanceQACard> createState() => _AttendanceQACardState();
}

class _AttendanceQACardState extends State<AttendanceQACard> {
  int _expandedIndex = -1;

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
              'Attendance Q&A',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap a question to preview the impact on your attendance',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            ...List.generate(_qaScenarios.length, (i) {
              final scenario = _qaScenarios[i];
              final isExpanded = _expandedIndex == i;
              return _buildScenarioTile(
                context, scenario, isExpanded, i);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildScenarioTile(
    BuildContext context,
    _QAScenario scenario,
    bool isExpanded,
    int index,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final result = AttendanceSimulationHelper.simulate(
      currentPresent: widget.totalPresent,
      currentTotal: widget.totalHours,
      additionalPresent: scenario.hoursAttended,
      additionalTotal: scenario.hoursMissed + scenario.hoursAttended,
      target: widget.target,
    );

    return Column(
      children: [
        if (index > 0) Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() {
              _expandedIndex = isExpanded ? -1 : index;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scenario.question,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        scenario.subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (isExpanded) _buildResultRow(context, result),
      ],
    );
  }

  Widget _buildResultRow(BuildContext context, SimulationResult result) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final statusColor = result.isSafe
        ? Colors.green
        : result.isWarning
            ? Colors.orange
            : Colors.red;
    final statusLabel = result.isSafe
        ? 'SAFE'
        : result.isWarning
            ? 'WARNING'
            : 'DANGER';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildMiniStat('Predicted', '${result.predictedPercentage.toStringAsFixed(1)}%'),
                const SizedBox(width: 12),
                _buildMiniStat('Change', '${result.difference >= 0 ? '+' : ''}${result.difference.toStringAsFixed(1)}%',
                    valueColor: result.difference < 0 ? Colors.red : Colors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Status', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  'Safe leaves remaining: ${result.predictedSafeBunks}',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
                const SizedBox(width: 8),
                if (result.predictedSafeBunks < result.currentSafeBunks)
                  Text(
                    '(-${result.currentSafeBunks - result.predictedSafeBunks})',
                    style: const TextStyle(fontSize: 11, color: Colors.red),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
