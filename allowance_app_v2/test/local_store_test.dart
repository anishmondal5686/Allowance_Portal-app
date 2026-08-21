import 'package:flutter_test/flutter_test.dart';

import 'package:allowance_app_v2/services/local_store.dart';

void main() {
  group('monthFileName', () {
    test('builds a file name from a month string', () {
      expect(LocalStore.monthFileName('SEPTEMBER, 2026'),
          'SEPTEMBER2026.json');
    });

    test('falls back when the month is blank', () {
      expect(LocalStore.monthFileName('  '), 'claim.json');
    });
  });
}
