import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/models/master_data.dart';
import 'package:allowance_shared/models/movement.dart';
import 'package:allowance_shared/services/official_forms_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ClaimData sampleData() {
    final data = ClaimData(
      master: MasterData(
        month: 'JULY, 2026',
        name: 'A Pilot',
        designation: 'Berthing Pilot',
        employee: 'EMP 123',
        pay: '100000',
        bill: 'BILL 1',
      ),
      attShifts: {'2026-07-11': 'N'},
    );
    Movement mv({
      required String allowance,
      String from = 'OFF',
      String to = 'B2',
      String start = '22:30',
      String end = '23:30',
    }) =>
        Movement(
            date: '11/07/26',
            vessel: 'MV TEST',
            from: from,
            to: to,
            start: start,
            end: end,
            loa: '180',
            beam: '32',
            allowance: allowance);
    data.movements
      ..add(mv(allowance: 'length'))
      ..add(mv(allowance: 'cold'))
      ..add(mv(allowance: 'nightact'))
      ..add(mv(allowance: 'navigation', from: 'OFF', to: 'LOCK'))
      ..add(mv(allowance: 'navigation', from: 'LOCK', to: 'OFF'));
    return data;
  }

  test('dump generated form PDFs to disk', () async {
    final dir = Directory(
        r'C:\Users\way2m\AppData\Local\Temp\opencode\gen');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final data = sampleData();
    data.attLocked = true;
    for (var i = 1; i <= 3; i++) {
      data.attShifts['2026-07-$i'] = 'N';
      data.movements.add(Movement(
          date: '1$i/07/26',
          vessel: 'MV ROW $i',
          from: 'OFF',
          to: 'B2',
          start: '22:00',
          end: '23:30',
          loa: '180',
          beam: '32',
          allowance: 'nightact'));
    }
    for (var i = 1; i <= 24; i++) {
      data.movements.add(Movement(
          date: '2$i/07/26',
          vessel: 'MV LEN $i',
          from: 'B2',
          to: 'OFF',
          start: '06:00',
          end: '09:30',
          loa: '180',
          beam: '32',
          allowance: 'length'));
      data.attShifts['2026-07-2$i'] = 'N';
    }
    for (var i = 1; i <= 8; i++) {
      data.movements.add(Movement(
          date: '3$i/07/26',
          vessel: 'MV LOCK $i',
          from: 'LOCK',
          to: 'APP',
          start: '10:15',
          end: '11:45',
          loa: '180',
          beam: '32',
          allowance: 'lock'));
    }
    for (final form in OfficialForm.values) {
      final bytes = await OfficialFormsService.buildFormPdf(form, data);
      final name = switch (form) {
        OfficialForm.lengthAndCold => 'length_cold.pdf',
        OfficialForm.lengthAllowance => 'length_adm.pdf',
        OfficialForm.nightActWeightage => 'night.pdf',
        OfficialForm.lockToApproachJetty => 'lock.pdf',
        OfficialForm.lockToApproachJettyAdmDuty => 'lock_adm_duty.pdf',
        OfficialForm.nightNavigation => 'nav.pdf',
        OfficialForm.nightActWeightageAdmDuty => 'adm_duty_night.pdf',
        OfficialForm.nightNavigationAdmDuty => 'adm_duty_nav.pdf',
      };
      final f = File('${dir.path}\\$name');
      f.writeAsBytesSync(bytes);
      expect(f.lengthSync(), greaterThan(500));
    }

    final adm = ClaimData(
      master: MasterData(
        month: 'JULY, 2026',
        name: 'A Dock Master',
        designation: 'Assistant Dock Master',
        employee: 'EMP 456',
        pay: '83000',
        bill: 'BILL 2',
        basic: '173790',
        ada: '94348',
      ),
      attShifts: {
        '2026-07-11': 'N',
        '2026-07-12': 'N',
        '2026-07-13': 'N',
      },
    );
    adm.attLocked = true;
    adm.movements
      ..add(Movement(
          date: '11/07/26',
          vessel: 'MV OUT 1',
          from: 'LOCK',
          to: 'OFF',
          start: '20:30',
          end: '22:45',
          loa: '229',
          beam: '32.26',
          allowances: ['navigation', 'lock'],
          navigationTypes: ['outward-210']))
      ..add(Movement(
          date: '12/07/26',
          vessel: 'MV IN 1',
          from: '13 OFF',
          to: 'LOCK',
          start: '21:15',
          end: '23:30',
          loa: '250',
          beam: '33.1',
          allowances: ['navigation', 'lock'],
          navigationTypes: ['inward-210']))
      ..add(Movement(
          date: '13/07/26',
          vessel: 'MV LOCK 1',
          from: 'LOCK',
          to: 'APP',
          start: '10:00',
          end: '11:15',
          loa: '180',
          beam: '32',
          allowance: 'lock'))
      ..add(Movement(
          date: '13/07/26',
          vessel: 'MV OUT 2',
          from: 'LOCK',
          to: 'OFF',
          start: '19:10',
          end: '21:00',
          loa: '195',
          beam: '30.1',
          allowances: ['navigation'],
          navigationTypes: ['outward-180-210']))
      ..add(Movement(
          date: '13/07/26',
          vessel: 'MV ADM LEN',
          from: 'B2',
          to: 'OFF',
          start: '06:00',
          end: '09:00',
          loa: '229',
          allowances: ['length']));
    for (final form in [
      OfficialForm.nightActWeightage,
      OfficialForm.nightNavigation,
      OfficialForm.lockToApproachJetty,
      OfficialForm.lengthAllowance,
    ]) {
      final bytes = await OfficialFormsService.buildFormPdf(form, adm);
      final name = switch (form) {
        OfficialForm.nightActWeightage => 'adm_night.pdf',
        OfficialForm.nightNavigation => 'adm_nav_combined.pdf',
        OfficialForm.lengthAllowance => 'adm_length.pdf',
        _ => 'adm_lock.pdf',
      };
      final f = File('${dir.path}\\$name');
      f.writeAsBytesSync(bytes);
      expect(f.lengthSync(), greaterThan(500));
    }

    final dockPilot = ClaimData(
      master: MasterData(
        month: 'JULY, 2026',
        name: 'A Dock Pilot',
        designation: 'Dock Pilot',
        employee: 'EMP 789',
        bill: 'BILL 3',
        basic: '89000',
        ada: '43000',
      ),
    );
    dockPilot.movements.add(Movement(
        date: '11/07/26',
        vessel: 'MV DP 1',
        from: 'OFF',
        to: 'LOCK',
        start: '20:30',
        end: '22:45',
        loa: '180',
        beam: '32',
        allowance: 'navigation'));
    for (final form in [
      OfficialForm.nightNavigation,
      OfficialForm.lengthAndCold,
      OfficialForm.lockToApproachJetty
    ]) {
      final bytes = await OfficialFormsService.buildFormPdf(form, dockPilot);
      final name = switch (form) {
        OfficialForm.nightNavigation => 'dp_nav.pdf',
        OfficialForm.lengthAndCold => 'dp_length_cold.pdf',
        _ => 'dp_lock.pdf',
      };
      final f = File('${dir.path}\\$name');
      f.writeAsBytesSync(bytes);
      expect(f.lengthSync(), greaterThan(500));
    }

    final actingBp = ClaimData(
      master: MasterData(
        month: 'JULY, 2026',
        name: 'A Berthing Pilot',
        designation: 'Berthing Pilot',
        employee: 'EMP 321',
        pay: '100000',
        bill: 'BILL 4',
      ),
      attShifts: {
        '2026-07-11': 'N',
        '2026-07-12': 'N',
        '2026-07-13': 'N',
        '2026-07-14': 'N',
      },
      actingAdmDates: ['2026-07-12', '2026-07-13'],
    );
    actingBp.attLocked = true;
    actingBp.movements
      ..add(Movement(
          date: '12/07/26',
          vessel: 'MV ACT OUT',
          from: 'LOCK',
          to: 'OFF',
          start: '22:30',
          end: '23:45',
          loa: '229',
          beam: '32.26',
          allowances: ['navigation', 'lock'],
          navigationTypes: ['outward-210']))
      ..add(Movement(
          date: '14/07/26',
          vessel: 'MV OWN NAV',
          from: 'LOCK',
          to: 'OFF',
          start: '21:00',
          end: '23:30',
          loa: '195',
          beam: '30.1',
          allowance: 'navigation'))
      ..add(Movement(
          date: '12/07/26',
          vessel: 'MV ACT LEN',
          from: 'B2',
          to: 'OFF',
          start: '06:00',
          end: '09:00',
          loa: '229',
          beam: '32',
          allowance: 'length'))
      ..add(Movement(
          date: '14/07/26',
          vessel: 'MV OWN LEN',
          from: 'B2',
          to: 'OFF',
          start: '06:00',
          end: '09:00',
          loa: '180',
          beam: '32',
          allowance: 'length'));
    for (final form in [
      OfficialForm.nightActWeightage,
      OfficialForm.nightActWeightageAdmDuty,
      OfficialForm.nightNavigation,
      OfficialForm.nightNavigationAdmDuty,
      OfficialForm.lengthAndCold,
      OfficialForm.lengthAllowance,
      OfficialForm.lockToApproachJetty,
      OfficialForm.lockToApproachJettyAdmDuty,
    ]) {
      final bytes = await OfficialFormsService.buildFormPdf(form, actingBp);
      final name = switch (form) {
        OfficialForm.nightActWeightage => 'acting_own_night.pdf',
        OfficialForm.nightActWeightageAdmDuty => 'acting_adm_night.pdf',
        OfficialForm.nightNavigation => 'acting_own_nav.pdf',
        OfficialForm.nightNavigationAdmDuty => 'acting_adm_nav.pdf',
        OfficialForm.lengthAllowance => 'acting_adm_length.pdf',
        OfficialForm.lockToApproachJetty => 'acting_own_lock.pdf',
        OfficialForm.lockToApproachJettyAdmDuty => 'acting_adm_lock.pdf',
        _ => 'acting_own_length_cold.pdf',
      };
      final f = File('${dir.path}\\$name');
      f.writeAsBytesSync(bytes);
      expect(f.lengthSync(), greaterThan(500));
    }
  });
}