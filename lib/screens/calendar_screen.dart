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
    
    // Получаем данные с учетом настроек отображения
    final scheduleData = provider.getScheduleForCalendar();
    if (scheduleData == null) return;

    _calendarEventsCache.clear();
    
    // Заполняем кэш событий для календаря
    for (var date in scheduleData.keys) {
      try {
        final dateTime = _parseDate(date);
        final daySchedule = scheduleData[date]!;
        
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
    final scheduleData = provider.getScheduleForCalendar();
    
    if (scheduleData == null || !scheduleData.containsKey(dateStr)) {
      return [];
    }
    
    // Собираем все уроки для этого дня
    final daySchedule = scheduleData[dateStr]!;
    final allLessons = <ScheduleItem>[];
    
    for (var groupLessons in daySchedule.values) {
      allLessons.addAll(groupLessons);
    }
    
    // Сортируем по номеру пары
    allLessons.sort((a, b) => a.lessonNumber.compareTo(b.lessonNumber));
    
    // Сохраняем в кэш
    _calendarEventsCache[date] = allLessons;
    
    return allLessons;
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
    
    // Если нет фильтра или нет уроков, возвращаем как есть
    if (_selectedFilter == 'all' || lessons.isEmpty) {
      return lessons;
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
    
    // Если после фильтрации ничего не осталось, показываем уведомление
    if (filteredLessons.isEmpty && lessons.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _selectedFilter == 'group'
                    ? 'Нет расписания для группы $_selectedGroup на этот день'
                    : 'Нет расписания для преподавателя $_selectedTeacher на этот день'
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      });
    }
    
    return filteredLessons;
  }

  // Преобразует номер месяца в строку для формата даты
  String _getMonthStr(int month) {
    const monthMap = {
      1: 'янв',
      2: 'фев',
      3: 'март',
      4: 'апр',
      5: 'май',
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
        },
      ),
    );
  }

  // Показывает цветные точки для дней с парами
  Widget _buildEventMarkers(DateTime date, ScheduleProvider scheduleProvider, NotesProvider notesProvider) {
    final hasSchedule = _getScheduleForDay(date).isNotEmpty;
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
      'апр': 4, 'май': 5,
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
    return Consumer<ScheduleProvider>(
      builder: (context, provider, child) {
        // Обновляем кэш при изменении данных или настроек
        if (provider.scheduleData != null && !_isInitialized) {
          _isInitialized = true;
          // Используем addPostFrameCallback, чтобы избежать ошибок setState во время build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _prepareCalendarData();
            }
          });
        }
        
        // Получаем заметку для выбранного дня
        final notesProvider = Provider.of<NotesProvider>(context);
        final selectedDayNote = _selectedDay != null 
            ? notesProvider.getNote(_selectedDay!) 
            : null;
        
        final hasAnySchedule = provider.fullScheduleData?.isNotEmpty ?? false;
        
        // Проверяем, есть ли расписание для текущего фильтра
        bool hasFilteredSchedule = false;
        if (hasAnySchedule && _selectedFilter != 'all') {
          for (var daySchedule in provider.fullScheduleData!.values) {
            if (_selectedFilter == 'group' && _selectedGroup != null) {
              if (daySchedule.containsKey(_selectedGroup)) {
                hasFilteredSchedule = true;
                break;
              }
            } else if (_selectedFilter == 'teacher' && _selectedTeacher != null) {
              for (var lessons in daySchedule.values) {
                if (lessons.any((l) => l.teacher == _selectedTeacher)) {
                  hasFilteredSchedule = true;
                  break;
                }
              }
            }
          }
        }

        // Показываем предупреждение, если нет расписания для выбранного фильтра
        if (!hasFilteredSchedule && _selectedFilter != 'all') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _selectedFilter == 'group'
                      ? 'Нет расписания для группы $_selectedGroup'
                      : 'Нет расписания для преподавателя $_selectedTeacher'
                ),
                duration: const Duration(seconds: 3),
              ),
            );
          });
        }

        // Используем отфильтрованное расписание для календаря
        final scheduleData = provider.getScheduleForCalendar();
        
        // Если нет данных, показываем пустой календарь
        if (scheduleData == null || scheduleData.isEmpty) {
          return const Center(
            child: Text('Нет данных о расписании'),
          );
        }
        
        // Получаем список групп и преподавателей для фильтров
        final groups = provider.groups;
        final teachers = provider.teachers;
        
        // Получаем расписание для выбранного дня
        final selectedDaySchedule = _selectedDay != null 
            ? _getScheduleForDay(_selectedDay!) 
            : <ScheduleItem>[];
        
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const Icon(Icons.calendar_today),
                const SizedBox(width: 10),
                const Text('Календарь'),
                const Spacer(),
                if (_selectedFilter != 'all')
                  Chip(
                    label: Text(_selectedFilter == 'group'
                        ? _selectedGroup ?? ''
                        : _selectedTeacher ?? ''),
                    onDeleted: () {
                      setState(() {
                        _selectedFilter = 'all';
                        _selectedGroup = null;
                        _selectedTeacher = null;
                      });
                      _saveSettings();
                    },
                  ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.filter_list),
                tooltip: 'Фильтр',
                onPressed: _showFilterDialog,
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
                        color: Theme.of(context).colorScheme.error,
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
                      final schedule = _getScheduleForDay(_selectedDay!);
                      final note = notesProvider.getNote(_selectedDay!);
                      
                      if (_noteController.text != note?.text) {
                        _noteController.text = note?.text ?? '';
                      }

                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (schedule.isEmpty && (_selectedFilter != 'all')) ...[
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
                                      _selectedFilter == 'group'
                                          ? 'Нет расписания для группы ${_selectedGroup}'
                                          : 'Нет расписания для преподавателя ${_selectedTeacher}',
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
      },
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
      'апр': 4, 'май': 5,
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

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }
} 