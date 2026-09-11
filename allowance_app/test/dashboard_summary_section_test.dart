import 'dart:convert';

import 'package:allowance_app/screens/dashboard_screen.dart';
import 'package:allowance_app/services/drive_service.dart';
import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/services/allowance_calculator.dart';
import 'package:allowance_shared/theme/modern_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

/// Minimal in-memory [DriveService] that never touches storage or the network,
/// so the dashboard's init-time month listing is deterministic under the
/// widget test's fake async clock.
class _FakeDriveService extends DriveService {
  @override
  Future<List<String>> listSavedMonths() async => <String>[];

  @override
  Future<ClaimData?> loadLocalBackup({String? month}) async => null;
}

const String augustJson = r'''
{"master":{"month":"2026-08","name":"ANISH MONDAL","designation":"BERTHING PILOT","employee":"20281","pay":"83000","bill":"9090","basic":"","ada":""},"movements":[{"date":"02/08/2026","vessel":"BERGE NISHIKAWA","from":"13","to":"LOCK","start":"0500","end":"0600","loa":"199.9","beam":"32.26","allowances":["length","nightact"],"navigationTypes":[]},{"date":"03/08/2026","vessel":"LADY","from":"LOCK","to":"4","start":"0126","end":"0300","loa":"199.9","beam":"32.25","allowances":["length","nightact"],"navigationTypes":[]},{"date":"04/08/2026","vessel":"COMMON LUCK","from":"LOCK","to":"2","start":"0212","end":"0310","loa":"197.0","beam":"32.26","allowances":["length","nightact"],"navigationTypes":[]},{"date":"05/08/2026","vessel":"PETIT LANCY","from":"3","to":"LOCK","start":"1924","end":"2012","loa":"228.99","beam":"32.26","allowances":["length","navigation"],"navigationTypes":["outward-210"]}],"attOffDay":"2","attRotation":"N","attShifts":{"2026-8-1":"N","2026-8-2":"N","2026-8-3":"N","2026-8-4":"OFF","2026-8-5":"E"},"attManualDates":["2026-8-1"],"actingAdmDates":[],"attLocked":true}
''';

ClaimData parseData() =>
    ClaimData.fromJson(jsonDecode(augustJson) as Map<String, dynamic>);

Widget _buildDashboard(ClaimData data) {
  return MaterialApp(
    home: DashboardScreen(
      claimData: data,
      onDataChanged: () {},
      themeId: ModernThemeId.modernMarine,
      onThemeChanged: (_) {},
      appVersion: '2.0.8',
      driveService: _FakeDriveService(),
    ),
  );
}

Future<void> _pumpDashboard(WidgetTester tester) async {
  tester.view.devicePixelRatio = 2.625;
  tester.view.physicalSize = const Size(1080, 2400);
  await tester.pumpWidget(_buildDashboard(parseData()));
  await tester.pump(const Duration(seconds: 1));
  for (var i = 0; i < 6; i++) {
    await tester.fling(
        find.byType(Scrollable).first, const Offset(0, -500), 1200);
    await tester.pump(const Duration(milliseconds: 200));
  }
}

final _fmt = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

void main() {
  testWidgets('Monthly Summary section replaces Quick Stats', (tester) async {
    await _pumpDashboard(tester);
    expect(find.text('Monthly Summary'), findsOneWidget);
    expect(find.text('Claim totals & active allowances'), findsOneWidget);
    expect(find.text('Quick Stats'), findsNothing);
    expect(find.text('Overview of current month'), findsNothing);
  });

  testWidgets('hero shows grand total and active claims count', (tester) async {
    final summary = AllowanceCalculator.computeSummary(parseData());
    expect(summary.lines, isNotEmpty);
    await _pumpDashboard(tester);
    expect(find.text('Grand Total'), findsOneWidget);
    expect(find.text(_fmt.format(summary.grandTotal)), findsOneWidget);
    expect(
      find.text('Active claims · ${summary.lines.length}'),
      findsOneWidget,
    );
  });

  testWidgets('per-allowance KPI cards render labels and hours',
      (tester) async {
    final summary = AllowanceCalculator.computeSummary(parseData());
    await _pumpDashboard(tester);
    for (final line in summary.lines) {
      // Each label appears in KPI card and in PieChart badge
      expect(find.text(line.label), findsWidgets);
      expect(find.text(_fmt.format(line.amount)), findsOneWidget);
    }
    final weightage = summary.lines
        .where((l) => l.key == 'weightage')
        .toList();
    if (weightage.isNotEmpty) {
      expect(find.textContaining(RegExp(r'for .* hrs')), findsOneWidget);
    }
  });
}