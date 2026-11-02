import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/models.dart';

class Credentials {
  final String username;
  final String password;
  const Credentials(this.username, this.password);
}

/// Per-service logins, kept in the Android Keystore-backed secure storage.
/// Nothing here is ever logged or written to the cache.
///
/// A login a service refused is remembered, so refreshes stop repeating it: a
/// university account can lock after a few failed logons (docs/ENDPOINTS.md).
class CredentialStore {
  final FlutterSecureStorage _storage;
  CredentialStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  /// How long a refused login stays unused. Saving a login clears it at once;
  /// this only lets a refusal that wasn't about the password (a server having
  /// a bad moment) mend itself, at one failed logon a day.
  static const refusalLasts = Duration(hours: 24);

  Future<Credentials?> read(Service s) async {
    final user = await _storage.read(key: '${s.name}.username');
    final pass = await _storage.read(key: '${s.name}.password');
    if (user == null || pass == null) return null;
    return Credentials(user, pass);
  }

  Future<void> write(Service s, Credentials c) async {
    await _storage.write(key: '${s.name}.username', value: c.username);
    await _storage.write(key: '${s.name}.password', value: c.password);
    await _storage.delete(key: _refusedKey(s));
  }

  Future<void> clear(Service s) async {
    await _storage.delete(key: '${s.name}.username');
    await _storage.delete(key: '${s.name}.password');
    await _storage.delete(key: _refusedKey(s));
  }

  /// Remembers that [s] refused [c]. Only a hash of the login is stored.
  Future<void> markRefused(Service s, Credentials c) => _storage.write(
      key: _refusedKey(s), value: '${_fingerprint(c)} ${DateTime.now().millisecondsSinceEpoch}');

  /// Whether [s] refused exactly this login within [refusalLasts].
  Future<bool> isRefused(Service s, Credentials c) async {
    final parts = (await _storage.read(key: _refusedKey(s)))?.split(' ');
    if (parts == null || parts.length != 2 || parts.first != _fingerprint(c)) return false;
    final at = int.tryParse(parts.last);
    return at != null && DateTime.now().millisecondsSinceEpoch - at < refusalLasts.inMilliseconds;
  }

  static String _refusedKey(Service s) => '${s.name}.refused';

  static String _fingerprint(Credentials c) =>
      sha256.convert(utf8.encode('${c.username.trim()}\u0000${c.password}')).toString();
}
