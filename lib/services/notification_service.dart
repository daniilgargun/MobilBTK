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

  /// Запасная иконка на случай, если основной в сборке не оказалось.
  ///
  /// Ровно это и случилось однажды: `isShrinkResources` вырезал
  /// `ic_stat_schedule`, потому что ссылка на него — строка в Dart, а
  /// сокращатель ресурсов видит только ссылки из манифеста, разметки и
  /// Kotlin. Ресурс держит `android/app/src/main/res/raw/keep.xml`, но
  /// уведомления не та функция, ради которой приложение вправе не
  /// запуститься, поэтому вторая линия обороны остаётся здесь.
  static const String _fallbackIcon = '@mipmap/ic_launcher';

  /// Иконка, с которой плагин согласился инициализироваться.
  String _icon = _smallIcon;

  /// Иконку берёт и [LessonReminderService]: она должна быть той же, что
  /// принял плагин, иначе показ напоминания упадёт на неизвестном ресурсе.
  String get icon => _icon;

  static const MethodChannel _platform = MethodChannel(
    'com.gargun.btktimetable/widget',
  );

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Инициализация сервиса уведомлений.
  ///
  /// Ничего не бросает наружу: вызывается из `main()` до `runApp`, и любое
  /// исключение отсюда означало бы приложение, которое не запускается вовсе.
  /// Разрешение здесь не запрашивается — системный диалог поверх пустого
  /// экрана выглядит как зависший запуск, поэтому его показывает уже
  /// работающий интерфейс ([requestPermission]).
  Future<void> initialize() async {
    if (_initialized) return;

    if (!await _initializeWith(_smallIcon)) {
      if (!await _initializeWith(_fallbackIcon)) {
        // Уведомлений не будет, но приложение работает.
        return;
      }
      _icon = _fallbackIcon;
    }

    try {
      await _createNotificationChannels();
    } catch (e) {
      debugPrint('⚠️ Не удалось создать канал уведомлений: $e');
    }

    _initialized = true;
  }

  Future<bool> _initializeWith(String icon) async {
    try {
      await _notifications.initialize(
        settings: InitializationSettings(
          android: AndroidInitializationSettings(icon),
        ),
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
      return true;
    } catch (e) {
      debugPrint('⚠️ Уведомления не инициализировались с иконкой $icon: $e');
      return false;
    }
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

  /// Запрашивает разрешение на уведомления (Android 13+).
  ///
  /// Вызывается с уже отрисованного интерфейса: системный диалог, показанный
  /// до первого кадра, висит поверх пустого экрана и неотличим от зависания.
  Future<void> requestPermission() async {
    try {
      await _android?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('⚠️ Запрос разрешения на уведомления не удался: $e');
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
  }

  /// Сводка изменений бывает длинной (несколько пар в нескольких днях),
  /// поэтому текст разворачивается по нажатию, а не обрезается многоточием.
  NotificationDetails _details(String body) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        icon: _icon,
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        styleInformation: BigTextStyleInformation(body),
      ),
    );
  }

  /// Показывает уведомление об изменениях в расписании.
  ///
  /// Текст берётся подробный: после фильтра по своей группе изменений
  /// обычно единицы, и «2 изменено» заставляет открывать приложение,
  /// чтобы понять, что именно поменялось.
  Future<void> showScheduleUpdateNotification(ScheduleDiffResult diff) async {
    if (!diff.hasChanges) return;
    await _show('Обновление расписания', diff.detailedSummary);
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
