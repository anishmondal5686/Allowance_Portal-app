import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/models/master_data.dart';
import 'package:allowance_app/screens/dashboard_screen.dart';
import 'package:allowance_app/services/drive_service.dart';
import 'package:allowance_shared/theme/modern_theme.dart';

void main() {
  testWidgets('employee field label is DPS No. for DOCK PILOT and ADM, '
      'Employee ID for Berthing Pilot', (tester) async {
    Future<void> pump(String designation) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DashboardScreen(
            key: UniqueKey(),
            claimData: ClaimData(master: MasterData(designation: designation)),
            driveService: DriveService(),
            onDataChanged: () {},
            themeId: ModernThemeId.modernMarine,
            onThemeChanged: (_) {},
            appVersion: '2.0.4',
          ),
        ),
      ));
    }

    await pump('DOCK PILOT');
    expect(find.text('DPS No.'), findsOneWidget);
    expect(find.text('Employee ID'), findsNothing);

    await pump('ADM');
    expect(find.text('DPS No.'), findsOneWidget);
    expect(find.text('Employee ID'), findsNothing);

    await pump('BERTHING PILOT');
    expect(find.text('Employee ID'), findsOneWidget);
    expect(find.text('DPS No.'), findsNothing);
  });
}
