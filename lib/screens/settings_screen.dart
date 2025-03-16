import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../providers/schedule_provider.dart';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import '../main.dart';
import 'package:intl/intl.dart' as intl;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _isDarkMode;
  bool _isLoading = true;
  String _appVersion = '';
  int _storageDays = 30;
  String _lastUpdateInfo = '';
  Map<String, String> _cacheInfo = {};
  bool _showCacheDetails = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadAppVersion();
    _loadLastUpdateInfo();
    _calculateCacheSize();
  }

  // Загружаем настройки из памяти телефона
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('is_dark_mode');
      _storageDays = prefs.getInt('schedule_storage_days') ?? 30;
      _isLoading = false;
    });
  }

  // Получаем версию приложения
  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _appVersion = packageInfo.version;
    });
  }

  // Смотрим когда последний раз обновляли расписание
  Future<void> _loadLastUpdateInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastUpdateStr = prefs.getString('last_schedule_update');
      
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
    } catch (e) {
      setState(() {
        _lastUpdateInfo = "Ошибка получения информации";
      });
    }
  }

  // Считаем сколько места занимает приложение
  Future<void> _calculateCacheSize() async {
    try {
      final dbDir = await getDatabasesPath();
      final Map<String, String> cacheInfo = {};
      
      // Размер базы данных
      final dbFile = File('$dbDir/schedule.db');
      if (await dbFile.exists()) {
        final dbSize = await dbFile.length();
        cacheInfo['База данных'] = _formatSize(dbSize);
      } else {
        cacheInfo['База данных'] = '0 КБ';
      }
      
      // Размер SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final prefsSize = await prefs.getKeys().length * 100; // Примерная оценка
      cacheInfo['Настройки'] = _formatSize(prefsSize);
      
      // Общий размер
      final totalSize = await _calculateTotalCacheSize();
      cacheInfo['Общий размер'] = _formatSize(totalSize);
      
      setState(() {
        _cacheInfo = cacheInfo;
      });
    } catch (e) {
      print('Ошибка при расчете размера кэша: $e');
    }
  }

  // Считаем общий размер всех данных
  Future<int> _calculateTotalCacheSize() async {
    int totalSize = 0;
    
    try {
      final dbDir = await getDatabasesPath();
      
      // Размер базы данных
      final dbFile = File('$dbDir/schedule.db');
      if (await dbFile.exists()) {
        totalSize += await dbFile.length();
      }
      
      // Примерный размер SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      totalSize += prefs.getKeys().length * 100; // Примерная оценка
      
    } catch (e) {
      print('Ошибка при расчете общего размера кэша: $e');
    }
    
    return totalSize;
  }

  // Переводит байты в нормальный размер (КБ, МБ)
  String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes Б';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Загрузка настроек...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
      ),
      body: ListView(
        children: [
          // Секция внешнего вида
          _buildSectionHeader('Внешний вид'),
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
          const Divider(),

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
            title: const Text('Разработчик'),
            subtitle: const Text('Gargun Daniil'),
            leading: Icon(
              Icons.person_outline,
              color: Theme.of(context).colorScheme.primary,
            ),
            onTap: () {
              _showDeveloperInfo();
            },
          ),
          ListTile(
            title: const Text('Сайт колледжа'),
            subtitle: const Text('bartc.by'),
            leading: Icon(
              Icons.public,
              color: Theme.of(context).colorScheme.primary,
            ),
            onTap: () {
              _launchUrl('https://bartc.by');
            },
          ),
          ListTile(
            title: const Text('Telegram-бот'),
            subtitle: const Text('@BTKraspbot'),
            leading: Icon(
              Icons.telegram,
              color: Theme.of(context).colorScheme.primary,
            ),
            onTap: () => _launchUrl('https://t.me/BTKraspbot'),
          ),
          ListTile(
            title: const Text('Версия'),
            subtitle: Text(_appVersion),
            leading: Icon(
              Icons.info_outline,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
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
    final newValue = !(_isDarkMode ?? false);
    setState(() {
      _isDarkMode = newValue;
    });
    await prefs.setBool('is_dark_mode', newValue);
    
    // Обновляем тему в родительском виджете
    if (context.mounted) {
      final appState = context.findAncestorStateOfType<MyAppState>();
      if (appState != null) {
        appState.updateTheme(newValue);
      }
    }
  }

  // Обновляет количество дней хранения расписания
  Future<void> _updateStorageDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _storageDays = days;
      _isLoading = true;
    });
    
    await prefs.setInt('schedule_storage_days', days);
    
    // Обновляем настройки в провайдере и очищаем старые данные
    final provider = context.read<ScheduleProvider>();
    await provider.updateStorageDays(days);
    
    // Пересчитываем размер кэша
    await _calculateCacheSize();
    
    setState(() {
      _isLoading = false;
    });
    
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
  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    
    if (urlString.startsWith('https://t.me/')) {
      try {
        final telegramUrl = Uri.parse('tg://resolve?domain=${urlString.split('/').last}');
        if (await canLaunchUrl(telegramUrl)) {
          await launchUrl(telegramUrl);
          return;
        }
      } catch (e) {
        debugPrint('Ошибка открытия Telegram: $e');
      }
    }
    
    try {
      await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('Ошибка открытия ссылки: $e');
    }
  }

  // Показывает инфу обо мне
  void _showDeveloperInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Разработчик'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gargun Daniil(383)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () => _launchUrl('tg://resolve?domain=Daniilgargun'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.telegram,
                      color: Theme.of(context).colorScheme.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '@Daniilgargun',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  // Диалог сброса настроек
  Future<void> _showResetSettingsDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сбросить настройки?'),
        content: const Text('Все настройки будут возвращены к значениям по умолчанию. Данные расписания не будут удалены.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );

    if (result == true) {
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
      final provider = context.read<ScheduleProvider>();
      await provider.updateStorageDays(30);
      
      // Перезагружаем настройки
      await _loadSettings();
      
      // Обновляем тему в родительском виджете
      if (context.mounted) {
        final appState = context.findAncestorStateOfType<MyAppState>();
        if (appState != null) {
          appState.updateTheme(false);
        }
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Настройки сброшены')),
        );
      }
    }
  }

  // Диалог очистки расписания
  Future<void> _showClearScheduleDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить расписание?'),
        content: const Text('Все сохраненные данные расписания будут удалены. Вам потребуется подключение к интернету для загрузки нового расписания.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );

    if (result == true) {
      setState(() {
        _isLoading = true;
      });
      
      // Очищаем базу данных
      final db = context.read<DatabaseService>();
      await db.recreateDatabase();
      
      // Сбрасываем данные в провайдере
      final provider = context.read<ScheduleProvider>();
      provider.clearCache();
      
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Данные расписания очищены')),
        );
      }
    }
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
              const PopupMenuItem(
                value: 7,
                child: Text('7 дней'),
              ),
              const PopupMenuItem(
                value: 14,
                child: Text('14 дней'),
              ),
              const PopupMenuItem(
                value: 30,
                child: Text('30 дней (рекомендуется)'),
              ),
              const PopupMenuItem(
                value: 60,
                child: Text('60 дней'),
              ),
              const PopupMenuItem(
                value: 90,
                child: Text('90 дней'),
              ),
            ],
          ),
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
              setState(() {
                _isLoading = true;
              });
              await context.read<ScheduleProvider>().updateSchedule();
              await _loadLastUpdateInfo();
              setState(() {
                _isLoading = false;
              });
            },
          ),
        ),
        const Divider(),
      ],
    );
  }
} 