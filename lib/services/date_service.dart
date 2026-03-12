import 'package:flutter/foundation.dart';

/// Единый сервис для работы с датами в приложении
/// Обеспечивает консистентность парсинга и форматирования дат
class DateService {
  static const Map<String, int> _monthMap = {
    // Январь
    'янв': 1, 'января': 1, 'январь': 1,
    // Февраль
    'фев': 2, 'февр': 2, 'февраля': 2, 'февраль': 2,
    // Март
    'март': 3, 'мар': 3, 'марта': 3,
    // Апрель
    'апр': 4, 'апреля': 4, 'апрель': 4,
    // Май
    'май': 5, 'мая': 5,
    // Июнь
    'июн': 6, 'июня': 6, 'июнь': 6,
    // Июль
    'июл': 7, 'июля': 7, 'июль': 7,
    // Август
    'авг': 8, 'августа': 8, 'август': 8,
    // Сентябрь
    'сен': 9, 'сентября': 9, 'сентябрь': 9,
    // Октябрь
    'окт': 10, 'октября': 10, 'октябрь': 10,
    // Ноябрь
    'ноя': 11, 'нояб': 11, 'ноября': 11, 'ноябрь': 11,
    // Декабрь
    'дек': 12, 'декабря': 12, 'декабрь': 12,
    // Добавляем поддержку числового формата
    '01': 1, '02': 2, '03': 3, '04': 4,
    '05': 5, '06': 6, '07': 7, '08': 8,
    '09': 9, '10': 10, '11': 11, '12': 12,
  };

  static const Map<int, String> _monthNames = {
    1: 'января',
    2: 'февраля',
    3: 'марта',
    4: 'апреля',
    5: 'мая',
    6: 'июня',
    7: 'июля',
    8: 'августа',
    9: 'сентября',
    10: 'октября',
    11: 'ноября',
    12: 'декабря',
  };

  static const Map<int, String> _monthShortNames = {
    1: 'янв',
    2: 'фев',
    3: 'март',
    4: 'апр',
    5: 'мая',
    6: 'июнь',
    7: 'июль',
    8: 'авг',
    9: 'сен',
    10: 'окт',
    11: 'ноя',
    12: 'дек',
  };

  /// Парсит строку даты в формате "день.месяц.год" или "день-месяц" в DateTime
  /// Например: "08.12.2025" -> DateTime(2025, 12, 8)
  /// Или старый формат: "01-март" -> DateTime(year, 3, 1)
  static DateTime parseScheduleDate(String dateStr) {
    try {
      // Пробуем новый формат dd.MM.yyyy
      if (dateStr.contains('.')) {
        final parts = dateStr.split('.');
        if (parts.length == 3) {
          final day = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final year = int.parse(parts[2]);
          return DateTime(year, month, day);
        }
      }

      // Пробуем старый формат dd-MMM
      final parts = dateStr.split('-');
      if (parts.length != 2) {
        throw FormatException(
            'Неверный формат даты: $dateStr. Ожидается формат "dd.MM.yyyy" или "день-месяц"');
      }

      final day = int.parse(parts[0]);
      final monthStr = parts[1].toLowerCase().trim().replaceAll('.', '');

      final month = _monthMap[monthStr];
      if (month == null) {
        throw FormatException('Неизвестный месяц: $monthStr');
      }

      final year = _calculateAcademicYear(month);

      return DateTime(year, month, day);
    } catch (e) {
      debugPrint('❌ Ошибка парсинга даты "$dateStr": $e');
      rethrow;
    }
  }

  /// Определяет год для учебного расписания
  /// Учебный год: сентябрь текущего года - июнь следующего года
  static int _calculateAcademicYear(int month) {
    final now = DateTime.now();

    // Если сейчас сентябрь-декабрь, а дата январь-июнь, то это следующий год
    if (now.month >= 9 && month <= 6) {
      return now.year + 1;
    }
    // Если сейчас январь-июнь, а дата сентябрь-декабрь, то это предыдущий год
    else if (now.month <= 6 && month >= 9) {
      return now.year - 1;
    }
    // В остальных случаях используем текущий год
    else {
      return now.year;
    }
  }

  /// Форматирует DateTime в строку для отображения с днем недели
  /// Например: DateTime(2024, 11, 6) -> "6 ноября (четверг)"
  static String formatDateWithWeekday(DateTime date) {
    final monthName = _monthNames[date.month] ?? 'неизвестно';
    final weekdays = [
      'понедельник',
      'вторник',
      'среда',
      'четверг',
      'пятница',
      'суббота',
      'воскресенье'
    ];
    final weekday = weekdays[date.weekday - 1];
    return '${date.day} $monthName ($weekday)';
  }

  /// Форматирует строку даты в формате "день-месяц" в строку для отображения с днем недели
  /// Например: "6-нояб" -> "6 ноября (четверг)"
  static String formatDateStringWithWeekday(String dateStr) {
    try {
      final date = parseScheduleDate(dateStr);
      return formatDateWithWeekday(date);
    } catch (e) {
      debugPrint('❌ Ошибка форматирования даты "$dateStr": $e');
      return dateStr;
    }
  }

  /// Форматирует DateTime в строку для отображения
  /// Например: DateTime(2024, 3, 15) -> "15 марта"
  static String formatDateForDisplay(DateTime date) {
    final monthName = _monthNames[date.month] ?? 'неизвестно';
    return '${date.day} $monthName';
  }

  /// Форматирует DateTime в строку для хранения в базе
  /// Используем новый формат: "dd.MM.yyyy"
  /// Например: DateTime(2025, 12, 8) -> "08.12.2025"
  static String formatDateForStorage(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  /// Получает короткое название месяца по номеру
  static String getMonthShortName(int month) {
    return _monthShortNames[month] ?? 'неизвестно';
  }

  /// Получает полное название месяца по номеру
  static String getMonthFullName(int month) {
    return _monthNames[month] ?? 'неизвестно';
  }

  /// Проверяет, является ли дата валидной для расписания
  static bool isValidScheduleDate(String dateStr) {
    try {
      parseScheduleDate(dateStr);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Получает список дат в диапазоне для календаря
  static List<DateTime> getDateRange(DateTime start, DateTime end) {
    final dates = <DateTime>[];
    var current = DateTime(start.year, start.month, start.day);
    final endDate = DateTime(end.year, end.month, end.day);

    while (current.isBefore(endDate) || current.isAtSameMomentAs(endDate)) {
      dates.add(current);
      current = current.add(const Duration(days: 1));
    }

    return dates;
  }

  /// Проверяет, нужно ли удалить дату из архива
  static bool shouldDeleteFromArchive(String dateStr, int storageDays) {
    try {
      final date = parseScheduleDate(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final cutoffDate = today.subtract(Duration(days: storageDays));
      final dateOnly = DateTime(date.year, date.month, date.day);

      return dateOnly.isBefore(cutoffDate);
    } catch (e) {
      // Если дата не парсится, удаляем её
      debugPrint(
          '❌ Некорректная дата в архиве: $dateStr, рекомендуется удалить');
      return true;
    }
  }

  /// Получает текущую дату в формате для хранения
  static String getCurrentDateForStorage() {
    final now = DateTime.now();
    return formatDateForStorage(now);
  }

  /// Проверяет, является ли дата актуальной (сегодня или в будущем)
  static bool isActualDate(String dateStr) {
    try {
      final date = parseScheduleDate(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dateOnly = DateTime(date.year, date.month, date.day);

      return dateOnly.isAtSameMomentAs(today) || dateOnly.isAfter(today);
    } catch (e) {
      return false;
    }
  }

  /// Алиас для formatDateForStorage
  static String formatDate(DateTime date) {
    return formatDateForStorage(date);
  }

  /// Форматирует строку даты (dd-MMM) в строку для отображения (dd MMMM)
  static String formatDateString(String dateStr) {
    try {
      final date = parseScheduleDate(dateStr);
      return formatDateForDisplay(date);
    } catch (e) {
      return dateStr;
    }
  }

  /// Проверяет, совпадают ли два дня
  static bool isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }
}
