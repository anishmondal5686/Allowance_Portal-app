import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:allowance_app_v2/models/claim_data.dart';
import 'package:allowance_app_v2/models/master_data.dart';
import 'package:allowance_app_v2/models/movement.dart';
import 'package:allowance_app_v2/services/official_forms_service.dart';

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

  group('pdfFileName', () {
    test('uses the correct base name per form', () {
      expect(OfficialFormsService.pdfFileName(
              OfficialForm.lengthAndCold, 'JULY, 2026'),
          'Length_Cold_Allowance_JULY_2026.pdf');
      expect(OfficialFormsService.pdfFileName(
              OfficialForm.nightActWeightage, 'August 2026'),
          'Night_Act_Weightage_August_2026.pdf');
      expect(OfficialFormsService.pdfFileName(
              OfficialForm.lockToApproachJetty, 'SEP 2026'),
          'Lock_to_App_Jetty_SEP_2026.pdf');
      expect(OfficialFormsService.pdfFileName(
              OfficialForm.lockToApproachJettyAdmDuty, 'SEP 2026'),
          'Lock_to_App_Jetty_ADM_Duty_SEP_2026.pdf');
      expect(OfficialFormsService.pdfFileName(
              OfficialForm.nightNavigation, 'OCT, 2026'),
          'Night_Navigation_OCT_2026.pdf');
      expect(OfficialFormsService.pdfFileName(
              OfficialForm.nightActWeightageAdmDuty, 'JULY, 2026'),
          'Night_Weightage_ADM_Duty_JULY_2026.pdf');
      expect(OfficialFormsService.pdfFileName(
              OfficialForm.nightNavigationAdmDuty, 'JULY, 2026'),
          'Night_Navigation_ADM_Duty_JULY_2026.pdf');
    });

    test('falls back to claim when month is blank', () {
      expect(OfficialFormsService.pdfFileName(OfficialForm.lengthAndCold, '  '),
          'Length_Cold_Allowance_claim.pdf');
    });
  });

  group('buildFormPdf', () {
    for (final form in OfficialForm.values) {
      test('${form.name} produces a valid PDF with sample data', () async {
        final bytes = await OfficialFormsService.buildFormPdf(form, sampleData());
        expect(bytes, isA<Uint8List>());
        expect(bytes.length, greaterThan(500));
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      });

      test('${form.name} produces a valid PDF when empty', () async {
        final bytes = await OfficialFormsService.buildFormPdf(
            form, ClaimData(master: MasterData()));
        expect(bytes.length, greaterThan(500));
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      });
    }

    test('pagininates a large length & cold form without errors', () async {
      final data = ClaimData(master: MasterData(month: 'JULY, 2026'));
      for (var i = 0; i < 25; i++) {
        data.movements.add(Movement(
            date: '11/07/26',
            vessel: 'MV $i',
            from: 'OFF',
            to: 'B2',
            start: '22:00',
            end: '23:00',
            loa: '180',
            beam: '32',
            allowance: 'length'));
      }
      final bytes =
          await OfficialFormsService.buildFormPdf(OfficialForm.lengthAndCold, data);
      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('night weightage gaps render in the night act & weightage form',
        () async {
      final data = sampleData();
      data.attLocked = true;
      data.attShifts = {
        for (var d = 1; d <= 3; d++) '2026-07-$d': 'N',
      };
      final bytes = await OfficialFormsService.buildFormPdf(
          OfficialForm.nightActWeightage, data);
      expect(bytes.length, greaterThan(500));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('weightage is skipped when attendance is not locked', () async {
      final data = sampleData();
      data.attShifts = {
        for (var d = 1; d <= 3; d++) '2026-07-$d': 'N',
      };
      final bytes = await OfficialFormsService.buildFormPdf(
          OfficialForm.nightActWeightage, data);
      expect(bytes.length, greaterThan(500));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('night navigation form splits dual-banking movements into rows',
        () async {
      final data = sampleData();
      final bytes = await OfficialFormsService.buildFormPdf(
          OfficialForm.nightNavigation, data);
      expect(bytes.length, greaterThan(500));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('a movement with multiple allowances appears in each form',
        () async {
      final data = sampleData();
      data.movements.clear();
      data.movements.add(Movement(
          date: '11/07/26',
          vessel: 'MV MULTI',
          from: '13 OFF',
          to: 'LOCK',
          start: '22:30',
          end: '01:30',
          loa: '229',
          beam: '32.26',
          allowances: ['length', 'nightact', 'navigation'],
          navigationTypes: ['unbanking', 'outward-210']));
      for (final form in OfficialForm.values) {
        final bytes = await OfficialFormsService.buildFormPdf(form, data);
        expect(bytes.length, greaterThan(500));
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      }
    });
  });

  group('ADM forms', () {
    test('ADM lock form is the original lock form, not the combined form',
        () async {
      final data = sampleData();
      data.master = data.master.copy()..designation = 'Assistant Dock Master';
      data.movements.add(Movement(
          date: '12/07/26',
          vessel: 'MV LOCK',
          from: 'LOCK',
          to: 'APP',
          start: '10:00',
          end: '11:00',
          loa: '180',
          beam: '32',
          allowance: 'lock'));
      final nav = await OfficialFormsService.buildFormPdf(
          OfficialForm.nightNavigation, data);
      final lock = await OfficialFormsService.buildFormPdf(
          OfficialForm.lockToApproachJetty, data);
      final pilotLock = await OfficialFormsService.buildFormPdf(
          OfficialForm.lockToApproachJetty, sampleData());
      expect(nav.length, greaterThan(500));
      expect(lock.length, greaterThan(500));
      expect(String.fromCharCodes(nav.take(5)), '%PDF-');
      expect(String.fromCharCodes(lock.take(5)), '%PDF-');
      expect(lock, isNot(equals(nav)),
          reason: 'ADM lock form must NOT be the combined form');
      expect((lock.length - pilotLock.length).abs() < 2000, isTrue,
          reason: 'ADM lock form must match the pilot lock form size');
    });

    test('combined form renders for an ADM with empty data', () async {
      final data = ClaimData(master: MasterData(designation: 'ADM'));
      final bytes = await OfficialFormsService.buildFormPdf(
          OfficialForm.nightNavigation, data);
      expect(bytes.length, greaterThan(500));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('combined form paginates many movements without errors', () async {
      final data = ClaimData(master: MasterData(
          month: 'JULY, 2026', designation: 'ADM (Assistant Dock Master)'));
      for (var i = 0; i < 15; i++) {
        data.movements.add(Movement(
            date: '11/07/26',
            vessel: 'MV NAV $i',
            from: '13 OFF',
            to: 'LOCK',
            start: '22:00',
            end: '23:00',
            loa: '229',
            beam: '32',
            allowances: ['navigation', 'lock'],
            navigationTypes: ['inward-210']));
      }
      final bytes = await OfficialFormsService.buildFormPdf(
          OfficialForm.nightNavigation, data);
      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('night weightage form renders full 8-hr rows for an ADM night shift',
        () async {
      final data = ClaimData(
        master: MasterData(
            month: 'JULY, 2026',
            designation: 'Assistant Dock Master',
            basic: '173790',
            ada: '94348'),
        attShifts: {'2026-07-11': 'N', '2026-07-12': 'N'},
        attLocked: true,
      );
      data.movements.add(Movement(
          date: '11/07/26',
          vessel: 'MV OUT 1',
          from: 'LOCK',
          to: 'OFF',
          start: '22:30',
          end: '23:45',
          loa: '229',
          beam: '32',
          allowance: 'navigation'));
      final bytes = await OfficialFormsService.buildFormPdf(
          OfficialForm.nightActWeightage, data);
      expect(bytes.length, greaterThan(500));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });

  group('Acting ADM forms', () {
    ClaimData actingData() {
      final data = ClaimData(
        master: MasterData(
            month: 'JULY, 2026',
            designation: 'Dock Pilot',
            basic: '89000',
            ada: '43000'),
        attShifts: {'2026-07-11': 'N', '2026-07-12': 'N', '2026-07-13': 'N'},
        attLocked: true,
        actingAdmDates: ['2026-07-12'],
      );
      data.movements.add(Movement(
          date: '12/07/26',
          vessel: 'MV ADM NAV',
          from: 'LOCK',
          to: 'OFF',
          start: '22:30',
          end: '23:45',
          loa: '229',
          beam: '32',
          allowances: ['navigation'],
          navigationTypes: ['outward-210']));
      return data;
    }

    test('mixed month builds both the own and the ADM-duty weightage form',
        () async {
      final data = actingData();
      final own = await OfficialFormsService.buildFormPdf(
          OfficialForm.nightActWeightage, data);
      final admDuty = await OfficialFormsService.buildFormPdf(
          OfficialForm.nightActWeightageAdmDuty, data);
      expect(String.fromCharCodes(own.take(5)), '%PDF-');
      expect(String.fromCharCodes(admDuty.take(5)), '%PDF-');
      expect(own.length, greaterThan(500));
      expect(admDuty.length, greaterThan(500));
    });

    test('mixed month builds both the own and the ADM-duty navigation form',
        () async {
      final data = actingData();
      final own = await OfficialFormsService.buildFormPdf(
          OfficialForm.nightNavigation, data);
      final admDuty = await OfficialFormsService.buildFormPdf(
          OfficialForm.nightNavigationAdmDuty, data);
      expect(String.fromCharCodes(own.take(5)), '%PDF-');
      expect(String.fromCharCodes(admDuty.take(5)), '%PDF-');
      expect(own.length, greaterThan(500));
      expect(admDuty.length, greaterThan(500));
    });
  });
}
