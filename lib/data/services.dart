import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/cache.dart';
import '../core/credentials.dart';
import '../core/session.dart';
import '../models/models.dart';
import '../services/eclass/eclass_client.dart';
import '../services/edupage/edupage_client.dart';
import '../services/ins/ins_client.dart';
import '../services/mail/ews_client.dart';
import 'app_data.dart';

/// Everything the app runs on, built from persistent state only (cookie
/// jars, the credential store, the JSON cache). The UI and the background
/// refresh both start here, because a background isolate shares no memory
/// with the UI.
class AppServices {
  final AppData data;
  final Sessions sessions;
  final CredentialStore credentials;
  const AppServices(this.data, this.sessions, this.credentials);

  static Future<AppServices> open() async {
    final sessions = Sessions();
    await sessions.init();
    final credentials = CredentialStore();
    final data = AppData(
      eclass: EclassClient(sessions, credentials),
      timetable: EdupageClient(sessions.client(Service.edupage)),
      ins: InsClient(sessions, credentials),
      mail: EwsClient(sessions.client(Service.mail), credentials),
      cache: await JsonCache.open(),
      prefs: Prefs(await SharedPreferences.getInstance()),
    );
    return AppServices(data, sessions, credentials);
  }
}

/// A failure worth retrying soon: the network, not the login or the page.
bool isNetworkError(Object? e) =>
    e is DioException &&
    (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout);
