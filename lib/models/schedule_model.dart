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