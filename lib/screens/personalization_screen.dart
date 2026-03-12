import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/personalization_provider.dart';
import '../models/personalization_settings.dart';
import '../themes/theme_presets.dart';
import '../widgets/schedule_item_card.dart';
import '../models/schedule_model.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

/// Экран настроек персонализации интерфейса
class PersonalizationScreen extends StatelessWidget {
  const PersonalizationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки интерфейса'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            onPressed: () => _showResetDialog(context),
            tooltip: 'Сбросить настройки',
          ),
        ],
      ),
      body: Consumer<PersonalizationProvider>(
        builder: (context, provider, _) {
          final settings = provider.settings;

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              // Цветовая тема
              _buildSection(
                context,
                icon: Icons.palette_outlined,
                title: 'Цветовая тема',
                subtitle: 'Выберите основной цвет приложения',
                child: _buildThemePresetSelector(context, provider, settings),
              ),

              const Divider(height: 24),

              // Формат отображения
              _buildSection(
                context,
                icon: Icons.view_module_outlined,
                title: 'Формат расписания',
                subtitle: 'Выберите способ отображения расписания',
                child: _buildDisplayFormatSelector(context, provider, settings),
              ),

              const Divider(height: 24),

              // Предпросмотр
              _buildSection(
                context,
                icon: Icons.preview_outlined,
                title: 'Предпросмотр',
                subtitle: 'Как будет выглядеть текст с вашими настройками',
                child: _buildPreview(context, settings),
              ),

              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildThemePresetSelector(
    BuildContext context,
    PersonalizationProvider provider,
    PersonalizationSettings settings,
  ) {
    return Card(
      elevation: 0,
      color:
          Theme.of(context).colorScheme.surfaceVariant.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            ...ThemePresets.availableThemes.map((themeName) {
              final isSelected = settings.themePreset == themeName;
              final color = ThemePresets.getColor(themeName) ?? Colors.blue;
              final label = themeName;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => provider.setThemePreset(themeName),
                        borderRadius: BorderRadius.circular(50),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                              width: isSelected ? 4 : 2,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.4),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : [],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              );
            }),
            // Кнопка палитры для выбора любого цвета
            Builder(builder: (context) {
              final isSelected = settings.themePreset == 'Custom';
              // If isSelected, use settings.seedColor, otherwise use a rainbow/grey
              final color = isSelected
                  ? settings.seedColor
                  : Theme.of(context).colorScheme.surfaceContainerHighest;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _showColorPicker(context, provider),
                        borderRadius: BorderRadius.circular(50),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                              width: isSelected ? 4 : 2,
                            ),
                            gradient:
                                !isSelected // Show gradient rainbow if not selected
                                    ? const SweepGradient(
                                        colors: [
                                          Colors.red,
                                          Colors.orange,
                                          Colors.yellow,
                                          Colors.green,
                                          Colors.blue,
                                          Colors.indigo,
                                          Colors.purple,
                                          Colors.red,
                                        ],
                                      )
                                    : null,
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.4),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : [],
                          ),
                          child: isSelected
                              ? null
                              : const Icon(Icons.colorize,
                                  color: Colors.white, size: 24),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Свой',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDisplayFormatSelector(
    BuildContext context,
    PersonalizationProvider provider,
    PersonalizationSettings settings,
  ) {
    return Card(
      elevation: 0,
      color:
          Theme.of(context).colorScheme.surfaceVariant.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: _buildFormatCard(
                context,
                icon: Icons.view_list_rounded,
                title: 'Список',
                description: 'Компактный вид',
                isSelected: settings.displayFormat == DisplayFormat.list,
                onTap: () => provider.setDisplayFormat(DisplayFormat.list),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildFormatCard(
                context,
                icon: Icons.grid_view_rounded,
                title: 'Сетка',
                description: 'Обзор пар',
                isSelected: settings.displayFormat == DisplayFormat.grid,
                onTap: () => provider.setDisplayFormat(DisplayFormat.grid),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.2),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 32,
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        color: isSelected
                            ? Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer
                                .withValues(alpha: 0.8)
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context, PersonalizationSettings settings) {
    // Создаем пример карточки занятия
    final exampleItem = ScheduleItem(
      group: '383',
      lessonNumber: 1,
      subgroup: null,
      subject: 'Программирование',
      teacher: 'Иванов И.И.',
      classroom: '205',
    );
    final exampleDate = DateTime.now();

    return Card(
      elevation: 0,
      color:
          Theme.of(context).colorScheme.surfaceVariant.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (settings.displayFormat == DisplayFormat.list)
              // Показываем список
              ScheduleItemCard(
                item: exampleItem,
                date: exampleDate,
                index: 0,
                isCompact: false,
              )
            else
              // Показываем сетку
              SizedBox(
                height: 200,
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: 2,
                  itemBuilder: (context, index) {
                    return ScheduleItemCard(
                      item: ScheduleItem(
                        group: '383',
                        lessonNumber: index + 1,
                        subgroup: null,
                        subject: index == 0 ? 'Программирование' : 'Математика',
                        teacher: 'Иванов И.И.',
                        classroom: '205',
                      ),
                      date: exampleDate,
                      index: index,
                      isCompact: true,
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Text(
              settings.displayFormat == DisplayFormat.list
                  ? 'Так будет выглядеть карточка занятия'
                  : 'Так будет выглядеть расписание в сетке',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showResetDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.restart_alt,
          color: Theme.of(context).colorScheme.primary,
          size: 32,
        ),
        title: const Text('Сбросить настройки?'),
        content: const Text(
          'Все настройки персонализации будут возвращены к значениям по умолчанию.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              context.read<PersonalizationProvider>().resetSettings();
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Настройки сброшены'),
                  behavior: SnackBarBehavior.floating,
                  action: SnackBarAction(
                    label: 'OK',
                    onPressed: () {},
                  ),
                ),
              );
            },
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
  }

  void _showColorPicker(
      BuildContext context, PersonalizationProvider provider) {
    Color pickerColor = provider.settings.seedColor;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выберите цвет'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (color) {
              pickerColor = color;
            },
            pickerAreaHeightPercent: 0.8,
            enableAlpha: false,
            displayThumbColor: true,
            showLabel: true, // Show hex code
            labelTypes: const [], // Default shows all, or we can customize
            paletteType: PaletteType.hsvWithHue,
            hexInputBar: true, // Enable HEX input
          ),
        ),
        actions: <Widget>[
          TextButton(
            child: const Text('Отмена'),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
          FilledButton(
            child: const Text('Выбрать'),
            onPressed: () {
              provider.setCustomTheme(pickerColor);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}
