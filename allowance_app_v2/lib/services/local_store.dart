import 'dart:convert';
import 'dart:io' as io;
import 'package:path_provider/path_provider.dart';
import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/models/master_data.dart';

/// Local-only persistence for the app. Data is saved on the device in the
/// app's documents directory; nothing is uploaded anywhere.
class LocalStore {
  static const _fileNameFallback = 'claim.json';

  /// Optional override for the directory that stores claim files. Defaults to
  /// the platform documents directory. Provided so widget tests can back the
  /// store with an isolated temp directory instead of path_provider.
  Future<io.Directory> Function()? _dirOverride;

  LocalStore({Future<io.Directory> Function()? dirOverride}) {
    _dirOverride = dirOverride;
  }

  Future<io.Directory> _dir() => (_dirOverride ?? getApplicationDocumentsDirectory)();

  static String monthFileName(String month) {
    final parsed = MasterData.parseMonthYear(month);
    if (parsed != null) {
      return '${MasterData.monthNames[parsed.$2 - 1]}${parsed.$1}.json';
    }
    final cleaned = month
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (cleaned.isEmpty) return _fileNameFallback;
    return '$cleaned.json';
  }

  static String fileNameFor(ClaimData data) => monthFileName(data.master.month);

  /// Maximum number of monthly claim files to keep. When a save would exceed
  /// this, the oldest monthly files are deleted so the newest 12 remain.
  static const int maxMonths = 12;

  /// Parses a stored monthly filename (e.g. 'September2026.json') back into a
  /// canonical month key like '2026-09'. Returns null for non-month files such
  /// as 'claim.json'.
  static String? monthKeyFromFileName(String fname) {
    var base = fname;
    if (base.endsWith('.json')) {
      base = base.substring(0, base.length - '.json'.length);
    }
    final match = RegExp(r'^([A-Za-z]+)(\d{4})$').firstMatch(base);
    if (match == null) return null;
    final monthName = match.group(1)!;
    final year = int.tryParse(match.group(2)!);
    if (year == null) return null;
    final month = MasterData.monthNames
            .indexWhere((m) => m.toLowerCase() == monthName.toLowerCase()) +
        1;
    if (month < 1 || month > 12) return null;
    return MasterData.monthKey(year, month);
  }

  Future<String> save(ClaimData data) async {
    final dir = await _dir();
    final file = io.File(
        '${dir.path}${io.Platform.pathSeparator}${fileNameFor(data)}');
    final jsonString = jsonEncode(data.toJson());
    await file.writeAsString(jsonString);
    await pruneToNewest(maxMonths);
    return file.path;
  }

  /// Returns the canonical keys of all saved monthly files (e.g. '2026-09'),
  /// sorted newest-first by file modification time. Non-month files are
  /// ignored.
  Future<List<String>> listSavedMonths() async {
    final dir = await _dir();
    final months = <String, DateTime>{};
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is! io.File || !entity.path.endsWith('.json')) continue;
        final key = monthKeyFromFileName(entity.uri.pathSegments.last);
        if (key == null) continue;
        if (!months.containsKey(key)) {
          months[key] = await entity.lastModified();
        }
      }
    }
    final sorted = months.keys.toList()
      ..sort((a, b) => months[b]!.compareTo(months[a]!));
    return sorted;
  }

  /// Keeps only the newest [n] monthly files, deleting the rest. When two or
  /// more files map to the same month key, only the newest one is retained for
  /// that month (older duplicates are treated as redundant). Always keeps at
  /// least the current month's entries even if [n] is smaller.
  Future<void> pruneToNewest(int n) async {
    if (n < 1) return;
    final dir = await _dir();
    if (!await dir.exists()) return;
    final newestByMonth = <String, io.File>{};
    final stamped = <io.File, DateTime>{};
    await for (final entity in dir.list()) {
      if (entity is! io.File || !entity.path.endsWith('.json')) continue;
      final key = monthKeyFromFileName(entity.uri.pathSegments.last);
      if (key == null) continue;
      final modified = await entity.lastModified();
      stamped[entity] = modified;
      final current = newestByMonth[key];
      if (current == null || modified.isAfter(stamped[current]!)) {
        newestByMonth[key] = entity;
      }
    }
    final dupes = <String>{for (final f in stamped.keys) f.path};
    dupes.removeAll(newestByMonth.values.map((f) => f.path));
    final sortedNewest = newestByMonth.values.toList()
      ..sort((a, b) => stamped[b]!.compareTo(stamped[a]!));
    for (final f in sortedNewest.skip(n)) {
      dupes.add(f.path);
    }
    for (final path in dupes) {
      try {
        await io.File(path).delete();
      } catch (_) {
        // Ignore individual delete failures (e.g. in-use file).
      }
    }
  }

  Future<ClaimData?> load({String? month}) async {
    try {
      final dir = await _dir();
      final fname = month != null && month.trim().isNotEmpty
          ? monthFileName(month)
          : null;
      final file = fname != null
          ? io.File('${dir.path}${io.Platform.pathSeparator}$fname')
          : await _mostRecentLocalFile(dir);
      if (file == null || !await file.exists()) return null;
      final jsonString = await file.readAsString();
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      return ClaimData.fromJson(jsonData);
    } catch (e) {
      return null;
    }
  }

  Future<io.File?> _mostRecentLocalFile(io.Directory dir) async {
    if (!await dir.exists()) return null;
    io.File? newest;
    DateTime? newestTime;
    await for (final entity in dir.list()) {
      if (entity is! io.File || !entity.path.endsWith('.json')) continue;
      final modified = await entity.lastModified();
      if (newest == null || modified.isAfter(newestTime!)) {
        newest = entity;
        newestTime = modified;
      }
    }
    return newest;
  }
}
