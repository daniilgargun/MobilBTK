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

// Модель для блока
class Block {
  List<List<bool>> shape; // Форма блока (матрица true/false)
  Color color;
  int size;
  
  Block({required this.shape, required this.color, required this.size});
  
  // Конструктор для создания блока из JSON
  Block.fromJson(Map<String, dynamic> json)
      : shape = (json['shape'] as List)
            .map((row) => (row as List).map((cell) => cell as bool).toList())
            .toList(),
        color = Color(json['color']),
        size = json['size'];
  
  // Метод для преобразования в JSON
  Map<String, dynamic> toJson() => {
    'shape': shape,
    'color': color.value,
    'size': size,
  };
}

// Перечисление профессий для блоков
enum ProfessionType {
  it(Colors.blue, Color(0xFF5E92F3), 'IT и программирование'),
  cooking(Colors.red, Color(0xFFF44336), 'Пищевая промышленность'),
  logistics(Colors.green, Color(0xFF66BB6A), 'Логистика'),
  law(Colors.amber, Color(0xFFFFCA28), 'Правоведение'),
  marketing(Colors.orange, Color(0xFFFF9800), 'Маркетинг'),
  baking(Colors.brown, Color(0xFF8D6E63), 'Хлебобулочные изделия'),
  meat(Colors.deepOrange, Color(0xFFFF5722), 'Мясное производство'),
  electricity(Colors.purple, Color(0xFF9C27B0), 'Электротехника'),
  tourism(Colors.teal, Color(0xFF26A69A), 'Туризм');
  
  final Color lightColor;
  final Color darkColor;
  final String label;
  
  const ProfessionType(this.lightColor, this.darkColor, this.label);
  
  Color getColor(bool isDarkMode) {
    return isDarkMode ? darkColor : lightColor;
  }
}

// Состояния игры
enum GameState {
  notStarted,
  playing,
  gameOver
} 