import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The last good result of a fetch, with when it was fetched, so screens can
/// show stale data with an "updated 2 h ago" line instead of a blank page.
class Cached<T> {
  final T value;
  final DateTime fetchedAt;
  const Cached(this.value, this.fetchedAt);
}

/// What a screen gets for one data source: the newest data it has (maybe
/// stale) plus the error from the last refresh, if it failed.
class Snapshot<T> {
  final Cached<T>? data;
  final Object? error;
  final bool loading;
  const Snapshot({this.data, this.error, this.loading = false});
}

class JsonCache {
  final SharedPreferences _prefs;
  JsonCache(this._prefs);

  static Future<JsonCache> open() async => JsonCache(await SharedPreferences.getInstance());

  Cached<T>? read<T>(String key, T Function(Object? json) decode) {
    final raw = _prefs.getString('cache.$key');
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return Cached(decode(j['value']), DateTime.parse(j['at'] as String));
    } catch (_) {
      return null; // shape changed between app versions; refetch
    }
  }

  Future<Cached<T>> write<T>(String key, T value, Object? Function(T) encode) async {
    final at = DateTime.now();
    await _prefs.setString(
        'cache.$key', jsonEncode({'at': at.toIso8601String(), 'value': encode(value)}));
    return Cached(value, at);
  }
}
