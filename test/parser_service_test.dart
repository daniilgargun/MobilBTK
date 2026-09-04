/*
 * Тесты разбора страницы расписания.
 *
 * Парсер — самая хрупкая часть приложения: данных нет ни в каком API,
 * они вытаскиваются из HTML сайта колледжа. Разметка ниже повторяет
 * реальную структуру страницы: строка заголовка на <th>, семь колонок
 * (Дата, Группа, Пара, Дисциплина, Преподаватель, Кабинет, Подгр),
 * дата в формате "dd-МММ", подгруппа "0" вместо пустой.
 */

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilapp/services/parser_service.dart';
import 'package:mobilapp/services/remote_config_service.dart';

String page(String rows) {
  return '''
<html><body>
<table>
  <tr>
    <th>Дата</th><th>Группа</th><th>Пара</th><th>Дисциплина</th>
    <th>Преподаватель</th><th>Кабинет</th><th>Подгр</th>
  </tr>
  $rows
</table>
</body></html>
''';
}

String row(
  String date,
  String group,
  String number,
  String subject,
  String teacher,
  String classroom,
  String subgroup,
) {
  return '<tr><td>$date</td><td>$group</td><td>$number</td>'
      '<td>$subject</td><td>$teacher</td><td>$classroom</td>'
      '<td>$subgroup</td></tr>';
}

void main() {
  final year = DateTime.now().year;

  group('раскладка колонок из конфига', () {
    // Ради этого случая раскладка и вынесена в конфиг: если колледж
    // вставит колонку в начало таблицы, все поля съедут на одну позицию,
    // и приложение начнёт показывать преподавателя в графе предмета.
    String shiftedRow() {
      return '<tr><td>#</td><td>03-сен</td><td>205</td><td>1</td>'
          '<td>Математика</td><td>Иванов И.И.</td><td>202</td>'
          '<td>0</td></tr>';
    }

    test('со вшитой раскладкой сдвинутая таблица разбирается неверно', () {
      final result = ParserService.parseHtmlForTest(page(shiftedRow()));

      // Группой стала дата — ровно та поломка, от которой защищаемся.
      expect(result.groups, isNot(contains('205')));
    });

    test('сдвинутая раскладка из конфига разбирается верно', () {
      final result = ParserService.parseHtmlForTest(
        page(shiftedRow()),
        columns: ParserColumns.fromJson(
          '{"date":1,"group":2,"number":3,"subject":4,'
          '"teacher":5,"classroom":6,"subgroup":7}',
        ),
      );

      expect(result.groups, ['205']);
      expect(result.teachers, ['Иванов И.И.']);

      final lesson = result.schedule['03.09.$year']!['205']!.single;
      expect(lesson.subject, 'Математика');
      expect(lesson.classroom, '202');
      expect(lesson.lessonNumber, 1);
    });
  });

  group('разбор страницы', () {
    test('строка заголовка на <th> не попадает в данные', () {
      final result = ParserService.parseHtmlForTest(
        page(
          row('03-сен', '205', '1', 'Математика', 'Иванов И.И.', '202', '0'),
        ),
      );

      // Если бы заголовок разбирался, здесь появились бы день "Дата",
      // группа "Группа" и преподаватель "Преподаватель".
      expect(result.schedule.keys, hasLength(1));
      expect(result.groups, ['205']);
      expect(result.teachers, ['Иванов И.И.']);
    });

    test('дата приводится к формату хранения dd.MM.yyyy', () {
      final result = ParserService.parseHtmlForTest(
        page(
          row('03-сен', '205', '1', 'Математика', 'Иванов И.И.', '202', '0'),
        ),
      );

      expect(result.schedule.keys.single, '03.09.$year');
    });

    test('занятие разбирается по всем колонкам', () {
      final result = ParserService.parseHtmlForTest(
        page(row('03-сен', '205', '2', 'Физика', 'Петров П.П.', 'К22', '1')),
      );

      final lesson = result.schedule['03.09.$year']!['205']!.single;
      expect(lesson.group, '205');
      expect(lesson.lessonNumber, 2);
      expect(lesson.subject, 'Физика');
      expect(lesson.teacher, 'Петров П.П.');
      expect(lesson.classroom, 'К22');
      expect(lesson.subgroup, '1');
    });

    test('несколько дней и групп раскладываются корректно', () {
      final result = ParserService.parseHtmlForTest(
        page(
          [
            row('03-сен', '205', '1', 'Математика', 'Иванов И.И.', '202', '0'),
            row('03-сен', '313', '1', 'Физика', 'Петров П.П.', '307', '0'),
            row('04-сен', '205', '1', 'История', 'Сидоров С.С.', '101', '0'),
          ].join(),
        ),
      );

      expect(result.schedule.keys, hasLength(2));
      expect(result.schedule['03.09.$year']!.keys, hasLength(2));
      expect(result.schedule['04.09.$year']!.keys, ['205']);
      expect(result.groups, ['205', '313']);
      expect(result.teachers, ['Иванов И.И.', 'Петров П.П.', 'Сидоров С.С.']);
    });

    test('несколько пар одной группы за день сохраняются все', () {
      final result = ParserService.parseHtmlForTest(
        page(
          [
            row('03-сен', '205', '1', 'Математика', 'Иванов И.И.', '202', '0'),
            row('03-сен', '205', '2', 'Физика', 'Иванов И.И.', '202', '0'),
          ].join(),
        ),
      );

      expect(result.schedule['03.09.$year']!['205'], hasLength(2));
    });

    test('нераспознанный номер пары даёт 0, а не роняет разбор', () {
      final result = ParserService.parseHtmlForTest(
        page(
          row('03-сен', '205', '—', 'Классный час', 'Иванов И.И.', '202', '0'),
        ),
      );

      expect(result.schedule['03.09.$year']!['205']!.single.lessonNumber, 0);
    });

    test('строка без даты пропускается', () {
      final result = ParserService.parseHtmlForTest(
        page(row('', '205', '1', 'Математика', 'Иванов И.И.', '202', '0')),
      );

      expect(result.schedule, isEmpty);
    });

    test('строка с недостающими колонками не ломает разбор', () {
      final result = ParserService.parseHtmlForTest(
        page('<tr><td>03-сен</td><td>205</td></tr>'),
      );

      // День создаётся, но занятий в нём нет.
      expect(result.schedule['03.09.$year'], isEmpty);
    });

    test('пустая страница не приводит к исключению', () {
      final result = ParserService.parseHtmlForTest(
        '<html><body></body></html>',
      );
      expect(result.schedule, isEmpty);
      expect(result.groups, isEmpty);
    });

    test('группы и преподаватели отсортированы и без повторов', () {
      final result = ParserService.parseHtmlForTest(
        page(
          [
            row('03-сен', '313', '1', 'Физика', 'Петров П.П.', '307', '0'),
            row('03-сен', '205', '1', 'Математика', 'Иванов И.И.', '202', '0'),
            row('03-сен', '205', '2', 'Алгебра', 'Иванов И.И.', '202', '0'),
          ].join(),
        ),
      );

      expect(result.groups, ['205', '313']);
      expect(result.teachers, ['Иванов И.И.', 'Петров П.П.']);
    });
  });

  group('хэш содержимого', () {
    test('одинаковые байты дают одинаковый хэш', () {
      final a = utf8.encode('расписание');
      final b = utf8.encode('расписание');
      expect(ParserService.hashForTest(a), ParserService.hashForTest(b));
    });

    test('перестановка байт меняет хэш', () {
      // Именно этот случай пропускала прежняя реализация: она складывала
      // байты, а сумма от перестановки не меняется — перестановка двух пар
      // в расписании считалась "изменений нет".
      final a = utf8.encode('AB');
      final b = utf8.encode('BA');
      expect(ParserService.hashForTest(a), isNot(ParserService.hashForTest(b)));
    });

    test('изменение одного символа меняет хэш', () {
      expect(
        ParserService.hashForTest(utf8.encode('каб. 202')),
        isNot(ParserService.hashForTest(utf8.encode('каб. 203'))),
      );
    });
  });

  group('на сайте нет расписания', () {
    // Каникулы и промежуток между семестрами: страница на месте, таблица
    // пустая. Это законное состояние, которое держится неделями, а раньше
    // оно возвращалось как ошибка разбора — с красным сообщением каждые
    // 15 минут и отчётом в Crashlytics на каждую проверку.
    test('пустая таблица — это не ошибка', () {
      final result = ParserService.parseHtmlForTest(page(''));

      expect(result.noSchedule, isTrue);
      expect(result.error, isNull);
      expect(result.schedule, isEmpty);
    });

    test('страница вообще без таблицы тоже не ошибка', () {
      final result = ParserService.parseHtmlForTest(
        '<html><body><p>Расписание временно не публикуется</p></body></html>',
      );

      expect(result.noSchedule, isTrue);
      expect(result.error, isNull);
    });

    test('непустое расписание пустым не считается', () {
      final result = ParserService.parseHtmlForTest(
        page(
          row('03-сен', '205', '1', 'Математика', 'Иванов И.И.', '202', '0'),
        ),
      );

      expect(result.noSchedule, isFalse);
      expect(result.schedule, isNotEmpty);
    });
  });
}
