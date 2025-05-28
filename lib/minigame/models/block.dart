import 'package:flutter/material.dart';

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