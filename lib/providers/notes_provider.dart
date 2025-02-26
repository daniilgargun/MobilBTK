import 'package:flutter/foundation.dart';
import '../models/note_model.dart';
import '../services/database_service.dart';

class NotesProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  Map<String, Note> _notes = {};
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  bool hasNoteForDate(DateTime date) {
    final dateStr = date.toIso8601String().split('T')[0];
    return _notes.containsKey(dateStr);
  }

  Note? getNote(DateTime date) {
    final dateStr = date.toIso8601String().split('T')[0];
    return _notes[dateStr];
  }

  Future<void> saveNote(Note note) async {
    final dateStr = note.date.toIso8601String().split('T')[0];
    _notes[dateStr] = note;
    await _db.saveNote(note);
    notifyListeners();
  }

  Future<void> loadNotes() async {
    if (_isLoaded) return; // Загружаем только один раз
    
    final notes = await _db.getNotes();
    _notes = {
      for (var note in notes)
        note.date.toIso8601String().split('T')[0]: note
    };
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> deleteNote(DateTime date) async {
    final dateStr = date.toIso8601String().split('T')[0];
    _notes.remove(dateStr);
    await _db.deleteNote(date);
    notifyListeners();
  }
} 