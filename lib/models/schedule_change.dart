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

  /// Оставляет только изменения, прошедшие проверку.
  ///
  /// Счётчики пересобираются, иначе в сводке остались бы числа от полного
  /// расписания: пользователь видел бы «12 изменено», открывал приложение и
  /// не находил у себя ни одного изменения.
  ScheduleDiffResult where(bool Function(ScheduleChange change) test) {
    final filtered = changes.where(test).toList(growable: false);

    var added = 0;
    var removed = 0;
    var modified = 0;
    final newDays = <String>{};

    for (final change in filtered) {
      switch (change.type) {
        case ChangeType.added:
          added++;
        case ChangeType.newDay:
          added++;
          newDays.add(change.date);
        case ChangeType.removed:
          removed++;
        case ChangeType.modified:
          modified++;
      }
    }

    return ScheduleDiffResult(
      changes: filtered,
      hasChanges: filtered.isNotEmpty,
      addedCount: added,
      removedCount: removed,
      modifiedCount: modified,
      newDaysCount: newDays.length,
    );
  }

  String get summary {
    if (!hasChanges) return 'Изменений нет';

    final parts = <String>[];
    if (newDaysCount > 0) parts.add('$newDaysCount новых дней');
    if (addedCount > 0) parts.add('$addedCount добавлено');
    if (removedCount > 0) parts.add('$removedCount удалено');
    if (modifiedCount > 0) parts.add('$modifiedCount изменено');

    return parts.join(', ');
  }

  /// Текст уведомления с перечислением самих изменений.
  ///
  /// Когда изменений мало — а после фильтра по своей группе их обычно
  /// единицы — «2 добавлено, 1 изменено» не говорит ничего полезного:
  /// приходится открывать приложение и глазами искать, что поменялось.
  /// Поэтому при небольшом числе изменений перечисляем их прямо в
  /// уведомлении, а при большом возвращаемся к короткой сводке.
  String get detailedSummary {
    if (!hasChanges) return summary;
    if (changes.length > _detailLimit) return summary;

    final lines = <String>[];
    for (final change in changes) {
      final item = change.newItem ?? change.oldItem;
      if (item == null) continue;

      final prefix = switch (change.type) {
        ChangeType.added || ChangeType.newDay => '+',
        ChangeType.removed => '−',
        ChangeType.modified => '~',
      };

      final lesson = item.lessonNumber > 0 ? '${item.lessonNumber} пара' : '';
      final parts = [
        change.date,
        if (lesson.isNotEmpty) lesson,
        item.subject,
      ].where((part) => part.isNotEmpty);

      lines.add('$prefix ${parts.join(' · ')}');
    }

    return lines.isEmpty ? summary : lines.join('\n');
  }

  /// Сколько изменений ещё имеет смысл перечислять поимённо.
  ///
  /// Четыре строки Android показывает в развёрнутом уведомлении целиком.
  /// Дальше список всё равно обрежется, и короткая сводка честнее.
  static const int _detailLimit = 4;
}
