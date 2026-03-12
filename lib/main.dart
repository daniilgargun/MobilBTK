/*
 * БТК Расписание - Мобильное приложение для просмотра расписания
 *
 * Copyright (c) 2024 Daniil Gargun. All rights reserved.
 * Авторские права (c) 2024 Данил Гаргун. Все права защищены.
 *
 * Автор: Данил Гаргун
 * Telegram: @Daniilgargun (https://t.me/Daniilgargun)
 * Email: daniilgorgun38@gmail.com
 * Phone: +375299545338
 *
 * Данное программное обеспечение является проприетарным и защищено
 * законами об авторском праве. Использование без разрешения запрещено.
 *
 * This software is proprietary and protected by copyright laws.
 * Unauthorized use is prohibited.
 */

import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'providers/notes_provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/personalization_provider.dart';
import 'screens/calendar_screen.dart';
import 'screens/schedule_screen.dart';
import 'screens/settings_screen.dart';

import 'screens/widget_settings_screen.dart';
import 'services/ads_service.dart';
import 'services/connectivity_service.dart';
import 'services/database_service.dart';
import 'services/notification_service.dart';
import 'themes/theme_presets.dart';
import 'package:workmanager/workmanager.dart';
import 'package:upgrader/upgrader.dart';
import 'services/home_widget_service.dart';

void main() {
  // Используем runZonedGuarded для перехвата всех необработанных ошибок
  runZonedGuarded(() async {
    // Убедимся, что все биндинги Flutter инициализированы
    WidgetsFlutterBinding.ensureInitialized();

    // Инициализация Firebase
    await Firebase.initializeApp();

    // Настраиваем отображение от края до края (Edge-to-Edge)
    // Это позволяет приложению рисовать под системными панелями
    if (!kIsWeb && Platform.isAndroid) {
      try {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        // ИСПРАВЛЕНИЕ: Удалена первоначальная жесткая настройка цвета иконок.
        // Теперь стиль будет применен в MyHomePage в зависимости от темы,
        // что предотвращает "моргание" и невидимые иконки при запуске.
      } catch (e) {
        debugPrint('Ошибка настройки системного UI (edge-to-edge): $e');
      }
    }

    // Глобальный обработчик ошибок Flutter
    FlutterError.onError = (FlutterErrorDetails details) {
      // Игнорируем специфическую ошибку OpenGL, которая не является критической
      if (!details.toString().contains('OpenGL ES API')) {
        debugPrint('Перехвачена ошибка Flutter: ${details.exception}');
        FlutterError.presentError(details);
      }
    };

    // Инициализируем временные зоны для работы с датами и уведомлениями
    tz.initializeTimeZones();

    // Устанавливаем русскую локаль для форматирования дат
    await initializeDateFormatting('ru_RU', null);

    // Инициализация сервиса проверки подключения к сети
    final connectivityService = ConnectivityService();
    await connectivityService.init();

    // Инициализация виджета
    // await HomeWidgetService.initialize();
    await HomeWidgetService.updateBellScheduleData();

    // Инициализация сервиса уведомлений
    await NotificationService().initialize();

    // Инициализация базы данных
    await DatabaseService().database;

    // Создаем и загружаем данные для провайдеров
    final scheduleProvider = ScheduleProvider();
    final notesProvider = NotesProvider();
    final personalizationProvider = PersonalizationProvider();

    // Устанавливаем провайдер в ConnectivityService для фоновых задач
    connectivityService.setScheduleProvider(scheduleProvider);

    // Инициализация workmanager для периодических обновлений
    // Синхронизация при восстановлении связи работает через ConnectivityService
    try {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: kDebugMode,
      );

      // Регистрируем периодическую задачу обновления расписания
      // Обновление каждый час, но только в рабочее время (7-19, кроме воскресенья)
      // Проверка времени выполняется внутри задачи
      await Workmanager().registerPeriodicTask(
        'schedule-sync',
        'syncSchedule',
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );
    } catch (e) {
      debugPrint('Ошибка инициализации Workmanager: $e');
    }

    // Запускаем инициализацию рекламы с задержкой, чтобы не блокировать старт
    if (!kIsWeb) {
      Future.delayed(const Duration(seconds: 3), () {
        AdsService().initialize().catchError((e, stackTrace) {
          // РЕКОМЕНДАЦИЯ: Для релизных версий здесь стоит использовать
          // сервис для сбора ошибок, например, Firebase Crashlytics или Sentry.
          debugPrint('------ ОШИБКА ИНИЦИАЛИЗАЦИИ РЕКЛАМЫ ------');
          debugPrint('Ошибка: $e');
          debugPrint('Стек: $stackTrace');
          debugPrint('------------------------------------------');
        });
      });
    }

    // Запускаем приложение
    runApp(
      MultiProvider(
        providers: [
          // Используем .value для существующих экземпляров провайдеров
          ChangeNotifierProvider.value(value: scheduleProvider),
          ChangeNotifierProvider.value(value: notesProvider),
          ChangeNotifierProvider.value(value: personalizationProvider),
        ],
        child: MyApp(key: myAppKey),
      ),
    );
  }, (error, stack) {
    // Логируем ошибки, которые не были пойманы Flutter
    debugPrint('Неперехваченная ошибка в ZonedGuarded: $error');
    debugPrint('Стек: $stack');
  });
}

// Обработчик фоновых задач для workmanager
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('🔄 Выполнение фоновой задачи: $task');

    try {
      if (task == 'syncSchedule') {
        // Инициализируем необходимые сервисы для фоновой задачи
        WidgetsFlutterBinding.ensureInitialized();
        tz.initializeTimeZones();
        await initializeDateFormatting('ru_RU', null);

        await ConnectivityService.performPeriodicSync();
        return Future.value(true);
      }
      return Future.value(false);
    } catch (e) {
      debugPrint('❌ Ошибка выполнения фоновой задачи: $e');
      return Future.value(false);
    }
  });
}

// Глобальный ключ для доступа к состоянию MyApp из других виджетов
final GlobalKey<MyAppState> myAppKey = GlobalKey<MyAppState>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Главный виджет приложения
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool? _isDarkMode;
  bool _useDynamicColors = false;
  bool _isWidgetConfiguration = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadThemeSettings();
    _checkWidgetConfiguration();
    _checkWidgetSettingsAction();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkWidgetSettingsAction();
    }
  }

  Future<void> _checkWidgetSettingsAction() async {
    try {
      const platform = MethodChannel('com.gargun.btktimetable/widget');
      final bool? shouldOpenSettings =
          await platform.invokeMethod('checkWidgetSettingsAction');
      if (shouldOpenSettings == true) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (context) => const WidgetSettingsScreen(),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error checking widget settings action: $e');
    }
  }

  Future<void> _checkWidgetConfiguration() async {
    try {
      const platform = MethodChannel('com.gargun.btktimetable/widget');
      final int? appWidgetId = await platform.invokeMethod('getAppWidgetId');
      if (appWidgetId != null && appWidgetId != 0) {
        setState(() {
          _isWidgetConfiguration = true;
        });
      }
    } catch (e) {
      debugPrint('Error checking widget configuration: $e');
    }
  }

  // Загружаем настройки темы из SharedPreferences
  Future<void> _loadThemeSettings() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    final savedTheme = prefs.getBool('is_dark_mode');
    final useDynamicColors = prefs.getBool('use_dynamic_colors') ?? false;

    bool isDarkMode;
    if (savedTheme == null) {
      // Если тема не сохранена, используем системную
      final brightness = View.of(context).platformDispatcher.platformBrightness;
      isDarkMode = brightness == Brightness.dark;
      await prefs.setBool('is_dark_mode', isDarkMode);
    } else {
      isDarkMode = savedTheme;
    }

    setState(() {
      _isDarkMode = isDarkMode;
      _useDynamicColors = useDynamicColors;
    });
  }

  // Метод для обновления темы из настроек
  void updateTheme(bool isDarkMode) {
    setState(() {
      _isDarkMode = isDarkMode;
    });
    // Сохраняем новое значение темы
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('is_dark_mode', isDarkMode);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Показываем индикатор загрузки, пока тема не определена
    if (_isDarkMode == null) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    // Поддержка динамических цветов (Material You)
    return Consumer<PersonalizationProvider>(
      builder: (context, personalizationProvider, _) {
        return DynamicColorBuilder(
            builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
          final settings = personalizationProvider.settings;
          ColorScheme lightColorScheme;
          ColorScheme darkColorScheme;

          if (_useDynamicColors &&
              lightDynamic != null &&
              darkDynamic != null) {
            // Если динамические цвета включены и доступны, используем их
            lightColorScheme = lightDynamic;
            darkColorScheme = darkDynamic;
          } else {
            // Используем настройки персонализации или стандартную схему
            final seedColor = ThemePresets.getColor(settings.themePreset) ??
                settings.seedColor;
            lightColorScheme = ColorScheme.fromSeed(
              seedColor: seedColor,
              brightness: Brightness.light,
            );
            darkColorScheme = ColorScheme.fromSeed(
              seedColor: seedColor,
              brightness: Brightness.dark,
            );
          }

          return MaterialApp(
            navigatorKey: navigatorKey,
            title: 'Мобильное приложение',
            theme: ThemeData(
              colorScheme: lightColorScheme,
              useMaterial3: true,
              pageTransitionsTheme: const PageTransitionsTheme(
                builders: {
                  TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
                  TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                  TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
                  TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
                  TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
                },
              ),
            ),
            darkTheme: ThemeData(
              colorScheme: darkColorScheme,
              useMaterial3: true,
              pageTransitionsTheme: const PageTransitionsTheme(
                builders: {
                  TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
                  TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                  TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
                  TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
                  TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
                },
              ),
            ),
            themeMode: _isDarkMode! ? ThemeMode.dark : ThemeMode.light,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('ru', 'RU'),
            ],
            home: _isWidgetConfiguration
                ? const WidgetSettingsScreen(isConfiguration: true)
                : const MyHomePage(),
          );
        });
      },
    );
  }
}

// Главный экран с нижней навигационной панелью
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => MyHomePageState();
}

class MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;

  late List<Widget> _screens;
  late List<NavigationDestination> _destinations;

  @override
  void initState() {
    super.initState();
    // Сразу обновляем навигацию на основе текущего состояния
    _updateNavigationItems();

    // Загружаем данные после построения UI, чтобы избежать зависания при запуске
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final scheduleProvider =
        Provider.of<ScheduleProvider>(context, listen: false);
    final notesProvider = Provider.of<NotesProvider>(context, listen: false);

    await scheduleProvider.loadSchedule();
    await notesProvider.loadNotes();
  }

  // Централизованный метод для обновления списка экранов и пунктов навигации
  void _updateNavigationItems() {
    _screens = const [
      ScheduleScreen(),
      CalendarScreen(),
      SettingsScreen(),
    ];
    _destinations = const [
      NavigationDestination(icon: Icon(Icons.schedule), label: 'Расписание'),
      NavigationDestination(
          icon: Icon(Icons.calendar_month), label: 'Календарь'),
      NavigationDestination(icon: Icon(Icons.settings), label: 'Настройки'),
    ];

    // Если текущий индекс стал невалидным (например, после скрытия мини-игры),
    // сбрасываем на первый экран.
    if (_selectedIndex >= _screens.length) {
      _selectedIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Применяем правильный стиль для системных иконок в зависимости от темы
    final Brightness platformBrightness =
        Theme.of(context).brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarIconBrightness: platformBrightness,
      systemNavigationBarIconBrightness: platformBrightness,
    ));

    return Theme(
      data: Theme.of(context).copyWith(
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          titleTextStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
          contentTextStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
      child: UpgradeAlert(
        upgrader: Upgrader(
          languageCode: 'ru',
          countryCode: 'RU',
          durationUntilAlertAgain: Duration.zero,
          debugLogging: kDebugMode,
        ),
        showReleaseNotes: true,
        showIgnore: false,
        showLater: true,
        child: Scaffold(
          body: IndexedStack(
            index: _selectedIndex,
            children: _screens,
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            animationDuration: const Duration(milliseconds: 200),
            onDestinationSelected: (index) {
              // Haptic feedback на Android
              if (Theme.of(context).platform == TargetPlatform.android) {
                HapticFeedback.selectionClick();
              }
              setState(() {
                _selectedIndex = index;
              });
            },
            destinations: _destinations,
          ),
        ),
      ),
    );
  }
}
