import 'package:flutter_test/flutter_test.dart';

import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/models/master_data.dart';
import 'package:allowance_shared/models/movement.dart';
import 'package:allowance_shared/services/allowance_calculator.dart';

void main() {
  group('calcNightOverlapMinutes', () {
    test('returns minutes within 22:00-06:00 window', () {
      expect(AllowanceCalculator.calcNightOverlapMinutes('23:00', '01:00'), 120);
      expect(AllowanceCalculator.calcNightOverlapMinutes('06:00', '14:00'), 0);
      expect(AllowanceCalculator.calcNightOverlapMinutes('22:00', '06:00'), 480);
      expect(AllowanceCalculator.calcNightOverlapMinutes('22:30', '23:30'), 60);
      // Ported webapp quirk: a start before 22:00 maps into the next night
      // segment, so the overlap resolves to 0.
      expect(AllowanceCalculator.calcNightOverlapMinutes('21:00', '22:30'), 0);
      expect(AllowanceCalculator.calcNightOverlapMinutes('', '10:00'), 0);
    });
  });

  group('normDateKey', () {
    test('normalises DD/MM/YY and YYYY-MM-DD forms', () {
      expect(AllowanceCalculator.normDateKey('15/08/26'), '2026-8-15');
      expect(AllowanceCalculator.normDateKey('15-08-2026'), '2026-8-15');
      expect(AllowanceCalculator.normDateKey('2026/8/15'), '2026-8-15');
      expect(AllowanceCalculator.normDateKey('2026-8-15'), '2026-8-15');
    });

    test('prevDateKey crosses month boundaries', () {
      expect(AllowanceCalculator.prevDateKey('2026-8-1'), '2026-7-31');
      expect(AllowanceCalculator.prevDateKey('2026-1-1'), '2025-12-31');
    });
  });

  group('amountFor', () {
    final lengthMovement = Movement(loa: '180', beam: '32');

    test('pilot length allowance', () {
      expect(
        AllowanceCalculator.amountFor(
            allowance: 'length', movement: lengthMovement),
        310,
      );
      final short = Movement(loa: '100');
      expect(
        AllowanceCalculator.amountFor(
            allowance: 'length', movement: short),
        0,
      );
    });

    test('nightact depends on loa', () {
      final big = Movement(loa: '180');
      final small = Movement(loa: '120');
      expect(
        AllowanceCalculator.amountFor(
            allowance: 'nightact', movement: big),
        205,
      );
      expect(
        AllowanceCalculator.amountFor(
            allowance: 'nightact', movement: small),
        135,
      );
    });

    test('lock rate', () {
      final m = Movement();
      expect(
        AllowanceCalculator.amountFor(allowance: 'lock', movement: m),
        1000,
      );
    });

    test('navigation rates', () {
      expect(
        AllowanceCalculator.amountFor(
            allowance: 'navigation',
            movement: Movement(
                loa: '200', navigationType: 'outward-180-210')),
        540,
      );
      expect(
        AllowanceCalculator.amountFor(
            allowance: 'navigation',
            movement: Movement(loa: '220', navigationType: 'outward-210')),
        810,
      );
      expect(
        AllowanceCalculator.amountFor(
            allowance: 'navigation',
            movement: Movement(loa: '100', navigationType: 'outward-210')),
        0,
      );
    });

    test('adm rates apply when adm is true', () {
      expect(
        AllowanceCalculator.amountFor(
            allowance: 'lock', movement: Movement(), adm: true),
        1500,
      );
      expect(
        AllowanceCalculator.amountFor(
            allowance: 'navigation',
            movement: Movement(loa: '200', navigationType: 'outward-180-210'),
            adm: true),
        675,
      );
      expect(
        AllowanceCalculator.amountFor(
            allowance: 'navigation',
            movement: Movement(loa: '220', navigationType: 'outward-210'),
            adm: true),
        1010,
      );
      expect(
        AllowanceCalculator.amountFor(
            allowance: 'navigation',
            movement: Movement(loa: '220', navigationType: 'inward-210'),
            adm: true),
        540,
      );
      expect(
        AllowanceCalculator.amountFor(
            allowance: 'navigation',
            movement: Movement(beam: '32', navigationType: 'outward-beam'),
            adm: true),
        675,
      );
      expect(
        AllowanceCalculator.amountFor(
            allowance: 'navigation',
            movement: Movement(beam: '32', navigationType: 'outward-beam')),
        540,
      );
    });

    test('adm gets length but no cold or nightact', () {
      expect(
        AllowanceCalculator.amountFor(
            allowance: 'length', movement: Movement(loa: '200'), adm: true),
        310,
      );
      expect(
        AllowanceCalculator.amountFor(
            allowance: 'length', movement: Movement(loa: '100'), adm: true),
        0,
      );
      expect(
        AllowanceCalculator.amountFor(
            allowance: 'cold', movement: Movement(), adm: true),
        0,
      );
      expect(
        AllowanceCalculator.amountFor(
            allowance: 'nightact', movement: Movement(loa: '200'), adm: true),
        0,
      );
    });
  });

  group('calcNightWeightageMinutes', () {
    test('a full unattended night shift yields a full night', () {
      // N shift on 2026-8-10 with a nightact movement at 22:00-23:00
      // counts active minutes of 60, so weightage = 480 - 60.
      final movements = [
        Movement(
            date: '10/08/26',
            start: '22:00',
            end: '23:00',
            allowance: 'nightact'),
      ];
      final attShifts = {
        '2026-8-10': 'N',
        '2026-8-11': 'N',
      };
      expect(
        AllowanceCalculator.calcNightWeightageMinutes(
            movements: movements, attShifts: attShifts),
        480 - 60 + 480,
      );
    });

    test('nightact movement after midnight maps to previous night', () {
      final movements = [
        Movement(
            date: '11/08/26',
            start: '01:00',
            end: '02:00',
            allowance: 'nightact'),
      ];
      final attShifts = {'2026-8-11': 'N'};
      // 01:00 belongs to the 10th night; no N shift stored for the 10th,
      // so only the weightage from movement active minutes applies.
      final result = AllowanceCalculator.calcNightWeightageMinutes(
          movements: movements, attShifts: attShifts);
      expect(result, greaterThan(0));
    });

    test('lock to approach jetty time is not counted as inactive', () {
      final movements = [
        Movement(
            date: '10/08/26',
            start: '22:00',
            end: '02:00',
            allowance: 'lock'),
      ];
      final attShifts = {'2026-8-10': 'N'};
      // 4 hours of lock movement overlap the night (240 min active),
      // so weightage = 480 - 240 = 240.
      expect(
        AllowanceCalculator.calcNightWeightageMinutes(
            movements: movements, attShifts: attShifts),
        240,
      );
    });

    test('no weightage for dates whose shift is not night', () {
      final movements = [
        Movement(
            date: '10/08/26',
            start: '22:00',
            end: '23:00',
            allowance: 'nightact'),
        Movement(
            date: '11/08/26',
            start: '22:00',
            end: '23:00',
            allowance: 'nightact'),
      ];
      // 10th is a night shift, 11th is an evening shift.
      final attShifts = {'2026-8-10': 'N', '2026-8-11': 'E'};
      expect(
        AllowanceCalculator.calcNightWeightageMinutes(
            movements: movements, attShifts: attShifts),
        480 - 60,
      );
      expect(
        AllowanceCalculator.hasWeightage(
            movements: movements, attShifts: attShifts),
        isTrue,
      );
    });

    test('no weightage when no night shifts exist', () {
      final movements = [
        Movement(
            date: '10/08/26',
            start: '22:00',
            end: '23:00',
            allowance: 'nightact'),
      ];
      final attShifts = {'2026-8-10': 'E'};
      expect(
        AllowanceCalculator.calcNightWeightageMinutes(
            movements: movements, attShifts: attShifts),
        0,
      );
      expect(
        AllowanceCalculator.hasWeightage(
            movements: movements, attShifts: attShifts),
        isFalse,
      );
    });

    test('adm fullNights counts the full 8 hrs per night shift', () {
      final movements = [
        Movement(
            date: '10/08/26',
            start: '22:00',
            end: '02:00',
            allowance: 'lock'),
        Movement(
            date: '11/08/26',
            start: '22:30',
            end: '01:30',
            allowance: 'nightact'),
      ];
      final attShifts = {'2026-8-10': 'N', '2026-8-11': 'N'};
      // ADM rule: active movement time is still claimed as a separate
      // allowance, so every night shift earns the full 480 minutes.
      expect(
        AllowanceCalculator.calcNightWeightageMinutes(
            movements: movements,
            attShifts: attShifts,
            fullNights: true),
        2 * 480,
      );
      expect(
        AllowanceCalculator.calcNightWeightageMinutes(
            movements: movements, attShifts: attShifts),
        480 - 240 + (480 - 180),
      );
    });

    test('acting ADM dates count full 8 hrs, other nights gap-based', () {
      final attShifts = {'2026-8-10': 'N', '2026-8-11': 'N'};
      final movements = [
        Movement(
            date: '10/08/26',
            start: '23:00',
            end: '01:00',
            loa: '180',
            allowance: 'nightact'),
      ];
      // 10th (acting): full 480; 11th: 480 - 0 = 480.
      expect(
        AllowanceCalculator.calcNightWeightageMinutes(
            movements: movements,
            attShifts: attShifts,
            actingAdmDates: {'2026-8-10'}),
        2 * 480,
      );
      // 10th: 480 - 120 overlap = 360; 11th (acting): full 480.
      expect(
        AllowanceCalculator.calcNightWeightageMinutes(
            movements: movements,
            attShifts: attShifts,
            actingAdmDates: {'2026-8-11'}),
        480 - 120 + 480,
      );
      // Acting dates only ever apply to nights that are N.
      expect(
        AllowanceCalculator.calcNightWeightageMinutes(
            movements: movements,
            attShifts: attShifts,
            actingAdmDates: {'2026-8-20'}),
        480 - 120 + 480,
      );
    });
  });

  group('autoDetect', () {
    test('LOCK to approach jetty movement forces lock only', () {
      final result = AllowanceCalculator.autoDetect(
          movement: Movement(from: 'LOCK', to: 'APPROACH JETTY', loa: '200'));
      expect(result.allowance, 'lock');
      expect(result.applicable, ['lock']);
    });

    test('approach jetty to LOCK movement forces lock only', () {
      final result = AllowanceCalculator.autoDetect(
          movement: Movement(from: 'APP. JETTY', to: 'LOCK', loa: '200'));
      expect(result.allowance, 'lock');
      expect(result.applicable, ['lock']);
    });

    test('long vessel daylight movement detects length', () {
      final result = AllowanceCalculator.autoDetect(
          movement: Movement(
              date: '10/08/26',
              from: 'HDC',
              to: 'HDC',
              start: '09:00',
              end: '12:00',
              loa: '190',
              beam: '30'));
      expect(result.allowance, 'length');
      expect(result.applicable, contains('length'));
      expect(result.applicable, isNot(contains('nightact')));
    });

    test('night movement detects nightact', () {
      final result = AllowanceCalculator.autoDetect(
          movement: Movement(
              date: '10/08/26',
              start: '23:00',
              end: '01:00',
              loa: '100'));
      expect(result.allowance, 'nightact');
    });

    test('night OFF to LOCK movement detects length, nightact and both nav '
        'types', () {
      final result = AllowanceCalculator.autoDetect(
          movement: Movement(
              date: '10/08/26',
              from: '13 OFF',
              to: 'LOCK',
              start: '22:30',
              end: '01:30',
              loa: '229',
              beam: '32.26'));
      expect(result.applicable, contains('length'));
      expect(result.applicable, contains('nightact'));
      expect(result.applicable, isNot(contains('lock')));
      expect(result.applicable, contains('navigation'));
      expect(result.navTypes, contains('unbanking'));
      expect(result.navTypes, contains('outward-210'));
    });

    test('LOCK to non-jetty movement does not detect lock', () {
      final result = AllowanceCalculator.autoDetect(
          movement: Movement(
              date: '10/08/26',
              from: 'LOCK',
              to: 'HDC',
              start: '09:00',
              end: '12:00',
              loa: '100',
              beam: '20'));
      expect(result.applicable, isNot(contains('lock')));
      expect(result.applicable, isNot(contains('cold')));
      expect(result.applicable, isNot(contains('navigation')));
    });
  });

  group('computeSummary', () {
    test('sums allowances and weightage', () {
      final data = ClaimData(
        master: MasterData(pay: '100000', designation: 'Berthing Pilot'),
      );
      data.attLocked = true;
      data.movements.add(Movement(
          date: '10/08/26',
          start: '23:00',
          end: '01:00',
          loa: '180',
          allowance: 'nightact'));
      final summary = AllowanceCalculator.computeSummary(data);
      expect(summary.lines.any((l) => l.key == 'nightact'), isTrue);
      expect(summary.grandTotal, greaterThan(0));
      expect(summary.payWarning, isFalse);
    });

    test('warns when weightage applies without pay', () {
      final data = ClaimData(
        master: MasterData(pay: '', designation: 'Berthing Pilot'),
      );
      data.attLocked = true;
      data.attShifts['2026-8-10'] = 'N';
      final summary = AllowanceCalculator.computeSummary(data);
      expect(summary.payWarning, isTrue);
    });

    test('night weightage always shows based on confirmed shifts regardless of lock', () {
      final data = ClaimData(
        master: MasterData(
          pay: '100000',
          designation: 'BERTHING PILOT',
          month: 'AUGUST, 2026',
        ),
      );
      data.attShifts['2026-8-10'] = 'N';
      data.movements.add(Movement(
          date: '10/08/26',
          start: '23:00',
          end: '01:00',
          loa: '180',
          allowance: 'nightact'));
      final summary = AllowanceCalculator.computeSummary(data);
      expect(summary.lines.any((l) => l.key == 'weightage'), isTrue);
      expect(summary.nightWeightageHours, greaterThan(0));
    });

    test('ADM night weightage is credited as hours, not an amount', () {
      final data = ClaimData(
        master: MasterData(
            designation: 'Assistant Dock Master',
            basic: '173790',
            ada: '94348'),
      );
      data.attLocked = true;
      data.attShifts = {
        '2026-8-5': 'N',
        '2026-8-6': 'N',
        '2026-8-7': 'N',
      };
      data.movements.add(Movement(
          date: '10/08/26',
          start: '23:00',
          end: '01:00',
          loa: '180',
          allowance: 'nightact'));
      final summary = AllowanceCalculator.computeSummary(data);
      expect(summary.lines.any((l) => l.key == 'weightage'), isFalse);
      expect(summary.nightWeightageHours, closeTo(24, 0.001));
      expect(summary.grandTotal,
          summary.lines.fold<double>(0, (s, l) => s + l.amount));
      expect(summary.payWarning, isFalse);
    });

    test('Dock Pilot night weightage is credited as hours, not an amount', () {
      final data = ClaimData(
        master: MasterData(designation: 'Dock Pilot',
            basic: '89000',
            ada: '43000'),
      );
      data.attLocked = true;
      data.attShifts = {'2026-8-10': 'N', '2026-8-11': 'N'};
      data.movements.add(Movement(
          date: '10/08/26',
          start: '23:00',
          end: '01:00',
          loa: '180',
          allowance: 'nightact'));
      final summary = AllowanceCalculator.computeSummary(data);
      expect(summary.lines.any((l) => l.key == 'weightage'), isFalse);
      // 10th: 480 - 120 movement overlap = 360; 11th: 480. Total 840 min.
      expect(summary.nightWeightageHours, closeTo(14, 0.001));
      expect(summary.grandTotal,
          summary.lines.fold<double>(0, (s, l) => s + l.amount));
      expect(summary.payWarning, isFalse);
    });

    test('Berthing Pilot keeps the amount and also reports hours', () {
      final data = ClaimData(
        master: MasterData(pay: '100000', designation: 'Berthing Pilot'),
      );
      data.attLocked = true;
      data.attShifts = {'2026-8-10': 'N'};
      data.movements.add(Movement(
          date: '10/08/26',
          start: '23:00',
          end: '01:00',
          loa: '180',
          allowance: 'nightact'));
      final summary = AllowanceCalculator.computeSummary(data);
      final weightLine = summary.lines.firstWhere((l) => l.key == 'weightage');
      expect(weightLine.amount, greaterThan(0));
      expect(summary.hasWeightageAmount, isTrue);
      // 480 - 120 overlap = 360 min = 6 hrs.
      expect(summary.nightWeightageHours, closeTo(6, 0.001));
      expect(summary.payWarning, isFalse);
    });

    test('Berthing Pilot acting as ADM gets ADM rates and full-8h weightage '
        'on acting dates', () {
      final data = ClaimData(
        master: MasterData(pay: '100000', designation: 'Berthing Pilot'),
      );
      data.attLocked = true;
      data.attShifts = {'2026-8-10': 'N', '2026-8-11': 'N'};
      data.actingAdmDates.add('2026-8-11');
      // Acting-date movement: lock billed at the ADM rate (1500).
      data.movements.add(Movement(
          date: '11/08/26',
          from: 'LOCK',
          to: 'APP JETTY',
          start: '10:00',
          end: '12:00',
          loa: '229',
          allowance: 'lock'));
      // Acting-date nightact is dropped (ADM gets no night act).
      data.movements.add(Movement(
          date: '11/08/26',
          start: '23:00',
          end: '01:00',
          loa: '180',
          allowance: 'nightact'));
      // Acting-date length counts at the ADM rate (310) — confirmed rule.
      data.movements.add(Movement(
          date: '11/08/26',
          from: 'B2',
          to: 'OFF',
          start: '06:00',
          end: '09:00',
          loa: '229',
          allowance: 'length'));
      final summary = AllowanceCalculator.computeSummary(data);
      final lockLine = summary.lines.firstWhere((l) => l.key == 'lock');
      expect(lockLine.amount, 1500);
      expect(summary.lines.any((l) => l.key == 'nightact'), isFalse);
      final lengthLine = summary.lines.firstWhere((l) => l.key == 'length');
      expect(lengthLine.amount, 310);
      // 10th: 480 (no movements); 11th acting: full 480 → 960 min = 16 hrs.
      expect(summary.nightWeightageHours, closeTo(16, 0.001));
      final weightLine = summary.lines.firstWhere((l) => l.key == 'weightage');
      expect(weightLine.amount, closeTo((960 / 60 / 1440) * 100000, 1));
      expect(summary.payWarning, isFalse);
    });

    test('post-midnight movement during an acting-ADM night shift is billed '
        'at the ADM rate (shift-date attribution)', () {
      final data = ClaimData(
        master: MasterData(pay: '100000', designation: 'Berthing Pilot'),
      );
      data.attLocked = true;
      data.attShifts = {'2026-8-11': 'N'};
      data.actingAdmDates.add('2026-8-11');
      // Movement at 02:45 on calendar 12/08 belongs to the 11/08 night shift
      // (22:00 11/08 -> 06:00 12/08) → billed at the ADM lock rate.
      data.movements.add(Movement(
          date: '12/08/26',
          from: 'LOCK',
          to: 'APP JETTY',
          start: '02:45',
          end: '03:10',
          loa: '229',
          allowance: 'lock'));
      final summary = AllowanceCalculator.computeSummary(data);
      final lockLine = summary.lines.firstWhere((l) => l.key == 'lock');
      expect(lockLine.amount, 1500);
      // 11/08 night is acting-ADM → full 8h weightage.
      expect(summary.nightWeightageHours, closeTo(8, 0.001));
    });

    test('Dock Pilot acting as ADM keeps hours-only weightage with full-8h '
        'acting nights', () {
      final data = ClaimData(
        master: MasterData(
            designation: 'Dock Pilot', basic: '89000', ada: '43000'),
      );
      data.attLocked = true;
      data.attShifts = {'2026-8-10': 'N', '2026-8-11': 'N'};
      data.actingAdmDates.add('2026-8-11');
      data.movements.add(Movement(
          date: '10/08/26',
          start: '23:00',
          end: '01:00',
          loa: '180',
          allowance: 'nightact'));
      final summary = AllowanceCalculator.computeSummary(data);
      expect(summary.lines.any((l) => l.key == 'weightage'), isFalse);
      // 10th: 480 - 120 = 360; 11th acting: 480 → 840 min = 14 hrs.
      expect(summary.nightWeightageHours, closeTo(14, 0.001));
      expect(summary.grandTotal,
          summary.lines.fold<double>(0, (s, l) => s + l.amount));
      expect(summary.payWarning, isFalse);
    });

    test('a movement with multiple allowances counts each one', () {
      final data = ClaimData(
          master: MasterData(pay: '100000', designation: 'Berthing Pilot'));
      data.attLocked = true;
      data.attShifts['2026-8-10'] = 'N';
      data.movements.add(Movement(
          date: '10/08/26',
          from: '13 OFF',
          to: 'LOCK',
          start: '22:30',
          end: '01:30',
          loa: '229',
          beam: '32.26',
          allowances: ['length', 'nightact', 'navigation'],
          navigationTypes: ['unbanking', 'outward-210']));
      final summary = AllowanceCalculator.computeSummary(data);
      final lengthLine = summary.lines.firstWhere((l) => l.key == 'length');
      final nightLine = summary.lines.firstWhere((l) => l.key == 'nightact');
      final navLine = summary.lines.firstWhere((l) => l.key == 'navigation');
      expect(lengthLine.amount, 310);
      expect(nightLine.amount, 205);
      expect(navLine.amount, 540 + 810);
      expect(
        summary.grandTotal,
        310 + 205 + 540 + 810 + summary.lines
            .firstWhere((l) => l.key == 'weightage')
            .amount,
      );
    });

    test('ADM night navigation without explicit type still appears in summary', () {
      // Regression: a nav movement saved with only 'navigation' and no
      // navigationTypes (direction implied by from/to) was absent from the
      // claim summary even though the night-navigation form listed it.
      final data = ClaimData(
        master: MasterData(
          month: 'SEPTEMBER, 2026',
          basic: '83000',
          ada: '46000',
          designation: 'Assistant Dock Master',
        ),
      );
      data.attLocked = true;
      data.movements.add(Movement(
          date: '15/09/26',
          from: '13 OFF',
          to: 'LOCK', // outward
          start: '21:00',
          end: '23:00',
          loa: '220', // >= 210 -> outward-210, ADM 1010
          allowances: ['navigation'])); // no navigationTypes
      final summary = AllowanceCalculator.computeSummary(data);
      final navLine = summary.lines.firstWhere((l) => l.key == 'navigation');
      expect(navLine.amount, 1010);
    });
  });

  group('month filtering', () {
    Movement mv(String date, {String allowance = 'length'}) => Movement(
        date: date,
        from: 'OFF',
        to: 'B2',
        start: '10:00',
        end: '12:00',
        loa: '180',
        allowance: allowance);

    test('movementsForMonth keeps only movements within the master month', () {
      final data = ClaimData(master: MasterData(month: 'SEPTEMBER, 2026'));
      data.movements
        ..add(mv('15/09/26'))
        ..add(mv('16/09/26'))
        ..add(mv('11/07/26'))
        ..add(mv('02/10/26'))
        ..add(mv(''));
      final filtered = AllowanceCalculator.movementsForMonth(data);
      expect(filtered.map((m) => m.date), ['15/09/26', '16/09/26']);
    });

    test('movementsForMonth returns everything when month is blank', () {
      final data = ClaimData(master: MasterData(month: ''));
      data.movements
        ..add(mv('15/09/26'))
        ..add(mv('11/07/26'));
      expect(AllowanceCalculator.movementsForMonth(data).length, 2);
    });

    test('movementsForMonth sorts same-date movements by start time', () {
      Movement timed(String date, String start, String vessel) => Movement(
          date: date,
          vessel: vessel,
          from: 'OFF',
          to: 'B2',
          start: start,
          end: '12:00',
          loa: '180',
          allowance: 'length');
      final data = ClaimData(master: MasterData(month: 'SEPTEMBER, 2026'));
      data.movements
        ..add(timed('15/09/26', '19:00', 'LATE'))
        ..add(timed('17/09/26', '06:00', 'NEWEST-DAY'))
        ..add(timed('15/09/26', '01:30', 'AFTER-MIDNIGHT'))
        ..add(timed('15/09/26', '10:00', 'MID'))
        ..add(timed('16/09/26', '08:00', 'NEXT-DAY'));
      final sorted = AllowanceCalculator.movementsForMonth(data);
      expect(sorted.map((m) => m.vessel),
          ['AFTER-MIDNIGHT', 'MID', 'LATE', 'NEXT-DAY', 'NEWEST-DAY']);
    });

    test('attShiftsForMonth keeps only shifts within the master month', () {
      final data = ClaimData(master: MasterData(month: 'SEPTEMBER, 2026'));
      data.attShifts = {
        '2026-9-15': 'N',
        '2026-9-16': 'E',
        '2026-7-11': 'N',
        '2026-10-2': 'M',
        'junk': 'N',
      };
      final filtered = AllowanceCalculator.attShiftsForMonth(data);
      expect(filtered.keys, ['2026-9-15', '2026-9-16']);
    });

    test('computeSummary ignores movements outside the master month', () {
      final data = ClaimData(master: MasterData(month: 'SEPTEMBER, 2026'));
      data.movements
        ..add(mv('15/09/26', allowance: 'cold'))
        ..add(mv('11/07/26', allowance: 'cold'));
      final summary = AllowanceCalculator.computeSummary(data);
      final coldLine = summary.lines.firstWhere((l) => l.key == 'cold');
      expect(coldLine.amount, 160);
    });

    test('night weightage is excluded for future month shifts', () {
      final futureMonth = DateTime.now().add(const Duration(days: 45));
      final futureKey = '${futureMonth.year}-${futureMonth.month}-15';
      final minutes = AllowanceCalculator.calcNightWeightageMinutes(
        movements: [],
        attShifts: {futureKey: 'N'},
        fullNights: true,
      );
      expect(minutes, 0);
    });

    test('movementShiftDate correctly attributes post-midnight movements (<06:00 AM) to previous shift date', () {
      final mPostMidnight = Movement(date: '24/08/2026', start: '01:30', end: '03:00');
      expect(AllowanceCalculator.movementShiftDate(mPostMidnight), '2026-8-23');

      final mNightStart = Movement(date: '23/08/2026', start: '22:30', end: '23:45');
      expect(AllowanceCalculator.movementShiftDate(mNightStart), '2026-8-23');

      final mDayShift = Movement(date: '24/08/2026', start: '09:00', end: '11:00');
      expect(AllowanceCalculator.movementShiftDate(mDayShift), '2026-8-24');
    });

    test('movementShiftDate respects user attendance when movement starts 05:30-05:59 AM', () {
      final mEarlyMorning = Movement(date: '24/08/2026', start: '05:45', end: '08:00');
      expect(AllowanceCalculator.movementShiftDate(mEarlyMorning, attShifts: {'2026-8-24': 'M'}), '2026-8-24');
      expect(AllowanceCalculator.movementShiftDate(mEarlyMorning), '2026-8-23');
    });

    test('movementShiftDate attributes 05:45 AM movement to previous night shift if previous day was N', () {
      final mEarlyMorning = Movement(date: '23/08/2026', start: '05:45', end: '08:00');
      expect(AllowanceCalculator.movementShiftDate(mEarlyMorning, attShifts: {'2026-8-22': 'N', '2026-8-23': 'M'}), '2026-8-22');
      expect(AllowanceCalculator.movementShiftDate(mEarlyMorning, attShifts: {'2026-8-22': 'OFF', '2026-8-23': 'M'}), '2026-8-23');
    });
  });

  group('calcSheet', () {
    Movement nav(String date, String type, {String loa = '220', String beam = '32'}) =>
        Movement(
            date: date,
            vessel: 'V',
            from: 'LOCK',
            to: 'LOCK',
            start: '21:00',
            end: '23:00',
            loa: loa,
            beam: beam,
            allowances: ['navigation'],
            navigationTypes: [type]);

    Movement length(String date, {String loa = '180'}) => Movement(
        date: date,
        vessel: 'V',
        from: 'OFF',
        to: 'B1',
        start: '09:00',
        end: '11:00',
        loa: loa,
        allowances: ['length']);

    CalcSheetRow rowOf(List<CalcSheetRow> rows, String category) =>
        rows.firstWhere((r) => r.category == category);

    test('ADM sheet uses ADM rates and omits cold/nightact rows', () {
      final data = ClaimData(master: MasterData(
          month: 'SEPTEMBER, 2026',
          designation: 'Assistant Dock Master'));
      data.attLocked = true;
      data.movements
        ..add(nav('15/09/26', 'outward-210'))
        ..add(length('16/09/26'));
      final sheet = AllowanceCalculator.calcSheet(data);
      expect(sheet.isAdm, true);
      expect(sheet.hasActing, false);
      final cats = sheet.baseRows.map((r) => r.category).toList();
      expect(cats.any((c) => c.contains('Night act')), false);
      expect(cats.any((c) => c.contains('Cold')), false);
      expect(rowOf(sheet.baseRows, 'Night navigation (Outward L>210 m)').amount, 1010);
      expect(rowOf(sheet.baseRows, 'Night navigation (Outward L>210 m)').count, 1);
      expect(rowOf(sheet.baseRows, 'Length (LOA>175.26m)').amount, 310);
      expect(rowOf(sheet.baseRows, 'Lock to App. Jetty & vice versa').rateChart, '1500');
    });

    test('length row only counts movements with LOA >= 175.26', () {
      final data = ClaimData(master: MasterData(
          month: 'SEPTEMBER, 2026',
          designation: 'Berthing Pilot'));
      data.movements
        ..add(length('15/09/26', loa: '180'))
        ..add(length('16/09/26', loa: '150'));
      final sheet = AllowanceCalculator.calcSheet(data);
      final lengthRow = rowOf(sheet.baseRows, 'Length (LOA>175.26m)');
      expect(lengthRow.count, 1);
      expect(lengthRow.amount, 310);
    });

    test('BP has weightage amount, DP and ADM weightage amount is zero', () {
      final bp = ClaimData(master: MasterData(
          month: 'SEPTEMBER, 2026', designation: 'Berthing Pilot', pay: '83000'));
      bp.attLocked = true;
      bp.attShifts = {'2026-9-15': 'N'};
      bp.movements.add(length('15/09/26'));
      expect(AllowanceCalculator.calcSheet(bp).weightageAmount, greaterThan(0));

      final dp = ClaimData(master: MasterData(
          month: 'SEPTEMBER, 2026', designation: 'Dock Pilot'));
      dp.attLocked = true;
      dp.attShifts = {'2026-9-15': 'N'};
      dp.movements.add(length('15/09/26'));
      expect(AllowanceCalculator.calcSheet(dp).weightageAmount, 0);

      final adm = ClaimData(master: MasterData(
          month: 'SEPTEMBER, 2026', designation: 'Assistant Dock Master'));
      adm.attLocked = true;
      adm.attShifts = {'2026-9-15': 'N'};
      adm.movements.add(length('15/09/26'));
      expect(AllowanceCalculator.calcSheet(adm).weightageAmount, 0);
    });

    test('BP/DP acting-ADM splits movements into a separate acting table', () {
      final data = ClaimData(master: MasterData(
          month: 'SEPTEMBER, 2026',
          designation: 'Dock Pilot'));
      data.attLocked = true;
      data.actingAdmDates = ['2026-9-15'];
      data.movements
        ..add(nav('15/09/26', 'outward-210')) // acting (ADM rate 1010)
        ..add(nav('16/09/26', 'outward-210')); // own (DP rate 810)
      final sheet = AllowanceCalculator.calcSheet(data);
      expect(sheet.hasActing, true);
      final actingNav = rowOf(sheet.actingRows, 'Night navigation (Outward L>210 m)');
      expect(actingNav.count, 1);
      expect(actingNav.amount, 1010);
      final baseNav = rowOf(sheet.baseRows, 'Night navigation (Outward L>210 m)');
      expect(baseNav.count, 1);
      expect(baseNav.amount, 810);
    });

    test('acting-ADM DP shows night weightage hours only (no amount)', () {
      final data = ClaimData(
        master: MasterData(basic: '50000', ada: '15000',
            designation: 'Dock Pilot'),
      );
      data.attLocked = true;
      data.attShifts = {'2026-8-10': 'N', '2026-8-11': 'N'};
      data.actingAdmDates.add('2026-8-11');
      data.movements
        ..add(Movement(
            date: '10/08/26',
            from: 'LOCK',
            to: 'LOCK',
            start: '21:00',
            end: '23:00',
            loa: '180',
            allowance: 'length')) // own night
        ..add(Movement(
            date: '11/08/26',
            from: 'LOCK',
            to: 'LOCK',
            start: '21:00',
            end: '23:00',
            loa: '180',
            allowance: 'length')); // acting night
      final sheet = AllowanceCalculator.calcSheet(data);
      expect(sheet.hasActing, true);
      expect(sheet.weightageAmount, 0);
      expect(sheet.baseWeightageAmount, 0);
      expect(sheet.actingWeightageAmount, 0);
      final baseW = rowOf(sheet.baseRows, 'Night weightage (HRS)');
      final actingW = rowOf(sheet.actingRows, 'Night weightage (HRS)');
      expect(baseW.amount, 0);
      expect(actingW.amount, 0);
      expect(baseW.hours, greaterThan(0));
      expect(actingW.hours, greaterThan(0));
    });

    test('acting-ADM BP weightage amount is split across both tables', () {
      final data = ClaimData(
        master: MasterData(pay: '100000', designation: 'Berthing Pilot'),
      );
      data.attLocked = true;
      data.attShifts = {'2026-8-10': 'N', '2026-8-11': 'N'};
      data.actingAdmDates.add('2026-8-11');
      data.movements
        ..add(Movement(
            date: '10/08/26',
            from: 'LOCK',
            to: 'LOCK',
            start: '21:00',
            end: '23:00',
            loa: '180',
            allowance: 'length')) // own night
        ..add(Movement(
            date: '11/08/26',
            from: 'LOCK',
            to: 'LOCK',
            start: '21:00',
            end: '23:00',
            loa: '180',
            allowance: 'length')); // acting night
      final sheet = AllowanceCalculator.calcSheet(data);
      expect(sheet.hasActing, true);
      expect(sheet.weightageAmount, greaterThan(0));
      expect(sheet.actingWeightageAmount, greaterThan(0));
      final baseW = rowOf(sheet.baseRows, 'Night weightage (HRS)');
      final actingW = rowOf(sheet.actingRows, 'Night weightage (HRS)');
      // Acting table carries the acting-nights amount; base carries the rest.
      expect(actingW.amount, sheet.actingWeightageAmount);
      expect(baseW.amount, closeTo(sheet.baseWeightageAmount, 0.001));
      expect(sheet.actingWeightageAmount + sheet.baseWeightageAmount,
          closeTo(sheet.weightageAmount, 0.001));
      expect(actingW.hours, sheet.actingWeightageHours);
      expect(baseW.hours, sheet.baseWeightageHours);
      expect(baseW.hours, greaterThan(0));
      expect(actingW.hours, greaterThan(0));
    });

    test('ADM night navigation without explicit type still counts in calc sheet', () {
      // Regression: a nav movement saved with only 'navigation' and no
      // navigationTypes (from/to imply the direction) was omitted from the
      // calc-sheet printout even though the night-navigation form showed it.
      final data = ClaimData(master: MasterData(
          month: 'SEPTEMBER, 2026',
          designation: 'Assistant Dock Master'));
      data.attLocked = true;
      data.movements.add(Movement(
          date: '15/09/26',
          vessel: 'V',
          from: 'LOCK',
          to: 'OFF', // inward
          start: '21:00',
          end: '23:00',
          loa: '220', // >= 210 -> inward-210, 540
          allowances: ['navigation'])); // no navigationTypes
      final sheet = AllowanceCalculator.calcSheet(data);
      expect(rowOf(sheet.baseRows, 'Night navigation (Inward L>210 m)').count, 1);
      expect(rowOf(sheet.baseRows, 'Night navigation (Inward L>210 m)').amount, 540);
      expect(rowOf(sheet.baseRows, 'Night navigation (Inward L>210 m)').rateChart, '540');
    });

    test('acting-ADM nav without explicit type counts at ADM rate in calc sheet', () {
      // A DP/BP doing acting ADM uses the same ADM direction convention
      // (basin->lock = outward) and ADM rates even when no nav type was saved.
      final data = ClaimData(master: MasterData(
          month: 'SEPTEMBER, 2026',
          designation: 'Dock Pilot'));
      data.attLocked = true;
      data.actingAdmDates = ['2026-9-15'];
      data.movements.add(Movement(
          date: '15/09/26',
          vessel: 'V',
          from: 'BASIN',
          to: 'LOCK', // outward, ADM rate
          start: '21:00',
          end: '23:00',
          loa: '220', // >= 210 -> outward-210, ADM 1010
          allowances: ['navigation'])); // no navigationTypes
      final sheet = AllowanceCalculator.calcSheet(data);
      expect(sheet.hasActing, true);
      expect(rowOf(sheet.actingRows, 'Night navigation (Outward L>210 m)').count, 1);
      expect(rowOf(sheet.actingRows, 'Night navigation (Outward L>210 m)').amount, 1010);
      expect(
          rowOf(sheet.baseRows, 'Night navigation (Outward L>210 m)').count, 0);
    });
  });

  group('roster', () {
    test('rotation carries across the month boundary', () {
      // Off day Tuesday, first September working block is M. The trailing
      // Aug 31 (Monday, the day before the Sep 1 off) must keep its prior
      // shift (E) rather than resetting to the new month's week zero.
      String pred(int m, int d) => AllowanceCalculator.predictRosterShift(
          dt: DateTime(2026, m, d),
          offDay: '2',
          rotation: 'M',
          claimYear: 2026,
          claimMonth: 9);
      expect(pred(8, 31), 'E');
      expect(pred(9, 1), 'OFF');
      for (var d = 2; d <= 7; d++) {
        expect(pred(9, d), 'M');
      }
      expect(pred(9, 8), 'OFF');
    });

    test('fillRoster reproduces the anchored first-week pattern', () {
      final filled = AllowanceCalculator.fillRoster(
          year: 2026, month: 8, offDay: '2', rotation: 'N', existing: {});
      expect(filled['2026-8-1'], 'N');
      expect(filled['2026-8-2'], 'N');
      expect(filled['2026-8-3'], 'N');
      expect(filled['2026-8-4'], 'OFF');
      expect(filled['2026-8-5'], 'E');
      expect(filled['2026-8-31'], 'E');
    });
  });
}
