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
  
  Map<String, Map<String, List<ScheduleItem>>>? _scheduleData;
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
  bool _isOffline = false;  // Добавляем поле для отслеживания офлайн режима
  static DateTime? _lastUpdateTime;
  Timer? _connectivityCheckTimer;

  Map<String, Map<String, List<ScheduleItem>>>? get scheduleData => _scheduleData;
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
    // Проверяем подключение каждые 5 секунд
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
      
      // Проверяем подключение
      final connectivityService = ConnectivityService();
      final isOnline = await connectivityService.isOnline();
      _isOffline = !isOnline;
      notifyListeners();
      
      // Сначала пробуем загрузить из кэша
      final cached = await _db.getSchedule();
      if (cached.isNotEmpty && _mounted) {
        _scheduleData = cached;
        notifyListeners();
        
        if (!isOnline) {
          _updateStatus('Работа в офлайн режиме');
          _isLoaded = true;
          return;
        }
      }

      if (!isOnline) {
        if (cached.isEmpty) {
          _handleError(
            'Нет данных',
            details: 'Для первой загрузки требуется подключение к интернету',
          );
        }
        return;
      }

      final shouldUpdate = await _db.shouldUpdateSchedule();
      if (shouldUpdate || _scheduleData == null || _scheduleData!.isEmpty) {
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
    debugPrint('🔄 Запрос на обновление расписания');
    debugPrint('Тихий режим: $silent');
    debugPrint('Офлайн режим: $_isOffline');

    final connectivityService = ConnectivityService();
    final isOnline = await connectivityService.isOnline();
    
    debugPrint('📡 Статус подключения: ${isOnline ? "онлайн" : "офлайн"}');

    if (!isOnline) {
      _isOffline = true;
      notifyListeners();
      debugPrint('❌ Нет подключения к интернету');
      return;
    }

    _isOffline = false;

    if (_lastUpdateTime != null && 
        DateTime.now().difference(_lastUpdateTime!) < const Duration(seconds: 5)) {
      developer.log('Слишком частые обновления, подождите');
      return;
    }

    if (_isUpdating) {
      developer.log('Обновление уже выполняется');
      return;
    }

    _isUpdating = true;
    _lastUpdateTime = DateTime.now();

    if (!silent) {
      _isLoading = true;
      _updateStatus('Обновление расписания...');
    }
    
    try {
      final result = await compute(_parseScheduleIsolate, _parser.url);
      debugPrint('📦 Результат парсинга: ${result.$1 != null ? "успешно" : "ошибка"}');
      
      if (result.$1 != null) {
        await _db.saveSchedule(result.$1!);
        await _db.saveGroupsAndTeachers(result.$2, result.$3);
        await _db.updateLastUpdateTime();
        
        _scheduleData = result.$1;
        _groups = result.$2;
        _teachers = result.$3;
        
        _isLoaded = true;
        _error = null;
        
        if (!silent) {
          _showSuccess = true;
          _successMessage = 'Расписание успешно обновлено';
        }
      } else if (result.$4 != null) {
        _handleError(
          'Ошибка обновления',
          details: result.$4,
        );
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
    if (_scheduleData == null) return;

    final now = DateTime.now();
    final cutoffDate = now.subtract(Duration(days: _storageDays));

    _scheduleData!.removeWhere((dateStr, _) {
      try {
        final parts = dateStr.split('-');
        if (parts.length != 2) return false;
        
        final day = int.tryParse(parts[0]);
        if (day == null) return false;
        
        final monthMap = {
          'янв': 1, 'фев': 2, 'мар': 3, 'апр': 4,
          'май': 5, 'июн': 6, 'июл': 7, 'авг': 8,
          'сен': 9, 'окт': 10, 'ноя': 11, 'дек': 12
        };
        
        final month = monthMap[parts[1].toLowerCase()];
        if (month == null) return false;
        
        final date = DateTime(now.year, month, day);
        
        return date.isBefore(cutoffDate);
      } catch (e) {
        return false;
      }
    });

    await _db.cleanOldSchedule(_storageDays);
    notifyListeners();
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

  // Статический метод для выполнения в изоляте
  static Future<(Map<String, Map<String, List<ScheduleItem>>>?, List<String>, List<String>, String?)> 
      _parseScheduleIsolate(String url) async {
    final parser = ParserService();
    return await parser.parseSchedule();
  }

  Future<bool> shouldUpdateSchedule() async {
    try {
      final now = DateTime.now();
      
      // Не обновляем в воскресенье
      if (now.weekday == DateTime.sunday) {
        return false;
      }
      
      // Обновляем только в рабочее время (7:00 - 19:59)
      if (now.hour < 7 || now.hour >= 20) {
        return false;
      }
      
      final lastUpdate = await getLastUpdateTime();
      
      // Если никогда не обновлялось
      if (lastUpdate == null) {
        return true;
      }
      
      // Если последнее обновление было в другой день
      if (lastUpdate.day != now.day || 
          lastUpdate.month != now.month || 
          lastUpdate.year != now.year) {
        return true;
      }
      
      // Обновляем каждые 3 часа в рабочее время
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
}