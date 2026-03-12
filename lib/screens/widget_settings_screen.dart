import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/home_widget_service.dart';
import '../widgets/widget_preview.dart';

class WidgetSettingsScreen extends StatefulWidget {
  final bool isConfiguration;

  const WidgetSettingsScreen({
    super.key,
    this.isConfiguration = false,
  });

  @override
  State<WidgetSettingsScreen> createState() => _WidgetSettingsScreenState();
}

class _WidgetSettingsScreenState extends State<WidgetSettingsScreen> {
  bool _isLoading = true;
  bool _isDark = true;
  int _transparency = 0;
  static const platform = MethodChannel('com.gargun.btktimetable/widget');

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await HomeWidgetService.loadWidgetSettings();
    if (mounted) {
      setState(() {
        _isDark = settings['isDark'];
        _transparency = settings['transparency'];
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isLoading = true;
    });

    await HomeWidgetService.saveWidgetSettings(_isDark, _transparency);

    if (widget.isConfiguration) {
      debugPrint('✅ Настройки сохранены, завершаем конфигурацию виджета');
      try {
        await platform.invokeMethod('finishConfigure');
      } on PlatformException catch (e) {
        debugPrint("Failed to finish configuration: '${e.message}'.");
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Настройки виджета сохранены')),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки виджета'),
        automaticallyImplyLeading: !widget.isConfiguration,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Preview Section
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Предпросмотр',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          WidgetPreview(
                            isDark: _isDark,
                            transparency: _transparency,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Settings Section
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Внешний вид',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SwitchListTile(
                            title: const Text('Тёмная тема виджета'),
                            subtitle: const Text(
                                'Использовать тёмный фон для виджета'),
                            value: _isDark,
                            onChanged: (value) {
                              setState(() {
                                _isDark = value;
                              });
                            },
                            secondary: Icon(
                              _isDark ? Icons.dark_mode : Icons.light_mode,
                              color: colorScheme.primary,
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                          const Divider(),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.opacity, color: colorScheme.primary),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Прозрачность фона',
                                      style:
                                          Theme.of(context).textTheme.bodyLarge,
                                    ),
                                    Text(
                                      '${_transparency.round()}%',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: _transparency.toDouble(),
                            min: 0,
                            max: 100,
                            divisions: 20,
                            label: '${_transparency.round()}%',
                            onChanged: (value) {
                              setState(() {
                                _transparency = value.toInt();
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Save Button
                  FilledButton.icon(
                    onPressed: _saveSettings,
                    icon:
                        Icon(widget.isConfiguration ? Icons.check : Icons.save),
                    label: Text(widget.isConfiguration
                        ? 'Добавить виджет'
                        : 'Сохранить настройки'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(
                      height: 50), // Extra padding for bottom navigation
                ],
              ),
            ),
    );
  }
}
