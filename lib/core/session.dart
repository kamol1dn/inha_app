import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';

/// Certificates accepted even though normal validation rejects them, pinned
/// by host and SHA-256 of the DER bytes. ins.inha.uz still serves the
/// *.inha.uz RapidSSL certificate that expired on 2024-11-16. Pinning that
/// exact certificate keeps the connection encrypted and unforgeable; if IUT
/// renews it, the new one passes normal validation and this is never asked.
/// Approved by the user on 2026-10-22.
const pinnedExpiredCerts = {
  'ins.inha.uz': 'c657e8b75a4c6dd1c3358b38a516d307c12fa0245e02556b25adce0b83df7ca0',
};

bool acceptPinnedCert(X509Certificate cert, String host) {
  final pin = pinnedExpiredCerts[host];
  return pin != null && sha256.convert(cert.der).toString() == pin;
}

/// Thrown when a service rejects the saved login (wrong password, or none saved).
class LoginRequired implements Exception {
  final Service service;
  final String message;
  LoginRequired(this.service, [this.message = 'Login needed']);
  @override
  String toString() => '${service.label}: $message';
}

/// Thrown when a page loaded but did not look like we expected, which
/// usually means the site changed. Carries enough to debug, never page content.
class ParseError implements Exception {
  final String what;
  ParseError(this.what);
  @override
  String toString() => 'Could not read $what';
}

/// One Dio per service, each with its own persistent cookie jar so sessions
/// survive app restarts and a fresh login is only needed when one expires.
class Sessions {
  final Map<Service, Dio> _clients = {};
  late final String _cookieDir;

  // Desktop on purpose: Coursemos serves a different theme to mobile agents,
  // and the parsers are written against the desktop markup.
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/155.0 Safari/537.36';

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    _cookieDir = '${dir.path}${Platform.pathSeparator}cookies';
  }

  Dio client(Service s) => _clients.putIfAbsent(s, () {
        final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'User-Agent': _userAgent},
          // Logins answer with redirects; callers inspect them.
          followRedirects: true,
          validateStatus: (code) => code != null && code < 500,
        ));
        dio.httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () => HttpClient()
            ..badCertificateCallback = (cert, host, port) => acceptPinnedCert(cert, host),
        );
        dio.interceptors.add(CookieManager(
          PersistCookieJar(storage: FileStorage('$_cookieDir/${s.name}/')),
        ));
        return dio;
      });

  /// Forget a service's cookies, e.g. after the user changes its login.
  Future<void> reset(Service s) async {
    final dio = _clients.remove(s);
    for (final i in dio?.interceptors ?? const <Interceptor>[]) {
      if (i is CookieManager) await i.cookieJar.deleteAll();
    }
  }
}
