import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart';
import '../models/schedule_model.dart';
import 'database_service.dart';
import 'dart:convert';
import 'dart:developer' as developer;

class ParserService {
  final String url =
      "https://bartc.by/index.php/obuchayushchemusya/dnevnoe-otdelenie/tekushchee-raspisanie";
  final DatabaseService _db = DatabaseService();
  static bool _isLoading = false;
  static DateTime? _lastLoadTime;

  // Кэш для промежуточных результатов парсинга с временными метками
  static Map<String, dynamic> _parseCache = {};
  static DateTime? _lastParseTime;
  static String? _lastParseHash;

  // Время жизни кэша (в секундах) - 30 минут
  static const int _cacheLifetimeSeconds = 1800;

  // Парсит расписание с сайта колледжа
  // Использую библиотеку html для парсинга

  // Основной метод парсинга с кэшированием
  // Возвращает:
  // - расписание
  // - список групп
  // - список преподов
  // - ошибку если что-то пошло не так
  Future<
      (
        Map<String, Map<String, List<ScheduleItem>>>,
        List<String>,
        List<String>,
        String?
      )> parseSchedule() async {
    try {
      // Проверяем кэш перед загрузкой
      final now = DateTime.now();
      if (_lastParseTime != null &&
          _lastParseHash != null &&
          now.difference(_lastParseTime!).inSeconds < _cacheLifetimeSeconds) {
        developer.log('📦 Используем кэшированные данные парсинга');
        return _getCachedResult();
      }

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        // Пытаемся использовать кэш при ошибке
        if (_lastParseHash != null) {
          developer.log('⚠️ Ошибка загрузки, используем кэш');
          return _getCachedResult();
        }
        return (
          <String, Map<String, List<ScheduleItem>>>{},
          <String>[],
          <String>[],
          'Ошибка загрузки: ${response.statusCode}'
        );
      }

      // Вычисляем хэш содержимого для проверки изменений
      final contentHash = _calculateHash(response.body);

      // Если содержимое не изменилось, используем кэш
      if (contentHash == _lastParseHash && _lastParseTime != null) {
        developer.log('✅ Содержимое не изменилось, используем кэш');
        _lastParseTime = now;
        return _getCachedResult();
      }

      final document = html.parse(response.body);
      final tables = document.getElementsByTagName('table');
      final schedule = <String, Map<String, List<ScheduleItem>>>{};
      final groupSet = <String>{};
      final teacherSet = <String>{};
      var daysFound = 0;

      for (var table in tables) {
        daysFound += _parseTableData(table, schedule, groupSet, teacherSet);
      }

      if (daysFound == 0) {
        // Если новых дней нет, но есть кэш, используем его
        if (_lastParseHash != null) {
          developer.log('📦 Новых дней не найдено, используем кэш');
          return _getCachedResult();
        }
        return (
          <String, Map<String, List<ScheduleItem>>>{},
          <String>[],
          <String>[],
          'Новых дней в расписании не найдено'
        );
      }

      // Сохраняем результат в кэш
      _saveToCache(
          schedule, groupSet.toList()..sort(), teacherSet.toList()..sort());
      _lastParseTime = now;
      _lastParseHash = contentHash;

      return (
        schedule,
        groupSet.toList()..sort(),
        teacherSet.toList()..sort(),
        null
      );
    } catch (e) {
      // При ошибке пытаемся использовать кэш
      if (_lastParseHash != null) {
        developer.log('⚠️ Ошибка парсинга, используем кэш: $e');
        return _getCachedResult();
      }

      if (e is http.ClientException) {
        return (
          <String, Map<String, List<ScheduleItem>>>{},
          <String>[],
          <String>[],
          'Ошибка подключения к серверу колледжа'
        );
      }
      return (
        <String, Map<String, List<ScheduleItem>>>{},
        <String>[],
        <String>[],
        'Ошибка при загрузке расписания'
      );
    }
  }

  // Вычисляет простой хэш строки для проверки изменений
  String _calculateHash(String content) {
    return utf8
        .encode(content)
        .fold<int>(0, (sum, byte) => sum + byte)
        .toString();
  }

  // Сохраняет результат парсинга в кэш
  void _saveToCache(
    Map<String, Map<String, List<ScheduleItem>>> schedule,
    List<String> groups,
    List<String> teachers,
  ) {
    _parseCache = {
      'schedule': schedule,
      'groups': groups,
      'teachers': teachers,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  // Получает результат из кэша
  (
    Map<String, Map<String, List<ScheduleItem>>>,
    List<String>,
    List<String>,
    String?
  ) _getCachedResult() {
    if (_parseCache.isEmpty) {
      return (
        <String, Map<String, List<ScheduleItem>>>{},
        <String>[],
        <String>[],
        'Кэш пуст'
      );
    }

    try {
      final schedule = _parseCache['schedule']
          as Map<String, Map<String, List<ScheduleItem>>>;
      final groups = _parseCache['groups'] as List<String>;
      final teachers = _parseCache['teachers'] as List<String>;
      return (schedule, groups, teachers, null);
    } catch (e) {
      developer.log('Ошибка получения из кэша: $e');
      return (
        <String, Map<String, List<ScheduleItem>>>{},
        <String>[],
        <String>[],
        'Ошибка чтения кэша'
      );
    }
  }

  int _parseTableData(
      Element table,
      Map<String, Map<String, List<ScheduleItem>>> scheduleData,
      Set<String> groupSet,
      Set<String> teacherSet) {
    final rows = table.getElementsByTagName('tr');
    String currentDay = "";
    String currentGroup = "";
    var newDaysCount = 0;

    for (var row in rows) {
      final cells = row.getElementsByTagName('td');
      if (cells.isEmpty) continue;

      final dateCell = cells[0].text.trim();
      if (dateCell.isNotEmpty) {
        try {
          currentDay = _extractDate(dateCell);
          if (!scheduleData.containsKey(currentDay)) {
            newDaysCount++;
            scheduleData[currentDay] = {};
          }

          final groupCell = cells.length > 1 ? cells[1].text.trim() : "";
          if (groupCell.isNotEmpty) {
            currentGroup = groupCell;
            groupSet.add(currentGroup);

            final lesson = _extractLessonData(cells);
            if (lesson != null) {
              final lessonWithGroup = lesson.copyWith(group: currentGroup);
              scheduleData[currentDay]!.putIfAbsent(currentGroup, () => []);
              scheduleData[currentDay]![currentGroup]!.add(lessonWithGroup);

              if (lessonWithGroup.teacher.isNotEmpty) {
                teacherSet.add(lessonWithGroup.teacher);
              }
            }
          }
        } catch (e) {
          continue;
        }
      }
    }
    return newDaysCount;
  }

  String _extractDate(String dateCell) {
    var cleanDate = dateCell.replaceAll(RegExp(r'[\(\)]'), '').trim();

    // Пытаемся распарсить формат "dd-MMM" (например, "04-дек")
    try {
      final parts = cleanDate.split('-');
      if (parts.length == 2) {
        final day = int.tryParse(parts[0]);
        if (day != null) {
          final monthStr = parts[1].toLowerCase();

          final months = {
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
            'дек': 12
          };

          // Проверяем, начинается ли месяц с одной из аббревиатур (на случай лишних символов)
          int? month;
          for (var entry in months.entries) {
            if (monthStr.startsWith(entry.key)) {
              month = entry.value;
              break;
            }
          }

          if (month != null) {
            final now = DateTime.now();
            var year = now.year;

            // Логика перехода года
            // Если сейчас декабрь, а дата январь - это следующий год
            if (now.month == 12 && month == 1) {
              year++;
            }
            // Если сейчас январь, а дата декабрь - это прошлый год (маловероятно для расписания, но все же)
            else if (now.month == 1 && month == 12) {
              year--;
            }

            return '${day.toString().padLeft(2, '0')}.${month.toString().padLeft(2, '0')}.$year';
          }
        }
      }
    } catch (e) {
      // Если не удалось распарсить, возвращаем как есть
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

  // Очистка кэша
  static void clearCache() {
    _parseCache.clear();
    _lastParseTime = null;
    _lastParseHash = null;
  }
}
