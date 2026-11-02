import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/features/update_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// GitHub's answer without the network; a null body is a failed request.
class _Answer implements HttpClientAdapter {
  _Answer(this.body);
  final Map<String, dynamic>? body;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (body == null) return ResponseBody.fromString('{}', 500);
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('isNewerVersion', () {
    test('compares each part as a number', () {
      expect(isNewerVersion('1.4.0', '1.3.0'), isTrue);
      expect(isNewerVersion('1.10.0', '1.9.0'), isTrue);
      expect(isNewerVersion('2.0.0', '1.99.99'), isTrue);
      expect(isNewerVersion('1.3.0', '1.4.0'), isFalse);
    });

    test('the same version is not newer, whatever its tag or build number says', () {
      expect(isNewerVersion('v1.4.0', '1.4.0'), isFalse);
      expect(isNewerVersion('1.4.0+9', '1.4.0+5'), isFalse);
      expect(isNewerVersion('v1.4.1', '1.4.0+5'), isTrue);
    });

    test('a tag that is not a version is never newer', () {
      expect(isNewerVersion('nightly', '1.4.0'), isFalse);
      expect(isNewerVersion('', '1.4.0'), isFalse);
    });
  });

  group('fetchLatestVersion', () {
    Dio answering(Map<String, dynamic> body) => Dio()
      ..httpClientAdapter = _Answer(body);

    test('reads the tag of a release that holds an APK', () async {
      final dio = answering({
        'tag_name': 'v1.4.0',
        'assets': [
          {'name': 'iut-eclass-chrome-1.4.0.zip'},
          {'name': 'app-arm64-v8a-release.apk'},
        ],
      });
      expect(await fetchLatestVersion(dio), '1.4.0');
    });

    test('a release without an APK yet is not news', () async {
      final dio = answering({
        'tag_name': 'v1.4.0',
        'assets': [
          {'name': 'iut-eclass-chrome-1.4.0.zip'},
        ],
      });
      expect(await fetchLatestVersion(dio), isNull);
    });

    test('no answer gives null', () async {
      final dio = Dio()..httpClientAdapter = _Answer(null);
      expect(await fetchLatestVersion(dio), isNull);
    });
  });

  group('asking', () {
    Future<BuildContext> host(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      return tester.element(find.byType(SizedBox));
    }

    Future<void> ask(BuildContext context, String? newest) =>
        promptForUpdate(context, latest: () async => newest, current: () async => '1.3.0');

    testWidgets('a newer version asks once, and offers the releases page', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final context = await host(tester);
      await tester.runAsync(() => SharedPreferences.getInstance());

      ask(context, '1.4.0');
      await tester.pumpAndSettle();
      expect(find.text('New version available'), findsOneWidget);
      expect(find.textContaining('Version 1.4.0 is out. You have 1.3.0.'), findsOneWidget);
      expect(find.text('Open releases'), findsOneWidget);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('New version available'), findsNothing);

      ask(context, '1.4.0');
      await tester.pumpAndSettle();
      expect(find.text('New version available'), findsNothing);

      ask(context, '1.5.0');
      await tester.pumpAndSettle();
      expect(find.textContaining('Version 1.5.0 is out.'), findsOneWidget);
    });

    testWidgets('no newer version, or no answer from GitHub, says nothing', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final context = await host(tester);
      ask(context, '1.3.0');
      await tester.pumpAndSettle();
      ask(context, null);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('checking from Settings always answers', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final context = await host(tester);
      Future<void> check(String? newest) =>
          checkForUpdateNow(context, latest: () async => newest, current: () async => '1.4.0');

      check('1.4.0');
      await tester.pump();
      await tester.pump();
      expect(find.text('You have the latest version, 1.4.0.'), findsOneWidget);
      ScaffoldMessenger.of(context).clearSnackBars();

      check(null);
      await tester.pump();
      await tester.pump();
      expect(find.text("Couldn't reach GitHub. Check the connection."), findsOneWidget);
      ScaffoldMessenger.of(context).clearSnackBars();

      check('1.5.0');
      await tester.pumpAndSettle();
      expect(find.text('New version available'), findsOneWidget);
    });
  });
}
