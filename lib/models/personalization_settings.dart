import 'package:flutter/material.dart';

/// Формат отображения расписания
enum DisplayFormat {
  list, // Список
  grid, // Сетка
}

/// Модель настроек персонализации интерфейса
class PersonalizationSettings {
  final Color seedColor;
  final DisplayFormat displayFormat;
  final String themePreset; // Название предустановленной темы

  PersonalizationSettings({
    this.seedColor = Colors.blue,
    this.displayFormat = DisplayFormat.list,
    this.themePreset = 'Синяя',
  });

  /// Создает копию с измененными полями
  PersonalizationSettings copyWith({
    Color? seedColor,
    DisplayFormat? displayFormat,
    String? themePreset,
  }) {
    return PersonalizationSettings(
      seedColor: seedColor ?? this.seedColor,
      displayFormat: displayFormat ?? this.displayFormat,
      themePreset: themePreset ?? this.themePreset,
    );
  }

  /// Преобразование в JSON для сохранения
  Map<String, dynamic> toJson() {
    return {
      'seedColor': seedColor.toARGB32(),
      'displayFormat': displayFormat.name,
      'themePreset': themePreset,
    };
  }

  /// Создание из JSON при загрузке
  factory PersonalizationSettings.fromJson(Map<String, dynamic> json) {
    return PersonalizationSettings(
      seedColor: Color(json['seedColor'] ?? Colors.blue.toARGB32()),
      displayFormat: DisplayFormat.values.firstWhere(
        (e) => e.name == json['displayFormat'],
        orElse: () => DisplayFormat.list,
      ),
      themePreset: json['themePreset'] ?? 'Синяя',
    );
  }
}
