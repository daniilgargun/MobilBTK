/*
 * Copyright (c) 2024 Daniil Gargun. All rights reserved.
 * Author: Daniil Gargun | Telegram: @Daniilgargun | Email: daniilgorgun38@gmail.com
 */

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/schedule_model.dart';

/// Кто пользуется приложением.
enum ProfileRole {
  student,
  teacher;

  String get storageKey => name;

  String get label => this == ProfileRole.student ? 'Студент' : 'Преподаватель';

  static ProfileRole? fromStorage(String? value) {
    for (final role in ProfileRole.values) {
      if (role.storageKey == value) return role;
    }
    return null;
  }
}

/// Кем пользователь себя назначил: номер группы или фамилия преподавателя.
///
/// Нужен там, где «своё» расписание надо отличить от чужого: уведомления об
/// изменениях и напоминания о парах. Раньше вместо профиля использовался
/// последний поисковый запрос — он меняется, когда человек просто посмотрел
/// расписание однокурсника, и на такое опираться нельзя.
@immutable
class UserProfile {
  final ProfileRole role;

  /// Номер группы или фамилия преподавателя — как они написаны в расписании.
  final String value;

  const UserProfile({required this.role, required this.value});

  /// Относится ли занятие к этому профилю.
  ///
  /// Сравнение точное, а не по подстроке: в колледже номера групп и
  /// кабинетов пересекаются (есть и группа 209, и кабинет 209), и поиск
  /// по подстроке уже приводил к тому, что группе показывали чужие пары.
  bool matches(ScheduleItem item) {
    switch (role) {
      case ProfileRole.student:
        return item.group.trim().toLowerCase() == value.trim().toLowerCase();
      case ProfileRole.teacher:
        return item.teacher.trim().toLowerCase() == value.trim().toLowerCase();
    }
  }

  String get description => '${role.label} · $value';

  @override
  bool operator ==(Object other) =>
      other is UserProfile && other.role == role && other.value == value;

  @override
  int get hashCode => Object.hash(role, value);
}

/// Хранит профиль в `SharedPreferences`.
///
/// Именно там, а не в провайдере: профиль читает изолят фоновой задачи
/// Workmanager, где ни провайдеров, ни состояния приложения нет.
class UserProfileService {
  static final UserProfileService _instance = UserProfileService._internal();
  factory UserProfileService() => _instance;
  UserProfileService._internal();

  static const String _roleKey = 'profile_role';
  static const String _valueKey = 'profile_value';

  final ValueNotifier<UserProfile?> _profile = ValueNotifier<UserProfile?>(
    null,
  );

  /// Текущий профиль. null — пользователь его ещё не выбрал.
  UserProfile? get profile => _profile.value;

  /// Для виджетов, которым надо перерисоваться при смене профиля.
  ValueListenable<UserProfile?> get listenable => _profile;

  /// Читает профиль из хранилища.
  Future<UserProfile?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _profile.value = readFrom(
        prefs.getString(_roleKey),
        prefs.getString(_valueKey),
      );
    } catch (e) {
      debugPrint('⚠️ Не удалось прочитать профиль: $e');
      _profile.value = null;
    }
    return _profile.value;
  }

  /// Сохраняет профиль; null очищает его.
  Future<void> save(UserProfile? profile) async {
    _profile.value = profile;

    final prefs = await SharedPreferences.getInstance();
    if (profile == null) {
      await prefs.remove(_roleKey);
      await prefs.remove(_valueKey);
      return;
    }

    await prefs.setString(_roleKey, profile.role.storageKey);
    await prefs.setString(_valueKey, profile.value);
  }

  /// Собирает профиль из пары сохранённых строк.
  @visibleForTesting
  static UserProfile? readFrom(String? role, String? value) {
    final parsedRole = ProfileRole.fromStorage(role);
    final trimmed = value?.trim() ?? '';
    if (parsedRole == null || trimmed.isEmpty) return null;
    return UserProfile(role: parsedRole, value: trimmed);
  }
}
