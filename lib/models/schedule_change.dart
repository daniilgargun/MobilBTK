import 'schedule_model.dart';

// Модель для описания изменений в расписании
class ScheduleChange {
  final ChangeType type;
  final String date;
  final String group;
  final ScheduleItem? oldItem;
  final ScheduleItem? newItem;
  final String description;

  ScheduleChange({
    required this.type,
    required this.date,
    required this.group,
    this.oldItem,
    this.newItem,
    required this.description,
  });

  @override
  String toString() {
    return description;
  }
}

enum ChangeType {
  added, // Добавлено новое занятие
  removed, // Удалено занятие
  modified, // Изменено занятие
  newDay, // Добавлен новый день
}

// Результат сравнения расписаний
class ScheduleDiffResult {
  final List<ScheduleChange> changes;
  final bool hasChanges;
  final int addedCount;
  final int removedCount;
  final int modifiedCount;
  final int newDaysCount;

  ScheduleDiffResult({
    required this.changes,
    required this.hasChanges,
    required this.addedCount,
    required this.removedCount,
    required this.modifiedCount,
    required this.newDaysCount,
  });

  String get summary {
    if (!hasChanges) return 'Изменений нет';

    final parts = <String>[];
    if (newDaysCount > 0) parts.add('$newDaysCount новых дней');
    if (addedCount > 0) parts.add('$addedCount добавлено');
    if (removedCount > 0) parts.add('$removedCount удалено');
    if (modifiedCount > 0) parts.add('$modifiedCount изменено');

    return parts.join(', ');
  }
}
