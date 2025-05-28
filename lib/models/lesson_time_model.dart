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
  final bool isFirstHalf;  // Первый или второй час пары

  const LessonTime({
    required this.start,
    required this.end,
    required this.lessonNumber,
    required this.dayType,
    required this.isFirstHalf,
  });

  // Особые часы в расписании
  static const Map<String, Map<String, String>> specialHours = {
    "tuesday": {
      "name": "Классный час",
      "time": "14:10-14:55",
    },
    "thursday": {
      "name": "Часы информации",
      "time": "14:10-14:35",
    },
  };

  // Для диалога расписания звонков
  static List<(String, String, String)> getLessonTimesForUI(String dayType) {
    final result = <(String, String, String)>[];
    
    for (int lessonNumber = 1; lessonNumber <= 6; lessonNumber++) {
      final times = getTimesForLesson(lessonNumber, dayType);
      if (times.length == 2) {
        result.add((
          '$lessonNumber)',
          times[0].start + '-' + times[0].end,
          times[1].start + '-' + times[1].end,
        ));
      }
    }
    
    return result;
  }

  // Получить информацию о специальном часе для дня
  static Map<String, String>? getSpecialHourInfo(String dayType) {
    return specialHours[dayType];
  }

  // Все расписания звонков
  static Map<String, List<LessonTime>> lessonTimes = {
    "normal": [ // Понедельник, среда, пятница
      LessonTime(start: "8:00", end: "8:45", lessonNumber: 1, dayType: "normal", isFirstHalf: true),
      LessonTime(start: "8:55", end: "9:40", lessonNumber: 1, dayType: "normal", isFirstHalf: false),
      LessonTime(start: "9:50", end: "10:35", lessonNumber: 2, dayType: "normal", isFirstHalf: true),
      LessonTime(start: "11:00", end: "11:45", lessonNumber: 2, dayType: "normal", isFirstHalf: false),
      LessonTime(start: "12:20", end: "13:05", lessonNumber: 3, dayType: "normal", isFirstHalf: true),
      LessonTime(start: "13:15", end: "14:00", lessonNumber: 3, dayType: "normal", isFirstHalf: false),
      LessonTime(start: "14:10", end: "14:55", lessonNumber: 4, dayType: "normal", isFirstHalf: true),
      LessonTime(start: "15:05", end: "15:50", lessonNumber: 4, dayType: "normal", isFirstHalf: false),
      LessonTime(start: "16:00", end: "16:45", lessonNumber: 5, dayType: "normal", isFirstHalf: true),
      LessonTime(start: "16:55", end: "17:40", lessonNumber: 5, dayType: "normal", isFirstHalf: false),
      LessonTime(start: "17:50", end: "18:35", lessonNumber: 6, dayType: "normal", isFirstHalf: true),
      LessonTime(start: "18:40", end: "19:25", lessonNumber: 6, dayType: "normal", isFirstHalf: false),
    ],
    "tuesday": [ // Вторник
      LessonTime(start: "8:00", end: "8:45", lessonNumber: 1, dayType: "tuesday", isFirstHalf: true),
      LessonTime(start: "8:55", end: "9:40", lessonNumber: 1, dayType: "tuesday", isFirstHalf: false),
      LessonTime(start: "9:50", end: "10:35", lessonNumber: 2, dayType: "tuesday", isFirstHalf: true),
      LessonTime(start: "11:00", end: "11:45", lessonNumber: 2, dayType: "tuesday", isFirstHalf: false),
      LessonTime(start: "12:20", end: "13:05", lessonNumber: 3, dayType: "tuesday", isFirstHalf: true),
      LessonTime(start: "13:15", end: "14:00", lessonNumber: 3, dayType: "tuesday", isFirstHalf: false),
      LessonTime(start: "15:05", end: "15:50", lessonNumber: 4, dayType: "tuesday", isFirstHalf: true),
      LessonTime(start: "16:00", end: "16:45", lessonNumber: 4, dayType: "tuesday", isFirstHalf: false),
      LessonTime(start: "16:55", end: "17:40", lessonNumber: 5, dayType: "tuesday", isFirstHalf: true),
      LessonTime(start: "17:50", end: "18:35", lessonNumber: 5, dayType: "tuesday", isFirstHalf: false),
      LessonTime(start: "18:45", end: "19:30", lessonNumber: 6, dayType: "tuesday", isFirstHalf: true),
      LessonTime(start: "19:35", end: "20:20", lessonNumber: 6, dayType: "tuesday", isFirstHalf: false),
    ],
    "thursday": [ // Четверг
      LessonTime(start: "8:00", end: "8:45", lessonNumber: 1, dayType: "thursday", isFirstHalf: true),
      LessonTime(start: "8:55", end: "9:40", lessonNumber: 1, dayType: "thursday", isFirstHalf: false),
      LessonTime(start: "9:50", end: "10:35", lessonNumber: 2, dayType: "thursday", isFirstHalf: true),
      LessonTime(start: "11:00", end: "11:45", lessonNumber: 2, dayType: "thursday", isFirstHalf: false),
      LessonTime(start: "12:20", end: "13:05", lessonNumber: 3, dayType: "thursday", isFirstHalf: true),
      LessonTime(start: "13:15", end: "14:00", lessonNumber: 3, dayType: "thursday", isFirstHalf: false),
      LessonTime(start: "14:45", end: "15:30", lessonNumber: 4, dayType: "thursday", isFirstHalf: true),
      LessonTime(start: "15:40", end: "16:25", lessonNumber: 4, dayType: "thursday", isFirstHalf: false),
      LessonTime(start: "16:35", end: "17:20", lessonNumber: 5, dayType: "thursday", isFirstHalf: true),
      LessonTime(start: "17:30", end: "18:15", lessonNumber: 5, dayType: "thursday", isFirstHalf: false),
      LessonTime(start: "18:25", end: "19:10", lessonNumber: 6, dayType: "thursday", isFirstHalf: true),
      LessonTime(start: "19:15", end: "20:00", lessonNumber: 6, dayType: "thursday", isFirstHalf: false),
    ],
    "saturday": [ // Суббота
      LessonTime(start: "8:00", end: "8:45", lessonNumber: 1, dayType: "saturday", isFirstHalf: true),
      LessonTime(start: "8:55", end: "9:40", lessonNumber: 1, dayType: "saturday", isFirstHalf: false),
      LessonTime(start: "9:50", end: "10:35", lessonNumber: 2, dayType: "saturday", isFirstHalf: true),
      LessonTime(start: "10:45", end: "11:30", lessonNumber: 2, dayType: "saturday", isFirstHalf: false),
      LessonTime(start: "11:50", end: "12:35", lessonNumber: 3, dayType: "saturday", isFirstHalf: true),
      LessonTime(start: "12:40", end: "13:25", lessonNumber: 3, dayType: "saturday", isFirstHalf: false),
      LessonTime(start: "13:35", end: "14:20", lessonNumber: 4, dayType: "saturday", isFirstHalf: true),
      LessonTime(start: "14:25", end: "15:10", lessonNumber: 4, dayType: "saturday", isFirstHalf: false),
      LessonTime(start: "15:20", end: "16:05", lessonNumber: 5, dayType: "saturday", isFirstHalf: true),
      LessonTime(start: "16:10", end: "16:55", lessonNumber: 5, dayType: "saturday", isFirstHalf: false),
      LessonTime(start: "17:05", end: "17:50", lessonNumber: 6, dayType: "saturday", isFirstHalf: true),
      LessonTime(start: "17:55", end: "18:40", lessonNumber: 6, dayType: "saturday", isFirstHalf: false),
    ],
  };

  // Получаем время для конкретной пары
  static List<LessonTime> getTimesForLesson(int lessonNumber, String dayType) {
    return lessonTimes[dayType]?.where((time) => time.lessonNumber == lessonNumber).toList() ?? [];
  }

  // Получить строковое представление времени пары
  static String getTimeRangeString(int lessonNumber, String dayType) {
    final times = getTimesForLesson(lessonNumber, dayType);
    if (times.length == 2) {
      return '${times[0].start} - ${times[1].end}';
    }
    return '';
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

  // Получить список дней с одинаковым расписанием
  static String getDaysWithSameSchedule(String dayType) {
    switch (dayType) {
      case "normal":
        return "Понедельник, среда, пятница";
      case "tuesday":
        return "Вторник";
      case "thursday":
        return "Четверг";
      case "saturday":
        return "Суббота";
      default:
        return "";
    }
  }
} 