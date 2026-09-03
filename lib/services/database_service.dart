import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/schedule_model.dart';
import '../models/note_model.dart';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'date_service.dart';

// Работа с базой данных SQLite
// Храним тут расписание, заметки и настройки

class DatabaseService {
  static Database? _database;
  static const int _databaseVersion = 3;

  // Кэш для данных
  static Map<String, Map<String, List<ScheduleItem>>> _scheduleCache = {};
  static final Map<String, List<String>> _listsCache = {};
  static bool _isInitialized = false;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  // Создаем/открываем базу
  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'schedule.db');

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          // Добавляем индексы для существующих баз данных
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_current_schedule_date ON current_schedule(date)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_current_schedule_group ON current_schedule(group_name)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_archive_schedule_date ON archive_schedule(date)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_archive_schedule_group ON archive_schedule(group_name)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_notes_date ON notes(date)',
          );
        }
      },
    );
  }

  // Создаем все таблицы с индексами для оптимизации запросов
  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE current_schedule (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        group_name TEXT NOT NULL,
        lesson_number INTEGER NOT NULL,
        subject TEXT NOT NULL,
        teacher TEXT NOT NULL,
        classroom TEXT NOT NULL,
        subgroup TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE archive_schedule (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        group_name TEXT NOT NULL,
        lesson_number INTEGER NOT NULL,
        subject TEXT NOT NULL,
        teacher TEXT NOT NULL,
        classroom TEXT NOT NULL,
        subgroup TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )
    ''');

    await db.execute('''
      CREATE TABLE teachers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )
    ''');

    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        text TEXT NOT NULL
      )
    ''');

    // Создаем индексы для оптимизации запросов
    await db.execute(
      'CREATE INDEX idx_current_schedule_date ON current_schedule(date)',
    );
    await db.execute(
      'CREATE INDEX idx_current_schedule_group ON current_schedule(group_name)',
    );
    await db.execute(
      'CREATE INDEX idx_archive_schedule_date ON archive_schedule(date)',
    );
    await db.execute(
      'CREATE INDEX idx_archive_schedule_group ON archive_schedule(group_name)',
    );
    await db.execute('CREATE INDEX idx_notes_date ON notes(date)');
  }

  Future<void> cacheGroupsAndTeachers(
    List<String> groups,
    List<String> teachers,
  ) async {
    final db = await database;
    final batch = db.batch();

    batch.delete('groups');
    batch.delete('teachers');

    for (var group in groups) {
      batch.insert('groups', {'name': group});
    }
    for (var teacher in teachers) {
      batch.insert('teachers', {'name': teacher});
    }

    await batch.commit(noResult: true);
  }

  // Сохраняем текущее расписание с использованием батчинга для производительности
  Future<void> saveCurrentSchedule(
    Map<String, Map<String, List<ScheduleItem>>> scheduleData,
  ) async {
    final db = await database;
    final batch = db.batch();

    // Удаляем старое расписание
    batch.delete('current_schedule');

    // Добавляем все записи в батч
    for (var date in scheduleData.keys) {
      for (var group in scheduleData[date]!.keys) {
        for (var item in scheduleData[date]![group]!) {
          batch.insert('current_schedule', {
            'date': date,
            'group_name': group,
            'lesson_number': item.lessonNumber,
            'subject': item.subject,
            'teacher': item.teacher,
            'classroom': item.classroom,
            'subgroup': item.subgroup,
          });
        }
      }
    }

    // Выполняем все операции одной транзакцией
    await batch.commit(noResult: true);
  }

  // Переносим расписание в архив.
  //
  // Архив — это последняя известная версия каждого дня; из него читает
  // календарь. Раньше день записывался только при условии
  // `existing.isEmpty`, то есть первая попавшая в архив версия дня
  // замораживалась навсегда: после замены пары или смены кабинета
  // экран расписания показывал новые данные, а календарь — старые.
  // Теперь записи дня заменяются целиком.
  //
  // Дни, которых нет в [scheduleData], не трогаются: за их удаление
  // отвечает cleanOldArchive по сроку хранения.
  Future<void> archiveSchedule(
    Map<String, Map<String, List<ScheduleItem>>> scheduleData,
  ) async {
    if (scheduleData.isEmpty) return;

    final db = await database;

    await db.transaction((txn) async {
      final batch = txn.batch();

      for (final date in scheduleData.keys) {
        batch.delete('archive_schedule', where: 'date = ?', whereArgs: [date]);

        for (final group in scheduleData[date]!.keys) {
          for (final item in scheduleData[date]![group]!) {
            batch.insert('archive_schedule', {
              'date': date,
              'group_name': group,
              'lesson_number': item.lessonNumber,
              'subject': item.subject,
              'teacher': item.teacher,
              'classroom': item.classroom,
              'subgroup': item.subgroup,
            });
          }
        }
      }

      await batch.commit(noResult: true);
    });
  }

  Future<Map<String, Map<String, List<ScheduleItem>>>>
  getCurrentSchedule() async {
    return _getScheduleFromTable('current_schedule');
  }

  Future<Map<String, Map<String, List<ScheduleItem>>>>
  getArchiveSchedule() async {
    return _getScheduleFromTable('archive_schedule');
  }

  Future<Map<String, Map<String, List<ScheduleItem>>>> _getScheduleFromTable(
    String tableName,
  ) async {
    final db = await database;
    final scheduleData = <String, Map<String, List<ScheduleItem>>>{};

    final List<Map<String, dynamic>> results = await db.query(tableName);

    final Set<String> uniqueDates = {};

    for (var row in results) {
      final date = row['date'] as String;

      // Добавляем фильтрацию для current_schedule, чтобы всегда показывать только актуальные даты
      if (tableName == 'current_schedule' && !DateService.isActualDate(date)) {
        continue; // Пропускаем устаревшие даты для текущего расписания
      }

      uniqueDates.add(date);
      final group = row['group_name'] as String;

      scheduleData.putIfAbsent(date, () => {});
      scheduleData[date]!.putIfAbsent(group, () => []);

      scheduleData[date]![group]!.add(
        ScheduleItem(
          group: group,
          lessonNumber: row['lesson_number'] as int,
          subject: row['subject'] as String,
          teacher: row['teacher'] as String,
          classroom: row['classroom'] as String,
          subgroup: row['subgroup'] as String?,
        ),
      );
    }

    return scheduleData;
  }

  /// Префикс "YYYY-MM-DD" для поиска заметок по дню независимо от времени.
  ///
  /// В таблице notes нет UNIQUE по date, поэтому ConflictAlgorithm.replace
  /// никогда не срабатывал и каждое сохранение добавляло новую строку.
  /// Вдобавок дата сохранялась целиком со временем: если день выбирался
  /// с ненулевым временем (при открытии календаря выбран DateTime.now()),
  /// то удаление по точному совпадению даты не находило строку —
  /// заметка исчезала только из памяти и возвращалась после перезапуска.
  static String _dayPrefix(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.toIso8601String().split('T').first;
  }

  Future<void> saveNote(Note note) async {
    final db = await database;
    final normalized = DateTime(note.date.year, note.date.month, note.date.day);

    await db.transaction((txn) async {
      // Убираем прежние записи этого дня, включая созданные старой версией
      // приложения со временем в дате.
      await txn.delete(
        'notes',
        where: 'date LIKE ?',
        whereArgs: ['${_dayPrefix(note.date)}%'],
      );
      await txn.insert('notes', {
        'date': normalized.toIso8601String(),
        'text': note.text,
      });
    });
  }

  Future<List<Note>> getNotes() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query('notes');
      return List.generate(maps.length, (i) => Note.fromMap(maps[i]));
    } catch (e) {
      return [];
    }
  }

  Future<void> deleteNote(DateTime date) async {
    try {
      final db = await database;
      await db.delete(
        'notes',
        where: 'date LIKE ?',
        whereArgs: ['${_dayPrefix(date)}%'],
      );
    } catch (e) {
      debugPrint('Ошибка при удалении заметки: $e');
    }
  }

  Future<void> clearDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'schedule.db');
    await deleteDatabase(path);
    _database = null;
  }

  // ВНИМАНИЕ: здесь раньше был метод cleanOldSchedule(int days), который
  // сравнивал столбец date (формат "dd.MM.yyyy") со строкой
  // cutoffDate.toIso8601String() (формат "2026-08-04T..."). Это сравнение
  // двух разных форматов как текста: любая дата с днём месяца 01–19
  // считалась меньше порога и удалялась независимо от возраста,
  // а дни 20–31 не удалялись никогда.
  //
  // Метод нигде не вызывался (очисткой занимаются cleanOldArchive и
  // _cleanCurrentSchedule, оба через DateService), поэтому он удалён,
  // чтобы его случайно не подключили.

  // Чистим старые записи из архива
  // Оставляем только за последние N дней
  Future<void> cleanOldArchive(int days) async {
    final db = await database;

    debugPrint('🧹 Очистка архива в базе данных');
    debugPrint('📅 Период хранения: $days дней');

    final records = await db.query(
      'archive_schedule',
      distinct: true,
      columns: ['date'],
    );
    int deletedCount = 0;

    // Используем batch для более эффективного удаления
    final batch = db.batch();

    for (var record in records) {
      final dateStr = record['date'] as String;

      if (DateService.shouldDeleteFromArchive(dateStr, days)) {
        batch.delete(
          'archive_schedule',
          where: 'date = ?',
          whereArgs: [dateStr],
        );
        deletedCount++;
        debugPrint('❌ Помечена для удаления: $dateStr');
      } else {
        debugPrint('✅ Оставлена дата в БД: $dateStr');
      }
    }

    // Выполняем все удаления одной транзакцией
    if (deletedCount > 0) {
      await batch.commit(noResult: true);
      debugPrint('📊 Удалено дней из БД: $deletedCount');
    } else {
      debugPrint('📊 Нет данных для удаления');
    }

    // Также очищаем текущее расписание от старых записей
    await _cleanCurrentSchedule(days);
  }

  // Очищаем текущее расписание от старых записей
  Future<void> _cleanCurrentSchedule(int days) async {
    final db = await database;
    final records = await db.query(
      'current_schedule',
      distinct: true,
      columns: ['date'],
    );
    int deletedCount = 0;

    final batch = db.batch();

    for (var record in records) {
      final dateStr = record['date'] as String;

      if (DateService.shouldDeleteFromArchive(dateStr, days)) {
        batch.delete(
          'current_schedule',
          where: 'date = ?',
          whereArgs: [dateStr],
        );
        deletedCount++;
      }
    }

    if (deletedCount > 0) {
      await batch.commit(noResult: true);
      debugPrint(
        '📊 Удалено старых записей из текущего расписания: $deletedCount',
      );
    }
  }

  Future<void> recreateDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'schedule.db');

    if (_database != null) {
      await _database!.close();
      _database = null;
    }

    await deleteDatabase(path);
    _database = await _initDB();
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

  // Проверяет надо ли обновить расписание
  // Обновляем если:
  // - прошло больше 3 часов
  // - новый день
  // - нет сохраненного расписания
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

  Future<void> saveGroupsAndTeachers(
    List<String> groups,
    List<String> teachers,
  ) async {
    final db = await database;
    final batch = db.batch();

    batch.delete('groups');
    batch.delete('teachers');

    for (var group in groups) {
      batch.insert('groups', {'name': group});
    }
    for (var teacher in teachers) {
      batch.insert('teachers', {'name': teacher});
    }

    await batch.commit(noResult: true);
  }

  Future<void> updateLastUpdateTime() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().toIso8601String();
    await prefs.setString('last_update_time', now);
  }

  // Инициализация с предварительной загрузкой
  Future<void> _initialize() async {
    if (_isInitialized) return;

    final db = await database;
    // Предварительно загружаем все основные данные
    await Future.wait([
      _preloadSchedule(db),
      _preloadGroups(db),
      _preloadTeachers(db),
    ]);

    _isInitialized = true;
  }

  // Предварительная загрузка расписания
  Future<void> _preloadSchedule(Database db) async {
    _scheduleCache = await _getScheduleFromTable('current_schedule');
  }

  // Предварительная загрузка групп
  Future<void> _preloadGroups(Database db) async {
    final List<Map<String, dynamic>> maps = await db.query('groups');
    _listsCache['groups'] = maps.map((e) => e['name'] as String).toList();
  }

  // Предварительная загрузка преподавателей
  Future<void> _preloadTeachers(Database db) async {
    final List<Map<String, dynamic>> maps = await db.query('teachers');
    _listsCache['teachers'] = maps.map((e) => e['name'] as String).toList();
  }

  // Получение расписания из кэша
  Future<Map<String, Map<String, List<ScheduleItem>>>> getSchedule() async {
    await _initialize();
    return _scheduleCache;
  }

  // Получение групп из кэша
  Future<List<String>> getGroups() async {
    await _initialize();
    return _listsCache['groups'] ?? [];
  }

  // Получение преподавателей из кэша
  Future<List<String>> getTeachers() async {
    await _initialize();
    return _listsCache['teachers'] ?? [];
  }

  // Очистка кэша при обновлении данных
  void clearCache() {
    _scheduleCache.clear();
    _listsCache.clear();
    _isInitialized = false;
  }

  // Получаем только актуальное расписание из архива (текущий день и будущие дни)
  Future<Map<String, Map<String, List<ScheduleItem>>>>
  getActualArchiveSchedule() async {
    final db = await database;
    final scheduleData = <String, Map<String, List<ScheduleItem>>>{};

    final List<Map<String, dynamic>> results = await db.query(
      'archive_schedule',
    );

    debugPrint('🔍 Фильтрация актуального расписания из архива');

    for (var row in results) {
      final dateStr = row['date'] as String;

      // Используем DateService для проверки актуальности даты
      if (DateService.isActualDate(dateStr)) {
        final group = row['group_name'] as String;

        scheduleData.putIfAbsent(dateStr, () => {});
        scheduleData[dateStr]!.putIfAbsent(group, () => []);

        scheduleData[dateStr]![group]!.add(
          ScheduleItem(
            group: group,
            lessonNumber: row['lesson_number'] as int,
            subject: row['subject'] as String,
            teacher: row['teacher'] as String,
            classroom: row['classroom'] as String,
            subgroup: row['subgroup'] as String?,
          ),
        );

        debugPrint('✅ Добавлена актуальная дата: $dateStr');
      } else {
        debugPrint('❌ Пропущена устаревшая дата: $dateStr');
      }
    }

    debugPrint('📊 Восстановлено актуальных дней: ${scheduleData.keys.length}');
    return scheduleData;
  }
}
