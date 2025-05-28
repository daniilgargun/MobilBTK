import 'package:flutter/material.dart';

// Модель для игровой клетки
class Cell {
  bool isFilled = false;
  Color color = Colors.transparent;
  
  // Конструктор по умолчанию
  Cell();
  
  // Конструктор для создания клетки из JSON
  Cell.fromJson(Map<String, dynamic> json)
      : isFilled = json['isFilled'] ?? false,
        color = json['color'] != null
            ? Color(json['color'])
            : Colors.transparent;
  
  // Метод для преобразования в JSON
  Map<String, dynamic> toJson() => {
    'isFilled': isFilled,
    'color': color.value,
  };
} 