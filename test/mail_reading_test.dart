import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/data/app_data.dart';
import 'package:inha_app/features/link_text.dart';
import 'package:inha_app/ui/format/format.dart';

import 'fakes.dart';

void main() {
  group('findLinks', () {
    List<(String, String)> links(String text) =>
        [for (final l in findLinks(text)) (l.label, l.uri.toString())];

    test('web addresses, with sentence punctuation left out', () {
      expect(links('Slides: https://eclass.inha.ac.kr/mod/ubfile/view.php?id=91234. Thanks'),
          [('https://eclass.inha.ac.kr/mod/ubfile/view.php?id=91234', 'https://eclass.inha.ac.kr/mod/ubfile/view.php?id=91234')]);
      expect(links('(see https://iut.uz/en/news)'), [('https://iut.uz/en/news', 'https://iut.uz/en/news')]);
      expect(links('Wiki: https://en.wikipedia.org/wiki/JPEG_(format), page 2'),
          [('https://en.wikipedia.org/wiki/JPEG_(format)', 'https://en.wikipedia.org/wiki/JPEG_(format)')]);
    });

    test('links Exchange wrote as label<url> show only the host', () {
      const text = 'Register here<https://forms.office.com/r/abc123?utm_source=x> by Friday';
      final l = findLinks(text).single;
      expect(l.label, ' forms.office.com');
      expect(l.uri.toString(), 'https://forms.office.com/r/abc123?utm_source=x');
      expect(text.substring(l.start, l.end), '<https://forms.office.com/r/abc123?utm_source=x>');
      expect(links('Write to the office <mailto:registrar@inha.uz>'),
          [('registrar@inha.uz', 'mailto:registrar@inha.uz')]);
    });

    test('www. gets https; mail addresses become mailto', () {
      expect(links('Visit www.inha.uz, or write to registrar@inha.uz.'), [
        ('www.inha.uz', 'https://www.inha.uz'),
        ('registrar@inha.uz', 'mailto:registrar@inha.uz'),
      ]);
    });

    test('plain text has none', () {
      expect(findLinks('Room B-304 at 15:00. Bring a laptop.'), isEmpty);
      expect(findLinks(''), isEmpty);
    });
  });

  test('fileSize', () {
    expect(fileSize(812), '812 B');
    expect(fileSize(48213), '47 KB');
    expect(fileSize(2411724), '2.3 MB');
    expect(fileSize(18874368), '18 MB');
  });

  group('AppData mail', () {
    test('refresh loads the first page and the server unread count', () async {
      final (data, _, _, _, mail) = await makeAppData();
      mail.all = [for (var i = 0; i < 45; i++) mailHeader(i, unread: i < 3)];
      mail.unread = 7; // counts unread mail beyond the first page too
      await data.refreshMail();
      expect(data.inbox.data!.value, hasLength(AppData.mailPageSize));
      expect(data.mailUnread.data!.value, 7);
      expect(data.mailHasMore, isTrue);
      expect(mail.pages, [(30, 0)]);
    });

    test('load more appends the next page and stops at the end', () async {
      final (data, _, _, _, mail) = await makeAppData();
      mail.all = [for (var i = 0; i < 45; i++) mailHeader(i)];
      await data.refreshMail();
      await data.loadMoreMail();
      expect(data.inbox.data!.value.map((m) => m.id), [for (var i = 0; i < 45; i++) 'id$i']);
      expect(data.mailHasMore, isFalse);
      await data.loadMoreMail(); // nothing left: no request
      expect(mail.pages, [(30, 0), (30, 30)]);
    });

    test('a failed page keeps what is loaded and can be retried', () async {
      final (data, _, _, _, mail) = await makeAppData();
      mail.all = [for (var i = 0; i < 40; i++) mailHeader(i)];
      await data.refreshMail();
      mail.error = Exception('offline');
      await data.loadMoreMail();
      expect(data.inbox.data!.value, hasLength(30));
      expect(data.mailMoreError, isNotNull);
      mail.error = null;
      await data.loadMoreMail();
      expect(data.inbox.data!.value, hasLength(40));
      expect(data.mailMoreError, isNull);
    });

    test('marking read updates the server, the row and the count, and survives a restart', () async {
      final (data, _, _, _, mail) = await makeAppData();
      mail.all = [mailHeader(0, unread: true), mailHeader(1, unread: true)];
      mail.unread = 2;
      await data.refreshMail();
      final fetchedAt = data.inbox.data!.fetchedAt;

      await data.setMailRead('id0');
      expect(mail.marked, [('id0', true)]);
      expect(data.inbox.data!.value.map((m) => m.unread), [false, true]);
      expect(data.mailUnread.data!.value, 1);
      expect(data.inbox.data!.fetchedAt, fetchedAt); // an edit, not a fetch

      await data.setMailRead('id0', read: false);
      expect(data.inbox.data!.value.first.unread, isTrue);
      expect(data.mailUnread.data!.value, 2);

      await data.setMailRead('id1');
      await data.reloadFromCache();
      expect(data.inbox.data!.value.map((m) => m.unread), [true, false]);
      expect(data.mailUnread.data!.value, 1);
    });

    test('a refused mark-read changes nothing here', () async {
      final (data, _, _, _, mail) = await makeAppData();
      mail.all = [mailHeader(0, unread: true)];
      mail.unread = 1;
      await data.refreshMail();
      mail.error = Exception('refused');
      await expectLater(data.setMailRead('id0'), throwsException);
      expect(data.inbox.data!.value.single.unread, isTrue);
      expect(data.mailUnread.data!.value, 1);
    });
  });
}
