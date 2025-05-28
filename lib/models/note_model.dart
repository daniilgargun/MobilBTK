// Модель для заметок в календаре
// Просто текст и дата
class Note {
  final DateTime date;
  final String text;

  Note({
    required this.date,
    required this.text,
  });

  // Для сохранения в базу данных
  Map<String, dynamic> toMap() {
    return {
      'date': date.toIso8601String(),
      'text': text,
    };
  }

  // Для загрузки из базы данных
  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      date: DateTime.parse(map['date']),
      text: map['text'],
    );
  }
} 