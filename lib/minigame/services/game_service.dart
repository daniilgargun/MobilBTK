import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math' show Random;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class GameService {
  static const String _gameStateKey = 'minigame_state';
  static const String _highScoreKey = 'minigame_high_score';
  static const String _cookiesKey = 'minigame_cookies';
  static const String _adLivesKey = 'minigame_ad_lives';
  static const String _cookieLivesKey = 'minigame_cookie_lives';
  
  // Сохранение состояния игры
  static Future<bool> saveGameState({
    required List<List<Cell>> board,
    required int score,
    required int level,
    required GameState gameState,
    required List<Block> availableBlocks,
    required int placedBlocksCount,
    required List<bool> usedBlocks,
    required int blocksUsedCount,
    int comboCounter = 0,
    bool hasRecentlyCleared = false,
    int lastPlacedBlocksCount = 0,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final jsonBoard = board.map((row) => 
        row.map((cell) => cell.toJson()).toList()
      ).toList();
      
      final jsonBlocks = availableBlocks.map((block) => block.toJson()).toList();
      
      final gameStateJson = jsonEncode({
        'board': jsonBoard,
        'score': score,
        'level': level,
        'gameState': gameState.index,
        'availableBlocks': jsonBlocks,
        'placedBlocksCount': placedBlocksCount,
        'usedBlocks': usedBlocks,
        'blocksUsedCount': blocksUsedCount,
        'comboCounter': comboCounter,
        'hasRecentlyCleared': hasRecentlyCleared,
        'lastPlacedBlocksCount': lastPlacedBlocksCount,
      });
      
      return await prefs.setString(_gameStateKey, gameStateJson);
    } catch (e) {
      debugPrint('Ошибка при сохранении состояния игры: $e');
      return false;
    }
  }
  
  // Загрузка состояния игры
  static Future<Map<String, dynamic>?> loadGameState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final gameStateJson = prefs.getString(_gameStateKey);
      
      if (gameStateJson == null) {
        return null;
      }
      
      final decoded = jsonDecode(gameStateJson);
      
      // Конвертируем обратно board
      final List<dynamic> jsonBoard = decoded['board'];
      final List<List<Cell>> board = jsonBoard.map((row) {
        return List<Cell>.from(
          row.map((cellJson) => Cell.fromJson(cellJson))
        );
      }).toList();
      
      // Конвертируем обратно blocks
      final List<dynamic> jsonBlocks = decoded['availableBlocks'];
      final List<Block> availableBlocks = jsonBlocks.map((blockJson) {
        return Block.fromJson(blockJson);
      }).toList();
      
      return {
        'board': board,
        'score': decoded['score'],
        'level': decoded['level'],
        'gameState': GameState.values[decoded['gameState']],
        'availableBlocks': availableBlocks,
        'placedBlocksCount': decoded['placedBlocksCount'],
        'usedBlocks': decoded['usedBlocks'] ?? List.filled(3, false),
        'blocksUsedCount': decoded['blocksUsedCount'] ?? 0,
        'comboCounter': decoded['comboCounter'] ?? 0,
        'hasRecentlyCleared': decoded['hasRecentlyCleared'] ?? false,
        'lastPlacedBlocksCount': decoded['lastPlacedBlocksCount'] ?? 0,
      };
    } catch (e) {
      debugPrint('Ошибка при загрузке состояния игры: $e');
      return null;
    }
  }
  
  // Удаление сохраненного состояния игры
  static Future<bool> clearSavedGame() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove(_gameStateKey);
    } catch (e) {
      debugPrint('Ошибка при удалении сохраненного состояния игры: $e');
      return false;
    }
  }
  
  // Сохранение рекорда
  static Future<bool> saveHighScore(int score) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentHighScore = prefs.getInt(_highScoreKey) ?? 0;
      
      if (score > currentHighScore) {
        return await prefs.setInt(_highScoreKey, score);
      }
      
      return true;
    } catch (e) {
      debugPrint('Ошибка при сохранении рекорда: $e');
      return false;
    }
  }
  
  // Получение рекорда
  static Future<int> getHighScore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_highScoreKey) ?? 0;
    } catch (e) {
      debugPrint('Ошибка при получении рекорда: $e');
      return 0;
    }
  }
  
  // Создание случайного блока
  static Block createRandomBlock() {
    final random = Random();
    // Получаем случайную профессию
    final professionType = ProfessionType.values[random.nextInt(ProfessionType.values.length)];
    // Предполагаем, что тема темная
    final color = professionType.getColor(true);
    
    // Определяем тип блока с большим разнообразием
    final int blockType = random.nextInt(16); // Увеличиваем разнообразие до 16 типов блоков
    
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
    
    // Для L-образных блоков 2x2
    if (blockType == 3) {
      return Block(
        shape: [
          [true, false],
          [true, true],
        ],
        color: color,
        size: 3,
      );
    }
    
    // Для перевернутых L-образных блоков 2x2
    if (blockType == 4) {
      return Block(
        shape: [
          [false, true],
          [true, true],
        ],
        color: color,
        size: 3,
      );
    }
    
    // Для блоков 2x2
    if (blockType == 5) {
      return Block(
        shape: [
          [true, true],
          [true, true],
        ],
        color: color,
        size: 4,
      );
    }
    
    // Для T-образных блоков
    if (blockType == 6) {
      return Block(
        shape: [
          [true, true, true],
          [false, true, false],
        ],
        color: color,
        size: 4,
      );
    }
    
    // Для перевернутых T-образных блоков
    if (blockType == 7) {
      return Block(
        shape: [
          [false, true, false],
          [true, true, true],
        ],
        color: color,
        size: 4,
      );
    }
    
    // Для Z-образных блоков
    if (blockType == 8) {
      return Block(
        shape: [
          [true, true, false],
          [false, true, true],
        ],
        color: color,
        size: 4,
      );
    }
    
    // Для S-образных блоков
    if (blockType == 9) {
      return Block(
        shape: [
          [false, true, true],
          [true, true, false],
        ],
        color: color,
        size: 4,
      );
    }
    
    // Для длинных блоков 1x3
    if (blockType == 10) {
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
    
    // Для длинных блоков 3x1
    if (blockType == 11) {
      return Block(
        shape: [
          [true, true, true],
        ],
        color: color,
        size: 3,
      );
    }
    
    // Для L-образных блоков 3x2
    if (blockType == 12) {
      return Block(
        shape: [
          [true, false],
          [true, false],
          [true, true],
        ],
        color: color,
        size: 5,
      );
    }
    
    // Для перевернутых L-образных блоков 3x2
    if (blockType == 13) {
      return Block(
        shape: [
          [false, true],
          [false, true],
          [true, true],
        ],
        color: color,
        size: 5,
      );
    }
    
    // Для фигуры в виде плюса
    if (blockType == 14) {
      return Block(
        shape: [
          [false, true, false],
          [true, true, true],
          [false, true, false],
        ],
        color: color,
        size: 5,
      );
    }
    
    // Для блоков 1x4 (по умолчанию)
    return Block(
      shape: [
        [true, true, true, true],
      ],
      color: color,
      size: 4,
    );
  }
  
  // Получение количества печенек
  static Future<int> getCookies() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_cookiesKey) ?? 0;
    } catch (e) {
      debugPrint('Ошибка при получении печенек: $e');
      return 0;
    }
  }
  
  // Сохранение количества печенек
  static Future<bool> saveCookies(int cookies) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setInt(_cookiesKey, cookies);
    } catch (e) {
      debugPrint('Ошибка при сохранении печенек: $e');
      return false;
    }
  }
  
  // Добавление печенек
  static Future<int> addCookies(int amount) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentCookies = prefs.getInt(_cookiesKey) ?? 0;
      final newCookies = currentCookies + amount;
      await prefs.setInt(_cookiesKey, newCookies);
      return newCookies;
    } catch (e) {
      debugPrint('Ошибка при добавлении печенек: $e');
      return -1;
    }
  }
  
  // Использование печенек
  static Future<bool> useCookies(int amount) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentCookies = prefs.getInt(_cookiesKey) ?? 0;
      
      if (currentCookies < amount) {
        return false; // Недостаточно печенек
      }
      
      await prefs.setInt(_cookiesKey, currentCookies - amount);
      return true;
    } catch (e) {
      debugPrint('Ошибка при использовании печенек: $e');
      return false;
    }
  }
  
  // Получение количества оставшихся воскрешений через рекламу
  static Future<int> getAdLives() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_adLivesKey) ?? 2; // По умолчанию 2 воскрешения
    } catch (e) {
      debugPrint('Ошибка при получении рекламных воскрешений: $e');
      return 0;
    }
  }
  
  // Использование воскрешения через рекламу
  static Future<bool> useAdLife() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final adLives = prefs.getInt(_adLivesKey) ?? 2;
      
      if (adLives <= 0) {
        return false; // Нет доступных воскрешений через рекламу
      }
      
      await prefs.setInt(_adLivesKey, adLives - 1);
      return true;
    } catch (e) {
      debugPrint('Ошибка при использовании рекламного воскрешения: $e');
      return false;
    }
  }
  
  // Получение количества дополнительных воскрешений через печеньки
  static Future<int> getCookieLives() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_cookieLivesKey) ?? 2; // По умолчанию 2 воскрешения
    } catch (e) {
      debugPrint('Ошибка при получении воскрешений через печеньки: $e');
      return 0;
    }
  }
  
  // Использование воскрешения через печеньки
  static Future<bool> useCookieLife() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookieLives = prefs.getInt(_cookieLivesKey) ?? 2;
      
      if (cookieLives <= 0) {
        return false; // Нет доступных воскрешений через печеньки
      }
      
      await prefs.setInt(_cookieLivesKey, cookieLives - 1);
      return true;
    } catch (e) {
      debugPrint('Ошибка при использовании воскрешения через печеньки: $e');
      return false;
    }
  }
  
  // Сброс воскрешений (вызывается при старте нового дня)
  static Future<bool> resetLives() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_adLivesKey, 2);
      await prefs.setInt(_cookieLivesKey, 2);
      return true;
    } catch (e) {
      debugPrint('Ошибка при сбросе воскрешений: $e');
      return false;
    }
  }
  
  // Обновление количества жизней при начале новой игры
  static Future<bool> updateLivesForNewGame() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_adLivesKey, 2);
      await prefs.setInt(_cookieLivesKey, 2);
      return true;
    } catch (e) {
      debugPrint('Ошибка при обновлении жизней для новой игры: $e');
      return false;
    }
  }
} 