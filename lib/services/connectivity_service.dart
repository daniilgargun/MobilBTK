import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/material.dart';
import '../widgets/error_snackbar.dart';
import '../providers/schedule_provider.dart';
import '../services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

// Следит за подключением к интернету
// Кэширует данные когда офлайн
// Обеспечивает фоновую синхронизацию при восстановлении связи
// Периодическое обновление расписания с уведомлениями

class ConnectivityService {
  // Создаем один экземпляр на все приложение
  static final ConnectivityService _instance = ConnectivityService._internal();
  static bool _hasShownOfflineWarning =
      false; // Статическое поле для отслеживания уведомления

  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final _connectivity = Connectivity();
  late Box<String> _cache;
  bool _lastKnownStatus = true;
  DateTime? _lastSyncTime;
  bool _isSyncing = false;
  ScheduleProvider? _scheduleProvider;

  Future<void> init() async {
    await Hive.initFlutter();
    _cache = await Hive.openBox<String>('schedule_cache');
    _lastKnownStatus = await isOnline();
    _connectivity.onConnectivityChanged.listen(_handleConnectivityChange);

    // Загружаем время последней синхронизации
    final prefs = await SharedPreferences.getInstance();
    final lastSyncStr = prefs.getString('last_sync_time');
    if (lastSyncStr != null) {
      _lastSyncTime = DateTime.parse(lastSyncStr);
    }
  }

  // Проверяем изменения подключения
  void _handleConnectivityChange(List<ConnectivityResult> results) async {
    final isOnlineNow = !results.contains(ConnectivityResult.none);

    if (isOnlineNow != _lastKnownStatus) {
      _lastKnownStatus = isOnlineNow;

      if (isOnlineNow) {
        _hasShownOfflineWarning = false;
        // Автоматическая фоновая синхронизация при восстановлении связи
        await _performBackgroundSync();
      }
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
  Future<void> _performBackgroundSync() async {
    if (_isSyncing) return;

    // Проверяем время синхронизации
    if (!_canSyncNow()) {
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

      final shouldSync = _lastSyncTime == null ||
          now.difference(_lastSyncTime!).inMinutes >= syncIntervalMinutes;

      if (shouldSync) {
        debugPrint(
            '🔄 Начинаем фоновую синхронизацию (интервал: $syncIntervalMinutes мин)...');
        final provider = _scheduleProvider ?? ScheduleProvider();

        // Обновляем расписание и получаем информацию об изменениях
        final diffResult = await provider.updateSchedule(silent: true);

        // Отправляем уведомление при обнаружении изменений
        if (diffResult != null && diffResult.hasChanges) {
          debugPrint('📢 Обнаружены изменения: ${diffResult.summary}');
          await NotificationService()
              .showScheduleUpdateNotification(diffResult);
        }

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

  // Получает время последней синхронизации
  DateTime? get lastSyncTime => _lastSyncTime;

  // Получает статус синхронизации
  bool get isSyncing => _isSyncing;

  // Проверяет есть ли интернет
  Future<bool> isOnline() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _lastKnownStatus = !results.contains(ConnectivityResult.none);
      return _lastKnownStatus;
    } catch (e) {
      return false;
    }
  }

  bool get lastKnownStatus => _lastKnownStatus;

  // Показывает предупреждение что нет инета
  // Показывает только один раз
  void showOfflineWarning(BuildContext context) {
    if (!_lastKnownStatus && !_hasShownOfflineWarning) {
      _hasShownOfflineWarning = true;
      CustomSnackBar.showWarning(
        context,
        'Нет подключения к интернету. Работа в офлайн режиме.',
      );
    }
  }

  // Сохраняет данные в кэш
  Future<void> cacheData(String key, String data) async {
    await _cache.put(key, data);
  }

  // Берет данные из кэша
  String? getCachedData(String key) {
    return _cache.get(key);
  }

  Future<void> clearCache() async {
    await _cache.clear();
  }

  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged;
}
