import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/models/master_data.dart';
import 'package:allowance_app_v2/screens/dashboard_screen.dart';
import 'package:allowance_app_v2/services/local_store.dart';
import 'package:allowance_shared/theme/modern_theme.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';

/// In-memory [LocalStore] so the dashboard never touches path_provider.
class _FakeLocalStore extends LocalStore {
  final Map<String, ClaimData> saved = {};

  @override
  Future<ClaimData?> load({String? month}) async => saved[month];

  @override
  Future<List<String>> listSavedMonths() async => saved.keys.toList();
}

Widget _dashboard(ClaimData claim, {LocalStore? store, VoidCallback? onChanged}) {
  return MaterialApp(
    home: Scaffold(
      body: DashboardScreen(
        key: UniqueKey(),
        claimData: claim,
        onDataChanged: onChanged ?? () {},
        themeId: ModernThemeId.modernMarine,
        onThemeChanged: (_) {},
        appVersion: '2.0.36',
        localStore: store ?? _FakeLocalStore(),
      ),
    ),
  );
}

ClaimData _claim({String designation = 'BERTHING PILOT'}) => ClaimData(
      master: MasterData(
        month: '2026-09',
        name: 'TEST USER',
        designation: designation,
      ),
    );

Finder _field(String name) => find.byWidgetPredicate(
      (w) => w is FormBuilderTextField && w.name == name,
      description: 'FormBuilderTextField($name)',
    );

/// Records `SystemNavigator.pop()` requests. The dashboard is the root route,
/// so a confirmed exit is a platform exit request rather than a route pop —
/// `handlePopRoute` in binding.dart falls through to the platform whenever
/// `maybePop` has nothing to dismiss.
List<String> _watchExitRequests(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      calls.add(call.method);
      return null;
    },
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, null);
  });
  return calls;
}

int _exits(List<String> calls) =>
    calls.where((m) => m == 'SystemNavigator.pop').length;

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Simulates the system back gesture.
Future<void> _pressBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await _settle(tester);
}

Future<void> _type(WidgetTester tester, String field, String value) async {
  await tester.enterText(_field(field), value);
  await _settle(tester);
}

/// Fills every field the master form validates as required, so `_saveMaster`'s
/// `saveAndValidate()` passes. `pay` is only required for a berthing pilot.
Future<void> _fillRequiredFields(
  WidgetTester tester, {
  String designation = 'BERTHING PILOT',
}) async {
  await _type(tester, 'employee', 'EMP-1');
  await _type(tester, 'sapEmployeeId', 'SAP-1');
  // Bill and pay are digits-only fields.
  await _type(tester, 'bill', '4242');
  if (designation == 'BERTHING PILOT') {
    await _type(tester, 'pay', '1000');
  }
}

/// Taps a Daily Action tile, scrolling it into view first. Focusing a master
/// field scrolls the tile row off-screen, which makes a bare tap miss.
Future<void> _tapTile(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await _settle(tester);
}

void main() {
  testWidgets('back with no unsaved edits exits without prompting',
      (tester) async {
    final exits = _watchExitRequests(tester);
    await tester.pumpWidget(_dashboard(_claim()));
    await _settle(tester);

    await _pressBack(tester);

    expect(find.text('Unsaved changes'), findsNothing);
    // Nothing to confirm, so the framework pops/exits on its own.
    expect(_exits(exits), 1);
  });

  testWidgets('back with unsaved edits prompts instead of exiting',
      (tester) async {
    final exits = _watchExitRequests(tester);
    await tester.pumpWidget(_dashboard(_claim()));
    await _settle(tester);

    await _type(tester, 'name', 'NEW NAME');
    await _pressBack(tester);

    expect(find.text('Unsaved changes'), findsOneWidget);
    // The guard must hold: exiting now would silently lose the edit.
    expect(_exits(exits), 0);
  });

  testWidgets('cancelling the unsaved-changes prompt keeps the dashboard',
      (tester) async {
    final exits = _watchExitRequests(tester);
    final claim = _claim();
    await tester.pumpWidget(_dashboard(claim));
    await _settle(tester);

    await _type(tester, 'name', 'NEW NAME');
    await _pressBack(tester);

    await tester.tap(find.text('Cancel'));
    await _settle(tester);

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.text('Unsaved changes'), findsNothing);
    expect(_exits(exits), 0);
    expect(claim.master.name, 'TEST USER');
  });

  testWidgets('discarding unsaved edits exits without persisting them',
      (tester) async {
    final exits = _watchExitRequests(tester);
    final claim = _claim();
    var saves = 0;
    await tester.pumpWidget(_dashboard(claim, onChanged: () => saves++));
    await _settle(tester);

    await _type(tester, 'name', 'NEW NAME');
    await _pressBack(tester);

    await tester.tap(find.text('Discard'));
    await _settle(tester);

    expect(find.text('Unsaved changes'), findsNothing);
    expect(_exits(exits), 1);
    expect(claim.master.name, 'TEST USER');
    expect(saves, 0);
  });

  testWidgets('saving unsaved edits exits and persists the master form',
      (tester) async {
    final exits = _watchExitRequests(tester);
    final claim = _claim();
    var saves = 0;
    await tester.pumpWidget(_dashboard(claim, onChanged: () => saves++));
    await _settle(tester);

    await _fillRequiredFields(tester);
    await _type(tester, 'name', 'NEW NAME');
    await _pressBack(tester);
    expect(find.text('Unsaved changes'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await _settle(tester);

    expect(find.text('Unsaved changes'), findsNothing);
    expect(_exits(exits), 1);
    expect(claim.master.name, 'NEW NAME');
    expect(claim.master.bill, '4242');
    expect(saves, 1);
  });

  // Regression: the dashboard used to compare a serialization of the claim
  // against a baseline captured when the widget was built. Returning from a
  // child screen left that baseline stale, so back and the month switcher both
  // prompted about work that was already saved.
  testWidgets('a child-screen round trip does not resurrect a false prompt',
      (tester) async {
    final exits = _watchExitRequests(tester);
    final claim = _claim();
    await tester.pumpWidget(_dashboard(claim));
    await _settle(tester);

    // Clean form, so the child return clears the dirty flag.
    await _tapTile(tester, 'Movements');
    expect(find.text('Unsaved changes'), findsNothing);

    await _pressBack(tester);
    await _settle(tester);
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(_exits(exits), 0);

    await _pressBack(tester);
    expect(find.text('Unsaved changes'), findsNothing);
    expect(_exits(exits), 1);
  });

  // The Movements and Attendance screens persist their own data but never
  // commit the master form, so clearing the flag on return must not drop a
  // pending master edit.
  testWidgets('an unsaved master edit still prompts after a child round trip',
      (tester) async {
    final exits = _watchExitRequests(tester);
    final claim = _claim();
    await tester.pumpWidget(_dashboard(claim));
    await _settle(tester);

    await _type(tester, 'name', 'NEW NAME');
    await _tapTile(tester, 'Movements');

    await _pressBack(tester);
    await _settle(tester);
    expect(find.byType(DashboardScreen), findsOneWidget);

    await _pressBack(tester);
    expect(find.text('Unsaved changes'), findsOneWidget);
    expect(_exits(exits), 0);
    expect(claim.master.name, 'TEST USER');
  });

  testWidgets('back after an explicit master save does not prompt',
      (tester) async {
    final exits = _watchExitRequests(tester);
    final claim = _claim();
    var saves = 0;
    await tester.pumpWidget(_dashboard(claim, onChanged: () => saves++));
    await _settle(tester);

    await _fillRequiredFields(tester);
    await _pressBack(tester);
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await _settle(tester);

    expect(saves, 1);
    expect(claim.master.name, 'TEST USER');

    // A second back press has nothing left to confirm.
    await _pressBack(tester);
    expect(find.text('Unsaved changes'), findsNothing);
    expect(_exits(exits), 2);
  });

  testWidgets('a back press inside a child screen is not guarded',
      (tester) async {
    final exits = _watchExitRequests(tester);
    await tester.pumpWidget(_dashboard(_claim()));
    await _settle(tester);

    await _tapTile(tester, 'Movements');
    expect(find.text('Unsaved changes'), findsNothing);

    // Back on the child screen pops it, no dialog: only the dashboard guards.
    await _pressBack(tester);
    expect(find.text('Unsaved changes'), findsNothing);
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(_exits(exits), 0);
  });
}