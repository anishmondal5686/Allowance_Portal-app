import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allowance_shared/theme/modern_theme.dart';

void main() {
  group('modernDynamic', () {
    test('is offered in the theme list and round-trips through its id', () {
      expect(ModernThemeId.values, contains(ModernThemeId.modernDynamic));
      expect(
        ModernThemeId.fromId('modernDynamic'),
        ModernThemeId.modernDynamic,
      );
    });

    test('takes its palette from the platform when one is supplied', () {
      final wallpaper =
          ColorScheme.fromSeed(seedColor: const Color(0xFF00696D));
      final t = ModernThemeData.buildModern(
        ModernThemeId.modernDynamic,
        dynamicScheme: wallpaper,
      );

      expect(t.colorScheme.primary, wallpaper.primary);
      expect(t.colorScheme.secondary, wallpaper.secondary);
      expect(t.brightness, ModernThemeId.modernDynamic.brightness);
    });

    test('falls back to its seed when the platform has no palette', () {
      // This is the Android 11-and-below path, where the plugin hands back null.
      final t = ModernThemeData.buildModern(ModernThemeId.modernDynamic);

      final expected = ColorScheme.fromSeed(
        seedColor: ModernThemeId.modernDynamic.seed,
        brightness: ModernThemeId.modernDynamic.brightness,
      );
      expect(t.colorScheme.primary, expected.primary);
      expect(t.colorScheme.surface, expected.surface);
    });

    test('a dynamic palette from one theme does not leak into another', () {
      final wallpaper =
          ColorScheme.fromSeed(seedColor: const Color(0xFF00696D));
      final t = ModernThemeData.buildModern(
        ModernThemeId.modernTeal,
        dynamicScheme: wallpaper,
      );
      final plain = ModernThemeData.buildModern(ModernThemeId.modernTeal);

      expect(t.colorScheme.primary, plain.colorScheme.primary);
    });

    test('reports no FlexScheme because its colours come from the platform',
        () {
      expect(ModernThemeId.modernDynamic.isDynamic, isTrue);
      for (final id in ModernThemeId.values.where((t) => t != ModernThemeId.modernDynamic)) {
        expect(id.isDynamic, isFalse, reason: id.id);
      }
    });
  });

  test('the seed fallback is distinct from every fixed-palette theme', () {
    final primaries = <Color>{};
    for (final id in ModernThemeId.values) {
      primaries.add(ModernThemeData.buildModern(id).colorScheme.primary);
    }
    // Guards theme_distinct_test: a collision would make the two themes
    // indistinguishable in the picker.
    expect(primaries.length, ModernThemeId.values.length);
  });
}