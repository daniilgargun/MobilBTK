import 'package:flutter_test/flutter_test.dart';
import 'package:mobilapp/services/remote_config_service.dart';

/// Конфиг задаётся руками в консоли, поэтому единственная реальная защита
/// от опечатки — то, что испорченное значение молча заменяется рабочим.
void main() {
  group('ParserColumns.fromJson', () {
    test('пустая строка даёт значения по умолчанию', () {
      final columns = ParserColumns.fromJson('');
      expect(columns.date, 0);
      expect(columns.subgroup, 6);
    });

    test('разбирает полный набор колонок', () {
      final columns = ParserColumns.fromJson(
        '{"date":1,"group":2,"number":3,"subject":4,'
        '"teacher":5,"classroom":6,"subgroup":7}',
      );
      expect(columns.date, 1);
      expect(columns.classroom, 6);
      expect(columns.subgroup, 7);
    });

    test('пропущенное поле берётся из значений по умолчанию', () {
      final columns = ParserColumns.fromJson('{"teacher":9}');
      expect(columns.teacher, 9);
      expect(columns.subject, 3);
    });

    test('нечисловое и отрицательное значение игнорируются', () {
      final columns = ParserColumns.fromJson('{"date":"первая","group":-1}');
      expect(columns.date, 0);
      expect(columns.group, 1);
    });

    test('поломанный JSON не роняет разбор', () {
      final columns = ParserColumns.fromJson('{это не json');
      expect(columns.date, 0);
      expect(columns.teacher, 4);
    });

    test('requiredCount учитывает самую правую обязательную колонку', () {
      expect(ParserColumns.defaults.requiredCount, 6);
      expect(ParserColumns.fromJson('{"classroom":9}').requiredCount, 10);
    });
  });

  group('sanitizeUrl', () {
    test('пустое значение оставляет вшитый адрес', () {
      expect(RemoteConfigService.sanitizeUrl(''), AppConfig.defaultScheduleUrl);
      expect(
        RemoteConfigService.sanitizeUrl(null),
        AppConfig.defaultScheduleUrl,
      );
    });

    test('http и мусор отвергаются: расписание грузим только по https', () {
      expect(
        RemoteConfigService.sanitizeUrl('http://bartc.by/rasp'),
        AppConfig.defaultScheduleUrl,
      );
      expect(
        RemoteConfigService.sanitizeUrl('bartc.by/rasp'),
        AppConfig.defaultScheduleUrl,
      );
    });

    test('корректный https-адрес принимается', () {
      expect(
        RemoteConfigService.sanitizeUrl(' https://bartc.by/new-page '),
        'https://bartc.by/new-page',
      );
    });
  });

  group('parseAnnouncement', () {
    test('пустое значение означает отсутствие объявления', () {
      expect(RemoteConfigService.parseAnnouncement('').isEmpty, isTrue);
      expect(RemoteConfigService.parseAnnouncement(null).isEmpty, isTrue);
    });

    test('объявление без текста не показывается', () {
      final announcement = RemoteConfigService.parseAnnouncement(
        '{"id":"1","url":"https://t.me/Daniilgargun"}',
      );
      expect(announcement.isEmpty, isTrue);
    });

    test('разбирает текст, ссылку и идентификатор', () {
      final announcement = RemoteConfigService.parseAnnouncement(
        '{"id":"site-moved","text":"Сайт колледжа переехал",'
        '"url":"https://bartc.by"}',
      );
      expect(announcement.id, 'site-moved');
      expect(announcement.text, 'Сайт колледжа переехал');
      expect(announcement.url, 'https://bartc.by');
      expect(announcement.isEmpty, isFalse);
    });

    test('без id он выводится из текста, иначе объявление не закрыть', () {
      final announcement = RemoteConfigService.parseAnnouncement(
        '{"text":"Проверка связи"}',
      );
      expect(announcement.id, isNotEmpty);
      expect(announcement.isEmpty, isFalse);
    });
  });
}
