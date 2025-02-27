import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/schedule_provider.dart';
import '../models/schedule_model.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/schedule_item_card.dart';
import '../widgets/bell_schedule_dialog.dart';
import '../widgets/error_snackbar.dart';
import 'package:share_plus/share_plus.dart';
import '../services/connectivity_service.dart';
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
  static const EdgeInsets _listPadding = EdgeInsets.all(8);
  static const Duration _animationDuration = Duration(milliseconds: 300);
  bool _hasShownOfflineWarning = false;

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
    final lastQuery = prefs.getString(_searchQueryKey) ?? '';
    setState(() {
      _searchQuery = lastQuery;
      _searchController.text = lastQuery;
    });
  }

  Future<void> _saveSearchQuery(String query) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_searchQueryKey, query);
  }

  String formatScheduleDate(String dateStr) {
    try {
      // Парсим дату формата "21-фев"
      final parts = dateStr.split('-');
      if (parts.length != 2) return dateStr;

      final day = int.parse(parts[0]);
      final monthMap = {
        'янв': 1, 'фев': 2, 'мар': 3, 'апр': 4,
        'май': 5, 'июн': 6, 'июл': 7, 'авг': 8,
        'сен': 9, 'окт': 10, 'ноя': 11, 'дек': 12
      };
      final month = monthMap[parts[1].toLowerCase()];
      if (month == null) return dateStr;

      final date = DateTime(DateTime.now().year, month, day);
      final weekDay = DateFormat('EEEE', 'ru_RU').format(date);
      
      return '${parts[0]} ${parts[1]}($weekDay)';
    } catch (e) {
      return dateStr;
    }
  }

  // Обновим поле поиска
  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
            _saveSearchQuery(value);
          });
        },
        decoration: InputDecoration(
          labelText: 'Поиск',
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.search_outlined), // Добавлена иконка поиска
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                      _saveSearchQuery('');
                    });
                  },
                )
              : null,
        ),
      ),
    );
  }

  // Обновим отображение даты
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
          formatScheduleDate(date),
          key: ValueKey<String>(date), // Важно для анимации
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.left,
        ),
      ),
    );
  }

  // Обновим навигацию точками
  Widget _buildPageDots(List<String> dates) {
    return Positioned(
      bottom: 16,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.8),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min, // Это сделает контейнер по размеру содержимого
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(dates.length, (index) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _currentPage == index
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceVariant,
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // Добавим метод для форматирования текста
  String _formatScheduleForSharing(List<ScheduleItem> lessons, String date) {
    final buffer = StringBuffer();
    
    if (lessons.isNotEmpty) {
      final group = lessons.first.group;
      buffer.writeln('📚 Расписание группы $group\n');
    }
    
    buffer.writeln('📅 ${formatScheduleDate(date)}');
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

  // Добавим метод для преобразования строковой даты в DateTime
  DateTime _parseDate(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length != 2) return DateTime.now();

    final day = int.parse(parts[0]);
    final monthMap = {
      'янв': 1, 'фев': 2, 'мар': 3, 'апр': 4,
      'май': 5, 'июн': 6, 'июл': 7, 'авг': 8,
      'сен': 9, 'окт': 10, 'ноя': 11, 'дек': 12
    };
    final month = monthMap[parts[1].toLowerCase()] ?? 1;
    
    return DateTime(DateTime.now().year, month, day);
  }

  @override
  Widget build(BuildContext context) {
    // Определяем текущую тему
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    // Цвета для кнопки обновления
    final buttonColor = isDarkMode 
        ? const Color(0xFF194874).withOpacity(0.8)
        : Colors.white;
    
    // Цвета для индикаторов
    final activeIndicatorColor = isDarkMode 
        ? Colors.white 
        : const Color(0xFF194874);
    final inactiveIndicatorColor = isDarkMode 
        ? Colors.white.withOpacity(0.3)
        : const Color(0xFF194874).withOpacity(0.3);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Расписание'),
        actions: [
          IconButton(
            icon: const Icon(Icons.access_time),
            onPressed: _showBellSchedule,
            tooltip: 'Расписание звонков',
          ),
        ],
      ),
      body: Consumer<ScheduleProvider>(
        builder: (context, provider, child) {
          // Показываем предупреждение об офлайн режиме через сервис
          if (provider.isOffline) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ConnectivityService().showOfflineWarning(context);
            });
          }

          // Показываем ошибки
          if (provider.errorMessage != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              CustomSnackBar.showError(
                context,
                provider.errorMessage!,
              );
              provider.dismissError();
            });
          }

          // Показываем успешные сообщения
          if (provider.successMessage != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              CustomSnackBar.showSuccess(
                context,
                provider.successMessage!,
              );
              provider.dismissSuccess();
            });
          }

          return Stack(
            children: [
              // Основной контент
              if (provider.isLoading) (
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      if (provider.status != null)
                        Text(provider.status!),
                    ],
                  ),
                )
              ) else if (provider.scheduleData == null || provider.scheduleData!.isEmpty) (
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Нет данных'),
                      if (!provider.isOffline)
                        ElevatedButton(
                          onPressed: () => provider.loadSchedule(),
                          child: const Text('Повторить загрузку'),
                        ),
                      if (provider.isOffline)
                        Text(
                          'Подключитесь к интернету для загрузки расписания',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
                )
              ) else (
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSearchField(),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _buildDateHeader(provider.scheduleData!.keys.toList()[_currentPage]),
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
                              final date = provider.scheduleData!.keys.toList()[index];
                              final daySchedule = provider.scheduleData![date]!;
                              final allLessons = <ScheduleItem>[];
                              
                              // Собираем все пары за день
                              for (var groupLessons in daySchedule.values) {
                                allLessons.addAll(groupLessons.toList());
                              }

                              // Фильтруем по поиску
                              final filteredLessons = _searchQuery.isEmpty
                                  ? allLessons
                                  : allLessons.where((lesson) {
                                      final query = _searchQuery.toLowerCase();
                                      return lesson.group.toLowerCase().contains(query) ||
                                             lesson.teacher.toLowerCase().contains(query) ||
                                             lesson.classroom.toLowerCase().contains(query) ||
                                             lesson.subject.toLowerCase().contains(query);
                                    }).toList();

                              // Сортируем по номеру пары
                              filteredLessons.sort((a, b) => a.lessonNumber.compareTo(b.lessonNumber));

                              return Stack(
                                children: [
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    transitionBuilder: (Widget child, Animation<double> animation) {
                                      return FadeTransition(
                                        opacity: animation,
                                        child: SlideTransition(
                                          position: Tween<Offset>(
                                            begin: Offset(_currentPage > index ? -1.0 : 1.0, 0.0),
                                            end: Offset.zero,
                                          ).animate(CurvedAnimation(
                                            parent: animation,
                                            curve: Curves.easeInOut,
                                          )),
                                          child: child,
                                        ),
                                      );
                                    },
                                    child: ListView.builder(
                                      key: PageStorageKey('schedule_list_$date'),
                                      itemCount: filteredLessons.length,
                                      padding: _listPadding,
                                      cacheExtent: 500,
                                      itemBuilder: (context, index) {
                                        if (!mounted) return const SizedBox();
                                        
                                        return ScheduleItemCard(
                                          key: ValueKey('${filteredLessons[index].hashCode}_$index'),
                                          item: filteredLessons[index],
                                          index: index,
                                          date: _parseDate(date),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          
                          // Индикатор страниц как отдельный слой поверх всего содержимого
                          if (provider.scheduleData != null && provider.scheduleData!.isNotEmpty)
                            Positioned(
                              bottom: 20,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isDarkMode 
                                      ? Colors.black.withOpacity(0.6)
                                      : Colors.white.withOpacity(0.6),
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
                                        if (provider.scheduleData!.keys.length > 10) {
                                          // Вычисляем диапазон отображаемых точек
                                          int start = _currentPage - 4;
                                          if (start < 0) start = 0;
                                          if (start > provider.scheduleData!.keys.length - 10) 
                                            start = provider.scheduleData!.keys.length - 10;
                                          
                                          // Если индекс вне диапазона, не показываем
                                          if (index + start >= provider.scheduleData!.keys.length) 
                                            return const SizedBox.shrink();
                                          
                                          // Проверяем, соответствует ли точка текущей странице
                                          bool isCurrentPage = (index + start) == _currentPage;
                                          
                                          return AnimatedContainer(
                                            duration: const Duration(milliseconds: 300),
                                            margin: const EdgeInsets.symmetric(horizontal: 4),
                                            height: 12,
                                            width: 12,
                                            decoration: BoxDecoration(
                                              color: isCurrentPage 
                                                ? const Color(0xFF2195F1) // Синий цвет для активной точки
                                                : isDarkMode
                                                  ? const Color(0xFF12293F).withOpacity(0.5) // Темная тема
                                                  : const Color(0xFFE3E3E3), // Светлая тема
                                              shape: BoxShape.circle,
                                            ),
                                          );
                                        } else {
                                          // Если дней меньше 10, показываем все точки
                                          return AnimatedContainer(
                                            duration: const Duration(milliseconds: 300),
                                            margin: const EdgeInsets.symmetric(horizontal: 4),
                                            height: 12,
                                            width: 12,
                                            decoration: BoxDecoration(
                                              color: _currentPage == index 
                                                ? const Color(0xFF2195F1) // Синий цвет для активной точки
                                                : isDarkMode
                                                  ? const Color(0xFF194874).withOpacity(0.5) // Темная тема
                                                  : const Color(0xFFE3E3E3), // Светлая тема
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
                )
              ),
            ],
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Кнопка поделиться
          if (_searchQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: FloatingActionButton(
                heroTag: "shareBtn",
                onPressed: _shareSchedule,
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF194874).withOpacity(0.8)
                    : const Color(0xFFFFFFFF).withOpacity(0.6), // Полупрозрачный в светлой теме
                elevation: 2,
                child: Icon(
                  Icons.share,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : const Color(0xFF194874),
                ),
              ),
            ),
          
          // Кнопка обновления
          Consumer<ScheduleProvider>(
            builder: (context, provider, child) {
              return FloatingActionButton(
                heroTag: "refreshBtn",
                onPressed: provider.isOffline ? null : () => provider.updateSchedule(),
                backgroundColor: provider.isOffline 
                    ? Colors.grey 
                    : (Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF194874).withOpacity(0.8)
                        : const Color(0xFFFFFFFF).withOpacity(0.6)), // Полупрозрачный в светлой теме
                elevation: 2,
                child: Icon(
                  Icons.refresh,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : const Color(0xFF194874),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pageController.dispose();
    _hasShownOfflineWarning = false;
    super.dispose();
  }

  // В классе ScheduleScreen добавим метод для показа диалога
  void _showBellSchedule() {
    showDialog(
      context: context,
      builder: (context) => const BellScheduleDialog(),
    );
  }

  // Добавим метод для поделиться расписанием
  void _shareSchedule() async {
    if (context.read<ScheduleProvider>().scheduleData != null) {
      final provider = context.read<ScheduleProvider>();
      final dates = provider.scheduleData!.keys.toList()..sort();
      final date = dates[_currentPage];
      final daySchedule = provider.scheduleData![date]!;
      final allLessons = <ScheduleItem>[];
      
      for (var groupLessons in daySchedule.values) {
        allLessons.addAll(groupLessons.toList());
      }

      final filteredLessons = allLessons.where((lesson) {
        final query = _searchQuery.toLowerCase();
        return lesson.group.toLowerCase().contains(query) ||
               lesson.teacher.toLowerCase().contains(query) ||
               lesson.classroom.toLowerCase().contains(query) ||
               lesson.subject.toLowerCase().contains(query);
      }).toList();

      if (filteredLessons.isNotEmpty) {
        final textToShare = _formatScheduleForSharing(filteredLessons, date);
        await Share.share(textToShare);
      }
    }
  }

  Future<void> _loadData() async {
    final provider = context.read<ScheduleProvider>();
    // Загружаем последовательно
    await provider.loadSchedule();
    await provider.loadGroupsAndTeachers();
  }
} 