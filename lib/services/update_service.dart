/*
 * Copyright (c) 2024 Daniil Gargun. All rights reserved.
 * Author: Daniil Gargun | Telegram: @Daniilgargun | Email: daniilgorgun38@gmail.com
 */

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'remote_config_service.dart';

/// Что делать с найденным обновлением.
enum UpdateUrgency {
  /// Обновление есть, но работать можно и на текущей версии.
  optional,

  /// Текущая версия ниже минимально поддерживаемой: без обновления
  /// приложение, скорее всего, показывает неверные данные.
  required,
}

/// Найденное обновление.
@immutable
class AvailableUpdate {
  final String version;
  final String notes;
  final UpdateUrgency urgency;

  const AvailableUpdate({
    required this.version,
    required this.notes,
    required this.urgency,
  });
}

/// Проверка обновлений через удалённый конфиг.
///
/// Раньше этим занимался пакет `upgrader`, который разбирал HTML страницы
/// приложения в Google Play. Google убрал со страницы поле с версией, и
/// разбор стал вытаскивать вместо неё категорию приложения — в логе это
/// видно как `invalid version format "Образование"`. Версия не
/// определялась, значит `isUpdateAvailable` всегда был false и предложение
/// обновиться не показывалось никогда.
///
/// Разбор чужого HTML — ровно та же хрупкость, из-за которой в приложении
/// уже есть удалённый конфиг. Поэтому версия просто объявляется в конфиге:
/// один параметр вместо страницы, которую Google волен переверстать.
class UpdateService {
  static const String _storeId = 'com.gargun.btktimetable';

  /// Версия, для которой пользователь уже нажал «Позже».
  static const String _postponedKey = 'update_postponed_version';

  const UpdateService._();

  /// Проверяет, есть ли версия новее установленной.
  ///
  /// Возвращает null, если обновления нет, если конфиг молчит или если
  /// пользователь уже отложил ровно эту версию. Отложенное обновление
  /// всё равно показывается, когда оно обязательное.
  static Future<AvailableUpdate?> check() async {
    final config = RemoteConfigService().config;
    final latest = config.latestVersion;
    if (latest.isEmpty) return null;

    final String current;
    try {
      current = (await PackageInfo.fromPlatform()).version;
    } catch (e) {
      debugPrint('⚠️ Не удалось определить версию приложения: $e');
      return null;
    }

    final isRequired =
        config.minSupportedVersion.isNotEmpty &&
        compareVersions(current, config.minSupportedVersion) < 0;

    if (!isRequired && compareVersions(current, latest) >= 0) return null;

    if (!isRequired) {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_postponedKey) == latest) return null;
    }

    return AvailableUpdate(
      version: latest,
      notes: config.updateNotes,
      urgency: isRequired ? UpdateUrgency.required : UpdateUrgency.optional,
    );
  }

  /// Запоминает, что пользователь отложил обновление до следующей версии.
  static Future<void> postpone(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_postponedKey, version);
  }

  /// Открывает страницу приложения в Google Play.
  ///
  /// Сначала пробуем схему `market://` — она ведёт прямо в приложение Play.
  /// Если Play не установлен (эмулятор, прошивка без сервисов Google),
  /// открываем ту же страницу в браузере.
  static Future<bool> openStore() async {
    final candidates = <Uri>[
      Uri.parse('market://details?id=$_storeId'),
      Uri.parse('https://play.google.com/store/apps/details?id=$_storeId'),
    ];

    for (final uri in candidates) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (e) {
        debugPrint('⚠️ Не удалось открыть $uri: $e');
      }
    }
    return false;
  }

  /// Сравнивает версии вида `1.0.13`.
  ///
  /// Отрицательное — `a` старее `b`, ноль — равны, положительное — новее.
  /// Разная длина допустима: `1.1` считается равной `1.1.0`. Всё, что не
  /// разбирается в число, считается нулём — испорченное значение в конфиге
  /// не должно приводить к вечному показу диалога.
  @visibleForTesting
  static int compareVersions(String a, String b) {
    final left = _parts(a);
    final right = _parts(b);
    final length = left.length > right.length ? left.length : right.length;

    for (var i = 0; i < length; i++) {
      final x = i < left.length ? left[i] : 0;
      final y = i < right.length ? right[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  static List<int> _parts(String version) {
    // Отбрасываем суффикс сборки: "1.0.13+17" и "1.0.13" — одна версия.
    final trimmed = version.trim().split('+').first;
    return trimmed
        .split('.')
        .map((part) => int.tryParse(part.trim()) ?? 0)
        .toList();
  }
}
