import 'package:flutter_test/flutter_test.dart';
import 'package:mobilapp/models/lesson_time_model.dart';

/// Расписание звонков — то, ради чего приложение открывают чаще всего.
/// Поэтому проверяем не только удачный разбор, но и что любая кривая
/// строка оставляет вшитое время, а не половину новой сетки.
void main() {
  /// 12 диапазонов: шесть пар по два получаса.
  String daySchedule(String Function(int index) build) {
    final items = List.generate(12, (i) => '"${build(i)}"').join(',');
    return '[$items]';
  }

  final shifted = daySchedule((i) {
    final startHour = 9 + i ~/ 2;
    final startMinute = i.isEven ? 0 : 30;
    return '$startHour:${startMinute.toString().padLeft(2, '0')}-'
        '$startHour:${(startMinute + 25).toString().padLeft(2, '0')}';
  });

  tearDown(() {
    // Возвращаем вшитое расписание, иначе тесты влияли бы друг на друга.
    LessonTime.applyRemoteOverride('');
  });

  test('пустой конфиг оставляет вшитое расписание', () {
    expect(LessonTime.applyRemoteOverride(''), isEmpty);
    expect(LessonTime.getTimesForLesson(1, 'normal').first.start, '8:00');
  });

  test('заменяет расписание указанного типа дня', () {
    final applied = LessonTime.applyRemoteOverride('{"normal":$shifted}');

    expect(applied, ['normal']);
    expect(LessonTime.getTimesForLesson(1, 'normal').first.start, '9:00');
    expect(LessonTime.getTimesForLesson(6, 'normal').last.end, '14:55');
  });

  test('незаданные типы дней остаются вшитыми', () {
    LessonTime.applyRemoteOverride('{"normal":$shifted}');

    expect(LessonTime.getTimesForLesson(1, 'saturday').first.start, '8:00');
    expect(LessonTime.getTimesForLesson(4, 'tuesday').first.start, '15:05');
  });

  test('номера пар и половины расставляются по порядку', () {
    LessonTime.applyRemoteOverride('{"normal":$shifted}');

    final times = LessonTime.lessonTimes['normal']!;
    expect(times.length, 12);
    expect(times[0].lessonNumber, 1);
    expect(times[0].isFirstHalf, isTrue);
    expect(times[1].lessonNumber, 1);
    expect(times[1].isFirstHalf, isFalse);
    expect(times[11].lessonNumber, 6);
    expect(times[11].isFirstHalf, isFalse);
  });

  test('неполный список (11 диапазонов) отвергается целиком', () {
    final incomplete = daySchedule((i) => '9:00-9:45');
    final trimmed = incomplete.replaceFirst(',"9:00-9:45"]', ']');

    expect(LessonTime.applyRemoteOverride('{"normal":$trimmed}'), isEmpty);
    expect(LessonTime.getTimesForLesson(1, 'normal').first.start, '8:00');
  });

  test('одна опечатка во времени отменяет весь день', () {
    final broken = shifted.replaceFirst('9:00-9:25', '9-00-9:25');

    expect(LessonTime.applyRemoteOverride('{"normal":$broken}'), isEmpty);
    expect(LessonTime.getTimesForLesson(1, 'normal').first.start, '8:00');
  });

  test('несуществующее время отвергается', () {
    final broken = shifted.replaceFirst('9:00-9:25', '25:00-9:25');

    expect(LessonTime.applyRemoteOverride('{"normal":$broken}'), isEmpty);
  });

  test('поломанный JSON не роняет приложение', () {
    expect(LessonTime.applyRemoteOverride('{нет'), isEmpty);
    expect(LessonTime.getTimesForLesson(1, 'normal').first.start, '8:00');
  });

  test('особые часы заменяются вместе с расписанием', () {
    LessonTime.applyRemoteOverride(
      '{"special":{"tuesday":{"name":"Собрание","time":"14:00-14:30"}}}',
    );

    expect(LessonTime.getSpecialHourInfo('tuesday')?['name'], 'Собрание');
  });

  test('пустые особые часы оставляют вшитые', () {
    LessonTime.applyRemoteOverride('{"special":{}}');

    expect(LessonTime.getSpecialHourInfo('tuesday')?['name'], 'Классный час');
  });
}
