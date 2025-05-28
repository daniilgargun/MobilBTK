import 'package:flutter/material.dart';

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