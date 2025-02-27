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
      
      // Загружаем оба типа расписания
      final currentSchedule = await _db.getCurrentSchedule();
      final archiveSchedule = await _db.getArchiveSchedule();
      
      debugPrint('📅 Текущее расписание: ${currentSchedule.keys.join(", ")}');
      debugPrint('📅 Архивное расписание: ${archiveSchedule.keys.join(", ")}');
      
      if ((currentSchedule.isNotEmpty || archiveSchedule.isNotEmpty) && _mounted) {
        _currentScheduleData = currentSchedule;
        _fullScheduleData = archiveSchedule;
        notifyListeners();
        
        if (!await ConnectivityService().isOnline()) {
          _updateStatus('Работа в офлайн режиме');
          _isLoaded = true;
          return;
        }
      }

      if (!await ConnectivityService().isOnline()) {
        if (currentSchedule.isEmpty && archiveSchedule.isEmpty) {
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
    // Предотвращаем параллельные обновления
    if (_isUpdating) {
      debugPrint('⏭️ Обновление уже выполняется, пропускаем');
      return;
    }
    
    _isUpdating = true;
    
    if (!silent) {
      _isLoading = true;
      _updateStatus('Обновление расписания...');
    }
    
    try {
      debugPrint('🔄 Начало обновления расписания');
      final result = await compute(_parseScheduleIsolate, _parser.url);
      
      if (result.$1 != null) {
        debugPrint('📅 Полученные даты: ${result.$1!.keys.join(", ")}');
        _currentScheduleData = result.$1;
        
        debugPrint('💾 Сохранение текущего расписания');
        await _db.saveCurrentSchedule(_currentScheduleData!);
        
        debugPrint('📚 Архивация расписания');
        await _db.archiveSchedule(_currentScheduleData!);
        
        debugPrint('📖 Загрузка архивного расписания');
        _fullScheduleData = await _db.getArchiveSchedule();
        debugPrint('📅 Даты в архиве: ${_fullScheduleData?.keys.join(", ")}');
        
        _groups = result.$2;
        _teachers = result.$3;
        
        await _db.saveGroupsAndTeachers(_groups, _teachers);
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_schedule_update', DateTime.now().toIso8601String());
        
        await _cleanOldSchedule();
        
        _isLoaded = true;
        _error = null;
        
        if (!silent) {
          _showSuccess = true;
          _successMessage = 'Расписание успешно обновлено';
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
      notifyListeners();
    }
  }

  Future<void> updateStorageDays(int days) async {
    _storageDays = days;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('schedule_storage_days', days);
    await _cleanOldSchedule();
  }

  Future<void> _cleanOldSchedule() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _storageDays = prefs.getInt('schedule_storage_days') ?? 30;
      
      // Очищаем старые данные из архива
      await _db.cleanOldArchive(_storageDays);
      
      // Обновляем локальное состояние
      if (_fullScheduleData != null) {
        final now = DateTime.now();
        final cutoffDate = now.subtract(Duration(days: _storageDays));
        
        _fullScheduleData!.removeWhere((dateStr, _) {
          try {
            final date = _parseDateString(dateStr);
            return date.isBefore(cutoffDate);
          } catch (e) {
            return false;
          }
        });
      }
      
      // Перезагружаем архивное расписание после очистки
      _fullScheduleData = await _db.getArchiveSchedule();
      
      notifyListeners();
    } catch (e) {
      debugPrint('Ошибка при очистке старого расписания: $e');
    }
  }

  DateTime _parseDateString(String dateStr) {
    debugPrint('🔍 Парсинг даты: $dateStr');
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
    
    debugPrint('✅ Распознана дата: $day.$month.$year');
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
    return await parser.parseSchedule();
  }

  Future<bool> shouldUpdateSchedule() async {
    try {
      final now = DateTime.now();
      
      if (now.weekday == DateTime.sunday) {
        return false;
      }
      
      if (now.hour < 7 || now.hour >= 20) {
        return false;
      }
      
      final lastUpdate = await getLastUpdateTime();
      
      if (lastUpdate == null) {
        return true;
      }
      
      if (lastUpdate.day != now.day || 
          lastUpdate.month != now.month || 
          lastUpdate.year != now.year) {
        return true;
      }
      
      final hoursSinceLastUpdate = now.difference(lastUpdate).inHours;
      if (hoursSinceLastUpdate >= 3) {
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('Ошибка при проверке необходимости обновления: $e');
      return false;
    }
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

  Map<String, Map<String, List<ScheduleItem>>>? getScheduleForCalendar() {
    return _fullScheduleData;
  }
}