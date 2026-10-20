import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/features/reports/application/reports_providers.dart';
import 'package:safebunk_v2/features/reports/data/models/report_event.dart';
import 'package:safebunk_v2/features/reports/data/models/report_model.dart';
import 'package:safebunk_v2/features/reports/presentation/screens/report_detail_screen.dart';

void main() {
  testWidgets('student detail shows resolution notes and status history', (
    tester,
  ) async {
    final report = ReportModel(
      id: 'rep_1',
      code: 'PULSE-1042',
      title: 'Water leakage',
      description: 'Water near the electrical panel.',
      category: 'Plumbing',
      location: 'Block B',
      imageUrl: null,
      priority: 'HIGH',
      status: 'RESOLVED',
      assignedDepartment: 'Maintenance',
      resolutionNotes: 'Replaced the faulty valve.',
      events: [
        ReportEventModel(
          id: 'e1',
          type: 'SUBMITTED',
          actorRole: 'STUDENT',
          remark: null,
          createdAt: DateTime.utc(2026, 10, 20, 9),
        ),
        ReportEventModel(
          id: 'e2',
          type: 'ASSIGNED',
          actorRole: 'ADMIN',
          remark: 'Maintenance',
          createdAt: DateTime.utc(2026, 10, 20, 10),
        ),
        ReportEventModel(
          id: 'e3',
          type: 'RESOLVED',
          actorRole: 'STAFF',
          remark: 'Replaced the faulty valve.',
          createdAt: DateTime.utc(2026, 10, 20, 11),
        ),
      ],
      aiCategory: null,
      aiPriority: null,
      aiConfidence: null,
      createdAt: DateTime.utc(2026, 10, 20, 9),
      updatedAt: DateTime.utc(2026, 10, 20, 11),
      resolvedAt: DateTime.utc(2026, 10, 20, 11),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reportDetailProvider(
            report.id,
          ).overrideWith((ref) async => report),
        ],
        child: MaterialApp(
          home: ReportDetailScreen(reportId: report.id, initial: report),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('RESOLUTION'), 300);
    expect(find.text('Replaced the faulty valve.'), findsAtLeastNWidgets(1));

    await tester.scrollUntilVisible(find.text('ACTIVITY'), 300);
    expect(find.text('Assignment'), findsNothing);
    expect(find.text('Campus staff'), findsOneWidget);
    expect(find.text('Submitted'), findsOneWidget);
  });
}
