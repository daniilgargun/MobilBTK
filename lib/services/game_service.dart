import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game_models.dart';

class GameService {
  static const int boardSize = 8; // Размер доски
  static const int maxBlockCount = 3; // Максимум блоков для выбора
  
  // Сохраняем состояние игры
  static Future<void> saveGameState({
    required List<List<Cell>> board,
    required List<Block> availableBlocks,
    required int score,
    required int placedBlocksCount,
    required GameState gameState,
  }) async {
    if (gameState != GameState.playing) return;
    
    final prefs = await SharedPreferences.getInstance();
    
    // Сохраняем игровую доску
    final boardJson = board.map((row) => 
      row.map((cell) => cell.toJson()).toList()
    ).toList();
    
    // Сохраняем доступные блоки
    final blocksJson = availableBlocks.map((block) => block.toJson()).toList();
    
    // Создаем полный объект состояния игры
    final gameStateJson = {
      'board': boardJson,
      'availableBlocks': blocksJson,
      'score': score,
      'placedBlocksCount': placedBlocksCount,
      'gameState': gameState.index,
    };
    
    // Сохраняем данные как строку JSON
    await prefs.setString('minigame_saved_state', jsonEncode(gameStateJson));
  }
  
  // Загружаем состояние игры
  static Future<Map<String, dynamic>> loadGameState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedStateJson = prefs.getString('minigame_saved_state');
    
    if (savedStateJson == null) {
      throw Exception('Нет сохраненного состояния игры');
    }
    
    final gameStateMap = jsonDecode(savedStateJson) as Map<String, dynamic>;
    return gameStateMap;
  }
  
  // Проверяем наличие сохраненной игры
  static Future<bool> hasSavedGame() async {
    final prefs = await SharedPreferences.getInstance();
    final savedState = prefs.getString('minigame_saved_state');
    if (savedState == null) return false;
    
    try {
      final gameStateMap = jsonDecode(savedState) as Map<String, dynamic>;
      final savedGameState = gameStateMap['gameState'] ?? 0;
      return GameState.values[savedGameState] == GameState.playing;
    } catch (e) {
      return false;
    }
  }
  
  // Сохраняем рекорд
  static Future<void> saveHighScore(int score, int currentHighScore) async {
    if (score <= currentHighScore) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('minigame_high_score', score);
  }
  
  // Загружаем рекорд
  static Future<int> loadHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('minigame_high_score') ?? 0;
  }
  
  // Очистка сохраненной игры
  static Future<void> clearSavedGame() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('minigame_saved_state');
  }
  
  // Создаем случайный блок
  static Block createRandomBlock(bool isDarkMode) {
    final Random random = Random();
    
    // Получаем случайную профессию
    final professionType = ProfessionType.values[random.nextInt(ProfessionType.values.length)];
    final color = professionType.getColor(isDarkMode);
    
    // Определяем размер блока и форму
    final int blockType = random.nextInt(10);
    
    // Для блоков 1х1
    if (blockType == 0) {
      return Block(
        shape: [
          [true],
        ],
        color: color,
        size: 1,
      );
    }
    
    // Для блоков 2х1
    if (blockType == 1) {
      return Block(
        shape: [
          [true, true],
        ],
        color: color,
        size: 2,
      );
    }
    
    // Для блоков 1х2
    if (blockType == 2) {
      return Block(
        shape: [
          [true],
          [true],
        ],
        color: color,
        size: 2,
      );
    }
    
    // Для блоков 2х2
    if (blockType == 3) {
      return Block(
        shape: [
          [true, true],
          [true, true],
        ],
        color: color,
        size: 4,
      );
    }
    
    // Для L-образных блоков
    if (blockType == 4) {
      return Block(
        shape: [
          [true, false],
          [true, false],
          [true, true],
        ],
        color: color,
        size: 4,
      );
    }
    
    // Для Г-образных блоков
    if (blockType == 5) {
      return Block(
        shape: [
          [true, true, true],
          [true, false, false],
        ],
        color: color,
        size: 4,
      );
    }
    
    // 3x1 прямая линия
    if (blockType == 6) {
      return Block(
        shape: [
          [true, true, true],
        ],
        color: color,
        size: 3,
      );
    }
    
    // 1x3 прямая линия
    if (blockType == 7) {
      return Block(
        shape: [
          [true],
          [true],
          [true],
        ],
        color: color,
        size: 3,
      );
    }
    
    // Т-образный блок
    if (blockType == 8) {
      return Block(
        shape: [
          [true, true, true],
          [false, true, false],
        ],
        color: color,
        size: 4,
      );
    }
    
    // Зигзагообразный блок
    return Block(
      shape: [
        [false, true, true],
        [true, true, false],
      ],
      color: color,
      size: 4,
    );
  }
  
  // Проверяем, можно ли разместить блок на доске
  static bool canPlaceBlock(Block block, int row, int col, List<List<Cell>> board) {
    // Проверяем границы доски
    if (row < 0 || col < 0) return false;
    if (row + block.shape.length > boardSize || 
        col + block.shape[0].length > boardSize) return false;
    
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
} 