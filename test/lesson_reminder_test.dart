import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobilapp/models/schedule_model.dart';
import 'package:mobilapp/services/lesson_reminder_service.dart';
import 'package:mobilapp/services/user_profile_service.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Отбор напоминаний считается на устройстве и в фоновом изоляте, где его
/// никто не увидит. Поэтому проверяем именно отбор: что попало в очередь
/// будильников и что из неё выпало.
void main() {
  late tz.Location minsk;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tzdata.initializeTimeZones();
    minsk = tz.getLocation('Europe/Minsk');
    tz.setLocalLocation(minsk);
  });

  ScheduleItem lesson({
    required String group,
    required int number,
    String subject = 'Математика',
    String teacher = 'Савина Е.В.',
    String classroom = '312',
  }) => ScheduleItem(
    group: group,
    lessonNumber: number,
    subject: subject,
    teacher: teacher,
    classroom: classroom,
    subgroup: null,
  );

  /// Пятница 11.09.2026 — обычный день, 1 пара в 8:00.
  const dateKey = '11.09.2026';
  tz.TZDateTime at(int hour, int minute) =>
      tz.TZDateTime(minsk, 2026, 9, 11, hour, minute);

  List<LessonReminder> plan(
    Map<String, Map<String, List<ScheduleItem>>> schedule,
    UserProfile profile, {
    tz.TZDateTime? now,
    tz.TZDateTime? horizon,
  }) {
    final from = now ?? at(6, 0);
    return LessonReminderService().planForTest(
      schedule,
      profile,
      from,
      horizon ?? from.add(const Duration(days: 7)),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Сервис — синглтон; сбрасываем к значениям по умолчанию (15 минут).
    await LessonReminderService().setMinutesBefore(
      LessonReminderService.defaultMinutes,
    );
  });

  test('напоминание ставится за указанное время до начала пары', () {
    final result = plan({
      dateKey: {
        '396': [lesson(group: '396', number: 1)],
      },
    }, const UserProfile(role: ProfileRole.student, value: '396'));

    expect(result, hasLength(1));
    // 1 пара в обычный день начинается в 8:00, напоминание за 15 минут.
    expect(result.single.fireAt, at(7, 45));
    expect(result.single.lessonStart, at(8, 0));
  });

  test('чужие группы не попадают в напоминания', () {
    final result = plan({
      dateKey: {
        '396': [lesson(group: '396', number: 1)],
        '203': [lesson(group: '203', number: 2)],
      },
    }, const UserProfile(role: ProfileRole.student, value: '396'));

    expect(result, hasLength(1));
    expect(result.single.item.group, '396');
  });

  test('у преподавателя одна пара сразу в двух группах даёт одно '
      'напоминание', () {
    final result = plan({
      dateKey: {
        '396': [lesson(group: '396', number: 1, teacher: 'Савина Е.В.')],
        '203': [lesson(group: '203', number: 1, teacher: 'Савина Е.В.')],
      },
    }, const UserProfile(role: ProfileRole.teacher, value: 'Савина Е.В.'));

    expect(result, hasLength(1));
  });

  test('прошедшие пары пропускаются', () {
    final result = plan(
      {
        dateKey: {
          '396': [
            lesson(group: '396', number: 1),
            lesson(group: '396', number: 5),
          ],
        },
      },
      const UserProfile(role: ProfileRole.student, value: '396'),
      // Уже полдень: первая пара давно прошла, пятая ещё нет.
      now: at(12, 0),
    );

    expect(result, hasLength(1));
    expect(result.single.item.lessonNumber, 5);
  });

  test('дни за горизонтом планирования не попадают', () {
    final result = plan({
      dateKey: {
        '396': [lesson(group: '396', number: 1)],
      },
      '25.09.2026': {
        '396': [lesson(group: '396', number: 1)],
      },
    }, const UserProfile(role: ProfileRole.student, value: '396'));

    expect(result, hasLength(1));
    expect(result.single.fireAt, at(7, 45));
  });

  test('неразборчивая дата не роняет планирование', () {
    final result = plan({
      'не дата': {
        '396': [lesson(group: '396', number: 1)],
      },
      dateKey: {
        '396': [lesson(group: '396', number: 1)],
      },
    }, const UserProfile(role: ProfileRole.student, value: '396'));

    expect(result, hasLength(1));
  });

  test('напоминания отсортированы по времени срабатывания', () {
    final result = plan({
      dateKey: {
        '396': [
          lesson(group: '396', number: 4),
          lesson(group: '396', number: 1),
          lesson(group: '396', number: 2),
        ],
      },
    }, const UserProfile(role: ProfileRole.student, value: '396'));

    expect(result.map((r) => r.item.lessonNumber), [1, 2, 4]);
  });

  test('текст напоминания содержит время, кабинет и преподавателя', () {
    final result = plan({
      dateKey: {
        '396': [
          lesson(
            group: '396',
            number: 1,
            subject: 'Маркетинг',
            classroom: 'О24',
            teacher: 'Савина Е.В.',
          ),
        ],
      },
    }, const UserProfile(role: ProfileRole.student, value: '396'));

    final reminder = result.single;
    expect(reminder.title, contains('Маркетинг'));
    expect(reminder.title, contains('15 мин'));
    expect(reminder.body, contains('8:00'));
    expect(reminder.body, contains('О24'));
    expect(reminder.body, contains('Савина Е.В.'));
  });
}
