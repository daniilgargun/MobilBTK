import 'package:flutter/foundation.dart';

import '../services/parser_service.dart';
import '../services/crash_reporter.dart';
import '../services/database_service.dart';
import '../services/date_service.dart';
import '../services/schedule_search.dart';
import '../services/cache_service.dart';
import '../services/schedule_diff_service.dart';
import '../models/schedule_model.dart';
import '../models/schedule_change.dart';

import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart' as intl;

import '../services/connectivity_service.dart';

import 'dart:async';

import 'dart:convert';

import '../services/home_widget_service.dart';

class ScheduleProvider extends ChangeNotifier {
  /// Ключ, под которым хранится хэш последней успешно разобранной страницы.
  /// Позволяет пропускать разбор, когда на сайте ничего не изменилось.
  static const String _pageHashKey = 'last_page_hash';

  final ParserService _parser = ParserService();
  final DatabaseService _db = DatabaseService();

  Map<String, Map<String, List<ScheduleItem>>>? _currentScheduleData;
  Map<String, Map<String, List<ScheduleItem>>>? _fullScheduleData;
  Map<String, Map<String, List<ScheduleItem>>>?
  _previousScheduleData; // Для сравнения
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

  /// На сайте колледжа сейчас нет расписания.
  ///
  /// Отличается от «не удалось загрузить»: страница открылась и разобралась,
  /// в ней просто нет ни одного дня. Так выглядят каникулы и промежуток
  /// между семестрами — по несколько недель подряд.
  bool _scheduleUnpublished = false;

  StreamSubscription<bool>? _connectivitySubscription;

  // Используем централизованный сервис кэширования
  final CacheService _cacheService = CacheService();

  // Добавляем переменную для хранения настроек отображения
  int _displayDays = 30;

  // Настройки подсказок поиска
  SearchSuggestionSettings _searchSettings = SearchSuggestionSettings();
  SearchSuggestionSettings get searchSettings => _searchSettings;

  // Добавляем свойство для хранения текущего выбранного элемента (группа/преподаватель)
  SearchEntity? _currentEntity;
  SearchEntity? get currentEntity => _currentEntity;

  // Метод для установки текущего выбранного элемента
  void setCurrentEntity(SearchEntity entity) {
    _currentEntity = entity;
    notifyListeners();
  }

  // Метод для очистки текущего выбранного элемента
  void clearCurrentEntity() {
    _currentEntity = null;
    notifyListeners();
  }

  Map<String, Map<String, List<ScheduleItem>>>? get scheduleData =>
      _currentScheduleData;

  // Кэш хронологически отсортированных дат текущего расписания.
  // Порядок ключей Map зависит от порядка строк в SQLite и не является
  // хронологическим, поэтому опираться на него в UI нельзя.
  List<String>? _orderedDatesCache;
  Map<String, Map<String, List<ScheduleItem>>>? _orderedDatesSource;

  /// Даты текущего расписания в хронологическом порядке.
  List<String> get orderedDates {
    final data = _currentScheduleData;
    if (data == null || data.isEmpty) return const <String>[];

    if (!identical(_orderedDatesSource, data) ||
        _orderedDatesCache == null ||
        _orderedDatesCache!.length != data.length) {
      _orderedDatesSource = data;
      _orderedDatesCache = DateService.sortDateKeys(data.keys);
    }
    return _orderedDatesCache!;
  }

  Map<String, Map<String, List<ScheduleItem>>>? get fullScheduleData =>
      _fullScheduleData;
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
  bool get scheduleUnpublished => _scheduleUnpublished;

  ScheduleProvider() {
    // Раньше здесь стоял Timer.periodic(5 сек), который на каждом тике дёргал
    // платформенный вызов проверки сети и мог вызывать notifyListeners().
    // Это разряжало батарею и приводило к лишним перестроениям всего дерева.
    // Теперь слушаем поток изменений подключения — событие приходит только
    // при реальной смене состояния сети.
    _connectivitySubscription = ConnectivityService().onStatusChanged.listen(
      _onConnectivityChanged,
    );

    // Стартовое состояние сети
    _checkConnectivity();

    // Инициализируем настройки отображения
    _initDisplayDays();

    // Загружаем настройки подсказок поиска
    _loadSearchSuggestionSettings();
  }

  void _onConnectivityChanged(bool isOnline) {
    if (_isOffline == !isOnline) return;

    _isOffline = !isOnline;
    notifyListeners();

    // Сохраняем прежнее поведение: при возвращении связи расписание
    // подтягивается сразу, а не ждёт окна фоновой синхронизации.
    // Параллельный запуск отсекается флагом _isUpdating внутри updateSchedule.
    if (isOnline) {
      updateSchedule(silent: true);
    }
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

      if ((currentSchedule.isNotEmpty || archiveSchedule.isNotEmpty) &&
          _mounted) {
        _currentScheduleData = currentSchedule;
        _fullScheduleData = archiveSchedule;

        // Проверяем, не пусто ли текущее расписание, и если да - восстанавливаем из архива
        if (_currentScheduleData == null || _currentScheduleData!.isEmpty) {
          debugPrint('🔄 Текущее расписание пусто, восстанавливаем из архива');

          // Получаем только актуальное расписание из архива
          final actualSchedule = await _db.getActualArchiveSchedule();

          if (actualSchedule.isNotEmpty) {
            _currentScheduleData = actualSchedule;

            // Сохраняем восстановленные данные
            await _db.saveCurrentSchedule(_currentScheduleData!);
            debugPrint('✅ Текущее расписание восстановлено из архива');
          }
        }

        notifyListeners();

        // Обновляем виджет при загрузке из архива
        updateHomeWidget();

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
      final nothingToShow =
          _currentScheduleData == null || _currentScheduleData!.isEmpty;
      if (shouldUpdate || nothingToShow) {
        // Первая загрузка идёт с индикатором, а не молча.
        //
        // Разбор расписания всего колледжа на бюджетном телефоне занимает
        // около минуты, и всё это время экран показывал «Нет данных» с
        // кнопкой «Повторить загрузку»: приложение выглядело сломанным
        // сразу после установки, а нажатие кнопки только начинало работу
        // заново. Когда данные уже есть, обновление по-прежнему тихое —
        // подменять готовое расписание спиннером незачем.
        await updateSchedule(silent: !nothingToShow);
      } else {
        _isLoaded = true;
        _updateStatus(null);
        notifyListeners();
        // Обновляем виджет после загрузки
        updateHomeWidget();
      }
    } catch (e, stackTrace) {
      developer.log(
        'Ошибка при загрузке расписания:',
        error: e,
        stackTrace: stackTrace,
      );
      _handleError(
        'Не удалось загрузить расписание',
        details: 'Проверьте подключение к интернету и попробуйте снова',
      );
    }
  }

  Future<ScheduleDiffResult?> updateSchedule({bool silent = false}) async {
    // Дешёвая отсечка на явном случае: сетевых интерфейсов нет вообще.
    // Обратное — не доказательство связи, поэтому решающая проверка ниже,
    // по результату самого запроса.
    if (!await ConnectivityService().isOnline()) {
      _setOffline(true);
      _handleError(
        'Нет подключения к интернету',
        details: 'Показано сохранённое расписание',
      );
      return null;
    }

    // Предотвращаем параллельные обновления
    if (_isUpdating) {
      debugPrint('⏭️ Обновление уже выполняется, пропускаем');
      return null;
    }

    _isUpdating = true;

    if (!silent) {
      _isLoading = true;
      _updateStatus('Обновление расписания...');
      notifyListeners();
    }

    try {
      // Снимок, с которым будем сравнивать новые данные.
      //
      // В фоновой задаче Workmanager провайдер создаётся заново в другом
      // изоляте и его _currentScheduleData пуст. Раньше из-за этого
      // _previousScheduleData всегда оказывался null, сравнение не
      // выполнялось, и уведомления об изменениях не приходили никогда —
      // работал только показ «обновлено» при ручном обновлении.
      // Поэтому если в памяти пусто, берём предыдущий снимок из базы.
      final baseline = _currentScheduleData ?? await _db.getCurrentSchedule();
      _previousScheduleData = baseline.isEmpty ? null : _actualOnly(baseline);

      final prefs = await SharedPreferences.getInstance();
      final previousHash = prefs.getString(_pageHashKey);

      final result = await _parser.parseSchedule(previousHash: previousHash);

      if (result.error != null) {
        if (result.networkFailure) {
          // Запрос не дошёл до сайта. Это и есть единственная надёжная
          // примета офлайна: список сетевых интерфейсов о доступности
          // интернета не говорит ничего (см. _setOffline).
          _setOffline(true);
          _handleError(
            'Нет связи с сайтом колледжа',
            details: 'Показано сохранённое расписание',
          );
          return null;
        }

        if (result.siteUnavailable) {
          // Сайт жив, но сейчас отвечает ошибкой. Разбор тут ни при чём,
          // и в Crashlytics такому не место: пятисотки от bartc.by
          // случаются регулярно и завалили бы отчёты, скрыв настоящую
          // поломку разбора.
          _handleError(
            'Сайт колледжа не отвечает',
            details: 'Показано сохранённое расписание, попробуем позже',
          );
          return null;
        }

        // Сайт колледжа рано или поздно поменяет вёрстку, и приложение
        // молча перестанет обновляться. Отметка в Crashlytics — способ
        // узнать об этом раньше, чем начнут жаловаться пользователи.
        // Сетевые сбои и временные ошибки сайта сюда не попадают: их
        // десятки тысяч в день, и настоящая поломка разбора утонула бы.
        CrashReporter.reportParseFailure(result.error!);
        _handleError('Ошибка обновления', details: result.error);
        return null;
      }

      // Ответ получен — что бы в нём ни было, связь есть.
      _setOffline(false);

      // Страница на сайте не изменилась: разбор не выполнялся, писать в базу
      // нечего. Отмечаем факт успешной проверки и выходим.
      // Расписания на сайте нет — это законное состояние, а не сбой.
      if (result.noSchedule) {
        await _reportEmptyPageOnce(result.contentHash);

        // Хэш намеренно НЕ сохраняем. Пустой страница может оказаться и
        // из-за съехавшей вёрстки, а её чинят правкой `parser_columns` в
        // удалённом конфиге. Запомни мы хэш — следующая проверка ушла бы в
        // `notModified`, разбор не повторился бы, и починка не подействовала
        // бы до тех пор, пока колледж сам не изменит страницу.
        await prefs.setString(
          'last_schedule_update',
          DateTime.now().toIso8601String(),
        );
        _scheduleUnpublished = true;
        _isLoaded = true;
        _error = null;
        _errorMessage = null;
        _errorDetails = null;
        _showError = false;
        if (!silent) {
          _showSuccess = true;
          _successMessage = 'На сайте колледжа пока нет расписания';
        }
        return null;
      }

      if (result.notModified) {
        await prefs.setString(
          'last_schedule_update',
          DateTime.now().toIso8601String(),
        );
        _isLoaded = true;
        _error = null;
        if (!silent) {
          _showSuccess = true;
          _successMessage = 'Расписание актуально';
        }
        return null;
      }

      if (result.schedule.isNotEmpty) {
        _scheduleUnpublished = false;
        _currentScheduleData = result.schedule;
        await _db.saveCurrentSchedule(_currentScheduleData!);
        await _db.archiveSchedule(_currentScheduleData!);
        _fullScheduleData = await _db.getArchiveSchedule();

        _groups = result.groups;
        _teachers = result.teachers;

        await _db.saveGroupsAndTeachers(_groups, _teachers);

        await prefs.setString(
          'last_schedule_update',
          DateTime.now().toIso8601String(),
        );
        if (result.contentHash != null) {
          await prefs.setString(_pageHashKey, result.contentHash!);
        }

        await _cleanOldSchedule();

        _isLoaded = true;
        _error = null;

        // Инвалидируем кэш после успешного обновления
        _cacheService.invalidateScheduleCache();

        // Сравниваем расписание и получаем изменения.
        // Обе стороны приводим к актуальным дням: снимок из базы уже
        // отфильтрован по дате, и без такой же фильтрации свежих данных
        // вчерашний день, ещё висящий на сайте, выглядел бы как добавленный.
        ScheduleDiffResult? diffResult;
        if (_previousScheduleData != null &&
            _previousScheduleData!.isNotEmpty) {
          diffResult = ScheduleDiffService.compareSchedules(
            _previousScheduleData!,
            _actualOnly(_currentScheduleData!),
          );

          debugPrint('📊 Изменения в расписании: ${diffResult.summary}');
        }

        if (!silent) {
          _showSuccess = true;
          if (diffResult != null && diffResult.hasChanges) {
            _successMessage = 'Расписание обновлено. ${diffResult.summary}';
          } else {
            _successMessage = 'Расписание успешно обновлено';
          }
        }

        // Обновляем виджет после обновления расписания
        await updateHomeWidget();

        return diffResult;
      }
    } catch (e) {
      debugPrint('❌ Ошибка обновления: $e');
      _handleError(
        'Ошибка обновления',
        details: 'Проверьте подключение к интернету и попробуйте снова',
      );
      return null;
    } finally {
      _isLoading = false;
      _isUpdating = false;
      _updateStatus(null);

      // Явно уведомляем слушателей для обновления UI
      notifyListeners();
    }
    return null;
  }

  /// Ключ, под которым запомнена версия страницы, о пустоте которой уже
  /// доложено. Нужен, чтобы не слать один и тот же отчёт каждые 15 минут.
  static const String _emptyPageReportKey = 'last_reported_empty_page';

  /// Сообщает о пустой странице один раз на каждую её версию.
  ///
  /// Пустая страница — это либо каникулы, либо съехавшая вёрстка, и снаружи
  /// они неразличимы. Молчать нельзя: поломку разбора надо заметить раньше
  /// пользователей. Слать каждый раз тоже нельзя: за лето это десятки тысяч
  /// одинаковых отчётов от каждого устройства, в которых утонет настоящая
  /// авария. Поэтому отчёт уходит один раз на каждую новую версию страницы:
  /// сменилась вёрстка — новый хэш — новый отчёт.
  Future<void> _reportEmptyPageOnce(String? contentHash) async {
    if (contentHash == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_emptyPageReportKey) == contentHash) return;
      await prefs.setString(_emptyPageReportKey, contentHash);
      CrashReporter.reportParseFailure(
        'Страница расписания разобрана, но не содержит ни одного дня. '
        'Это либо каникулы, либо изменилась вёрстка сайта.',
      );
    } catch (e) {
      debugPrint('⚠️ Не удалось отметить пустую страницу: $e');
    }
  }

  /// Оставляет только сегодняшние и будущие дни.
  ///
  /// Изменения в уже прошедших днях пользователю не интересны, а главное —
  /// снимок из таблицы current_schedule и так читается с этим фильтром,
  /// поэтому сравнивать с нефильтрованными свежими данными нельзя.
  Map<String, Map<String, List<ScheduleItem>>> _actualOnly(
    Map<String, Map<String, List<ScheduleItem>>> data,
  ) {
    final result = <String, Map<String, List<ScheduleItem>>>{};
    data.forEach((date, groups) {
      if (DateService.isActualDate(date)) {
        result[date] = groups;
      }
    });
    return result;
  }

  /// Получает список изменений между текущим и предыдущим расписанием
  ScheduleDiffResult? getScheduleChanges() {
    if (_previousScheduleData == null || _currentScheduleData == null) {
      return null;
    }
    return ScheduleDiffService.compareSchedules(
      _previousScheduleData!,
      _currentScheduleData!,
    );
  }

  Future<void> updateStorageDays(int days) async {
    // Минимальный период хранения - 30 дней или выбранное пользователем значение (что больше)
    _storageDays = days > 30 ? days : 30;
    // Сохраняем выбранное пользователем значение для отображения
    _displayDays = days;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('schedule_storage_days', days);
    await _cleanOldSchedule();

    // Инвалидируем кэш, чтобы обновить данные в календаре
    _cacheService.invalidateScheduleCache();

    notifyListeners();
  }

  Future<void> _cleanOldSchedule() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userSelectedDays = prefs.getInt('schedule_storage_days') ?? 30;

      // Используем выбранное пользователем значение для очистки календаря
      _storageDays = userSelectedDays;
      _displayDays = userSelectedDays;

      debugPrint('🧹 Очистка старого расписания');
      debugPrint('📅 Период хранения: $_storageDays дней');

      // Очищаем старые данные из базы данных
      await _db.cleanOldArchive(_storageDays);

      // Обновляем локальное состояние fullScheduleData
      if (_fullScheduleData != null) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final cutoffDate = today.subtract(Duration(days: _storageDays));

        debugPrint('📅 Дата отсечения: ${cutoffDate.toString()}');

        final keysToRemove = <String>[];

        // Собираем ключи для удаления, используя DateService
        for (var dateStr in _fullScheduleData!.keys) {
          if (DateService.shouldDeleteFromArchive(dateStr, _storageDays)) {
            keysToRemove.add(dateStr);
            debugPrint('❌ Удаляем устаревшую дату: $dateStr');
          } else {
            debugPrint('✅ Оставляем дату: $dateStr');
          }
        }

        // Удаляем устаревшие данные
        for (var key in keysToRemove) {
          _fullScheduleData!.remove(key);
        }

        debugPrint('📊 Удалено дней: ${keysToRemove.length}');
        debugPrint('📊 Осталось дней: ${_fullScheduleData!.keys.length}');

        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ Ошибка при очистке старого расписания: $e');
    }
  }

  Future<void> loadGroupsAndTeachers() async {
    try {
      developer.log('Начало загрузки групп и преподавателей из базы');

      final db = await _db.database;
      final groupsResult = await db.query('groups');
      final teachersResult = await db.query('teachers');

      _groups = groupsResult.map((e) => e['name'] as String).toList();
      _teachers = teachersResult.map((e) => e['name'] as String).toList();

      developer.log(
        'Загружено из базы:',
        error: {
          'Количество групп': _groups.length,
          'Группы': _groups,
          'Количество преподавателей': _teachers.length,
        },
      );

      notifyListeners();
    } catch (e, stackTrace) {
      developer.log(
        'Ошибка загрузки групп и преподавателей:',
        error: e,
        stackTrace: stackTrace,
      );
    }
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
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    super.dispose();
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

  /// Отмечает состояние связи по факту удавшегося или сорвавшегося запроса.
  ///
  /// Список сетевых интерфейсов, который отдаёт `connectivity_plus`, о
  /// доступности интернета не говорит ничего. Проверено на телефоне с
  /// поднятым VPN: при выключенных Wi-Fi и мобильных данных
  /// `checkConnectivity` возвращает `[ConnectivityResult.vpn]` — интерфейс
  /// VPN остаётся «подключённым», когда канала под ним уже нет. Ровно так же
  /// выглядят captive portal в колледже и нулевой баланс на симке.
  /// Поэтому офлайн определяется по тому, дошёл ли запрос до сайта.
  void _setOffline(bool value) {
    if (_isOffline == value) return;
    _isOffline = value;
    notifyListeners();
  }

  Future<void> _checkConnectivity() async {
    // Синхронизацию при восстановлении связи выполняет ConnectivityService,
    // здесь только отражаем состояние в UI, чтобы не запускать два
    // конкурирующих обновления расписания одновременно.
    final isOnline = await ConnectivityService().isOnline();
    if (!_mounted) return;

    if (_isOffline != !isOnline) {
      _isOffline = !isOnline;
      notifyListeners();
    }
  }

  // Получает расписание для календаря с учетом настроек отображения
  Map<String, Map<String, List<ScheduleItem>>>? getScheduleForCalendar() {
    // Возвращаем полные данные архива для отображения в календаре
    return _fullScheduleData;
  }

  // Подготавливаем данные заранее

  // Получаем подготовленные данные для даты
  List<ScheduleItem> getPreparedSchedule(String date) {
    return _cacheService.getPreparedSchedule(date) ?? [];
  }

  // Получаем отфильтрованные данные
  List<ScheduleItem> getFilteredSchedule(String date, String query) {
    final cacheKey = _cacheService.createFilterKey(date, 'search', query);

    // Проверяем кэш
    final cached = _cacheService.getFilteredData(cacheKey);
    if (cached != null) {
      return cached;
    }

    final lessons = getPreparedSchedule(date);
    if (query.isEmpty) {
      return lessons;
    }

    final lowercaseQuery = query.toLowerCase();
    final filtered = lessons
        .where(
          (lesson) =>
              lesson.group.toLowerCase().contains(lowercaseQuery) ||
              lesson.teacher.toLowerCase().contains(lowercaseQuery) ||
              lesson.classroom.toLowerCase().contains(lowercaseQuery) ||
              lesson.subject.toLowerCase().contains(lowercaseQuery),
        )
        .toList();

    _cacheService.setFilteredData(cacheKey, filtered);
    return filtered;
  }

  void clearCache() {
    _cacheService.clearAll();
    _orderedDatesCache = null;
    _orderedDatesSource = null;
    // Необходимо принудительно уведомить слушателей при очистке кэша
    notifyListeners();
  }

  /// Полный сброс состояния после очистки базы данных с последующей
  /// перезагрузкой. Без него экран продолжал показывать расписание,
  /// которого в базе уже нет.
  Future<void> reloadAfterDataCleared() async {
    _currentScheduleData = null;
    _fullScheduleData = null;
    _previousScheduleData = null;
    _groups = [];
    _teachers = [];
    _isLoaded = false;
    _error = null;
    _errorMessage = null;
    _showError = false;
    _orderedDatesCache = null;
    _orderedDatesSource = null;
    _cacheService.clearAll();

    // Сбрасываем хэш страницы, иначе следующая загрузка решит,
    // что расписание не изменилось, и не заполнит пустую базу.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pageHashKey);

    notifyListeners();

    await loadSchedule();
  }

  // Добавим метод для синхронизации currentScheduleData с fullScheduleData
  Future<void> syncScheduleData() async {
    try {
      if (_fullScheduleData != null && _fullScheduleData!.isNotEmpty) {
        if (_currentScheduleData == null || _currentScheduleData!.isEmpty) {
          debugPrint(
            '🔄 Синхронизация данных: восстановление текущего расписания из архива',
          );

          // Получаем только актуальное расписание из архива
          final actualSchedule = await _db.getActualArchiveSchedule();

          if (actualSchedule.isNotEmpty) {
            _currentScheduleData = actualSchedule;
            await _db.saveCurrentSchedule(_currentScheduleData!);
            notifyListeners();
            // Обновляем виджет после синхронизации
            updateHomeWidget();
            debugPrint('✅ Синхронизация выполнена успешно');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Ошибка при синхронизации данных: $e');
    }
  }

  // Загрузка настроек подсказок поиска из SharedPreferences
  Future<void> _loadSearchSuggestionSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString('search_suggestion_settings');

      if (settingsJson != null) {
        final Map<String, dynamic> jsonMap = json.decode(settingsJson);
        _searchSettings = SearchSuggestionSettings.fromJson(jsonMap);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Ошибка при загрузке настроек подсказок поиска: $e');
    }
  }

  // Сохранение настроек подсказок поиска в SharedPreferences
  Future<void> saveSearchSuggestionSettings(
    SearchSuggestionSettings settings,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = json.encode(settings.toJson());
      await prefs.setString('search_suggestion_settings', settingsJson);

      _searchSettings = settings;
      notifyListeners();
    } catch (e) {
      debugPrint('Ошибка при сохранении настроек подсказок поиска: $e');
    }
  }

  // Добавление элемента в избранные группы
  Future<void> addFavoriteGroup(String group) async {
    if (!_searchSettings.favoriteGroups.contains(group)) {
      final updatedGroups = List<String>.from(_searchSettings.favoriteGroups)
        ..add(group);
      await saveSearchSuggestionSettings(
        _searchSettings.copyWith(favoriteGroups: updatedGroups),
      );
    }
  }

  // Удаление элемента из избранных групп
  Future<void> removeFavoriteGroup(String group) async {
    if (_searchSettings.favoriteGroups.contains(group)) {
      final updatedGroups = List<String>.from(_searchSettings.favoriteGroups)
        ..remove(group);
      await saveSearchSuggestionSettings(
        _searchSettings.copyWith(favoriteGroups: updatedGroups),
      );
    }
  }

  // Добавление элемента в избранные преподаватели
  Future<void> addFavoriteTeacher(String teacher) async {
    if (!_searchSettings.favoriteTeachers.contains(teacher)) {
      final updatedTeachers = List<String>.from(
        _searchSettings.favoriteTeachers,
      )..add(teacher);
      await saveSearchSuggestionSettings(
        _searchSettings.copyWith(favoriteTeachers: updatedTeachers),
      );
    }
  }

  // Удаление элемента из избранных преподавателей
  Future<void> removeFavoriteTeacher(String teacher) async {
    if (_searchSettings.favoriteTeachers.contains(teacher)) {
      final updatedTeachers = List<String>.from(
        _searchSettings.favoriteTeachers,
      )..remove(teacher);
      await saveSearchSuggestionSettings(
        _searchSettings.copyWith(favoriteTeachers: updatedTeachers),
      );
    }
  }

  // Добавление элемента в избранные кабинеты
  Future<void> addFavoriteClassroom(String classroom) async {
    if (!_searchSettings.favoriteClassrooms.contains(classroom)) {
      final updatedClassrooms = List<String>.from(
        _searchSettings.favoriteClassrooms,
      )..add(classroom);
      await saveSearchSuggestionSettings(
        _searchSettings.copyWith(favoriteClassrooms: updatedClassrooms),
      );
    }
  }

  // Удаление элемента из избранных кабинетов
  Future<void> removeFavoriteClassroom(String classroom) async {
    if (_searchSettings.favoriteClassrooms.contains(classroom)) {
      final updatedClassrooms = List<String>.from(
        _searchSettings.favoriteClassrooms,
      )..remove(classroom);
      await saveSearchSuggestionSettings(
        _searchSettings.copyWith(favoriteClassrooms: updatedClassrooms),
      );
    }
  }

  // Добавление элемента в избранные предметы
  Future<void> addFavoriteSubject(String subject) async {
    if (!_searchSettings.favoriteSubjects.contains(subject)) {
      final updatedSubjects = List<String>.from(
        _searchSettings.favoriteSubjects,
      )..add(subject);
      await saveSearchSuggestionSettings(
        _searchSettings.copyWith(favoriteSubjects: updatedSubjects),
      );
    }
  }

  // Удаление элемента из избранных предметов
  Future<void> removeFavoriteSubject(String subject) async {
    if (_searchSettings.favoriteSubjects.contains(subject)) {
      final updatedSubjects = List<String>.from(
        _searchSettings.favoriteSubjects,
      )..remove(subject);
      await saveSearchSuggestionSettings(
        _searchSettings.copyWith(favoriteSubjects: updatedSubjects),
      );
    }
  }

  // Переключение режима избранного
  Future<void> toggleFavoritesMode(bool useFavorites) async {
    await saveSearchSuggestionSettings(
      _searchSettings.copyWith(useFavorites: useFavorites),
    );
  }

  // Переключение показа групп
  Future<void> toggleShowGroups(bool show) async {
    await saveSearchSuggestionSettings(
      _searchSettings.copyWith(showGroups: show),
    );
  }

  // Переключение показа преподавателей
  Future<void> toggleShowTeachers(bool show) async {
    await saveSearchSuggestionSettings(
      _searchSettings.copyWith(showTeachers: show),
    );
  }

  // Переключение показа кабинетов
  Future<void> toggleShowClassrooms(bool show) async {
    await saveSearchSuggestionSettings(
      _searchSettings.copyWith(showClassrooms: show),
    );
  }

  // Переключение показа предметов
  Future<void> toggleShowSubjects(bool show) async {
    await saveSearchSuggestionSettings(
      _searchSettings.copyWith(showSubjects: show),
    );
  }

  // Получение избранных подсказок поиска
  List<String> getFavoriteSuggestions() {
    final suggestions = <String>[];

    if (_searchSettings.showGroups) {
      suggestions.addAll(_searchSettings.favoriteGroups);
    }

    if (_searchSettings.showTeachers) {
      suggestions.addAll(_searchSettings.favoriteTeachers);
    }

    if (_searchSettings.showClassrooms) {
      suggestions.addAll(_searchSettings.favoriteClassrooms);
    }

    if (_searchSettings.showSubjects) {
      suggestions.addAll(_searchSettings.favoriteSubjects);
    }

    return suggestions.take(7).toList();
  }

  // Обновление данных виджета
  Future<void> updateHomeWidget() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final query = prefs.getString('last_search_query') ?? '';
      // Область поиска важна и здесь: без неё виджет группы 209 показывал
      // бы ещё и чужие пары, проходящие в кабинете 209.
      final scope = EntityTypeLabel.fromStorage(
        prefs.getString('last_search_scope'),
      );
      await HomeWidgetService.updateScheduleWidget(
        _currentScheduleData,
        query,
        scope: scope,
      );
      await HomeWidgetService.updateBellScheduleData();
    } catch (e) {
      debugPrint('❌ Ошибка обновления виджета: $e');
    }
  }
}
