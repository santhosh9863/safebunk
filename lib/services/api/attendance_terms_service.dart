import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../../core/cache/memory_cache.dart';
import '../../core/cache/persistent_cache.dart';
import '../../core/network/api_constants.dart';
import '../../core/network/dio_client.dart';
import '../../models/api/academic_term_model.dart';

typedef TermChangeListener = void Function(String previousTermId, String newTermId);

/// Raw data collected from Linways for a single resolution pass. Every
/// candidate signal is captured and logged so the active term/period can
/// be traced end-to-end.
class _TermSignals {
  final List<Map<String, dynamic>> rawTermEntries;
  final List<AcademicTermModel> termList;
  final String studiedTermsCurrentTermId;
  final String profileAcademicTermId;
  final String profileAcademicTermName;
  final String profileCurrentSem;
  final String activeDatesFromDate;
  final String activeDatesToDate;

  const _TermSignals({
    required this.rawTermEntries,
    required this.termList,
    required this.studiedTermsCurrentTermId,
    required this.profileAcademicTermId,
    required this.profileAcademicTermName,
    required this.profileCurrentSem,
    required this.activeDatesFromDate,
    required this.activeDatesToDate,
  });
}

class _ResolvedPeriods {
  final CurrentTerm? term;
  final CurrentTerm? dateRange;

  const _ResolvedPeriods(this.term, this.dateRange);
}

/// Resolves the student's CURRENT academic term and the CURRENT attendance
/// date range by cross-checking every signal Linways exposes instead of
/// trusting a single (possibly stale) field:
///
///   Term selection:
///     1. Term whose start/end date range contains today
///     2. `academicTermId` from get-student-basic-details (enrolled term)
///     3. `currentTermId` from fetch-student-studied-terms (portal default)
///     4. Newest term by start date
///
///   Date range (used by daily attendance — the official portal derives this
///   from `daily-attendance-date-fetch`, NOT from the studied-terms entry):
///     1. `data.dates[0]` from daily-attendance-date-fetch (authoritative)
///     2. The resolved term's own start/end dates
///
/// Results are cached in memory (with in-flight deduplication) so N screens
/// sharing the same provider instance trigger exactly ONE resolution pass.
///
/// Detects academic-term changes and invalidates all persisted attendance
/// caches so stale semester data can never be served again.
class AttendanceTermsService {
  final Dio _dio;
  final List<TermChangeListener> _termChangeListeners = [];
  final MemoryCache<_ResolvedPeriods> _resolutionCache =
      MemoryCache<_ResolvedPeriods>(ttl: const Duration(minutes: 10));
  final Map<String, Future<_ResolvedPeriods?>> _inFlight = {};

  AttendanceTermsService() : _dio = DioClient.instance.dio;

  void addTermChangeListener(TermChangeListener listener) {
    if (!_termChangeListeners.contains(listener)) {
      _termChangeListeners.add(listener);
    }
  }

  /// The student's active term (termId + dates if the term has them).
  Future<CurrentTerm?> fetchCurrentTerm(String studentId) async {
    return (await _getResolved(studentId))?.term;
  }

  /// The active attendance date range (from daily-attendance-date-fetch,
  /// falling back to the resolved term's dates).
  Future<CurrentTerm?> fetchCurrentDateRange(String studentId) async {
    return (await _getResolved(studentId))?.dateRange;
  }

  Future<_ResolvedPeriods?> _getResolved(String studentId) async {
    final cached = _resolutionCache.get(studentId);
    if (cached != null) return cached;

    final inFlight = _inFlight[studentId];
    if (inFlight != null) return inFlight;

    final future = _resolveAll(studentId);
    _inFlight[studentId] = future;
    try {
      final resolved = await future;
      if (resolved != null) {
        _resolutionCache.set(studentId, resolved);
      }
      return resolved;
    } finally {
      _inFlight.remove(studentId);
    }
  }

  Future<_ResolvedPeriods?> _resolveAll(String studentId) async {
    final signals = await _fetchSignals(studentId);

    _logSignals(studentId, signals);

    final term = _resolveCurrentTerm(signals);
    if (term != null) {
      debugPrint('[Term] RESOLVED termId=${term.termId} '
          '(name="${term.termName}", dates=${term.startDate} → ${term.endDate}) '
          'reason="${term.reason}"');
    } else {
      debugPrint('[Term] NO term could be resolved for student $studentId');
    }

    final dateRange = _resolveDateRange(signals, term);
    if (dateRange != null) {
      debugPrint('[Term] RESOLVED date range ${dateRange.startDate} → ${dateRange.endDate} '
          'reason="${dateRange.reason}"');
    } else {
      debugPrint('[Term] NO date range could be resolved for student $studentId');
    }

    await _handleTermChange(studentId, term?.termId ?? '');
    return _ResolvedPeriods(term, dateRange);
  }

  // ── Signal collection ────────────────────────────────────────────────

  Future<_TermSignals> _fetchSignals(String studentId) async {
    var rawTermEntries = <Map<String, dynamic>>[];
    var termList = <AcademicTermModel>[];
    var studiedTermsCurrentTermId = '';
    var profileAcademicTermId = '';
    var profileAcademicTermName = '';
    var profileCurrentSem = '';
    var activeDatesFromDate = '';
    var activeDatesToDate = '';

    try {
      final response = await _dio.get(
        '${ApiConstants.studiedTerms}/$studentId',
        options: Options(
          headers: {
            'Referer': 'https://sfcv4.linways.com/academics/',
            'Accept': 'application/json, text/plain, */*',
          },
        ),
      );
      final raw = response.data;
      debugPrint('[Term] RAW fetch-student-studied-terms response: ${_encodeRaw(raw)}');
      if (raw is Map<String, dynamic>) {
        final data = raw['data'];
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          studiedTermsCurrentTermId =
              (map['currentTermId']?.toString() ?? '').trim();
          if (map['termList'] is List) {
            rawTermEntries = (map['termList'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
            termList = rawTermEntries
                .map((e) => AcademicTermModel.fromJson(e))
                .where((t) => t.termId.isNotEmpty)
                .toList();
          }
        }
      }
    } on DioException catch (e) {
      debugPrint('[Term] fetch-student-studied-terms failed: ${e.response?.statusCode}');
    } catch (e) {
      debugPrint('[Term] fetch-student-studied-terms parse failed: $e');
    }

    try {
      final response = await _dio.get(
        ApiConstants.studentBasicDetails,
        queryParameters: {'studentId': studentId},
        options: Options(
          headers: {
            'Referer': 'https://sfcv4.linways.com/academics/',
            'Accept': 'application/json, text/plain, */*',
          },
        ),
      );
      final raw = response.data;
      debugPrint('[Term] RAW get-student-basic-details response: ${_encodeRaw(raw)}');
      if (raw is Map<String, dynamic>) {
        final data = raw['data'];
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          final props = map['properties'] is Map
              ? Map<String, dynamic>.from(map['properties'] as Map)
              : <String, dynamic>{};
          profileAcademicTermId =
              (map['academicTermId']?.toString() ??
                      props['academicTermId']?.toString() ??
                      '')
                  .trim();
          profileAcademicTermName =
              (map['academicTermName']?.toString() ??
                      props['academicTermName']?.toString() ??
                      '')
                  .trim();
          profileCurrentSem =
              (map['currentSem']?.toString() ??
                      map['currentSemester']?.toString() ??
                      '')
                  .trim();
        }
      }
    } on DioException catch (e) {
      debugPrint('[Term] get-student-basic-details failed: ${e.response?.statusCode}');
    } catch (e) {
      debugPrint('[Term] get-student-basic-details parse failed: $e');
    }

    // The official portal derives the daily-attendance date range from this
    // endpoint — the studied-terms entry often has NO dates (e.g. S5).
    try {
      final paramsJson = jsonEncode(studentId);
      final response = await _dio.get(
        ApiConstants.dailyAttendanceDateFetch,
        queryParameters: {'params': paramsJson},
        options: Options(
          headers: {
            'Referer': 'https://sfcv4.linways.com/academics/',
            'Accept': 'application/json, text/plain, */*',
          },
        ),
      );
      final raw = response.data;
      debugPrint('[Term] RAW daily-attendance-date-fetch response: ${_encodeRaw(raw)}');
      if (raw is Map<String, dynamic>) {
        final data = raw['data'];
        final dates = data is Map
            ? (Map<String, dynamic>.from(data))['dates']
            : (data is List ? data : null);
        if (dates is List && dates.isNotEmpty && dates.first is Map) {
          final first = Map<String, dynamic>.from(dates.first as Map);
          activeDatesFromDate =
              (first['fromDate']?.toString() ??
                      first['from_date']?.toString() ??
                      '')
                  .trim();
          activeDatesToDate =
              (first['toDate']?.toString() ??
                      first['to_date']?.toString() ??
                      '')
                  .trim();
        }
      }
    } on DioException catch (e) {
      debugPrint('[Term] daily-attendance-date-fetch failed: ${e.response?.statusCode}');
    } catch (e) {
      debugPrint('[Term] daily-attendance-date-fetch parse failed: $e');
    }

    return _TermSignals(
      rawTermEntries: rawTermEntries,
      termList: termList,
      studiedTermsCurrentTermId: studiedTermsCurrentTermId,
      profileAcademicTermId: profileAcademicTermId,
      profileAcademicTermName: profileAcademicTermName,
      profileCurrentSem: profileCurrentSem,
      activeDatesFromDate: activeDatesFromDate,
      activeDatesToDate: activeDatesToDate,
    );
  }

  static String _encodeRaw(dynamic raw) {
    try {
      return jsonEncode(raw);
    } catch (_) {
      return raw?.toString() ?? 'null';
    }
  }

  // ── Resolution ───────────────────────────────────────────────────────

  CurrentTerm? _resolveCurrentTerm(_TermSignals s) {
    final termList = s.termList;
    final today = _today();

    // 1. Term whose date range contains today — the strongest "this is
    //    what the student is studying right now" signal.
    final containingToday = termList
        .where((t) => _containsDate(t, today))
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    if (containingToday.isNotEmpty) {
      final pick = containingToday.last;
      return _toCurrentTerm(pick, reason: 'term containing today ($today)');
    }

    // 2. Student's enrolled term from the profile (authoritative when
    //    present in the term list).
    if (s.profileAcademicTermId.isNotEmpty) {
      final match =
          termList.where((t) => t.termId == s.profileAcademicTermId).firstOrNull;
      if (match != null) {
        return _toCurrentTerm(match,
            reason: 'profile academicTermId=${s.profileAcademicTermId}');
      }
      debugPrint('[Term] profile academicTermId=${s.profileAcademicTermId} not in termList');
    }

    // 3. Portal's attendance default term.
    if (s.studiedTermsCurrentTermId.isNotEmpty) {
      final match = termList
          .where((t) => t.termId == s.studiedTermsCurrentTermId)
          .firstOrNull;
      if (match != null) {
        return _toCurrentTerm(match,
            reason: 'studied-terms currentTermId=${s.studiedTermsCurrentTermId}');
      }
      if (termList.isEmpty) {
        debugPrint(
            '[Term] termList empty — falling back to raw currentTermId=${s.studiedTermsCurrentTermId}');
        return CurrentTerm(
          termId: s.studiedTermsCurrentTermId,
          reason: 'studied-terms currentTermId (no termList)',
        );
      }
    }

    // 4. Newest term by start date.
    if (termList.isNotEmpty) {
      final sorted = [...termList]
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
      final pick = sorted.last;
      return _toCurrentTerm(pick, reason: 'newest term by startDate');
    }

    // 5. Raw profile term id as a last resort (no term list at all).
    if (s.profileAcademicTermId.isNotEmpty) {
      return CurrentTerm(
        termId: s.profileAcademicTermId,
        termName: s.profileAcademicTermName,
        reason: 'profile academicTermId (no termList)',
      );
    }

    return null;
  }

  CurrentTerm? _resolveDateRange(_TermSignals s, CurrentTerm? term) {
    // 1. The portal's own active-date-range endpoint (authoritative).
    if (s.activeDatesFromDate.isNotEmpty && s.activeDatesToDate.isNotEmpty) {
      return CurrentTerm(
        termId: term?.termId ?? '',
        startDate: s.activeDatesFromDate,
        endDate: s.activeDatesToDate,
        reason: 'daily-attendance-date-fetch',
      );
    }

    // 2. The resolved term's own dates.
    if (term != null &&
        term.startDate.isNotEmpty &&
        term.endDate.isNotEmpty) {
      return CurrentTerm(
        termId: term.termId,
        startDate: term.startDate,
        endDate: term.endDate,
        reason: 'current term dates (${term.reason})',
      );
    }

    return null;
  }

  CurrentTerm _toCurrentTerm(AcademicTermModel term, {required String reason}) {
    return CurrentTerm(
      termId: term.termId,
      termName: term.termName,
      startDate: term.startDate,
      endDate: term.endDate,
      reason: reason,
    );
  }

  // ── Term-change detection & cache invalidation ───────────────────────

  Future<void> _handleTermChange(String studentId, String termId) async {
    if (termId.isEmpty) return;
    final previous = PersistentCache.getStoredTermId(studentId);
    if (previous != null && previous.isNotEmpty && previous != termId) {
      debugPrint('[Term] ACADEMIC TERM CHANGED for student $studentId: '
          '$previous → $termId — clearing persisted attendance caches');
      await PersistentCache.deleteStudentAttendance(studentId);
      for (final listener in List.of(_termChangeListeners)) {
        try {
          listener(previous, termId);
        } catch (e) {
          debugPrint('[Term] term-change listener error: $e');
        }
      }
    }
    if (previous != termId) {
      await PersistentCache.setStoredTermId(studentId, termId);
    }
  }

  // ── Logging ──────────────────────────────────────────────────────────

  void _logSignals(String studentId, _TermSignals s) {
    debugPrint('[Term] ── TERM SIGNALS for student $studentId ──');
    debugPrint('[Term] fetch-student-studied-terms/{studentId}: '
        'currentTermId="${s.studiedTermsCurrentTermId}"');
    if (s.rawTermEntries.isEmpty) {
      debugPrint('[Term]   termList: EMPTY');
    } else {
      for (final entry in s.rawTermEntries) {
        debugPrint('[Term]   RAW term entry: ${jsonEncode(entry)}');
      }
    }
    debugPrint('[Term] get-student-basic-details?studentId=$studentId: '
        'academicTermId="${s.profileAcademicTermId}" '
        'academicTermName="${s.profileAcademicTermName}" '
        'currentSem="${s.profileCurrentSem}"');
    debugPrint('[Term] daily-attendance-date-fetch?params="$studentId": '
        'activeDates=${s.activeDatesFromDate} → ${s.activeDatesToDate}');
    debugPrint('[Term] ────────────────────────────────────────────');
  }

  // ── Date helpers ─────────────────────────────────────────────────────

  static String _today() {
    final now = DateTime.now();
    return '${now.year}-${_pad(now.month)}-${_pad(now.day)}';
  }

  static String _pad(int n) => n < 10 ? '0$n' : '$n';

  static bool _containsDate(AcademicTermModel term, String date) {
    final start = term.startDate;
    final end = term.endDate;
    if (start.isEmpty || end.isEmpty) return false;
    if (!_isIsoDate(start) || !_isIsoDate(end)) return false;
    return start.compareTo(date) <= 0 && end.compareTo(date) >= 0;
  }

  static bool _isIsoDate(String d) {
    final parts = d.split('-');
    if (parts.length != 3) return false;
    return parts[0].length == 4 && parts[1].length == 2 && parts[2].length == 2;
  }
}
