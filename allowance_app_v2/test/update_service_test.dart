import 'package:allowance_shared/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateService.selectAssetsForVariant', () {
    final v1 = _asset('allowance_app_v2.0.24-arm64-v8a_RELEASE.apk');
    final v2 = _asset('allowance_app_v2_v2.0.24-arm64-v8a_RELEASE.apk');
    final other = _asset('notes.txt');

    test('v1 keeps only the v1 APK, never the v2 APK', () {
      final picked = UpdateService.selectAssetsForVariant(
        [v1, v2, other],
        appVariant: 'v1',
      );
      expect(
          picked.map((a) => a.name),
          ['allowance_app_v2.0.24-arm64-v8a_RELEASE.apk']);
    });

    test('v2 keeps only the v2 APK, never the v1 APK', () {
      final picked = UpdateService.selectAssetsForVariant(
        [v1, v2, other],
        appVariant: 'v2',
      );
      expect(
          picked.map((a) => a.name),
          ['allowance_app_v2_v2.0.24-arm64-v8a_RELEASE.apk']);
    });

    test('no variant keeps both APKs and skips non-APK files', () {
      final picked = UpdateService.selectAssetsForVariant([v1, v2, other]);
      expect(picked.length, 2);
    });

    test('realistic asset list never leaves a variant assetless', () {
      for (final variant in ['v1', 'v2']) {
        final picked = UpdateService.selectAssetsForVariant(
          [v1, v2],
          appVariant: variant,
        );
        expect(picked, isNotEmpty,
            reason: 'variant $variant was left assetless');
      }
    });
  });
}

Map<String, dynamic> _asset(String name) => {
      'name': name,
      'browser_download_url': 'https://example.com/$name',
      'size': 42,
    };