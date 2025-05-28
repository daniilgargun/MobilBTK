import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart';
import '../models/schedule_model.dart';
import 'database_service.dart';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

class ParserService {
  final String url = "https://bartc.by/index.php/obuchayushchemusya/dnevnoe-otdelenie/tekushchee-raspisanie";
  final DatabaseService _db = DatabaseService();
  static bool _isLoading = false;
  static DateTime? _lastLoadTime;

  // Кэш для промежуточных результатов парсинга
  static Map<String, dynamic> _parseCache = {};

  // Парсит расписание с сайта колледжа
  // Использую библиотеку html для парсинга

  // Основной метод парсинга
  // Возвращает:
  // - расписание
  // - список групп
  // - список преподов
  // - ошибку если что-то пошло не так
  Future<(Map<String, Map<String, List<ScheduleItem>>>, List<String>, List<String>, String?)> parseSchedule() async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        return (<String, Map<String, List<ScheduleItem>>>{}, <String>[], <String>[], 'Ошибка загрузки: ${response.statusCode}');
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
        return (<String, Map<String, List<ScheduleItem>>>{}, <String>[], <String>[], 'Новых дней в расписании не найдено');
      }

      return (schedule, groupSet.toList()..sort(), teacherSet.toList()..sort(), null);
    } catch (e) {
      if (e is http.ClientException) {
        return (<String, Map<String, List<ScheduleItem>>>{}, <String>[], <String>[], 'Ошибка подключения к серверу колледжа');
      }
      return (<String, Map<String, List<ScheduleItem>>>{}, <String>[], <String>[], 'Ошибка при загрузке расписания');
    }
  }

  int _parseTableData(Element table, Map<String, Map<String, List<ScheduleItem>>> scheduleData, 
                     Set<String> groupSet, Set<String> teacherSet) {
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
    return dateCell.replaceAll(RegExp(r'[\(\)]'), '').trim();
  }

  ScheduleItem? _extractLessonData(List<Element> cells) {
    try {
      if (cells.length < 6) return null;

      final number = cells[2].text.trim();
      final discipline = cells[3].text.trim();
      final teacher = cells[4].text.trim();
      final classroom = cells[5].text.trim();
      final subgroup = cells.length > 6 ? cells[6].text.trim() : '';

      if (number.isNotEmpty || discipline.isNotEmpty || teacher.isNotEmpty || classroom.isNotEmpty) {
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
  }
} 