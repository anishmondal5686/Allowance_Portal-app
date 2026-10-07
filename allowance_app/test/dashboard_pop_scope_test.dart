import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/models/master_data.dart';
import 'package:allowance_app/screens/dashboard_screen.dart';
import 'package:allowance_app/services/drive_service.dart';
import 'package:allowance_shared/theme/modern_theme.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';

/// In-memory [DriveService] so the dashboard never touches the file system or
/// Google APIs. `saveLocalBackup` snapshots the claim (serialisation
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

Widget _dashboard(ClaimData claim,
    {DriveService? drive, VoidCallback? onChanged}) {
  return MaterialApp(
    home: Scaffold(
      body: DashboardScreen(
        key: UniqueKey(),
        claimData: claim,
        driveService: drive ?? _FakeDriveService(),
        onDataChanged: onChanged ?? () {},
        themeId: ModernThemeId.modernMarine,
        onThemeChanged: (_) {},
        appVersion: '2.0.36',
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
/// so an exit is a platform exit request rather than a route pop â€”
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

  testWidgets('back with unsaved edits flushes them and exits without prompting',
      (tester) async {
    final exits = _watchExitRequests(tester);
    final claim = _claim();
    final store = _FakeDriveService();
    var saves = 0;
    await tester.pumpWidget(
        _dashboard(claim, drive: store, onChanged: () => saves++));
    await _settle(tester);

    await _type(tester, 'name', 'NEW NAME');
    await _pressBack(tester);

    // No dialog: the pending edit is flushed to the store, then the app exits.
    expect(find.text('Unsaved changes'), findsNothing);
    expect(_exits(exits), 1);
    expect(claim.master.name, 'NEW NAME');
    expect(store.saved['2026-09']?.master.name, 'NEW NAME');
    expect(saves, greaterThanOrEqualTo(1));
  });

  testWidgets('the debounce window auto-commits edits without pressing back',
      (tester) async {
    final store = _FakeDriveService();
    final claim = _claim();
    await tester.pumpWidget(_dashboard(claim, drive: store));
    await _settle(tester);

    await _type(tester, 'name', 'NEW NAME');

    // Let the 2s auto-commit timer fire under the fake async clock.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(store.saved['2026-09']?.master.name, 'NEW NAME');
    expect(find.text('Unsaved changes'), findsNothing);
  });

  testWidgets('explicit Save still commits a valid form, then back exits cleanly',
      (tester) async {
    final exits = _watchExitRequests(tester);
    final claim = _claim();
    var saves = 0;
    await tester.pumpWidget(_dashboard(claim, onChanged: () => saves++));
    await _settle(tester);

    await _fillRequiredFields(tester);
    await _type(tester, 'name', 'NEW NAME');
    await tester.ensureVisible(find.text('Save Master Data'));
    await tester.pump();
    await tester.tap(find.text('Save Master Data'));
    await _settle(tester);

    expect(saves, 1);
    expect(claim.master.name, 'NEW NAME');

    // A back press flushes (no-op: already saved) and exits, no dialog.
    await _pressBack(tester);
    expect(find.text('Unsaved changes'), findsNothing);
    expect(_exits(exits), 1);
  });

  testWidgets('a child-screen round trip then back exits without prompting',
      (tester) async {
    final exits = _watchExitRequests(tester);
    final claim = _claim();
    await tester.pumpWidget(_dashboard(claim));
    await _settle(tester);

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
  // commit the master form; a pending master edit must survive the round
  // trip and flush on exit instead of being dropped or prompting.
  testWidgets('an unsaved master edit survives a child round trip and flushes on exit',
      (tester) async {
    final exits = _watchExitRequests(tester);
    final claim = _claim();
    final store = _FakeDriveService();
    await tester.pumpWidget(_dashboard(claim, drive: store));
    await _settle(tester);

    await _type(tester, 'name', 'NEW NAME');
    await _tapTile(tester, 'Movements');

    await _pressBack(tester);
    await _settle(tester);
    expect(find.byType(DashboardScreen), findsOneWidget);

    await _pressBack(tester);
    expect(find.text('Unsaved changes'), findsNothing);
    expect(_exits(exits), 1);
    expect(claim.master.name, 'NEW NAME');
    expect(store.saved['2026-09']?.master.name, 'NEW NAME');
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
