import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../../models/api/subject_wise_attendance_model.dart';

class SubjectWiseAttendanceService {
  final Dio _dio;

  SubjectWiseAttendanceService() : _dio = DioClient.instance.dio;

  Future<List<SubjectWiseAttendanceModel>> fetchSubjectWiseAttendance({
    required String studentId,
    String termId = '4',
    String startDate = '2026-02-03',
    String endDate = '2026-05-30',
  }) async {
    final filter = {
      'firstTime': false,
      'termId': termId,
      'startDate': startDate,
      'endDate': endDate,
      'studentId': studentId,
      'academicStatus': 'ACTIVE',
      'mapping': 'STUDENT-SUBJECT-WISE',
    };

    final filterJson = jsonEncode(filter);

    print('[SUBJECT_API] === SUBJECT-WISE ATTENDANCE ===');
    print('[SUBJECT_API] Endpoint: /attendance/subject-wise-attendance-report');
    print('[SUBJECT_API] Filter: $filterJson');

    try {
      // Browser-matching headers for this isolated endpoint
      final requestOptions = Options(
        headers: {
          'X-Menu-Code': 'STUDENT_SUBJECT_WISE_ATTENDANCE_METHOD',
          'Referer': 'https://sfcv4.linways.com/academics/',
          'Accept': 'application/json, text/plain, */*',
        },
      );

      final response = await _dio.get(
        '/attendance/subject-wise-attendance-report',
        queryParameters: {'filter': filterJson},
        options: requestOptions,
      );

      print('[SUBJECT_API] Status: ${response.statusCode}');
      print('[SUBJECT_API] Request headers: ${requestOptions.headers}');
      print('[SUBJECT_API] Response headers: ${response.headers.map}');

      final rawData = response.data;
      print('[SUBJECT_API] Response type: ${rawData.runtimeType}');

      if (rawData is Map<String, dynamic>) {
        print('[SUBJECT_API] Top-level keys: ${rawData.keys.toList()}');

        if (rawData['data'] is Map<String, dynamic>) {
          final inner = rawData['data'] as Map<String, dynamic>;
          print('[SUBJECT_API] data keys: ${inner.keys.toList()}');

          if (inner['termDetails'] is List) {
            final termList = inner['termDetails'] as List;
            print('[SUBJECT_API] termDetails length: ${termList.length}');

            if (termList.isEmpty) {
              if (inner['pdfData'] is String) {
                final pdfBase64 = inner['pdfData'] as String;
                print('[SUBJECT_API] termDetails empty, pdfData length: ${pdfBase64.length} chars');
                print('[PDF_FORENSICS] ============ FORENSIC INSPECTION ============');
                print('[PDF_FORENSICS] pdfData length: ${pdfBase64.length} chars');

                try {
                  final bytes = base64Decode(pdfBase64);
                  print('[PDF_FORENSICS] Decoded: ${bytes.length} bytes');

                  final header = String.fromCharCodes(bytes.take(8));
                  print('[PDF_FORENSICS] Header: "$header"');

                  if (header.startsWith('%PDF')) {
                    print('[PDF_FORENSICS] Type: PDF');
                    final preview = String.fromCharCodes(bytes, 0, bytes.length > 4000 ? 4000 : bytes.length);
                    print('[PDF_FORENSICS] Has Tj operators: ${preview.contains('Tj')}');
                    print('[PDF_FORENSICS] Has TJ arrays: ${preview.contains('TJ')}');
                    print('[PDF_FORENSICS] Has BT/ET blocks: ${preview.contains('BT')}');
                    print('[PDF_FORENSICS] Has stream objects: ${preview.contains('stream')}');

                    final lower = preview.toLowerCase();
                    for (final kw in ['course', 'subject', 'attendance', 'percentage', 'total', 'present', 'dutyleave', 'name', 'staff', 'table']) {
                      if (lower.contains(kw)) {
                        print('[PDF_FORENSICS] Keyword "$kw": FOUND');
                      }
                    }

                    // Count PDF pages
                    final pageCount = 'Page'.allMatches(preview).length;
                    print('[PDF_FORENSICS] Approximate pages referenced: $pageCount');

                    // Save temp file for manual inspection
                    final dir = Directory.systemTemp;
                    final ts = DateTime.now().millisecondsSinceEpoch;
                    final f = File('${dir.path}/attendance_report_$ts.pdf');
                    await f.writeAsBytes(bytes);
                    print('[PDF_FORENSICS] Saved to: ${f.path}');

                  } else if (header.trimLeft().startsWith('<') || header.trimLeft().startsWith('{')) {
                    print('[PDF_FORENSICS] Type: Structured text (HTML/JSON)');
                    print('[PDF_FORENSICS] Preview: ${String.fromCharCodes(bytes.take(300))}');

                  } else if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
                    print('[PDF_FORENSICS] Type: GZIP compressed');

                  } else if (bytes.length >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
                    print('[PDF_FORENSICS] Type: PNG image');

                  } else {
                    print('[PDF_FORENSICS] Type: Unknown binary');
                    print('[PDF_FORENSICS] Hex: ${bytes.take(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
                    print('[PDF_FORENSICS] ASCII: ${String.fromCharCodes(bytes.take(64))}');
                  }
                } catch (e) {
                  print('[PDF_FORENSICS] Decode error: $e');
                }

                print('[PDF_FORENSICS] ============ END FORENSIC INSPECTION ============');
              }
              print('[SUBJECT_API] No subject-wise data available');
              return [];
            }

            final models = termList.map((e) {
              if (e is! Map) return null;
              return SubjectWiseAttendanceModel.fromJson(Map<String, dynamic>.from(e));
            }).whereType<SubjectWiseAttendanceModel>().toList();

            print('[SUBJECT_API] Parsed ${models.length} subjects');
            for (final m in models) {
              print('[SUBJECT_API] ---');
              print('[SUBJECT_API] Subject: ${m.subjectName}');
              print('[SUBJECT_API] TH: ${m.totalHours}');
              print('[SUBJECT_API] AH: ${m.attendedHours}');
              print('[SUBJECT_API] DL: ${m.dutyLeave}');
              print('[SUBJECT_API] Effective: ${m.effectivePresent}');
              print('[SUBJECT_API] Final %: ${m.finalPercentage}');
              print('[SUBJECT_API] % w/o DL: ${m.percentageWithoutDL}');
            }
            print('[SUBJECT_API] === COMPLETE ===');
            return models;
          }

          print('[SUBJECT_API] termDetails is not a List. Type: ${inner['termDetails']?.runtimeType}');
          return [];
        }

        print('[SUBJECT_API] response.data is not a Map');
        return [];
      }

      print('[SUBJECT_API] Unexpected response type');
      return [];
    } on DioException catch (e) {
      print('[SUBJECT_API] DioException: ${e.message}');
      print('[SUBJECT_API] Status: ${e.response?.statusCode}');
      if (e.response?.data != null) {
        print('[SUBJECT_API] Body: ${jsonEncode(e.response?.data).substring(0, 500)}');
      }
      return [];
    }
  }
}
