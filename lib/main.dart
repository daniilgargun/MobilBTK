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

void main() async {
  // Инициализируем всякие важные штуки
  WidgetsFlutterBinding.ensureInitialized();
  
  // Убираем надоедливые сообщения про OpenGL
  FlutterError.onError = (FlutterErrorDetails details) {
    if (!details.toString().contains('OpenGL ES API')) {
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

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => scheduleProvider),
        ChangeNotifierProvider(create: (_) => notesProvider),
      ],
      child: const MyApp(),
    ),
  );
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
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;
  
  final List<Widget> _screens = [
    const ScheduleScreen(),
    const CalendarScreen(),
    const SettingsScreen(),
  ];
  
  final List<String> _titles = [
    'Расписание',
    'Календарь',
    'Настройки',
  ];

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
        destinations: const [
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
        ],
      ),
    );
  }
}
