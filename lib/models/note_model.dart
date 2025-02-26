class Note {
  final DateTime date;
  final String text;

  Note({
    required this.date,
    required this.text,
  });

  Map<String, dynamic> toMap() {
    return {
      'date': date.toIso8601String(),
      'text': text,
    };
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      date: DateTime.parse(map['date']),
      text: map['text'],
    );
  }
} 