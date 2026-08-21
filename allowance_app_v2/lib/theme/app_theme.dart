import 'package:flutter/material.dart';

/// Interchangeable app themes for the Allowance Portal.
///
/// Each theme is identified by a stable [id] that is persisted to disk, so
/// the user's choice survives app restarts.
enum AppThemeId {
  marineLight(
    'marineLight',
    'Marine',
    Icons.light_mode_outlined,
    Color(0xFF283593),
    Brightness.light,
  ),
  oceanLight(
    'oceanLight',
    'Ocean',
    Icons.water_drop_outlined,
    Color(0xFF00695C),
    Brightness.light,
  ),
  sunsetLight(
    'sunsetLight',
    'Sunset',
    Icons.wb_sunny_outlined,
    Color(0xFFBF360C),
    Brightness.light,
  ),
  midnightDark(
    'midnightDark',
    'Midnight',
    Icons.dark_mode_outlined,
    Color(0xFF3F51B5),
    Brightness.dark,
  ),
  abyssDark(
    'abyssDark',
    'Abyss',
    Icons.nightlight_outlined,
    Color(0xFF00897B),
    Brightness.dark,
  );

  const AppThemeId(this.id, this.label, this.icon, this.seed, this.brightness);

  final String id;
  final String label;
  final IconData icon;
  final Color seed;
  final Brightness brightness;

  static AppThemeId fromId(String? id) {
    if (id == null) return AppThemeId.marineLight;
    for (final t in AppThemeId.values) {
      if (t.id == id) return t;
    }
    return AppThemeId.marineLight;
  }
}

/// Builds the [ThemeData] for a given [AppThemeId].
///
/// All themes share the same Material 3 component styling (rounded cards,
/// consistent inputs, floating snackbars) so switching between them only
/// changes the colour language, not the layout.
class AppTheme {
  AppTheme._();

  static ThemeData build(AppThemeId id) {
    final scheme = ColorScheme.fromSeed(
      seedColor: id.seed,
      brightness: id.brightness,
    );
    final radius = BorderRadius.circular(10);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: radius),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: 0.25),
      ),
    );
  }
}
