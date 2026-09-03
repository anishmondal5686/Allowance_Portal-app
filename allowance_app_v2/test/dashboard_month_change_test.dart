import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/models/master_data.dart';
import 'package:allowance_shared/models/movement.dart';
import 'package:allowance_app_v2/screens/dashboard_screen.dart';
import 'package:allowance_app_v2/services/local_store.dart';
import 'package:allowance_shared/theme/modern_theme.dart';

/// In-memory [LocalStore] that never touches path_provider or the file system,
/// so month switching is deterministic under the widget test's fake async.
class _FakeLocalStore extends LocalStore {
  final Map<String, ClaimData> saved = {};

  @override
  Future<ClaimData?> load({String? month}) async => saved[month];

  @override
  Future<List<String>> listSavedMonths() async => saved.keys.toList();
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
          localStore: _FakeLocalStore(),
        ),
      ),
    ));

    expect(claim.movements, isNotEmpty);

    await tester.pumpAndSettle();
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
          onDataChanged: () {},
          themeId: ModernThemeId.modernMarine,
          onThemeChanged: (_) {},
          appVersion: '2.0.18',
          localStore: _FakeLocalStore(),
        ),
      ),
    ));

    await tester.pumpAndSettle();
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

  testWidgets('changing to a saved month auto-loads the saved claim',
      (tester) async {
    final store = _FakeLocalStore();
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
          localStore: store,
        ),
      ),
    ));

    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('August').last);
    await tester.pumpAndSettle();

    expect(find.text('Start a new month?'), findsNothing);
    expect(claim.master.month, '2026-08');
    expect(claim.master.name, 'SAVED USER');
    expect(claim.movements, hasLength(1));
  });

  testWidgets('unsaved edits prompt before switching and Cancel aborts',
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
          localStore: _FakeLocalStore(),
        ),
      ),
    ));

    await tester.pumpAndSettle();

    // Edit an uncommitted master-field change (typing alone is not autosaved).
    await tester.enterText(
        find.widgetWithText(TextFormField, 'TEST USER'), 'NEW NAME');
    await tester.pump();

    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('August').last);
    await tester.pumpAndSettle();

    expect(find.text('Unsaved changes'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(claim.master.month, '2026-09');
    expect(claim.attShifts, isNotEmpty);
    expect(find.text('Start a new month?'), findsNothing);
  });

  testWidgets('unsaved edits prompt lets the user discard and continue switching',
      (tester) async {
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
          localStore: _FakeLocalStore(),
        ),
      ),
    ));

    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'TEST USER'), 'NEW NAME');
    await tester.pump();

    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('August').last);
    await tester.pumpAndSettle();

    expect(find.text('Unsaved changes'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    // Continue to the 'Start a new month?' flow for the empty target month.
    expect(find.text('Start a new month?'), findsOneWidget);
    await tester.tap(find.text('Start New'));
    await tester.pumpAndSettle();
    expect(claim.master.month, '2026-08');
  });
}
