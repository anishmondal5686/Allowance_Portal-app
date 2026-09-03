import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/models/master_data.dart';

class SyncResult {
  final bool success;
  final String? error;
  const SyncResult(this.success, [this.error]);
}

class _AuthClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  final String _token;

  _AuthClient(this._token);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

class DriveService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [DriveApi.driveFileScope],
    serverClientId: '486404217110-vc0k0mqncck6lhc05ttii85ekiufra6m.apps.googleusercontent.com',
  );

  GoogleSignInAccount? _currentUser;
  DriveApi? _driveApi;
  _AuthClient? _client;
  String? _baseFolderId;
  String? _userFolderId;
  Future<io.Directory> Function()? _dirOverride;

  DriveService({Future<io.Directory> Function()? dirOverride}) {
    _dirOverride = dirOverride;
  }

  static const _fileNameFallback = 'claim.json';
  static const _appFolderName = 'Allowance App';

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

  bool get isSignedIn => _currentUser != null;
  GoogleSignInAccount? get currentUser => _currentUser;

  /// Stable per-user key used to isolate Drive folders and local backups.
  static String userKeyFor(String email) {
    final e = email.trim();
    if (e.isEmpty) return 'local';
    return e.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  }

  String get _userKey => userKeyFor(_currentUser?.email ?? '');

  Future<SyncResult> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      if (_currentUser == null) {
        return const SyncResult(false, 'Sign-in cancelled');
      }
      final authHeaders = await _currentUser!.authHeaders;
      final authValue = authHeaders['Authorization'];
      if (authValue == null) {
        return const SyncResult(false, 'Failed to get auth token');
      }
      final token = authValue.replaceFirst('Bearer ', '');
      _client = _AuthClient(token);
      _driveApi = DriveApi(_client!);
      _baseFolderId = null;
      _userFolderId = null;
      return const SyncResult(true);
    } catch (e, stack) {
      debugPrint('SignIn error: $e\n$stack');
      return SyncResult(false, 'Sign-in error: $e');
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    _client?.close();
    _client = null;
    _driveApi = null;
    _baseFolderId = null;
    _userFolderId = null;
  }

  Future<String?> _findFolder(String name, {String? parent}) async {
    if (_driveApi == null) return null;
    try {
      final parentClause =
          parent != null ? " and '$parent' in parents" : '';
      final response = await _driveApi!.files.list(
        q: "name='$name' and mimeType='application/vnd.google-apps.folder'"
            " and trashed=false$parentClause",
        spaces: 'drive',
        $fields: 'files(id)',
      );
      final files = response.files ?? [];
      return files.isNotEmpty ? files.first.id : null;
    } catch (e) {
      return null;
    }
  }

  Future<String?> _ensureBaseFolder() async {
    if (_driveApi == null) return null;
    if (_baseFolderId != null) return _baseFolderId;
    final existing = await _findFolder(_appFolderName);
    if (existing != null) {
      _baseFolderId = existing;
      return existing;
    }
    try {
      final folder = File()
        ..name = _appFolderName
        ..mimeType = 'application/vnd.google-apps.folder';
      final created = await _driveApi!.files.create(folder, $fields: 'id');
      _baseFolderId = created.id;
      return created.id;
    } catch (e) {
      debugPrint('Create app folder error: $e');
      return null;
    }
  }

  Future<String?> _ensureUserFolder() async {
    if (_driveApi == null) return null;
    if (_userFolderId != null) return _userFolderId;
    final base = await _ensureBaseFolder();
    if (base == null) return null;
    final existing = await _findFolder(_userKey, parent: base);
    if (existing != null) {
      _userFolderId = existing;
      return existing;
    }
    try {
      final folder = File()
        ..name = _userKey
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [base];
      final created = await _driveApi!.files.create(folder, $fields: 'id');
      _userFolderId = created.id;
      await _migrateLegacyDriveFiles(created.id!);
      return created.id;
    } catch (e) {
      debugPrint('Create user folder error: $e');
      return null;
    }
  }

  /// One-time migration: pull pre-multi-user claim files from the Drive root
  /// into the newly created user folder.
  Future<void> _migrateLegacyDriveFiles(String userFolderId) async {
    try {
      final response = await _driveApi!.files.list(
        q: "trashed=false and name contains '.json'",
        spaces: 'drive',
        $fields: 'files(id, name)',
      );
      final files = response.files ?? [];
      for (final f in files) {
        final name = f.name ?? '';
        if (!name.endsWith('.json') || name == _fileNameFallback) continue;
        if (f.id == null) continue;
        await _driveApi!.files.update(
          File()..name = name,
          f.id!,
          addParents: userFolderId,
          removeParents: 'root',
        );
      }
    } catch (e) {
      debugPrint('Migrate legacy Drive files error: $e');
    }
  }

  Future<String?> findExistingFileId(String fileName) async {
    if (_driveApi == null) return null;
    final parent = await _ensureUserFolder();
    if (parent == null) return null;
    try {
      final response = await _driveApi!.files.list(
        q: "name='$fileName' and trashed=false and '$parent' in parents",
        spaces: 'drive',
      );
      if (response.files != null && response.files!.isNotEmpty) {
        return response.files!.first.id;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<List<String>> listDriveFiles() async {
    if (_driveApi == null) return const [];
    final parent = await _ensureUserFolder();
    if (parent == null) return const [];
    try {
      final response = await _driveApi!.files.list(
        q: "trashed=false and '$parent' in parents",
        spaces: 'drive',
        $fields: 'files(id, name)',
      );
      final files = response.files ?? [];
      final names = files
          .map((f) => f.name ?? '')
          .where((n) => n.endsWith('.json'))
          .toList()
        ..sort();
      return names;
    } catch (e) {
      return const [];
    }
  }

  Future<SyncResult> uploadClaim(ClaimData data) async {
    if (_driveApi == null) {
      return const SyncResult(false, 'Not signed in');
    }
    try {
      final parent = await _ensureUserFolder();
      if (parent == null) {
        return const SyncResult(false, 'Drive folder unavailable');
      }
      final jsonString = jsonEncode(data.toJson());
      final bytes = utf8.encode(jsonString);
      final fileName = fileNameFor(data);
      final fileId = await findExistingFileId(fileName);

      final driveFile = File()..name = fileName;

      if (fileId != null) {
        await _driveApi!.files.update(
          driveFile,
          fileId,
          uploadMedia: Media(Stream.value(bytes), bytes.length),
        );
      } else {
        driveFile.parents = [parent];
        await _driveApi!.files.create(
          driveFile,
          uploadMedia: Media(Stream.value(bytes), bytes.length),
        );
      }
      return const SyncResult(true);
    } catch (e) {
      return SyncResult(false, 'Upload error: $e');
    }
  }

  Future<SyncResult> downloadClaim({
    required ClaimData target,
    String? fileName,
  }) async {
    if (_driveApi == null) {
      return const SyncResult(false, 'Not signed in');
    }
    try {
      final fname = fileName ?? fileNameFor(target);
      final fileId = await findExistingFileId(fname);
      if (fileId == null) {
        return SyncResult(false, 'No file found on Drive for "$fname"');
      }

      final response = await _driveApi!.files.get(
        fileId,
        downloadOptions: DownloadOptions.fullMedia,
      ) as Media?;

      if (response == null) {
        return const SyncResult(false, 'Empty response from Drive');
      }

      final jsonString = await response.stream.transform(utf8.decoder).join();
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      final data = ClaimData.fromJson(jsonData);

        target.master = data.master;
        target.movements
        ..clear()
        ..addAll(data.movements);
      target.attShifts = data.attShifts;
      target.attManualDates = data.attManualDates;
      target.attLocked = data.attLocked;
      target.attOffDay = data.attOffDay;
      target.attRotation = data.attRotation;

      return const SyncResult(true);
    } catch (e) {
      return SyncResult(false, 'Download error: $e');
    }
  }

  Future<io.Directory> _localUserDir() async {
    final override = _dirOverride;
    if (override != null) return override();
    final base = await getApplicationDocumentsDirectory();
    final dir = io.Directory('${base.path}${io.Platform.pathSeparator}'
        '$_appFolderName${io.Platform.pathSeparator}$_userKey');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Maximum number of monthly local backup files to keep. When a save would
  /// exceed this, the oldest monthly files are deleted so the newest 12 remain.
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

  Future<String> saveLocalBackup(ClaimData data) async {
    final dir = await _localUserDir();
    final file = io.File(
        '${dir.path}${io.Platform.pathSeparator}${fileNameFor(data)}');
    final jsonString = jsonEncode(data.toJson());
    await file.writeAsString(jsonString);
    await pruneLocalBackupsToNewest(maxMonths);
    return file.path;
  }

  /// Returns the canonical keys of all saved monthly local backups (e.g.
  /// '2026-09'), sorted newest-first by file modification time. Non-month
  /// files are ignored.
  Future<List<String>> listSavedMonths() async {
    final dir = await _localUserDir();
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

  /// Keeps only the newest [n] monthly local backup files, deleting the rest.
  /// When two or more files map to the same month key, only the newest one is
  /// retained for that month (older duplicates are treated as redundant).
  Future<void> pruneLocalBackupsToNewest(int n) async {
    if (n < 1) return;
    final dir = await _localUserDir();
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

  Future<ClaimData?> loadLocalBackup({String? month}) async {
    try {
      final userDir = await _localUserDir();
      final fname = month != null && month.trim().isNotEmpty
          ? monthFileName(month)
          : null;
      var file = fname != null
          ? io.File('${userDir.path}${io.Platform.pathSeparator}$fname')
          : await _mostRecentLocalFile(userDir);
      // Legacy fallback: pre-multi-user backups live directly in the app
      // documents dir. Copy any found file into the user folder so that
      // subsequent saves and loads line up.
      if (file == null || !await file.exists()) {
        final legacyDir = await getApplicationDocumentsDirectory();
        var legacy = fname != null
            ? io.File('${legacyDir.path}${io.Platform.pathSeparator}$fname')
            : await _mostRecentLocalFile(legacyDir);
        if (legacy != null && await legacy.exists()) {
          final target = '${userDir.path}${io.Platform.pathSeparator}'
              '${legacy.path.split(io.Platform.pathSeparator).last}';
          try {
            file = await legacy.copy(target);
          } catch (_) {
            file = legacy;
          }
        }
      }
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
