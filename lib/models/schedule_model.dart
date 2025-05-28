// Модель для одной пары в расписании
// Хранит всю инфу о паре:
// - группа
// - номер пары
// - подгруппа (если есть)
// - предмет
// - препод
// - кабинет
class ScheduleItem {
  final String group;
  final int lessonNumber;
  final String? subgroup;
  final String subject;
  final String teacher;
  final String classroom;

  ScheduleItem({
    required this.group,
    required this.lessonNumber,
    this.subgroup,
    required this.subject,
    required this.teacher,
    required this.classroom,
  });

  // Для сохранения в базу
  Map<String, dynamic> toMap() {
    return {
      'group': group,
      'lessonNumber': lessonNumber,
      'subgroup': subgroup,
      'subject': subject,
      'teacher': teacher,
      'classroom': classroom,
    };
  }

  // Для загрузки из базы
  factory ScheduleItem.fromMap(Map<String, dynamic> map) {
    return ScheduleItem(
      group: map['group'],
      lessonNumber: map['lessonNumber'],
      subgroup: map['subgroup'],
      subject: map['subject'],
      teacher: map['teacher'],
      classroom: map['classroom'],
    );
  }

  // Создает копию с измененными полями
  ScheduleItem copyWith({
    String? group,
    int? lessonNumber,
    String? subgroup,
    String? subject,
    String? teacher,
    String? classroom,
  }) {
    return ScheduleItem(
      group: group ?? this.group,
      lessonNumber: lessonNumber ?? this.lessonNumber,
      subgroup: subgroup ?? this.subgroup,
      subject: subject ?? this.subject,
      teacher: teacher ?? this.teacher,
      classroom: classroom ?? this.classroom,
    );
  }
} 

// Модель для настроек подсказок поиска
class SearchSuggestionSettings {
  // Включен ли режим "Избранное" вместо случайных подсказок
  final bool useFavorites;
  
  // Список избранных групп
  final List<String> favoriteGroups;
  
  // Список избранных преподавателей
  final List<String> favoriteTeachers;
  
  // Список избранных кабинетов
  final List<String> favoriteClassrooms;
  
  // Список избранных предметов
  final List<String> favoriteSubjects;
  
  // Настройки отображения категорий
  final bool showGroups;
  final bool showTeachers;
  final bool showClassrooms;
  final bool showSubjects;

  SearchSuggestionSettings({
    this.useFavorites = false,
    this.favoriteGroups = const [],
    this.favoriteTeachers = const [],
    this.favoriteClassrooms = const [],
    this.favoriteSubjects = const [],
    this.showGroups = true,
    this.showTeachers = true,
    this.showClassrooms = true,
    this.showSubjects = true,
  });

  // Создает копию с измененными полями
  SearchSuggestionSettings copyWith({
    bool? useFavorites,
    List<String>? favoriteGroups,
    List<String>? favoriteTeachers,
    List<String>? favoriteClassrooms,
    List<String>? favoriteSubjects,
    bool? showGroups,
    bool? showTeachers,
    bool? showClassrooms,
    bool? showSubjects,
  }) {
    return SearchSuggestionSettings(
      useFavorites: useFavorites ?? this.useFavorites,
      favoriteGroups: favoriteGroups ?? this.favoriteGroups,
      favoriteTeachers: favoriteTeachers ?? this.favoriteTeachers,
      favoriteClassrooms: favoriteClassrooms ?? this.favoriteClassrooms,
      favoriteSubjects: favoriteSubjects ?? this.favoriteSubjects,
      showGroups: showGroups ?? this.showGroups,
      showTeachers: showTeachers ?? this.showTeachers,
      showClassrooms: showClassrooms ?? this.showClassrooms,
      showSubjects: showSubjects ?? this.showSubjects,
    );
  }

  // Преобразование в JSON для сохранения
  Map<String, dynamic> toJson() {
    return {
      'useFavorites': useFavorites,
      'favoriteGroups': favoriteGroups,
      'favoriteTeachers': favoriteTeachers,
      'favoriteClassrooms': favoriteClassrooms,
      'favoriteSubjects': favoriteSubjects,
      'showGroups': showGroups,
      'showTeachers': showTeachers,
      'showClassrooms': showClassrooms,
      'showSubjects': showSubjects,
    };
  }

  // Создание из JSON при загрузке
  factory SearchSuggestionSettings.fromJson(Map<String, dynamic> json) {
    return SearchSuggestionSettings(
      useFavorites: json['useFavorites'] ?? false,
      favoriteGroups: List<String>.from(json['favoriteGroups'] ?? []),
      favoriteTeachers: List<String>.from(json['favoriteTeachers'] ?? []),
      favoriteClassrooms: List<String>.from(json['favoriteClassrooms'] ?? []),
      favoriteSubjects: List<String>.from(json['favoriteSubjects'] ?? []),
      showGroups: json['showGroups'] ?? true,
      showTeachers: json['showTeachers'] ?? true,
      showClassrooms: json['showClassrooms'] ?? true,
      showSubjects: json['showSubjects'] ?? true,
    );
  }
} 

// Модель для хранения текущего выбранного элемента в поиске
class SearchEntity {
  final String name;        // Имя группы/преподавателя/кабинета/предмета
  final EntityType type;    // Тип элемента

  SearchEntity({
    required this.name,
    required this.type,
  });
}

// Перечисление типов поисковых сущностей
enum EntityType {
  group,      // Группа
  teacher,    // Преподаватель
  classroom,  // Кабинет
  subject     // Предмет
} 