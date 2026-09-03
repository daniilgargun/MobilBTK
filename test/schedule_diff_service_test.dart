/*
 * Тесты сравнения расписаний — на нём построены уведомления об изменениях,
 * поэтому и ложные срабатывания, и пропуски одинаково вредны.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilapp/models/schedule_model.dart';
import 'package:mobilapp/services/schedule_diff_service.dart';

ScheduleItem lesson({
  String group = '205',
  int number = 1,
  String subject = 'Математика',
  String teacher = 'Иванов И.И.',
  String classroom = '202',
  String? subgroup,
}) {
  return ScheduleItem(
    group: group,
    lessonNumber: number,
    subject: subject,
    teacher: teacher,
    classroom: classroom,
    subgroup: subgroup,
  );
}

void main() {
  group('compareSchedules', () {
    test('одинаковые расписания не дают изменений', () {
      final data = {
        '03.09.2026': {
          '205': [lesson()],
        },
      };

      final result = ScheduleDiffService.compareSchedules(data, data);

      expect(result.hasChanges, isFalse);
      expect(result.summary, 'Изменений нет');
    });

    test('новый день отмечается как новый', () {
      final oldData = {
        '03.09.2026': {
          '205': [lesson()],
        },
      };
      final newData = {
        '03.09.2026': {
          '205': [lesson()],
        },
        '04.09.2026': {
          '205': [lesson(number: 2)],
        },
      };

      final result = ScheduleDiffService.compareSchedules(oldData, newData);

      expect(result.hasChanges, isTrue);
      expect(result.newDaysCount, 1);
    });

    test('смена кабинета фиксируется как изменение', () {
      final oldData = {
        '03.09.2026': {
          '205': [lesson(classroom: '202')],
        },
      };
      final newData = {
        '03.09.2026': {
          '205': [lesson(classroom: '310')],
        },
      };

      final result = ScheduleDiffService.compareSchedules(oldData, newData);

      expect(result.hasChanges, isTrue);
      expect(result.modifiedCount, 1);
    });

    test('удалённая пара фиксируется', () {
      final oldData = {
        '03.09.2026': {
          '205': [lesson(number: 1), lesson(number: 2)],
        },
      };
      final newData = {
        '03.09.2026': {
          '205': [lesson(number: 1)],
        },
      };

      final result = ScheduleDiffService.compareSchedules(oldData, newData);

      expect(result.hasChanges, isTrue);
      expect(result.removedCount, 1);
    });

    test('добавленная пара фиксируется', () {
      final oldData = {
        '03.09.2026': {
          '205': [lesson(number: 1)],
        },
      };
      final newData = {
        '03.09.2026': {
          '205': [lesson(number: 1), lesson(number: 2)],
        },
      };

      final result = ScheduleDiffService.compareSchedules(oldData, newData);

      expect(result.addedCount, 1);
    });

    test('первая загрузка не выглядит как пачка изменений', () {
      final newData = {
        '03.09.2026': {
          '205': [lesson()],
        },
      };

      final result = ScheduleDiffService.compareSchedules({}, newData);

      // Иначе пользователь получал бы уведомление "расписание изменилось"
      // при самом первом запуске приложения.
      expect(result.modifiedCount, 0);
    });
  });

  group('calculateScheduleHash', () {
    test('одинаковые данные дают одинаковый хэш', () {
      final a = {
        '03.09.2026': {
          '205': [lesson()],
        },
      };
      final b = {
        '03.09.2026': {
          '205': [lesson()],
        },
      };

      expect(
        ScheduleDiffService.calculateScheduleHash(a),
        ScheduleDiffService.calculateScheduleHash(b),
      );
    });

    test('изменение данных меняет хэш', () {
      final a = {
        '03.09.2026': {
          '205': [lesson(classroom: '202')],
        },
      };
      final b = {
        '03.09.2026': {
          '205': [lesson(classroom: '310')],
        },
      };

      expect(
        ScheduleDiffService.calculateScheduleHash(a),
        isNot(ScheduleDiffService.calculateScheduleHash(b)),
      );
    });
  });
}
