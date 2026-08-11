class TimetableBatchInfo {
  final String id;
  final String name;

  const TimetableBatchInfo({required this.id, required this.name});

  factory TimetableBatchInfo.fromJson(Map<String, dynamic> json) => TimetableBatchInfo(
    id: _s(json['id']) ?? '',
    name: _s(json['name']) ?? '',
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  static String? _s(dynamic v) => v is String ? v : (v?.toString());
}

class TimetableEntry {
  final String id;
  final String staffId;
  final String day;
  final String hour;
  final String fromTime;
  final String toTime;
  final String date;
  final String subjectCode;
  final String subjectName;
  final List<TimetableBatchInfo> batches;
  final bool isOpenToAll;
  final String? attendanceMarked;

  const TimetableEntry({
    required this.id,
    required this.staffId,
    required this.day,
    required this.hour,
    required this.fromTime,
    required this.toTime,
    required this.date,
    required this.subjectCode,
    required this.subjectName,
    required this.batches,
    this.isOpenToAll = false,
    this.attendanceMarked,
  });

  factory TimetableEntry.fromJson(Map<String, dynamic> json) {
    final subjects = _safeList(json['subjects']);
    final firstSubject = subjects.isNotEmpty ? subjects[0] as Map<String, dynamic> : null;
    return TimetableEntry(
      id: _s(json['id']) ?? '',
      staffId: _s(json['staffId']) ?? '',
      day: _s(json['day']) ?? '',
      hour: _s(json['hour']) ?? '',
      fromTime: _s(json['fromTime']) ?? '',
      toTime: _s(json['toTime']) ?? '',
      date: _s(json['date']) ?? '',
      subjectCode: _s(firstSubject?['code']) ?? '',
      subjectName: _s(firstSubject?['name']) ?? '',
      batches: _safeList(json['batches']).map((e) {
        final m = e as Map<String, dynamic>;
        return TimetableBatchInfo(id: _s(m['id']) ?? '', name: _s(m['name']) ?? '');
      }).toList(),
      isOpenToAll: _s(json['isOpenToAll']) == '1',
      attendanceMarked: _s(json['attendanceMarked']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'staffId': staffId,
    'day': day,
    'hour': hour,
    'fromTime': fromTime,
    'toTime': toTime,
    'date': date,
    'subjectCode': subjectCode,
    'subjectName': subjectName,
    'batches': batches.map((b) => b.toJson()).toList(),
    'isOpenToAll': isOpenToAll,
    if (attendanceMarked != null) 'attendanceMarked': attendanceMarked,
  };

  static String? _s(dynamic v) => v is String ? v : (v?.toString());
  static List _safeList(dynamic v) => (v is List) ? v : [];
}

class TimetableHour {
  final String hour;
  final String hourName;
  final List<TimetableEntry> timeTables;

  const TimetableHour({
    required this.hour,
    required this.hourName,
    required this.timeTables,
  });

  factory TimetableHour.fromJson(Map<String, dynamic> json) {
    final rawTables = _safeList(json['timeTables']);
    return TimetableHour(
      hour: _s(json['hour']) ?? '',
      hourName: _s(json['hourName']) ?? '',
      timeTables: rawTables
          .map((e) => TimetableEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'hour': hour,
    'hourName': hourName,
    'timeTables': timeTables.map((t) => t.toJson()).toList(),
  };

  static String? _s(dynamic v) => v is String ? v : (v?.toString());
  static List _safeList(dynamic v) => (v is List) ? v : [];
}

class TimetableDay {
  final String date;
  final String day;
  final String dayName;
  final List<TimetableHour> hours;

  const TimetableDay({
    required this.date,
    required this.day,
    required this.dayName,
    required this.hours,
  });

  factory TimetableDay.fromJson(Map<String, dynamic> json) => TimetableDay(
    date: _s(json['date']) ?? '',
    day: _s(json['day']) ?? '',
    dayName: _s(json['dayName']) ?? '',
    hours: _safeList(json['hours'])
        .map((e) => TimetableHour.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'date': date,
    'day': day,
    'dayName': dayName,
    'hours': hours.map((h) => h.toJson()).toList(),
  };

  List<TimetableEntry> get allEntries {
    final entries = <TimetableEntry>[];
    for (final hour in hours) {
      entries.addAll(hour.timeTables);
    }
    return entries;
  }

  static String? _s(dynamic v) => v is String ? v : (v?.toString());
  static List _safeList(dynamic v) => (v is List) ? v : [];
}

class DayHourModel {
  final String id;
  final String name;
  final String order;

  const DayHourModel({required this.id, required this.name, required this.order});

  factory DayHourModel.fromJson(Map<String, dynamic> json) => DayHourModel(
    id: _s(json['id']) ?? '',
    name: _s(json['name']) ?? '',
    order: _s(json['order']) ?? '',
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'order': order};

  static String? _s(dynamic v) => v is String ? v : (v?.toString());
}

class DayOrderModel {
  final String id;
  final String name;
  final String order;

  const DayOrderModel({required this.id, required this.name, required this.order});

  factory DayOrderModel.fromJson(Map<String, dynamic> json) => DayOrderModel(
    id: _s(json['id']) ?? '',
    name: _s(json['name']) ?? '',
    order: _s(json['order']) ?? '',
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'order': order};

  static String? _s(dynamic v) => v is String ? v : (v?.toString());
}
