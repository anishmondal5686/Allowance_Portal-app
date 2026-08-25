import 'dart:convert';

import 'package:allowance_app_v2/screens/dashboard_screen.dart';
import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/theme/modern_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
    ),
  );
}

Future<void> _pumpAtSize(WidgetTester tester, ClaimData data,
    {double textScale = 1.0}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  tester.view.platformDispatcher.textScaleFactorTestValue = textScale;
  await tester.pumpWidget(_buildDashboard(data));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _scrollFull(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.fling(find.byType(Scrollable).first, const Offset(0, -600), 1200);
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('dashboard default text scale has no overflow', (tester) async {
    await _pumpAtSize(tester, parseData());
    await _scrollFull(tester);
  });

  testWidgets('dashboard 1.15x text scale has no overflow', (tester) async {
    await _pumpAtSize(tester, parseData(), textScale: 1.15);
    await _scrollFull(tester);
  });

  testWidgets('dashboard 1.3x text scale has no overflow', (tester) async {
    await _pumpAtSize(tester, parseData(), textScale: 1.3);
    await _scrollFull(tester);
  });
}
