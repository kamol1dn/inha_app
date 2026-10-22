import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/cache.dart';
import 'core/credentials.dart';
import 'core/session.dart';
import 'data/app_data.dart';
import 'models/models.dart';
import 'services/eclass/eclass_client.dart';
import 'services/edupage/edupage_client.dart';
import 'services/ins/ins_client.dart';
import 'services/mail/ews_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sessions = Sessions();
  await sessions.init();
  final prefs = Prefs(await SharedPreferences.getInstance());
  final credentials = CredentialStore();
  final data = AppData(
    eclass: EclassClient(sessions, credentials),
    timetable: EdupageClient(sessions.client(Service.edupage)),
    ins: InsClient(sessions, credentials),
    mail: EwsClient(sessions.client(Service.mail), credentials),
    cache: await JsonCache.open(),
    prefs: prefs,
  );
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: data),
      Provider.value(value: sessions),
      Provider.value(value: credentials),
    ],
    child: const InhaApp(),
  ));
  data.refreshAll();
}
