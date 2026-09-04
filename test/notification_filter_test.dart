import 'package:flutter_test/flutter_test.dart';
import 'package:mobilapp/models/schedule_model.dart';
import 'package:mobilapp/services/schedule_diff_service.dart';
import 'package:mobilapp/services/user_profile_service.dart';

/// Дифф сравнивает расписание всего колледжа. Без фильтра студент получал
/// уведомление «изменено 12 пар», где ни одна не его.
void main() {
  ScheduleItem lesson({
    required String group,
    required int number,
    required String subject,
    String teacher = 'Иванов И.И.',
    String classroom = '312',
  }) => ScheduleItem(
    group: group,
    lessonNumber: number,
    subject: subject,
    teacher: teacher,
    classroom: classroom,
    subgroup: null,
  );

  Map<String, Map<String, List<ScheduleItem>>> day(
    Map<String, List<ScheduleItem>> groups,
  ) => {'05.09.2026': groups};

  test('студенту остаются только изменения его группы', () {
    final before = day({
      '396': [lesson(group: '396', number: 1, subject: 'Математика')],
      '203': [lesson(group: '203', number: 1, subject: 'Физика')],
    });
    final after = day({
      '396': [lesson(group: '396', number: 1, subject: 'Маркетинг')],
      '203': [lesson(group: '203', number: 1, subject: 'Химия')],
    });

    final diff = ScheduleDiffService.compareSchedules(before, after);
    expect(diff.modifiedCount, 2, reason: 'изменились обе группы');

    final personal = ScheduleDiffService.forProfile(
      diff,
      const UserProfile(role: ProfileRole.student, value: '396'),
    );

    expect(personal.modifiedCount, 1);
    expect(personal.changes.single.group, '396');
  });

  test('счётчики пересобираются, а не остаются от полного расписания', () {
    final before = day({
      '396': [lesson(group: '396', number: 1, subject: 'Математика')],
    });
    final after = day({
      '396': [lesson(group: '396', number: 1, subject: 'Математика')],
      '203': [lesson(group: '203', number: 2, subject: 'Физика')],
    });

    final diff = ScheduleDiffService.compareSchedules(before, after);
    expect(diff.hasChanges, isTrue);

    final personal = ScheduleDiffService.forProfile(
      diff,
      const UserProfile(role: ProfileRole.student, value: '396'),
    );

    expect(personal.hasChanges, isFalse);
    expect(personal.addedCount, 0);
    expect(personal.summary, 'Изменений нет');
  });

  test('преподавателю остаются его пары в любых группах', () {
    final before = day({
      '396': [
        lesson(
          group: '396',
          number: 1,
          subject: 'Математика',
          teacher: 'Савина Е.В.',
        ),
      ],
      '203': [
        lesson(
          group: '203',
          number: 1,
          subject: 'Физика',
          teacher: 'Петров П.П.',
        ),
      ],
    });
    final after = day({
      '396': [
        lesson(
          group: '396',
          number: 1,
          subject: 'Маркетинг',
          teacher: 'Савина Е.В.',
        ),
      ],
      '203': [
        lesson(
          group: '203',
          number: 1,
          subject: 'Химия',
          teacher: 'Петров П.П.',
        ),
      ],
    });

    final personal = ScheduleDiffService.forProfile(
      ScheduleDiffService.compareSchedules(before, after),
      const UserProfile(role: ProfileRole.teacher, value: 'Савина Е.В.'),
    );

    expect(personal.modifiedCount, 1);
    expect(personal.changes.single.group, '396');
  });

  test('без профиля ничего не отфильтровывается', () {
    final before = day({
      '396': [lesson(group: '396', number: 1, subject: 'Математика')],
    });
    final after = day({
      '396': [lesson(group: '396', number: 1, subject: 'Маркетинг')],
      '203': [lesson(group: '203', number: 1, subject: 'Физика')],
    });

    final diff = ScheduleDiffService.compareSchedules(before, after);

    expect(
      ScheduleDiffService.forProfile(diff, null).changes.length,
      diff.changes.length,
    );
  });

  test('регистр и пробелы в профиле не мешают совпадению', () {
    final before = day({
      '396': [
        lesson(
          group: '396',
          number: 1,
          subject: 'Математика',
          teacher: 'Савина Е.В.',
        ),
      ],
    });
    final after = day({
      '396': [
        lesson(
          group: '396',
          number: 1,
          subject: 'Маркетинг',
          teacher: 'Савина Е.В.',
        ),
      ],
    });

    final personal = ScheduleDiffService.forProfile(
      ScheduleDiffService.compareSchedules(before, after),
      const UserProfile(role: ProfileRole.teacher, value: '  савина е.в. '),
    );

    expect(personal.hasChanges, isTrue);
  });

  test('удалённый день остаётся у своей группы', () {
    final before = day({
      '396': [lesson(group: '396', number: 1, subject: 'Математика')],
      '203': [lesson(group: '203', number: 1, subject: 'Физика')],
    });

    final diff = ScheduleDiffService.compareSchedules(before, {
      '06.09.2026': <String, List<ScheduleItem>>{},
    });

    final personal = ScheduleDiffService.forProfile(
      diff,
      const UserProfile(role: ProfileRole.student, value: '396'),
    );

    expect(personal.removedCount, 1);
  });

  group('текст уведомления', () {
    test('при малом числе изменений перечисляет их', () {
      final before = day({
        '396': [lesson(group: '396', number: 2, subject: 'Математика')],
      });
      final after = day({
        '396': [lesson(group: '396', number: 2, subject: 'Маркетинг')],
      });

      final personal = ScheduleDiffService.forProfile(
        ScheduleDiffService.compareSchedules(before, after),
        const UserProfile(role: ProfileRole.student, value: '396'),
      );

      expect(personal.detailedSummary, contains('Маркетинг'));
      expect(personal.detailedSummary, contains('2 пара'));
    });

    test('при большом числе изменений возвращается к короткой сводке', () {
      final before = day({
        '396': [
          for (var i = 1; i <= 6; i++)
            lesson(group: '396', number: i, subject: 'Предмет $i'),
        ],
      });
      final after = day({
        '396': [
          for (var i = 1; i <= 6; i++)
            lesson(group: '396', number: i, subject: 'Другое $i'),
        ],
        '203': [
          for (var i = 1; i <= 6; i++)
            lesson(group: '203', number: i, subject: 'Третье $i'),
        ],
      });

      final personal = ScheduleDiffService.forProfile(
        ScheduleDiffService.compareSchedules(before, after),
        const UserProfile(role: ProfileRole.student, value: '396'),
      );

      expect(personal.changes.length, 6);
      expect(personal.detailedSummary, personal.summary);
    });
  });

  group('UserProfileService.readFrom', () {
    test('пустое значение не даёт профиля', () {
      expect(UserProfileService.readFrom('student', ''), isNull);
      expect(UserProfileService.readFrom('student', '   '), isNull);
      expect(UserProfileService.readFrom(null, '396'), isNull);
    });

    test('неизвестная роль отбрасывается', () {
      expect(UserProfileService.readFrom('director', '396'), isNull);
    });

    test('обе роли читаются', () {
      expect(
        UserProfileService.readFrom('student', ' 396 '),
        const UserProfile(role: ProfileRole.student, value: '396'),
      );
      expect(
        UserProfileService.readFrom('teacher', 'Савина Е.В.'),
        const UserProfile(role: ProfileRole.teacher, value: 'Савина Е.В.'),
      );
    });
  });
}
