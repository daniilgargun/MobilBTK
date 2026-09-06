/*
 * Copyright (c) 2024 Daniil Gargun. All rights reserved.
 * Author: Daniil Gargun | Telegram: @Daniilgargun | Email: daniilgorgun38@gmail.com
 */

import 'package:flutter/foundation.dart';

/// Что попадает в logcat из release-сборки, а что нет.
///
/// Правило одно: рутинные логи в release молчат, сообщения об ошибках —
/// никогда. Живёт это отдельным файлом, потому что применять правило надо в
/// каждой точке входа, а их три и они в разных местах: `main()`,
/// `callbackDispatcher` (Workmanager) и `firebaseMessagingBackgroundHandler`
/// (сообщения сторожа).

/// Заглушает рутинное логирование в release-сборке.
///
/// Вызывать **в каждой точке входа**, а не только в `main()`.
///
/// Фоновые задачи выполняются в отдельных изолятах со своими точками входа,
/// и `main()` в них не выполняется вовсе. Пока заглушка стояла только там,
/// фоновая синхронизация — то есть ровно тот код, через который проходят
/// расписание и профиль пользователя, — продолжала писать в logcat из
/// release-сборки. Проверено на устройстве: строка «Начинаем фоновую
/// синхронизацию» была видна в логе неотлаживаемой сборки.
void silenceRoutineLogsInRelease() {
  if (!kReleaseMode) return;
  debugPrint = (String? message, {int? wrapWidth}) {};
}

/// Печатает ошибку в обход заглушённого `debugPrint`.
///
/// `debugPrintSynchronously` — отдельная функция, а не заменённая переменная,
/// поэтому [silenceRoutineLogsInRelease] её не касается. Иначе падение при
/// запуске выглядит как молчащий чёрный экран без единой строки в logcat, а
/// найти причину без логов невозможно.
///
/// `developer.log` тут не годится: в AOT-сборке он до logcat не доходит.
void logError(String message, Object error, StackTrace? stack) {
  debugPrintSynchronously('❌ $message: $error');
  if (stack != null) debugPrintSynchronously(stack.toString());
}
