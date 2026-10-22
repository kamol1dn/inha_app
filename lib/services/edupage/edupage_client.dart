import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/session.dart' show ParseError;
import '../../models/models.dart';
import 'timetable_api.dart';
import 'timetable_parser.dart';

/// [TimetableApi] over the public EduPage RPC endpoints (docs/ENDPOINTS.md).
///
/// Production passes `Sessions().client(Service.edupage)`; tests pass a Dio
/// with a fake adapter. Every call fetches fresh data (the whole university's
/// timetable, about 400 KB); caching is the caller's job.
class EdupageClient implements TimetableApi {
  EdupageClient(this._dio, {this.year, this.baseUrl = 'https://iut.edupage.org'});

  final Dio _dio;

  /// School year sent to `getTTViewerData`, e.g. 2026. Usually leave it null:
  /// then the newest visible timetable is used, which survives the year
  /// rolling over.
  final int? year;

  final String baseUrl;

  /// The RPCs answer without it today, but the reference script (and the
  /// public page) load /timetable/ first for its PHPSESSID. Once per client is
  /// enough, since the production Dio keeps cookies.
  bool _warmedUp = false;

  @override
  Future<List<Lesson>> lessons(String classGroup, {Set<String> excludeSubjects = const {}}) async =>
      lessonsFor(await _tables(), classGroup, excludeSubjects: excludeSubjects);

  @override
  Future<List<String>> classGroups() async => classGroupsIn(await _tables());

  Future<EdupageTables> _tables() async {
    // The server rejects a bare [null]; with no year the second arg is {}.
    final viewer = await _rpc('ttviewer.js', 'getTTViewerData', [null, year ?? <String, Object?>{}]);
    final ttNum = chooseTtNum(viewer);
    return parseTables(await _rpc('regulartt.js', 'regularttGetData', [null, ttNum]));
  }

  Map<String, String> get _headers => {'Referer': '$baseUrl/timetable/'};

  Future<Object?> _rpc(String script, String func, List<Object?> args) async {
    if (!_warmedUp) {
      await _dio.get<String>(
        '$baseUrl/timetable/',
        options: Options(
          headers: _headers,
          responseType: ResponseType.plain,
          validateStatus: (_) => true, // only for the cookie; the RPC decides
        ),
      );
      _warmedUp = true;
    }

    final res = await _dio.post<Object?>(
      '$baseUrl/timetable/server/$script?__func=$func',
      data: {'__args': args, '__gsh': '00000000'},
      options: Options(
        headers: _headers,
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    if (res.statusCode != 200) {
      throw DioException.badResponse(
        statusCode: res.statusCode ?? 0,
        requestOptions: res.requestOptions,
        response: res,
      );
    }

    var body = res.data;
    if (body is String) {
      try {
        body = jsonDecode(body);
      } on FormatException {
        throw ParseError('EduPage $func reply');
      }
    }
    // A rejected call answers 200 with {"e": "Error: ..."} and no "r".
    if (body is! Map || !body.containsKey('r')) throw ParseError('EduPage $func reply');
    return body;
  }
}
