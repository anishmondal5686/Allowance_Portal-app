import 'dart:convert';
import 'dart:io' as io;
import 'package:path_provider/path_provider.dart';
import '../models/claim_data.dart';
import '../models/master_data.dart';

/// Local-only persistence for the app. Data is saved on the device in the
/// app's documents directory; nothing is uploaded anywhere.
class LocalStore {
  static const _fileNameFallback = 'claim.json';

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

  Future<String> save(ClaimData data) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = io.File(
        '${dir.path}${io.Platform.pathSeparator}${fileNameFor(data)}');
    final jsonString = jsonEncode(data.toJson());
    await file.writeAsString(jsonString);
    return file.path;
  }

  Future<ClaimData?> load({String? month}) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
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
