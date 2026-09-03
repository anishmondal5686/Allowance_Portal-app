import 'dart:convert';
import 'dart:io' as io;

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

  group('monthKeyFromFileName', () {
    test('parses a stored monthly file name into a month key', () {
      expect(DriveService.monthKeyFromFileName('September2026.json'), '2026-09');
      expect(DriveService.monthKeyFromFileName('December2025.json'), '2025-12');
      expect(DriveService.monthKeyFromFileName('January2027.json'), '2027-01');
    });

    test('is case-insensitive on the month name', () {
      expect(DriveService.monthKeyFromFileName('september2026.json'), '2026-09');
      expect(DriveService.monthKeyFromFileName('SEPTEMBER2026.json'), '2026-09');
    });

    test('returns null for non-month files', () {
      expect(DriveService.monthKeyFromFileName('claim.json'), isNull);
      expect(DriveService.monthKeyFromFileName('notes.txt'), isNull);
      expect(DriveService.monthKeyFromFileName('September.json'), isNull);
      expect(DriveService.monthKeyFromFileName('202609.json'), isNull);
      expect(DriveService.monthKeyFromFileName('NotAMonth2026.json'), isNull);
    });
  });

  test('keeps the newest 12 monthly backups by default', () {
    expect(DriveService.maxMonths, 12);
  });

  group('pruneLocalBackupsToNewest', () {
    Future<void> write(io.Directory dir, String name) async {
      final f = io.File(
          '${dir.path}${io.Platform.pathSeparator}$name');
      await f.writeAsString(jsonEncode({'m': name}));
      await f.setLastModified(DateTime(2026, name.contains('2025') ? 1 : 9));
    }

    test('dedupes files that map to the same month, keeping the newest',
        () async {
      final dir = await io.Directory.systemTemp.createTemp('drivestore');
      try {
        await write(dir, 'September2026.json');
        await write(dir, 'september2026.json');
        await write(dir, 'October2026.json');
        final service = DriveService(dirOverride: () async => dir);
        await service.pruneLocalBackupsToNewest(12);
        final remaining = dir
            .listSync()
            .whereType<io.File>()
            .map((f) => f.uri.pathSegments.last)
            .toList();
        expect(remaining.length, 2, reason: 'one duplicate should be removed');
        expect(remaining.where((n) => n.toLowerCase() == 'september2026.json'),
            hasLength(1));
        expect(remaining, contains('October2026.json'));
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
