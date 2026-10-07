import 'package:allowance_app_v2/screens/dashboard_screen.dart';
import 'package:allowance_shared/services/allowance_calculator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two / three allowance lines, matching the case where a previously zero line
/// becomes payable and the pie has to grow a section while still animating.
ClaimSummary _summary(int lineCount) {
  final lines = [
    for (var i = 0; i < lineCount; i++)
      ClaimSummaryLine('key$i', 'Label $i', 100.0 + i),
  ];
  return ClaimSummary(
    lines: lines,
    grandTotal: lines.fold<double>(0, (sum, l) => sum + l.amount),
    payWarning: false,
  );
}

Widget _host(ClaimSummary summary) => MaterialApp(
      home: Scaffold(body: AllowancePieChart(summary: summary)),
    );

void main() {
  testWidgets('growing the section count mid-animation does not throw RangeError',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_summary(2)));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.pumpWidget(_host(_summary(3)));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // fl_chart's RenderPieChart.badgeWidgetPaint has no bounds check on
    // data.sections, so a stale section count would surface here.
    expect(tester.takeException(), isNull);
    expect(find.byType(AllowancePieChart), findsOneWidget);
  });

  testWidgets('shrinking the section count mid-animation does not throw',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_summary(4)));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.pumpWidget(_host(_summary(2)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
