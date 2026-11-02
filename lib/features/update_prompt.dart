import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'common.dart';

/// Where a new version is announced, and where the student goes to fetch it.
const _latestRelease = 'https://api.github.com/repos/kamol1dn/inha_app/releases/latest';
final releasesPage = Uri.parse('https://github.com/kamol1dn/inha_app/releases/latest');

/// The last version the student was told about, so each one asks only once.
const _toldKey = 'update.toldVersion';

/// "v1.4.0" or "1.4.0+5" as [1, 4, 0]; null for anything else.
List<int>? _parts(String version) {
  final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)').firstMatch(version.trim());
  return m == null ? null : [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
}

/// Whether [latest] is a later version than [current]. The build number after
/// "+" doesn't count, and a tag that isn't a version is never newer.
bool isNewerVersion(String latest, String current) {
  final (a, b) = (_parts(latest), _parts(current));
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

/// The newest release's version, "1.4.0", or null when GitHub can't say. A
/// release counts once it holds an APK: the extension's files reach it minutes
/// earlier, and a build that fails leaves it without one.
Future<String?> fetchLatestVersion([Dio? dio]) async {
  try {
    final res = await (dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 10))))
        .get<Map<String, dynamic>>(_latestRelease);
    final tag = res.data?['tag_name'];
    final assets = res.data?['assets'];
    final hasApk = assets is List && assets.any((a) => a is Map && '${a['name']}'.endsWith('.apk'));
    return tag is String && hasApk ? tag.trim().replaceFirst(RegExp('^v'), '') : null;
  } on DioException {
    return null;
  }
}

Future<void> _showUpdate(BuildContext context, {required String latest, required String current}) => showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('New version available'),
        content: Text('Version $latest is out. You have $current. Download it from the releases page, then install it over this one.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(), child: const Text('Later')),
          TextButton(
            onPressed: () {
              Navigator.of(dialog).pop();
              openUrl(context, releasesPage);
            },
            child: const Text('Open releases'),
          ),
        ],
      ),
    );

/// At start: tells the student about a newer version, once per version. Says
/// nothing when there is none or GitHub can't be reached.
Future<void> promptForUpdate(
  BuildContext context, {
  Future<String?> Function() latest = fetchLatestVersion,
  Future<String> Function()? current,
}) async {
  final have = await (current ?? _installedVersion)();
  final newest = await latest();
  if (newest == null || !isNewerVersion(newest, have) || !context.mounted) return;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString(_toldKey) == newest || !context.mounted) return;
  await prefs.setString(_toldKey, newest);
  if (context.mounted) await _showUpdate(context, latest: newest, current: have);
}

/// From Settings: the same check on request, and it always answers.
Future<void> checkForUpdateNow(
  BuildContext context, {
  Future<String?> Function() latest = fetchLatestVersion,
  Future<String> Function()? current,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final have = await (current ?? _installedVersion)();
  final newest = await latest();
  if (!context.mounted) return;
  if (newest == null) {
    messenger.showSnackBar(const SnackBar(content: Text("Couldn't reach GitHub. Check the connection.")));
  } else if (isNewerVersion(newest, have)) {
    await _showUpdate(context, latest: newest, current: have);
  } else {
    messenger.showSnackBar(SnackBar(content: Text('You have the latest version, $have.')));
  }
}

Future<String> _installedVersion() async => (await PackageInfo.fromPlatform()).version;
