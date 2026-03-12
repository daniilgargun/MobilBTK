import 'package:flutter/material.dart';
import '../models/personalization_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/home_widget_service.dart';

/// Провайдер для управления настройками персонализации
class PersonalizationProvider extends ChangeNotifier {
  PersonalizationSettings _settings = PersonalizationSettings();

  PersonalizationSettings get settings => _settings;

  PersonalizationProvider() {
    _loadSettings();
  }

  /// Загружает настройки из SharedPreferences
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString('personalization_settings');

      if (settingsJson != null) {
        final json = jsonDecode(settingsJson) as Map<String, dynamic>;
        _settings = PersonalizationSettings.fromJson(json);
        // Sync color to widget on load
        HomeWidgetService.saveWidgetColor(_settings.seedColor.toARGB32());
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Ошибка загрузки настроек персонализации: $e');
    }
  }

  /// Сохраняет настройки в SharedPreferences
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = jsonEncode(_settings.toJson());
      await prefs.setString('personalization_settings', settingsJson);
    } catch (e) {
      debugPrint('Ошибка сохранения настроек персонализации: $e');
    }
  }

  /// Устанавливает основной цвет темы
  Future<void> setSeedColor(Color color) async {
    _settings = _settings.copyWith(seedColor: color);
    await _saveSettings();
    await HomeWidgetService.saveWidgetColor(color.toARGB32());
    notifyListeners();
  }

  /// Устанавливает формат отображения
  Future<void> setDisplayFormat(DisplayFormat format) async {
    _settings = _settings.copyWith(displayFormat: format);
    await _saveSettings();
    notifyListeners();
  }

  /// Устанавливает предустановленную тему
  Future<void> setThemePreset(String themeName) async {
    _settings = _settings.copyWith(themePreset: themeName);
    await _saveSettings();
    notifyListeners();
  }

  /// Обновляет все настройки сразу
  Future<void> updateSettings(PersonalizationSettings newSettings) async {
    _settings = newSettings;
    await _saveSettings();
    await HomeWidgetService.saveWidgetColor(_settings.seedColor.toARGB32());
    notifyListeners();
  }

  /// Сбрасывает настройки к значениям по умолчанию
  Future<void> resetSettings() async {
    _settings = PersonalizationSettings();
    await _saveSettings();
    await HomeWidgetService.saveWidgetColor(_settings.seedColor.toARGB32());
    notifyListeners();
  }

  /// Устанавливает кастомную цветовую тему
  Future<void> setCustomTheme(Color color) async {
    _settings = _settings.copyWith(seedColor: color, themePreset: 'Custom');
    await _saveSettings();
    await HomeWidgetService.saveWidgetColor(color.toARGB32());
    notifyListeners();
  }
}
