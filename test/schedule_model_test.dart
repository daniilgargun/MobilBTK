/*
 * Сравнение по значению у ScheduleItem нужно, чтобы список расписания
 * не пересоздавал карточки при каждом обновлении данных.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilapp/models/lesson_time_model.dart';
import 'package:mobilapp/models/schedule_model.dart';

void main() {
  ScheduleItem make({String classroom = '202', String? subgroup}) =>
      ScheduleItem(
        group: '205',
        lessonNumber: 1,
        subject: 'Математика',
        teacher: 'Иванов И.И.',
        classroom: classroom,
        subgroup: subgroup,
      );

  group('ScheduleItem', () {
    test('равные по содержимому объекты равны', () {
      expect(make(), make());
      expect(make().hashCode, make().hashCode);
    });

    test('разный кабинет делает объекты неравными', () {
      expect(make(classroom: '202'), isNot(make(classroom: '310')));
    });

    test('разная подгруппа делает объекты неравными', () {
      expect(make(subgroup: '1'), isNot(make(subgroup: '2')));
      expect(make(subgroup: null), isNot(make(subgroup: '1')));
    });

    test('copyWith сохраняет остальные поля', () {
      final copy = make().copyWith(classroom: '999');
      expect(copy.group, '205');
      expect(copy.subject, 'Математика');
      expect(copy.classroom, '999');
    });

    test('сериализация в Map и обратно не теряет данные', () {
      final original = make(subgroup: '2');
      final restored = ScheduleItem.fromMap(original.toMap());
      expect(restored, original);
    });

    test('годится как ключ множества', () {
      expect({make(), make()}.length, 1);
    });
  });

  group('LessonTime', () {
    test('тип дня определяется по дню недели', () {
      expect(LessonTime.getDayType(DateTime.tuesday), 'tuesday');
      expect(LessonTime.getDayType(DateTime.thursday), 'thursday');
      expect(LessonTime.getDayType(DateTime.saturday), 'saturday');
      expect(LessonTime.getDayType(DateTime.monday), 'normal');
      expect(LessonTime.getDayType(DateTime.friday), 'normal');
    });

    test('у каждого типа дня заданы времена звонков', () {
      for (final dayType in ['normal', 'tuesday', 'thursday', 'saturday']) {
        expect(
          LessonTime.lessonTimes[dayType],
          isNotEmpty,
          reason: 'нет расписания звонков для типа дня $dayType',
        );
      }
    });

    test('пара состоит из двух половин', () {
      final times = LessonTime.getTimesForLesson(1, 'normal');
      expect(times.length, 2);
      expect(times[0].isFirstHalf, isTrue);
      expect(times[1].isFirstHalf, isFalse);
    });

    test('особые часы заданы только для вторника и четверга', () {
      expect(LessonTime.getSpecialHourInfo('tuesday'), isNotNull);
      expect(LessonTime.getSpecialHourInfo('thursday'), isNotNull);
      expect(LessonTime.getSpecialHourInfo('normal'), isNull);
    });
  });
}
