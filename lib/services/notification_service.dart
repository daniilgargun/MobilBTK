/*
 * Copyright (c) 2024 Daniil Gargun. All rights reserved.
 * Author: Daniil Gargun | Telegram: @Daniilgargun | Email: daniilgorgun38@gmail.com
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/schedule_change.dart';

/// Локальные уведомления об изменениях в расписании.
///
/// Серверных push нет и не планируется: уведомление рождается на самом
/// устройстве, когда фоновая синхронизация нашла разницу между старым и
/// новым расписанием (`ScheduleDiffService`).
///
/// Приложение android-only, поэтому ветки для iOS убраны — они всё равно
/// никогда не выполнялись, но создавали впечатление, что платформа
/// поддерживается.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const String _channelId = 'schedule_updates';
  static const String _channelName = 'Обновления расписания';
  static const String _channelDescription =
      'Уведомления об изменениях в расписании';

  /// Одноцветная иконка для строки состояния.
  ///
  /// Раньше здесь стоял `@mipmap/ic_launcher`. Начиная с Android 5.0 система
  /// берёт от маленькой иконки только альфа-канал, поэтому цветной логотип
  /// приложения превращался в белый квадрат без деталей.
  static const String _smallIcon = '@drawable/ic_stat_schedule';

  static const MethodChannel _platform = MethodChannel(
    'com.gargun.btktimetable/widget',
  );

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Инициализация сервиса уведомлений
  Future<void> initialize() async {
    if (_initialized) return;

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings(_smallIcon),
    );

    await _notifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    await _createNotificationChannels();
    await _requestPermissions();

    _initialized = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _notifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Создает каналы уведомлений для Android
  Future<void> _createNotificationChannels() async {
    const scheduleChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _android?.createNotificationChannel(scheduleChannel);
  }

  /// Запрашивает разрешения на уведомления (Android 13+)
  Future<void> _requestPermissions() async {
    await _android?.requestNotificationsPermission();
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
  }

  /// Сводка изменений бывает длинной (несколько пар в нескольких днях),
  /// поэтому текст разворачивается по нажатию, а не обрезается многоточием.
  NotificationDetails _details(String body) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        icon: _smallIcon,
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        styleInformation: BigTextStyleInformation(body),
      ),
    );
  }

  /// Показывает уведомление об изменениях в расписании
  Future<void> showScheduleUpdateNotification(ScheduleDiffResult diff) async {
    if (!diff.hasChanges) return;
    await _show('Обновление расписания', diff.summary);
  }

  /// Показывает уведомление о новом расписании
  Future<void> showNewScheduleNotification(String message) async {
    await _show('Расписание обновлено', message);
  }

  Future<void> _show(String title, String body) async {
    if (!_initialized) {
      await initialize();
    }

    await _notifications.show(
      id: _nextNotificationId(),
      title: title,
      body: body,
      notificationDetails: _details(body),
      payload: 'schedule_update',
    );
  }

  /// Открывает системный экран настроек уведомлений приложения.
  ///
  /// Сначала пробуем обычный запрос разрешения: если пользователь ещё не
  /// отказывал, он увидит привычный системный диалог. После окончательного
  /// отказа Android больше не показывает диалог и запрос молча возвращает
  /// false — тогда открываем настройки приложения напрямую, иначе нажатие
  /// в настройках выглядело бы как «ничего не произошло».
  Future<void> openSystemSettings() async {
    final granted = await _android?.requestNotificationsPermission() ?? false;
    if (granted) return;

    try {
      await _platform.invokeMethod('openNotificationSettings');
    } on PlatformException catch (e) {
      debugPrint('⚠️ Не удалось открыть настройки уведомлений: $e');
    } on MissingPluginException {
      // Канал доступен только когда открыта MainActivity.
    }
  }

  /// Отменяет все уведомления
  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  /// Проверяет, разрешены ли уведомления
  Future<bool> areNotificationsEnabled() async {
    return await _android?.areNotificationsEnabled() ?? false;
  }
}
