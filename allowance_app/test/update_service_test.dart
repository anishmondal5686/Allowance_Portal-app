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
      expect(picked.map((a) => a.name), ['allowance_app_v2.0.24-arm64-v8a_RELEASE.apk']);
    });

    test('v2 keeps only the v2 APK, never the v1 APK', () {
      final picked = UpdateService.selectAssetsForVariant(
        [v1, v2, other],
        appVariant: 'v2',
      );
      expect(picked.map((a) => a.name), [
        'allowance_app_v2_v2.0.24-arm64-v8a_RELEASE.apk'
      ]);
    });

    test('no variant keeps both APKs and skips non-APK files', () {
      final picked =
          UpdateService.selectAssetsForVariant([v1, v2, other]);
      expect(picked.length, 2);
    });

    test('realistic asset list never leaves a variant assetless', () {
      for (final variant in ['v1', 'v2']) {
        final picked = UpdateService.selectAssetsForVariant(
          [v1, v2],
          appVariant: variant,
        );
        expect(picked, isNotEmpty, reason: 'variant $variant was left assetless');
      }
    });

    test('current release naming keeps the two variants disjoint', () {
      const currentV1 = 'allowance_app_v1_2.0.36-arm64-v8a_RELEASE.apk';
      const currentV2 = 'allowance_app_v2_2.0.36-arm64-v8a_RELEASE.apk';

      // The in-app updater matches assets by name, so a v1 asset must contain
      // 'v1' and must never contain 'v2' — otherwise v1 devices pick up the
      // v2 APK and the install fails on a package-name mismatch.
      expect(currentV1.contains('v1'), isTrue);
      expect(currentV1.contains('v2'), isFalse);

      final assets = [_asset(currentV1), _asset(currentV2)];
      expect(
        UpdateService.selectAssetsForVariant(assets, appVariant: 'v1')
            .map((a) => a.name),
        [currentV1],
      );
      expect(
        UpdateService.selectAssetsForVariant(assets, appVariant: 'v2')
            .map((a) => a.name),
        [currentV2],
      );
    });
  });
}

Map<String, dynamic> _asset(String name) => {
      'name': name,
      'browser_download_url': 'https://example.com/$name',
      'size': 42,
    };