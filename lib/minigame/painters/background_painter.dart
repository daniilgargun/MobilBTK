import 'package:flutter/material.dart';
import '../models/background_particle.dart';

// Художник для анимированного фона
class BackgroundPainter extends CustomPainter {
  final List<BackgroundParticle> particles;
  final bool isDarkMode;
  
  BackgroundPainter({
    required this.particles,
    required this.isDarkMode,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      // Рисуем частицу как градиентный круг с мягкими краями
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            particle.color.withOpacity(particle.opacity),
            particle.color.withOpacity(0.0),
          ],
          stops: [0.3, 1.0], // Добавляем остановки для более резкого градиента
        ).createShader(Rect.fromCircle(
          center: Offset(particle.x, particle.y),
          radius: particle.size,
        ));
      
      canvas.drawCircle(
        Offset(particle.x, particle.y),
        particle.size,
        paint,
      );
      
      // Рисуем блики для более привлекательного эффекта
      if (particle.size > 4) {
        final blickPaint = Paint()
          ..color = Colors.white.withOpacity(particle.opacity * 0.4)
          ..style = PaintingStyle.fill;
        
        canvas.drawCircle(
          Offset(
            particle.x - particle.size * 0.2,
            particle.y - particle.size * 0.2,
          ),
          particle.size * 0.3,
          blickPaint,
        );
      }
    }
  }
  
  @override
  bool shouldRepaint(covariant BackgroundPainter oldDelegate) {
    return true; // перерисовываем каждый раз
  }
} 