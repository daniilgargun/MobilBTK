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
import 'package:firebase_messaging/firebase_messaging.dart';

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
import 'services/crash_reporter.dart';
import 'services/database_service.dart';
import 'services/notification_service.dart';
import 'services/push_service.dart';
import 'services/remote_config_service.dart';
import 'services/lesson_reminder_service.dart';
import 'services/update_service.dart';
import 'services/user_profile_service.dart';
import 'models/lesson_time_model.dart';
import 'themes/theme_presets.dart';

import 'package:workmanager/workmanager.dart';

import 'services/home_widget_service.dart';

/// Один шаг инициализации, который не имеет права не пустить приложение.
///
/// Раньше вокруг этой последовательности не было ни одного `try`: осечка
/// любого плагина уходила в обработчик зоны, `runApp` не вызывался — и
/// пользователь видел чёрный экран. Именно так и случилось, когда
/// сокращатель ресурсов вырезал иконку уведомлений: плагин ответил ошибкой
/// «неизвестный ресурс», и приложение перестало запускаться целиком
/// из-за функции, без которой прекрасно живёт.
Future<void> _step(String name, Future<void> Function() body) async {
  try {
    await body();
  } catch (e, stack) {
    _logError('Шаг запуска «$name» не выполнен', e, stack);
    CrashReporter.report(e, stack);
  }
}

/// Печатает ошибку в обход заглушённого `debugPrint`.
///
/// В release `debugPrint` заменяется пустой функцией, чтобы рутинные логи не
/// оседали в logcat. Сообщения об ошибках исчезали вместе с ними, поэтому
/// падение при запуске выглядело как молчащий чёрный экран.
/// `developer.log` тут не подходит: в AOT-сборке он до logcat не доходит.
void _logError(String message, Object error, StackTrace? stack) {
  debugPrintSynchronously('❌ $message: $error');
  if (stack != null) debugPrintSynchronously(stack.toString());
}

void main() {
  // Сотня точек логирования писала в logcat, где их мог прочитать кто угодно.
  // Ошибки это не глушит: они идут через [_logError] мимо `debugPrint`.
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // Используем runZonedGuarded для перехвата всех необработанных ошибок
  runZonedGuarded(
    () async {
      // Убедимся, что все биндинги Flutter инициализированы
      WidgetsFlutterBinding.ensureInitialized();

      // Инициализация Firebase. Без google-services.json (например, в CI)
      // вызов падает — приложение должно продолжать работать и без него.
      var firebaseReady = false;
      try {
        await Firebase.initializeApp();
        firebaseReady = true;
      } catch (e) {
        debugPrint('⚠️ Firebase недоступен: $e');
      }

      if (firebaseReady) {
        await CrashReporter.initialize();
      }

      // Настройки, которые можно поменять без выпуска новой версии:
      // адрес страницы расписания, раскладка колонок в её таблице,
      // расписание звонков, выключатель рекламы, объявление.
      final remoteConfig = RemoteConfigService();
      await remoteConfig.load();
      LessonTime.applyRemoteOverride(remoteConfig.config.bellScheduleJson);

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
        if (details.toString().contains('OpenGL ES API')) return;

        _logError(
          'Перехвачена ошибка Flutter',
          details.exception,
          details.stack,
        );
        FlutterError.presentError(details);
        CrashReporter.report(details.exception, details.stack, fatal: true);
      };

      // Ошибки, до которых Flutter не дотягивается: колбэки платформы и
      // необработанные Future вне зоны runZonedGuarded.
      PlatformDispatcher.instance.onError = (error, stack) {
        _logError('Необработанная ошибка платформы', error, stack);
        CrashReporter.report(error, stack, fatal: true);
        return true;
      };

      // Инициализируем временные зоны для работы с датами и уведомлениями
      tz.initializeTimeZones();

      // Устанавливаем русскую локаль для форматирования дат
      await _step('локаль', () => initializeDateFormatting('ru_RU', null));

      // Инициализация сервиса проверки подключения к сети
      final connectivityService = ConnectivityService();
      await _step('связь', connectivityService.init);

      // Инициализация виджета
      await _step('виджет звонков', HomeWidgetService.updateBellScheduleData);

      // Инициализация сервиса уведомлений
      await _step('уведомления', NotificationService().initialize);

      // Сообщения сторожа страницы расписания.
      //
      // Обработчик фонового изолята регистрируется до runApp: сообщение может
      // прийти, когда приложение не запущено, и тогда точка входа должна уже
      // быть объявлена. Сама подписка — сетевой вызов, поэтому в фоне: старт
      // приложения её не ждёт.
      if (firebaseReady) {
        await _step('сообщения сторожа', () async {
          FirebaseMessaging.onBackgroundMessage(
            firebaseMessagingBackgroundHandler,
          );
          FirebaseMessaging.onMessage.listen((message) {
            PushService.handleMessage(message.data.cast<String, String>());
          });
        });
        unawaited(PushService().initialize());
      }

      // Профиль (своя группа или своя фамилия) и напоминания о парах.
      // Профиль нужен раньше расписания: по нему фильтруются уведомления.
      await _step('профиль', () async {
        await UserProfileService().load();
        await LessonReminderService().load();
        await LessonReminderService().createChannel();
      });

      // Инициализация базы данных
      await _step('база данных', () => DatabaseService().database);

      // Создаем и загружаем данные для провайдеров
      final scheduleProvider = ScheduleProvider();
      final notesProvider = NotesProvider();
      final personalizationProvider = PersonalizationProvider();

      // Устанавливаем провайдер в ConnectivityService для фоновых задач
      connectivityService.setScheduleProvider(scheduleProvider);

      // Инициализация workmanager для периодических обновлений
      // Синхронизация при восстановлении связи работает через ConnectivityService
      try {
        await Workmanager().initialize(callbackDispatcher);

        // Регистрируем периодическую задачу обновления расписания
        // Обновление каждый час, но только в рабочее время (7-19, кроме воскресенья)
        // Проверка времени выполняется внутри задачи
        await Workmanager().registerPeriodicTask(
          'schedule-sync',
          'syncSchedule',
          frequency: const Duration(minutes: 15),
          constraints: Constraints(networkType: NetworkType.connected),
          // Не пересоздаём уже запланированную задачу на каждом запуске
          // приложения — иначе отсчёт периода начинается заново и
          // фоновая синхронизация может не сработать ни разу.
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        );
      } catch (e) {
        debugPrint('Ошибка инициализации Workmanager: $e');
      }

      // Свежий конфиг тянем в фоне: старт приложения не должен ждать сеть.
      if (firebaseReady) {
        unawaited(
          remoteConfig.refresh().then((_) {
            LessonTime.applyRemoteOverride(
              remoteConfig.config.bellScheduleJson,
            );
            // Виджеты на рабочем столе получают время уже посчитанным,
            // поэтому после смены сетки звонков их надо перерисовать.
            return HomeWidgetService.updateBellScheduleData();
          }),
        );
      }

      // Запускаем инициализацию рекламы с задержкой, чтобы не блокировать старт
      Future.delayed(const Duration(seconds: 3), () {
        AdsService().initialize().catchError((e, stackTrace) {
          debugPrint('❌ Ошибка инициализации рекламы: $e');
          CrashReporter.report(e, stackTrace);
        });
      });

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
    },
    (error, stack) {
      // Логируем ошибки, которые не были пойманы Flutter
      _logError('Неперехваченная ошибка зоны', error, stack);
      CrashReporter.report(error, stack, fatal: true);
    },
  );
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

        // Фоновая задача живёт в отдельном изоляте: статика главного
        // изолята сюда не попадает, поэтому конфиг читаем заново.
        // Firebase здесь не поднимаем — значения уже сохранены в
        // SharedPreferences при последнем обновлении из приложения.
        final config = await RemoteConfigService().load();
        LessonTime.applyRemoteOverride(config.bellScheduleJson);
        await UserProfileService().load();
        await LessonReminderService().load();

        await ConnectivityService.performPeriodicSync();
        return true;
      }
      return false;
    } catch (e, stack) {
      debugPrint('❌ Ошибка выполнения фоновой задачи: $e');
      CrashReporter.report(e, stack);
      return false;
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

    // Разрешение спрашиваем, когда интерфейс уже нарисован. Системный
    // диалог, показанный до первого кадра, висит поверх пустого экрана и
    // от зависшего запуска неотличим.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().requestPermission();
    });
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
      final bool? shouldOpenSettings = await platform.invokeMethod(
        'checkWidgetSettingsAction',
      );
      if (shouldOpenSettings == true) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (context) => const WidgetSettingsScreen()),
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
      if (!mounted) return;

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

    if (!mounted) return;

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
              final seedColor =
                  ThemePresets.getColor(settings.themePreset) ??
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
                  },
                ),
              ),
              darkTheme: ThemeData(
                colorScheme: darkColorScheme,
                useMaterial3: true,
                pageTransitionsTheme: const PageTransitionsTheme(
                  builders: {
                    TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
                  },
                ),
              ),
              themeMode: _isDarkMode! ? ThemeMode.dark : ThemeMode.light,
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('ru', 'RU')],
              home: _isWidgetConfiguration
                  ? const WidgetSettingsScreen(isConfiguration: true)
                  : const MyHomePage(),
            );
          },
        );
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
    final scheduleProvider = Provider.of<ScheduleProvider>(
      context,
      listen: false,
    );
    final notesProvider = Provider.of<NotesProvider>(context, listen: false);

    await scheduleProvider.loadSchedule();
    await notesProvider.loadNotes();

    // Напоминания переставляем и при обычном запуске: расписание могло
    // обновиться фоновой задачей, пока приложение было закрыто.
    unawaited(
      LessonReminderService().reschedule(scheduleProvider.scheduleData),
    );

    // Конфиг обновляется в фоне, поэтому проверку версии делаем после
    // загрузки расписания — к этому моменту свежие значения уже пришли.
    if (mounted) {
      unawaited(_checkForUpdate());
    }
  }

  // Централизованный метод для обновления списка экранов и пунктов навигации
  void _updateNavigationItems() {
    _screens = const [ScheduleScreen(), CalendarScreen(), SettingsScreen()];
    _destinations = const [
      NavigationDestination(icon: Icon(Icons.schedule), label: 'Расписание'),
      NavigationDestination(
        icon: Icon(Icons.calendar_month),
        label: 'Календарь',
      ),
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
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarIconBrightness: platformBrightness,
        systemNavigationBarIconBrightness: platformBrightness,
      ),
    );

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
          contentTextStyle: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
      child: Scaffold(
        body: IndexedStack(index: _selectedIndex, children: _screens),
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
    );
  }

  /// Показывает предложение обновиться, если в конфиге объявлена версия
  /// новее установленной.
  ///
  /// Проверка отложена и не блокирует запуск: свежий конфиг приходит уже
  /// после того, как приложение показало расписание.
  Future<void> _checkForUpdate() async {
    final update = await UpdateService.check();
    if (update == null || !mounted) return;

    final isRequired = update.urgency == UpdateUrgency.required;

    final action = await showDialog<String>(
      context: context,
      // Обязательное обновление не закрыть мимо кнопок: на старой версии
      // приложение показывает неверные данные, а не просто устаревший вид.
      barrierDismissible: !isRequired,
      builder: (context) => PopScope(
        canPop: !isRequired,
        child: AlertDialog(
          icon: const Icon(Icons.system_update),
          title: Text(isRequired ? 'Нужно обновиться' : 'Доступно обновление'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Версия ${update.version} уже в Google Play.'),
              if (update.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(update.notes),
              ],
              if (isRequired) ...[
                const SizedBox(height: 12),
                const Text(
                  'Текущая версия больше не может правильно читать '
                  'расписание с сайта колледжа.',
                ),
              ],
            ],
          ),
          actions: [
            if (!isRequired)
              TextButton(
                onPressed: () => Navigator.pop(context, 'later'),
                child: const Text('Позже'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'update'),
              child: const Text('Обновить'),
            ),
          ],
        ),
      ),
    );

    if (action == 'update') {
      final opened = await UpdateService.openStore();
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть Google Play')),
        );
      }
      return;
    }

    // Закрытие мимо кнопок тоже считаем «позже»: иначе диалог всплывал бы
    // при каждом переключении вкладок.
    if (!isRequired) {
      await UpdateService.postpone(update.version);
    }
  }
}
