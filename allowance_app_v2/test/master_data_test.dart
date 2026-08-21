import 'package:flutter_test/flutter_test.dart';
import 'package:allowance_app_v2/models/master_data.dart';

void main() {
  group('MasterData.parseMonthYear', () {
    test('parses YYYY-MM keys', () {
      expect(MasterData.parseMonthYear('2026-09'), (2026, 9));
      expect(MasterData.parseMonthYear('2026/09'), (2026, 9));
      expect(MasterData.parseMonthYear('2026-9'), (2026, 9));
    });

    test('parses month name strings', () {
      expect(MasterData.parseMonthYear('JULY, 2026'), (2026, 7));
      expect(MasterData.parseMonthYear('September 2026'), (2026, 9));
      expect(MasterData.parseMonthYear('january 2025'), (2025, 1));
    });

    test('returns null for unparseable input', () {
      expect(MasterData.parseMonthYear(''), isNull);
      expect(MasterData.parseMonthYear('   '), isNull);
      expect(MasterData.parseMonthYear('not a month'), isNull);
    });
  });

  group('MasterData.monthKey/monthLabel', () {
    test('monthKey pads the month to two digits', () {
      expect(MasterData.monthKey(2026, 9), '2026-09');
      expect(MasterData.monthKey(2026, 12), '2026-12');
    });

    test('monthLabel produces an uppercase month name', () {
      expect(MasterData.monthLabel(2026, 9), 'SEPTEMBER, 2026');
    });
  });

  group('MasterData.isAdm', () {
    test('true for ADM designations', () {
      for (final d in [
        'ADM',
        'ADM - Haldia Dock',
        'Assistant Dock Master',
        'ASSISTANT DOCK MASTER',
        'Dock Pilot / ADM',
      ]) {
        expect(
          MasterData(designation: d).isAdm,
          isTrue,
          reason: 'designation "$d" should be ADM',
        );
      }
    });

    test('false for non-ADM designations', () {
      for (final d in [
        '',
        'Dock Pilot',
        'Berthing Pilot',
        'Harbour Pilot',
        'Assistant',
        'ADMINISTRATIVE OFFICER',
      ]) {
        expect(
          MasterData(designation: d).isAdm,
          isFalse,
          reason: 'designation "$d" should not be ADM',
        );
      }
    });
  });
}
