import 'package:flutter/material.dart';

import '../../../../core/errors/app_exceptions.dart';
import '../../data/models/ml_suggestion.dart';
import '../../domain/report_enums.dart';

/// User-triggered duplicate suggestion section shared by student and staff
/// report details and the pre-submission report form.
///
/// The widget is presentation-only: [load] performs the authenticated request
/// and no result can modify, merge, reject, or block a report.
class DuplicateSuggestionsCard extends StatefulWidget {
  final String description;
  final String checkLabel;
  final Future<DuplicateSuggestion> Function() load;
  final VoidCallback? onSessionExpired;

  const DuplicateSuggestionsCard({
    super.key,
    required this.description,
    required this.checkLabel,
    required this.load,
    this.onSessionExpired,
  });

  @override
  State<DuplicateSuggestionsCard> createState() =>
      _DuplicateSuggestionsCardState();
}

class _DuplicateSuggestionsCardState extends State<DuplicateSuggestionsCard> {
  bool _loading = false;
  DuplicateSuggestion? _result;
  String? _error;

  Future<void> _check() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await widget.load();
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } on SessionExpiredException catch (error) {
      widget.onSessionExpired?.call();
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not check for possible duplicates. Please try again.';
        _loading = false;
      });
    }
  }

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
            'POSSIBLE DUPLICATES',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.description,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _check,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search, size: 18),
              label: Text(_loading ? 'Checking…' : widget.checkLabel),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _MessageBox(
              icon: Icons.cloud_off_outlined,
              color: cs.error,
              background: cs.errorContainer.withValues(alpha: 0.45),
              title: 'Could not check for duplicates',
              message: _error!,
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: 12),
            _ResultBody(result: _result!),
          ],
        ],
      ),
    );
  }
}

class _ResultBody extends StatelessWidget {
  final DuplicateSuggestion result;

  const _ResultBody({required this.result});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!result.available) {
      return _MessageBox(
        icon: Icons.info_outline,
        color: cs.onSurfaceVariant,
        background: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        title: 'ML suggestions unavailable',
        message:
            '${duplicateSuggestionFailureMessage(result.reason)} '
            'Your report details and photos are unaffected.',
      );
    }

    if (result.candidates.isEmpty) {
      return _MessageBox(
        icon: Icons.check_circle_outline,
        color: const Color(0xFF2E7D32),
        background: const Color(0xFFEAF5EA),
        title: 'No possible duplicates found.',
        message: result.existingComplaintsEvaluated == null
            ? 'You can still review the details before submitting.'
            : 'Compared with ${result.existingComplaintsEvaluated} of your '
                  'earlier report(s). You can still review the details before '
                  'submitting.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4E5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: Color(0xFF8A5300),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Possible matches — not confirmed duplicates. '
                  'Nothing was merged or changed.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: Color(0xFF6B4100),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _MetaChip(
              icon: Icons.flag_outlined,
              label: result.decision?.label ?? 'Review manually',
            ),
            if (result.modelVersion != null)
              _MetaChip(
                icon: Icons.model_training_outlined,
                label: 'Model ${result.modelVersion}',
              ),
          ],
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < result.candidates.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _CandidateTile(
            candidate: result.candidates[i],
            duplicateThreshold: result.duplicateThreshold,
            uncertainThreshold: result.uncertainThreshold,
          ),
        ],
        const SizedBox(height: 10),
        Text(
          result.scoreNote.isEmpty
              ? 'Similarity scores are for ranking only, not probabilities.'
              : result.scoreNote,
          style: TextStyle(
            fontSize: 11.5,
            height: 1.35,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Suggestions only. No report was changed.',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _CandidateTile extends StatelessWidget {
  final DuplicateCandidate candidate;
  final double? duplicateThreshold;
  final double? uncertainThreshold;

  const _CandidateTile({
    required this.candidate,
    required this.duplicateThreshold,
    required this.uncertainThreshold,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final score = candidate.rankingScore;
    final isMatch = duplicateThreshold != null && score >= duplicateThreshold!;
    final isUncertain =
        !isMatch && uncertainThreshold != null && score >= uncertainThreshold!;
    final decisionLabel = isMatch
        ? 'Possible match'
        : isUncertain
        ? 'Uncertain'
        : 'Low similarity';
    final decisionColor = isMatch
        ? const Color(0xFF9A3412)
        : isUncertain
        ? const Color(0xFF8A5300)
        : cs.onSurfaceVariant;
    final status = ReportStatus.fromApi(candidate.status);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate.reportCode,
                      style: const TextStyle(
                        fontSize: 12,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      candidate.title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: decisionColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  decisionLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: decisionColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ScoreChip(label: 'Similarity', value: candidate.similarityScore),
              _ScoreChip(label: 'Ranking', value: candidate.rankingScore),
              Text(
                status.label,
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          if ((candidate.category ?? '').isNotEmpty ||
              (candidate.location ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              [
                if ((candidate.category ?? '').isNotEmpty) candidate.category!,
                if ((candidate.location ?? '').isNotEmpty) candidate.location!,
              ].join(' · '),
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
            ),
          ],
          if (candidate.reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final reason in candidate.reasons)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.onSurfaceVariant,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        reason,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 7),
          Text(
            'Report ID: ${candidate.reportId}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurfaceVariant.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  final String label;
  final double value;

  const _ScoreChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        '$label ${formatMlScore(value)}',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cs.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _MessageBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String message;

  const _MessageBox({
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: TextStyle(fontSize: 12, height: 1.35, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
