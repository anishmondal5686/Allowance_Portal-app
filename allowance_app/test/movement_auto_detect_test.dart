import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/models/master_data.dart';
import 'package:allowance_shared/models/movement.dart';
import 'package:allowance_app/screens/movement_screen.dart';

void main() {
  testWidgets('Auto-detect is shown for Berthing Pilot but hidden for '
      'DOCK PILOT and ADM', (tester) async {
    Future<void> pump(String designation) async {
      await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        home: Scaffold(
          body: MovementScreen(
            key: UniqueKey(),
            claimData: ClaimData(master: MasterData(designation: designation)),
            onChanged: () {},
          ),
        ),
      ));
      await tester.tap(find.byTooltip('Add Movement'));
      await tester.pumpAndSettle();
    }

    await pump('BERTHING PILOT');
    expect(find.text('Auto-detect allowances'), findsOneWidget);

    await pump('DOCK PILOT');
    expect(find.text('Auto-detect allowances'), findsNothing);

    await pump('ADM');
    expect(find.text('Auto-detect allowances'), findsNothing);
  });

  testWidgets('ADM movement form offers Length, Lock and Night Nav with '
      'outward/inward nav types', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MovementScreen(
        key: UniqueKey(),
        claimData: ClaimData(master: MasterData(designation: 'ADM')),
        onChanged: () {},
      ),
    ));
    await tester.tap(find.byTooltip('Add Movement'));
    await tester.pumpAndSettle();

    expect(find.text('Length'), findsOneWidget);
    expect(find.text('Lock to App. Jetty & vice versa'), findsOneWidget);
    expect(find.text('Night Nav'), findsOneWidget);
    expect(find.text('Cold Move'), findsNothing);
    expect(find.text('Night Act'), findsNothing);

    await tester.ensureVisible(find.text('Night Nav'));
    await tester.tap(find.text('Night Nav'));
    await tester.pumpAndSettle();
    expect(find.text('Out 180-210'), findsOneWidget);
    expect(find.text('Out ≥210'), findsOneWidget);
    expect(find.text('Out Beam≥30.5'), findsOneWidget);
    expect(find.text('In ≥210'), findsOneWidget);
    expect(find.text('Dbl Banking'), findsNothing);
    expect(find.text('Unbanking'), findsNothing);
  });

  testWidgets('BP editing a movement on an acting-ADM date sees ADM options '
      'and drops disallowed allowances', (tester) async {
    final data = ClaimData(
      master: MasterData(
        month: 'JULY, 2026',
        designation: 'Berthing Pilot',
      ),
      actingAdmDates: ['2026-7-12'],
    );
    data.movements.add(Movement(
        date: '12/07/26',
        vessel: 'MV ACT',
        from: 'B2',
        to: 'OFF',
        start: '06:00',
        end: '09:00',
        loa: '229',
        beam: '32',
        allowance: 'length'));
    await tester.pumpWidget(MaterialApp(
      home: MovementScreen(
        key: UniqueKey(),
        claimData: data,
        onChanged: () {},
      ),
    ));
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(
          of: dialog, matching: find.text('Length')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: dialog, matching: find.text('Lock to App. Jetty & vice versa')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Night Nav')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Cold Move')),
      findsNothing,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Night Act')),
      findsNothing,
    );
  });

  testWidgets('register card hides Night Act/Cold on acting-ADM dates',
      (tester) async {
    final data = ClaimData(
      master: MasterData(month: 'JULY, 2026', designation: 'Berthing Pilot'),
      actingAdmDates: ['2026-7-12'],
    );
    data.movements.add(Movement(
        date: '12/07/26',
        vessel: 'MV ACT',
        from: 'B2',
        to: 'OFF',
        start: '23:00',
        end: '02:00',
        loa: '229',
        beam: '32',
        allowances: ['length', 'nightact', 'navigation']));
    await tester.pumpWidget(MaterialApp(
      home: MovementScreen(
        key: UniqueKey(),
        claimData: data,
        onChanged: () {},
      ),
    ));
    expect(find.textContaining('Length'), findsWidgets);
    expect(find.textContaining('Night Nav'), findsWidgets);
    expect(find.textContaining('Night Act'), findsNothing);
    expect(find.textContaining('Cold'), findsNothing);
  });
}
