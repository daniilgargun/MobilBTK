/*
 * Copyright (c) 2024 Daniil Gargun. All rights reserved.
 * Author: Daniil Gargun | Telegram: @Daniilgargun | Email: daniilgorgun38@gmail.com
 */

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Отправка ошибок в Firebase Crashlytics.
///
/// Обёртка нужна по двум причинам. Во-первых, Crashlytics можно вызывать
/// только после удачной инициализации Firebase, а её может не быть: сборка
/// без `google-services.json`, отключённый проект, изолят фоновой задачи.
/// Во-вторых, отчётность не должна становиться источником новых падений —
/// поэтому здесь всё завёрнуто в try/catch.
class CrashReporter {
  const CrashReporter._();

  /// Включает сбор отчётов.
  ///
  /// В отладке сбор выключен: иначе каждая ошибка, которую разработчик и так
  /// видит в консоли, попадала бы в статистику и портила её.
  static Future<void> initialize() async {
    try {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        !kDebugMode,
      );
    } catch (e) {
      debugPrint('⚠️ Crashlytics недоступен: $e');
    }
  }

  /// Записывает ошибку.
  static void report(Object error, StackTrace? stack, {bool fatal = false}) {
    try {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: fatal);
    } catch (_) {
      // Отчётность не критична: приложение работает и без неё.
    }
  }

  /// Сообщает, что разбор страницы расписания не дал данных.
  ///
  /// Приложение живёт разбором чужого HTML — рано или поздно колледж поменяет
  /// вёрстку, и приложение молча перестанет обновляться. Без этой отметки
  /// узнать о поломке можно было бы только из жалоб пользователей; теперь она
  /// видна в консоли Firebase, и адрес или раскладку колонок можно поправить
  /// удалённым конфигом, не выпуская обновление.
  static void reportParseFailure(String reason) {
    try {
      final crashlytics = FirebaseCrashlytics.instance;
      crashlytics.setCustomKey('parse_failure_reason', reason);
      crashlytics.recordError(
        StateError('Разбор расписания не дал данных: $reason'),
        StackTrace.current,
        reason: 'schedule_parse_failed',
        fatal: false,
      );
    } catch (_) {
      // См. выше: без отчётности приложение работает.
    }
  }
}
