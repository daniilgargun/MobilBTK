import 'package:flutter/material.dart';
import '../models/block.dart';

// Painter для отрисовки блока при перетаскивании
class FeedbackBlockPainter extends CustomPainter {
  final Block block;
  final double cellSize;
  final Color color;
  final bool isDarkMode;
  
  FeedbackBlockPainter({
    required this.block,
    required this.cellSize,
    required this.color,
    required this.isDarkMode,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final int rows = block.shape.length;
    final int cols = block.shape[0].length;
    
    // Используем тот же цвет, что и на доске
    final Color blockColor = color;
    
    // Кисть для заполнения
    final Paint fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = blockColor.withOpacity(0.85);
    
    // Кисть для границы
    final Paint borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = blockColor;
    
    // Рисуем ячейки как квадраты с небольшим отступом
    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < cols; j++) {
        if (block.shape[i][j]) {
          // Координаты ячейки
          final double left = j * cellSize;
          final double top = i * cellSize;
          
          // Небольшой отступ для визуального разделения ячеек
          final double margin = 1.0;
          final Rect cellRect = Rect.fromLTWH(
            left + margin, 
            top + margin, 
            cellSize - margin * 2, 
            cellSize - margin * 2
          );
          
          // Рисуем заполнение ячейки
          canvas.drawRRect(
            RRect.fromRectAndRadius(cellRect, Radius.circular(2)),
            fillPaint
          );
          
          // Рисуем границу ячейки
          canvas.drawRRect(
            RRect.fromRectAndRadius(cellRect, Radius.circular(2)),
            borderPaint
          );
        }
      }
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => 
    oldDelegate is! FeedbackBlockPainter ||
    oldDelegate.block != block ||
    oldDelegate.cellSize != cellSize ||
    oldDelegate.color != color ||
    oldDelegate.isDarkMode != isDarkMode;
} 