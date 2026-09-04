/*
 * Copyright (c) 2024 Daniil Gargun. All rights reserved.
 * Author: Daniil Gargun | Telegram: @Daniilgargun | Email: daniilgorgun38@gmail.com
 */

import 'dart:async';

import 'package:flutter/material.dart';
// ScrollCacheExtent объявлен в слое rendering и не реэкспортируется material.dart
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:provider/provider.dart';

import '../providers/schedule_provider.dart';
import '../providers/personalization_provider.dart';
import '../models/schedule_model.dart';
import '../models/personalization_settings.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/schedule_item_card.dart';
import '../widgets/bell_schedule_dialog.dart';
import '../widgets/error_snackbar.dart';

import 'package:share_plus/share_plus.dart';

import '../services/connectivity_service.dart';
import '../services/date_service.dart';
import '../services/schedule_search.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final PageController _pageController = PageController(initialPage: 0);
  int _currentPage = 0;
  static const String _searchQueryKey = 'last_search_query';
  static const String _searchScopeKey = 'last_search_scope';

  /// Поле, которым ограничен поиск. null — искать по всем полям.
  ///
  /// В колледже номера групп и кабинетов пересекаются (есть и группа 209,
  /// и кабинет 209), поэтому запрос по всем полям показывал группе 209
  /// ещё и чужие пары, проходящие в кабинете 209.
  EntityType? _searchScope;

  /// Запомненный разбор запроса: по каким полям он вообще что-то находит.
  /// Пересчитывается лениво, чтобы не бегать по всему расписанию на
  /// каждую перестройку.
  String? _scopeOptionsQuery;
  List<EntityType> _scopeOptions = const [];
  static const EdgeInsets _listPadding = EdgeInsets.all(8);
  bool _isRestoring = false;
  bool _isShareButtonPressed = false;
  bool _isRefreshButtonPressed = false;

  // Кэш для отфильтрованных данных
  final Map<String, List<ScheduleItem>> _filteredCache = {};

  // Подготовленные данные для всех дат
  final Map<String, List<ScheduleItem>> _preparedData = {};

  // Ссылка на карту расписания, из которой построен _preparedData.
  // Нужна, чтобы понять, что провайдер отдал новые данные: сравнение по
  // количеству дней пропускало обновления, в которых число дней не изменилось,
  // и экран показывал старое расписание.
  Map<String, Map<String, List<ScheduleItem>>>? _preparedSource;

  ScheduleProvider? _scheduleProvider;

  // Отложенное сохранение поискового запроса.
  //
  // Раньше каждое нажатие клавиши записывало запрос в SharedPreferences
  // и полностью пересобирало виджет на главном экране: сериализация всего
  // расписания в JSON плюс вызов через платформенный канал на каждый символ.
  // При наборе это заметно подтормаживало ввод.
  Timer? _searchSaveDebounce;
  static const Duration _searchSaveDelay = Duration(milliseconds: 600);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Сохраняем ссылку на провайдер
    _scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);
  }

  @override
  void initState() {
    super.initState();
    _loadLastSearchQuery();
    // Отложенная загрузка
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadLastSearchQuery() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final lastQuery = prefs.getString(_searchQueryKey) ?? '';
    final lastScope = EntityTypeLabel.fromStorage(
      prefs.getString(_searchScopeKey),
    );
    setState(() {
      _searchQuery = lastQuery;
      _searchController.text = lastQuery;
      _searchScope = lastScope;
    });
  }

  void _onSearchChanged(
    String value, {
    bool immediate = false,
    EntityType? scope,
  }) {
    setState(() {
      // При смене текста прежняя область теряет смысл: она выбиралась
      // под конкретный запрос.
      if (value != _searchQuery) {
        _searchScope = null;
        _filteredCache.clear();
      }
      // Подсказка из избранного знает, чем именно она была сохранена,
      // и сразу ставит нужную область.
      if (scope != null) {
        _searchScope = scope;
        _filteredCache.clear();
      }
      _searchQuery = value;
    });

    _searchSaveDebounce?.cancel();

    if (immediate) {
      _saveSearchQuery(value);
      return;
    }

    _searchSaveDebounce = Timer(_searchSaveDelay, () {
      if (mounted) _saveSearchQuery(value);
    });
  }

  /// Ограничивает поиск одним полем (или снимает ограничение).
  void _setSearchScope(EntityType? scope) {
    if (_searchScope == scope) return;
    setState(() {
      _searchScope = scope;
      _filteredCache.clear();
    });
    _saveSearchQuery(_searchQuery);
  }

  Future<void> _saveSearchQuery(String query) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_searchQueryKey, query);

    final scope = _searchScope;
    if (scope == null) {
      await prefs.remove(_searchScopeKey);
    } else {
      await prefs.setString(_searchScopeKey, scope.storageKey);
    }
    // Обновляем виджет при смене запроса
    if (_scheduleProvider != null) {
      await _scheduleProvider!.updateHomeWidget();
    }
  }

  String _formatDate(String dateStr) {
    return DateService.formatDateStringWithWeekday(dateStr);
  }

  // Кэш подсказок.
  //
  // Раньше подсказки пересчитывались на каждой перерисовке, а зерном
  // случайности служило текущее время — чипы перетасовывались буквально
  // на каждом кадре и «прыгали» под пальцем. Теперь набор меняется только
  // при смене данных или настроек подсказок.
  List<String>? _cachedSuggestions;
  int? _suggestionsSignature;
  final int _suggestionSeed = DateTime.now().millisecondsSinceEpoch;

  List<String> _getRandomSuggestions(ScheduleProvider provider) {
    final settings = provider.searchSettings;
    final signature = Object.hash(
      identityHashCode(provider.scheduleData),
      settings.useFavorites,
      settings.showGroups,
      settings.showTeachers,
      settings.showClassrooms,
      settings.showSubjects,
      settings.favoriteGroups.length,
      settings.favoriteTeachers.length,
      settings.favoriteClassrooms.length,
      settings.favoriteSubjects.length,
      provider.groups.length,
      provider.teachers.length,
    );

    final cached = _cachedSuggestions;
    if (cached != null && _suggestionsSignature == signature) {
      return cached;
    }

    final result = _buildSuggestions(provider);
    _suggestionsSignature = signature;
    _cachedSuggestions = result;
    return result;
  }

  List<String> _buildSuggestions(ScheduleProvider provider) {
    final suggestions = <String>{};
    final random = _suggestionSeed;

    // Получаем реальные данные
    if (provider.scheduleData != null && provider.scheduleData!.isNotEmpty) {
      final allItems = <ScheduleItem>[];

      // Собираем все уроки
      for (var daySchedule in provider.scheduleData!.values) {
        for (var groupSchedule in daySchedule.values) {
          allItems.addAll(groupSchedule);
        }
      }

      if (allItems.isEmpty) return [];

      // Добавляем случайную группу
      if (provider.groups.isNotEmpty && provider.searchSettings.showGroups) {
        suggestions.add(provider.groups[random % provider.groups.length]);
      }

      // Добавляем случайного преподавателя
      if (provider.teachers.isNotEmpty &&
          provider.searchSettings.showTeachers) {
        suggestions.add(
          provider.teachers[(random ~/ 2) % provider.teachers.length],
        );
      }

      // Добавляем случайный кабинет
      if (provider.searchSettings.showClassrooms) {
        final classrooms = allItems.map((e) => e.classroom).toSet().toList();
        if (classrooms.isNotEmpty) {
          suggestions.add(classrooms[(random ~/ 3) % classrooms.length]);
        }
      }

      // Добавляем случайный предмет
      if (provider.searchSettings.showSubjects) {
        final subjects = allItems.map((e) => e.subject).toSet().toList();
        if (subjects.isNotEmpty) {
          suggestions.add(subjects[(random ~/ 4) % subjects.length]);
        }
      }
    }

    // Возвращаем до 7 случайных подсказок
    return suggestions.take(7).toList();
  }

  // Создает чип для быстрого поиска
  Widget _buildSearchChip(String label) {
    return ActionChip(
      label: Text(label),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest
          .withAlpha((0.7 * 255).toInt()),
      onPressed: () {
        _searchController.text = label;
        // Выбор подсказки — однократное действие, сохраняем сразу.
        _onSearchChanged(label, immediate: true);
      },
    );
  }

  // Показывает информацию о поиске
  void _showSearchInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.search, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Как искать?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSearchInfoItem(
              Icons.group,
              'Группа',
              'Например: "383", "194"',
            ),
            const SizedBox(height: 12),
            _buildSearchInfoItem(
              Icons.person,
              'Преподаватель',
              'По фамилии: "Соловей", "Иванов"',
            ),
            const SizedBox(height: 12),
            _buildSearchInfoItem(
              Icons.class_,
              'Предмет',
              'Например: "Физика", "Математика"',
            ),
            const SizedBox(height: 12),
            _buildSearchInfoItem(Icons.room, 'Кабинет', 'Номер: "401", "О37"'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  // Создает элемент в диалоге информации о поиске
  Widget _buildSearchInfoItem(IconData icon, String title, String example) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(
                example,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Добавил красивую анимацию для даты
  Widget _buildDateHeader(String date) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 8.0),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 0.2),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: Text(
          _formatDate(date),
          key: ValueKey<String>(date), // Важно для анимации
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.left,
        ),
      ),
    );
  }

  // Добавил точки внизу для навигации между днями
  // Функция для форматирования текста при отправке расписания
  String _formatScheduleForSharing(List<ScheduleItem> lessons, String date) {
    final buffer = StringBuffer();

    if (lessons.isNotEmpty) {
      if (_searchQuery.isNotEmpty) {
        buffer.writeln('🔍 Результаты поиска: $_searchQuery\n');
      } else {
        final group = lessons.first.group;
        buffer.writeln('📚 Расписание группы $group\n');
      }
    }

    buffer.writeln('📅 ${_formatDate(date)}');
    buffer.writeln('═════════════════════\n');

    for (var lesson in lessons) {
      buffer.writeln('🕐 ${lesson.lessonNumber} пара');
      buffer.writeln('📚 ${lesson.subject}');
      buffer.writeln('👨‍🏫 ${lesson.teacher}');
      buffer.writeln('🏢 Кабинет: ${lesson.classroom}');
      if (lesson.subgroup != null && lesson.subgroup != "0") {
        buffer.writeln('👥 Подгруппа: ${lesson.subgroup}');
      }
      buffer.writeln('');
    }

    buffer.writeln('Отправлено из приложения БТК Расписание');
    return buffer.toString();
  }

  // Преобразует строку с датой в нормальный DateTime
  // Например из "01-март" делает DateTime
  DateTime _parseDate(String dateStr) {
    try {
      return DateService.parseScheduleDate(dateStr);
    } catch (e) {
      debugPrint('Ошибка парсинга даты: $e');
      return DateTime.now();
    }
  }

  // Подготавливаем данные для всех дат
  void _prepareData(ScheduleProvider provider) {
    if (provider.scheduleData == null) return;

    _preparedSource = provider.scheduleData;
    _preparedData.clear();
    _filteredCache.clear();
    _scopeOptionsQuery = null;

    for (var date in provider.scheduleData!.keys) {
      final daySchedule = provider.scheduleData![date]!;
      final allLessons = <ScheduleItem>[];

      for (var groupLessons in daySchedule.values) {
        allLessons.addAll(groupLessons.toList());
      }

      // Сортируем по номеру пары
      allLessons.sort((a, b) => a.lessonNumber.compareTo(b.lessonNumber));
      _preparedData[date] = allLessons;
    }

    // Проверяем, не вышли ли мы за пределы доступных дней после обновления данных
    if (provider.scheduleData!.isNotEmpty) {
      if (_currentPage >= provider.scheduleData!.length || _currentPage < 0) {
        _currentPage = provider.scheduleData!.length - 1;
        // Обновляем позицию PageController при изменении индекса
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) {
            _pageController.jumpToPage(_currentPage);
          }
        });
      }
    }
  }

  // Получаем отфильтрованные данные с использованием кэша
  List<ScheduleItem> _getFilteredLessons(String date, String query) {
    final cacheKey = '${date}_${query}_${_searchScope?.storageKey ?? 'all'}';

    if (_filteredCache.containsKey(cacheKey)) {
      return _filteredCache[cacheKey]!;
    }

    final allLessons = _preparedData[date] ?? [];
    final filteredLessons = ScheduleSearch.filter(
      allLessons,
      query,
      _searchScope,
    );

    _filteredCache[cacheKey] = filteredLessons;
    return filteredLessons;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Расписание'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showSearchInfo,
            tooltip: 'Как искать?',
          ),
          IconButton(
            icon: const Icon(Icons.access_time),
            onPressed: _showBellSchedule,
            tooltip: 'Расписание звонков',
          ),
        ],
      ),
      body: Consumer<ScheduleProvider>(
        builder: (context, provider, child) {
          // Подготавливаем данные при первой загрузке или обновлении расписания.
          // Сравниваем именно саму карту: провайдер при каждом обновлении
          // присваивает новый экземпляр, поэтому изменения внутри дня
          // (замена пары, смена кабинета) тоже попадут на экран.
          if (provider.scheduleData != null &&
              !identical(_preparedSource, provider.scheduleData)) {
            _prepareData(provider);
          }

          // Показываем предупреждение об офлайн режиме через сервис
          if (provider.isOffline) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ConnectivityService().showOfflineWarning(context);
            });
          }

          // Показываем ошибки с разными иконками в зависимости от типа
          if (provider.errorMessage != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final message = provider.errorMessage!;
              final isWarning =
                  message.contains("Новых дней") ||
                  message.contains("Слишком частые запросы");

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Icon(
                        isWarning ? Icons.warning_amber : Icons.error_outline,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(message)),
                    ],
                  ),
                  backgroundColor: isWarning ? Colors.orange : Colors.red,
                  duration: const Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              provider.dismissError();
            });
          }

          // Показываем успешные сообщения
          if (provider.successMessage != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              CustomSnackBar.showSuccess(context, provider.successMessage!);
              provider.dismissSuccess();
            });
          }

          // Проверяем, есть ли данные в fullScheduleData, но нет в scheduleData
          final hasArchiveButNoCurrentData =
              provider.fullScheduleData != null &&
              provider.fullScheduleData!.isNotEmpty &&
              (provider.scheduleData == null || provider.scheduleData!.isEmpty);

          return Stack(
            children: [
              // Основной контент
              if (provider.isLoading)
                (Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      if (provider.status != null) Text(provider.status!),
                    ],
                  ),
                ))
              else if (provider.scheduleData == null ||
                  provider.scheduleData!.isEmpty)
                (Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Нет данных'),
                      const SizedBox(height: 16),
                      if (hasArchiveButNoCurrentData)
                        ElevatedButton.icon(
                          onPressed: _isRestoring
                              ? null
                              : () async {
                                  setState(() => _isRestoring = true);
                                  try {
                                    await provider.syncScheduleData();
                                  } finally {
                                    if (mounted) {
                                      setState(() {
                                        _isRestoring = false;
                                        _prepareData(provider);
                                      });
                                    }
                                  }
                                },
                          icon: _isRestoring
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.sync_problem),
                          label: Text(
                            _isRestoring
                                ? 'Восстановление...'
                                : 'Восстановить расписание',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .primary,
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onPrimary,
                          ),
                        ),
                      if (!provider.isOffline && !hasArchiveButNoCurrentData)
                        ElevatedButton(
                          onPressed: () => provider.loadSchedule(),
                          child: const Text('Повторить загрузку'),
                        ),
                      if (provider.isOffline)
                        Text(
                          'Подключитесь к интернету для загрузки расписания',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
                ))
              else
                (Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSearchField(),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _buildDateHeader(
                        provider.orderedDates[_currentPage.clamp(
                          0,
                          provider.orderedDates.length - 1,
                        )],
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          PageView.builder(
                            controller: _pageController,
                            onPageChanged: (index) {
                              setState(() {
                                _currentPage = index;
                              });
                            },
                            itemCount: provider.scheduleData!.length,
                            itemBuilder: (context, index) {
                              final date = provider.orderedDates[index];
                              final filteredLessons = _getFilteredLessons(
                                date,
                                _searchQuery,
                              );

                              return Stack(
                                children: [
                                  if (filteredLessons.isEmpty)
                                    Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.event_busy,
                                            size: 64,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withAlpha((0.5 * 255).toInt()),
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            _searchQuery.isEmpty
                                                ? 'Нет расписания на этот день'
                                                : 'Нет расписания по вашему запросу',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurface
                                                      .withAlpha(
                                                        (0.7 * 255).toInt(),
                                                      ),
                                                ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      transitionBuilder:
                                          (
                                            Widget child,
                                            Animation<double> animation,
                                          ) {
                                            return FadeTransition(
                                              opacity: animation,
                                              child: SlideTransition(
                                                position:
                                                    Tween<Offset>(
                                                      begin: Offset(
                                                        _currentPage > index
                                                            ? -1.0
                                                            : 1.0,
                                                        0.0,
                                                      ),
                                                      end: Offset.zero,
                                                    ).animate(
                                                      CurvedAnimation(
                                                        parent: animation,
                                                        curve: Curves.easeInOut,
                                                      ),
                                                    ),
                                                child: child,
                                              ),
                                            );
                                          },
                                      child: Consumer<PersonalizationProvider>(
                                        builder: (context, personalizationProvider, _) {
                                          final displayFormat =
                                              personalizationProvider
                                                  .settings
                                                  .displayFormat;

                                          if (displayFormat ==
                                              DisplayFormat.grid) {
                                            // Сетка
                                            return GridView.builder(
                                              key: PageStorageKey(
                                                'schedule_grid_$date',
                                              ),
                                              scrollCacheExtent:
                                                  const ScrollCacheExtent.pixels(
                                                    1000,
                                                  ),
                                              gridDelegate:
                                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                                    crossAxisCount: 2,
                                                    crossAxisSpacing: 4,
                                                    mainAxisSpacing: 4,
                                                    // Карточка занимает высоту
                                                    // по содержимому: при 1.15
                                                    // почти половина карточки
                                                    // оставалась пустой.
                                                    childAspectRatio: 1.5,
                                                  ),
                                              padding: const EdgeInsets.all(4),
                                              itemCount: filteredLessons.length,
                                              itemBuilder: (context, index) {
                                                return TweenAnimationBuilder<
                                                  double
                                                >(
                                                  tween: Tween(
                                                    begin: 0.0,
                                                    end: 1.0,
                                                  ),
                                                  duration: Duration(
                                                    milliseconds:
                                                        220 +
                                                        (index.clamp(0, 5) *
                                                            40),
                                                  ),
                                                  curve: Curves.easeOut,
                                                  builder: (context, value, child) {
                                                    return Opacity(
                                                      opacity: value,
                                                      child:
                                                          Transform.translate(
                                                            offset: Offset(
                                                              0,
                                                              20 * (1 - value),
                                                            ),
                                                            child: child,
                                                          ),
                                                    );
                                                  },
                                                  child: RepaintBoundary(
                                                    child: ScheduleItemCard(
                                                      key: ValueKey(
                                                        filteredLessons[index],
                                                      ),
                                                      item:
                                                          filteredLessons[index],
                                                      index: index,
                                                      date: _parseDate(date),
                                                      isCompact: true,
                                                    ),
                                                  ),
                                                );
                                              },
                                            );
                                          } else {
                                            // Список
                                            return ListView.builder(
                                              key: PageStorageKey(
                                                'schedule_list_$date',
                                              ),
                                              scrollCacheExtent:
                                                  const ScrollCacheExtent.pixels(
                                                    1000,
                                                  ),
                                              itemCount: filteredLessons.length,
                                              padding: _listPadding,
                                              itemBuilder: (context, index) {
                                                return TweenAnimationBuilder<
                                                  double
                                                >(
                                                  tween: Tween(
                                                    begin: 0.0,
                                                    end: 1.0,
                                                  ),
                                                  duration: Duration(
                                                    milliseconds:
                                                        220 +
                                                        (index.clamp(0, 5) *
                                                            40),
                                                  ),
                                                  curve: Curves.easeOut,
                                                  builder: (context, value, child) {
                                                    return Opacity(
                                                      opacity: value,
                                                      child:
                                                          Transform.translate(
                                                            offset: Offset(
                                                              0,
                                                              20 * (1 - value),
                                                            ),
                                                            child: child,
                                                          ),
                                                    );
                                                  },
                                                  child: RepaintBoundary(
                                                    child: ScheduleItemCard(
                                                      key: ValueKey(
                                                        filteredLessons[index],
                                                      ),
                                                      item:
                                                          filteredLessons[index],
                                                      index: index,
                                                      date: _parseDate(date),
                                                    ),
                                                  ),
                                                );
                                              },
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),

                          // Индикатор страниц как отдельный слой поверх всего содержимого
                          if (provider.scheduleData != null &&
                              provider.scheduleData!.isNotEmpty)
                            Positioned(
                              bottom: 20,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surface
                                        .withValues(alpha: 0.8),
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: List.generate(
                                      provider.scheduleData!.keys.length > 10
                                          ? 10
                                          : provider.scheduleData!.keys.length,
                                      (index) {
                                        // Если дней больше 10, показываем только ближайшие к текущему
                                        if (provider.scheduleData!.keys.length >
                                            10) {
                                          // Вычисляем диапазон отображаемых точек
                                          int start = _currentPage - 4;
                                          if (start < 0) {
                                            start = 0;
                                          }
                                          if (start >
                                              provider
                                                      .scheduleData!
                                                      .keys
                                                      .length -
                                                  10) {
                                            start =
                                                provider
                                                    .scheduleData!
                                                    .keys
                                                    .length -
                                                10;
                                          }

                                          // Если индекс вне диапазона, не показываем
                                          if (index + start >=
                                              provider
                                                  .scheduleData!
                                                  .keys
                                                  .length) {
                                            return const SizedBox.shrink();
                                          }

                                          // Проверяем, соответствует ли точка текущей странице
                                          bool isCurrentPage =
                                              (index + start) == _currentPage;

                                          return AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 300,
                                            ),
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                            ),
                                            height: 12,
                                            width: 12,
                                            decoration: BoxDecoration(
                                              color: isCurrentPage
                                                  ? Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                  : Theme.of(context)
                                                        .colorScheme
                                                        .surfaceContainerHighest
                                                        .withValues(alpha: 0.5),
                                              shape: BoxShape.circle,
                                            ),
                                          );
                                        } else {
                                          // Если дней меньше 10, показываем все точки
                                          return AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 300,
                                            ),
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                            ),
                                            height: 12,
                                            width: 12,
                                            decoration: BoxDecoration(
                                              color: _currentPage == index
                                                  ? Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                  : Theme.of(context)
                                                        .colorScheme
                                                        .surfaceContainerHighest
                                                        .withValues(alpha: 0.5),
                                              shape: BoxShape.circle,
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                )),
            ],
          );
        },
      ),
      floatingActionButton: Builder(
        builder: (fabContext) {
          final colorScheme = Theme.of(fabContext).colorScheme;
          final shareBackground = colorScheme.primaryContainer.withValues(
            alpha: 0.8,
          );
          final shareForeground = colorScheme.onPrimaryContainer;
          final refreshEnabledBackground = colorScheme.primaryContainer
              .withValues(alpha: 0.8);
          final refreshEnabledForeground = colorScheme.onPrimaryContainer;
          final refreshDisabledBackground = colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.5);
          final refreshDisabledForeground = colorScheme.onSurfaceVariant;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Кнопка поделиться
              if (_searchQuery.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: GestureDetector(
                    onTapDown: (_) =>
                        setState(() => _isShareButtonPressed = true),
                    onTapUp: (_) =>
                        setState(() => _isShareButtonPressed = false),
                    onTapCancel: () =>
                        setState(() => _isShareButtonPressed = false),
                    child: AnimatedScale(
                      scale: _isShareButtonPressed ? 0.85 : 1.0,
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeInOutCubic,
                      child: FloatingActionButton(
                        heroTag: "shareBtn",
                        onPressed: _shareSchedule,
                        backgroundColor: shareBackground,
                        foregroundColor: shareForeground,
                        elevation: 1,
                        child: const Icon(Icons.share),
                      ),
                    ),
                  ),
                ),

              // Кнопка обновления
              Consumer<ScheduleProvider>(
                builder: (context, provider, child) {
                  final isOffline = provider.isOffline;
                  return GestureDetector(
                    onTapDown: (_) =>
                        setState(() => _isRefreshButtonPressed = true),
                    onTapUp: (_) =>
                        setState(() => _isRefreshButtonPressed = false),
                    onTapCancel: () =>
                        setState(() => _isRefreshButtonPressed = false),
                    child: AnimatedScale(
                      scale: _isRefreshButtonPressed ? 0.85 : 1.0,
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeInOutCubic,
                      child: FloatingActionButton(
                        heroTag: "refreshBtn",
                        onPressed: isOffline
                            ? null
                            : () => provider.updateSchedule(),
                        backgroundColor: isOffline
                            ? refreshDisabledBackground
                            : refreshEnabledBackground,
                        foregroundColor: isOffline
                            ? refreshDisabledForeground
                            : refreshEnabledForeground,
                        elevation: 1,
                        child: const Icon(Icons.refresh),
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _searchSaveDebounce?.cancel();
    _searchController.dispose();
    _pageController.dispose();
    _filteredCache.clear();
    _preparedData.clear();

    // Удаляем слушатель при уничтожении виджета
    _scheduleProvider?.removeListener(_onScheduleDataChanged);
    super.dispose();
  }

  // Показывает диалог с расписанием звонков
  void _showBellSchedule() {
    showDialog(
      context: context,
      builder: (context) => const BellScheduleDialog(),
    );
  }

  /// Переключатели категорий подсказок.
  ///
  /// Раньше это были четыре галочки в отдельном диалоге за неподписанной
  /// шестерёнкой. Диалог удалён: категории переключаются прямо здесь,
  /// а избранным управляет звезда в строке поиска.
  Widget _buildSuggestionCategories(ScheduleProvider provider) {
    final settings = provider.searchSettings;

    final categories = <(String, bool, Future<void> Function(bool))>[
      ('Группы', settings.showGroups, provider.toggleShowGroups),
      ('Преподы', settings.showTeachers, provider.toggleShowTeachers),
      ('Кабинеты', settings.showClassrooms, provider.toggleShowClassrooms),
      ('Предметы', settings.showSubjects, provider.toggleShowSubjects),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: categories
          .map(
            (category) => FilterChip(
              label: Text(category.$1),
              selected: category.$2,
              // Галочка заметно расширяет чип, а состояние и так видно
              // по заливке — иначе четыре категории занимают две строки.
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              onSelected: (value) => category.$3(value),
            ),
          )
          .toList(),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Consumer<ScheduleProvider>(
            builder: (context, provider, child) {
              final isFavorite = _isQueryFavorite(provider);

              return TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  labelText: 'Поиск',
                  hintText: 'Группа, преподаватель, предмет или кабинет',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.search_outlined),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                isFavorite ? Icons.star : Icons.star_border,
                                color: isFavorite
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              tooltip: isFavorite
                                  ? 'Убрать из избранного'
                                  : 'В избранное',
                              onPressed: () => _toggleFavorite(provider),
                            ),
                            IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: 'Очистить',
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged('', immediate: true);
                              },
                            ),
                          ],
                        ),
                ),
              );
            },
          ),

          _buildScopeSelector(),

          if (_searchQuery.isEmpty)
            Consumer<ScheduleProvider>(
              builder: (context, provider, child) {
                final favorites = _favoriteEntries(provider);
                final suggestions = _getRandomSuggestions(provider)
                    .where(
                      (item) => !favorites.any(
                        (fav) => fav.key.toLowerCase() == item.toLowerCase(),
                      ),
                    )
                    .toList();

                final theme = Theme.of(context);
                final captionStyle = theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Избранное видно всегда: прежний тумблер прятал его,
                    // и о разделе никто не знал.
                    if (favorites.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 6),
                        child: Text('Избранное', style: captionStyle),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: favorites
                            .map(
                              (entry) => InputChip(
                                avatar: const Icon(Icons.star, size: 16),
                                label: Text(entry.key),
                                onPressed: () => _onSearchChanged(
                                  entry.key,
                                  immediate: true,
                                  scope: entry.value,
                                ),
                                onDeleted: () => _removeFavoriteTyped(
                                  provider,
                                  entry.key,
                                  entry.value,
                                ),
                                deleteIcon: const Icon(Icons.close, size: 16),
                                tooltip: entry.value.label,
                              ),
                            )
                            .toList(),
                      ),
                    ],

                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 6),
                      child: Text('Подсказки', style: captionStyle),
                    ),
                    _buildSuggestionCategories(provider),
                    if (suggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: suggestions
                            .map((suggestion) => _buildSearchChip(suggestion))
                            .toList(),
                      ),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  // Функция для кнопки "Поделиться"
  // Собирает расписание в текст и открывает меню отправки
  void _shareSchedule() async {
    final provider = context.read<ScheduleProvider>();
    if (provider.scheduleData == null) return;

    // Раньше список дат сортировался как текст (`..sort()`), а PageView
    // использовал порядок ключей Map — из-за этого «Поделиться» отправляло
    // расписание не того дня, который открыт на экране.
    final dates = provider.orderedDates;
    if (dates.isEmpty || _currentPage < 0 || _currentPage >= dates.length) {
      return;
    }

    final date = dates[_currentPage];
    final filteredLessons = _getFilteredLessons(date, _searchQuery);

    if (filteredLessons.isEmpty) {
      if (mounted) {
        CustomSnackBar.showWarning(
          context,
          'Нечего отправить: на этот день нет расписания по вашему запросу',
        );
      }
      return;
    }

    final textToShare = _formatScheduleForSharing(filteredLessons, date);
    final box = context.findRenderObject() as RenderBox?;

    await SharePlus.instance.share(
      ShareParams(
        text: textToShare,
        // Нужно для корректного позиционирования листа "Поделиться" на iPad.
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  // Загружает данные при запуске
  Future<void> _loadData() async {
    if (!mounted || _scheduleProvider == null) return;

    // Загружаем последовательно
    await _scheduleProvider!.loadSchedule();
    await _scheduleProvider!.loadGroupsAndTeachers();

    if (!mounted) return;

    // Проверяем синхронизацию данных
    if (_scheduleProvider!.scheduleData == null ||
        _scheduleProvider!.scheduleData!.isEmpty) {
      if (_scheduleProvider!.fullScheduleData != null &&
          _scheduleProvider!.fullScheduleData!.isNotEmpty) {
        debugPrint('🔄 Запуск синхронизации расписания из архива');
        await _scheduleProvider!.syncScheduleData();
        if (!mounted) return;
        _prepareData(_scheduleProvider!);
      }
    }

    // Устанавливаем слушатель на изменение данных в провайдере
    _scheduleProvider!.addListener(_onScheduleDataChanged);
  }

  // Обработчик изменения данных в провайдере
  void _onScheduleDataChanged() {
    if (!mounted || _scheduleProvider == null) return;

    if (_scheduleProvider!.scheduleData != null) {
      setState(() {
        _prepareData(_scheduleProvider!);
      });
    }
  }

  // Показывает настройки подсказок поиска
  // Построение чипов для избранных элементов с возможностью удаления
  // Диалог для добавления нового элемента в избранное
  // Вспомогательный метод для добавления элемента в избранное
  /// Сколько занятий нашлось по каждому полю для текущего запроса.
  /// Считается один раз на запрос и переиспользуется при перестройках.
  Map<EntityType, int> _scopeCounts = const {};

  List<EntityType> _currentScopeOptions() {
    if (_scopeOptionsQuery == _searchQuery) return _scopeOptions;

    final query = _searchQuery;
    if (query.isEmpty) {
      _scopeOptionsQuery = query;
      _scopeOptions = const [];
      _scopeCounts = const {};
      return _scopeOptions;
    }

    final counts = <EntityType, int>{};
    for (final lessons in _preparedData.values) {
      ScheduleSearch.countByType(lessons, query).forEach((type, value) {
        counts[type] = (counts[type] ?? 0) + value;
      });
    }

    _scopeOptionsQuery = query;
    _scopeCounts = counts;
    _scopeOptions = EntityType.values
        .where((type) => (counts[type] ?? 0) > 0)
        .toList(growable: false);
    return _scopeOptions;
  }

  /// Избранное одним списком, вместе с полем, которым оно сохранено.
  List<MapEntry<String, EntityType>> _favoriteEntries(
    ScheduleProvider provider,
  ) {
    final settings = provider.searchSettings;
    return [
      ...settings.favoriteGroups.map((v) => MapEntry(v, EntityType.group)),
      ...settings.favoriteTeachers.map((v) => MapEntry(v, EntityType.teacher)),
      ...settings.favoriteClassrooms.map(
        (v) => MapEntry(v, EntityType.classroom),
      ),
      ...settings.favoriteSubjects.map((v) => MapEntry(v, EntityType.subject)),
    ];
  }

  bool _isQueryFavorite(ScheduleProvider provider) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return false;
    return _favoriteEntries(provider)
        .any((entry) => entry.key.toLowerCase() == query);
  }

  Future<void> _removeFavoriteTyped(
    ScheduleProvider provider,
    String value,
    EntityType type,
  ) async {
    switch (type) {
      case EntityType.group:
        await provider.removeFavoriteGroup(value);
      case EntityType.teacher:
        await provider.removeFavoriteTeacher(value);
      case EntityType.classroom:
        await provider.removeFavoriteClassroom(value);
      case EntityType.subject:
        await provider.removeFavoriteSubject(value);
    }
  }

  Future<void> _addFavoriteTyped(
    ScheduleProvider provider,
    String value,
    EntityType type,
  ) async {
    switch (type) {
      case EntityType.group:
        await provider.addFavoriteGroup(value);
      case EntityType.teacher:
        await provider.addFavoriteTeacher(value);
      case EntityType.classroom:
        await provider.addFavoriteClassroom(value);
      case EntityType.subject:
        await provider.addFavoriteSubject(value);
    }
  }

  /// Добавляет или убирает текущий запрос из избранного.
  ///
  /// Раньше, чтобы добавить одну группу, нужно было открыть неподписанную
  /// шестерёнку, включить тумблер «Использовать избранное» (без него раздел
  /// вообще не показывался), нажать «Добавить» и выбрать категорию во втором
  /// диалоге. Теперь это одна кнопка прямо в строке поиска.
  Future<void> _toggleFavorite(ScheduleProvider provider) async {
    final query = _searchQuery.trim();
    if (query.isEmpty) return;

    final existing = _favoriteEntries(provider)
        .where((entry) => entry.key.toLowerCase() == query.toLowerCase())
        .toList();

    if (existing.isNotEmpty) {
      for (final entry in existing) {
        await _removeFavoriteTyped(provider, entry.key, entry.value);
      }
      if (mounted) {
        CustomSnackBar.showSuccess(context, 'Убрано из избранного: $query');
      }
      return;
    }

    // Тип берём из выбранной области, иначе — из того, где запрос вообще
    // находится. Так «209» сохранится именно как группа, если пользователь
    // до этого выбрал область «Группа».
    final options = _currentScopeOptions();
    final type =
        _searchScope ?? (options.isNotEmpty ? options.first : EntityType.group);

    await _addFavoriteTyped(provider, query, type);
    if (mounted) {
      CustomSnackBar.showSuccess(
        context,
        'В избранное: $query (${type.label.toLowerCase()})',
      );
    }
  }

  /// Переключатель области поиска. Появляется только когда запрос
  /// неоднозначен — например, «209» это и группа, и кабинет.
  Widget _buildScopeSelector() {
    final options = _currentScopeOptions();
    if (_searchQuery.isEmpty || options.length < 2) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Совпадений несколько — уточните, что искать:',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Всё'),
                selected: _searchScope == null,
                onSelected: (_) => _setSearchScope(null),
              ),
              ...options.map(
                (type) => ChoiceChip(
                  label: Text(
                    '${type.shortLabel} · ${_scopeCounts[type] ?? 0}',
                  ),
                  selected: _searchScope == type,
                  onSelected: (_) => _setSearchScope(type),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Обновлен для добавления кнопки настроек
}
