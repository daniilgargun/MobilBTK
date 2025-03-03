import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/schedule_model.dart';
import '../models/note_model.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Работа с базой данных SQLite
// Храним тут расписание, заметки и настройки

class DatabaseService {
  static Database? _database;
  static const int _databaseVersion = 2;
  
  // Кэш для данных
  static Map<String, Map<String, List<ScheduleItem>>> _scheduleCache = {};
  static Map<String, List<String>> _listsCache = {};
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
    );
  }

  // Создаем все таблицы
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
  }

  Future<void> cacheGroupsAndTeachers(List<String> groups, List<String> teachers) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('groups');
      await txn.delete('teachers');

      for (var group in groups) {
        await txn.insert('groups', {'name': group});
      }
      for (var teacher in teachers) {
        await txn.insert('teachers', {'name': teacher});
      }
    });
  }

  // Сохраняем текущее расписание
  Future<void> saveCurrentSchedule(Map<String, Map<String, List<ScheduleItem>>> scheduleData) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('current_schedule');
      
      for (var date in scheduleData.keys) {
        for (var group in scheduleData[date]!.keys) {
          for (var item in scheduleData[date]![group]!) {
            await txn.insert('current_schedule', {
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
    });
  }

  // Переносим старое расписание в архив
  Future<void> archiveSchedule(Map<String, Map<String, List<ScheduleItem>>> scheduleData) async {
    final db = await database;
    
    await db.transaction((txn) async {
      for (var date in scheduleData.keys) {
        final existing = await txn.query(
          'archive_schedule',
          where: 'date = ?',
          whereArgs: [date],
        );

        if (existing.isEmpty) {
          for (var group in scheduleData[date]!.keys) {
            for (var item in scheduleData[date]![group]!) {
              await txn.insert('archive_schedule', {
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
      }
    });
  }

  Future<Map<String, Map<String, List<ScheduleItem>>>> getCurrentSchedule() async {
    return _getScheduleFromTable('current_schedule');
  }

  Future<Map<String, Map<String, List<ScheduleItem>>>> getArchiveSchedule() async {
    return _getScheduleFromTable('archive_schedule');
  }

  Future<Map<String, Map<String, List<ScheduleItem>>>> _getScheduleFromTable(String tableName) async {
    final db = await database;
    final scheduleData = <String, Map<String, List<ScheduleItem>>>{};
    
    final List<Map<String, dynamic>> results = await db.query(tableName);
    
    final Set<String> uniqueDates = {};
    
    for (var row in results) {
      final date = row['date'] as String;
      uniqueDates.add(date);
      final group = row['group_name'] as String;
      
      scheduleData.putIfAbsent(date, () => {});
      scheduleData[date]!.putIfAbsent(group, () => []);
      
      scheduleData[date]![group]!.add(ScheduleItem(
        group: group,
        lessonNumber: row['lesson_number'] as int,
        subject: row['subject'] as String,
        teacher: row['teacher'] as String,
        classroom: row['classroom'] as String,
        subgroup: row['subgroup'] as String?,
      ));
    }
    
    return scheduleData;
  }

  Future<void> saveNote(Note note) async {
    final db = await database;
    await db.insert(
      'notes',
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
        where: 'date = ?',
        whereArgs: [date.toIso8601String()],
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

  Future<void> cleanOldSchedule(int days) async {
    try {
      final db = await database;
      final cutoffDate = DateTime.now().subtract(Duration(days: days));
      
      await db.delete(
        'current_schedule',
        where: 'date < ?',
        whereArgs: [cutoffDate.toIso8601String()],
      );
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_schedule_cleanup', DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('Ошибка при очистке старого расписания: $e');
    }
  }

  // Чистим старые записи из архива
  // Оставляем только за последние N дней
  Future<void> cleanOldArchive(int days) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: days));
    
    final records = await db.query('archive_schedule', distinct: true, columns: ['date']);
    
    for (var record in records) {
      final dateStr = record['date'] as String;
      try {
        final date = _parseDate(dateStr);
        if (date.isBefore(cutoffDate)) {
          await db.delete(
            'archive_schedule',
            where: 'date = ?',
            whereArgs: [dateStr],
          );
        }
      } catch (e) {
        continue;
      }
    }
  }

  // Переводит строку с датой в DateTime
  // Например "01-март" -> DateTime
  DateTime _parseDate(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length != 2) {
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
    };
    
    final month = monthMap[monthStr];
    if (month == null) {
      throw FormatException('Неизвестный месяц: $monthStr');
    }
    
    final now = DateTime.now();
    var year = now.year;
    
    if (month < now.month) {
      year++;
    }
    
    return DateTime(year, month, day);
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
      
      if (lastUpdate.day != now.day || lastUpdate.month != now.month || lastUpdate.year != now.year) {
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

  Future<void> saveGroupsAndTeachers(List<String> groups, List<String> teachers) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('groups');
      await txn.delete('teachers');
      
      for (var group in groups) {
        await txn.insert('groups', {'name': group});
      }
      for (var teacher in teachers) {
        await txn.insert('teachers', {'name': teacher});
      }
    });
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
    final List<Map<String, dynamic>> maps = await db.query('current_schedule');
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
} 