import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import '../models/schedule_model.dart';

/// Результат загрузки расписания с сайта колледжа.
class ParseResult {
  final Map<String, Map<String, List<ScheduleItem>>> schedule;
  final List<String> groups;
  final List<String> teachers;

  /// Текст ошибки для показа пользователю; null — если всё прошло успешно.
  final String? error;

  /// Хэш содержимого страницы. Сохраняется между запусками, чтобы в
  /// следующий раз понять, менялось ли расписание.
  final String? contentHash;

  /// Страница не изменилась с прошлой загрузки — разбор не выполнялся.
  final bool notModified;

  const ParseResult({
    this.schedule = const {},
    this.groups = const [],
    this.teachers = const [],
    this.error,
    this.contentHash,
    this.notModified = false,
  });

  const ParseResult.error(String message)
    : schedule = const {},
      groups = const [],
      teachers = const [],
      error = message,
      contentHash = null,
      notModified = false;
}

/// Загружает и разбирает расписание с сайта колледжа.
///
/// Раньше вся работа (и запрос, и разбор) выполнялась внутри `compute()`,
/// а кэш и хэш страницы лежали в статических полях этого класса. Статические
/// поля живут в изоляте, который `compute()` создаёт и уничтожает на каждый
/// вызов, поэтому кэш никогда не переживал даже двух подряд обновлений:
/// каждая фоновая синхронизация (раз в 15 минут) заново качала и полностью
/// разбирала страницу.
///
/// Теперь запрос и подсчёт хэша выполняются на вызывающем изоляте (сетевой
/// запрос асинхронный и интерфейс не блокирует), хэш хранится вызывающим
/// кодом между запусками, а в отдельный изолят уходит только разбор HTML —
/// единственная действительно тяжёлая часть.
class ParserService {
  final String url =
      "https://bartc.by/index.php/obuchayushchemusya/dnevnoe-otdelenie/tekushchee-raspisanie";

  /// Жёсткий таймаут сетевого запроса.
  /// Без него зависший ответ сервера навсегда оставлял экран в состоянии
  /// "Обновление расписания..." — прогресс не заканчивался никогда.
  static const Duration _requestTimeout = Duration(seconds: 25);

  static const Map<String, String> _headers = {
    // Сайт колледжа отдаёт 403 на некоторые "пустые" User-Agent,
    // поэтому представляемся явно.
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml',
  };

  /// Загружает расписание.
  ///
  /// [previousHash] — хэш страницы с прошлой успешной загрузки. Если
  /// содержимое не изменилось, разбор пропускается и возвращается
  /// результат с `notModified: true`.
  Future<ParseResult> parseSchedule({String? previousHash}) async {
    try {
      final response = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(_requestTimeout);

      if (response.statusCode != 200) {
        return ParseResult.error('Ошибка загрузки: ${response.statusCode}');
      }

      // bodyBytes, а не body: хэш считаем по исходным байтам, без накладных
      // расходов на декодирование в строку.
      final contentHash = _calculateHash(response.bodyBytes);

      if (previousHash != null && previousHash == contentHash) {
        developer.log('📦 Расписание на сайте не изменилось, разбор пропущен');
        return ParseResult(contentHash: contentHash, notModified: true);
      }

      final parsed = await compute(_parseHtml, response.body);

      if (parsed.schedule.isEmpty) {
        return const ParseResult.error('Новых дней в расписании не найдено');
      }

      return ParseResult(
        schedule: parsed.schedule,
        groups: parsed.groups,
        teachers: parsed.teachers,
        contentHash: contentHash,
      );
    } on TimeoutException {
      return const ParseResult.error(
        'Сервер колледжа не отвечает. Попробуйте позже',
      );
    } on http.ClientException {
      return const ParseResult.error('Ошибка подключения к серверу колледжа');
    } catch (e, stackTrace) {
      developer.log(
        'Ошибка при загрузке расписания',
        error: e,
        stackTrace: stackTrace,
      );
      return const ParseResult.error('Ошибка при загрузке расписания');
    }
  }

  /// Разбор HTML без сети — точка входа для тестов.
  @visibleForTesting
  static ParseResult parseHtmlForTest(String body) {
    final parsed = _parseHtml(body);
    return ParseResult(
      schedule: parsed.schedule,
      groups: parsed.groups,
      teachers: parsed.teachers,
    );
  }

  /// Хэш содержимого страницы для тестов.
  @visibleForTesting
  static String hashForTest(List<int> bytes) => _calculateHash(bytes);

  /// Хэш содержимого страницы.
  ///
  /// Раньше здесь была сумма байт: у неё слишком много коллизий — например,
  /// перестановка двух пар местами не меняет сумму, и обновление расписания
  /// молча считалось "содержимое не изменилось". FNV-1a учитывает порядок.
  static String _calculateHash(List<int> bytes) {
    const int fnvOffset = 0x811c9dc5;
    const int fnvPrime = 0x01000193;
    var hash = fnvOffset;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * fnvPrime) & 0xffffffff;
    }
    // Длина добавляет устойчивости к коллизиям на коротких ответах.
    return '${hash.toRadixString(16)}-${bytes.length}';
  }
}

/// Данные, полученные разбором страницы. Возвращается из изолята.
class _ParsedPage {
  final Map<String, Map<String, List<ScheduleItem>>> schedule;
  final List<String> groups;
  final List<String> teachers;

  const _ParsedPage(this.schedule, this.groups, this.teachers);
}

/// Разбор HTML. Выполняется в отдельном изоляте через `compute`.
_ParsedPage _parseHtml(String body) {
  final document = html.parse(body);
  final tables = document.getElementsByTagName('table');
  final schedule = <String, Map<String, List<ScheduleItem>>>{};
  final groupSet = <String>{};
  final teacherSet = <String>{};

  for (final table in tables) {
    _parseTableData(table, schedule, groupSet, teacherSet);
  }

  return _ParsedPage(
    schedule,
    groupSet.toList()..sort(),
    teacherSet.toList()..sort(),
  );
}

int _parseTableData(
  Element table,
  Map<String, Map<String, List<ScheduleItem>>> scheduleData,
  Set<String> groupSet,
  Set<String> teacherSet,
) {
  final rows = table.getElementsByTagName('tr');
  String currentDay = "";
  String currentGroup = "";
  var newDaysCount = 0;

  for (final row in rows) {
    // Заголовок таблицы состоит из <th>, поэтому список <td> у него пуст
    // и строка отбрасывается — так и должно быть.
    final cells = row.getElementsByTagName('td');
    if (cells.isEmpty) continue;

    final dateCell = cells[0].text.trim();
    if (dateCell.isEmpty) continue;

    try {
      currentDay = _extractDate(dateCell);
      if (!scheduleData.containsKey(currentDay)) {
        newDaysCount++;
        scheduleData[currentDay] = {};
      }

      final groupCell = cells.length > 1 ? cells[1].text.trim() : "";
      if (groupCell.isEmpty) continue;

      currentGroup = groupCell;
      groupSet.add(currentGroup);

      final lesson = _extractLessonData(cells);
      if (lesson == null) continue;

      final lessonWithGroup = lesson.copyWith(group: currentGroup);
      scheduleData[currentDay]!.putIfAbsent(currentGroup, () => []);
      scheduleData[currentDay]![currentGroup]!.add(lessonWithGroup);

      if (lessonWithGroup.teacher.isNotEmpty) {
        teacherSet.add(lessonWithGroup.teacher);
      }
    } catch (e) {
      continue;
    }
  }
  return newDaysCount;
}

const Map<String, int> _months = {
  'янв': 1,
  'фев': 2,
  'мар': 3,
  'апр': 4,
  'май': 5,
  'июн': 6,
  'июл': 7,
  'авг': 8,
  'сен': 9,
  'окт': 10,
  'ноя': 11,
  'дек': 12,
};

/// Приводит дату вида "04-дек" к формату хранения "dd.MM.yyyy".
String _extractDate(String dateCell) {
  final cleanDate = dateCell.replaceAll(RegExp(r'[\(\)]'), '').trim();

  try {
    final parts = cleanDate.split('-');
    if (parts.length == 2) {
      final day = int.tryParse(parts[0]);
      if (day != null) {
        final monthStr = parts[1].toLowerCase();

        // Проверяем, начинается ли месяц с одной из аббревиатур
        // (на случай лишних символов).
        int? month;
        for (final entry in _months.entries) {
          if (monthStr.startsWith(entry.key)) {
            month = entry.value;
            break;
          }
        }

        if (month != null) {
          final now = DateTime.now();
          var year = now.year;

          // Логика перехода года.
          if (now.month == 12 && month == 1) {
            year++;
          } else if (now.month == 1 && month == 12) {
            year--;
          }

          return '${day.toString().padLeft(2, '0')}.'
              '${month.toString().padLeft(2, '0')}.$year';
        }
      }
    }
  } catch (e) {
    developer.log('Ошибка парсинга даты "$cleanDate": $e');
  }

  return cleanDate;
}

ScheduleItem? _extractLessonData(List<Element> cells) {
  try {
    if (cells.length < 6) return null;

    final number = cells[2].text.trim();
    final discipline = cells[3].text.trim();
    final teacher = cells[4].text.trim();
    final classroom = cells[5].text.trim();
    final subgroup = cells.length > 6 ? cells[6].text.trim() : '';

    if (number.isNotEmpty ||
        discipline.isNotEmpty ||
        teacher.isNotEmpty ||
        classroom.isNotEmpty) {
      return ScheduleItem(
        group: '',
        lessonNumber: int.tryParse(number) ?? 0,
        subject: discipline,
        teacher: teacher,
        classroom: classroom,
        subgroup: subgroup.isEmpty ? null : subgroup,
      );
    }
  } catch (e) {
    developer.log("Ошибка извлечения данных урока:", error: e);
  }
  return null;
}
