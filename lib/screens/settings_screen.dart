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

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('is_dark_mode');
      _storageDays = prefs.getInt('schedule_storage_days') ?? 30;
      _isLoading = false;
    });
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _appVersion = packageInfo.version;
    });
  }

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
      return const Center(child: CircularProgressIndicator());
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
          ),
          const Divider(),

          // Секция расписания
          _buildSectionHeader('Расписание'),
          ListTile(
            title: const Text('Хранение расписания'),
            subtitle: Text('$_storageDays дней'),
            trailing: PopupMenuButton<int>(
              icon: const Icon(Icons.arrow_drop_down_circle_outlined),
              onSelected: _updateStorageDays,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 7,
                  child: Text('7 дней'),
                ),
                const PopupMenuItem(
                  value: 15,
                  child: Text('15 дней'),
                ),
                const PopupMenuItem(
                  value: 30,
                  child: Text('30 дней'),
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

          // Секция управления данными
          _buildSectionHeader('Управление данными'),
          ListTile(
            title: const Text('Данные приложения'),
            subtitle: Text(_cacheInfo['Общий размер'] ?? '0 КБ'),
            trailing: IconButton(
              icon: Icon(_showCacheDetails 
                ? Icons.keyboard_arrow_up 
                : Icons.keyboard_arrow_down),
              onPressed: () {
                setState(() {
                  _showCacheDetails = !_showCacheDetails;
                });
              },
            ),
          ),
          if (_showCacheDetails)
            ..._cacheInfo.entries
                .where((entry) => entry.key != 'Общий размер')
                .map((entry) => Padding(
                  padding: const EdgeInsets.only(left: 16.0),
                  child: ListTile(
                    title: Text(entry.key),
                    trailing: Text(entry.value),
                  ),
                )),
          ListTile(
            title: const Text('Очистить кэш'),
            subtitle: const Text('Выберите, что нужно очистить'),
            trailing: const Icon(Icons.delete_forever),
            onTap: () {
              _showClearCacheDialog();
            },
          ),
          const Divider(),

          // Секция о приложении
          _buildSectionHeader('О приложении'),
          ListTile(
            title: const Text('Разработчик'),
            subtitle: const Text('Gargun Daniil'),
            onTap: () {
              _showDeveloperInfo();
            },
          ),
          ListTile(
            title: const Text('Сайт колледжа'),
            subtitle: const Text('bartc.by'),
            onTap: () {
              _launchUrl('https://bartc.by');
            },
          ),
          ListTile(
            title: const Text('Telegram-бот'),
            subtitle: const Text('@BTKraspbot'),
            onTap: () => _launchUrl('https://t.me/BTKraspbot'),
          ),
          ListTile(
            title: const Text('Версия'),
            subtitle: Text(_appVersion),
          ),
        ],
      ),
    );
  }

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

  Future<void> _updateStorageDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _storageDays = days;
    });
    await prefs.setInt('schedule_storage_days', days);
  }

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

  Future<void> _showClearCacheDialog() async {
    final result = await showDialog<Map<String, bool>>(
      context: context,
      builder: (context) {
        final checkboxValues = {
          'База данных': true,
          'Настройки': false,
        };
        
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Очистить кэш?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Выберите, что нужно очистить:'),
                const SizedBox(height: 16),
                ...checkboxValues.entries.map((entry) => CheckboxListTile(
                  title: Text(entry.key),
                  subtitle: Text(_cacheInfo[entry.key] ?? '0 КБ'),
                  value: entry.value,
                  onChanged: (value) {
                    setState(() {
                      checkboxValues[entry.key] = value ?? false;
                    });
                  },
                )),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, checkboxValues),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                ),
                child: const Text('Очистить'),
              ),
            ],
          ),
        );
      },
    );

    if (result != null) {
      // Очистка выбранных данных
      final db = context.read<DatabaseService>();
      
      if (result['База данных'] == true) {
        await db.recreateDatabase();
      }
      
      if (result['Настройки'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
      }
      
      // Перезагрузка настроек и пересчет размера кэша
      await _loadSettings();
      await _calculateCacheSize();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Кэш очищен')),
        );
      }
    }
  }
} 