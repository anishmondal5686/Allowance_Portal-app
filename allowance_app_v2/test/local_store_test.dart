import 'dart:convert';
import 'dart:io' as io;

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

  group('monthKeyFromFileName', () {
    test('parses a stored monthly file name into a month key', () {
      expect(LocalStore.monthKeyFromFileName('September2026.json'), '2026-09');
      expect(LocalStore.monthKeyFromFileName('December2025.json'), '2025-12');
      expect(LocalStore.monthKeyFromFileName('January2027.json'), '2027-01');
    });

    test('is case-insensitive on the month name', () {
      expect(LocalStore.monthKeyFromFileName('september2026.json'), '2026-09');
      expect(LocalStore.monthKeyFromFileName('SEPTEMBER2026.json'), '2026-09');
    });

    test('returns null for non-month files', () {
      expect(LocalStore.monthKeyFromFileName('claim.json'), isNull);
      expect(LocalStore.monthKeyFromFileName('notes.txt'), isNull);
      expect(LocalStore.monthKeyFromFileName('September.json'), isNull);
      expect(LocalStore.monthKeyFromFileName('202609.json'), isNull);
      expect(LocalStore.monthKeyFromFileName('NotAMonth2026.json'), isNull);
    });
  });

  test('keeps the newest 12 monthly files by default', () {
    expect(LocalStore.maxMonths, 12);
  });

  group('pruneToNewest', () {
    Future<void> write(io.Directory dir, String name) async {
      final f = io.File(
          '${dir.path}${io.Platform.pathSeparator}$name');
      await f.writeAsString(jsonEncode({'m': name}));
      await f.setLastModified(DateTime(2026, name.contains('2025') ? 1 : 9));
    }

    test('dedupes files that map to the same month, keeping the newest',
        () async {
      final dir = await io.Directory.systemTemp.createTemp('monthstore');
      try {
        await write(dir, 'September2026.json');
        await write(dir, 'september2026.json');
        await write(dir, 'October2026.json');
        final store = LocalStore(dirOverride: () async => dir);
        await store.pruneToNewest(12);
        final remaining =
            dir.listSync().whereType<io.File>().map((f) => f.uri.pathSegments.last).toList();
        expect(remaining.length, 2, reason: 'one duplicate should be removed');
        // The duplicate case mapping to '2026-09' must not both survive.
        expect(remaining.where((n) => n.toLowerCase() == 'september2026.json'),
            hasLength(1));
        expect(remaining, contains('October2026.json'));
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
