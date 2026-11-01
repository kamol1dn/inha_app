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

export '../core/session.dart' show isNetworkError, isServerError, isWorthRetrying;

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
    final eclass = EclassClient(sessions, credentials);
    final ins = InsClient(sessions, credentials);
    final data = AppData(
      eclass: eclass,
      timetable: EdupageClient(sessions.client(Service.edupage)),
      ins: ins,
      mail: EwsClient(sessions.client(Service.mail), credentials),
      cache: await JsonCache.open(),
      prefs: Prefs(await SharedPreferences.getInstance()),
    );
    eclass.loginStep = (login) => data.sync.step('eClass', 'signing in', login);
    ins.loginStep = (login) => data.sync.step('INS', 'signing in', login);
    data.hasLogin = (s) async => await credentials.read(s) != null;
    return AppServices(data, sessions, credentials);
  }
}

