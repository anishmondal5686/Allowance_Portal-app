import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/models/master_data.dart';
import 'package:allowance_shared/models/movement.dart';
import 'package:allowance_app/screens/dashboard_screen.dart';
import 'package:allowance_app/services/drive_service.dart';
import 'package:allowance_shared/theme/modern_theme.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';

/// In-memory [DriveService] subclass whose operations never touch the
/// file system, so month switching is deterministic under the widget test's
/// fake async. `saveLocalBackup` snapshots the claim (serialisation
/// round-trip), so assertions on flushed months observe what was actually
/// written, not a live alias.
class _FakeDriveService extends DriveService {
  final Map<String, ClaimData> saved = {};

  @override
  Future<ClaimData?> loadLocalBackup({String? month}) async => saved[month];

  @override
  Future<List<String>> listSavedMonths() async => saved.keys.toList();

  @override
  Future<String> saveLocalBackup(ClaimData data) async {
    saved[data.master.month] = ClaimData.fromJson(
        jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>);
    return 'fake';
  }
}

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
          onDataChanged: () {},
          themeId: ModernThemeId.modernMarine,
          onThemeChanged: (_) {},
          appVersion: '2.0.18',
          driveService: _FakeDriveService(),
        ),
      ),
    ));

    expect(claim.movements, isNotEmpty);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('August').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Start a new month?'), findsOneWidget);
    expect(find.text('Start New'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Start New'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

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
          onDataChanged: () {},
          themeId: ModernThemeId.modernMarine,
          onThemeChanged: (_) {},
          appVersion: '2.0.18',
          driveService: _FakeDriveService(),
        ),
      ),
    ));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('August').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Start a new month?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(claim.master.month, '2026-09');
    expect(claim.attShifts, isNotEmpty);
  });

  testWidgets('changing to a saved month auto-loads the saved claim',
      (tester) async {
    final store = _FakeDriveService();
    final saved = ClaimData(
      master: MasterData(
        month: '2026-08',
        name: 'SAVED USER',
        designation: 'DOCK PILOT',
      ),
    );
    saved.movements.addAll([
      Movement(
        date: '2026-08-12',
        start: '10:00',
        end: '13:00',
        from: 'JETTY',
        to: 'ANCHORAGE',
        allowance: 'Length',
      ),
    ]);
    store.saved['2026-08'] = saved;

    final claim = ClaimData(
      master: MasterData(
        month: '2026-09',
        name: 'TEST USER',
        designation: 'BERTHING PILOT',
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DashboardScreen(
          key: UniqueKey(),
          claimData: claim,
          onDataChanged: () {},
          themeId: ModernThemeId.modernMarine,
          onThemeChanged: (_) {},
          appVersion: '2.0.18',
          driveService: store,
        ),
      ),
    ));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('August').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Start a new month?'), findsNothing);
    expect(claim.master.month, '2026-08');
    expect(claim.master.name, 'SAVED USER');
    expect(claim.movements, hasLength(1));
  });

  testWidgets('pending master edits flush into the old month before switching',
      (tester) async {
    final store = _FakeDriveService();
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
          onDataChanged: () {},
          themeId: ModernThemeId.modernMarine,
          onThemeChanged: (_) {},
          appVersion: '2.0.18',
          driveService: store,
        ),
      ),
    ));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Edit a master field without explicitly saving.
    await tester.enterText(
        find.byType(FormBuilderTextField).first,
        'NEW NAME');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Master Data now sits below the fold, so focusing the name field scrolls
    // it into view and pushes the month picker off the top. Scroll back.
    await tester.ensureVisible(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('August').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // No prompt: the flush already wrote September, then the switch proceeds.
    expect(find.text('Unsaved changes'), findsNothing);
    expect(find.text('Start a new month?'), findsOneWidget);

    await tester.tap(find.text('Start New'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(claim.master.month, '2026-08');
    expect(store.saved['2026-09']?.master.name, 'NEW NAME');
  });

  testWidgets('switching to a saved month flushes pending edits first, then loads',
      (tester) async {
    final store = _FakeDriveService();
    final saved = ClaimData(
      master: MasterData(
        month: '2026-08',
        name: 'SAVED USER',
        designation: 'DOCK PILOT',
      ),
    );
    saved.movements.addAll([
      Movement(
        date: '2026-08-12',
        start: '10:00',
        end: '13:00',
        from: 'JETTY',
        to: 'ANCHORAGE',
        allowance: 'Length',
      ),
    ]);
    store.saved['2026-08'] = saved;

    final claim = ClaimData(
      master: MasterData(
        month: '2026-09',
        name: 'TEST USER',
        designation: 'BERTHING PILOT',
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DashboardScreen(
          key: UniqueKey(),
          claimData: claim,
          onDataChanged: () {},
          themeId: ModernThemeId.modernMarine,
          onThemeChanged: (_) {},
          appVersion: '2.0.18',
          driveService: store,
        ),
      ),
    ));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.enterText(
        find.byType(FormBuilderTextField).first,
        'NEW NAME');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.ensureVisible(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('August').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // September's pending edit is preserved on disk, then August loads over it.
    expect(find.text('Unsaved changes'), findsNothing);
    expect(find.text('Start a new month?'), findsNothing);
    expect(store.saved['2026-09']?.master.name, 'NEW NAME');
    expect(claim.master.month, '2026-08');
    expect(claim.master.name, 'SAVED USER');
    expect(claim.movements, hasLength(1));
  });
}
