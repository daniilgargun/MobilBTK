import 'package:flutter/material.dart';
import 'dart:math' show Random;

// Модель для фоновых частиц
class BackgroundParticle {
  double x;
  double y;
  double size;
  double speed;
  Color color;
  double opacity;
  
  static final Random random = Random();
  
  BackgroundParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.color,
    required this.opacity,
  });
  
  // Фабричный метод для создания случайной частицы
  static BackgroundParticle createRandom(Size screenSize, bool isDarkMode) {
    final baseColor = isDarkMode ? Colors.white70 : Colors.blue;
    final hueAdjust = (random.nextDouble() * 0.2) - 0.1;
    final colorHsl = HSLColor.fromColor(baseColor);
    final adjustedColor = colorHsl
        .withHue((colorHsl.hue + hueAdjust * 60) % 360)
        .withSaturation(random.nextDouble() * 0.4 + 0.2)
        .withLightness(isDarkMode 
            ? random.nextDouble() * 0.3 + 0.5  // Более светлые для темной темы
            : random.nextDouble() * 0.3 + 0.4) // Более темные для светлой темы
        .toColor();
    
    return BackgroundParticle(
      x: random.nextDouble() * screenSize.width,
      y: random.nextDouble() * screenSize.height,
      size: random.nextDouble() * 6 + 2,
      speed: random.nextDouble() * 0.5 + 0.2,
      color: adjustedColor,
      opacity: random.nextDouble() * 0.4 + 0.2,
    );
  }
  
  // Обновляет позицию частицы
  void update(Size screenSize) {
    y += speed;
    if (y > screenSize.height) {
      y = 0;
      x = random.nextDouble() * screenSize.width;
    }
  }
} 