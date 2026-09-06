import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/material.dart';

import '../providers/schedule_provider.dart';
import '../services/notification_service.dart';
import 'lesson_reminder_service.dart';
import 'schedule_diff_service.dart';
import 'user_profile_service.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

// Следит за подключением к интернету
// Кэширует данные когда офлайн
// Обеспечивает фоновую синхронизацию при восстановлении связи
// Периодическое обновление расписания с уведомлениями

class ConnectivityService {
  // Создаем один экземпляр на все приложение
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final _connectivity = Connectivity();

  // Box может быть ещё не открыт (например, при обращении из фонового изолята
  // до вызова init()). Раньше поле было `late` и обращение к нему до
  // инициализации роняло приложение с LateInitializationError.
  Box<String>? _cache;

  // Широковещательный поток состояния сети.
  // На него подписан ScheduleProvider вместо опроса раз в 5 секунд.
  final StreamController<bool> _statusController =
      StreamController<bool>.broadcast();

  /// Поток изменений подключения: true — сеть есть, false — офлайн.
  Stream<bool> get onStatusChanged => _statusController.stream;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isInitialized = false;
  bool _lastKnownStatus = true;
  DateTime? _lastSyncTime;
  bool _isSyncing = false;
  ScheduleProvider? _scheduleProvider;

  Future<void> init() async {
    // init() вызывается и из main(), и из фоновой задачи Workmanager.
    // Повторная подписка приводила бы к дублирующимся синхронизациям.
    if (_isInitialized) return;
    _isInitialized = true;

    await Hive.initFlutter();
    _cache = await Hive.openBox<String>('schedule_cache');
    _lastKnownStatus = await isOnline();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _handleConnectivityChange,
    );

    // Загружаем время последней синхронизации
    final prefs = await SharedPreferences.getInstance();
    final lastSyncStr = prefs.getString('last_sync_time');
    if (lastSyncStr != null) {
      _lastSyncTime = DateTime.parse(lastSyncStr);
    }
  }

  /// Есть ли хоть один пригодный сетевой интерфейс.
  ///
  /// Раньше проверка была написана наоборот — «в списке нет пометки none».
  /// На Samsung с выключенными Wi-Fi и мобильными данными
  /// `checkConnectivity` возвращает пустой список, а не список с `none`, и
  /// такая проверка объявляла телефон подключённым: кнопка обновления
  /// оставалась активной, предупреждение об офлайне не показывалось, а
  /// обновление молча упиралось в сеть. Проверено на SM-A135F, Android 14.
  static bool _hasNetwork(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);

  // Проверяем изменения подключения
  void _handleConnectivityChange(List<ConnectivityResult> results) async {
    final isOnlineNow = _hasNetwork(results);
    final changed = isOnlineNow != _lastKnownStatus;
    _lastKnownStatus = isOnlineNow;

    // Состояние сообщается на каждое событие, а не только на смену.
    //
    // `ScheduleProvider` держит свой признак офлайна по факту сорвавшегося
    // запроса, и тот вполне может расходиться с тем, что видит система: при
    // поднятом VPN интерфейс остаётся «подключённым» и когда канала под ним
    // уже нет. Тогда выключение и возврат Wi-Fi для системы не смена
    // состояния, события не было, и надпись «нет сети» висела на экране,
    // пока связь давно вернулась.
    if (!_statusController.isClosed) {
      _statusController.add(isOnlineNow);
    }

    if (isOnlineNow && changed) {
      // Автоматическая фоновая синхронизация при восстановлении связи
      await _performBackgroundSync();
    }
  }

  // Устанавливает провайдер расписания для использования в фоновых задачах
  void setScheduleProvider(ScheduleProvider provider) {
    _scheduleProvider = provider;
  }

  // Проверяет, можно ли выполнять синхронизацию в текущее время
  // Возвращает true если время между 7:00 и 21:00 и не воскресенье
  bool _canSyncNow() {
    final now = tz.TZDateTime.now(tz.local);
    final hour = now.hour;
    final weekday = now.weekday; // 1 = понедельник, 7 = воскресенье

    // Воскресенье - не синхронизируем
    if (weekday == 7) {
      return false;
    }

    // Время должно быть между 7:00 и 21:00 (общее окно)
    return hour >= 7 && hour < 21;
  }

  // Проверяет, находится ли текущее время в окне интенсивного мониторинга
  bool _isIntensiveMonitoringWindow() {
    final now = tz.TZDateTime.now(tz.local);
    final hour = now.hour;
    return hour >= 7 && hour < 17;
  }

  // Выполняет фоновую синхронизацию при восстановлении связи
  //
  // [force] снимает проверку окна и интервала. Так синхронизация приходит
  // по сообщению от сторожа страницы: он уже установил, что расписание
  // изменилось, и ждать следующего окна незачем. Опрос по таймеру, наоборот,
  // без этих проверок обходился бы дорого впустую.
  Future<void> _performBackgroundSync({bool force = false}) async {
    if (_isSyncing) return;

    // Проверяем время синхронизации
    if (!force && !_canSyncNow()) {
      debugPrint('⏰ Вне времени синхронизации или воскресенье');
      return;
    }

    _isSyncing = true;
    try {
      // Проверяем, нужно ли обновлять данные
      final now = DateTime.now();

      // Определяем интервал синхронизации
      // В интенсивное время (7-17) - каждые 15 минут (или при каждом запуске задачи)
      // В остальное время - реже, например раз в 3 часа
      int syncIntervalMinutes = 180; // 3 часа по умолчанию
      if (_isIntensiveMonitoringWindow()) {
        syncIntervalMinutes = 15; // 15 минут в рабочее время
      }

      final shouldSync =
          force ||
          _lastSyncTime == null ||
          now.difference(_lastSyncTime!).inMinutes >= syncIntervalMinutes;

      if (shouldSync) {
        debugPrint(
          '🔄 Начинаем фоновую синхронизацию (интервал: $syncIntervalMinutes мин)...',
        );
        final provider = _scheduleProvider ?? ScheduleProvider();

        // Обновляем расписание и получаем информацию об изменениях
        final diffResult = await provider.updateSchedule(silent: true);

        // Уведомляем только о том, что касается пользователя.
        //
        // Дифф сравнивает расписание всего колледжа, поэтому без фильтра
        // студенту приходило «изменено 12 пар», где ни одна не его.
        // Профиль читаем из хранилища: здесь может быть изолят фоновой
        // задачи, где состояния приложения нет.
        if (diffResult != null && diffResult.hasChanges) {
          final profile = await UserProfileService().load();
          final personal = ScheduleDiffService.forProfile(diffResult, profile);

          if (personal.hasChanges) {
            debugPrint('📢 Обнаружены изменения: ${personal.summary}');
            await NotificationService().showScheduleUpdateNotification(
              personal,
            );
          } else {
            debugPrint('🔕 Изменения есть, но не по профилю пользователя');
          }
        }

        // Расписание могло сдвинуться — переставляем напоминания о парах.
        await LessonReminderService().reschedule(provider.scheduleData);

        _lastSyncTime = now;

        // Сохраняем время синхронизации
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_sync_time', now.toIso8601String());
        debugPrint('✅ Фоновая синхронизация завершена');
      }
    } catch (e) {
      debugPrint('⚠️ Ошибка фоновой синхронизации: $e');
    } finally {
      _isSyncing = false;
    }
  }

  // Выполняет периодическую синхронизацию (вызывается из workmanager)
  static Future<void> performPeriodicSync() async {
    final service = ConnectivityService();
    await service.init();
    await service._performBackgroundSync();
  }

  /// Синхронизация по сообщению от сторожа страницы (`PushService`).
  ///
  /// Окно и интервал не проверяются: сторож присылает сообщение только
  /// когда страница действительно изменилась, и только в рабочие часы —
  /// повторять эти проверки на телефоне значит отложить уведомление до
  /// следующего пробуждения по таймеру, ради которого всё и затевалось.
  static Future<void> performPushSync() async {
    final service = ConnectivityService();
    await service.init();
    await service._performBackgroundSync(force: true);
  }

  // Получает время последней синхронизации
  DateTime? get lastSyncTime => _lastSyncTime;

  // Получает статус синхронизации
  bool get isSyncing => _isSyncing;

  // Проверяет есть ли интернет
  Future<bool> isOnline() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _lastKnownStatus = _hasNetwork(results);
      return _lastKnownStatus;
    } catch (e) {
      return false;
    }
  }

  bool get lastKnownStatus => _lastKnownStatus;

  // Сохраняет данные в кэш
  Future<void> cacheData(String key, String data) async {
    await _cache?.put(key, data);
  }

  // Берет данные из кэша
  String? getCachedData(String key) {
    return _cache?.get(key);
  }

  Future<void> clearCache() async {
    await _cache?.clear();
  }

  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged;

  /// Освобождает ресурсы. Используется в тестах и при завершении изолята.
  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    await _statusController.close();
    _isInitialized = false;
  }
}
