import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/schedule_model.dart';
import '../models/note_model.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DatabaseService {
  static Database? _database;
  static const int _databaseVersion = 2;
  static Map<String, Map<String, List<ScheduleItem>>>? _scheduleCache;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

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
    
    for (var row in results) {
      final date = row['date'] as String;
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
      debugPrint('Ошибка при получении заметок: $e');
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

  Future<void> cleanOldArchive(int days) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: days));
    
    await db.delete(
      'archive_schedule',
      where: 'date < ?',
      whereArgs: [cutoffDate.toIso8601String()],
    );
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
} 