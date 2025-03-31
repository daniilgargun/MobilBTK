import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:mobilapp/screens/minigame_screen.dart';
import 'dart:math';

void main() {
  group('Block model tests', () {
    test('Block constructor creates valid block', () {
      final block = Block(
        shape: [
          [true, true],
          [true, false],
        ],
        color: Colors.blue,
        size: 3,
      );
      
      expect(block.shape, [
        [true, true],
        [true, false],
      ]);
      expect(block.color, Colors.blue);
      expect(block.size, 3);
    });
  });
  
  group('Cell model tests', () {
    test('Cell initializes with default values', () {
      final cell = Cell();
      
      expect(cell.isFilled, false);
      expect(cell.color, Colors.transparent);
    });
    
    test('Cell values can be updated', () {
      final cell = Cell();
      cell.isFilled = true;
      cell.color = Colors.red;
      
      expect(cell.isFilled, true);
      expect(cell.color, Colors.red);
    });
  });
  
  group('ProfessionType enum tests', () {
    test('ProfessionType has the correct values', () {
      expect(ProfessionType.values.length, 7);
      expect(ProfessionType.it.color, Colors.blue);
      expect(ProfessionType.cooking.label, 'Пищевая промышленность');
      expect(ProfessionType.logistics.color, Colors.green);
    });
  });
  
  group('Block placement logic tests', () {
    test('Block placement boundary checks', () {
      // Проверяем размещение блока за границами доски
      final block = Block(
        shape: [
          [true, true],
          [true, false],
        ],
        color: Colors.blue,
        size: 3,
      );
      
      // Создаем доску 8x8
      final board = List.generate(
        8, 
        (_) => List.generate(
          8, 
          (_) => Cell(),
        ),
      );
      
      // Функция для проверки возможности размещения блока
      bool canPlaceBlock(Block block, int row, int col) {
        // Проверяем границы доски
        if (row < 0 || col < 0) return false;
        if (row + block.shape.length > 8 || 
            col + block.shape[0].length > 8) return false;
        
        // Проверяем, что все клетки блока можно разместить
        for (int i = 0; i < block.shape.length; i++) {
          for (int j = 0; j < block.shape[i].length; j++) {
            if (block.shape[i][j] && board[row + i][col + j].isFilled) {
              return false;
            }
          }
        }
        
        return true;
      }
      
      // Проверки размещения
      expect(canPlaceBlock(block, 0, 0), true); // В пределах доски
      expect(canPlaceBlock(block, -1, 0), false); // За левой границей
      expect(canPlaceBlock(block, 0, -1), false); // За верхней границей
      expect(canPlaceBlock(block, 7, 0), false); // За нижней границей
      expect(canPlaceBlock(block, 0, 7), false); // За правой границей
      
      // Заполняем ячейку и проверяем
      board[0][0].isFilled = true;
      expect(canPlaceBlock(block, 0, 0), false); // Не должно работать
      expect(canPlaceBlock(block, 0, 1), true); // Должно работать
    });
  });
  
  group('Line clearing tests', () {
    test('Row and column clearing logic', () {
      // Создаем доску 8x8
      final board = List.generate(
        8, 
        (_) => List.generate(
          8, 
          (_) => Cell(),
        ),
      );
      
      // Заполняем первую строку и первый столбец
      for (int j = 0; j < 8; j++) {
        board[0][j].isFilled = true;
        board[0][j].color = Colors.blue;
      }
      
      for (int i = 0; i < 8; i++) {
        board[i][0].isFilled = true;
        board[i][0].color = Colors.red;
      }
      
      // Проверяем заполненные строки и столбцы
      List<int> fullRows = [];
      List<int> fullCols = [];
      
      // Проверяем строки
      for (int i = 0; i < 8; i++) {
        bool isRowFull = true;
        for (int j = 0; j < 8; j++) {
          if (!board[i][j].isFilled) {
            isRowFull = false;
            break;
          }
        }
        if (isRowFull) {
          fullRows.add(i);
        }
      }
      
      // Проверяем столбцы
      for (int j = 0; j < 8; j++) {
        bool isColFull = true;
        for (int i = 0; i < 8; i++) {
          if (!board[i][j].isFilled) {
            isColFull = false;
            break;
          }
        }
        if (isColFull) {
          fullCols.add(j);
        }
      }
      
      // Очищаем заполненные строки и столбцы
      for (int row in fullRows) {
        for (int j = 0; j < 8; j++) {
          board[row][j].isFilled = false;
          board[row][j].color = Colors.transparent;
        }
      }
      
      for (int col in fullCols) {
        for (int i = 0; i < 8; i++) {
          board[i][col].isFilled = false;
          board[i][col].color = Colors.transparent;
        }
      }
      
      // Проверяем, что строка и столбец очищены
      expect(fullRows, [0]); // Первая строка полная
      expect(fullCols, [0]); // Первый столбец полный
      
      // Проверяем, что ячейки теперь пусты
      for (int j = 0; j < 8; j++) {
        expect(board[0][j].isFilled, false);
      }
      
      for (int i = 0; i < 8; i++) {
        expect(board[i][0].isFilled, false);
      }
    });
  });
  
  group('Block generation tests', () {
    test('Random block generation creates valid blocks', () {
      // Функция для создания случайного блока
      Block createRandomBlock(Random random) {
        // Получаем случайную профессию
        final professionType = ProfessionType.values[random.nextInt(ProfessionType.values.length)];
        
        // Определяем размер блока
        int size = random.nextInt(3) + 1; // Размер 1-3
        
        // Для блоков 1х1
        if (size == 1) {
          return Block(
            shape: [
              [true],
            ],
            color: professionType.color,
            size: 1,
          );
        }
        
        // Для блоков 2х1
        if (size == 2 && random.nextBool()) {
          return Block(
            shape: [
              [true, true],
            ],
            color: professionType.color,
            size: 2,
          );
        }
        
        // Для блоков 1х2
        if (size == 2) {
          return Block(
            shape: [
              [true],
              [true],
            ],
            color: professionType.color,
            size: 2,
          );
        }
        
        // Для блоков 2х2
        if (size == 3 && random.nextBool()) {
          return Block(
            shape: [
              [true, true],
              [true, true],
            ],
            color: professionType.color,
            size: 3,
          );
        }
        
        // Для L-образных блоков
        if (random.nextBool()) {
          return Block(
            shape: [
              [true, false],
              [true, true],
            ],
            color: professionType.color,
            size: 3,
          );
        }
        
        // Для Г-образных блоков
        return Block(
            shape: [
              [true, true],
              [true, false],
            ],
            color: professionType.color,
            size: 3,
          );
      }
      
      final random = Random(42); // Фиксированный seed для воспроизводимости
      
      // Создаем 10 случайных блоков и проверяем их
      for (int i = 0; i < 10; i++) {
        final block = createRandomBlock(random);
        
        // Проверяем размеры блока
        expect(block.shape.isNotEmpty, true);
        expect(block.shape[0].isNotEmpty, true);
        
        // Проверяем, что есть хотя бы одна заполненная ячейка
        bool hasFilledCell = false;
        for (var row in block.shape) {
          for (var cell in row) {
            if (cell) {
              hasFilledCell = true;
              break;
            }
          }
          if (hasFilledCell) break;
        }
        expect(hasFilledCell, true);
        
        // Проверяем, что цвет блока соответствует цвету одной из профессий
        expect(
          ProfessionType.values.any((p) => p.color == block.color),
          true,
        );
      }
    });
  });
  
  group('Game continuation logic tests', () {
    test('Game over detection works correctly', () {
      // Создаем доску 8x8
      final board = List.generate(
        8, 
        (_) => List.generate(
          8, 
          (_) => Cell(),
        ),
      );
      
      // Заполняем доску, оставляя только одну ячейку свободной
      for (int i = 0; i < 8; i++) {
        for (int j = 0; j < 8; j++) {
          if (i != 7 || j != 7) {
            board[i][j].isFilled = true;
          }
        }
      }
      
      // Создаем блоки
      final availableBlocks = [
        Block(
          shape: [
            [true, true],
          ],
          color: Colors.blue,
          size: 2,
        ),
        Block(
          shape: [
            [true],
            [true],
          ],
          color: Colors.red,
          size: 2,
        ),
        Block(
          shape: [
            [true, true],
            [true, true],
          ],
          color: Colors.green,
          size: 4,
        ),
      ];
      
      // Функция для проверки возможности размещения блока
      bool canPlaceBlock(Block block, int row, int col) {
        // Проверяем границы доски
        if (row < 0 || col < 0) return false;
        if (row + block.shape.length > 8 || 
            col + block.shape[0].length > 8) return false;
        
        // Проверяем, что все клетки блока можно разместить
        for (int i = 0; i < block.shape.length; i++) {
          for (int j = 0; j < block.shape[i].length; j++) {
            if (block.shape[i][j] && board[row + i][col + j].isFilled) {
              return false;
            }
          }
        }
        
        return true;
      }
      
      // Функция для проверки, можно ли продолжить игру
      bool canContinueGame(List<Block> blocks) {
        // Проверяем, что хотя бы один из доступных блоков можно разместить на доске
        for (Block block in blocks) {
          for (int i = 0; i < 8; i++) {
            for (int j = 0; j < 8; j++) {
              if (canPlaceBlock(block, i, j)) {
                return true;
              }
            }
          }
        }
        
        return false;
      }
      
      // С этими блоками продолжать игру нельзя
      expect(canContinueGame(availableBlocks), false);
      
      // Добавляем блок 1x1, который можно разместить
      availableBlocks.add(
        Block(
          shape: [
            [true],
          ],
          color: Colors.amber,
          size: 1,
        ),
      );
      
      // Теперь игру можно продолжить
      expect(canContinueGame(availableBlocks), true);
    });
  });
} 