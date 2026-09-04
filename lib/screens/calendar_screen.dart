import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../providers/schedule_provider.dart';
import '../models/schedule_model.dart';
import '../models/note_model.dart';
import '../providers/notes_provider.dart';

import 'package:intl/intl.dart';

import '../widgets/schedule_item_card.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/calendar_filter_sheet.dart';
import '../services/date_service.dart';
import '../services/cache_service.dart';

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

  // День, для которого текст заметки уже загружен в поле.
  //
  // Раньше текст подставлялся в контроллер при каждой перестройке, если он
  // отличался от сохранённого. Сохранение шло на каждый символ и было
  // асинхронным, поэтому во время быстрого набора провайдер успевал
  // уведомить слушателей со старым значением — поле перезаписывалось,
  // курсор прыгал в начало, часть символов терялась.
  DateTime? _loadedNoteDay;

  // Отложенная запись заметки в базу вместо записи на каждое нажатие.
  Timer? _noteSaveDebounce;
  static const Duration _noteSaveDelay = Duration(milliseconds: 500);
  static const String _filterKey = 'selected_filter';
  static const String _groupKey = 'selected_group';
  static const String _teacherKey = 'selected_teacher';
  static const String _calendarFormatKey = 'calendar_format';

  // Используем централизованный сервис кэширования
  final CacheService _cacheService = CacheService();
  CalendarFormat _savedFormat = CalendarFormat.month;
  bool _isInitialized = false;
  ScheduleProvider? _scheduleProvider; // Сохраняем ссылку на провайдер

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadSavedFormat();
    _loadSettings();
    // Не вызываем _prepareCalendarData здесь, так как виджет еще не готов
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Сохраняем ссылку на провайдер для безопасного удаления слушателя
    _scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);

    // Подготавливаем данные календаря после того, как зависимости готовы
    if (!_isInitialized) {
      _isInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scheduleProvider != null) {
          _prepareCalendarData();
          _updateCurrentEntity();
          // Добавляем слушатель изменений провайдера
          _scheduleProvider!.addListener(_onProviderChanged);
        }
      });
    }
  }

  // Обработчик изменений в провайдере
  void _onProviderChanged() {
    if (!mounted) return;

    // Используем SchedulerBinding для безопасного обновления
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _prepareCalendarData();
      }
    });
  }

  Future<void> _loadSavedFormat() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final savedFormat = prefs.getString('calendar_format') ?? 'month';
    setState(() {
      _savedFormat = _parseCalendarFormat(savedFormat);
      _calendarFormat = _savedFormat;
    });
  }

  // Карты, из которых построен текущий кэш календаря.
  // Провайдер уведомляет слушателей и по причинам, не связанным с данными
  // (скрытие ошибки, смена офлайн-статуса, выбор группы). Без этой проверки
  // весь кэш календаря очищался и перестраивался по всему архиву на каждое
  // такое уведомление — на больших архивах это заметный подтормаживание.
  Map<String, Map<String, List<ScheduleItem>>>? _calendarArchiveSource;
  Map<String, Map<String, List<ScheduleItem>>>? _calendarCurrentSource;

  void _prepareCalendarData({bool force = false}) {
    if (!mounted || _scheduleProvider == null) return;

    if (!force &&
        identical(
          _calendarArchiveSource,
          _scheduleProvider!.fullScheduleData,
        ) &&
        identical(_calendarCurrentSource, _scheduleProvider!.scheduleData)) {
      return;
    }

    _calendarArchiveSource = _scheduleProvider!.fullScheduleData;
    _calendarCurrentSource = _scheduleProvider!.scheduleData;

    try {
      // Получаем полные данные архива, а не только filtered data
      final fullArchiveData = _scheduleProvider!.fullScheduleData;
      final currentScheduleData = _scheduleProvider!.scheduleData;

      if (fullArchiveData == null && currentScheduleData == null) return;

      // Очищаем кэш календаря
      _cacheService.clearCalendarCache();

      // Основной источник данных - полный архив
      final sourceData = fullArchiveData ?? {};

      // Заполняем кэш событий для календаря из всего архива
      for (var date in sourceData.keys) {
        try {
          final dateTime = DateService.parseScheduleDate(date);
          final daySchedule = sourceData[date]!;

          // Собираем все уроки для этого дня
          final allLessons = <ScheduleItem>[];
          for (var groupLessons in daySchedule.values) {
            allLessons.addAll(groupLessons);
          }

          // Сортируем по номеру пары
          allLessons.sort((a, b) => a.lessonNumber.compareTo(b.lessonNumber));

          // Сохраняем в кэш
          _cacheService.setCalendarEvents(dateTime, allLessons);
        } catch (e) {
          debugPrint(
            'Ошибка при подготовке данных календаря для даты $date: $e',
          );
          // Продолжаем обработку других дат
        }
      }

      // Дополнительно добавляем текущие данные, если есть
      if (currentScheduleData != null) {
        for (var date in currentScheduleData.keys) {
          try {
            final dateTime = DateService.parseScheduleDate(date);
            final daySchedule = currentScheduleData[date]!;

            // Собираем все уроки для этого дня
            final allLessons = <ScheduleItem>[];
            for (var groupLessons in daySchedule.values) {
              allLessons.addAll(groupLessons);
            }

            // Сортируем по номеру пары
            allLessons.sort((a, b) => a.lessonNumber.compareTo(b.lessonNumber));

            // Сохраняем в кэш (перезаписываем, если уже есть)
            _cacheService.setCalendarEvents(dateTime, allLessons);
          } catch (e) {
            debugPrint(
              'Ошибка при подготовке текущих данных календаря для даты $date: $e',
            );
            // Продолжаем обработку других дат
          }
        }
      }

      // Обновляем UI
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Ошибка в _prepareCalendarData: $e');
    }
  }

  List<ScheduleItem> _getEventsForDay(DateTime date) {
    // Проверяем, есть ли дата в кэше
    final cachedEvents = _cacheService.getCalendarEvents(date);
    if (cachedEvents != null) {
      return cachedEvents;
    }

    // Если нет в кэше, пробуем найти по строковому представлению даты
    final dateStr = DateService.formatDateForStorage(date);

    if (_scheduleProvider == null) return [];

    final fullArchiveData = _scheduleProvider!.fullScheduleData;
    final currentScheduleData = _scheduleProvider!.scheduleData;

    if (fullArchiveData == null && currentScheduleData == null) {
      return [];
    }

    // Проверяем сначала в текущих данных
    if (currentScheduleData != null &&
        currentScheduleData.containsKey(dateStr)) {
      final daySchedule = currentScheduleData[dateStr]!;
      final allLessons = <ScheduleItem>[];

      for (var groupLessons in daySchedule.values) {
        allLessons.addAll(groupLessons);
      }

      // Сортируем и кэшируем
      allLessons.sort((a, b) => a.lessonNumber.compareTo(b.lessonNumber));
      _cacheService.setCalendarEvents(date, allLessons);
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
      _cacheService.setCalendarEvents(date, allLessons);
      return allLessons;
    }

    return [];
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

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

    // Если нет уроков, возвращаем пустой список
    if (lessons.isEmpty) {
      return [];
    }

    // Если выбран фильтр "все", возвращаем все уроки
    if (_selectedFilter == 'all') {
      return lessons;
    }

    // Применяем конкретный фильтр
    final filteredLessons = lessons.where((lesson) {
      if (_selectedFilter == 'group' && _selectedGroup != null) {
        return lesson.group == _selectedGroup;
      } else if (_selectedFilter == 'teacher' && _selectedTeacher != null) {
        return lesson.teacher == _selectedTeacher;
      }
      return false; // Если фильтр выбран, но значение не установлено
    }).toList();

    return filteredLessons;
  }

  // Обновленный диалог выбора фильтра с красивым дизайном
  // Делает кнопку фильтра с иконкой
  /// Открывает лист фильтра.
  ///
  /// Раньше здесь было два диалога подряд: сначала выбор типа фильтра,
  /// затем отдельное окно со списком. Теперь один лист с вкладками.
  Future<void> _showFilterDialog() async {
    final provider = _scheduleProvider;
    if (provider == null) return;

    final result = await showCalendarFilterSheet(
      context: context,
      groups: provider.groups,
      teachers: provider.teachers,
      selectedFilter: _selectedFilter,
      selectedGroup: _selectedGroup,
      selectedTeacher: _selectedTeacher,
    );

    if (result == null || !mounted) return;

    setState(() {
      _selectedFilter = result.filter;
      _selectedGroup = result.group;
      _selectedTeacher = result.teacher;
    });

    _saveSettings();
    _updateCurrentEntity();
  }

  // Показывает цветные точки для дней с парами
  Widget _buildEventMarkers(
    DateTime date,
    ScheduleProvider scheduleProvider,
    NotesProvider notesProvider,
  ) {
    final allEvents = _getEventsForDay(date); // Все события без фильтра
    final hasSchedule = allEvents.isNotEmpty;
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
    bool hasSpecial = false; // для особых преподавателей или предметов

    for (var lesson in schedule) {
      if (lesson.subject.toLowerCase().contains('пр')) {
        hasPractice = true;
      } else if (lesson.teacher.toLowerCase().contains('соловей')) {
        hasSpecial = true;
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

  @override
  Widget build(BuildContext context) {
    final scheduleProvider =
        _scheduleProvider ?? Provider.of<ScheduleProvider>(context);
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
                backgroundColor: Theme.of(context).colorScheme.primaryContainer
                    .withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
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
                    border: Border.all(
                      color: Colors.grey.withValues(alpha: 0.4),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  formatButtonTextStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  formatButtonPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
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
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.5),
                  ),
                  todayDecoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  selectedDecoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  weekendDecoration: BoxDecoration(shape: BoxShape.circle),
                  defaultDecoration: BoxDecoration(shape: BoxShape.circle),
                  todayTextStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                  selectedTextStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                  disabledTextStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.3),
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
                    return _buildEventMarkers(
                      date,
                      scheduleProvider,
                      notesProvider,
                    );
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
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      );
                    }
                    return Center(child: Text(text));
                  },
                  // Заменяем cellBuilder на defaultBuilder, todayBuilder и selectedBuilder
                  defaultBuilder: (context, day, focusedDay) {
                    // Метки о наличии пар и заметок рисует markerBuilder,
                    // здесь достаточно самого числа.
                    final isSunday = day.weekday == DateTime.sunday;

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
                    return Container(
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary
                            .withValues(alpha: 0.3),
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
                            color: Theme.of(context).colorScheme.onSurface
                                .withValues(alpha: 0.3),
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
            child: const Divider(thickness: 1.5),
          ),
          if (_selectedDay != null)
            Expanded(
              child: Consumer2<ScheduleProvider, NotesProvider>(
                builder: (context, provider, notesProvider, child) {
                  final allEvents = _getEventsForDay(
                    _selectedDay!,
                  ); // Все события без фильтра
                  final schedule = _getScheduleForDay(_selectedDay!);
                  final note = notesProvider.getNote(_selectedDay!);

                  // Подставляем текст только при смене выбранного дня,
                  // иначе поле перетирается во время ввода.
                  if (_loadedNoteDay == null ||
                      !DateService.isSameDay(_loadedNoteDay!, _selectedDay!)) {
                    _loadedNoteDay = _selectedDay;
                    final text = note?.text ?? '';
                    if (_noteController.text != text) {
                      _noteController.text = text;
                    }
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Показываем сообщение, если нет расписания для выбранного дня
                        if (schedule.isEmpty) ...[
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.event_busy,
                                  size: 64,
                                  color: Theme.of(context).colorScheme.primary
                                      .withValues(alpha: 0.5),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _getDetailedStatusText(
                                    _selectedDay!,
                                    provider,
                                    allEvents.isNotEmpty,
                                  ),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.7),
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ] else if (schedule.isNotEmpty) ...[
                          Text(
                            'Расписание на ${DateService.formatDateForDisplay(_selectedDay!)}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          ...schedule.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: ScheduleItemCard(
                                item: item,
                                index: schedule.indexOf(item),
                                date: _selectedDay!,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Row(
                          children: [
                            Icon(
                              Icons.note_alt_outlined,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Заметка на ${DateService.formatDateForDisplay(_selectedDay!)}',
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
                            // День фиксируем здесь: если пользователь
                            // переключит дату до срабатывания таймера,
                            // текст всё равно попадёт в нужный день.
                            final day = _selectedDay!;
                            _noteSaveDebounce?.cancel();
                            _noteSaveDebounce = Timer(
                              _noteSaveDelay,
                              () => _persistNote(notesProvider, day, value),
                            );
                          },
                          onTapOutside: (event) {
                            // Записываем сразу, чтобы правка не потерялась,
                            // если пользователь тут же уйдёт с экрана.
                            _noteSaveDebounce?.cancel();
                            _persistNote(
                              notesProvider,
                              _selectedDay!,
                              _noteController.text,
                            );
                            FocusScope.of(context).unfocus();
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

  void _saveCalendarFormat(CalendarFormat format) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('calendar_format', format.toString());
  }

  // Получает детальный статус для отображения в расписании
  String _getDetailedStatusText(
    DateTime day,
    ScheduleProvider provider,
    bool hasAnySchedule,
  ) {
    final now = DateTime.now();
    final isFuture = day.isAfter(now);
    final isOneDayAhead = day.difference(now).inDays <= 1 && day.isAfter(now);
    final isSunday = day.weekday == DateTime.sunday;

    // Если есть какое-то расписание на этот день, но нет для текущего фильтра
    if (hasAnySchedule) {
      if (_selectedFilter == 'group' && _selectedGroup != null) {
        return 'Нет расписания для группы $_selectedGroup на ${DateService.formatDateForDisplay(day)}';
      } else if (_selectedFilter == 'teacher' && _selectedTeacher != null) {
        return 'Нет расписания для преподавателя $_selectedTeacher на ${DateService.formatDateForDisplay(day)}';
      }
    }

    // Проверяем состояние дня
    if (isFuture) {
      if (isOneDayAhead) {
        return 'Расписание на ${DateService.formatDateForDisplay(day)} ещё не загружено\nОбновите данные позже';
      } else {
        return 'Расписание на ${DateService.formatDateForDisplay(day)} будет доступно позже';
      }
    } else if (isSunday) {
      return 'Выходной день - воскресенье';
    } else {
      return 'На ${DateService.formatDateForDisplay(day)} нет данных о расписании';
    }
  }

  // Обновляет текущую сущность для отображения в AppBar
  void _updateCurrentEntity() {
    if (!mounted || _scheduleProvider == null) return;

    try {
      if (_selectedFilter == 'group' && _selectedGroup != null) {
        _scheduleProvider!.setCurrentEntity(
          SearchEntity(name: _selectedGroup!, type: EntityType.group),
        );
      } else if (_selectedFilter == 'teacher' && _selectedTeacher != null) {
        _scheduleProvider!.setCurrentEntity(
          SearchEntity(name: _selectedTeacher!, type: EntityType.teacher),
        );
      } else {
        _scheduleProvider!.clearCurrentEntity();
      }
    } catch (e) {
      debugPrint('Ошибка в _updateCurrentEntity: $e');
    }
  }

  /// Записывает или удаляет заметку указанного дня.
  void _persistNote(NotesProvider notesProvider, DateTime day, String value) {
    if (value.trim().isEmpty) {
      notesProvider.deleteNote(day);
    } else {
      notesProvider.saveNote(Note(date: day, text: value));
    }
  }

  @override
  void dispose() {
    _noteSaveDebounce?.cancel();

    // Удаляем слушатель изменений провайдера безопасно
    if (_scheduleProvider != null) {
      try {
        _scheduleProvider!.removeListener(_onProviderChanged);
      } catch (e) {
        // Игнорируем ошибки, если провайдер уже деактивирован
        debugPrint('Ошибка при удалении слушателя: $e');
      }
    }

    _noteController.dispose();
    super.dispose();
  }
}
