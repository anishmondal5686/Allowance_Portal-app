import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allowance_shared/theme/modern_theme.dart';

void main() {
  test('each ModernThemeId builds a visually distinct primary colour', () {
    final primaries = <Color, String>{};
    for (final id in ModernThemeId.values) {
      final t = ModernThemeData.buildModern(id);
      expect(t.brightness, id.brightness);
      expect(primaries.containsKey(t.colorScheme.primary), isFalse,
          reason: '${id.id} shares its primary with '
              '${primaries[t.colorScheme.primary]}');
      primaries[t.colorScheme.primary] = id.id;
    }
    expect(primaries.length, ModernThemeId.values.length);
  });
}