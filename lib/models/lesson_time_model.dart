// Модель для хранения времени пар
// Разное расписание для разных дней недели:
// - Обычное (пн, ср, пт)
// - Вторник (с классным часом)
// - Четверг (с часом информации)
// - Суббота (сокращенные перемены)

class LessonTime {
  // Время начала и конца пары
  final String start;
  final String end;
  final int lessonNumber;  // Номер пары (1-6)
  final String dayType;    // Тип дня (normal/tuesday/thursday/saturday)

  const LessonTime({
    required this.start,
    required this.end,
    required this.lessonNumber,
    required this.dayType,
  });

  // Все расписания звонков
  static Map<String, List<LessonTime>> lessonTimes = {
    "normal": [ // Понедельник, среда, пятница
      LessonTime(start: "8:00", end: "8:45", lessonNumber: 1, dayType: "normal"),
      LessonTime(start: "8:55", end: "9:40", lessonNumber: 1, dayType: "normal"),
      LessonTime(start: "9:50", end: "10:35", lessonNumber: 2, dayType: "normal"),
      LessonTime(start: "11:00", end: "11:45", lessonNumber: 2, dayType: "normal"),
      LessonTime(start: "12:20", end: "13:05", lessonNumber: 3, dayType: "normal"),
      LessonTime(start: "13:15", end: "14:00", lessonNumber: 3, dayType: "normal"),
      LessonTime(start: "14:10", end: "14:55", lessonNumber: 4, dayType: "normal"),
      LessonTime(start: "15:05", end: "15:50", lessonNumber: 4, dayType: "normal"),
      LessonTime(start: "16:00", end: "16:45", lessonNumber: 5, dayType: "normal"),
      LessonTime(start: "16:55", end: "17:40", lessonNumber: 5, dayType: "normal"),
      LessonTime(start: "17:50", end: "18:35", lessonNumber: 6, dayType: "normal"),
      LessonTime(start: "18:40", end: "19:25", lessonNumber: 6, dayType: "normal"),
    ],
    "tuesday": [ // Вторник
      LessonTime(start: "8:00", end: "8:45", lessonNumber: 1, dayType: "tuesday"),
      LessonTime(start: "8:55", end: "9:40", lessonNumber: 1, dayType: "tuesday"),
      LessonTime(start: "9:50", end: "10:35", lessonNumber: 2, dayType: "tuesday"),
      LessonTime(start: "11:00", end: "11:45", lessonNumber: 2, dayType: "tuesday"),
      LessonTime(start: "12:20", end: "13:05", lessonNumber: 3, dayType: "tuesday"),
      LessonTime(start: "13:15", end: "14:00", lessonNumber: 3, dayType: "tuesday"),
      LessonTime(start: "15:05", end: "15:50", lessonNumber: 4, dayType: "tuesday"),
      LessonTime(start: "16:00", end: "16:45", lessonNumber: 4, dayType: "tuesday"),
      LessonTime(start: "16:55", end: "17:40", lessonNumber: 5, dayType: "tuesday"),
      LessonTime(start: "17:50", end: "18:35", lessonNumber: 5, dayType: "tuesday"),
      LessonTime(start: "18:45", end: "19:30", lessonNumber: 6, dayType: "tuesday"),
      LessonTime(start: "19:35", end: "20:20", lessonNumber: 6, dayType: "tuesday"),
    ],
    "thursday": [ // Четверг
      LessonTime(start: "8:00", end: "8:45", lessonNumber: 1, dayType: "thursday"),
      LessonTime(start: "8:55", end: "9:40", lessonNumber: 1, dayType: "thursday"),
      LessonTime(start: "9:50", end: "10:35", lessonNumber: 2, dayType: "thursday"),
      LessonTime(start: "11:00", end: "11:45", lessonNumber: 2, dayType: "thursday"),
      LessonTime(start: "12:20", end: "13:05", lessonNumber: 3, dayType: "thursday"),
      LessonTime(start: "13:15", end: "14:00", lessonNumber: 3, dayType: "thursday"),
      LessonTime(start: "14:45", end: "15:30", lessonNumber: 4, dayType: "thursday"),
      LessonTime(start: "15:40", end: "16:25", lessonNumber: 4, dayType: "thursday"),
      LessonTime(start: "16:35", end: "17:20", lessonNumber: 5, dayType: "thursday"),
      LessonTime(start: "17:30", end: "18:15", lessonNumber: 5, dayType: "thursday"),
      LessonTime(start: "18:25", end: "19:10", lessonNumber: 6, dayType: "thursday"),
      LessonTime(start: "19:15", end: "20:00", lessonNumber: 6, dayType: "thursday"),
    ],
    "saturday": [ // Суббота
      LessonTime(start: "8:00", end: "8:45", lessonNumber: 1, dayType: "saturday"),
      LessonTime(start: "8:55", end: "9:40", lessonNumber: 1, dayType: "saturday"),
      LessonTime(start: "9:50", end: "10:35", lessonNumber: 2, dayType: "saturday"),
      LessonTime(start: "10:45", end: "11:30", lessonNumber: 2, dayType: "saturday"),
      LessonTime(start: "11:50", end: "12:35", lessonNumber: 3, dayType: "saturday"),
      LessonTime(start: "12:40", end: "13:25", lessonNumber: 3, dayType: "saturday"),
      LessonTime(start: "13:35", end: "14:20", lessonNumber: 4, dayType: "saturday"),
      LessonTime(start: "14:25", end: "15:10", lessonNumber: 4, dayType: "saturday"),
      LessonTime(start: "15:20", end: "16:05", lessonNumber: 5, dayType: "saturday"),
      LessonTime(start: "16:10", end: "16:55", lessonNumber: 5, dayType: "saturday"),
      LessonTime(start: "17:05", end: "17:50", lessonNumber: 6, dayType: "saturday"),
      LessonTime(start: "17:55", end: "18:40", lessonNumber: 6, dayType: "saturday"),
    ],
  };

  // Получаем время для конкретной пары
  static List<LessonTime> getTimesForLesson(int lessonNumber, String dayType) {
    return lessonTimes[dayType]?.where((time) => time.lessonNumber == lessonNumber).toList() ?? [];
  }

  // Определяем тип дня по номеру дня недели
  static String getDayType(int weekday) {
    switch (weekday) {
      case DateTime.tuesday:
        return "tuesday";
      case DateTime.thursday:
        return "thursday";
      case DateTime.saturday:
        return "saturday";
      default:
        return "normal";
    }
  }

  // Получаем название дня недели по-русски
  static String getDayName(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return "Понедельник";
      case DateTime.tuesday:
        return "Вторник";
      case DateTime.wednesday:
        return "Среда";
      case DateTime.thursday:
        return "Четверг";
      case DateTime.friday:
        return "Пятница";
      case DateTime.saturday:
        return "Суббота";
      default:
        return "Воскресенье";
    }
  }
} 