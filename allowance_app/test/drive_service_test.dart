import 'package:flutter_test/flutter_test.dart';

import 'package:allowance_app/services/drive_service.dart';

void main() {
  group('userKeyFor', () {
    test('sanitises an email into a folder-safe key', () {
      expect(DriveService.userKeyFor('pilot.one@gmail.com'),
          'pilot.one_gmail.com');
    });

    test('handles blank input as the local fallback', () {
      expect(DriveService.userKeyFor(''), 'local');
      expect(DriveService.userKeyFor('   '), 'local');
    });

    test('strips whitespace and special characters', () {
      expect(DriveService.userKeyFor('  A B@c.d  '), 'A_B_c.d');
    });
  });

  group('monthFileName', () {
    test('builds a file name from a month string', () {
      expect(DriveService.monthFileName('SEPTEMBER, 2026'),
          'SEPTEMBER2026.json');
    });

    test('falls back when the month is blank', () {
      expect(DriveService.monthFileName('  '), 'claim.json');
    });
  });
}
