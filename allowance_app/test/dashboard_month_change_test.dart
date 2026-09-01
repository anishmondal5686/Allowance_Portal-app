import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/models/master_data.dart';
import 'package:allowance_shared/models/movement.dart';
import 'package:allowance_app/screens/dashboard_screen.dart';
import 'package:allowance_app/services/drive_service.dart';
import 'package:allowance_shared/theme/modern_theme.dart';

void main() {
  testWidgets('changing the month asks to start a new claim and clears data',
      (tester) async {
    final claim = ClaimData(
      master: MasterData(
        month: '2026-09',
        name: 'TEST USER',
        designation: 'BERTHING PILOT',
      ),
    );
    claim.movements.addAll([
      Movement(
        date: '2026-09-05',
        start: '09:00',
        end: '12:00',
        from: 'JETTY',
        to: 'ANCHORAGE',
        allowance: 'Length',
      ),
    ]);
    claim.attShifts['2026-09-05'] = 'N';

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DashboardScreen(
          key: UniqueKey(),
          claimData: claim,
          driveService: DriveService(),
          onDataChanged: () {},
          themeId: ModernThemeId.modernMarine,
          onThemeChanged: (_) {},
          appVersion: '2.0.18',
        ),
      ),
    ));

    expect(claim.movements, isNotEmpty);

    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('August').last);
    await tester.pumpAndSettle();

    expect(find.text('Start a new month?'), findsOneWidget);
    expect(find.text('Start New'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Start New'));
    await tester.pumpAndSettle();

    expect(claim.master.month, '2026-08');
    expect(claim.movements, isEmpty);
    expect(claim.attShifts, isEmpty);
  });

  testWidgets('cancelling the month change keeps current data and month',
      (tester) async {
    final claim = ClaimData(
      master: MasterData(
        month: '2026-09',
        name: 'TEST USER',
        designation: 'BERTHING PILOT',
      ),
    );
    claim.attShifts['2026-09-05'] = 'N';

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DashboardScreen(
          key: UniqueKey(),
          claimData: claim,
          driveService: DriveService(),
          onDataChanged: () {},
          themeId: ModernThemeId.modernMarine,
          onThemeChanged: (_) {},
          appVersion: '2.0.18',
        ),
      ),
    ));

    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('August').last);
    await tester.pumpAndSettle();

    expect(find.text('Start a new month?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(claim.master.month, '2026-09');
    expect(claim.attShifts, isNotEmpty);
  });
}
