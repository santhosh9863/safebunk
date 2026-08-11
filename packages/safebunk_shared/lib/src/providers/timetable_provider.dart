import 'package:riverpod/riverpod.dart';
import '../models/timetable/timetable.dart';
import '../repositories/timetable_repository.dart';

final timetableRepositoryProvider = Provider<TimetableRepository>((ref) {
  throw UnimplementedError('timetableRepositoryProvider must be overridden');
});

final todayScheduleProvider = FutureProvider<List<TimetableEntry>>((ref) async {
  final repo = ref.watch(timetableRepositoryProvider);
  return repo.getTodaySchedule();
});

class WeeklyTimetableRequest {
  final String batchId;
  final String fromDate;
  final String toDate;

  const WeeklyTimetableRequest({
    required this.batchId,
    required this.fromDate,
    required this.toDate,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WeeklyTimetableRequest &&
          batchId == other.batchId &&
          fromDate == other.fromDate &&
          toDate == other.toDate;

  @override
  int get hashCode => Object.hash(batchId, fromDate, toDate);
}

final weeklyTimetableProvider = FutureProvider.family<List<TimetableDay>, WeeklyTimetableRequest>((ref, request) async {
  final repo = ref.watch(timetableRepositoryProvider);
  return repo.getWeeklyTimetable(
    batchId: request.batchId,
    fromDate: request.fromDate,
    toDate: request.toDate,
  );
});

final dayHoursProvider = FutureProvider<List<DayHourModel>>((ref) async {
  final repo = ref.watch(timetableRepositoryProvider);
  return repo.getDayHours();
});
