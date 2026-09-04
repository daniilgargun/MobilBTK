import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../providers/personalization_provider.dart';
import '../providers/schedule_provider.dart';

import 'package:intl/intl.dart' as intl;

import '../main.dart'; // Для доступа к myAppKey
import 'about_screen.dart';
import 'personalization_screen.dart';

import 'widget_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _isDarkMode;
  String _appVersion = '';
  bool? _notificationsEnabled;
  int _storageDays = 30;
  String _lastUpdateInfo = 'Загрузка...';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadNotificationsEnabled();
    _loadAppVersion();
    _loadLastUpdateInfo();
  }

  // Загружаем настройки из памяти телефона
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isDarkMode = prefs.getBool('is_dark_mode');
        _storageDays = prefs.getInt('schedule_storage_days') ?? 30;
      });
    }
  }

  // Получаем версию приложения
  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = packageInfo.version;
      });
    }
  }

  // Смотрим когда последний раз обновляли расписание
  Future<void> _loadLastUpdateInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastUpdateStr = prefs.getString('last_schedule_update');

      if (mounted) {
        if (lastUpdateStr != null) {
          final lastUpdate = DateTime.parse(lastUpdateStr);
          final now = DateTime.now();
          final diff = now.difference(lastUpdate);

          setState(() {
            if (diff.inMinutes < 1) {
              _lastUpdateInfo = "Обновлено только что";
            } else if (diff.inMinutes < 60) {
              _lastUpdateInfo = "Обновлено ${diff.inMinutes} мин. назад";
            } else if (diff.inHours < 24) {
              _lastUpdateInfo = "Обновлено ${diff.inHours} ч. назад";
            } else {
              final formatter = intl.DateFormat('dd.MM.yyyy HH:mm', 'ru_RU');
              _lastUpdateInfo = "Обновлено ${formatter.format(lastUpdate)}";
            }
          });
        } else {
          setState(() {
            _lastUpdateInfo = "Нет данных об обновлении";
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastUpdateInfo = "Ошибка получения информации";
        });
      }
    }
  }

  // Загружаем количество печенек
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        children: [
          // Секция персонализации (объединенная)
          _buildSectionHeader('Персонализация'),
          SwitchListTile(
            title: const Text('Тёмная тема'),
            subtitle: const Text('Включить тёмный режим'),
            value: _isDarkMode ?? false,
            onChanged: (value) async {
              await toggleTheme();
            },
            secondary: Icon(
              _isDarkMode ?? false ? Icons.dark_mode : Icons.light_mode,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          ListTile(
            title: const Text('Настройки интерфейса'),
            subtitle: const Text('Цвета, шрифты, формат отображения'),
            leading: Icon(
              Icons.palette_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PersonalizationScreen(),
                ),
              );
            },
          ),
          const Divider(),

          // Секция виджета
          _buildWidgetSection(),

          // Секция расписания
          _buildScheduleSection(),

          // Секция управления данными
          _buildSectionHeader('Управление данными'),
          ListTile(
            title: const Text('Сбросить настройки'),
            subtitle: const Text('Вернуть настройки по умолчанию'),
            leading: Icon(
              Icons.settings_backup_restore,
              color: Theme.of(context).colorScheme.primary,
            ),
            onTap: () {
              _showResetSettingsDialog();
            },
          ),
          ListTile(
            title: const Text('Очистить данные расписания'),
            subtitle: const Text('Удалить сохраненное расписание'),
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.primary,
            ),
            onTap: () {
              _showClearScheduleDialog();
            },
          ),
          const Divider(),

          // Секция о приложении
          _buildSectionHeader('О приложении'),
          ListTile(
            // Заголовок раздела уже говорит «О приложении», поэтому
            // строка не повторяет его, а показывает версию.
            title: Text(
              _appVersion.isEmpty ? 'Приложение' : 'Версия $_appVersion',
            ),
            subtitle: const Text('Авторы, ссылки и поддержка'),
            leading: Icon(
              Icons.info_outline,
              color: Theme.of(context).colorScheme.primary,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AboutScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _loadNotificationsEnabled() async {
    final enabled = await NotificationService().areNotificationsEnabled();
    if (!mounted) return;
    setState(() => _notificationsEnabled = enabled);
  }

  Future<void> _onNotificationsTap() async {
    final service = NotificationService();

    if (_notificationsEnabled == false) {
      await service.openSystemSettings();
      await _loadNotificationsEnabled();
      return;
    }

    await service.showNewScheduleNotification(
      'Если вы видите это уведомление, доставка работает.',
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Отправлено проверочное уведомление')),
    );
  }

  // Делает заголовки разделов в настройках
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  // Переключает темную тему
  Future<void> toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final newValue = !(_isDarkMode ?? false);
    setState(() {
      _isDarkMode = newValue;
    });
    // Обновляем в настройках телефона
    await prefs.setBool('is_dark_mode', newValue);

    // Обновляем тему в главном виджете приложения через глобальный ключ
    final appState = myAppKey.currentState;
    if (appState != null) {
      appState.updateTheme(newValue);
    }
  }

  // Обновляет количество дней хранения расписания
  Future<void> _updateStorageDays(int days) async {
    final provider = context.read<ScheduleProvider>();
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;
    setState(() {
      _storageDays = days;
    });

    await prefs.setInt('schedule_storage_days', days);

    // Обновляем настройки в провайдере и очищаем старые данные
    await provider.updateStorageDays(days);

    // Показываем уведомление об успешном обновлении
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Настройки хранения обновлены: $_storageDays дней'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // Открывает ссылки (сайт колледжа и телеграм)
  /// Открывает ссылку, перебирая варианты.
  ///
  /// Раньше ссылка вида "tg://..." шла единственным вариантом: если Telegram
  /// не установлен, launchUrl бросал исключение, оно молча проглатывалось,
  /// и нажатие не давало вообще никакой реакции. Теперь для Telegram есть
  /// веб-запасной вариант, а при полной неудаче показывается уведомление.
  // Показывает инфу обо мне
  // Добавляем метод для показа диалога пожертвования
  // Диалог сброса настроек
  Future<void> _showResetSettingsDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сбросить настройки?'),
        content: const Text(
          'Все настройки будут возвращены к значениям по умолчанию. Данные расписания не будут удалены.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );

    if (result == true) {
      if (!mounted) return;
      final provider = context.read<ScheduleProvider>();
      final personalization = context.read<PersonalizationProvider>();
      final prefs = await SharedPreferences.getInstance();

      // Сохраняем только данные о последнем обновлении
      final lastUpdateStr = prefs.getString('last_schedule_update');

      // Очищаем все настройки
      await prefs.clear();

      // Восстанавливаем данные о последнем обновлении
      if (lastUpdateStr != null) {
        await prefs.setString('last_schedule_update', lastUpdateStr);
      }

      // Устанавливаем настройки по умолчанию
      await prefs.setBool('is_dark_mode', false);
      await prefs.setInt('schedule_storage_days', 30);

      // Обновляем настройки в провайдере
      await provider.updateStorageDays(30);

      // prefs.clear() стирает и настройки персонализации, но провайдер
      // держит их в памяти: без явного сброса цвет и формат оставались
      // прежними до перезапуска приложения, а на диске уже были удалены.
      await personalization.resetSettings();

      // Тема приложения живёт в MyAppState, а не в prefs: без этого вызова
      // тумблер в настройках показывал светлую тему, а приложение
      // оставалось тёмным до перезапуска.
      myAppKey.currentState?.updateTheme(false);

      // Перезагружаем настройки
      await _loadSettings();

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Настройки сброшены')));
      }
    }
  }

  // Диалог очистки расписания
  Future<void> _showClearScheduleDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить расписание?'),
        content: const Text(
          'Все сохраненные данные расписания будут удалены. Вам потребуется подключение к интернету для загрузки нового расписания.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );

    if (result == true) {
      if (!mounted) return;
      final provider = context.read<ScheduleProvider>();

      // DatabaseService — обычный синглтон, а не Provider.
      // Раньше здесь был context.read<DatabaseService>(), который падал с
      // ProviderNotFoundException, потому что в MultiProvider он не заведён.
      await DatabaseService().recreateDatabase();

      // Полностью сбрасываем состояние и перечитываем данные,
      // иначе на экране оставалось расписание, уже удалённое из базы.
      await provider.reloadAfterDataCleared();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Данные расписания очищены')),
        );
      }
    }
  }

  // Секция виджета
  Widget _buildWidgetSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Настройки виджетов'),
        ListTile(
          title: const Text('Настроить виджеты'),
          subtitle: const Text('Предпросмотр, тема, прозрачность'),
          leading: Icon(
            Icons.widgets_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const WidgetSettingsScreen(),
              ),
            );
          },
        ),
        const Divider(),
      ],
    );
  }

  // Секция расписания
  Widget _buildScheduleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Расписание'),
        ListTile(
          title: const Text('Период отображения'),
          subtitle: Text('$_storageDays дней'),
          leading: Icon(
            Icons.date_range,
            color: Theme.of(context).colorScheme.primary,
          ),
          trailing: PopupMenuButton<int>(
            icon: const Icon(Icons.tune),
            tooltip: 'Изменить период отображения',
            onSelected: _updateStorageDays,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 7, child: Text('7 дней')),
              const PopupMenuItem(value: 14, child: Text('14 дней')),
              const PopupMenuItem(
                value: 30,
                child: Text('30 дней (рекомендуется)'),
              ),
              const PopupMenuItem(value: 60, child: Text('60 дней')),
              const PopupMenuItem(value: 90, child: Text('90 дней')),
            ],
          ),
        ),
        // Уведомления приходят только об изменениях, найденных фоновым
        // разбором, поэтому ждать их можно долго. Строка ниже позволяет
        // сразу проверить, что доставка вообще работает.
        ListTile(
          title: const Text('Уведомления об изменениях'),
          subtitle: Text(
            _notificationsEnabled == null
                ? 'Проверка…'
                : _notificationsEnabled!
                ? 'Включены · нажмите для проверки'
                : 'Выключены — нажмите, чтобы включить',
          ),
          leading: Icon(
            _notificationsEnabled == false
                ? Icons.notifications_off_outlined
                : Icons.notifications_active_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          onTap: _onNotificationsTap,
        ),
        ListTile(
          title: const Text('Последнее обновление'),
          subtitle: Text(_lastUpdateInfo),
          leading: Icon(
            Icons.update,
            color: Theme.of(context).colorScheme.primary,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await context.read<ScheduleProvider>().updateSchedule();
              await _loadLastUpdateInfo();
            },
          ),
        ),
        const Divider(),
      ],
    );
  }
}
