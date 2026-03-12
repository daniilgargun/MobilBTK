# Документация для разработчиков - БТК Расписание

**Copyright (c) 2024 Daniil Gargun. All rights reserved.**

## Обзор проекта

БТК Расписание - мобильное приложение на Flutter для просмотра расписания занятий Белорусского торгово-экономического колледжа потребительской кооперации.

### Технические характеристики
- **Платформа:** Flutter 3.6.2+
- **Язык:** Dart
- **Архитектура:** Provider + Clean Architecture
- **База данных:** SQLite (sqflite)
- **Кэширование:** Hive
- **Минимальная версия Android:** API 26 (Android 8.0)

## Структура проекта

```
lib/
├── main.dart                    # Точка входа приложения
├── models/                      # Модели данных
│   ├── schedule_model.dart      # Модель расписания
│   ├── note_model.dart          # Модель заметок
│   └── lesson_time_model.dart   # Модель времени занятий
├── providers/                   # Провайдеры состояния (Provider)
│   ├── schedule_provider.dart   # Управление расписанием
│   └── notes_provider.dart      # Управление заметками
├── screens/                     # Экраны приложения
│   ├── schedule_screen.dart     # Экран расписания
│   ├── calendar_screen.dart     # Экран календаря
│   └── settings_screen.dart     # Экран настроек
├── services/                    # Сервисы
│   ├── database_service.dart    # Работа с SQLite
│   ├── parser_service.dart      # Парсинг данных с сайта
│   ├── connectivity_service.dart # Проверка интернет-соединения
│   ├── ads_service.dart         # Интеграция с Яндекс.Рекламой
│   ├── cache_service.dart      # Сервис кэширования
│   ├── date_service.dart       # Сервис работы с датами
│   └── error_service.dart      # Сервис обработки ошибок
├── widgets/                     # Переиспользуемые виджеты
│   ├── schedule_item_card.dart  # Карточка урока
│   ├── bell_schedule_dialog.dart # Диалог расписания звонков
│   ├── error_snackbar.dart      # Кастомные уведомления
│   ├── selection_dialog.dart    # Диалог выбора
│   └── developer_ads_widget.dart # Виджет поддержки разработчика
```

## Основной функционал

### 1. Расписание занятий
- **Загрузка данных:** Парсинг с официального сайта колледжа
- **Поиск:** По группам, преподавателям, предметам, кабинетам
- **Фильтрация:** Настраиваемые фильтры поиска
- **Избранное:** Система избранных элементов для быстрого поиска
- **Офлайн режим:** Кэширование данных для работы без интернета
- **Поделиться:** Экспорт расписания в текстовом формате
- **Навигация:** Постраничный просмотр по дням с индикаторами

### 2. Календарь
- **Просмотр по датам:** Интеграция с table_calendar
- **Заметки:** Добавление/редактирование заметок к датам
- **Цветовая маркировка:** Дни с занятиями выделяются цветом
- **Фильтрация:** Применение фильтров расписания к календарю

### 3. Настройки
- **Темы:** Светлая/темная тема с автоматическим определением системной
- **Кэш:** Управление размером и периодом хранения данных (30-365 дней)
- **Очистка данных:** Селективная очистка по категориям
- **Информация:** О приложении, разработчике, версии

## Технические детали

### Архитектура данных

#### ScheduleProvider
```dart
class ScheduleProvider extends ChangeNotifier {
  // Основные данные
  Map<String, Map<String, List<ScheduleItem>>>? scheduleData;
  Map<String, Map<String, List<ScheduleItem>>>? fullScheduleData;
  
  // Состояние
  bool isLoading;
  bool isOffline;
  String? errorMessage;
  String? successMessage;
  
  // Настройки поиска
  SearchSettings searchSettings;
  
  // Методы
  Future<void> loadSchedule();
  Future<void> updateSchedule();
  Future<void> syncScheduleData();
}
```

#### DatabaseService
```dart
class DatabaseService {
  // Таблицы
  static const String scheduleTable = 'schedule';
  static const String notesTable = 'notes';
  static const String groupsTable = 'groups';
  static const String teachersTable = 'teachers';
  
  // Методы
  Future<Database> get database;
  Future<void> saveSchedule(Map<String, dynamic> data);
  Future<List<ScheduleItem>> getSchedule();
  Future<void> saveNote(Note note);
  Future<List<Note>> getNotes();
}
```

### Система кэширования

#### Hive (быстрый кэш)
- Используется для временного хранения данных
- Ключи: connectivity_cache, parser_cache
- Автоматическая очистка при изменении настроек

#### SQLite (постоянное хранение)
- Основная база данных приложения
- Таблицы: schedule, notes, groups, teachers
- Миграции версий при обновлениях

### Интеграция с Яндекс.Рекламой

#### AdsService
```dart
class AdsService {
  // Конфигурация
  static const String _rewardedAdUnitId = 'R-M-14828109-1';
  
  // Методы
  Future<void> initialize();
  Future<bool> showRewardedAd();
  Future<bool> isAdAvailable();
}
```

**Использование:**
- Инициализация в main.dart с задержкой 3 секунды
- Показ в настройках для поддержки разработчика
- Обработка ошибок и таймаутов

### Офлайн режим

#### ConnectivityService
```dart
class ConnectivityService {
  // Проверка соединения
  Future<bool> hasConnection();
  
  // Кэширование
  Future<void> cacheData(String key, String data);
  String? getCachedData(String key);
  
  // Уведомления
  void showOfflineWarning(BuildContext context);
}
```

**Логика работы:**
1. Проверка соединения при запуске
2. Автоматическое переключение в офлайн режим
3. Показ предупреждений пользователю
4. Использование кэшированных данных

### Система уведомлений

#### CustomSnackBar
```dart
class CustomSnackBar {
  static void showError(BuildContext context, String message);
  static void showSuccess(BuildContext context, String message);
  static void showWarning(BuildContext context, String message);
  static void showOfflineMode(BuildContext context);
}
```

**Типы уведомлений:**
- Ошибки (красные) - проблемы загрузки, сетевые ошибки
- Успех (зеленые) - успешные операции
- Предупреждения (желтые) - офлайн режим, ограничения
- Информационные - через стандартные SnackBar

### Парсинг данных

#### ParserService
- Загрузка HTML с сайта колледжа
- Парсинг таблиц расписания
- Извлечение групп и преподавателей
- Обработка ошибок и валидация данных
- Кэширование результатов

### Работа с датами

#### DateService
- Единый сервис для парсинга и форматирования дат
- Поддержка формата "день-месяц" (например, "6-нояб")
- Автоматическое определение учебного года
- Форматирование дат для отображения и хранения

## Зависимости

### Основные пакеты
```yaml
dependencies:
  flutter: sdk
  provider: ^6.1.1          # Управление состоянием
  sqflite: ^2.3.2           # SQLite база данных
  hive: ^2.2.3              # Быстрое кэширование
  http: ^1.2.0              # HTTP запросы
  html: ^0.15.0             # Парсинг HTML
  shared_preferences: ^2.5.2 # Настройки
  table_calendar: ^3.0.9    # Календарь
  connectivity_plus: ^7.0.0 # Проверка соединения
  yandex_mobileads: ^7.12.0 # Яндекс.Реклама
  awesome_snackbar_content: ^0.1.5 # Красивые уведомления
  share_plus: ^12.0.0       # Поделиться
  url_launcher: ^6.2.5      # Открытие ссылок
  intl: ^0.20.2             # Интернационализация
  timezone: ^0.10.1         # Временные зоны
  cached_network_image: ^3.3.1 # Кэширование изображений
  dynamic_color: ^1.8.1      # Динамические цвета Material You
```

### Dev зависимости
```yaml
dev_dependencies:
  flutter_lints: ^6.0.0     # Линтер
  build_runner: ^2.4.8      # Генерация кода
  hive_generator: ^2.0.1    # Генератор для Hive
```

## Сборка и развертывание

### Android
```bash
# Debug сборка
flutter build apk --debug

# Release сборка
flutter build apk --release

# Bundle для Google Play
flutter build appbundle --release
```

### Конфигурация ProGuard
- Сохранение Flutter классов
- Правила для Яндекс.Рекламы
- Оптимизация размера APK
- Сохранение отладочных символов

### Подписание APK
- Использование upload-keystore.jks
- Конфигурация в android/app/build.gradle.kts
- Автоматическое подписание release сборок

## Особенности реализации

### Производительность
- Кэширование отфильтрованных данных
- Ленивая загрузка списков
- Оптимизированная перерисовка UI
- Предварительная подготовка данных

### Обработка ошибок
- Глобальный обработчик Flutter ошибок
- Graceful degradation при сетевых проблемах
- Информативные сообщения пользователю
- Логирование для отладки

### Безопасность
- Валидация входных данных
- Безопасное хранение настроек
- Защита от SQL инъекций
- Обработка некорректных данных с сервера

### Локализация
- Поддержка русского языка
- Форматирование дат и времени
- Адаптация под региональные настройки

## Известные ограничения

1. **Источник данных:** Зависимость от структуры сайта колледжа
2. **Офлайн режим:** Ограниченный функционал без интернета
3. **Реклама:** Требует подключения к интернету
4. **Платформы:** Оптимизировано для Android

## Планы развития

### Краткосрочные
- Улучшение производительности парсинга
- Расширение системы фильтров
- Оптимизация работы с базой данных

### Долгосрочные
- Поддержка iOS
- Push-уведомления
- Синхронизация между устройствами
- Расширение функционала календаря

## Контакты разработчика

**Автор:** Данил Гаргун  
**Telegram:** [@Daniilgargun](https://t.me/Daniilgargun)  
**Email:** daniilgorgun38@gmail.com  
**Телефон:** +375299545338

---

*Данная документация описывает реальный функционал приложения на момент версии 1.0.7* 