import 'package:flutter/material.dart';
import '../models/block.dart';
import '../models/models.dart';

// Painter для отображения превью расположения блока на доске
class BlockPreviewPainter extends CustomPainter {
  final Block block;
  final int row;
  final int col;
  final int boardSize;
  final double cellSize;
  final Color color;
  final bool isValid;
  final List<List<Cell>>? board; // Доска для проверки заполненных линий
  
  BlockPreviewPainter({
    required this.block,
    required this.row,
    required this.col,
    required this.boardSize,
    required this.cellSize,
    required this.color,
    required this.isValid,
    this.board,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Не показываем превью если позиция за пределами доски или невалидна
    if (row < 0 || col < 0 || !isValid) return;
    
    // Находим потенциально заполненные ряды и столбцы
    final filledRows = <int>{};
    final filledCols = <int>{};
    
    if (board != null) {
      // Создаем виртуальную копию доски с размещенным блоком
      final List<List<bool>> virtualBoard = List.generate(
        boardSize, 
        (r) => List.generate(
          boardSize, 
          (c) => board![r][c].isFilled,
        ),
      );
      
      // Добавляем блок на виртуальную доску
      for (int i = 0; i < block.shape.length; i++) {
        for (int j = 0; j < block.shape[i].length; j++) {
          if (block.shape[i][j]) {
            final int boardRow = row + i;
            final int boardCol = col + j;
            
            if (boardRow >= 0 && boardRow < boardSize && 
                boardCol >= 0 && boardCol < boardSize) {
              virtualBoard[boardRow][boardCol] = true;
            }
          }
        }
      }
      
      // Проверяем заполненные ряды
      for (int r = 0; r < boardSize; r++) {
        bool isRowFull = true;
        for (int c = 0; c < boardSize; c++) {
          if (!virtualBoard[r][c]) {
            isRowFull = false;
            break;
          }
        }
        if (isRowFull) {
          filledRows.add(r);
        }
      }
      
      // Проверяем заполненные столбцы
      for (int c = 0; c < boardSize; c++) {
        bool isColFull = true;
        for (int r = 0; r < boardSize; r++) {
          if (!virtualBoard[r][c]) {
            isColFull = false;
            break;
          }
        }
        if (isColFull) {
          filledCols.add(c);
        }
      }
    }
    
    // Рисуем подсветку для заполненных рядов и столбцов
    final Paint filledLinePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.yellow.withOpacity(0.3);
    
    // Рисуем подсветку рядов
    for (int r in filledRows) {
      canvas.drawRect(
        Rect.fromLTWH(0, r * cellSize, boardSize * cellSize, cellSize),
        filledLinePaint
      );
    }
    
    // Рисуем подсветку столбцов
    for (int c in filledCols) {
      canvas.drawRect(
        Rect.fromLTWH(c * cellSize, 0, cellSize, boardSize * cellSize),
        filledLinePaint
      );
    }
    
    // Отрисовываем каждую ячейку блока с точным соответствием сетке поля
    for (int i = 0; i < block.shape.length; i++) {
      for (int j = 0; j < block.shape[i].length; j++) {
        if (block.shape[i][j]) {
          final int boardRow = row + i;
          final int boardCol = col + j;
          
          // Проверяем, что ячейка находится в пределах доски
          if (boardRow >= 0 && boardRow < boardSize && 
              boardCol >= 0 && boardCol < boardSize) {
            
            // Точный расчет позиции ячейки по сетке
            final double x = boardCol * cellSize;
            final double y = boardRow * cellSize;
            
            // Небольшой отступ, согласованный с отступом в ячейках доски (1px)
            final double margin = 1.0;
            
            // Создаем прямоугольник для ячейки точно по размерам ячейки доски
            final Rect cellRect = Rect.fromLTWH(
              x + margin, 
              y + margin, 
              cellSize - (margin * 2), 
              cellSize - (margin * 2)
            );
            
            // Рисуем заполнение ячейки с полупрозрачным цветом
            final Paint cellPaint = Paint()
              ..style = PaintingStyle.fill
              ..color = color.withOpacity(0.5);
            
            // Используем тот же радиус закругления, что и в ячейках поля
            canvas.drawRRect(
              RRect.fromRectAndRadius(cellRect, Radius.circular(2)),
              cellPaint
            );
            
            // Рисуем границу ячейки того же цвета, что и основной блок
            final Paint borderPaint = Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0
              ..color = color;
            
            canvas.drawRRect(
              RRect.fromRectAndRadius(cellRect, Radius.circular(2)),
              borderPaint
            );
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(BlockPreviewPainter oldDelegate) =>
      oldDelegate.row != row ||
      oldDelegate.col != col ||
      oldDelegate.isValid != isValid ||
      oldDelegate.block != block;
} 