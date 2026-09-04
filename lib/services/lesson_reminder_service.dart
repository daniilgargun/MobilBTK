/*
 * Copyright (c) 2024 Daniil Gargun. All rights reserved.
 * Author: Daniil Gargun | Telegram: @Daniilgargun | Email: daniilgorgun38@gmail.com
 */

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/lesson_time_model.dart';
import '../models/schedule_model.dart';
import 'date_service.dart';
import 'user_profile_service.dart';

/// Напоминание за несколько минут до начала пары.
///
/// Уведомления планируются локально на устройстве: сервера у приложения нет.
/// Планируется только расписание выбранного профиля и только на ближайшие
/// дни — иначе в очереди Android оказались бы сотни будильников, которые всё
/// равно устареют после ближайшего обновления расписания.
class LessonReminderService {
  static final LessonReminderService _instance =
      LessonReminderService._internal();
  factory LessonReminderService() => _instance;
  LessonReminderService._internal();

  static const String _enabledKey = 'lesson_reminders_enabled';
  static const String _minutesKey = 'lesson_reminder_minutes';

  static const String _channelId = 'lesson_reminders';
  static const String _channelName = 'Напоминания о парах';
  static const String _channelDescription =
      'Напоминание за несколько минут до начала пары';

  static const String _smallIcon = '@drawable/ic_stat_schedule';

  /// Диапазон идентификаторов напоминаний.
  ///
  /// Уведомления об изменениях используют 0…99999, поэтому напоминания
  /// начинаются заведомо выше: при перепланировании надо снять только свои
  /// будильники, не трогая чужие уведомления.
  static const int _idBase = 200000;
  static const int _idLimit = 299999;

  /// На сколько дней вперёд планируем.
  static const int _horizonDays = 7;

  /// Допустимые значения «за сколько минут».
  static const List<int> minuteOptions = [5, 10, 15, 30];
  static const int defaultMinutes = 15;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  final ValueNotifier<bool> _enabled = ValueNotifier<bool>(false);
  final ValueNotifier<int> _minutes = ValueNotifier<int>(defaultMinutes);

  ValueListenable<bool> get enabledListenable => _enabled;
  ValueListenable<int> get minutesListenable => _minutes;

  bool get isEnabled => _enabled.value;
  int get minutesBefore => _minutes.value;

  AndroidFlutterLocalNotificationsPlugin? get _android => _notifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Читает настройки. Вызывается на старте и в фоновой задаче.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled.value = prefs.getBool(_enabledKey) ?? false;
      final minutes = prefs.getInt(_minutesKey) ?? defaultMinutes;
      _minutes.value = minuteOptions.contains(minutes)
          ? minutes
          : defaultMinutes;
    } catch (e) {
      debugPrint('⚠️ Не удалось прочитать настройки напоминаний: $e');
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  Future<void> setMinutesBefore(int value) async {
    if (!minuteOptions.contains(value)) return;
    _minutes.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_minutesKey, value);
  }

  /// Может ли приложение ставить точные будильники.
  ///
  /// На Android 12+ это отдельное разрешение. Без него напоминание всё
  /// равно придёт, но может опоздать на несколько минут — для напоминания
  /// «за 15 минут до пары» это существенно, поэтому в настройках честно
  /// пишем, что точность не гарантирована.
  Future<bool> canScheduleExactly() async {
    try {
      return await _android?.canScheduleExactNotifications() ?? false;
    } catch (e) {
      debugPrint('⚠️ Не удалось проверить разрешение на точные будильники: $e');
      return false;
    }
  }

  /// Просит разрешение на точные будильники.
  Future<bool> requestExactPermission() async {
    try {
      await _android?.requestExactAlarmsPermission();
    } catch (e) {
      debugPrint('⚠️ Запрос разрешения на точные будильники не прошёл: $e');
    }
    return canScheduleExactly();
  }

  /// Перепланирует напоминания под текущее расписание.
  ///
  /// Вызывается после каждого удачного обновления расписания и при смене
  /// настроек: старые будильники снимаются целиком, потому что пара могла
  /// не просто сдвинуться, а исчезнуть.
  Future<void> reschedule(
    Map<String, Map<String, List<ScheduleItem>>>? schedule,
  ) async {
    await load();
    await _cancelAll();

    final profile = UserProfileService().profile;
    if (!_enabled.value || profile == null || schedule == null) return;

    final exact = await canScheduleExactly();
    final now = tz.TZDateTime.now(tz.local);
    final horizon = now.add(const Duration(days: _horizonDays));

    var id = _idBase;

    for (final entry in _plan(schedule, profile, now, horizon)) {
      if (id > _idLimit) break;
      await _schedule(id++, entry, exact: exact);
    }

    debugPrint('⏰ Запланировано напоминаний: ${id - _idBase}');
  }

  /// Собирает список напоминаний: что и когда показать.
  ///
  /// Вынесено отдельно и без обращений к плагину, чтобы логику отбора можно
  /// было проверить тестами.
  @visibleForTesting
  List<LessonReminder> planForTest(
    Map<String, Map<String, List<ScheduleItem>>> schedule,
    UserProfile profile,
    tz.TZDateTime now,
    tz.TZDateTime horizon,
  ) => _plan(schedule, profile, now, horizon);

  List<LessonReminder> _plan(
    Map<String, Map<String, List<ScheduleItem>>> schedule,
    UserProfile profile,
    tz.TZDateTime now,
    tz.TZDateTime horizon,
  ) {
    final result = <LessonReminder>[];

    schedule.forEach((dateKey, groups) {
      if (!DateService.isValidScheduleDate(dateKey)) return;
      final date = DateService.parseScheduleDate(dateKey);

      final dayType = LessonTime.getDayType(date.weekday);

      // Пара может идти у нескольких групп одновременно (у преподавателя
      // так бывает часто) — напоминание нужно одно.
      final seenLessons = <int>{};

      groups.forEach((group, items) {
        for (final item in items) {
          if (!profile.matches(item)) continue;
          if (!seenLessons.add(item.lessonNumber)) continue;

          final times = LessonTime.getTimesForLesson(
            item.lessonNumber,
            dayType,
          );
          if (times.isEmpty) continue;

          final start = _parseTime(times.first.start);
          if (start == null) continue;

          final lessonStart = tz.TZDateTime(
            tz.local,
            date.year,
            date.month,
            date.day,
            start.$1,
            start.$2,
          );

          final fireAt = lessonStart.subtract(
            Duration(minutes: _minutes.value),
          );

          // Прошедшее время Android просто проглотит, а горизонт
          // ограничивает число будильников в очереди.
          if (!fireAt.isAfter(now) || fireAt.isAfter(horizon)) continue;

          result.add(
            LessonReminder(
              fireAt: fireAt,
              lessonStart: lessonStart,
              item: item,
              minutesBefore: _minutes.value,
            ),
          );
        }
      });
    });

    result.sort((a, b) => a.fireAt.compareTo(b.fireAt));
    return result;
  }

  Future<void> _schedule(
    int id,
    LessonReminder reminder, {
    required bool exact,
  }) async {
    try {
      await _notifications.zonedSchedule(
        id: id,
        title: reminder.title,
        body: reminder.body,
        scheduledDate: reminder.fireAt,
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            icon: _smallIcon,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
          ),
        ),
        payload: 'lesson_reminder',
      );
    } catch (e) {
      debugPrint('⚠️ Не удалось запланировать напоминание: $e');
    }
  }

  /// Снимает только свои будильники: уведомления об изменениях расписания
  /// живут в другом диапазоне идентификаторов и их трогать нельзя.
  Future<void> _cancelAll() async {
    try {
      final pending = await _notifications.pendingNotificationRequests();
      for (final request in pending) {
        if (request.id >= _idBase && request.id <= _idLimit) {
          await _notifications.cancel(id: request.id);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Не удалось снять старые напоминания: $e');
    }
  }

  /// Создаёт канал уведомлений. Отдельный от «изменений расписания», чтобы
  /// пользователь мог отключить в системе одно, не трогая другое.
  Future<void> createChannel() async {
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
    );
    await _android?.createNotificationChannel(channel);
  }

  /// Разбирает "8:00" в пару (часы, минуты).
  static (int, int)? _parseTime(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0].trim());
    final minute = int.tryParse(parts[1].trim());
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour, minute);
  }
}

/// Одно запланированное напоминание.
@immutable
class LessonReminder {
  final tz.TZDateTime fireAt;
  final tz.TZDateTime lessonStart;
  final ScheduleItem item;
  final int minutesBefore;

  const LessonReminder({
    required this.fireAt,
    required this.lessonStart,
    required this.item,
    required this.minutesBefore,
  });

  String get title => 'Через $minutesBefore мин — ${item.subject}';

  String get body {
    final time =
        '${lessonStart.hour}:'
        '${lessonStart.minute.toString().padLeft(2, '0')}';

    final parts = [
      '${item.lessonNumber} пара в $time',
      if (item.classroom.isNotEmpty) 'каб. ${item.classroom}',
      if (item.teacher.isNotEmpty) item.teacher,
    ];

    return parts.join(' · ');
  }
}
