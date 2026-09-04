/*
 * Тесты поиска по расписанию.
 *
 * Ключевой случай — совпадение номеров: в колледже есть и группа 209,
 * и кабинет 209. Без сужения области группа 209 видела чужие пары,
 * проходящие в кабинете 209.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilapp/models/schedule_model.dart';
import 'package:mobilapp/services/schedule_search.dart';

ScheduleItem lesson({
  String group = '205',
  int number = 1,
  String subject = 'Математика',
  String teacher = 'Иванов И.И.',
  String classroom = '101',
}) {
  return ScheduleItem(
    group: group,
    lessonNumber: number,
    subject: subject,
    teacher: teacher,
    classroom: classroom,
  );
}

void main() {
  // Пара группы 209 и пара другой группы, которая идёт в кабинете 209.
  final ownLesson = lesson(group: '209', classroom: '404');
  final roomLesson = lesson(group: '313', classroom: '209');
  final unrelated = lesson(group: '118', classroom: '777');
  final lessons = [ownLesson, roomLesson, unrelated];

  group('коллизия номера группы и кабинета', () {
    test('без области поиска находятся оба занятия', () {
      final found = ScheduleSearch.filter(lessons, '209', null);
      expect(found, hasLength(2));
    });

    test('область "Группа" оставляет только пары своей группы', () {
      final found = ScheduleSearch.filter(lessons, '209', EntityType.group);
      expect(found, [ownLesson]);
    });

    test('область "Кабинет" оставляет только пары в этом кабинете', () {
      final found = ScheduleSearch.filter(lessons, '209', EntityType.classroom);
      expect(found, [roomLesson]);
    });

    test('запрос распознаётся как неоднозначный', () {
      expect(ScheduleSearch.isAmbiguous(lessons, '209'), isTrue);
      expect(ScheduleSearch.matchedTypes(lessons, '209'), [
        EntityType.group,
        EntityType.classroom,
      ]);
    });

    test('счётчики совпадений считаются по каждому полю', () {
      final counts = ScheduleSearch.countByType(lessons, '209');
      expect(counts[EntityType.group], 1);
      expect(counts[EntityType.classroom], 1);
      expect(counts[EntityType.teacher], isNull);
    });
  });

  group('обычный поиск', () {
    test('однозначный запрос не считается неоднозначным', () {
      expect(ScheduleSearch.isAmbiguous(lessons, 'Иванов'), isFalse);
      expect(ScheduleSearch.matchedTypes(lessons, 'Иванов'), [
        EntityType.teacher,
      ]);
    });

    test('поиск не зависит от регистра', () {
      expect(ScheduleSearch.filter(lessons, 'иванов и.и.', null), hasLength(3));
    });

    test('пустой запрос возвращает всё без изменений', () {
      expect(ScheduleSearch.filter(lessons, '', null), same(lessons));
      expect(ScheduleSearch.countByType(lessons, ''), isEmpty);
      expect(ScheduleSearch.isAmbiguous(lessons, ''), isFalse);
    });

    test('запрос без совпадений даёт пустой результат', () {
      expect(ScheduleSearch.filter(lessons, 'неттакого', null), isEmpty);
      expect(ScheduleSearch.matchedTypes(lessons, 'неттакого'), isEmpty);
    });

    test('поиск по предмету работает', () {
      final found = ScheduleSearch.filter(lessons, 'матем', EntityType.subject);
      expect(found, hasLength(3));
    });

    test('область сужает даже однозначный запрос', () {
      // "Иванов" есть только среди преподавателей, поэтому в области
      // "Группа" не найдётся ничего.
      expect(
        ScheduleSearch.filter(lessons, 'Иванов', EntityType.group),
        isEmpty,
      );
    });
  });

  group('подписи и хранение', () {
    test('у каждой области есть подпись', () {
      for (final type in EntityType.values) {
        expect(type.label, isNotEmpty);
        expect(type.shortLabel, isNotEmpty);
      }
    });

    test('область переживает сохранение и чтение', () {
      for (final type in EntityType.values) {
        expect(EntityTypeLabel.fromStorage(type.storageKey), type);
      }
      expect(EntityTypeLabel.fromStorage(null), isNull);
      expect(EntityTypeLabel.fromStorage('мусор'), isNull);
    });
  });
}
