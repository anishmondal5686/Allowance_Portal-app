import 'dart:convert';
import 'package:http/http.dart' as http;

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
  static Future<UpdateInfo?> checkForUpdate(String currentVersion) async {
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
