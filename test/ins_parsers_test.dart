import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/core/session.dart';
import 'package:inha_app/services/ins/ins_parsers.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();
List<int> fixtureBytes(String name) => File('test/fixtures/$name').readAsBytesSync();

const fakeJumin = 'FAKE-JUMIN-000000-0000000';

void main() {
  group('login page', () {
    test('hiddenInputs returns every hidden input of form1, in order', () {
      final hidden = hiddenInputs(fixture('ins_start.html'));
      expect(hidden.keys.toList(), [
        '__EVENTTARGET',
        '__EVENTARGUMENT',
        '__VIEWSTATE',
        '__VIEWSTATEGENERATOR',
        '__EVENTVALIDATION',
        'errorMessage',
        'hdnPublicKey',
      ]);
      expect(hidden['__VIEWSTATE'],
          '/wEPDwUKLTFBS0VWSUVXU1RBVEUPZBYCAgMPZBYCZg8PFgIeBFRleHQFBEZBS0VkZGQ+v1ewFAKE/9z+Q==');
      expect(hidden['__VIEWSTATEGENERATOR'], 'FA4E0001');
      expect(hidden['__EVENTVALIDATION'], '/wEdAAXFAKEeventVALIDATIONxx+yy/zz==');
      expect(hidden['__EVENTTARGET'], '');
      // Not hidden, or not in form1.
      expect(hidden.containsKey('txtInhaID'), isFalse);
      expect(hidden.containsKey('btnLogin'), isFalse);
      expect(hidden.containsKey('noticeToken'), isFalse);
    });

    test('hiddenInputs falls back to the whole page when form1 has none', () {
      const html = '<table><form id="form1"><tr><td>'
          '<input type="HIDDEN" name="__VIEWSTATE" value="vs">'
          '</td></tr></form></table>';
      expect(hiddenInputs(html), {'__VIEWSTATE': 'vs'});
    });

    test('formAction', () {
      expect(formAction(fixture('ins_start.html')), './Start.aspx');
      expect(formAction('<form id="form1"></form>'), isNull);
    });

    test('isInsLoginPage', () {
      expect(isInsLoginPage(fixture('ins_start.html')), isTrue);
      expect(isInsLoginPage(fixture('ins_start_error.html')), isTrue);
      expect(isInsLoginPage(fixture('ins_left.html')), isFalse);
      expect(isInsLoginPage(fixture('ins_rpx.html')), isFalse);
    });

    test('loginError reads the hidden errorMessage', () {
      expect(loginError(fixture('ins_start.html')), isNull);
      expect(loginError(fixture('ins_start_error.html')),
          'The ID or password is incorrect. (fake message)');
    });

    test('isSessionExpired', () {
      expect(isSessionExpired(fixture('ins_start.html')), isTrue);
      expect(isSessionExpired("<script>top.location.href='/ITIS/Start.aspx';</script>"), isTrue);
      expect(isSessionExpired('<script>location.replace("Start.aspx")</script>'), isTrue);
      expect(isSessionExpired('<p>Your session has expired.</p>'), isTrue);
      expect(isSessionExpired(fixture('ins_rpx.html')), isFalse);
      // left.aspx has a logout script, which is why callers look for the menu first.
      expect(isSessionExpired(fixture('ins_left.html')), isTrue);
    });
  });

  group('menu', () {
    final left = fixture('ins_left.html');

    test('findMenuLink resolves each documented item against /ITIS/', () {
      expect(findMenuLink(left, 'View Grades and Standings'),
          '/ITIS/main.aspx?param=FAKEgRaD3s+St4nd/1ngs==&ENGYN=Y');
      expect(findMenuLink(left, 'Personal Information'),
          '/ITIS/main.aspx?param=FAKEpErS0nAL1nf0x9Kq&ENGYN=Y');
      expect(findMenuLink(left, 'Browse Course Syllabus'),
          '/ITIS/main.aspx?param=FAKEsYlLaBuS77Qw0pZ&ENGYN=Y');
      expect(findMenuLink(left, 'Browse Course Timetable'),
          '/ITIS/main.aspx?param=FAKEt1meTaBLe4Rt5nM&ENGYN=N');
      expect(findMenuLink(left, 'Confirm Course Registration'),
          '/ITIS/main.aspx?param=FAKEc0nF1rMreG8uV2s&ENGYN=Y');
    });

    test('findMenuLink: case-insensitive fallback, unknown text, javascript links', () {
      expect(findMenuLink(left, 'view grades and standings'),
          '/ITIS/main.aspx?param=FAKEgRaD3s+St4nd/1ngs==&ENGYN=Y');
      expect(findMenuLink(left, 'View Grades'), isNull);
      expect(findMenuLink(left, 'Logout'), isNull); // href="#", no .aspx in onclick
      const js = '<a href="javascript:void(0)" onclick="go(\'main.aspx?param=J&amp;ENGYN=Y\')">'
          'View Grades and Standings</a>';
      expect(findMenuLink(js, 'View Grades and Standings'), '/ITIS/main.aspx?param=J&ENGYN=Y');
      expect(findMenuLink('<a href="/ITIS/main.aspx?param=A">X</a>', 'X'), '/ITIS/main.aspx?param=A');
    });

    test('findMenuLink: menu written by script', () {
      const scripted = '<script>document.write("<li><a href=\\"main.aspx?param=P1&amp;ENGYN=Y\\">'
          'Personal Information</a></li>");'
          "menu.innerHTML += '<li><a href=\"main.aspx?param=G+r/9==&ENGYN=Y\" target=\"main\">"
          "<span></span>View Grades and Standings</a></li>';</script>";
      expect(findMenuLink(scripted, 'View Grades and Standings'),
          '/ITIS/main.aspx?param=G+r/9==&ENGYN=Y');
      expect(findMenuLink(scripted, 'Personal Information'), '/ITIS/main.aspx?param=P1&ENGYN=Y');
      expect(findMenuLink(scripted, 'Standings'), isNull);
      expect(hasMenuLinks(scripted), isTrue);
    });

    test('hasMenuLinks', () {
      expect(hasMenuLinks(left), isTrue);
      expect(hasMenuLinks(fixture('ins_start.html')), isFalse);
    });
  });

  group('report pages', () {
    test('extractXmlUrl reads the raw page: ViewerReportInForm second argument, as written', () {
      expect(extractXmlUrl(fixture('ins_rpx.html')), 'MarkView_xml.aspx?Value=FAKE0T0KEN0abc%3d');
    });

    test('extractXmlUrl: browser-built fileurl assignment (live DOM) still works', () {
      expect(
          extractXmlUrl("<script>window.frm.fileurl.value = '';\n"
              "window.frm.fileurl.value = 'https://ins.inha.uz/ITIS/STD/SJ/SJ_51001/MarkView_xml.aspx?Value=T';</script>"),
          'https://ins.inha.uz/ITIS/STD/SJ/SJ_51001/MarkView_xml.aspx?Value=T');
    });

    test('extractXmlUrl: double quotes, escaped slashes, input fallback, absent', () {
      expect(extractXmlUrl('<script>window.frm.fileurl.value="a\\/b.aspx?Value=1";</script>'),
          'a/b.aspx?Value=1');
      expect(
          extractXmlUrl('<form name="frm"><input type="hidden" name="fileurl" value="x.aspx?Value=2"></form>'),
          'x.aspx?Value=2');
      expect(extractXmlUrl(fixture('ins_left.html')), isNull);
      expect(extractXmlUrl("<script>window.frm.fileurl.value = '';</script>"), isNull);
    });

    test('pageRefs finds frames first, then quoted references', () {
      const frameset = '<frameset rows="0,*"><frame src="blank.htm">'
          '<frame name="body" src="STD/SJ/SJ_51001/MarkView.aspx"></frameset>';
      expect(pageRefs(frameset, 'markview'), ['STD/SJ/SJ_51001/MarkView.aspx']);
      const markView = '<form action="./MarkView.aspx"></form>'
          '<iframe id="rpt" src="MarkView_rpx.aspx?gubun=inform"></iframe>';
      expect(pageRefs(markView, 'markview_rpx'), ['MarkView_rpx.aspx?gubun=inform']);
      expect(pageRefs(markView, 'markview'),
          ['MarkView_rpx.aspx?gubun=inform', './MarkView.aspx']);
      expect(pageRefs("<script>location.href = 'STD/SJ/SJ_51001/MarkView.aspx';</script>", 'markview'),
          ['STD/SJ/SJ_51001/MarkView.aspx']);
    });
  });

  group('grades XML', () {
    test('decodeInsBytes: ASCII, UTF-8, and EUC-KR via Latin-1', () {
      expect(decodeInsBytes(ascii.encode('<a>1</a>')), '<a>1</a>');
      expect(decodeInsBytes(utf8.encode('﻿café')), 'café');
      // EUC-KR bytes are not valid UTF-8: ASCII around them must survive.
      expect(decodeInsBytes([0x41, 0xC1, 0xA4, 0xBA, 0xB8, 0x42]), 'AÁ¤º¸B');
    });

    test('parses the fixture', () {
      final report = parseGradesBytes(fixtureBytes('ins_grades.xml'));
      expect(report.gpa, closeTo(3.558824, 1e-9));
      expect(report.creditsEarned, 17.0);
      expect(report.yearOfStudy, 2); // MAIN/GRADE, not MARK/GRADE
      expect(report.records, hasLength(8));

      final first = report.records.first;
      expect(first.term, '2025 Fall Semester');
      expect(first.termKey, 20251);
      expect(first.code, 'CSE1001');
      expect(first.name, 'Introduction to Programming');
      expect(first.credits, 3.0);
      expect(first.letter, 'A+');
      expect(first.points, 4.5);
      expect(first.category, 'MR-M');
      expect(first.graded, isTrue);

      expect(report.records.map((r) => r.termKey).toSet(), {20251, 20252, 20261});
      expect(report.records[4].name, 'Signals & Systems');
      expect(report.records[4].letter, 'C+');
      expect(report.records[5].points, 3.0);

      final current = report.records.where((r) => r.termKey == 20261).toList();
      expect(current, hasLength(2));
      for (final r in current) {
        expect(r.term, 'Current Semester');
        expect(r.letter, '-');
        expect(r.graded, isFalse);
        expect(r.points, 0);
      }

      final graded = report.records.where((r) => r.graded);
      final credits = graded.fold<double>(0, (s, r) => s + r.credits);
      final points = graded.fold<double>(0, (s, r) => s + r.credits * r.points);
      expect(credits, report.creditsEarned);
      expect(points / credits, closeTo(report.gpa, 1e-6));
    });

    test('never carries JUMIN', () {
      final xml = decodeInsBytes(fixtureBytes('ins_grades.xml'));
      expect(xml, contains(fakeJumin)); // the fixture does have it...
      final json = jsonEncode(parseGrades(xml).toJson());
      expect(json, isNot(contains(fakeJumin))); // ...the report does not
      expect(json, isNot(contains('000000-0000000')));
      expect(json.toLowerCase(), isNot(contains('jumin')));
    });

    test('MAIN fields are direct children; MARKs may sit beside MAIN', () {
      const xml = '<NewDataSet>'
          '<MAIN><MARK><GRADE>7</GRADE><YEARTERM>20241</YEARTERM><HAKSU_NO>X1</HAKSU_NO>'
          '<MARKS>B0</MARKS><JUMSU>3.00</JUMSU><CREDIT>1.0</CREDIT></MARK>'
          '<GRADE>Junior</GRADE><COM_PYUNG>3.0</COM_PYUNG><COM_CREDIT>1.0</COM_CREDIT>'
          '<JUMIN>secret<GRADE>9</GRADE></JUMIN></MAIN>'
          '<MARK><YEARTERM>20242</YEARTERM><HAKSU_NO>X2</HAKSU_NO><MARKS></MARKS></MARK>'
          '</NewDataSet>';
      final r = parseGrades(xml);
      expect(r.yearOfStudy, 3); // "Junior"; MARK's 7 and JUMIN's 9 ignored
      expect(r.records.map((e) => e.code), ['X1', 'X2']);
      expect(r.records[0].term, '20241'); // no DISPLAY_YEARTERM -> YEARTERM
      expect(r.records[1].letter, '-'); // empty MARKS -> not graded
    });

    test('non-XML responses are a ParseError', () {
      expect(() => parseGrades(fixture('ins_start.html')), throwsA(isA<ParseError>()));
      expect(() => parseGrades(''), throwsA(isA<ParseError>()));
      expect(() => parseGrades('<html><body><main>hi</main></body></html>'),
          throwsA(isA<ParseError>()));
    });

    test('an XML with no courses yet is still a report', () {
      final r = parseGrades('<root><MAIN><GRADE>1</GRADE><COM_PYUNG>0</COM_PYUNG>'
          '<COM_CREDIT>0</COM_CREDIT></MAIN></root>');
      expect(r.records, isEmpty);
      expect(r.yearOfStudy, 1);
    });
  });
}
