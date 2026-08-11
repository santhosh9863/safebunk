import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safebunk_shared/safebunk_shared.dart';

class TimetableScreen extends ConsumerStatefulWidget {
  const TimetableScreen({super.key});

  @override
  ConsumerState<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends ConsumerState<TimetableScreen> {
  DateTime _currentDate = DateTime.now();

  String get _dateStr => '${_currentDate.year}-${_currentDate.month.toString().padLeft(2, '0')}-${_currentDate.day.toString().padLeft(2, '0')}';

  void _previousDay() => setState(() => _currentDate = _currentDate.subtract(const Duration(days: 1)));
  void _nextDay() => setState(() => _currentDate = _currentDate.add(const Duration(days: 1)));
  void _goToToday() => setState(() => _currentDate = DateTime.now());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              IconButton(onPressed: _previousDay, icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: GestureDetector(
                  onTap: _goToToday,
                  child:                     Text(
                    DateHelper.formatDisplay(_dateStr),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
              IconButton(onPressed: _nextDay, icon: const Icon(Icons.chevron_right)),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _timetableContent()),
      ],
    );
  }

  Widget _timetableContent() {
    return FutureBuilder<List<TimetableDay>>(
      future: _fetchTimetable(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final days = snapshot.data ?? [];
        if (days.isEmpty) {
          return const Center(child: Text('No classes scheduled'));
        }

        final day = days.first;
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(timetableRepositoryProvider);
            setState(() {});
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: day.hours.map((hour) => _ClassPeriodCard(hour: hour)).toList(),
          ),
        );
      },
    );
  }

  Future<List<TimetableDay>> _fetchTimetable() async {
    final repo = ref.read(timetableRepositoryProvider);
    final profileRepo = ref.read(profileRepositoryProvider);
    final profile = await profileRepo.getProfile();
    final weekStart = DateHelper.weekStart(_dateStr);
    final weekEnd = DateHelper.weekEnd(_dateStr);
    return repo.getWeeklyTimetable(batchId: profile.batchId, fromDate: weekStart, toDate: weekEnd);
  }
}

class _ClassPeriodCard extends StatelessWidget {
  final TimetableHour hour;
  const _ClassPeriodCard({required this.hour});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (hour.timeTables.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Column(
                children: [
                  Text(hour.hour, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(hour.hourName, style: theme.textTheme.bodySmall, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: hour.timeTables.map((entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(entry.subjectName, style: theme.textTheme.bodyMedium),
                )).toList(),
              ),
            ),
            if (hour.timeTables.isNotEmpty)
              Text(
                '${hour.timeTables.first.fromTime}-${hour.timeTables.first.toTime}',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }
}
