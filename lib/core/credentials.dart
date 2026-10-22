import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/models.dart';

class Credentials {
  final String username;
  final String password;
  const Credentials(this.username, this.password);
}

/// Per-service logins, kept in the Android Keystore-backed secure storage.
/// Nothing here is ever logged or written to the cache.
class CredentialStore {
  final FlutterSecureStorage _storage;
  CredentialStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  Future<Credentials?> read(Service s) async {
    final user = await _storage.read(key: '${s.name}.username');
    final pass = await _storage.read(key: '${s.name}.password');
    if (user == null || pass == null) return null;
    return Credentials(user, pass);
  }

  Future<void> write(Service s, Credentials c) async {
    await _storage.write(key: '${s.name}.username', value: c.username);
    await _storage.write(key: '${s.name}.password', value: c.password);
  }

  Future<void> clear(Service s) async {
    await _storage.delete(key: '${s.name}.username');
    await _storage.delete(key: '${s.name}.password');
  }
}
