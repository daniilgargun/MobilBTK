import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart';
import '../models/schedule_model.dart';
import 'database_service.dart';
import 'dart:developer' as developer;

class ParserService {
  final String url = "https://bartc.by/index.php/obuchayushchemusya/dnevnoe-otdelenie/tekushchee-raspisanie";
  final DatabaseService _db = DatabaseService();
  static bool _isLoading = false;
  static DateTime? _lastLoadTime;

  Future<(Map<String, Map<String, List<ScheduleItem>>>?, List<String>, List<String>, String?)> parseSchedule() async {
    // Проверяем, не было ли загрузки в последние 5 секунд
    if (_lastLoadTime != null && 
        DateTime.now().difference(_lastLoadTime!) < const Duration(seconds: 5)) {
      developer.log('Слишком частые запросы, подождите');
      return (null, <String>[], <String>[], null);
    }

    // Предотвращаем параллельные загрузки
    if (_isLoading) {
      developer.log('Загрузка уже выполняется');
      return (null, <String>[], <String>[], null);
    }

    _isLoading = true;
    _lastLoadTime = DateTime.now();

    try {
      developer.log('Начало загрузки расписания');
      
      final client = http.Client();
      final response = await client.get(
        Uri.parse(url),
        headers: {
          'Connection': 'keep-alive',
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0',
        },
      ).timeout(const Duration(seconds: 10));
      client.close();
      
      if (response.statusCode != 200) {
        developer.log('Ошибка HTTP: ${response.statusCode}');
        return (null, <String>[], <String>[], "❌ Ошибка получения расписания");
      }

      final document = html.parse(response.body);
      final tables = document.getElementsByTagName('table');
      
      if (tables.isEmpty) {
        developer.log('Таблицы с расписанием не найдены');
        return (null, <String>[], <String>[], "❌ Расписание не найдено");
      }

      final scheduleData = <String, Map<String, List<ScheduleItem>>>{};
      final groupSet = <String>{};
      final teacherSet = <String>{};

      for (var table in tables) {
        _parseTable(table, scheduleData, groupSet, teacherSet);
        // Даем время другим операциям
        await Future.delayed(const Duration(milliseconds: 1));
      }

      if (scheduleData.isEmpty) {
        developer.log('Расписание пустое');
        return (null, <String>[], <String>[], "❌ Расписание пустое");
      }

      developer.log(
        'Расписание успешно загружено',
        error: {
          'Дней': scheduleData.length,
          'Групп': groupSet.length,
          'Преподавателей': teacherSet.length,
        },
      );

      return (scheduleData, groupSet.toList()..sort(), teacherSet.toList()..sort(), null);
    } catch (e, stackTrace) {
      developer.log(
        'Ошибка при загрузке расписания',
        error: e,
        stackTrace: stackTrace,
      );
      return (null, <String>[], <String>[], "❌ Ошибка при получении расписания. Попробуйте позже.");
    } finally {
      _isLoading = false;
    }
  }

  // Выносим парсинг таблицы в отдельный метод
  void _parseTable(Element table, Map<String, Map<String, List<ScheduleItem>>> scheduleData, 
                  Set<String> groupSet, Set<String> teacherSet) {
    final rows = table.getElementsByTagName('tr');
    String currentDay = "";
    String currentGroup = "";

    for (var row in rows) {
      final cells = row.getElementsByTagName('td');
      if (cells.isEmpty) continue;

      final dateCell = cells[0].text.trim();
      if (dateCell.isNotEmpty) {
        try {
          currentDay = dateCell.replaceAll(RegExp(r'[\(\)]'), '');
          scheduleData.putIfAbsent(currentDay, () => {});

          final groupCell = row.querySelector('.ari-tbl-col-1');
          if (groupCell != null) {
            currentGroup = groupCell.text.trim();
            groupSet.add(currentGroup);

            final lessonData = _extractLessonData(row);
            if (lessonData != null) {
              final lessonWithGroup = lessonData.copyWith(group: currentGroup);
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
  }

  ScheduleItem? _extractLessonData(Element row) {
    try {
      final number = row.querySelector('.ari-tbl-col-2')?.text.trim() ?? '';
      final discipline = row.querySelector('.ari-tbl-col-3')?.text.trim() ?? '';
      final teacher = row.querySelector('.ari-tbl-col-4')?.text.trim() ?? '';
      final classroom = row.querySelector('.ari-tbl-col-5')?.text.trim() ?? '';
      final subgroup = row.querySelector('.ari-tbl-col-6')?.text.trim() ?? '';

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
} 