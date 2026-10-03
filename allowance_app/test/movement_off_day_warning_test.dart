import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/models/master_data.dart';
import 'package:allowance_shared/models/movement.dart';
import 'package:allowance_app/screens/movement_screen.dart';

void main() {
  // A 00:45 movement dated 13/07 belongs to the night shift of 12/07, so the
  // shift key differs from the raw date key and the OFF/unmarked guard runs.
  ClaimData seed(String start, {Map<String, String> att = const {}}) {
    final data = ClaimData(
      master: MasterData(month: 'JULY, 2026', designation: 'Berthing Pilot'),
    );
    data.attShifts.addAll(att);
    data.movements.add(Movement(
      date: '13/07/26',
      vessel: 'MV NIGHT',
      from: 'LOCK',
      to: 'BASIN',
      start: start,
      end: '04:00',
      loa: '180',
      beam: '32',
      allowance: 'length',
    ));
    return data;
  }

  Future<void> openEditor(WidgetTester tester, ClaimData data) async {
    await tester.pumpWidget(MaterialApp(
      home: MovementScreen(
        key: UniqueKey(),
        claimData: data,
        onChanged: () {},
      ),
    ));
    await tester.drag(find.byType(Slidable), const Offset(-400, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Save Movement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Movement'));
    await tester.pumpAndSettle();
  }

  testWidgets('post-midnight movement on an unmarked day warns before saving',
      (tester) async {
    await openEditor(tester, seed('00:45'));
    await tapSave(tester);

    expect(find.text('Night shift movement'), findsOneWidget);
    expect(find.textContaining('belongs to the night shift of'), findsOneWidget);
    expect(find.textContaining('not marked as a duty day'), findsOneWidget);
  });

  testWidgets('Cancel dismisses the warning and keeps the form open',
      (tester) async {
    await openEditor(tester, seed('00:45'));
    await tapSave(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Night shift movement'), findsNothing);
    expect(find.text('Save Movement'), findsOneWidget);
  });

  testWidgets('Save anyway closes the form and keeps the movement',
      (tester) async {
    final data = seed('00:45');
    await openEditor(tester, data);
    await tapSave(tester);

    await tester.tap(find.text('Save anyway'));
    await tester.pumpAndSettle();

    expect(find.text('Night shift movement'), findsNothing);
    expect(find.text('Save Movement'), findsNothing);
    expect(data.movements.length, 1);
    expect(data.movements.first.start, '00:45');
  });

  testWidgets('an OFF night shift shows the off-day reason', (tester) async {
    await openEditor(tester, seed('00:45', att: const {'2026-7-12': 'OFF'}));
    await tapSave(tester);

    expect(find.text('Night shift movement'), findsOneWidget);
    expect(find.textContaining('marked as an off day'), findsOneWidget);
  });

  testWidgets('a marked night shift saves without warning', (tester) async {
    await openEditor(tester, seed('00:45', att: const {'2026-7-12': 'N'}));
    await tapSave(tester);

    expect(find.text('Night shift movement'), findsNothing);
    expect(find.text('Save Movement'), findsNothing);
  });

  testWidgets('a same-day movement saves without warning', (tester) async {
    await openEditor(tester, seed('06:00'));
    await tapSave(tester);

    expect(find.text('Night shift movement'), findsNothing);
    expect(find.text('Save Movement'), findsNothing);
  });
}
