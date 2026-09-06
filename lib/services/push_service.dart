/*
 * Copyright (c) 2024 Daniil Gargun. All rights reserved.
 * Author: Daniil Gargun | Telegram: @Daniilgargun | Email: daniilgorgun38@gmail.com
 */

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;

import '../models/lesson_time_model.dart';
import 'connectivity_service.dart';
import 'crash_reporter.dart';
import 'lesson_reminder_service.dart';
import 'remote_config_service.dart';
import 'user_profile_service.dart';

/// Сообщения от сторожа страницы расписания (`server/`).
///
/// Уведомления об изменениях приложение строит само: качает страницу,
/// сравнивает с тем, что уже знает, фильтрует по профилю. Ломалось не это, а
/// момент запуска: Workmanager на оболочке Samsung усыпляют, и проверка
/// просто не выполнялась. Сообщение FCM с высоким приоритетом Doze пробивает.
///
/// Поэтому сервер не присылает ни расписания, ни текста уведомления — только
/// факт «страница изменилась». Разбор и сравнение остаются в приложении, в
/// единственном экземпляре, и вёрстку сайта не приходится чинить дважды.
///
/// Опрос по таймеру никуда не делся и остаётся запасным путём: сообщение
/// может не дойти (нет сервисов Google, приложение усыплено намертво,
/// сторож не развёрнут), и молчать в этом случае нельзя.
class PushService {
  static final PushService _instance = PushService._internal();
  factory PushService() => _instance;
  PushService._internal();

  /// Тема, в которую пишет сторож. Должна совпадать с `FCM_TOPIC`
  /// в `server/wrangler.toml`.
  static const String topic = 'schedule_all';

  static const String _subscribedKey = 'push_subscribed';
  static const String _lastHashKey = 'push_last_hash';

  /// Подписывает или отписывает устройство по состоянию удалённого конфига.
  ///
  /// Ничего не бросает наружу: вызывается при запуске, и приложение не имеет
  /// права не запуститься из-за недоступного FCM.
  Future<void> initialize() async {
    try {
      final enabled = RemoteConfigService().config.pushEnabled;
      final prefs = await SharedPreferences.getInstance();
      final subscribed = prefs.getBool(_subscribedKey) ?? false;

      if (enabled == subscribed) return;

      final messaging = FirebaseMessaging.instance;
      if (enabled) {
        await messaging.subscribeToTopic(topic);
      } else {
        await messaging.unsubscribeFromTopic(topic);
      }

      // Запоминаем, что уже сделано: подписка живёт на сервере FCM и
      // переживает перезапуск, а дёргать её на каждом старте — лишний
      // сетевой запрос на ровном месте.
      await prefs.setBool(_subscribedKey, enabled);
      debugPrint(
        enabled ? '📡 Подписка на «$topic»' : '📡 Отписка от «$topic»',
      );
    } catch (e) {
      debugPrint('⚠️ Подписка на сообщения не удалась: $e');
    }
  }

  /// Обрабатывает сообщение сторожа: и в фоне, и на переднем плане.
  ///
  /// Возвращает false, если синхронизация не запускалась.
  static Future<bool> handleMessage(Map<String, String> data) async {
    if (data['type'] != 'schedule_changed') return false;

    // FCM обещает доставку хотя бы раз, а не ровно один раз: то же сообщение
    // может прийти повторно. Хэш страницы отсекает повтор, иначе телефон
    // качал и разбирал бы 67 КБ разметки на каждую копию.
    final hash = data['page_hash'];
    final prefs = await SharedPreferences.getInstance();
    if (hash != null && hash.isNotEmpty) {
      if (prefs.getString(_lastHashKey) == hash) {
        debugPrint('📭 Сообщение про уже обработанную страницу, пропускаем');
        return false;
      }
      await prefs.setString(_lastHashKey, hash);
    }

    await ConnectivityService.performPushSync();
    return true;
  }
}

/// Точка входа фонового изолята FCM.
///
/// Помечена `vm:entry-point`, иначе её вырежет компилятор: из Dart её никто
/// не вызывает, зову́т снаружи. Изолят поднимается с нуля — ни Firebase, ни
/// временных зон, ни состояния приложения в нём нет, поэтому всё нужное
/// поднимается заново, ровно как в `callbackDispatcher`.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    // Тот же набор, что поднимает `callbackDispatcher`: изолят создаётся с
    // нуля, и без него не работают ни планировщик напоминаний (временны́е
    // зоны), ни форматирование дат в тексте уведомления.
    WidgetsFlutterBinding.ensureInitialized();
    tz.initializeTimeZones();
    await initializeDateFormatting('ru_RU', null);
    await Firebase.initializeApp();

    final config = await RemoteConfigService().load();
    LessonTime.applyRemoteOverride(config.bellScheduleJson);
    await UserProfileService().load();
    await LessonReminderService().load();

    await PushService.handleMessage(message.data.cast<String, String>());
  } catch (e, stack) {
    debugPrint('❌ Ошибка обработки сообщения в фоне: $e');
    CrashReporter.report(e, stack);
  }
}
