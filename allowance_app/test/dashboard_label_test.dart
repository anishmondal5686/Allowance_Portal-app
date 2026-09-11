import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/models/master_data.dart';
import 'package:allowance_app/screens/dashboard_screen.dart';
import 'package:allowance_app/services/drive_service.dart';
import 'package:allowance_shared/theme/modern_theme.dart';

/// In-memory [DriveService] that never touches storage or the network.
class _FakeDriveService extends DriveService {
  _FakeDriveService();

  @override
  Future<ClaimData?> loadLocalBackup({String? month}) async => null;

  @override
  Future<List<String>> listSavedMonths() async => <String>[];
}

void main() {
  testWidgets('employee field label is DPS No. for DOCK PILOT and ADM, '
      'Employee ID for Berthing Pilot', (tester) async {
    Future<void> pump(String designation) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DashboardScreen(
            key: UniqueKey(),
            claimData: ClaimData(master: MasterData(designation: designation)),
            driveService: _FakeDriveService(),
            onDataChanged: () {},
            themeId: ModernThemeId.modernMarine,
            onThemeChanged: (_) {},
            appVersion: '2.0.4',
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    await pump('DOCK PILOT');
    expect(find.text('DPS No.'), findsOneWidget);
    expect(find.text('Employee ID'), findsNothing);
    expect(find.text('SAP Employee ID'), findsOneWidget);

    await pump('ADM');
    expect(find.text('DPS No.'), findsOneWidget);
    expect(find.text('Employee ID'), findsNothing);
    expect(find.text('SAP Employee ID'), findsOneWidget);

    await pump('BERTHING PILOT');
    expect(find.text('Employee ID'), findsOneWidget);
    expect(find.text('DPS No.'), findsNothing);
    expect(find.text('SAP Employee ID'), findsOneWidget);
  });
}