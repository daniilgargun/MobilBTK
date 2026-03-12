import 'package:flutter/foundation.dart';
import '../models/schedule_model.dart';

/// Оптимизированный сервис кэширования для календаря
/// Управляет всеми типами кэша в едином месте
class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  // Кэш событий календаря: дата -> список уроков
  final Map<DateTime, List<ScheduleItem>> _calendarEventsCache = {};

  // Кэш отфильтрованных данных: ключ -> список уроков
  final Map<String, List<ScheduleItem>> _filteredCache = {};

  // Кэш подготовленных данных расписания: дата -> список уроков
  final Map<String, List<ScheduleItem>> _preparedScheduleCache = {};

  // Флаги состояния кэша
  bool _isCalendarCacheValid = false;
  bool _isScheduleCacheValid = false;

  // Максимальный размер кэша (количество записей)
  static const int _maxCacheSize = 1000;

  /// Очищает все кэши
  void clearAll() {
    _calendarEventsCache.clear();
    _filteredCache.clear();
    _preparedScheduleCache.clear();
    _isCalendarCacheValid = false;
    _isScheduleCacheValid = false;
    debugPrint('🧹 Все кэши очищены');
  }

  /// Очищает только кэш календаря
  void clearCalendarCache() {
    _calendarEventsCache.clear();
    _isCalendarCacheValid = false;
    debugPrint('🧹 Кэш календаря очищен');
  }

  /// Очищает только кэш расписания
  void clearScheduleCache() {
    _preparedScheduleCache.clear();
    _filteredCache.clear();
    _isScheduleCacheValid = false;
    debugPrint('🧹 Кэш расписания очищен');
  }

  /// Получает события для календаря по дате
  List<ScheduleItem>? getCalendarEvents(DateTime date) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    return _calendarEventsCache[normalizedDate];
  }

  /// Сохраняет события календаря для даты
  void setCalendarEvents(DateTime date, List<ScheduleItem> events) {
    final normalizedDate = DateTime(date.year, date.month, date.day);

    // Проверяем размер кэша и очищаем старые записи при необходимости
    if (_calendarEventsCache.length >= _maxCacheSize) {
      _cleanOldCalendarEntries();
    }

    _calendarEventsCache[normalizedDate] = List.from(events);
  }

  /// Получает подготовленное расписание по дате
  List<ScheduleItem>? getPreparedSchedule(String dateStr) {
    return _preparedScheduleCache[dateStr];
  }

  /// Сохраняет подготовленное расписание
  void setPreparedSchedule(String dateStr, List<ScheduleItem> schedule) {
    if (_preparedScheduleCache.length >= _maxCacheSize) {
      _cleanOldScheduleEntries();
    }

    _preparedScheduleCache[dateStr] = List.from(schedule);
  }

  /// Получает отфильтрованные данные
  List<ScheduleItem>? getFilteredData(String cacheKey) {
    return _filteredCache[cacheKey];
  }

  /// Сохраняет отфильтрованные данные
  void setFilteredData(String cacheKey, List<ScheduleItem> data) {
    if (_filteredCache.length >= _maxCacheSize) {
      _cleanOldFilteredEntries();
    }

    _filteredCache[cacheKey] = List.from(data);
  }

  /// Создает ключ для кэша отфильтрованных данных
  String createFilterKey(String date, String filter, String? value) {
    return '${date}_${filter}_${value ?? 'null'}';
  }

  /// Проверяет, валиден ли кэш календаря
  bool get isCalendarCacheValid => _isCalendarCacheValid;

  /// Проверяет, валиден ли кэш расписания
  bool get isScheduleCacheValid => _isScheduleCacheValid;

  /// Помечает кэш календаря как валидный
  void markCalendarCacheValid() {
    _isCalendarCacheValid = true;
  }

  /// Помечает кэш расписания как валидный
  void markScheduleCacheValid() {
    _isScheduleCacheValid = true;
  }

  /// Инвалидирует кэш календаря
  void invalidateCalendarCache() {
    _isCalendarCacheValid = false;
    clearCalendarCache();
  }

  /// Инвалидирует кэш расписания
  void invalidateScheduleCache() {
    _isScheduleCacheValid = false;
    clearScheduleCache();
  }

  /// Очищает старые записи из кэша календаря
  void _cleanOldCalendarEntries() {
    if (_calendarEventsCache.length <= _maxCacheSize ~/ 2) return;

    // Сортируем по дате и удаляем самые старые записи
    final sortedEntries = _calendarEventsCache.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final entriesToRemove = sortedEntries.take(_maxCacheSize ~/ 4);
    for (final entry in entriesToRemove) {
      _calendarEventsCache.remove(entry.key);
    }

    debugPrint(
        '🧹 Очищено ${entriesToRemove.length} старых записей из кэша календаря');
  }

  /// Очищает старые записи из кэша расписания
  void _cleanOldScheduleEntries() {
    if (_preparedScheduleCache.length <= _maxCacheSize ~/ 2) return;

    // Удаляем четверть самых старых записей
    final keys = _preparedScheduleCache.keys.take(_maxCacheSize ~/ 4).toList();
    for (final key in keys) {
      _preparedScheduleCache.remove(key);
    }

    debugPrint('🧹 Очищено ${keys.length} старых записей из кэша расписания');
  }

  /// Очищает старые записи из кэша фильтров
  void _cleanOldFilteredEntries() {
    if (_filteredCache.length <= _maxCacheSize ~/ 2) return;

    // Удаляем четверть самых старых записей
    final keys = _filteredCache.keys.take(_maxCacheSize ~/ 4).toList();
    for (final key in keys) {
      _filteredCache.remove(key);
    }

    debugPrint('🧹 Очищено ${keys.length} старых записей из кэша фильтров');
  }

  /// Получает статистику кэша
  Map<String, int> getCacheStats() {
    return {
      'calendar_events': _calendarEventsCache.length,
      'prepared_schedule': _preparedScheduleCache.length,
      'filtered_data': _filteredCache.length,
      'total_entries': _calendarEventsCache.length +
          _preparedScheduleCache.length +
          _filteredCache.length,
    };
  }

  /// Выводит статистику кэша в отладочную консоль
  void printCacheStats() {
    final stats = getCacheStats();
    debugPrint('📊 Статистика кэша:');
    debugPrint('  - События календаря: ${stats['calendar_events']}');
    debugPrint('  - Подготовленное расписание: ${stats['prepared_schedule']}');
    debugPrint('  - Отфильтрованные данные: ${stats['filtered_data']}');
    debugPrint('  - Всего записей: ${stats['total_entries']}');
    debugPrint('  - Кэш календаря валиден: $_isCalendarCacheValid');
    debugPrint('  - Кэш расписания валиден: $_isScheduleCacheValid');
  }
}
