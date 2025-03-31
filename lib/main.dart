// Главный файл приложения
// Тут настраиваем все основные штуки и запускаем приложение

import 'package:flutter/material.dart';
import 'screens/schedule_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/settings_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/notes_provider.dart';
import 'services/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'services/connectivity_service.dart';
import 'services/ads_service.dart';
import 'dart:async';
import 'dart:io';
import 'screens/minigame_screen.dart';

void main() {
  // Исправляем ошибку зон, перемещая runZonedGuarded снаружи, чтобы
  // ensureInitialized был вызван внутри зоны
  runZonedGuarded(() async {
    // Инициализируем всякие важные штуки
    WidgetsFlutterBinding.ensureInitialized();
    
    // Глобальный обработчик ошибок Flutter
    FlutterError.onError = (FlutterErrorDetails details) {
      // Если это не ошибка OpenGL, выводим в консоль
      if (!details.toString().contains('OpenGL ES API')) {
        debugPrint('Flutter Error: ${details.exception}');
        FlutterError.presentError(details);
      }
    };
    
    // Настраиваем временные зоны (нужно для уведомлений)
    tz.initializeTimeZones();
    
    // Запускаем сервис проверки интернета
    final connectivityService = ConnectivityService();
    await connectivityService.init();
    
    // Создаем все нужные сервисы заранее
    final databaseService = DatabaseService();
    await databaseService.database;
    
    final scheduleProvider = ScheduleProvider();
    final notesProvider = NotesProvider();
    
    // Настраиваем русский язык для дат
    await initializeDateFormatting('ru_RU', null);

    // Загружаем данные в фоне
    Future.microtask(() async {
      await notesProvider.loadNotes();
      await scheduleProvider.loadSchedule();
    });

    // Инициализируем рекламу
    Future.delayed(const Duration(seconds: 3), () async {
      try {
        debugPrint('------ ИНИЦИАЛИЗАЦИЯ РЕКЛАМЫ ------');
        debugPrint('Начинаем инициализацию Яндекс.Рекламы...');
        debugPrint('Устройство: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
        
        final stopwatch = Stopwatch()..start();
        await AdsService().initialize();
        stopwatch.stop();
        
        debugPrint('Яндекс.Реклама успешно инициализирована');
        debugPrint('Время инициализации: ${stopwatch.elapsedMilliseconds}ms');
        debugPrint('----------------------------------');
      } catch (e, stackTrace) {
        debugPrint('------ ОШИБКА ИНИЦИАЛИЗАЦИИ РЕКЛАМЫ ------');
        debugPrint('Ошибка при инициализации рекламы: $e');
        debugPrint('Устройство: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
        
        // Делим стек ошибки на строки для лучшей читаемости в логах
        final stackLines = stackTrace.toString().split('\n');
        debugPrint('Стек ошибки:');
        for (final line in stackLines.take(10)) { // Ограничиваем вывод стека 10 строками
          debugPrint('  $line');
        }
        debugPrint('------------------------------------------');
      }
    });

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => scheduleProvider),
          ChangeNotifierProvider(create: (_) => notesProvider),
        ],
        child: const MyApp(),
      ),
    );
  }, (error, stack) {
    debugPrint('Unhandled exception: $error');
    debugPrint('Stack trace: $stack');
  });
}

// Главный виджет приложения
// Настраиваем тему и навигацию
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  bool? _isDarkMode;
  bool _useDynamicColors = false;

  @override
  void initState() {
    super.initState();
    _loadThemeSettings();
  }

  Future<void> _loadThemeSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getBool('is_dark_mode');
    
    setState(() {
      // Если тема ещё не была сохранена (первый запуск),
      // используем системную тему
      if (savedTheme == null) {
        final window = WidgetsBinding.instance.window;
        final brightness = window.platformBrightness;
        _isDarkMode = brightness == Brightness.dark;
        // Сохраняем выбранную тему
        prefs.setBool('is_dark_mode', _isDarkMode!);
      } else {
        _isDarkMode = savedTheme;
      }
      _useDynamicColors = prefs.getBool('use_dynamic_colors') ?? false;
    });
  }
  
  // Добавляем метод для обновления темы из SettingsScreen
  void updateTheme(bool isDarkMode) {
    setState(() {
      _isDarkMode = isDarkMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Если тема ещё не загружена, показываем загрузочный экран
    if (_isDarkMode == null) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'Мобильное приложение',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: _isDarkMode == true ? ThemeMode.dark : ThemeMode.light,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ru', 'RU'),
      ],
      home: const MyHomePage(),
    );
  }
}

// Нижняя панель навигации
// Переключает между экранами:
// - Расписание
// - Календарь 
// - Настройки
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => MyHomePageState();
}

class MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;
  bool _minigameUnlocked = false;
  
  // Начальные экраны
  List<Widget> _screens = [
    const ScheduleScreen(),
    const CalendarScreen(),
    const SettingsScreen(),
  ];
  
  // Названия экранов в навигации
  List<String> _titles = [
    'Расписание',
    'Календарь',
    'Настройки',
  ];
  
  // Иконки для навигации
  List<NavigationDestination> _destinations = const [
    NavigationDestination(
      icon: Icon(Icons.schedule),
      label: 'Расписание',
    ),
    NavigationDestination(
      icon: Icon(Icons.calendar_month),
      label: 'Календарь',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings),
      label: 'Настройки',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _checkMinigameStatus();
  }
  
  // Проверяем статус разблокировки мини-игры при запуске
  Future<void> _checkMinigameStatus() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Проверяем все пасхалки и статус мини-игры
    final eggVersionFound = prefs.getBool('easter_egg_version_found') ?? false;
    final eggSearchFound = prefs.getBool('easter_egg_search_found') ?? false;
    final eggCalendarFound = prefs.getBool('easter_egg_calendar_found') ?? false;
    final minigameUnlocked = prefs.getBool('minigame_unlocked') ?? false;
    
    // Если все пасхалки найдены, но мини-игра не разблокирована, разблокируем ее
    if (eggVersionFound && eggSearchFound && eggCalendarFound && !minigameUnlocked) {
      await prefs.setBool('minigame_unlocked', true);
      setState(() {
        _minigameUnlocked = true;
        updateNavigation();
      });
    } 
    // Если мини-игра уже разблокирована, просто обновляем навигацию
    else if (minigameUnlocked && !_minigameUnlocked) {
      setState(() {
        _minigameUnlocked = true;
        updateNavigation();
      });
    }
  }
  
  // Публичный метод для проверки и обновления навигации из внешних виджетов
  Future<void> checkAndUpdateNavigation() async {
    await _checkMinigameStatus();
  }
  
  // Обновляем навигацию с учетом разблокированных функций
  void updateNavigation() {
    // Импортируем экран мини-игры уже добавлен вверху файла
    
    setState(() {
      if (_minigameUnlocked) {
        // Добавляем мини-игру в навигацию
        _screens = [
          const ScheduleScreen(),
          const CalendarScreen(),
          const MinigameScreen(), // Новый экран
          const SettingsScreen(),
        ];
        
        _titles = [
          'Расписание',
          'Календарь',
          'Мини-игра', // Новое название
          'Настройки',
        ];
        
        _destinations = [
          const NavigationDestination(
            icon: Icon(Icons.schedule),
            label: 'Расписание',
          ),
          const NavigationDestination(
            icon: Icon(Icons.calendar_month),
            label: 'Календарь',
          ),
          const NavigationDestination(
            icon: Icon(Icons.videogame_asset), // Новая иконка
            label: 'Мини-игра', // Новая надпись
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'Настройки',
          ),
        ];
      } else {
        // Стандартная навигация без мини-игры
        _screens = [
          const ScheduleScreen(),
          const CalendarScreen(),
          const SettingsScreen(),
        ];
        
        _titles = [
          'Расписание',
          'Календарь',
          'Настройки',
        ];
        
        _destinations = const [
          NavigationDestination(
            icon: Icon(Icons.schedule),
            label: 'Расписание',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month),
            label: 'Календарь',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'Настройки',
          ),
        ];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: _destinations,
      ),
    );
  }
} 