import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  final String latestVersion;
  final String releaseUrl;
  final String body;
  final List<UpdateAsset> assets;

  UpdateInfo({
    required this.latestVersion,
    required this.releaseUrl,
    required this.body,
    required this.assets,
  });
}

class UpdateAsset {
  final String name;
  final String downloadUrl;
  final int sizeBytes;

  UpdateAsset({required this.name, required this.downloadUrl, required this.sizeBytes});
}

class UpdateService {
  static const _repo = 'anishmondal5686/Allowance_Portal-app';

  /// Checks GitHub for the latest release. Returns null if no update available
  /// or if the network request fails.
  /// [appVariant] filters assets: 'v1' shows only v1 APK, 'v2' shows only v2 APK.
  static Future<UpdateInfo?> checkForUpdate(String currentVersion, {String? appVariant}) async {
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = (json['tag_name'] as String?)?.replaceFirst('v', '') ?? '';
      if (tagName.isEmpty) return null;

      if (!_isNewer(tagName, currentVersion)) return null;

      final body = (json['body'] as String?) ?? '';
      final htmlUrl = (json['html_url'] as String?) ?? '';

      final assets = <UpdateAsset>[];
      final assetsList = json['assets'] as List<dynamic>? ?? [];
      for (final a in assetsList) {
        final name = (a['name'] as String?) ?? '';
        if (!name.endsWith('.apk')) continue;
        if (appVariant == 'v1' && !name.contains('v1')) continue;
        if (appVariant == 'v2' && !name.contains('v2')) continue;
        assets.add(UpdateAsset(
          name: name,
          downloadUrl: (a['browser_download_url'] as String?) ?? '',
          sizeBytes: (a['size'] as int?) ?? 0,
        ));
      }

      return UpdateInfo(
        latestVersion: tagName,
        releaseUrl: htmlUrl,
        body: body,
        assets: assets,
      );
    } catch (_) {
      return null;
    }
  }

  /// Downloads an APK to the app cache directory.
  /// [onProgress] is called with a value between 0.0 and 1.0.
  /// Returns the file path on success, or throws on failure.
  static Future<String> downloadApk(
    UpdateAsset asset, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}${Platform.pathSeparator}${asset.name}';
    final file = File(filePath);

    final request = http.Request('GET', Uri.parse(asset.downloadUrl));
    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw Exception('Download failed: HTTP ${response.statusCode}');
    }

    final contentLength = response.contentLength ?? asset.sizeBytes;
    var receivedBytes = 0;
    final sink = file.openWrite();

    await for (final chunk in response.stream) {
      sink.add(chunk);
      receivedBytes += chunk.length;
      if (contentLength > 0) {
        onProgress?.call(receivedBytes / contentLength);
      }
    }
    await sink.flush();
    await sink.close();

    return filePath;
  }

  /// Returns true if [remote] is newer than [local].
  /// Both are semver strings like "2.0.0" (ignoring build number after +).
  static bool _isNewer(String remote, String local) {
    final r = _parseVersion(remote);
    final l = _parseVersion(local);
    if (r == null || l == null) return false;
    if (r[0] != l[0]) return r[0] > l[0];
    if (r[1] != l[1]) return r[1] > l[1];
    return r[2] > l[2];
  }

  static List<int>? _parseVersion(String v) {
    final parts = v.split('.');
    if (parts.length < 3) return null;
    final nums = parts.take(3).map(int.tryParse).toList();
    if (nums.any((n) => n == null)) return null;
    return nums.cast<int>().toList();
  }
}
