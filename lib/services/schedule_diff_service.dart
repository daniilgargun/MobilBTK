import '../models/schedule_model.dart';
import '../models/schedule_change.dart';

/// Сервис для сравнения двух версий расписания и определения изменений
class ScheduleDiffService {
  /// Сравнивает старое и новое расписание, возвращая список изменений
  static ScheduleDiffResult compareSchedules(
    Map<String, Map<String, List<ScheduleItem>>>? oldSchedule,
    Map<String, Map<String, List<ScheduleItem>>>? newSchedule,
  ) {
    if (oldSchedule == null || oldSchedule.isEmpty) {
      // Если старого расписания нет, считаем все новым
      final changes = <ScheduleChange>[];
      int newDaysCount = 0;

      newSchedule?.forEach((date, groups) {
        newDaysCount++;
        groups.forEach((group, items) {
          for (var item in items) {
            changes.add(ScheduleChange(
              type: ChangeType.added,
              date: date,
              group: group,
              newItem: item,
              description: 'Добавлено занятие: ${item.subject}',
            ));
          }
        });
      });

      return ScheduleDiffResult(
        changes: changes,
        hasChanges: changes.isNotEmpty,
        addedCount: changes.length,
        removedCount: 0,
        modifiedCount: 0,
        newDaysCount: newDaysCount,
      );
    }

    if (newSchedule == null || newSchedule.isEmpty) {
      // Если нового расписания нет, считаем все удаленным
      final changes = <ScheduleChange>[];

      oldSchedule.forEach((date, groups) {
        groups.forEach((group, items) {
          for (var item in items) {
            changes.add(ScheduleChange(
              type: ChangeType.removed,
              date: date,
              group: group,
              oldItem: item,
              description: 'Удалено занятие: ${item.subject}',
            ));
          }
        });
      });

      return ScheduleDiffResult(
        changes: changes,
        hasChanges: changes.isNotEmpty,
        addedCount: 0,
        removedCount: changes.length,
        modifiedCount: 0,
        newDaysCount: 0,
      );
    }

    final changes = <ScheduleChange>[];
    int addedCount = 0;
    int removedCount = 0;
    int modifiedCount = 0;
    int newDaysCount = 0;

    // Проверяем новые дни
    final oldDates = oldSchedule.keys.toSet();
    final newDates = newSchedule.keys.toSet();
    final addedDates =
        newDates.where((date) => !oldDates.contains(date)).toSet();
    final removedDates =
        oldDates.where((date) => !newDates.contains(date)).toSet();

    newDaysCount = addedDates.length;

    // Обрабатываем новые дни
    for (var date in addedDates) {
      final groups = newSchedule[date] ?? {};
      groups.forEach((group, items) {
        for (var item in items) {
          changes.add(ScheduleChange(
            type: ChangeType.newDay,
            date: date,
            group: group,
            newItem: item,
            description: 'Новый день: $date - ${item.subject}',
          ));
          addedCount++;
        }
      });
    }

    // Обрабатываем удаленные дни
    for (var date in removedDates) {
      final groups = oldSchedule[date] ?? {};
      groups.forEach((group, items) {
        for (var item in items) {
          changes.add(ScheduleChange(
            type: ChangeType.removed,
            date: date,
            group: group,
            oldItem: item,
            description: 'Удален день: $date - ${item.subject}',
          ));
          removedCount++;
        }
      });
    }

    // Обрабатываем общие дни
    final commonDates =
        oldDates.where((date) => newDates.contains(date)).toSet();
    for (var date in commonDates) {
      final oldGroups = oldSchedule[date] ?? {};
      final newGroups = newSchedule[date] ?? {};

      // Проверяем новые группы
      final oldGroupNames = oldGroups.keys.toSet();
      final newGroupNames = newGroups.keys.toSet();
      final addedGroups = newGroupNames
          .where((group) => !oldGroupNames.contains(group))
          .toSet();
      final removedGroups = oldGroupNames
          .where((group) => !newGroupNames.contains(group))
          .toSet();

      // Новые группы
      for (var group in addedGroups) {
        final items = newGroups[group] ?? [];
        for (var item in items) {
          changes.add(ScheduleChange(
            type: ChangeType.added,
            date: date,
            group: group,
            newItem: item,
            description: 'Добавлено: ${item.subject}',
          ));
          addedCount++;
        }
      }

      // Удаленные группы
      for (var group in removedGroups) {
        final items = oldGroups[group] ?? [];
        for (var item in items) {
          changes.add(ScheduleChange(
            type: ChangeType.removed,
            date: date,
            group: group,
            oldItem: item,
            description: 'Удалено: ${item.subject}',
          ));
          removedCount++;
        }
      }

      // Общие группы - сравниваем занятия
      final commonGroups =
          oldGroupNames.where((group) => newGroupNames.contains(group)).toSet();
      for (var group in commonGroups) {
        final oldItems = oldGroups[group] ?? [];
        final newItems = newGroups[group] ?? [];

        // Создаем карты для быстрого поиска
        final oldItemsMap = <String, ScheduleItem>{};
        final newItemsMap = <String, ScheduleItem>{};

        for (var item in oldItems) {
          final key = _getItemKey(item);
          oldItemsMap[key] = item;
        }

        for (var item in newItems) {
          final key = _getItemKey(item);
          newItemsMap[key] = item;
        }

        // Находим добавленные занятия
        final addedKeys = newItemsMap.keys
            .where((key) => !oldItemsMap.containsKey(key))
            .toList();
        for (var key in addedKeys) {
          final item = newItemsMap[key]!;
          changes.add(ScheduleChange(
            type: ChangeType.added,
            date: date,
            group: group,
            newItem: item,
            description:
                'Добавлено: ${item.subject} (${item.lessonNumber} пара)',
          ));
          addedCount++;
        }

        // Находим удаленные занятия
        final removedKeys = oldItemsMap.keys
            .where((key) => !newItemsMap.containsKey(key))
            .toList();
        for (var key in removedKeys) {
          final item = oldItemsMap[key]!;
          changes.add(ScheduleChange(
            type: ChangeType.removed,
            date: date,
            group: group,
            oldItem: item,
            description: 'Удалено: ${item.subject} (${item.lessonNumber} пара)',
          ));
          removedCount++;
        }

        // Находим измененные занятия
        final commonKeys = oldItemsMap.keys
            .where((key) => newItemsMap.containsKey(key))
            .toList();
        for (var key in commonKeys) {
          final oldItem = oldItemsMap[key]!;
          final newItem = newItemsMap[key]!;

          if (!_itemsEqual(oldItem, newItem)) {
            changes.add(ScheduleChange(
              type: ChangeType.modified,
              date: date,
              group: group,
              oldItem: oldItem,
              newItem: newItem,
              description: 'Изменено: ${oldItem.subject} → ${newItem.subject}',
            ));
            modifiedCount++;
          }
        }
      }
    }

    return ScheduleDiffResult(
      changes: changes,
      hasChanges: changes.isNotEmpty,
      addedCount: addedCount,
      removedCount: removedCount,
      modifiedCount: modifiedCount,
      newDaysCount: newDaysCount,
    );
  }

  /// Создает уникальный ключ для занятия
  static String _getItemKey(ScheduleItem item) {
    return '${item.lessonNumber}_${item.subgroup ?? 'no_subgroup'}_${item.subject}_${item.teacher}_${item.classroom}';
  }

  /// Сравнивает два занятия на равенство
  static bool _itemsEqual(ScheduleItem a, ScheduleItem b) {
    return a.lessonNumber == b.lessonNumber &&
        a.subgroup == b.subgroup &&
        a.subject == b.subject &&
        a.teacher == b.teacher &&
        a.classroom == b.classroom;
  }

  /// Вычисляет хеш расписания для быстрого сравнения
  static String calculateScheduleHash(
    Map<String, Map<String, List<ScheduleItem>>> schedule,
  ) {
    final buffer = StringBuffer();
    final sortedDates = schedule.keys.toList()..sort();

    for (var date in sortedDates) {
      buffer.write(date);
      final groups = schedule[date] ?? {};
      final sortedGroups = groups.keys.toList()..sort();

      for (var group in sortedGroups) {
        buffer.write(group);
        final items = groups[group] ?? [];
        final sortedItems = items.toList()
          ..sort((a, b) {
            if (a.lessonNumber != b.lessonNumber) {
              return a.lessonNumber.compareTo(b.lessonNumber);
            }
            return a.subject.compareTo(b.subject);
          });

        for (var item in sortedItems) {
          buffer.write(
              '${item.lessonNumber}_${item.subject}_${item.teacher}_${item.classroom}');
        }
      }
    }

    return buffer.toString().hashCode.toString();
  }
}
