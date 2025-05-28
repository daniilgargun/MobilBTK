import 'package:flutter/material.dart';
import '../models/game_models.dart';
import '../services/game_service.dart';

// Пейнтер для отображения превью расположения блока на доске
class BlockPreviewPainter extends CustomPainter {
  final Block block;
  final int row;
  final int col;
  final int boardSize;
  final double cellSize;
  final Color color;
  final bool isValid;
  
  BlockPreviewPainter({
    required this.block,
    required this.row,
    required this.col,
    required this.boardSize,
    required this.cellSize,
    required this.color,
    required this.isValid,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final double cellWidth = size.width / boardSize;
    final double cellHeight = size.height / boardSize;
    
    // Определяем цвет подсветки на основе валидности размещения
    final Color fillColor = isValid ? color : Colors.red.withOpacity(0.3);
    final Color borderColor = isValid ? color.withOpacity(0.9) : Colors.red.withOpacity(0.6);
    
    // Создаем кисти для рисования
    final Paint fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
      
    final Paint borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    
    // Рисуем блок на доске
    for (int i = 0; i < block.shape.length; i++) {
      for (int j = 0; j < block.shape[i].length; j++) {
        if (block.shape[i][j]) {
          final Rect rect = Rect.fromLTWH(
            (col + j) * cellWidth,
            (row + i) * cellHeight,
            cellWidth,
            cellHeight,
          );
          
          // Проверяем, что ячейка находится в пределах доски
          if (col + j >= 0 && col + j < boardSize && row + i >= 0 && row + i < boardSize) {
            // Рисуем заполнение
            canvas.drawRRect(
              RRect.fromRectAndRadius(rect.deflate(2), Radius.circular(4)),
              fillPaint,
            );
            
            // Рисуем границу
            canvas.drawRRect(
              RRect.fromRectAndRadius(rect.deflate(2), Radius.circular(4)),
              borderPaint,
            );
            
            // Добавляем внутренний круг для лучшей визуализации
            final double centerX = rect.center.dx;
            final double centerY = rect.center.dy;
            final double radius = cellWidth * 0.25;
            
            canvas.drawCircle(
              Offset(centerX, centerY),
              radius,
              Paint()
                ..color = isValid ? Colors.white.withOpacity(0.7) : Colors.white.withOpacity(0.4)
                ..style = PaintingStyle.fill
            );
          }
        }
      }
    }
  }
  
  @override
  bool shouldRepaint(covariant BlockPreviewPainter oldDelegate) {
    return oldDelegate.row != row || 
           oldDelegate.col != col || 
           oldDelegate.isValid != isValid ||
           oldDelegate.color != color;
  }
} 