/*
 * Тесты сервиса дат — на нём держатся порядок дней в расписании,
 * фильтрация архива и заголовки экрана.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilapp/services/date_service.dart';

void main() {
  group('parseScheduleDate', () {
    test('разбирает формат хранения dd.MM.yyyy', () {
      final date = DateService.parseScheduleDate('05.09.2026');
      expect(date.day, 5);
      expect(date.month, 9);
      expect(date.year, 2026);
    });

    test('разбирает формат сайта колледжа dd-МММ', () {
      final date = DateService.parseScheduleDate('03-сен');
      expect(date.day, 3);
      expect(date.month, 9);
    });

    test('понимает сокращения разной длины и точку в конце', () {
      // Реальные значения, встреченные в базе на устройстве:
      // "3-сент." роняло разбор с "Неизвестный месяц: сент".
      for (final raw in ['3-сен', '3-сент', '3-сент.', '3-сентября']) {
        final date = DateService.parseScheduleDate(raw);
        expect(date.day, 3, reason: raw);
        expect(date.month, 9, reason: raw);
      }
    });

    test('различает март и май по префиксу', () {
      expect(DateService.parseScheduleDate('5-мар').month, 3);
      expect(DateService.parseScheduleDate('5-марта').month, 3);
      expect(DateService.parseScheduleDate('5-май').month, 5);
      expect(DateService.parseScheduleDate('5-мая').month, 5);
    });

    test('бросает исключение на мусорной строке', () {
      expect(
        () => DateService.parseScheduleDate('Дата'),
        throwsFormatException,
      );
    });
  });

  group('sortDateKeys', () {
    test('сортирует хронологически, а не как текст', () {
      // Текстовая сортировка поставила бы 01.10 перед 02.09 —
      // именно из-за этого дни в расписании шли не по порядку.
      final sorted = DateService.sortDateKeys([
        '01.10.2026',
        '02.09.2026',
        '15.09.2026',
      ]);

      expect(sorted, ['02.09.2026', '15.09.2026', '01.10.2026']);
    });

    test('сортирует корректно через границу года', () {
      final sorted = DateService.sortDateKeys(['05.01.2027', '28.12.2026']);

      expect(sorted, ['28.12.2026', '05.01.2027']);
    });

    test('не теряет элементы и уводит нераспознанные даты в конец', () {
      final sorted = DateService.sortDateKeys([
        'мусор',
        '02.09.2026',
        '01.09.2026',
      ]);

      expect(sorted.length, 3);
      expect(sorted.first, '01.09.2026');
      expect(sorted.last, 'мусор');
    });

    test('устраняет дубликаты ключей', () {
      final sorted = DateService.sortDateKeys(['01.09.2026', '01.09.2026']);

      expect(sorted, ['01.09.2026']);
    });

    test('пустой вход даёт пустой список', () {
      expect(DateService.sortDateKeys(const []), isEmpty);
    });
  });

  group('isActualDate', () {
    test('сегодняшний день считается актуальным', () {
      final today = DateService.formatDateForStorage(DateTime.now());
      expect(DateService.isActualDate(today), isTrue);
    });

    test('вчерашний день не актуален', () {
      final yesterday = DateService.formatDateForStorage(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(DateService.isActualDate(yesterday), isFalse);
    });

    test('завтрашний день актуален', () {
      final tomorrow = DateService.formatDateForStorage(
        DateTime.now().add(const Duration(days: 1)),
      );
      expect(DateService.isActualDate(tomorrow), isTrue);
    });

    test('некорректная дата не считается актуальной', () {
      expect(DateService.isActualDate('не дата'), isFalse);
    });
  });

  group('shouldDeleteFromArchive', () {
    test('свежая запись остаётся', () {
      final recent = DateService.formatDateForStorage(
        DateTime.now().subtract(const Duration(days: 5)),
      );
      expect(DateService.shouldDeleteFromArchive(recent, 30), isFalse);
    });

    test('запись старше срока хранения удаляется', () {
      final old = DateService.formatDateForStorage(
        DateTime.now().subtract(const Duration(days: 60)),
      );
      expect(DateService.shouldDeleteFromArchive(old, 30), isTrue);
    });

    test('нечитаемая дата помечается на удаление', () {
      expect(DateService.shouldDeleteFromArchive('???', 30), isTrue);
    });
  });

  group('formatDateForStorage / isSameDay', () {
    test('формат хранения дополняется нулями', () {
      expect(
        DateService.formatDateForStorage(DateTime(2026, 1, 2)),
        '02.01.2026',
      );
    });

    test('isSameDay игнорирует время', () {
      expect(
        DateService.isSameDay(
          DateTime(2026, 9, 3, 8, 30),
          DateTime(2026, 9, 3, 23, 59),
        ),
        isTrue,
      );
    });
  });
}
