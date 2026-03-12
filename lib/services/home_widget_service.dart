import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../models/schedule_model.dart';
import '../models/lesson_time_model.dart';
import 'date_service.dart';

class HomeWidgetService {
  static const String _androidWidgetName = 'ScheduleWidget';

  /// Обновляет данные виджета расписания
  static Future<void> updateScheduleWidget(
    Map<String, Map<String, List<ScheduleItem>>>? scheduleData,
    String searchQuery,
  ) async {
    try {
      debugPrint('🔄 Обновление виджета для запроса: "$searchQuery"');

      final today = DateTime.now();

      if (scheduleData == null || scheduleData.isEmpty) {
        await _saveWidgetData([], 'Нет данных', searchQuery, today);
        return;
      }

      final dateStr = DateService.formatDate(today);

      List<ScheduleItem> lessons = [];
      String title = '';
      DateTime targetDate = today;

      // Проверяем расписание на сегодня
      if (scheduleData.containsKey(dateStr)) {
        final todayLessons =
            _filterLessons(scheduleData[dateStr]!, searchQuery);

        // Проверяем, закончились ли пары на сегодня
        bool isDayFinished = false;
        if (todayLessons.isNotEmpty) {
          final lastLesson = todayLessons.last;
          final lessonEndTime = _getHardcodedLessonEndTime(
              lastLesson.lessonNumber); // Use fallback for "is finished" check

          // Создаем DateTime для конца последней пары
          final endDateTime = DateTime(
            today.year,
            today.month,
            today.day,
            lessonEndTime.hour,
            lessonEndTime.minute,
          );

          if (today.isAfter(endDateTime)) {
            isDayFinished = true;
          }
        }

        if (!isDayFinished) {
          lessons = todayLessons;
          title = 'Сегодня, ${DateService.formatDateString(dateStr)}';
          targetDate = today;
        }
      }

      // Если на сегодня пусто или пары закончились, ищем ближайший день
      if (lessons.isEmpty) {
        final sortedDates = scheduleData.keys.toList()
          ..sort((a, b) => DateService.parseScheduleDate(a)
              .compareTo(DateService.parseScheduleDate(b)));

        for (final date in sortedDates) {
          final parsedDate = DateService.parseScheduleDate(date);

          // Ищем только будущие даты (или сегодня, если мы еще не проверяли его выше,
          // но выше мы уже проверили сегодня, так что ищем строго после сегодня)
          // НО: если сегодня пар не было вообще (todayLessons.isEmpty), то мы сюда попадем.
          // Если сегодня пары были, но закончились (isDayFinished=true), то мы тоже сюда попадем.
          // Поэтому условие: дата строго после сегодня.

          if (parsedDate.isAfter(today) &&
              !DateService.isSameDay(parsedDate, today)) {
            final dayLessons = _filterLessons(scheduleData[date]!, searchQuery);
            if (dayLessons.isNotEmpty) {
              lessons = dayLessons;
              targetDate = parsedDate;

              if (DateService.isSameDay(
                  parsedDate, today.add(const Duration(days: 1)))) {
                title = 'Завтра, ${DateService.formatDateString(date)}';
              } else {
                title = DateService.formatDateStringWithWeekday(date);
              }
              break;
            }
          }
        }
      }

      if (lessons.isEmpty) {
        await _saveWidgetData([], 'Нет занятий', searchQuery, today);
      } else {
        // Find the date object corresponding to the lessons
        // If "title" contains "Сегодня", it's today.
        // If "title" contains "Завтра" or "Monday", it's the date of the lessons.
        // Logic in finding lessons loop:
        // We know the `date` string from the loop. We should pass it or the parsed date.

        // Refactoring to pass the correct date to _saveWidgetData
        // We need to capture the date from the loop above.
        // Let's re-find the date object used.
        // This is imperfect reverse engineering.
        // Better to just calculate it when finding lessons.
        // But for now, let's trust the loop logic found a date.
        // We can regex parse the title date or pass it.
        // Passing it is cleaner but requires changing the loop structure significantly.
        // Let's rely on finding the date again efficiently or assume if we have lessons, we know the dayType.

        // Actually, simplest fix: pass the `date` string found in the loop to _saveWidgetData.

        // Re-implementing updateScheduleWidget to be cleaner and capture date
        await _saveWidgetData(lessons, title, searchQuery, targetDate);
      }
    } catch (e) {
      debugPrint('❌ Ошибка обновления виджета: $e');
    }
  }

  // Fallback for logic 'is day finished' without full LessonTime access inside the sorting loop
  // This mimics the old _getLessonEndTime just for the purpose of checking if today is over.
  static TimeOfDay _getHardcodedLessonEndTime(int lessonNumber) {
    switch (lessonNumber) {
      case 1:
        return const TimeOfDay(hour: 10, minute: 05);
      case 2:
        return const TimeOfDay(hour: 12, minute: 00);
      case 3:
        return const TimeOfDay(hour: 13, minute: 55);
      case 4:
        return const TimeOfDay(hour: 15, minute: 50);
      case 5:
        return const TimeOfDay(hour: 17, minute: 45);
      case 6:
        return const TimeOfDay(hour: 19, minute: 40);
      case 7:
        return const TimeOfDay(hour: 21, minute: 25);
      default:
        return const TimeOfDay(hour: 23, minute: 59);
    }
  }

  /// Фильтрует уроки по поисковому запросу
  static List<ScheduleItem> _filterLessons(
    Map<String, List<ScheduleItem>> daySchedule,
    String query,
  ) {
    final allLessons = <ScheduleItem>[];
    for (var groupLessons in daySchedule.values) {
      allLessons.addAll(groupLessons);
    }

    if (query.isEmpty) return allLessons;

    final lowercaseQuery = query.toLowerCase();
    return allLessons.where((lesson) {
      return lesson.group.toLowerCase().contains(lowercaseQuery) ||
          lesson.teacher.toLowerCase().contains(lowercaseQuery) ||
          lesson.classroom.toLowerCase().contains(lowercaseQuery) ||
          lesson.subject.toLowerCase().contains(lowercaseQuery);
    }).toList()
      ..sort((a, b) => a.lessonNumber.compareTo(b.lessonNumber));
  }

  /// Сохраняет данные в виджет
  static Future<void> _saveWidgetData(
    List<ScheduleItem> lessons,
    String title,
    String searchQuery,
    DateTime date,
  ) async {
    // Determine day type for time calculation
    final dayType = LessonTime.getDayType(date.weekday);

    // Serialize lessons with calculated times
    final lessonsList = lessons.map((e) {
      final map = e.toMap();

      // Calculate start and end times
      final times = LessonTime.getTimesForLesson(e.lessonNumber, dayType);
      String timeString = '';
      if (times.length == 2) {
        timeString = '${times[0].start} - ${times[1].end}';
      }

      map['time'] = timeString;
      return map;
    }).toList();

    final lessonsJson = jsonEncode(lessonsList);

    // Определяем заголовок виджета (например, номер группы)
    final widgetTitle = searchQuery.isNotEmpty ? searchQuery : 'Мое расписание';

    await HomeWidget.saveWidgetData<String>('schedule_data', lessonsJson);
    await HomeWidget.saveWidgetData<String>('schedule_date', title);
    await HomeWidget.saveWidgetData<String>('widget_title', widgetTitle);
    await HomeWidget.saveWidgetData<String>(
        'last_updated', DateFormat('HH:mm').format(DateTime.now()));

    await HomeWidget.updateWidget(
      name: _androidWidgetName,
      androidName: _androidWidgetName,
      iOSName: _androidWidgetName,
    );

    debugPrint('✅ Данные виджета сохранены: ${lessons.length} пар');
  }

  /// Сохраняет настройки виджета (тема и прозрачность)
  static Future<void> saveWidgetSettings(bool isDark, int transparency) async {
    await HomeWidget.saveWidgetData<bool>('widget_theme_dark', isDark);
    await HomeWidget.saveWidgetData<int>('widget_transparency', transparency);

    // Small delay to ensure data is persisted before widget update
    await Future.delayed(const Duration(milliseconds: 500));

    // Принудительно обновляем виджет расписания занятий
    await HomeWidget.updateWidget(
      name: _androidWidgetName,
      androidName: _androidWidgetName,
      iOSName: _androidWidgetName,
    );

    // Обновляем виджет звонков
    await updateBellScheduleData();
  }

  /// Сохраняет цвет виджета
  static Future<void> saveWidgetColor(int colorValue) async {
    await HomeWidget.saveWidgetData<int>('widget_color', colorValue);

    // Обновляем оба виджета
    await HomeWidget.updateWidget(
      name: _androidWidgetName,
      androidName: _androidWidgetName,
      iOSName: _androidWidgetName,
    );

    await HomeWidget.updateWidget(
      name: 'BellScheduleWidgetProvider',
      androidName: 'BellScheduleWidgetProvider',
    );
  }

  /// Обновляет данные для виджета звонков
  static Future<void> updateBellScheduleData() async {
    try {
      final templates = <String, List<Map<String, dynamic>>>{};

      // Генерируем шаблоны для всех типов дней
      for (final dayType in ['normal', 'tuesday', 'thursday', 'saturday']) {
        templates[dayType] = _generateBellScheduleForDayType(dayType);
      }

      await HomeWidget.saveWidgetData<String>(
          'bell_schedule_templates', jsonEncode(templates));

      await HomeWidget.updateWidget(
        name: 'BellScheduleWidgetProvider',
        androidName: 'BellScheduleWidgetProvider',
      );

      debugPrint('✅ Данные виджета звонков обновлены');
    } catch (e) {
      debugPrint('❌ Ошибка обновления виджета звонков: $e');
    }
  }

  static List<Map<String, dynamic>> _generateBellScheduleForDayType(
      String dayType) {
    final items = <Map<String, dynamic>>[];
    final times = LessonTime.lessonTimes[dayType] ?? [];

    for (var time in times) {
      items.add({
        'type': 'lesson',
        'number': time.isFirstHalf ? time.lessonNumber.toString() : '',
        'start': time.start,
        'end': time.end,
        'title': time.isFirstHalf ? '${time.lessonNumber} пара' : '',
      });

      // Проверяем, нужно ли добавить спец. час (после 3 пары, 2-й части)
      // Спец часы: вторник и четверг после 3 пары
      if ((dayType == 'tuesday' || dayType == 'thursday') &&
          time.lessonNumber == 3 &&
          !time.isFirstHalf) {
        final specialHour = LessonTime.getSpecialHourInfo(dayType);
        if (specialHour != null) {
          final specialTime = specialHour['time']!; // "14:10-14:55"
          final specialStart = specialTime.split('-')[0];
          final specialEnd = specialTime.split('-')[1];

          items.add({
            'type': 'special',
            'number': '',
            'start': specialStart,
            'end': specialEnd,
            'title': specialHour['name'],
          });

          // Добавляем пустой элемент, чтобы следующая пара начиналась с новой строки
          // (для GridView с 2 колонками)
          items.add({
            'type': 'dummy',
            'number': '',
            'start': '',
            'end': '',
            'title': '',
          });
        }
      }
    }

    return items;
  }

  static Future<Map<String, dynamic>> loadWidgetSettings() async {
    try {
      final isDark =
          await HomeWidget.getWidgetData<bool>('widget_theme_dark') ?? true;
      final transparency =
          await HomeWidget.getWidgetData<int>('widget_transparency') ?? 0;
      return {
        'isDark': isDark,
        'transparency': transparency,
      };
    } catch (e) {
      return {
        'isDark': true,
        'transparency': 0,
      };
    }
  }
}
