import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/core/errors/app_exceptions.dart';
import 'package:safebunk_v2/features/reports/application/reports_providers.dart';
import 'package:safebunk_v2/features/reports/data/models/report_model.dart';
import 'package:safebunk_v2/features/reports/presentation/screens/reports_tab.dart';

void main() {
  testWidgets('Reports tab shows a configuration error and Retry is safe', (
    tester,
  ) async {
    const message =
        'PULSE backend is not configured. Run the app with '
        '--dart-define=PULSE_BACKEND_URL=http://localhost:3000.';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reportsListProvider.overrideWith(
            (ref) => Future<List<ReportModel>>.error(
              const NetworkException(message),
            ),
          ),
        ],
        child: const MaterialApp(home: ReportsTab()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load reports'), findsOneWidget);
    expect(
      find.textContaining('PULSE backend is not configured'),
      findsOneWidget,
    );

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    // The error is rendered in the tab; retry must not leak an uncaught
    // async exception to the Flutter error handler.
    expect(tester.takeException(), isNull);
    expect(find.text('Could not load reports'), findsOneWidget);
  });
}
