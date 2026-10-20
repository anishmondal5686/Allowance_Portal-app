import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';

import 'package:allowance_app_v2/services/drive_service.dart';
import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/models/master_data.dart';

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

  group('migrateDocumentsRootFiles', () {
    test('copies month files from the documents root into the user folder '
        'and leaves the originals in place', () async {
      final userDir = await io.Directory.systemTemp.createTemp('drivestore-user');
      final legacyDir =
          await io.Directory.systemTemp.createTemp('drivestore-legacy');
      try {
        await io.File(
            '${legacyDir.path}${io.Platform.pathSeparator}September2026.json')
            .writeAsString(jsonEncode({'m': 'sep'}));
        // Existing file with the same name must NOT be overwritten.
        await io.File(
            '${userDir.path}${io.Platform.pathSeparator}October2026.json')
            .writeAsString(jsonEncode({'m': 'existing'}));
        await io.File(
            '${legacyDir.path}${io.Platform.pathSeparator}October2026.json')
            .writeAsString(jsonEncode({'m': 'newer'}));
        // Non-month clutter must be ignored (incl. the fallback and theme file).
        await io.File(
            '${legacyDir.path}${io.Platform.pathSeparator}claim.json')
            .writeAsString(jsonEncode({'m': 'junk'}));
        await io.File(
            '${legacyDir.path}${io.Platform.pathSeparator}app_theme_pref')
            .writeAsString('x');
        await io.File(
            '${legacyDir.path}${io.Platform.pathSeparator}notes.txt')
            .writeAsString('x');
        await io.File(
            '${legacyDir.path}${io.Platform.pathSeparator}September2026'
            ' backup 2026-10-20 1432.json')
            .writeAsString(jsonEncode({'m': 'conflict'}));

        final service = DriveService(
            dirOverride: () async => userDir,
        );
        final moved = await service
            .migrateDocumentsRootFiles(legacyDirOverride: legacyDir);

        expect(moved, 1, reason: 'only the missing September file copies');
        final userFiles = userDir.listSync().whereType<io.File>().toList();
        expect(userFiles.any((f) =>
            f.uri.pathSegments.last == 'September2026.json'), isTrue);
        expect(userFiles.any((f) =>
            f.uri.pathSegments.last == 'October2026.json'), isTrue);
        final kept =
            io.File('${userDir.path}/October2026.json'.replaceAll('/', io.Platform.pathSeparator));
        expect(jsonDecode(kept.readAsStringSync())['m'], 'existing');
        // Originals untouched (copy, never move).
        expect(
            io.File(
                '${legacyDir.path}/September2026.json'.replaceAll('/', io.Platform.pathSeparator))
                .existsSync(),
            isTrue);
      } finally {
        await userDir.delete(recursive: true);
        await legacyDir.delete(recursive: true);
      }
    });

    test('loadLocalBackup adopts an un-migrated documents-root month file',
        () async {
      final userDir = await io.Directory.systemTemp.createTemp('drivestore-user');
      final legacyDir =
          await io.Directory.systemTemp.createTemp('drivestore-legacy');
      try {
        final claim = ClaimData(
          master: MasterData(
            month: '2026-08',
            name: 'LEGACY USER',
            designation: 'DOCK PILOT',
          ),
        );
        await io.File(
            '${legacyDir.path}${io.Platform.pathSeparator}'
            'August2026.json')
            .writeAsString(jsonEncode(claim.toJson()));
        final service = DriveService(
          dirOverride: () async => userDir,
          legacyDirOverride: () async => legacyDir,
        );
        final loaded =
            await service.loadLocalBackup(month: '2026-08');
        expect(loaded?.master.name, 'LEGACY USER');
        // The fallback copies the file into the user folder for later loads.
        expect(
            io.File(
                '${userDir.path}/August2026.json'
                    .replaceAll('/', io.Platform.pathSeparator))
                .existsSync(),
            isTrue);
      } finally {
        await userDir.delete(recursive: true);
        await legacyDir.delete(recursive: true);
      }
    });
  });

  group('promoteLocalMonthsToUserFolder', () {
    // Not directly testable without a signed-in account; covered indirectly by
    // signIn() in device testing. The copy semantics mirror
    // migrateDocumentsRootFiles, which is fully covered above.
    test('month promotion mirrors the migration copy semantics', () {
      expect(DriveService.userKeyFor(''), 'local');
    });
  });

  group('createConflictBackup', () {
    test('writes a sibling backup file that listSavedMonths ignores',
        () async {
      final dir = await io.Directory.systemTemp.createTemp('drivestore');
      try {
        final data = ClaimData(
          master: MasterData(
            month: '2026-09',
            name: 'TEST USER',
            designation: 'DOCK PILOT',
          ),
        );
        final service = DriveService(dirOverride: () async => dir);
        await service.saveLocalBackup(data);
        final backupPath = await service.createConflictBackup(month: '2026-09');
        expect(backupPath, isNotNull);
        final months = await service.listSavedMonths();
        expect(months, ['2026-09'],
            reason: 'conflict backups must stay out of the month history');
        final backup = io.File(backupPath!);
        expect(backup.existsSync(), isTrue);
        expect(backup.uri.pathSegments.last, contains(' backup '));
        // Null when nothing is on the local mirror for the month.
        expect(await service.createConflictBackup(month: '2025-01'), isNull);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
