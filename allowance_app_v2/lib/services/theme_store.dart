import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../theme/modern_theme.dart';

/// Persists the user's selected theme id between app launches.
class ThemeStore {
  // NOTE: must NOT end in ".json" — LocalStore._mostRecentLocalFile scans
  // the documents directory for claim backups and would pick this up.
  static const _fileName = 'app_theme_pref';

  Future<ModernThemeId> load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$_fileName');
      if (!await file.exists()) return ModernThemeId.modernMarine;
      return ModernThemeId.fromId((await file.readAsString()).trim());
    } catch (_) {
      return ModernThemeId.modernMarine;
    }
  }

  Future<void> save(ModernThemeId id) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$_fileName');
      await file.writeAsString(id.id);
    } catch (_) {
      // Non-critical; the default theme is used next launch if save fails.
    }
  }
}
