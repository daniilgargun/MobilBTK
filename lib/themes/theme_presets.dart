import 'package:flutter/material.dart';

/// Предустановленные цветовые схемы для тем
class ThemePresets {
  static const Map<String, Color> presets = {
    'Синяя': Colors.blue,
    'Зеленая': Colors.green,
    'Фиолетовая': Colors.purple,
    'Оранжевая': Colors.orange,
    'Красная': Colors.red,
    'Бирюзовая': Colors.teal,
    'Розовая': Colors.pink,
  };

  /// Получает ColorScheme по имени темы
  static ColorScheme getColorScheme(String themeName, Brightness brightness) {
    final seedColor = presets[themeName] ?? Colors.blue;
    return ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
  }

  /// Получает список всех доступных тем
  static List<String> get availableThemes => presets.keys.toList();

  /// Получает цвет по имени темы
  static Color? getColor(String themeName) {
    return presets[themeName];
  }
}
