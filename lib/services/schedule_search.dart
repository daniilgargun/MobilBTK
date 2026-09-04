/*
 * Copyright (c) 2024 Daniil Gargun. All rights reserved.
 * Author: Daniil Gargun | Telegram: @Daniilgargun | Email: daniilgorgun38@gmail.com
 */

import '../models/schedule_model.dart';

/// Поиск по расписанию с возможностью сузить область.
///
/// В колледже номера групп и кабинетов пересекаются: есть и группа 209,
/// и кабинет 209. Поиск по всем полям сразу показывал группе 209 ещё и
/// чужие пары, которые просто проходят в кабинете 209, и пользоваться
/// расписанием было невозможно. Поэтому поиск умеет ограничиваться
/// конкретным полем — [EntityType].
class ScheduleSearch {
  const ScheduleSearch._();

  /// Значение поля [type] у занятия.
  static String fieldOf(ScheduleItem item, EntityType type) {
    switch (type) {
      case EntityType.group:
        return item.group;
      case EntityType.teacher:
        return item.teacher;
      case EntityType.classroom:
        return item.classroom;
      case EntityType.subject:
        return item.subject;
    }
  }

  /// Совпадает ли занятие с запросом в пределах области [scope].
  /// `scope == null` — искать по всем полям.
  static bool matches(ScheduleItem item, String query, EntityType? scope) {
    if (query.isEmpty) return true;
    final needle = query.toLowerCase();

    if (scope != null) {
      return fieldOf(item, scope).toLowerCase().contains(needle);
    }

    for (final type in EntityType.values) {
      if (fieldOf(item, type).toLowerCase().contains(needle)) return true;
    }
    return false;
  }

  /// Отбирает занятия по запросу и области поиска.
  static List<ScheduleItem> filter(
    List<ScheduleItem> lessons,
    String query,
    EntityType? scope,
  ) {
    if (query.isEmpty) return lessons;
    return lessons.where((item) => matches(item, query, scope)).toList();
  }

  /// Сколько занятий совпало с запросом по каждому полю.
  ///
  /// По этим числам экран решает, показывать ли переключатель области:
  /// он нужен только когда запрос неоднозначен — например, "209"
  /// совпадает и с номером группы, и с номером кабинета.
  static Map<EntityType, int> countByType(
    List<ScheduleItem> lessons,
    String query,
  ) {
    final counts = <EntityType, int>{};
    if (query.isEmpty) return counts;

    final needle = query.toLowerCase();
    for (final item in lessons) {
      for (final type in EntityType.values) {
        if (fieldOf(item, type).toLowerCase().contains(needle)) {
          counts[type] = (counts[type] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  /// Поля, по которым запрос вообще что-то находит, в постоянном порядке.
  static List<EntityType> matchedTypes(
    List<ScheduleItem> lessons,
    String query,
  ) {
    final counts = countByType(lessons, query);
    return EntityType.values
        .where((type) => (counts[type] ?? 0) > 0)
        .toList(growable: false);
  }

  /// Запрос неоднозначен: находит совпадения больше чем в одном поле.
  static bool isAmbiguous(List<ScheduleItem> lessons, String query) =>
      matchedTypes(lessons, query).length > 1;
}

/// Подписи областей поиска для интерфейса.
extension EntityTypeLabel on EntityType {
  String get label {
    switch (this) {
      case EntityType.group:
        return 'Группа';
      case EntityType.teacher:
        return 'Преподаватель';
      case EntityType.classroom:
        return 'Кабинет';
      case EntityType.subject:
        return 'Предмет';
    }
  }

  /// Короткая подпись для чипов, где мало места.
  String get shortLabel {
    switch (this) {
      case EntityType.group:
        return 'Группа';
      case EntityType.teacher:
        return 'Препод.';
      case EntityType.classroom:
        return 'Кабинет';
      case EntityType.subject:
        return 'Предмет';
    }
  }

  /// Значение для сохранения в настройках.
  String get storageKey => name;

  static EntityType? fromStorage(String? value) {
    if (value == null) return null;
    for (final type in EntityType.values) {
      if (type.name == value) return type;
    }
    return null;
  }
}
