# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## О проекте

«БТК Расписание» — Flutter-приложение (Android, `com.gargun.btktimetable`) для просмотра расписания
Белорусского торгово-экономического колледжа. Данные не приходят из API — они **парсятся из HTML**
публичной страницы `https://bartc.by/index.php/obuchayushchemusya/dnevnoe-otdelenie/tekushchee-raspisanie`.

Проприетарный код (см. `LICENSE`, `COPYRIGHT`). Весь UI, комментарии и документация — на русском;
поддерживается единственная локаль `ru_RU`.

## Команды

```bash
flutter pub get
flutter run                       # отладка на подключённом устройстве
flutter analyze                   # линт (flutter_lints)
dart format --set-exit-if-changed .   # CI падает на неотформатированном коде
flutter test                      # все тесты
flutter test test/widget_test.dart --plain-name "имя теста"   # один тест
flutter build apk --release
flutter build appbundle --release # артефакт для Google Play
```

Тесты покрывают чистую логику и карточку пары: `date_service_test.dart` (разбор и хронологическая
сортировка дат), `schedule_diff_service_test.dart` (сравнение расписаний, на котором держатся
уведомления), `schedule_model_test.dart` (равенство по значению, времена звонков),
`schedule_item_card_test.dart` (вёрстка карточки, переполнения, подгруппа «0»).
Экраны целиком не тестируются: они тянут плагины (Firebase, sqflite, реклама).

CI (`.github/workflows/main.yml`, Flutter 3.47.2) запускает format → analyze → test → сборку.
Шаги сборки помечены `continue-on-error`, потому что в репозитории нет ни
`android/app/google-services.json`, ни `android/key.properties`.

Release-сборка требует `android/key.properties` (не в git) с `keyAlias/keyPassword/storeFile/storePassword`;
keystore — `upload-keystore.jks`.

**Версия задаётся в двух местах и должна поменяться в обоих:** `pubspec.yaml` (`version: 1.0.12+16`)
и `android/app/build.gradle.kts` (`versionCode`/`versionName` прописаны литералами).

`targetSdk = 36` — требование Google Play для обновлений с 31.08.2026; понижать нельзя.
`packaging.jniLibs.useLegacyPackaging = false` нужен для поддержки страниц памяти 16 КБ.
В `proguard-rules.pro` не должно появляться правил вида `-keep class ** { *; }`: они отключают
сокращение кода целиком и обесценивают `isMinifyEnabled`.

## Архитектура

### Поток данных

```
bartc.by (HTML)
  → ParserService.parseSchedule()      ← вызывается через compute() в изоляте
  → ScheduleProvider                   ← единственный владелец состояния расписания
  → DatabaseService (SQLite)           ← current_schedule + archive_schedule
  → CacheService / UI / HomeWidgetService
```

Центральная структура данных, проходящая через все слои:
`Map<String /*дата*/, Map<String /*группа*/, List<ScheduleItem>>>`.
Ключ-дата всегда строка в формате `dd.MM.yyyy`.

### Две таблицы расписания

`current_schedule` — снимок того, что сейчас опубликовано на сайте (перезаписывается целиком).
`archive_schedule` — накопительная история (`fullScheduleData`), из неё живут календарь и просмотр
прошедших дней. `updateSchedule()` пишет в обе: `saveCurrentSchedule()` затем `archiveSchedule()`.
Обрезка старого регулируется `_storageDays` (минимум 30 дней, даже если пользователь выбрал меньше).

Инвариант архива: он хранит **последнюю известную** версию каждого дня, а не первую.
`archiveSchedule()` заменяет записи дня целиком; дни, отсутствующие во входных данных, не трогаются
(их удаляет `cleanOldArchive` по сроку хранения). Если сюда вернуть условие «писать только если дня
ещё нет», календарь снова начнёт показывать устаревшую версию дня, пока экран расписания показывает
актуальную.

Очистка старого — только через `DateService`: даты в столбце `date` хранятся как `dd.MM.yyyy`,
и сравнивать их в SQL с ISO-строками нельзя (`'03.09.2026' < '2026-08-04'` истинно как текст).

### Многоуровневое кэширование

- `ParserService` — запрос и хэш страницы считаются на вызывающем изоляте, в `compute()` уходит
  только разбор HTML. Хэш последней разобранной страницы хранит провайдер в `SharedPreferences`
  (`last_page_hash`); если содержимое не изменилось, разбор и запись в базу пропускаются.
  Не возвращайте кэш в статические поля `ParserService`: они живут в изоляте `compute()`
  и умирают вместе с ним, из-за чего кэш не переживал даже двух обновлений подряд.
- `DatabaseService` — статические `_scheduleCache` / `_listsCache`, прогреваются при инициализации.
- `CacheService` (синглтон) — кэши отфильтрованных выборок, событий календаря и подготовленных дней,
  лимит 1000 записей. Инвалидируется из `ScheduleProvider` после успешного обновления.
- `ConnectivityService` — Hive box `schedule_cache` для офлайн-данных.

Настройки хранятся в `SharedPreferences` (`is_dark_mode`, `use_dynamic_colors`,
`personalization_settings` (JSON), `schedule_storage_days`, `last_schedule_update`, `last_sync_time`).

### Фоновое обновление и уведомления

Две независимые точки входа, обе ведут в `ConnectivityService._performBackgroundSync()`:

1. `Workmanager` — периодическая задача `syncSchedule` (каждые 15 мин), обработчик — `callbackDispatcher`
   в `lib/main.dart` (помечен `@pragma('vm:entry-point')`; изолят фоновой задачи заново инициализирует
   timezone и `ru_RU`).
2. Слушатель `connectivity_plus` — синхронизация при восстановлении сети.

Окно синхронизации: 07:00–21:00, кроме воскресенья. Внутри 07:00–17:00 интервал 15 мин, иначе 3 часа.

После обновления `ScheduleDiffService.compareSchedules(old, new)` строит `ScheduleDiffResult`
(добавленные/удалённые/изменённые пары), и при `hasChanges` `NotificationService` шлёт локальное
уведомление. Никакого серверного push нет — «уведомления об обновлении» строятся полностью на диффе клиента.

### Виджеты на главный экран (Android)

Мост Dart → нативный код односторонний, через `home_widget` (SharedPreferences):
`HomeWidgetService` кладёт ключи `schedule_data` (JSON списка пар), `schedule_date`, `widget_title`,
`last_updated`, `bell_schedule_templates`, `widget_theme_dark`, `widget_transparency`, `widget_color`,
затем дёргает `HomeWidget.updateWidget()`. Читают их Kotlin-классы
`ScheduleWidget` / `ScheduleWidgetService` и `BellScheduleWidgetProvider` / `BellScheduleWidgetService`
(`android/app/src/main/kotlin/com/gargun/btktimetable/`), рисуя `RemoteViews`; `ScheduleWidget` держит
собственный `AlarmManager` с перерисовкой раз в минуту.

Обновления виджетов планирует `WidgetUpdateScheduler` (`WidgetTheme.kt`): одноразовый будильник
ровно на ближайшую границу пары или перемены, который после срабатывания ставит следующий.
Раньше оба виджета держали повторяющийся будильник раз в минуту — 1440 пробуждений в сутки.
Не заменяйте это на периодический таймер.

Фон виджета красится фильтром на отдельном `ImageView` (`R.id.widget_background`), а не через
`setBackgroundColor` у корневого контейнера: последний заменяет drawable сплошной заливкой
и стирает скругление углов.

Конфигурация виджета идёт через `MethodChannel('com.gargun.btktimetable/widget')`:
`getAppWidgetId`, `finishConfigure`, `checkWidgetSettingsAction`, `getWallpaper`.
`MyAppState` опрашивает канал в `initState` и на `AppLifecycleState.resumed`; если приложение запущено
как configure-activity виджета, вместо `MyHomePage` показывается `WidgetSettingsScreen(isConfiguration: true)`.

### Состояние и темы

Три `ChangeNotifier`, создаются в `main()` и передаются через `ChangeNotifierProvider.value`
(порядок инициализации важен: `ConnectivityService.setScheduleProvider()` вызывается до `runApp`):

- `ScheduleProvider` — расписание, группы/преподаватели, избранное, настройки поиска (`SearchSuggestionSettings`), офлайн-статус.
- `NotesProvider` — заметки к датам. Дата нормализуется до полуночи и в памяти, и в базе;
  у таблицы `notes` нет UNIQUE по дате, поэтому `saveNote` сначала удаляет записи дня
  (`date LIKE 'YYYY-MM-DD%'`), а затем вставляет одну.
- `PersonalizationProvider` — seed-цвет, пресет темы (`ThemePresets`), формат отображения (`DisplayFormat.list` / `grid`).

Светлая/тёмная тема живёт **не** в провайдере, а в `MyAppState` (`_isDarkMode`, `_useDynamicColors`);
экраны меняют её через глобальный `myAppKey.currentState?.updateTheme(...)`. Есть также глобальный
`navigatorKey`. Смена seed-цвета в `PersonalizationProvider` дополнительно пушится в виджеты
(`HomeWidgetService.saveWidgetColor`).

### Даты и время пар

Все преобразования дат — только через `DateService`: сайт отдаёт `«04-дек»`, `_extractDate`/`parseScheduleDate`
разворачивают это в `dd.MM.yyyy`, определяя учебный год (сентябрь–июнь) и переход через Новый год.
При работе с датами не парсите строки вручную.

Порядок дней берите из `ScheduleProvider.orderedDates` (внутри — `DateService.sortDateKeys`).
Порядок ключей `Map` идёт из порядка строк SQLite и не хронологичен, а `list.sort()` по строкам
`dd.MM.yyyy` сортирует как текст: `01.10` окажется раньше `02.09`.

Время звонков — в `LessonTime` (`lib/models/lesson_time_model.dart`), четыре типа дня:
`normal` / `tuesday` (классный час) / `thursday` (часы информации) / `saturday`; пара состоит из двух
получасовых половин (`isFirstHalf`).

`LessonTime` — **единственный** источник расписания звонков. Раньше время дублировалось ещё в двух
местах (`HomeWidgetService._getHardcodedLessonEndTime` и `ScheduleWidgetService.getLessonTime` в Kotlin),
и все три таблицы расходились. Обе копии удалены: Dart считает время из `LessonTime`, а в виджет оно
приходит уже посчитанным, в поле `time` каждого занятия. Не заводите новых таблиц времени.

## Внешние интеграции

- **Firebase** (`Firebase.initializeApp()` + Analytics) — `android/app/google-services.json` в git не хранится.
  Пакет `firebase_analytics` не используется из Dart, но нативный SDK собирает статистику
  автоматически: это отражено в `lib/docs/privacy_policy.md` и должно совпадать с формой
  Data Safety в Play Console.
- **Яндекс.Реклама** (`yandex_mobileads` 8.x, `YandexAds`) — только rewarded-ролик `R-M-14828109-1` в блоке «поддержать разработчика»;
  инициализация отложена на 3 секунды после старта, ошибки глушатся.
- **upgrader** — `UpgradeAlert` вокруг главного `Scaffold`, проверяет версию в Google Play.

## Соглашения

- Экраны сравнивают карты расписания через `identical(...)`, а не по числу дней: провайдер при
  каждом обновлении присваивает новый экземпляр, а число дней часто не меняется.
- Ввод, который что-то сохраняет, идёт через debounce: поиск (600 мс) пересобирает виджет на
  главном экране, заметка (500 мс) пишется в SQLite. Без задержки это выполнялось на каждый символ.
- `setState` после `await` всегда под проверкой `mounted`.
- Все ошибки верхнего уровня перехватываются `runZonedGuarded` + `FlutterError.onError` в `main()`;
  логирование — `debugPrint` с эмодзи-префиксами (`🔄 ✅ ❌ ⚠️ 📦`). Внешнего crash-reporting нет.
- Пользовательские сообщения об ошибках — `ErrorService` / `CustomSnackBar` / `ErrorBanner`, не голый `SnackBar`.
- Файлы верхнего уровня начинаются с блока копирайта — сохраняйте его при правках.
