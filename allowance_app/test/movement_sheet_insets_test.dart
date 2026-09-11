import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/models/master_data.dart';
import 'package:allowance_app/screens/movement_screen.dart';

void main() {
  testWidgets('movement sheet dodges the keyboard: Save Movement stays '
      'above the inset', (tester) async {
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MovementScreen(
        key: UniqueKey(),
        claimData: ClaimData(master: MasterData(designation: 'BERTHING PILOT')),
        onChanged: () {},
      ),
    ));
    await tester.tap(find.byTooltip('Add Movement'));
    await tester.pumpAndSettle();
    expect(find.text('Add Movement'), findsOneWidget);

    const saveBtn = FilledButton;
    const keyboardLogical = 266.7; // 800 physical / test DPR 3.0
    tester.view.viewInsets = FakeViewPadding(bottom: 800);
    await tester.pumpAndSettle();
    final withKb =
        tester.getRect(find.widgetWithText(saveBtn, 'Save Movement'));
    final inset = MediaQuery.of(
            tester.element(find.text('Add Movement')))
        .viewInsets
        .bottom;
    expect(inset, closeTo(keyboardLogical, 0.1));
    expect(withKb.bottom, lessThanOrEqualTo(600 - keyboardLogical + 0.01));

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    final withoutKb =
        tester.getRect(find.widgetWithText(saveBtn, 'Save Movement'));
    expect(withoutKb.bottom, lessThanOrEqualTo(600.0));
    expect(withKb.top, lessThan(withoutKb.top));
    expect(
      (withoutKb.bottom - withKb.bottom),
      closeTo(keyboardLogical, 0.1),
    );
  });
}