import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

import 'dart:io';

import '../models/schedule_change.dart';

/// Сервис для управления локальными уведомлениями
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Инициализация сервиса уведомлений
  Future<void> initialize() async {
    if (_initialized) return;

    // Настройки для Android
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // Настройки для iOS
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Создаем каналы уведомлений для Android
    if (Platform.isAndroid) {
      await _createNotificationChannels();
    }

    // Запрашиваем разрешения на Android 13+
    if (Platform.isAndroid) {
      await _requestPermissions();
    }

    _initialized = true;
  }

  /// Создает каналы уведомлений для Android
  Future<void> _createNotificationChannels() async {
    const scheduleChannel = AndroidNotificationChannel(
      'schedule_updates',
      'Обновления расписания',
      description: 'Уведомления об изменениях в расписании',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(scheduleChannel);
  }

  /// Запрашивает разрешения на уведомления (Android 13+)
  Future<void> _requestPermissions() async {
    final androidImplementation = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
    }
  }

  /// Идентификатор уведомления.
  ///
  /// Раньше использовался `millisecondsSinceEpoch % 100000` — два уведомления
  /// в пределах одной секунды могли получить один id, и второе затирало первое.
  int _notificationCounter = 0;
  int _nextNotificationId() {
    _notificationCounter = (_notificationCounter + 1) % 100000;
    return _notificationCounter;
  }

  /// Обработчик нажатия на уведомление
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Уведомление нажато: ${response.payload}');
    // Здесь можно добавить логику открытия конкретного экрана
  }

  /// Показывает уведомление об изменениях в расписании
  Future<void> showScheduleUpdateNotification(ScheduleDiffResult diff) async {
    if (!_initialized) {
      await initialize();
    }

    if (!diff.hasChanges) return;

    const title = 'Обновление расписания';
    final body = diff.summary;

    const androidDetails = AndroidNotificationDetails(
      'schedule_updates',
      'Обновления расписания',
      channelDescription: 'Уведомления об изменениях в расписании',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      id: _nextNotificationId(),
      title: title,
      body: body,
      notificationDetails: details,
      payload: 'schedule_update',
    );
  }

  /// Показывает уведомление о новом расписании
  Future<void> showNewScheduleNotification(String message) async {
    if (!_initialized) {
      await initialize();
    }

    const androidDetails = AndroidNotificationDetails(
      'schedule_updates',
      'Обновления расписания',
      channelDescription: 'Уведомления об изменениях в расписании',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      id: _nextNotificationId(),
      title: 'Расписание обновлено',
      body: message,
      notificationDetails: details,
      payload: 'schedule_update',
    );
  }

  /// Отменяет все уведомления
  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  /// Проверяет, разрешены ли уведомления
  Future<bool> areNotificationsEnabled() async {
    if (Platform.isAndroid) {
      final androidImplementation = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidImplementation != null) {
        return await androidImplementation.areNotificationsEnabled() ?? false;
      }
    }
    return true; // Для iOS предполагаем, что разрешено
  }
}
