import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../providers/schedule_provider.dart';
import '../models/schedule_model.dart';
import '../models/note_model.dart';
import '../providers/notes_provider.dart';
import 'package:intl/intl.dart';
import '../widgets/schedule_item_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/selection_dialog.dart';
import '../main.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  String _selectedFilter = 'all';
  String? _selectedGroup;
  String? _selectedTeacher;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  final TextEditingController _noteController = TextEditingController();
  static const String _filterKey = 'selected_filter';
  static const String _groupKey = 'selected_group';
  static const String _teacherKey = 'selected_teacher';
  static const String _calendarFormatKey = 'calendar_format';

  // Кэш для подготовленных данных календаря
  Map<DateTime, List<ScheduleItem>> _calendarEventsCache = {};
  CalendarFormat _savedFormat = CalendarFormat.month;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadSavedFormat();
    _loadSettings();
    _prepareCalendarData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateCurrentEntity();
    });
  }

  Future<void> _loadSavedFormat() async {
    final prefs = await SharedPreferences.getInstance();
    final savedFormat = prefs.getString('calendar_format') ?? 'month';
    setState(() {
      _savedFormat = _parseCalendarFormat(savedFormat);
      _calendarFormat = _savedFormat;
    });
  }

  void _prepareCalendarData() {
    final provider = Provider.of<ScheduleProvider>(context, listen: false);
    
    // Получаем полные данные архива, а не только filtered data
    final fullArchiveData = provider.fullScheduleData;
    final currentScheduleData = provider.scheduleData;
    
    if (fullArchiveData == null && currentScheduleData == null) return;
    
    // Очищаем кэш
    _calendarEventsCache.clear();
    
    // Основной источник данных - полный архив
    final sourceData = fullArchiveData ?? {};
    
    // Заполняем кэш событий для календаря из всего архива
    for (var date in sourceData.keys) {
      try {
        final dateTime = _parseDate(date);
        final daySchedule = sourceData[date]!;
        
        // Собираем все уроки для этого дня
        final allLessons = <ScheduleItem>[];
        for (var groupLessons in daySchedule.values) {
          allLessons.addAll(groupLessons);
        }
        
        // Сортируем по номеру пары
        allLessons.sort((a, b) => a.lessonNumber.compareTo(b.lessonNumber));
        
        // Сохраняем в кэш
        _calendarEventsCache[dateTime] = allLessons;
      } catch (e) {
        debugPrint('Ошибка при подготовке данных календаря: $e');
      }
    }
    
    // Дополнительно добавляем текущие данные, если есть
    if (currentScheduleData != null) {
      for (var date in currentScheduleData.keys) {
        try {
          final dateTime = _parseDate(date);
          final daySchedule = currentScheduleData[date]!;
          
          // Собираем все уроки для этого дня
          final allLessons = <ScheduleItem>[];
          for (var groupLessons in daySchedule.values) {
            allLessons.addAll(groupLessons);
          }
          
          // Сортируем по номеру пары
          allLessons.sort((a, b) => a.lessonNumber.compareTo(b.lessonNumber));
          
          // Сохраняем в кэш
          _calendarEventsCache[dateTime] = allLessons;
        } catch (e) {
          debugPrint('Ошибка при подготовке данных календаря: $e');
        }
      }
    }
    
    // Обновляем UI
    if (mounted) {
      setState(() {});
    }
  }

  List<ScheduleItem> _getEventsForDay(DateTime date) {
    // Проверяем, есть ли дата в кэше
    if (_calendarEventsCache.containsKey(date)) {
      return _calendarEventsCache[date]!;
    }
    
    // Если нет в кэше, пробуем найти по строковому представлению даты
    final day = date.day.toString().padLeft(2, '0');
    final monthStr = _getMonthStr(date.month);
    final dateStr = '$day-$monthStr';
    
    final provider = Provider.of<ScheduleProvider>(context, listen: false);
    final fullArchiveData = provider.fullScheduleData;
    final currentScheduleData = provider.scheduleData;
    
    if (fullArchiveData == null && currentScheduleData == null) {
      return [];
    }
    
    // Проверяем сначала в текущих данных
    if (currentScheduleData != null && currentScheduleData.containsKey(dateStr)) {
      final daySchedule = currentScheduleData[dateStr]!;
      final allLessons = <ScheduleItem>[];
      
      for (var groupLessons in daySchedule.values) {
        allLessons.addAll(groupLessons);
      }
      
      // Сортируем и кэшируем
      allLessons.sort((a, b) => a.lessonNumber.compareTo(b.lessonNumber));
      _calendarEventsCache[date] = allLessons;
      return allLessons;
    }
    
    // Затем проверяем в архиве
    if (fullArchiveData != null && fullArchiveData.containsKey(dateStr)) {
      final daySchedule = fullArchiveData[dateStr]!;
      final allLessons = <ScheduleItem>[];
      
      for (var groupLessons in daySchedule.values) {
        allLessons.addAll(groupLessons);
      }
      
      // Сортируем и кэшируем
      allLessons.sort((a, b) => a.lessonNumber.compareTo(b.lessonNumber));
      _calendarEventsCache[date] = allLessons;
      return allLessons;
    }
    
    return [];
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedFilter = prefs.getString(_filterKey) ?? 'all';
      _selectedGroup = prefs.getString(_groupKey);
      _selectedTeacher = prefs.getString(_teacherKey);
      
      // Загружаем сохраненный формат календаря
      final formatString = prefs.getString(_calendarFormatKey);
      if (formatString != null) {
        _calendarFormat = _parseCalendarFormat(formatString);
      }
    });
  }

  Future<void> _saveSettings() async {
    if (!mounted) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_filterKey, _selectedFilter);
    if (_selectedGroup != null) {
      await prefs.setString(_groupKey, _selectedGroup!);
    } else {
      await prefs.remove(_groupKey);
    }
    if (_selectedTeacher != null) {
      await prefs.setString(_teacherKey, _selectedTeacher!);
    } else {
      await prefs.remove(_teacherKey);
    }
    await prefs.setString(_calendarFormatKey, _calendarFormat.toString());
  }

  // Получаем расписание для выбранного дня с учетом фильтров
  List<ScheduleItem> _getScheduleForDay(DateTime day) {
    final lessons = _getEventsForDay(day);
    
    // Если нет фильтра, возвращаем пустой список - должен быть выбран фильтр
    if (_selectedFilter == 'all') {
      return [];
    }
    
    // Если нет уроков, возвращаем пустой список
    if (lessons.isEmpty) {
      return [];
    }
    
    // Применяем фильтр
    final filteredLessons = lessons.where((lesson) {
      if (_selectedFilter == 'group' && _selectedGroup != null) {
        return lesson.group == _selectedGroup;
      } else if (_selectedFilter == 'teacher' && _selectedTeacher != null) {
        return lesson.teacher == _selectedTeacher;
      }
      return true;
    }).toList();
    
    return filteredLessons;
  }

  // Преобразует номер месяца в строку для формата даты
  String _getMonthStr(int month) {
    const monthMap = {
      1: 'янв',
      2: 'фев',
      3: 'март',
      4: 'апр',
      5: 'мая',
      6: 'июн',
      7: 'июл',
      8: 'авг',
      9: 'сен',
      10: 'окт',
      11: 'ноя',
      12: 'дек',
    };
    return monthMap[month] ?? '';
  }

  // Обновленный диалог выбора фильтра с красивым дизайном
  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.filter_list, 
                  color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                const Text('Фильтр'),
              ],
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFilterOption(
                'Все расписание',
                'all',
                Icons.calendar_view_day,
              ),
              _buildFilterOption(
                'По группе',
                'group',
                Icons.group,
              ),
              _buildFilterOption(
                'По преподавателю',
                'teacher',
                Icons.person,
              ),
            ],
          ),
        );
      },
    );
  }

  // Делает кнопку фильтра с иконкой
  Widget _buildFilterOption(String title, String value, IconData icon) {
    final isSelected = _selectedFilter == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          Navigator.pop(context);
          
          if (value == 'group') {
            await Future.delayed(const Duration(milliseconds: 300));
            if (context.mounted) {
              await _showGroupSelectionDialog();
            }
          } else if (value == 'teacher') {
            await Future.delayed(const Duration(milliseconds: 300));
            if (context.mounted) {
              await _showTeacherSelectionDialog();
            }
          } else {
            setState(() {
              _selectedFilter = value;
              _selectedGroup = null;
              _selectedTeacher = null;
            });
            _saveSettings();
            _updateCurrentEntity();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          child: Row(
            children: [
              Icon(icon,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurface),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              if (isSelected)
                Icon(Icons.check,
                    color: Theme.of(context).colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showGroupSelectionDialog() async {
    final groups = context.read<ScheduleProvider>().groups;
    if (groups.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Список групп пуст')),
        );
      }
      return;
    }
    
    if (!context.mounted) return;
    
    await showDialog(
      context: context,
      builder: (context) => SelectionDialog(
        title: 'Выберите группу',
        items: groups,
        selectedItem: _selectedGroup,
        icon: Icons.group,
        onSelect: (group) {
          setState(() {
            _selectedFilter = 'group';
            _selectedGroup = group;
          });
          _saveSettings();
          _updateCurrentEntity();
        },
      ),
    );
  }

  Future<void> _showTeacherSelectionDialog() async {
    final teachers = context.read<ScheduleProvider>().teachers;
    if (teachers.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Список преподавателей пуст')),
        );
      }
      return;
    }
    
    if (!context.mounted) return;
    
    await showDialog(
      context: context,
      builder: (context) => SelectionDialog(
        title: 'Выберите\nпреподавателя',
        items: teachers,
        selectedItem: _selectedTeacher,
        icon: Icons.person,
        onSelect: (teacher) {
          setState(() {
            _selectedFilter = 'teacher';
            _selectedTeacher = teacher;
          });
          _saveSettings();
          _updateCurrentEntity();
        },
      ),
    );
  }

  // Показывает цветные точки для дней с парами
  Widget _buildEventMarkers(DateTime date, ScheduleProvider scheduleProvider, NotesProvider notesProvider) {
    final allEvents = _getEventsForDay(date); // Все события без фильтра
    final hasSchedule = _selectedFilter != 'all' && allEvents.isNotEmpty;
    final hasNote = notesProvider.hasNoteForDate(date);
    
    if (!hasSchedule && !hasNote) return const SizedBox.shrink();
    
    return Positioned(
      bottom: 1,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasSchedule)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: _getScheduleMarkerColor(date, scheduleProvider),
                shape: BoxShape.circle,
              ),
            ),
          if (hasNote)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.tertiary,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }

  // Выбирает цвет точки в зависимости от типа пары
  // Красный - Соловей
  // Синий - практика
  // Зеленый - лекция
  Color _getScheduleMarkerColor(DateTime date, ScheduleProvider provider) {
    final schedule = _getScheduleForDay(date);
    if (schedule.isEmpty) return Colors.transparent;

    // Проверяем типы пар в расписании
    bool hasPractice = false;
    bool hasLecture = false;
    bool hasSpecial = false; // для особых преподавателей или предметов

    for (var lesson in schedule) {
      if (lesson.subject.toLowerCase().contains('пр')) {
        hasPractice = true;
      } else if (lesson.teacher.toLowerCase().contains('соловей')) {
        hasSpecial = true;
      } else {
        hasLecture = true;
      }
    }

    // Приоритет цветов: особые > практические > лекции
    if (hasSpecial) {
      return Colors.red;
    } else if (hasPractice) {
      return Colors.blue;
    } else {
      return Colors.green;
    }
  }

  String _getCalendarFormatButtonText(CalendarFormat format) {
    switch (format) {
      case CalendarFormat.month:
        return 'Месяц';
      case CalendarFormat.twoWeeks:
        return '2 недели';
      case CalendarFormat.week:
        return 'Неделя';
      default:
        return 'Месяц';
    }
  }

  String _formatDate(String dateStr) {
    dateStr = dateStr.replaceAll('.', '');
    final parts = dateStr.split('-');
    if (parts.length != 2) return dateStr;

    final day = int.parse(parts[0]);
    final monthStr = parts[1].toLowerCase().trim();
    
    final monthNames = {
      'янв': 'января',
      'фев': 'февраля',
      'февр': 'февраля',
      'март': 'марта',
      'мар': 'марта',
      'апр': 'апреля',
      'май': 'мая',
      'мая': 'мая',
      'июн': 'июня',
      'июл': 'июля',
      'авг': 'августа',
      'сен': 'сентября',
      'окт': 'октября',
      'ноя': 'ноября',
      'дек': 'декабря',
    };

    final month = monthNames[monthStr] ?? monthStr;
    final weekday = _getWeekday(day, monthStr);
    
    return '$day $month';
  }

  String _getWeekday(int day, String monthStr) {
    // Определяем месяц
    final monthMap = {
      'янв': 1, 'фев': 2, 
      'март': 3, 'мар': 3,
      'апр': 4, 'май': 5, 'мая': 5,
      'июн': 6, 'июл': 7,
      'авг': 8, 'сен': 9,
      'окт': 10, 'ноя': 11,
      'дек': 12
    };
    
    final month = monthMap[monthStr.toLowerCase()] ?? 1;
    final now = DateTime.now();
    final year = month < now.month ? now.year + 1 : now.year;
    final date = DateTime(year, month, day);
    
    final weekdays = ['понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота', 'воскресенье'];
    return weekdays[date.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final scheduleProvider = Provider.of<ScheduleProvider>(context);
    final searchEntity = scheduleProvider.currentEntity;
    final title = searchEntity?.name ?? 'Календарь';
    
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_selectedFilter != 'all')
            TextButton(
              onPressed: _showFilterDialog,
              style: TextButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _selectedFilter == 'group' 
                      ? const Icon(Icons.group, size: 16) 
                      : const Icon(Icons.person, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    _selectedFilter == 'group' && _selectedGroup != null
                        ? _selectedGroup!
                        : _selectedTeacher ?? '',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: 'Фильтр',
          ),
        ],
      ),
      body: Column(
        children: [
          Consumer2<ScheduleProvider, NotesProvider>(
            builder: (context, scheduleProvider, notesProvider, child) {
              return TableCalendar(
                firstDay: DateTime.now().subtract(const Duration(days: 365)),
                lastDay: DateTime.now().add(const Duration(days: 365)),
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                calendarFormat: _calendarFormat,
                onFormatChanged: (format) {
                  setState(() {
                    _calendarFormat = format;
                    _saveCalendarFormat(format);
                  });
                },
                onPageChanged: (focusedDay) {
                  // Обновляем фокусный день при смене страницы
                  setState(() {
                    _focusedDay = focusedDay;
                    // Обновляем данные календаря при смене месяца
                    _prepareCalendarData();
                  });
                },
                locale: 'ru_RU',
                startingDayOfWeek: StartingDayOfWeek.monday,
                headerStyle: HeaderStyle(
                  formatButtonVisible: true,
                  formatButtonShowsNext: false,
                  titleCentered: true,
                  formatButtonDecoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.withOpacity(0.4)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  formatButtonTextStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  formatButtonPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  leftChevronIcon: const Icon(Icons.chevron_left),
                  rightChevronIcon: const Icon(Icons.chevron_right),
                ),
                calendarStyle: CalendarStyle(
                  outsideDaysVisible: true,
                  defaultTextStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  weekendTextStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  outsideTextStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
                  todayDecoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  selectedDecoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  weekendDecoration: BoxDecoration(
                    shape: BoxShape.circle,
                  ),
                  defaultDecoration: BoxDecoration(
                    shape: BoxShape.circle,
                  ),
                  todayTextStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                  selectedTextStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                  disabledTextStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                  ),
                ),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                },
                calendarBuilders: CalendarBuilders(
                  markerBuilder: (context, date, events) {
                    return _buildEventMarkers(date, scheduleProvider, notesProvider);
                  },
                  // Добавляем builder для отображения дополнительной информации
                  dowBuilder: (context, day) {
                    // Названия дней недели
                    final text = DateFormat.E('ru_RU').format(day);
                    
                    // Только воскресенье выделяем как выходной
                    if (day.weekday == DateTime.sunday) {
                      return Center(
                        child: Text(
                          text,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      );
                    }
                    return Center(child: Text(text));
                  },
                  // Заменяем cellBuilder на defaultBuilder, todayBuilder и selectedBuilder
                  defaultBuilder: (context, day, focusedDay) {
                    // Получаем события для дня
                    final events = _getEventsForDay(day);
                    final hasSchedule = events.isNotEmpty;
                    final hasNote = notesProvider.hasNoteForDate(day);
                    final isSunday = day.weekday == DateTime.sunday;
                    final isFuture = day.isAfter(DateTime.now());
                    
                    return Container(
                      margin: const EdgeInsets.all(2),
                      child: Stack(
                        children: [
                          // Число месяца
                          Center(
                            child: Text(
                              '${day.day}',
                              style: TextStyle(
                                color: isSunday 
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          
                          // Информационные метки больше не отображаются в ячейках календаря
                        ],
                      ),
                    );
                  },
                  selectedBuilder: (context, day, focusedDay) {
                    // Получаем события для дня
                    final events = _getEventsForDay(day);
                    final hasSchedule = events.isNotEmpty;
                    final hasNote = notesProvider.hasNoteForDate(day);
                    
                    return Container(
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Stack(
                        children: [
                          // Число месяца
                          Center(
                            child: Text(
                              '${day.day}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                          ),
                          // Никаких надписей, только индикаторы добавляются через markerBuilder
                        ],
                      ),
                    );
                  },
                  todayBuilder: (context, day, focusedDay) {
                    // Получаем события для дня
                    final events = _getEventsForDay(day);
                    final hasSchedule = events.isNotEmpty;
                    final hasNote = notesProvider.hasNoteForDate(day);
                    
                    return Container(
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                      child: Stack(
                        children: [
                          // Число месяца
                          Center(
                            child: Text(
                              '${day.day}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                          ),
                          // Никаких надписей, только индикаторы добавляются через markerBuilder
                        ],
                      ),
                    );
                  },
                  outsideBuilder: (context, day, focusedDay) {
                    return Container(
                      margin: const EdgeInsets.all(2),
                      child: Center(
                        child: Text(
                          '${day.day}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                eventLoader: _getEventsForDay,
                availableCalendarFormats: const {
                  CalendarFormat.month: 'Месяц',
                  CalendarFormat.twoWeeks: '2 недели',
                  CalendarFormat.week: 'Неделя',
                },
              );
            },
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: const Divider(
              thickness: 1.5,
            ),
          ),
          if (_selectedDay != null)
            Expanded(
              child: Consumer2<ScheduleProvider, NotesProvider>(
                builder: (context, provider, notesProvider, child) {
                  final allEvents = _getEventsForDay(_selectedDay!); // Все события без фильтра
                  final schedule = _selectedFilter == 'all' ? [] : _getScheduleForDay(_selectedDay!);
                  final note = notesProvider.getNote(_selectedDay!);
                  
                  if (_noteController.text != note?.text) {
                    _noteController.text = note?.text ?? '';
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Показываем сообщение о необходимости выбрать фильтр
                        if (_selectedFilter == 'all') ...[
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.filter_alt_outlined,
                                  size: 64,
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Выберите фильтр для просмотра расписания',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: _showFilterDialog,
                                  icon: const Icon(Icons.filter_list),
                                  label: const Text('Выбрать фильтр'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ]
                        // Показываем сообщение, если нет расписания для выбранного фильтра
                        else if (schedule.isEmpty && _selectedFilter != 'all') ...[
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.event_busy,
                                  size: 64,
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _getDetailedStatusText(_selectedDay!, provider, allEvents.isNotEmpty),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ] else if (schedule.isNotEmpty) ...[
                          Text(
                            'Расписание на ${_formatDate(DateFormat('d-MMM', 'ru_RU').format(_selectedDay!))}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          ...schedule.map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ScheduleItemCard(
                              item: item,
                              index: schedule.indexOf(item),
                              date: _selectedDay!,
                            ),
                          )),
                          const SizedBox(height: 16),
                        ],
                        Row(
                          children: [
                            Icon(Icons.note_alt_outlined,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Заметка на ${_formatDate(DateFormat('d-MMM', 'ru_RU').format(_selectedDay!))}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _noteController,
                          decoration: InputDecoration(
                            hintText: 'Добавить заметку...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                          ),
                          maxLines: 5,
                          onChanged: (value) {
                            if (value.trim().isEmpty) {
                              notesProvider.deleteNote(_selectedDay!);
                            } else {
                              notesProvider.saveNote(
                                Note(
                                  date: _selectedDay!,
                                  text: value,
                                ),
                              );
                            }
                          },
                          onTapOutside: (event) {
                            FocusScope.of(context).unfocus(); // Сбрасываем фокус при нажатии вне поля
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  CalendarFormat _parseCalendarFormat(String format) {
    switch (format) {
      case 'CalendarFormat.month':
        return CalendarFormat.month;
      case 'CalendarFormat.twoWeeks':
        return CalendarFormat.twoWeeks;
      case 'CalendarFormat.week':
        return CalendarFormat.week;
      default:
        return CalendarFormat.month;
    }
  }

  // Преобразует строку с датой в DateTime
  DateTime _parseDate(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length != 2) return DateTime.now();

    final day = int.parse(parts[0]);
    final monthStr = parts[1].toLowerCase().trim();
    
    final monthMap = {
      'янв': 1, 'фев': 2, 
      'март': 3, 'мар': 3,
      'апр': 4, 'май': 5, 'мая': 5,
      'июн': 6, 'июл': 7,
      'авг': 8, 'сен': 9,
      'окт': 10, 'ноя': 11,
      'дек': 12
    };
    
    final month = monthMap[monthStr] ?? 1;
    final now = DateTime.now();
    var year = now.year;
    
    if (month < now.month) {
      year++;
    }
    
    return DateTime(year, month, day);
  }

  void _saveCalendarFormat(CalendarFormat format) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('calendar_format', format.toString());
  }

  // Получает детальный статус для отображения в расписании
  String _getDetailedStatusText(DateTime day, ScheduleProvider provider, bool hasAnySchedule) {
    final now = DateTime.now();
    final isFuture = day.isAfter(now);
    final isOneDayAhead = day.difference(now).inDays <= 1 && day.isAfter(now);
    final isSunday = day.weekday == DateTime.sunday;
    
    // Если есть какое-то расписание на этот день, но нет для текущего фильтра
    if (hasAnySchedule) {
      if (_selectedFilter == 'group' && _selectedGroup != null) {
        return 'Нет расписания для группы $_selectedGroup на ${_formatDate(DateFormat('d-MMM', 'ru_RU').format(day))}';
      } else if (_selectedFilter == 'teacher' && _selectedTeacher != null) {
        return 'Нет расписания для преподавателя $_selectedTeacher на ${_formatDate(DateFormat('d-MMM', 'ru_RU').format(day))}';
      }
    }
    
    // Проверяем состояние дня
    if (isFuture) {
      if (isOneDayAhead) {
        return 'Расписание на ${_formatDate(DateFormat('d-MMM', 'ru_RU').format(day))} ещё не загружено\nОбновите данные позже';
      } else {
        return 'Расписание на ${_formatDate(DateFormat('d-MMM', 'ru_RU').format(day))} будет доступно позже';
      }
    } else if (isSunday) {
      return 'Выходной день - воскресенье';
    } else {
      return 'На ${_formatDate(DateFormat('d-MMM', 'ru_RU').format(day))} нет данных о расписании';
    }
  }

  // Получает текст статуса для дня без расписания (для отображения в маркерах календаря)
  String _getStatusText(DateTime day, ScheduleProvider provider) {
    final now = DateTime.now();
    final isFuture = day.isAfter(now);
    final isOneDayAhead = day.difference(now).inDays <= 1 && day.isAfter(now);
    final isSunday = day.weekday == DateTime.sunday;
    
    // Общее расписание без фильтра
    final allSchedule = provider.getScheduleForCalendar();
    
    if (allSchedule == null || allSchedule.isEmpty) {
      return isFuture ? "Ожидается" : "Нет данных";
    }
    
    // Проверяем, есть ли расписание для этого дня без учета фильтра
    final dateStr = '${day.day.toString().padLeft(2, '0')}-${_getMonthStr(day.month)}';
    final hasScheduleForDay = allSchedule.containsKey(dateStr);
    
    if (!hasScheduleForDay) {
      if (isFuture && isOneDayAhead) {
        return "Ожидается";
      } else if (isSunday) {
        return "Выходной";
      } else if (isFuture) {
        return "";
      } else {
        return "Нет данных";
      }
    }
    
    // Если есть расписание для дня, но после фильтрации ничего не осталось
    if (_selectedFilter != 'all') {
      if (_selectedFilter == 'group' && _selectedGroup != null) {
        return "Нет для группы";
      } else if (_selectedFilter == 'teacher' && _selectedTeacher != null) {
        return "Нет для преп.";
      }
    }
    
    return "";
  }

  // Обновляет текущую сущность для отображения в AppBar
  void _updateCurrentEntity() {
    final scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);
    
    if (_selectedFilter == 'group' && _selectedGroup != null) {
      scheduleProvider.setCurrentEntity(
        SearchEntity(
          name: _selectedGroup!,
          type: EntityType.group,
        ),
      );
    } else if (_selectedFilter == 'teacher' && _selectedTeacher != null) {
      scheduleProvider.setCurrentEntity(
        SearchEntity(
          name: _selectedTeacher!,
          type: EntityType.teacher,
        ),
      );
    } else {
      scheduleProvider.clearCurrentEntity();
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }
} 