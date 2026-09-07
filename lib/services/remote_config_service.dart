/*
 * Copyright (c) 2024 Daniil Gargun. All rights reserved.
 * Author: Daniil Gargun | Telegram: @Daniilgargun | Email: daniilgorgun38@gmail.com
 */

import 'dart:convert';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Номера колонок в таблице расписания на сайте колледжа.
///
/// Вынесены в конфиг, потому что это самое хрупкое место приложения:
/// API у колледжа нет, всё держится на разборе HTML. Если в таблицу добавят
/// колонку, все поля съедут на одну позицию, и приложение начнёт показывать
/// преподавателя в графе предмета. Раньше единственным лекарством был
/// выпуск новой версии.
@immutable
class ParserColumns {
  final int date;
  final int group;
  final int number;
  final int subject;
  final int teacher;
  final int classroom;
  final int subgroup;

  const ParserColumns({
    this.date = 0,
    this.group = 1,
    this.number = 2,
    this.subject = 3,
    this.teacher = 4,
    this.classroom = 5,
    this.subgroup = 6,
  });

  static const ParserColumns defaults = ParserColumns();

  /// Сколько колонок должно быть в строке, чтобы её имело смысл разбирать.
  int get requiredCount {
    var max = 0;
    for (final index in [date, group, number, subject, teacher, classroom]) {
      if (index > max) max = index;
    }
    return max + 1;
  }

  /// Разбирает JSON вида `{"date":0,"group":1,...}`.
  ///
  /// Любое отсутствующее или неверное поле берётся из значений по умолчанию:
  /// испорченный конфиг не должен ломать разбор целиком.
  factory ParserColumns.fromJson(String source) {
    if (source.trim().isEmpty) return defaults;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return defaults;

      int pick(String key, int fallback) {
        final value = decoded[key];
        return value is int && value >= 0 && value < 64 ? value : fallback;
      }

      return ParserColumns(
        date: pick('date', defaults.date),
        group: pick('group', defaults.group),
        number: pick('number', defaults.number),
        subject: pick('subject', defaults.subject),
        teacher: pick('teacher', defaults.teacher),
        classroom: pick('classroom', defaults.classroom),
        subgroup: pick('subgroup', defaults.subgroup),
      );
    } catch (_) {
      return defaults;
    }
  }
}

/// Объявление разработчика, которое можно показать всем пользователям
/// без выпуска новой версии.
@immutable
class Announcement {
  /// Меняется вместе с текстом: по нему запоминается «уже прочитано».
  final String id;
  final String text;

  /// Необязательная ссылка «Подробнее».
  final String url;

  const Announcement({this.id = '', this.text = '', this.url = ''});

  bool get isEmpty => id.isEmpty || text.isEmpty;
}

/// Значения, которые приложение читает при запуске и может получить с сервера.
///
/// У всех полей есть рабочие значения, вшитые в код: без сети, без Firebase
/// и без единого успешного обновления конфига приложение работает ровно так
/// же, как раньше.
@immutable
class AppConfig {
  final String scheduleUrl;
  final ParserColumns columns;

  /// Расписание звонков в JSON. Пусто — используется вшитое в приложение.
  final String bellScheduleJson;

  /// Выключатель рекламы: нужен, если рекламная сеть перестанет работать
  /// или изменит условия.
  final bool adsEnabled;

  final Announcement announcement;

  /// Последняя версия в Google Play, например `1.0.14`. Пусто — не проверять.
  ///
  /// Объявляется здесь, а не вычитывается со страницы Play: Google убрал
  /// оттуда поле версии, и разбор страницы (пакет `upgrader`) перестал
  /// работать — см. [UpdateService].
  final String latestVersion;

  /// Версия, ниже которой приложение просит обновиться настойчиво.
  final String minSupportedVersion;

  /// Что нового — текст в диалоге обновления.
  final String updateNotes;

  /// Подписываться ли на сообщения сторожа страницы (`PushService`).
  ///
  /// Сторож — отдельный сервис на стороне сервера, и он переживёт не всякую
  /// смену бесплатных тарифов. Выключатель позволяет отказаться от подписки
  /// без выпуска новой версии: приложение вернётся к опросу по таймеру,
  /// который никуда не девался и продолжает работать всё это время.
  final bool pushEnabled;

  const AppConfig({
    this.scheduleUrl = defaultScheduleUrl,
    this.columns = ParserColumns.defaults,
    this.bellScheduleJson = '',
    this.adsEnabled = true,
    this.announcement = const Announcement(),
    this.latestVersion = '',
    this.minSupportedVersion = '',
    this.updateNotes = '',
    this.pushEnabled = true,
  });

  static const String defaultScheduleUrl =
      'https://bartc.by/index.php/obuchayushchemusya/dnevnoe-otdelenie/'
      'tekushchee-raspisanie';

  static const AppConfig defaults = AppConfig();
}

/// Удалённая конфигурация поверх Firebase Remote Config.
///
/// Устроена в два слоя намеренно:
///
/// 1. [refresh] работает только на главном изоляте, где инициализирован
///    Firebase, и складывает полученные значения в `SharedPreferences`.
/// 2. [load] читает `SharedPreferences` и работает где угодно — в том числе
///    в изоляте фоновой задачи Workmanager, где Firebase не поднят.
///
/// Без такого разделения фоновая синхронизация (а это единственный источник
/// уведомлений) не видела бы новых настроек парсера, то есть ровно тот
/// сценарий, ради которого конфиг и добавлен, не работал бы.
class RemoteConfigService {
  static final RemoteConfigService _instance = RemoteConfigService._internal();
  factory RemoteConfigService() => _instance;
  RemoteConfigService._internal();

  static const String _urlKey = 'rc_schedule_url';
  static const String _columnsKey = 'rc_parser_columns';
  static const String _bellKey = 'rc_bell_schedule';
  static const String _adsKey = 'rc_ads_enabled';
  static const String _pushKey = 'rc_push_enabled';
  static const String _announcementKey = 'rc_announcement';
  static const String _latestVersionKey = 'rc_latest_version';
  static const String _minVersionKey = 'rc_min_supported_version';
  static const String _updateNotesKey = 'rc_update_notes';

  /// Как часто разрешено ходить на сервер за конфигом.
  ///
  /// Шесть часов — компромисс: изменение доезжает до пользователя в тот же
  /// день, а бесплатной квоты Firebase хватает с многократным запасом.
  static const Duration _fetchInterval = Duration(hours: 6);

  AppConfig _current = AppConfig.defaults;

  /// Текущие настройки. Доступны синхронно, ждать сеть вызывающему не нужно.
  AppConfig get config => _current;

  /// Читает последние сохранённые значения. Вызывается на старте до того,
  /// как что-либо пойдёт в сеть.
  Future<AppConfig> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _current = AppConfig(
        scheduleUrl: _sanitizeUrl(prefs.getString(_urlKey)),
        columns: ParserColumns.fromJson(prefs.getString(_columnsKey) ?? ''),
        bellScheduleJson: prefs.getString(_bellKey) ?? '',
        adsEnabled: prefs.getBool(_adsKey) ?? true,
        pushEnabled: prefs.getBool(_pushKey) ?? true,
        announcement: parseAnnouncement(prefs.getString(_announcementKey)),
        latestVersion: prefs.getString(_latestVersionKey) ?? '',
        minSupportedVersion: prefs.getString(_minVersionKey) ?? '',
        updateNotes: prefs.getString(_updateNotesKey) ?? '',
      );
    } catch (e) {
      debugPrint('⚠️ Не удалось прочитать сохранённый конфиг: $e');
      _current = AppConfig.defaults;
    }
    return _current;
  }

  /// Разбирает выключатель из консоли, не веря `getBool`.
  ///
  /// `getBool` считает истиной только «true», «1», «yes», «t», «on» — а всё
  /// остальное ложью: пустую строку, «False» с заглавной, случайный пробел,
  /// ключ, заведённый числом или JSON. То есть опечатка в консоли молча
  /// выключала бы функцию у всех сразу, а вернуть её можно было бы только
  /// заметив, что она пропала.
  ///
  /// Так и вышло: `push_enabled` в консоли получил значение, которое
  /// `getBool` истиной не счёл, приложение отписалось от темы сторожа и
  /// перестало получать уведомления — молча, без единого следа.
  ///
  /// Поэтому выключателем считается только явно написанное «нет». Всё
  /// непонятное — это вшитое значение по умолчанию, как и у остальных
  /// ключей конфига.
  @visibleForTesting
  static bool readFlag(String raw, {required bool fallback}) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return fallback;

    const yes = {'true', '1', 'yes', 'y', 't', 'on', 'да', 'вкл'};
    const no = {'false', '0', 'no', 'n', 'f', 'off', 'нет', 'выкл'};

    if (yes.contains(value)) return true;
    if (no.contains(value)) return false;
    return fallback;
  }

  /// Забирает свежие значения из Firebase и сохраняет их.
  ///
  /// Любая ошибка (нет сети, нет `google-services.json`, отключённый проект)
  /// гасится: приложение продолжает работать на прошлых значениях.
  Future<void> refresh() async {
    try {
      final remote = FirebaseRemoteConfig.instance;

      await remote.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 15),
          minimumFetchInterval: kDebugMode ? Duration.zero : _fetchInterval,
        ),
      );

      await remote.setDefaults(const {
        'schedule_url': AppConfig.defaultScheduleUrl,
        'parser_columns': '',
        'bell_schedule': '',
        'ads_enabled': true,
        'push_enabled': true,
        'announcement': '',
        'latest_version': '',
        'min_supported_version': '',
        'update_notes': '',
      });

      await remote.fetchAndActivate();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_urlKey, remote.getString('schedule_url'));
      await prefs.setString(_columnsKey, remote.getString('parser_columns'));
      await prefs.setString(_bellKey, remote.getString('bell_schedule'));
      await prefs.setBool(
        _adsKey,
        readFlag(remote.getValue('ads_enabled').asString(), fallback: true),
      );
      await prefs.setBool(
        _pushKey,
        readFlag(remote.getValue('push_enabled').asString(), fallback: true),
      );
      await prefs.setString(_announcementKey, remote.getString('announcement'));
      await prefs.setString(
        _latestVersionKey,
        remote.getString('latest_version'),
      );
      await prefs.setString(
        _minVersionKey,
        remote.getString('min_supported_version'),
      );
      await prefs.setString(_updateNotesKey, remote.getString('update_notes'));

      await load();
      debugPrint('✅ Удалённый конфиг обновлён');
    } catch (e) {
      debugPrint('⚠️ Удалённый конфиг недоступен, работаем на прошлом: $e');
    }
  }

  /// Пустая или синтаксически неверная ссылка означает «оставить вшитую»:
  /// опечатка в консоли не должна оставить пользователей без расписания.
  @visibleForTesting
  static String sanitizeUrl(String? value) => _sanitizeUrl(value);

  static String _sanitizeUrl(String? value) {
    if (value == null || value.trim().isEmpty) {
      return AppConfig.defaultScheduleUrl;
    }
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.isScheme('https')) {
      return AppConfig.defaultScheduleUrl;
    }
    return uri.toString();
  }

  @visibleForTesting
  static Announcement parseAnnouncement(String? source) {
    if (source == null || source.trim().isEmpty) return const Announcement();
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return const Announcement();
      final text = (decoded['text'] ?? '').toString().trim();
      if (text.isEmpty) return const Announcement();
      return Announcement(
        id: (decoded['id'] ?? text.hashCode).toString(),
        text: text,
        url: (decoded['url'] ?? '').toString().trim(),
      );
    } catch (_) {
      return const Announcement();
    }
  }
}
