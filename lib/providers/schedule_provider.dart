import 'package:flutter/foundation.dart';
import '../services/parser_service.dart';
import '../services/database_service.dart';
import '../models/schedule_model.dart';
import 'dart:developer' as developer;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart' as intl;
import 'package:flutter/foundation.dart';
import '../services/connectivity_service.dart';
import 'dart:async';
import 'package:flutter/widgets.dart';

class ScheduleProvider extends ChangeNotifier {
  final ParserService _parser = ParserService();
  final DatabaseService _db = DatabaseService();
  
  Map<String, Map<String, List<ScheduleItem>>>? _currentScheduleData;
  Map<String, Map<String, List<ScheduleItem>>>? _fullScheduleData;
  List<String> _groups = [];
  List<String> _teachers = [];
  String? _error;
  bool _isLoading = false;
  String? _status;
  bool _isLoaded = false;
  int _storageDays = 30;
  String? _errorMessage;
  String? _errorDetails;
  bool _showError = false;
  bool _mounted = true;
  bool _showSuccess = false;
  String? _successMessage;
  bool _isUpdating = false;
  bool _isOffline = false;
  static DateTime? _lastUpdateTime;
  Timer? _connectivityCheckTimer;

  // Кэш для подготовленных данных
  Map<String, List<ScheduleItem>> _preparedScheduleCache = {};
  Map<String, List<ScheduleItem>> _filteredCache = {};
  bool _isDataPrepared = false;

  // Добавляем переменную для хранения настроек отображения
  int _displayDays = 30;

  Map<String, Map<String, List<ScheduleItem>>>? get scheduleData => _currentScheduleData;
  Map<String, Map<String, List<ScheduleItem>>>? get fullScheduleData => _fullScheduleData;
  List<String> get groups => _groups;
  List<String> get teachers => _teachers;
  String? get error => _error;
  bool get isLoading => _isLoading;
  String? get status => _status;
  bool get isLoaded => _isLoaded;
  String? get errorMessage => _errorMessage;
  String? get errorDetails => _errorDetails;
  bool get showError => _showError;
  bool get mounted => _mounted;
  bool get showSuccess => _showSuccess;
  String? get successMessage => _successMessage;
  bool get isOffline => _isOffline;

  ScheduleProvider() {
    _connectivityCheckTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkConnectivity(),
    );
    
    // Инициализируем настройки отображения
    _initDisplayDays();
  }

  // Инициализирует настройки отображения
  Future<void> _initDisplayDays() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _displayDays = prefs.getInt('schedule_storage_days') ?? 30;
    } catch (e) {
      debugPrint('Ошибка при инициализации настроек отображения: $e');
    }
  }

  void _updateStatus(String? message) {
    _status = message;
    notifyListeners();
  }

  void _handleError(String message, {String? details}) {
    _errorMessage = message;
    _errorDetails = details;
    _showError = true;
    notifyListeners();
  }

  void dismissError() {
    _showError = false;
    _errorMessage = null;
    _errorDetails = null;
    notifyListeners();
  }

  void dismissSuccess() {
    _showSuccess = false;
    _successMessage = null;
    notifyListeners();
  }

  Future<void> loadSchedule() async {
    if (_isLoaded) return;
    
    try {
      _updateStatus('Загрузка расписания...');
      debugPrint('📥 Начало загрузки расписания');
      
      // Загружаем настройки отображения
      final prefs = await SharedPreferences.getInstance();
      _displayDays = prefs.getInt('schedule_storage_days') ?? 30;
      _storageDays = _displayDays > 30 ? _displayDays : 30;
      
      // Загружаем оба типа расписания
      final currentSchedule = await _db.getCurrentSchedule();
      final archiveSchedule = await _db.getArchiveSchedule();
      
      debugPrint('📅 Текущее расписание: ${currentSchedule.keys.join(", ")}');
      debugPrint('📅 Архивное расписание: ${archiveSchedule.keys.join(", ")}');
      
      if ((currentSchedule.isNotEmpty || archiveSchedule.isNotEmpty) && _mounted) {
        _currentScheduleData = currentSchedule;
        _fullScheduleData = archiveSchedule;

        // Проверяем, не пусто ли текущее расписание, и если да - восстанавливаем из архива
        if (_currentScheduleData == null || _currentScheduleData!.isEmpty) {
          debugPrint('🔄 Текущее расписание пусто, восстанавливаем из архива');
          if (_fullScheduleData != null && _fullScheduleData!.isNotEmpty) {
            _currentScheduleData = Map.from(_fullScheduleData!);
            // Сохраняем восстановленные данные
            await _db.saveCurrentSchedule(_currentScheduleData!);
            debugPrint('✅ Текущее расписание восстановлено из архива');
          }
        }
        
        notifyListeners();
        
        if (!await ConnectivityService().isOnline()) {
          _updateStatus('Работа в офлайн режиме');
          _isLoaded = true;
          return;
        }
      }

      if (!await ConnectivityService().isOnline()) {
        if ((currentSchedule.isEmpty && archiveSchedule.isEmpty) ||
            (_currentScheduleData == null || _currentScheduleData!.isEmpty)) {
          _handleError(
            'Нет данных',
            details: 'Для первой загрузки требуется подключение к интернету',
          );
        }
        return;
      }

      final shouldUpdate = await shouldUpdateSchedule();
      if (shouldUpdate || _currentScheduleData == null || _currentScheduleData!.isEmpty) {
        await updateSchedule(silent: true);
      } else {
        _isLoaded = true;
        _updateStatus(null);
        notifyListeners();
      }
    } catch (e, stackTrace) {
      developer.log('Ошибка при загрузке расписания:', error: e, stackTrace: stackTrace);
      _handleError(
        'Не удалось загрузить расписание',
        details: 'Проверьте подключение к интернету и попробуйте снова',
      );
    }
  }

  Future<void> updateSchedule({bool silent = false}) async {
    // Проверяем подключение к интернету перед обновлением
    if (!await ConnectivityService().isOnline()) {
      _handleError('Нет подключения к интернету');
      return;
    }

    // Предотвращаем параллельные обновления
    if (_isUpdating) {
      debugPrint('⏭️ Обновление уже выполняется, пропускаем');
      return;
    }
    
    _isUpdating = true;
    
    if (!silent) {
      _isLoading = true;
      _updateStatus('Обновление расписания...');
      notifyListeners();
    }
    
    try {
      final result = await compute(_parseScheduleIsolate, _parser.url);
      
      if (result.$1 != null) {
        // Сохраняем предыдущие данные для сравнения
        final previousScheduleKeys = _currentScheduleData?.keys.toList() ?? [];
        
        _currentScheduleData = result.$1;
        await _db.saveCurrentSchedule(_currentScheduleData!);
        await _db.archiveSchedule(_currentScheduleData!);
        _fullScheduleData = await _db.getArchiveSchedule();
        
        _groups = result.$2;
        _teachers = result.$3;
        
        await _db.saveGroupsAndTeachers(_groups, _teachers);
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_schedule_update', DateTime.now().toIso8601String());
        
        await _cleanOldSchedule();
        
        _isLoaded = true;
        _error = null;
        
        // Очищаем кэш после успешного обновления
        clearCache();
        
        // Проверяем, появились ли новые дни
        final currentScheduleKeys = _currentScheduleData?.keys.toList() ?? [];
        final hasNewDays = currentScheduleKeys.length > previousScheduleKeys.length;
        
        if (!silent) {
          _showSuccess = true;
          if (hasNewDays) {
            _successMessage = 'Расписание обновлено. Добавлены новые дни!';
          } else {
            _successMessage = 'Расписание успешно обновлено';
          }
        }
      } else if (result.$4 != null) {
        _handleError('Ошибка обновления', details: result.$4);
      }
    } catch (e) {
      debugPrint('❌ Ошибка обновления: $e');
      _handleError(
        'Ошибка обновления',
        details: 'Проверьте подключение к интернету и попробуйте снова',
      );
    } finally {
      _isLoading = false;
      _isUpdating = false;
      _updateStatus(null);
      
      // Явно уведомляем слушателей для обновления UI
      notifyListeners();
    }
  }

  Future<void> updateStorageDays(int days) async {
    // Минимальный период хранения - 30 дней или выбранное пользователем значение (что больше)
    _storageDays = days > 30 ? days : 30;
    // Сохраняем выбранное пользователем значение для отображения
    _displayDays = days;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('schedule_storage_days', days);
    await _cleanOldSchedule();
    
    // Очищаем кэш, чтобы обновить данные в календаре
    clearCache();
    
    notifyListeners();
  }

  Future<void> _cleanOldSchedule() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userSelectedDays = prefs.getInt('schedule_storage_days') ?? 30;
      
      // Фактический период хранения - 30 дней или выбранное пользователем значение (что больше)
      _storageDays = userSelectedDays > 30 ? userSelectedDays : 30;
      
      // Очищаем старые данные из базы данных
      await _db.cleanOldArchive(_storageDays);
      
      // Обновляем локальное состояние
      if (_fullScheduleData != null) {
        final now = DateTime.now();
        final cutoffDate = now.subtract(Duration(days: _storageDays));
        
        // Удаляем старые данные из архива
        _fullScheduleData!.removeWhere((dateStr, _) {
          try {
            final date = _parseDateString(dateStr);
            return date.isBefore(cutoffDate);
          } catch (e) {
            debugPrint('Ошибка при парсинге даты: $e');
            return false;
          }
        });
        
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Ошибка при очистке старого расписания: $e');
    }
  }

  DateTime _parseDateString(String dateStr) {
    
    final parts = dateStr.split('-');
    if (parts.length != 2) {
      debugPrint('❌ Неверный формат даты: $dateStr');
      throw FormatException('Неверный формат даты: $dateStr');
    }

    final day = int.parse(parts[0]);
    final monthStr = parts[1].toLowerCase().trim();
    
    final monthMap = {
      'янв': 1, 'фев': 2, 
      'март': 3, 'мар': 3, 
      'апр': 4, 'май': 5, 
      'июн': 6, 'июл': 7, 
      'авг': 8, 'сен': 9, 
      'окт': 10, 'ноя': 11, 
      'дек': 12,
      // Добавляем поддержку числового формата
      '01': 1, '02': 2, '03': 3, '04': 4,
      '05': 5, '06': 6, '07': 7, '08': 8,
      '09': 9, '10': 10, '11': 11, '12': 12,
    };
    
    final month = monthMap[monthStr];
    if (month == null) {
      debugPrint('❌ Неизвестный месяц: $monthStr');
      throw FormatException('Неизвестный месяц: $monthStr');
    }
    
    final now = DateTime.now();
    var year = now.year;
    
    if (month < now.month) {
      year++;
    }
    
    
    return DateTime(year, month, day);
  }

  Future<void> loadGroupsAndTeachers() async {
    try {
      developer.log('Начало загрузки групп и преподавателей из базы');
      
      final db = await _db.database;
      final groupsResult = await db.query('groups');
      final teachersResult = await db.query('teachers');

      _groups = groupsResult.map((e) => e['name'] as String).toList();
      _teachers = teachersResult.map((e) => e['name'] as String).toList();
      
      developer.log('Загружено из базы:', error: {
        'Количество групп': _groups.length,
        'Группы': _groups,
        'Количество преподавателей': _teachers.length,
      });
      
      notifyListeners();
    } catch (e, stackTrace) {
      developer.log('Ошибка загрузки групп и преподавателей:', error: e, stackTrace: stackTrace);
    }
  }

  List<String> _extractGroups(Map<String, Map<String, List<ScheduleItem>>> schedule) {
    final Set<String> uniqueGroups = {};
    
    for (var daySchedule in schedule.values) {
      for (var groupSchedule in daySchedule.values) {
        for (var item in groupSchedule) {
          uniqueGroups.add(item.group);
        }
      }
    }
    
    return uniqueGroups.toList()..sort();
  }

  List<String> _extractTeachers(Map<String, Map<String, List<ScheduleItem>>> schedule) {
    final Set<String> uniqueTeachers = {};
    
    for (var daySchedule in schedule.values) {
      for (var groupSchedule in daySchedule.values) {
        for (var item in groupSchedule) {
          uniqueTeachers.add(item.teacher);
        }
      }
    }
    
    return uniqueTeachers.toList()..sort();
  }

  Future<String> getLastUpdateInfo() async {
    final lastUpdate = await _db.getLastUpdateTime();
    if (lastUpdate == null) {
      return "Расписание еще не обновлялось";
    }
    
    final now = DateTime.now();
    final diff = now.difference(lastUpdate);
    
    if (diff.inMinutes < 1) {
      return "Обновлено только что";
    } else if (diff.inMinutes < 60) {
      return "Обновлено ${diff.inMinutes} мин. назад";
    } else if (diff.inHours < 24) {
      return "Обновлено ${diff.inHours} ч. назад";
    } else {
      final formatter = intl.DateFormat('dd.MM.yyyy HH:mm', 'ru_RU');
      return "Обновлено ${formatter.format(lastUpdate)}";
    }
  }

  @override
  void dispose() {
    _mounted = false;
    _connectivityCheckTimer?.cancel();
    super.dispose();
  }

  static Future<(Map<String, Map<String, List<ScheduleItem>>>?, List<String>, List<String>, String?)> 
      _parseScheduleIsolate(String url) async {
    final parser = ParserService();
    final result = await parser.parseSchedule();
    return result;
  }

  Future<bool> shouldUpdateSchedule() async {
    return true; // Теперь обновление доступно всегда
  }

  Future<DateTime?> getLastUpdateTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastUpdateStr = prefs.getString('last_schedule_update');
      if (lastUpdateStr != null) {
        return DateTime.parse(lastUpdateStr);
      }
      return null;
    } catch (e) {
      debugPrint('Ошибка при получении времени обновления: $e');
      return null;
    }
  }

  Future<void> _checkConnectivity() async {
    final connectivityService = ConnectivityService();
    final isOnline = await connectivityService.isOnline();
    
    if (isOnline != !_isOffline) {
      _isOffline = !isOnline;
      notifyListeners();
      
      if (!_isOffline) {
        await updateSchedule(silent: true);
      }
    }
  }

  // Получает расписание для календаря с учетом настроек отображения
  Map<String, Map<String, List<ScheduleItem>>>? getScheduleForCalendar() {
    // Возвращаем полные данные архива для отображения в календаре
    return _fullScheduleData;
  }

  // Подготавливаем данные заранее
  Future<void> _prepareData() async {
    if (_isDataPrepared) return;
    
    _preparedScheduleCache.clear();
    if (_currentScheduleData != null) {
      for (var date in _currentScheduleData!.keys) {
        final daySchedule = _currentScheduleData![date]!;
        final allLessons = <ScheduleItem>[];
        
        for (var groupLessons in daySchedule.values) {
          allLessons.addAll(groupLessons);
        }
        
        // Предварительная сортировка
        allLessons.sort((a, b) => a.lessonNumber.compareTo(b.lessonNumber));
        _preparedScheduleCache[date] = allLessons;
      }
    }
    _isDataPrepared = true;
  }

  // Получаем подготовленные данные для даты
  List<ScheduleItem> getPreparedSchedule(String date) {
    return _preparedScheduleCache[date] ?? [];
  }

  // Получаем отфильтрованные данные
  List<ScheduleItem> getFilteredSchedule(String date, String query) {
    final cacheKey = '${date}_$query';
    
    if (_filteredCache.containsKey(cacheKey)) {
      return _filteredCache[cacheKey]!;
    }
    
    final lessons = getPreparedSchedule(date);
    if (query.isEmpty) {
      return lessons;
    }
    
    final lowercaseQuery = query.toLowerCase();
    final filtered = lessons.where((lesson) =>
      lesson.group.toLowerCase().contains(lowercaseQuery) ||
      lesson.teacher.toLowerCase().contains(lowercaseQuery) ||
      lesson.classroom.toLowerCase().contains(lowercaseQuery) ||
      lesson.subject.toLowerCase().contains(lowercaseQuery)
    ).toList();
    
    _filteredCache[cacheKey] = filtered;
    return filtered;
  }

  @override
  void clearCache() {
    _preparedScheduleCache.clear();
    _filteredCache.clear();
    _isDataPrepared = false;
    // Необходимо принудительно уведомить слушателей при очистке кэша
    notifyListeners();
  }

  // Добавим метод для синхронизации currentScheduleData с fullScheduleData
  Future<void> syncScheduleData() async {
    try {
      if (_fullScheduleData != null && _fullScheduleData!.isNotEmpty) {
        if (_currentScheduleData == null || _currentScheduleData!.isEmpty) {
          debugPrint('🔄 Синхронизация данных: восстановление текущего расписания из архива');
          _currentScheduleData = Map.from(_fullScheduleData!);
          await _db.saveCurrentSchedule(_currentScheduleData!);
          notifyListeners();
          debugPrint('✅ Синхронизация выполнена успешно');
        }
      }
    } catch (e) {
      debugPrint('❌ Ошибка при синхронизации данных: $e');
    }
  }
}