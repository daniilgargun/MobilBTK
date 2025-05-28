import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:math' show Random, sin;
import 'dart:ui';  // Для ImageFilter
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../painters/painters.dart';
import '../widgets/widgets.dart';
import '../services/services.dart';
import '../../services/ads_service.dart';
import 'package:flutter/services.dart';

class MinigameScreen extends StatefulWidget {
  const MinigameScreen({Key? key}) : super(key: key);

  @override
  State<MinigameScreen> createState() => _MinigameScreenState();
}

class _MinigameScreenState extends State<MinigameScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const int boardSize = 10; // Размер игровой доски
  static const int initialBlockCount = 3; // Начальное количество блоков
  
  // Состояние игры
  late List<List<Cell>> board = List.generate(
    boardSize, 
    (_) => List.generate(
      boardSize, 
      (_) => Cell(),
    )
  );
  late List<Block> availableBlocks = List.generate(
    initialBlockCount,
    (_) => GameService.createRandomBlock(),
  );
  int score = 0;
  int highScore = 0;
  int level = 1;
  GameState gameState = GameState.notStarted;
  int placedBlocksCount = 0;
  int comboCounter = 0;
  
  // Переменные для UI
  double cellSize = 30;
  int? draggedBlockIndex;
  Offset? dragPosition;
  int? previewRow;
  int? previewCol;
  bool isValidPlacement = false;
  bool isDarkMode = true;
  
  // Переменные для отслеживания использованных блоков
  List<bool> usedBlocks = List.filled(3, false);
  int blocksUsedCount = 0;
  
  // Анимации
  Timer? linesClearedTimer;
  Timer? gameOverTimer;
  List<Map<String, dynamic>> pointAnimations = [];
  Map<String, dynamic>? comboDisplay;
  
  // Для определения размера доски
  final GlobalKey boardKey = GlobalKey();
  
  // Флаг для отслеживания инициализации
  bool _isInitialized = false;
  
  // Переменные для жизней
  int adLivesLeft = 2; // Количество доступных рекламных воскрешений
  int cookieLivesLeft = 2; // Количество доступных воскрешений через печеньки
  int cookiesAvailable = 0; // Количество доступных печенек
  int cookiesNeeded = 1; // Количество печенек для воскрешения - теперь только 1
  
  // Переменная для отсчета времени до окончания игры
  int _resurrectionCountdown = 10; // Увеличено с 5 до 10 секунд
  Timer? _resurrectionTimer;
  
  // Таймер для отмены загрузки рекламы
  Timer? _adLoadingTimer;
  int _adLoadingTimeout = 15; // 15 секунд на загрузку рекламы
  
  // Переменные для отслеживания комбо в течение 2 ходов
  bool hasRecentlyCleared = false; // Флаг для отслеживания очистки линий в предыдущем ходу
  int lastPlacedBlocksCount = 0; // Для отслеживания изменений в счетчике ходов
  int? lastComboCounter; // Для отслеживания последнего комбо
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initializeGame();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    linesClearedTimer?.cancel();
    gameOverTimer?.cancel();
    _resurrectionTimer?.cancel();
    _adLoadingTimer?.cancel();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Сохраняем игру при сворачивании приложения
      saveGame();
    }
  }
  
  // Добавляем метод для обработки перехода между вкладками
  @override
  void deactivate() {
    // При переходе между вкладками проверяем, не закончилась ли игра
    if (gameState == GameState.gameOver) {
      // Если игра закончена, обеспечиваем, чтобы сохранение не выполнялось
      // и принудительно сбрасываем состояние
      GameService.clearSavedGame();
    } else if (gameState == GameState.waitForResurrection) {
      // Если находимся в ожидании воскрешения, проверяем наличие доступных ходов
      if (!_hasValidMoves()) {
        // Если ходов нет, переключаем на gameOver
        gameState = GameState.gameOver;
        _resurrectionTimer?.cancel();
        _resurrectionTimer = null;
        GameService.clearSavedGame();
      } else {
        // Сохраняем текущее состояние
        saveGame();
      }
    } else {
      // Сохраняем состояние игры при переходе между вкладками
      saveGame();
    }
    super.deactivate();
  }
  
  // Проверяем обновления темы приложения при активации экрана
  @override
  void activate() {
    super.activate();
    // При возвращении на экран обновляем тему из SharedPreferences
    _loadCurrentTheme();
  }
  
  // Метод для загрузки текущей темы из настроек приложения
  Future<void> _loadCurrentTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final currentTheme = prefs.getBool('is_dark_mode');
    
    if (currentTheme != null && currentTheme != isDarkMode) {
      setState(() {
        isDarkMode = currentTheme;
      });
    }
  }
  
  Future<void> initializeGame() async {
    // Загружаем тему
    final prefs = await SharedPreferences.getInstance();
    
    // Загружаем рекорд
    final loadedHighScore = await GameService.getHighScore();
    
    // Загружаем количество печенек и жизней
    final loadedCookies = prefs.getInt('cookie_count') ?? 0; // Берем печеньки из общих настроек приложения
    final loadedAdLives = await GameService.getAdLives();
    final loadedCookieLives = await GameService.getCookieLives();
    
    // Пытаемся загрузить сохраненное состояние игры
    final savedState = await GameService.loadGameState();
    
    if (!mounted) return;

    setState(() {
      // Используем общую тему приложения вместо отдельной настройки
      isDarkMode = prefs.getBool('is_dark_mode') ?? false;
      highScore = loadedHighScore;
      cookiesAvailable = loadedCookies;
      
      if (savedState != null) {
        // Если есть сохраненное состояние игры, используем сохраненные значения для жизней
        adLivesLeft = loadedAdLives;
        cookieLivesLeft = loadedCookieLives;
        
        board = savedState['board'];
        score = savedState['score'];
        level = savedState['level'];
        gameState = savedState['gameState'];
        
        // Исправляем баг: если состояние при загрузке было "ожидание воскрешения" или "gameOver"
        // проверяем, можно ли продолжать игру
        if (gameState == GameState.waitForResurrection || gameState == GameState.gameOver) {
          availableBlocks = savedState['availableBlocks'];
          usedBlocks = List<bool>.from(savedState['usedBlocks'] ?? List.filled(initialBlockCount, false));
          
          // Проверяем наличие валидных ходов
          if (_hasValidMoves()) {
            // Если ходы есть, переводим игру в активное состояние
            gameState = GameState.playing;
          } else {
            // Если ходов нет, завершаем игру
            gameState = GameState.gameOver;
            // Убедимся, что таймер воскрешения остановлен
            _resurrectionTimer?.cancel();
            _resurrectionTimer = null;
          }
        } else if (gameState == GameState.loadingAd) {
          // Если был процесс загрузки рекламы, возвращаем к выбору воскрешения
          gameState = GameState.waitForResurrection;
        }
        
        availableBlocks = savedState['availableBlocks'];
        placedBlocksCount = savedState['placedBlocksCount'];
        usedBlocks = List<bool>.from(savedState['usedBlocks'] ?? List.filled(initialBlockCount, false));
        blocksUsedCount = savedState['blocksUsedCount'] ?? 0;
        comboCounter = savedState['comboCounter'] ?? 0;
        hasRecentlyCleared = savedState['hasRecentlyCleared'] ?? false;
        lastPlacedBlocksCount = savedState['lastPlacedBlocksCount'] ?? 0;
      } else {
        // Если нет сохраненной игры, инициализируем с начальными значениями
        adLivesLeft = 2; // Сбрасываем жизни при новой игре
        cookieLivesLeft = 2; // Сбрасываем жизни при новой игре
        
        board = List.generate(
          boardSize, 
          (_) => List.generate(
            boardSize, 
            (_) => Cell(),
          )
        );
        
        // Создаем стартовый набор блоков
        List<Block> initialBlocks = [];
        
        // Для начала игры даем набор простых блоков разной формы
        // Это обеспечит хороший старт для игрока
        initialBlocks.add(Block(
          shape: [[true]],
          color: ProfessionType.it.getColor(isDarkMode),
          size: 1,
        ));
        
        initialBlocks.add(Block(
          shape: [[true, true]],
          color: ProfessionType.marketing.getColor(isDarkMode),
          size: 2,
        ));
        
        initialBlocks.add(Block(
          shape: [[true], [true]],
          color: ProfessionType.logistics.getColor(isDarkMode),
          size: 2,
        ));
        
        availableBlocks = initialBlocks;
        score = 0;
        level = 1;
        placedBlocksCount = 0;
        comboCounter = 0;
        hasRecentlyCleared = false;
        lastPlacedBlocksCount = 0;
        usedBlocks = List.filled(initialBlockCount, false);
        blocksUsedCount = 0;
        gameState = GameState.notStarted;
        
        // Сохраняем начальное значение жизней в SharedPreferences
        GameService.updateLivesForNewGame();
      }
      
      _isInitialized = true;
    });
    
    // Запускаем таймер для расчета размера ячейки
    WidgetsBinding.instance.addPostFrameCallback((_) {
      calculateCellSize();
    });
  }
  
  void calculateCellSize() {
    if (boardKey.currentContext != null) {
      final RenderBox box = boardKey.currentContext!.findRenderObject() as RenderBox;
      final boardWidth = box.size.width;
      
      // Расчет размера ячейки на основе доступной ширины
      final newCellSize = (boardWidth / boardSize).floorToDouble();
      
      if (newCellSize != cellSize) {
        setState(() {
          cellSize = newCellSize;
        });
      }
    }
  }
  
  void startNewGame() {
    // Сначала очищаем все таймеры
    _resurrectionTimer?.cancel();
    _resurrectionTimer = null;
    
    setState(() {
      // Создаем пустую доску
      board = List.generate(
        boardSize, 
        (_) => List.generate(
          boardSize, 
          (_) => Cell(),
        )
      );
      
      // Создаем начальные блоки
      List<Block> initialBlocks = [];
      
      // Для начала игры даем набор простых блоков разной формы
      initialBlocks.add(Block(
        shape: [[true]],
        color: ProfessionType.it.getColor(isDarkMode),
        size: 1,
      ));
      
      initialBlocks.add(Block(
        shape: [[true, true]],
        color: ProfessionType.marketing.getColor(isDarkMode),
        size: 2,
      ));
      
      initialBlocks.add(Block(
        shape: [[true], [true]],
        color: ProfessionType.logistics.getColor(isDarkMode),
        size: 2,
      ));
      
      availableBlocks = initialBlocks;
      
      // Сбрасываем счетчики использованных блоков
      usedBlocks = List.filled(initialBlockCount, false);
      blocksUsedCount = 0;
      
      // Сбрасываем счетчики
      score = 0;
      level = 1;
      placedBlocksCount = 0;
      comboCounter = 0;
      gameState = GameState.playing; // Сразу начинаем игру, а не notStarted
      
      // Восстанавливаем количество жизней для нового раунда
      adLivesLeft = 2;
      cookieLivesLeft = 2;
      
      // Сохраняем новое состояние игры
      saveGame();
    });
    
    // Обновляем значения жизней в SharedPreferences
    GameService.updateLivesForNewGame();
  }
  
  void saveGame() {
    if (gameState != GameState.gameOver) {
      GameService.saveGameState(
        board: board,
        score: score,
        level: level,
        gameState: gameState,
        availableBlocks: availableBlocks,
        placedBlocksCount: placedBlocksCount,
        usedBlocks: usedBlocks,
        blocksUsedCount: blocksUsedCount,
        comboCounter: comboCounter,
        hasRecentlyCleared: hasRecentlyCleared,
        lastPlacedBlocksCount: lastPlacedBlocksCount,
      );
    } else {
      // Если игра окончена, удаляем сохранение
      GameService.clearSavedGame();
    }
  }
  
  // Начало игры
  void startGame() {
    setState(() {
      gameState = GameState.playing;
    });
  }
  
  // Проверяет, есть ли доступные ходы для текущих блоков
  bool _hasValidMoves() {
    for (int blockIndex = 0; blockIndex < availableBlocks.length; blockIndex++) {
      if (usedBlocks[blockIndex]) continue; // Пропускаем использованные блоки
      
      Block block = availableBlocks[blockIndex];
      
      // Проверяем все возможные позиции на доске
      for (int row = 0; row <= board.length - block.shape.length; row++) {
        for (int col = 0; col <= board[0].length - block.shape[0].length; col++) {
          if (_canPlaceBlockAt(block, row, col)) {
            return true; // Нашли хотя бы одну позицию для размещения блока
          }
        }
      }
    }
    
    return false; // Нет доступных ходов
  }
  
  // Проверяет, можно ли разместить блок в указанной позиции
  bool _canPlaceBlockAt(Block block, int row, int col) {
    for (int i = 0; i < block.shape.length; i++) {
      for (int j = 0; j < block.shape[i].length; j++) {
        if (block.shape[i][j]) {
          // Проверяем, находится ли клетка в пределах доски
          if (row + i >= board.length || col + j >= board[0].length) {
            return false;
          }
          
          // Проверяем, свободна ли клетка
          if (board[row + i][col + j]?.isFilled ?? false) {
            return false;
          }
        }
      }
    }
    
    return true;
  }
  
  // Установка блока на доску
  void placeBlock(int row, int col) {
    if (!isValidPlacement || draggedBlockIndex == null) return;

    final Block block = availableBlocks[draggedBlockIndex!];
    
    // Размещаем блок на игровом поле
    setState(() {
      // Добавляем очки за размещение блока (количество ячеек)
      int blockCells = 0;
      for (int i = 0; i < block.shape.length; i++) {
        for (int j = 0; j < block.shape[i].length; j++) {
          if (block.shape[i][j]) {
            blockCells++;
          }
        }
      }
      score += blockCells;
      placedBlocksCount++;
      
      // Обновляем уровень каждые 5 размещенных блоков
      level = 1 + (placedBlocksCount ~/ 5);
      
      // Помечаем блок как использованный
      usedBlocks[draggedBlockIndex!] = true;
      blocksUsedCount++;
      
      // Добавляем блок на игровое поле - каждая ячейка выравнивается по сетке
      for (int i = 0; i < block.shape.length; i++) {
        for (int j = 0; j < block.shape[i].length; j++) {
          if (block.shape[i][j]) {
            // Проверяем, что мы в пределах доски
            if (row + i >= 0 && row + i < boardSize && 
                col + j >= 0 && col + j < boardSize) {
              // Создаем новую ячейку и заполняем ее
              board[row + i][col + j] = Cell()
                ..isFilled = true
                ..color = block.color;
            }
          }
        }
      }
      
      // Сбрасываем состояние перетаскивания
      draggedBlockIndex = null;
      dragPosition = null;
      previewRow = null;
      previewCol = null;
      
      // Проверяем заполненные линии
      checkLines();
      
      // Проверяем, нужно ли сбросить блоки
      if (blocksUsedCount >= 3) {
        resetBlocks();
        
        // После сброса блоков проверяем, можно ли продолжать игру
        if (!_hasValidMoves()) {
          // Проверяем возможность воскрешения
          if (adLivesLeft > 0 || (cookieLivesLeft > 0 && cookiesAvailable >= cookiesNeeded)) {
            gameState = GameState.waitForResurrection;
          } else {
            gameState = GameState.gameOver;
          }
        }
      } else {
        // Проверяем, закончилась ли игра, если у нас не осталось ходов
        // даже с текущими неиспользованными блоками
        if (!_hasValidMoves()) {
          // Проверяем возможность воскрешения
          if (adLivesLeft > 0 || (cookieLivesLeft > 0 && cookiesAvailable >= cookiesNeeded)) {
            gameState = GameState.waitForResurrection;
          } else {
            gameState = GameState.gameOver;
          }
        }
      }
    });
  }
  
  // Сбрасываем использованные блоки и генерируем новые
  void resetBlocks() {
    // Создаем временный список для хранения новых блоков
    List<Block> newBlocks = [];
    
    // Для каждого использованного блока генерируем новый
    for (int i = 0; i < usedBlocks.length; i++) {
      if (usedBlocks[i]) {
        // Генерируем несколько случайных блоков и выбираем лучший
        List<Block> candidateBlocks = List.generate(
          5, // Генерируем 5 случайных блоков для выбора
          (_) => GameService.createRandomBlock()
        );
        
        // Оцениваем каждый блок
        List<Map<String, dynamic>> blockRatings = [];
        for (var block in candidateBlocks) {
          int complexity = _estimateBlockComplexity(block);
          if (complexity >= 0) { // Блок можно разместить
            blockRatings.add({
              'block': block,
              'complexity': complexity
            });
          }
        }
        
        // Если не нашли подходящих блоков, создаем простой блок 1x1
        if (blockRatings.isEmpty) {
          newBlocks.add(Block(
            shape: [[true]],
            color: GameService.createRandomBlock().color,
            size: 1,
          ));
          continue;
        }
        
        // Сортируем блоки по сложности (от среднего к сложному)
        blockRatings.sort((a, b) => a['complexity'].compareTo(b['complexity']));
        
        // Определяем текущий уровень сложности в зависимости от счета и уровня
        int difficultyIndex = 0;
        
        // Увеличиваем сложность с ростом уровня игрока
        if (level > 2) difficultyIndex = 1;
        if (level > 4) difficultyIndex = 2;
        
        // Для более высоких уровней или если доска почти пуста, выбираем более сложные блоки
        int emptyCells = 0;
        for (var row in board) {
          for (var cell in row) {
            if (!cell.isFilled) emptyCells++;
          }
        }
        
        double boardEmptiness = emptyCells / (boardSize * boardSize);
        if (boardEmptiness > 0.7) { // Если доска более чем на 70% пуста
          difficultyIndex = math.min(difficultyIndex + 1, blockRatings.length - 1);
        }
        
        // Выбираем блок в зависимости от сложности
        Block chosenBlock;
        if (blockRatings.length <= 2) {
          // Если мало вариантов, берем первый доступный
          chosenBlock = blockRatings[0]['block'];
        } else {
          // Иначе выбираем в зависимости от сложности
          int chosenIndex = math.min(difficultyIndex, blockRatings.length - 1);
          chosenBlock = blockRatings[chosenIndex]['block'];
        }
        
        newBlocks.add(chosenBlock);
      } else {
        // Если блок не был использован, оставляем его
        newBlocks.add(availableBlocks[i]);
      }
    }
    
    setState(() {
      blocksUsedCount = 0;
      
      // Обновляем блоки
      for (int i = 0; i < usedBlocks.length; i++) {
        if (usedBlocks[i]) {
          availableBlocks[i] = newBlocks[i];
          usedBlocks[i] = false;
        }
      }
    });
  }
  
  // Сбрасываем блоки после воскрешения
  void resetBlocksAfterResurrection() {
    // Создаем временный список для хранения новых блоков
    List<Block> newBlocks = [];
    
    // После воскрешения даем блоки, которые точно можно разместить
    for (int i = 0; i < availableBlocks.length; i++) {
      // Генерируем несколько вариантов блоков
      List<Block> candidateBlocks = [];
      
      // Всегда добавляем простой блок 1x1 как гарантию
      candidateBlocks.add(Block(
        shape: [[true]],
        color: GameService.createRandomBlock().color,
        size: 1,
      ));
      
      // Добавляем еще несколько простых блоков
      candidateBlocks.add(Block(
        shape: [[true, true]],
        color: GameService.createRandomBlock().color,
        size: 2,
      ));
      
      candidateBlocks.add(Block(
        shape: [[true], [true]],
        color: GameService.createRandomBlock().color,
        size: 2,
      ));
      
      // Добавляем несколько случайных блоков для разнообразия
      for (int j = 0; j < 2; j++) {
        candidateBlocks.add(GameService.createRandomBlock());
      }
      
      // Оцениваем каждый блок
      List<Map<String, dynamic>> blockRatings = [];
      for (var block in candidateBlocks) {
        int complexity = _estimateBlockComplexity(block);
        if (complexity >= 0) { // Блок можно разместить
          blockRatings.add({
            'block': block,
            'complexity': complexity
          });
        }
      }
      
      // Сортируем блоки по сложности (от простого к сложному)
      blockRatings.sort((a, b) => a['complexity'].compareTo(b['complexity']));
      
      // После воскрешения выбираем блоки меньшей сложности, чтобы игрок мог продолжить
      Block chosenBlock;
      if (blockRatings.isEmpty) {
        // Если нет подходящих блоков, создаем простой блок 1x1
        chosenBlock = Block(
          shape: [[true]],
          color: GameService.createRandomBlock().color,
          size: 1,
        );
      } else {
        // Выбираем из более простых блоков, чтобы дать игроку шанс
        int chosenIndex = math.min(0, blockRatings.length - 1); // Всегда берем самый простой
        chosenBlock = blockRatings[chosenIndex]['block'];
      }
      
      newBlocks.add(chosenBlock);
    }
    
    setState(() {
      blocksUsedCount = 0;
      
      // Обновляем все блоки
      for (int i = 0; i < availableBlocks.length; i++) {
        availableBlocks[i] = newBlocks[i];
        usedBlocks[i] = false;
      }
    });
  }
  
  // Проверка заполненных линий
  void checkLines() {
    List<int> fullRows = [];
    List<int> fullCols = [];
    
    // Проверка заполненных строк
    for (int i = 0; i < boardSize; i++) {
      bool isRowFull = true;
      for (int j = 0; j < boardSize; j++) {
        if (!board[i][j].isFilled) {
          isRowFull = false;
          break;
        }
      }
      if (isRowFull) {
        fullRows.add(i);
      }
    }
    
    // Проверка заполненных столбцов
    for (int j = 0; j < boardSize; j++) {
      bool isColFull = true;
      for (int i = 0; i < boardSize; i++) {
        if (!board[i][j].isFilled) {
          isColFull = false;
          break;
        }
      }
      if (isColFull) {
        fullCols.add(j);
      }
    }
    
    // Если есть заполненные линии
    if (fullRows.isNotEmpty || fullCols.isNotEmpty) {
      // Количество очищенных линий в этом ходу
      final int linesCleared = fullRows.length + fullCols.length;
      
      // НОВАЯ ЛОГИКА КОМБО:
      // 1. Если очищено несколько линий за ход, сразу считаем это как комбо
      // 2. Если линии очищены в предыдущем ходу и в текущем - увеличиваем счетчик комбо
      if (linesCleared > 1) {
        // Множественная очистка = сразу считаем как комбо
        comboCounter = math.max(2, comboCounter + 1);
        
        // Запоминаем, что в этом ходу было комбо
        lastComboCounter = comboCounter;
      } else if (hasRecentlyCleared) {
        // Очистка в предыдущем и текущем ходу - увеличиваем счетчик комбо
        // даже если текущая очистка только одна линия
        comboCounter++;
        
        // Здесь мы НЕ перезаписываем hasRecentlyCleared, он уже true
        // от предыдущего хода и должен остаться true
      } else {
        // Просто новая очистка
        comboCounter = 1;
      }
      
      // Устанавливаем флаг, что в этом ходу были очищены линии
      hasRecentlyCleared = true;
      
      // Очищаем линии
      for (int row in fullRows) {
        for (int j = 0; j < boardSize; j++) {
          board[row][j].isFilled = false;
          board[row][j].color = Colors.transparent;
        }
      }
      
      for (int col in fullCols) {
        for (int i = 0; i < boardSize; i++) {
          board[i][col].isFilled = false;
          board[i][col].color = Colors.transparent;
        }
      }
      
      // УЛУЧШЕННАЯ СИСТЕМА НАЧИСЛЕНИЯ ОЧКОВ:
      // 1. Базовые очки за линии увеличены
      // 2. Бонус за комбо значительно увеличен
      // 3. Дополнительный множитель за количество линий
      // 4. Специальный бонус за очистку 4+ линий
      
      // Базовые очки за каждую линию
      final int basePointsPerLine = 15; // Увеличено с 10 до 15
      final int basePoints = linesCleared * basePointsPerLine;
      
      // Бонус за комбо (увеличен)
      int comboBonus = 0;
      if (comboCounter > 1) {
        // Экспоненциальное увеличение бонуса с ростом комбо
        comboBonus = (comboCounter * comboCounter) * 8; // Значительно увеличен множитель
      }
      
      // Множитель за количество линий, очищенных за один ход
      int multiLineMultiplier = 1;
      if (linesCleared > 1) {
        multiLineMultiplier = linesCleared; // Множитель равен количеству линий
      }
      
      // Специальный бонус за большое количество линий за раз
      int specialBonus = 0;
      if (linesCleared >= 4) {
        specialBonus = 100; // Бонус за "тетрис"
      } else if (linesCleared == 3) {
        specialBonus = 50; // Бонус за тройную линию
      }
      
      // Финальный расчет очков
      final int bonusPoints = (basePoints * multiLineMultiplier) + comboBonus + specialBonus;
      
      // Добавляем очки
      score += bonusPoints;
      
      // Отображаем анимацию начисления очков
      if (dragPosition != null) {
        setState(() {
          pointAnimations.add({
            'points': bonusPoints,
            'position': dragPosition!,
            'color': getPointAnimationColor(linesCleared, comboCounter),
          });
        });
      }
      
      // Отображаем комбо, если заработано
      if (comboCounter > 1 || linesCleared > 1) {
        // Показываем комбо для множественных линий или если счетчик комбо > 1
        showComboDisplay(linesCleared, bonusPoints);
      } else if (comboCounter == 1 && hasRecentlyCleared && (lastComboCounter ?? 0) >= 2) {
        // Отображаем комбо только если это одна линия после настоящего комбо
        showComboDisplay(linesCleared, bonusPoints);
      }
      
      // Обновляем рекорд, если нужно
      if (score > highScore) {
        setState(() {
          highScore = score;
        });
        GameService.saveHighScore(highScore);
      }
    } else {
      // Если в текущем ходу не были очищены линии, проверяем статус предыдущего хода
      if (!hasRecentlyCleared) {
        // Сбрасываем комбо, если линии не были очищены в двух последовательных ходах
        comboCounter = 0;
      }
      
      // Сбрасываем флаг очистки для следующего хода
      hasRecentlyCleared = false;
    }
    
    // Запоминаем текущее количество размещенных блоков
    lastPlacedBlocksCount = placedBlocksCount;
  }
  
  // Определение цвета для анимации очков в зависимости от комбо и количества линий
  Color getPointAnimationColor(int linesCleared, int combo) {
    if (combo >= 5) {
      return Colors.purple; // Большое комбо
    } else if (linesCleared >= 4) {
      return Colors.red; // "Тетрис"
    } else if (combo >= 3 || linesCleared >= 3) {
      return Colors.amber; // Хорошее комбо или 3 линии
    } else if (combo >= 2 || linesCleared >= 2) {
      return Colors.orange; // Базовое комбо или 2 линии
    } else {
      return Colors.green; // Обычная очистка
    }
  }
  
  // Отображение комбо
  void showComboDisplay(int linesCleared, int bonusPoints) {
    setState(() {
      // Определяем, является ли очистка одной линии частью комбо-серии
      // Важно: isPartOfSeries должен быть true только если ранее было настоящее комбо (comboCounter >= 2)
      bool isPartOfSeries = linesCleared == 1 && comboCounter >= 1 && hasRecentlyCleared && (lastComboCounter ?? 0) >= 2;
      
      // Добавляем больше информации в комбо-дисплей
      comboDisplay = {
        'comboCount': comboCounter,
        'bonusPoints': bonusPoints,
        'linesCleared': linesCleared,
        'isSpecial': linesCleared >= 3 || comboCounter >= 4, // Флаг для "особого" комбо
        'isPartOfSeries': isPartOfSeries, // Новый флаг для серии
      };
      
      // Запоминаем текущее значение comboCounter для следующей проверки
      lastComboCounter = comboCounter;
      
      // Увеличиваем время отображения для более впечатляющих комбо
      int displayDuration = linesCleared > 1 ? 2 : 1; // Уменьшаем длительность для обычных комбо
      
      // Для серии комбо даем чуть больше времени
      if (isPartOfSeries) {
        displayDuration = 2; // Немного больше стандартной очистки
      }
      
      if (comboCounter >= 4 || linesCleared >= 3) {
        displayDuration = 3; // Больше времени для эффектных комбо
      }
      
      // Добавляем вибрацию для особых комбо
      try {
        if (linesCleared >= 3 || comboCounter >= 4) {
          HapticFeedback.mediumImpact(); // Вибрация для особых комбо
        } else if (linesCleared >= 2 || comboCounter >= 2) {
          HapticFeedback.lightImpact(); // Легкая вибрация для обычных комбо
        }
      } catch (e) {
        // Игнорируем ошибки вибрации
      }
      
      // Скрываем комбо через указанное время
      Future.delayed(Duration(seconds: displayDuration), () {
        if (mounted) {
          setState(() {
            comboDisplay = null;
          });
        }
      });
    });
  }
  
  // Проверка окончания игры с возможностью воскрешения
  void checkGameOver() {
    bool canPlaceAnyBlock = false;
    
    // Проверяем, можно ли разместить хотя бы один блок
    for (Block block in availableBlocks) {
      for (int i = 0; i < boardSize; i++) {
        for (int j = 0; j < boardSize; j++) {
          if (_canPlaceBlockAt(block, i, j)) {
            canPlaceAnyBlock = true;
            break;
          }
        }
        if (canPlaceAnyBlock) break;
      }
      if (canPlaceAnyBlock) break;
    }
    
    // Если нельзя разместить ни один блок
    if (!canPlaceAnyBlock) {
      setState(() {
        // Проверяем возможность воскрешения
        if (adLivesLeft > 0 || (cookieLivesLeft > 0 && cookiesAvailable >= cookiesNeeded)) {
          // Всегда показываем экран воскрешения
          gameState = GameState.waitForResurrection;
        } else {
          // Только если совсем нет воскрешений
          gameState = GameState.gameOver;
        }
        
        // Сохраняем рекорд
        if (score > highScore) {
          setState(() {
            highScore = score;
          });
          GameService.saveHighScore(highScore);
        }
      });
    }
  }
  
  // Метод для воскрешения через рекламу
  Future<void> resurrectWithAd() async {
    if (adLivesLeft <= 0) return;
    
    // Показываем индикатор загрузки
    setState(() {
      gameState = GameState.paused; // Показываем индикатор загрузки
    });
    
    try {
      // Используем AdsService для показа рекламы
      final adsService = AdsService();
      final success = await adsService.showRewardedAd();
      
      if (success) {
        // Используем life только если реклама была успешно показана
        final successAdLife = await GameService.useAdLife();
        
        // Не добавляем печеньки, так как они добавляются только в настройках
        if (successAdLife) {
          setState(() {
            adLivesLeft--;
            resetBlocksAfterResurrection(); // Сбрасываем блоки на 1x1
            gameState = GameState.playing; // Продолжаем игру
          });
        } else {
          setState(() {
            gameState = GameState.waitForResurrection; // Возвращаемся к выбору
          });
        }
      } else {
        setState(() {
          gameState = GameState.waitForResurrection; // Возвращаемся к выбору
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось воспроизвести рекламу'))
          );
        }
      }
    } catch (e) {
      // В случае ошибки показа рекламы
      setState(() {
        gameState = GameState.waitForResurrection;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка при загрузке рекламы'))
        );
      }
    }
  }
  
  // Метод для воскрешения через печеньки
  Future<void> resurrectWithCookies() async {
    if (cookieLivesLeft <= 0 || cookiesAvailable < cookiesNeeded) return;
    
    // Получаем доступ к общим настройкам
    final prefs = await SharedPreferences.getInstance();
    
    // Вычитаем печеньки
    int currentCookies = prefs.getInt('cookie_count') ?? 0;
    if (currentCookies >= cookiesNeeded) {
      // Обновляем количество печенек в общих настройках
      await prefs.setInt('cookie_count', currentCookies - cookiesNeeded);
      
      // Также обновляем счетчик жизней
      final usedLife = await GameService.useCookieLife();
      
      if (usedLife) {
        setState(() {
          cookiesAvailable = currentCookies - cookiesNeeded; // Обновляем локальный счетчик
          cookieLivesLeft--;
          resetBlocksAfterResurrection(); // Сбрасываем блоки на 1x1
          gameState = GameState.playing; // Продолжаем игру
        });
      }
    } else {
      setState(() {
        gameState = GameState.waitForResurrection; // Возвращаемся к выбору
      });
    }
  }
  
  // Запуск таймера воскрешения
  void _startResurrectionTimer() {
    // Отменяем предыдущий таймер, если он был
    _resurrectionTimer?.cancel();
    
    // Устанавливаем начальное значение
    setState(() {
      _resurrectionCountdown = 10; // Увеличено с 5 до 10 секунд
    });
    
    // Запускаем новый таймер
    _resurrectionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_resurrectionCountdown > 0) {
          _resurrectionCountdown--;
        } else {
          // Когда время вышло, переходим к экрану окончания игры
          _resurrectionTimer?.cancel();
          _resurrectionTimer = null;
          gameState = GameState.gameOver;
        }
      });
    });
  }
  
  // Виджет для отображения экрана воскрешения
  Widget _buildResurrectionScreen() {
    // Запускаем таймер при первом показе экрана
    if (_resurrectionTimer == null) {
      _startResurrectionTimer();
    }
    
    final primaryColor = Theme.of(context).colorScheme.primary;
    final primaryContainerColor = Theme.of(context).colorScheme.primaryContainer;
    final onPrimaryColor = Theme.of(context).colorScheme.onPrimary;
    
    return GestureDetector(
      onTap: () {
        // Закрываем экран воскрешения при тапе по заднему фону
        setState(() {
          gameState = GameState.gameOver;
          _resurrectionTimer?.cancel();
          _resurrectionTimer = null;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDarkMode 
                ? [
                    Colors.black.withOpacity(0.8),
                    Colors.grey.withOpacity(0.5),
                  ]
                : [
                    primaryColor.withOpacity(0.4),
                    primaryContainerColor.withOpacity(0.3),
                  ],
          ),
        ),
        alignment: Alignment.center,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: SingleChildScrollView(
            child: GestureDetector(
              onTap: () {
                // Предотвращаем срабатывание внешнего GestureDetector
                // когда нажимаем на само окно
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 64.0),
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  color: isDarkMode 
                      ? Colors.grey[850]!.withOpacity(0.95) 
                      : Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 5,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  border: Border.all(
                    color: isDarkMode 
                        ? Colors.grey[700]!.withOpacity(0.5) 
                        : primaryColor.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Positioned(
                          top: -50,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: primaryColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.warning_rounded,
                              size: 40,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 30),
                          child: Text(
                            'Нет доступных ходов!',
                            style: TextStyle(
                              color: isDarkMode ? Colors.white : Colors.black87,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDarkMode 
                            ? primaryColor.withOpacity(0.2) 
                            : primaryContainerColor.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Текущий счет: $score',
                        style: TextStyle(
                          color: isDarkMode ? Colors.white : Colors.black87,
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'У вас есть $_resurrectionCountdown сек. чтобы продолжить',
                      style: TextStyle(
                        color: isDarkMode ? Colors.amber : Colors.orange,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Кнопка воскрешения через рекламу
                    if (adLivesLeft > 0)
                      ElevatedButton.icon(
                        onPressed: () => resurrectWithAd(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: onPrimaryColor,
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        ),
                        icon: const Icon(Icons.play_circle_outline, size: 24),
                        label: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Реклама',
                              style: TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Осталось: $adLivesLeft',
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    if (adLivesLeft > 0)
                      const SizedBox(height: 16),
                    
                    // Кнопка воскрешения через печеньки
                    if (cookieLivesLeft > 0)
                      ElevatedButton.icon(
                        onPressed: cookiesAvailable >= cookiesNeeded
                          ? () => resurrectWithCookies()
                          : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: cookiesAvailable >= cookiesNeeded 
                              ? Colors.black87
                              : Colors.black38,
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        ),
                        icon: const Icon(Icons.cookie, size: 24),
                        label: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '1 печенька',
                              style: TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black12,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'У вас: $cookiesAvailable ${cookieLivesLeft > 0 ? "• Осталось: $cookieLivesLeft" : ""}',
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    const SizedBox(height: 16),
                    
                    // Кнопка начать новую игру
                    TextButton.icon(
                      onPressed: () {
                        _resurrectionTimer?.cancel();
                        _resurrectionTimer = null;
                        startNewGame();
                      },
                      icon: const Icon(Icons.refresh, size: 20),
                      label: const Text('Новая игра'),
                      style: TextButton.styleFrom(
                        foregroundColor: isDarkMode ? Colors.white70 : Colors.black54,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      ),
                    ),

                    // Кнопка закрыть
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        _resurrectionTimer?.cancel();
                        _resurrectionTimer = null;
                        setState(() {
                          gameState = GameState.gameOver;
                        });
                      },
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Закрыть'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDarkMode ? Colors.white60 : Colors.black45,
                        side: BorderSide(
                          color: isDarkMode ? Colors.white30 : Colors.black26,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  // Для перетаскивания блока
  void onPanStart(DragStartDetails details, int blockIndex) {
    if (gameState != GameState.playing) {
      startGame();
    }
    
    // Центрируем блок относительно касания
    final block = availableBlocks[blockIndex];
    final blockWidth = block.shape[0].length;
    final blockHeight = block.shape.length;
    final cellSizeForDrag = 20.0; // Уменьшенный размер для перетаскивания
    
    // Вертикальное смещение вверх для лучшей видимости
    final double verticalOffset = cellSizeForDrag * 1.0; // Увеличено с 3.0 до 5.0
    
    setState(() {
      draggedBlockIndex = blockIndex;
      // Смещаем блок выше точки касания для лучшей видимости
      dragPosition = Offset(
        details.globalPosition.dx - ((blockWidth * cellSizeForDrag) / 2),
        details.globalPosition.dy - ((blockHeight * cellSizeForDrag) / 2) - verticalOffset
      );
      updateBlockPreview(details.globalPosition);
    });
  }
  
  void onPanUpdate(DragUpdateDetails details) {
    if (draggedBlockIndex == null) return;
    
    // Обновляем позицию с сохранением смещения
    final block = availableBlocks[draggedBlockIndex!];
    final blockWidth = block.shape[0].length;
    final blockHeight = block.shape.length;
    final cellSizeForDrag = 25.0; // Уменьшенный размер для перетаскивания
    
    // Вертикальное смещение вверх для лучшей видимости
    final double verticalOffset = cellSizeForDrag * 8.0; 
    
    setState(() {
      // Смещаем блок выше точки касания для лучшей видимости
      dragPosition = Offset(
        details.globalPosition.dx - ((blockWidth * cellSizeForDrag) / 2),
        details.globalPosition.dy - ((blockHeight * cellSizeForDrag) / 2) - verticalOffset
      );
      updateBlockPreview(details.globalPosition);
    });
  }
  
  void onPanEnd(DragEndDetails details) {
    if (previewRow != null && previewCol != null && isValidPlacement && draggedBlockIndex != null) {
      placeBlock(previewRow!, previewCol!);
    } else {
      setState(() {
        draggedBlockIndex = null;
        dragPosition = null;
        previewRow = null;
        previewCol = null;
      });
    }
  }
  
  // Обновление позиции предпросмотра блока с эффектом магнита
  void updateBlockPreview(Offset globalPosition) {
    if (draggedBlockIndex == null || boardKey.currentContext == null) return;
    
    final RenderBox box = boardKey.currentContext!.findRenderObject() as RenderBox;
    final localPosition = box.globalToLocal(globalPosition);
    
    // Применяем то же смещение что и для перетаскиваемого блока
    final cellSizeForDrag = 75.0;
    final double verticalOffset = cellSizeForDrag * 1.5; // Небольшое смещение для предпросмотра
    
    // Точный расчет позиции с учетом смещения и размера ячейки
    final double exactRow = (localPosition.dy - verticalOffset) / cellSize;
    final double exactCol = localPosition.dx / cellSize;
    
    // Округляем до целого значения для выравнивания по сетке
    final int row = exactRow.floor();
    final int col = exactCol.floor();
    
    // Проверяем, можно ли разместить блок в текущей позиции
    final bool canPlace = _canPlaceBlockAt(availableBlocks[draggedBlockIndex!], row, col);
    
    // Поиск ближайшей валидной позиции для эффекта "магнита"
    int magnetRow = row;
    int magnetCol = col;
    bool foundValid = canPlace;
    
    // Если текущая позиция невалидна, ищем ближайшую валидную в пределах 2-х клеток
    if (!canPlace) {
      double closestDistance = double.infinity;
      final double magnetThreshold = 2.0; // Максимальное расстояние для срабатывания магнита
      
      // Проверяем соседние позиции в радиусе 2 клеток
      for (int r = math.max(0, row - 2); r <= math.min(boardSize - 1, row + 2); r++) {
        for (int c = math.max(0, col - 2); c <= math.min(boardSize - 1, col + 2); c++) {
          if (_canPlaceBlockAt(availableBlocks[draggedBlockIndex!], r, c)) {
            final double distance = math.sqrt((r - exactRow) * (r - exactRow) + (c - exactCol) * (c - exactCol));
            
            // Если нашли позицию ближе предыдущей и в пределах порога
            if (distance < closestDistance && distance < magnetThreshold) {
              closestDistance = distance;
              magnetRow = r;
              magnetCol = c;
              foundValid = true;
            }
          }
        }
      }
    }
    
    // Применяем магнитный эффект, только если нашли валидную позицию в пределах порога
    final bool shouldApplyMagnet = foundValid && (magnetRow != row || magnetCol != col);
    final int finalRow = shouldApplyMagnet ? magnetRow : row;
    final int finalCol = shouldApplyMagnet ? magnetCol : col;
    final bool finalIsValid = shouldApplyMagnet || canPlace;
    
    setState(() {
      previewRow = finalRow;
      previewCol = finalCol;
      isValidPlacement = finalIsValid;
    });
  }
  
  // Метод для поворота блока
  void rotateBlock(int blockIndex) {
    // Метод отключен - блоки теперь генерируются сразу в нужном повороте
  }
  
  void _showAd() {
    setState(() {
      gameState = GameState.loadingAd;
    });
    
    // Запускаем таймер для автоматической отмены загрузки рекламы
    _adLoadingTimer?.cancel();
    _adLoadingTimer = Timer(Duration(seconds: _adLoadingTimeout), () {
      // Автоматически отменяем загрузку рекламы при истечении времени
      if (gameState == GameState.loadingAd) {
        setState(() {
          gameState = GameState.waitForResurrection;
        });
        // Показываем уведомление пользователю
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось загрузить рекламу. Пожалуйста, попробуйте позже.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    });
    
    // Здесь вызовите ваш метод загрузки рекламы
  }
  
  @override
  Widget build(BuildContext context) {
    // Показываем загрузочный экран, пока данные не инициализированы
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: isDarkMode ? Colors.grey[900] : Colors.grey[100],
        appBar: AppBar(
          title: const Text('Мини-игра'),
          centerTitle: true,
          backgroundColor: isDarkMode ? Colors.grey[850] : Colors.white,
          foregroundColor: isDarkMode ? Colors.white : Colors.black87,
          elevation: isDarkMode ? 0 : 1,
          actions: [
            // Кнопка для начала новой игры
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => _buildNewGameDialog(context),
                );
              },
            ),
          ],
        ),
        body: Center(
          child: CircularProgressIndicator(
            color: isDarkMode ? Colors.white : Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }
    
    // Получаем основные цвета из темы приложения
    final primaryColor = Theme.of(context).colorScheme.primary;
    final primaryContainerColor = Theme.of(context).colorScheme.primaryContainer;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final backgroundAltColor = isDarkMode ? Colors.grey[850]! : Colors.grey[50]!;
    final borderColor = isDarkMode ? Colors.grey[800]! : Colors.grey[300]!;
    
    return Scaffold(
      backgroundColor: isDarkMode ? Colors.grey[900] : Colors.grey[100],
      appBar: AppBar(
        title: const Text('Мини-игра'),
        centerTitle: true,
        backgroundColor: isDarkMode ? Colors.grey[850] : Colors.white,
        foregroundColor: isDarkMode ? Colors.white : Colors.black87,
        elevation: isDarkMode ? 0 : 1,
        actions: [
          // Показываем количество печенек
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                const Icon(Icons.cookie, color: Colors.amber),
                const SizedBox(width: 4),
                Text(
                  '$cookiesAvailable',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Кнопка для начала новой игры
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => _buildNewGameDialog(context),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Анимированный фон
          IgnorePointer(
            child: _isInitialized ? AnimatedBackgroundWidget(
              isDarkMode: isDarkMode,
            ) : Container(),
          ),
          
          // Основной контент
          SafeArea(
            child: Column(
              children: [
                // Счет и уровень
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Текущий счет
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Счет: $score',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDarkMode ? Colors.white : Colors.black87,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                'Рекорд: $highScore',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDarkMode ? Colors.white70 : Colors.black54,
                                  fontWeight: score >= highScore ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              if (score >= highScore && score > 0)
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.amber.withOpacity(0.6),
                                        blurRadius: 4,
                                        spreadRadius: 0,
                                      ),
                                    ],
                                  ),
                                  child: TweenAnimationBuilder<double>(
                                    duration: const Duration(milliseconds: 1000),
                                    tween: Tween<double>(begin: 0.8, end: 1.0),
                                    curve: Curves.elasticInOut,
                                    builder: (context, value, child) {
                                      return Transform.scale(
                                        scale: 1.0 + 0.2 * sin(value * 2 * math.pi),
                                        child: Text(
                                          'Новый!',
                                          style: TextStyle(
                                            color: Colors.black87,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      
                      // Текущий уровень
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _getLevelColor(level),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          'Уровень $level',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Игровая доска
                AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    margin: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: isDarkMode 
                              ? Colors.black.withOpacity(0.3)
                              : Colors.black.withOpacity(0.15),
                          blurRadius: isDarkMode ? 8 : 6,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: !isDarkMode ? Border.all(
                        color: borderColor!,
                        width: 1,
                      ) : null,
                    ),
                    child: Stack(
                      children: [
                        // Игровая сетка
                        GridView.builder(
                          key: boardKey,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: boardSize,
                          ),
                          itemCount: boardSize * boardSize,
                          itemBuilder: (context, index) {
                            final int row = index ~/ boardSize;
                            final int col = index % boardSize;
                            final cell = board[row][col];
                            
                            // Проверяем, находится ли ячейка в превью блока
                            bool isPreviewCell = false;
                            if (draggedBlockIndex != null && previewRow != null && previewCol != null && isValidPlacement) {
                              final block = availableBlocks[draggedBlockIndex!];
                              for (int i = 0; i < block.shape.length; i++) {
                                for (int j = 0; j < block.shape[i].length; j++) {
                                  if (block.shape[i][j] && 
                                      row == previewRow! + i && 
                                      col == previewCol! + j) {
                                    isPreviewCell = true;
                                    break;
                                  }
                                }
                                if (isPreviewCell) break;
                              }
                            }
                            
                            // Проверяем, является ли ячейка частью заполненной линии
                            bool isFilledLineCell = false;
                            if (draggedBlockIndex != null && previewRow != null && previewCol != null && isValidPlacement) {
                              // Создаем виртуальную копию доски с блоком
                              List<List<bool>> virtualBoard = List.generate(
                                boardSize, 
                                (r) => List.generate(
                                  boardSize, 
                                  (c) => board[r][c].isFilled
                                )
                              );
                              
                              // Добавляем блок на виртуальную доску
                              final block = availableBlocks[draggedBlockIndex!];
                              for (int i = 0; i < block.shape.length; i++) {
                                for (int j = 0; j < block.shape[i].length; j++) {
                                  if (block.shape[i][j]) {
                                    final int vRow = previewRow! + i;
                                    final int vCol = previewCol! + j;
                                    if (vRow >= 0 && vRow < boardSize && vCol >= 0 && vCol < boardSize) {
                                      virtualBoard[vRow][vCol] = true;
                                    }
                                  }
                                }
                              }
                              
                              // Проверяем, полностью ли заполнена строка или столбец
                              bool isRowFull = true;
                              for (int c = 0; c < boardSize; c++) {
                                if (!virtualBoard[row][c]) {
                                  isRowFull = false;
                                  break;
                                }
                              }
                              
                              bool isColFull = true;
                              for (int r = 0; r < boardSize; r++) {
                                if (!virtualBoard[r][col]) {
                                  isColFull = false;
                                  break;
                                }
                              }
                              
                              isFilledLineCell = isRowFull || isColFull;
                            }
                            
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.all(1),
                              decoration: BoxDecoration(
                                color: isPreviewCell 
                                    ? availableBlocks[draggedBlockIndex!].color.withOpacity(0.5)
                                    : isFilledLineCell
                                        ? isDarkMode
                                            ? Colors.yellow.withOpacity(0.3)
                                            : primaryContainerColor.withOpacity(0.7)
                                        : cell.isFilled
                                            ? cell.color
                                            : (isDarkMode ? Colors.grey[700] : Colors.grey[300]),
                                borderRadius: BorderRadius.circular(4),
                                border: isPreviewCell 
                                    ? Border.all(
                                        color: availableBlocks[draggedBlockIndex!].color,
                                        width: 1.5,
                                      )
                                    : !isDarkMode && !cell.isFilled
                                        ? Border.all(
                                            color: borderColor!,
                                            width: 0.5,
                                          )
                                        : null,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Доступные блоки
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: List.generate(
                        availableBlocks.length,
                        (index) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: usedBlocks[index] 
                            ? Container(
                                decoration: BoxDecoration(
                                  color: isDarkMode ? Colors.grey[900] : backgroundAltColor,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: borderColor!,
                                    width: isDarkMode ? 2 : 1,
                                  ),
                                ),
                              )
                            : GestureDetector(
                                onPanStart: (details) => onPanStart(details, index),
                                onPanUpdate: onPanUpdate,
                                onPanEnd: onPanEnd,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isDarkMode ? Colors.grey[800] : surfaceColor,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: isDarkMode 
                                            ? Colors.black.withOpacity(0.15)
                                            : Colors.black.withOpacity(0.1),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                    border: !isDarkMode ? Border.all(
                                      color: borderColor,
                                      width: 1,
                                    ) : null,
                                  ),
                                  child: AspectRatio(
                                    aspectRatio: 1,
                                    child: Opacity(
                                      opacity: draggedBlockIndex == index ? 0.5 : 1.0,
                                      child: _buildBlockWidget(availableBlocks[index]),
                                    ),
                                  ),
                                ),
                              ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Перетаскиваемый блок
          if (draggedBlockIndex != null && dragPosition != null)
            Positioned(
              left: dragPosition!.dx,
              top: dragPosition!.dy,
              child: Material(
                color: Colors.transparent,
                elevation: 8,
                child: _buildDraggedBlockWidget(availableBlocks[draggedBlockIndex!]),
              ),
            ),
          
          // Анимация очков
          ...pointAnimations.map((animation) {
            return Positioned(
              left: animation['position'].dx - 20,
              top: animation['position'].dy - 50,
              child: PointsAnimation(
                points: animation['points'],
                color: animation['color'],
                onComplete: () {
                  setState(() {
                    pointAnimations.remove(animation);
                  });
                },
              ),
            );
          }).toList(),
          
          // Отображение комбо
          if (comboDisplay != null)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.25,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Material(
                    type: MaterialType.transparency,
                    child: ComboPointsDisplay(
                      comboCount: comboDisplay!['comboCount'],
                      bonusPoints: comboDisplay!['bonusPoints'],
                      linesCleared: comboDisplay!['linesCleared'],
                      isDarkMode: isDarkMode,
                      isSpecial: comboDisplay!['isSpecial'] ?? false,
                      isPartOfSeries: comboDisplay!['isPartOfSeries'] ?? false,
                    ),
                  ),
                ),
              ),
            ),
          
          // Экран "начать игру", если игра не начата
          if (gameState == GameState.notStarted)
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
              ),
              alignment: Alignment.center,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                child: Container(
                  margin: const EdgeInsets.all(32.0),
                  padding: const EdgeInsets.all(24.0),
                  decoration: BoxDecoration(
                    color: isDarkMode 
                        ? Colors.grey[900]!.withOpacity(0.9) 
                        : Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Мини-игра',
                        style: TextStyle(
                          color: isDarkMode ? Colors.white : Colors.black87,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Размещайте блоки на доске,\nчтобы заполнять линии',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isDarkMode ? Colors.white70 : Colors.black54,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: () {
                          startGame();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Начать игру',
                          style: TextStyle(
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          
          // Экран ожидания воскрешения
          if (gameState == GameState.waitForResurrection)
            _buildResurrectionScreen(),
          
          // Экран загрузки для рекламы
          if (gameState == GameState.paused)
            Container(
              color: Colors.black.withOpacity(0.85),
              alignment: Alignment.center,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Анимированная иконка загрузки
                    TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 800),
                      tween: Tween<double>(begin: 0.0, end: 1.0),
                      builder: (context, value, child) {
                        return Transform.scale(
                          scale: 1.0 + 0.1 * sin(value * 2 * 3.14159),
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withOpacity(0.5),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 30),
                    
                    // Анимированный индикатор загрузки
                    SizedBox(
                      width: 200,
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.white.withOpacity(0.2),
                        color: Colors.blue,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Анимированный текст
                    TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 1000),
                      tween: Tween<double>(begin: 0.7, end: 1.0),
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20, 
                              vertical: 12
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Загрузка рекламы...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Вы получите 1 печеньку за просмотр',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    
                    const SizedBox(height: 25),
                    
                    // Кнопка отмены загрузки рекламы
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          gameState = GameState.waitForResurrection;
                        });
                      },
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Отмена'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.withOpacity(0.7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
          // Экран окончания игры
          if (gameState == GameState.gameOver)
            GestureDetector(
              // Предотвращаем нажатия на задний фон
              onTap: () {},
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDarkMode 
                        ? [
                            Colors.black.withOpacity(0.7),
                            Colors.grey.withOpacity(0.4),
                          ]
                        : [
                            primaryColor.withOpacity(0.4),
                            primaryContainerColor.withOpacity(0.3),
                          ],
                  ),
                ),
                alignment: Alignment.center,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                  child: Container(
                    margin: const EdgeInsets.all(32.0),
                    padding: const EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      color: isDarkMode 
                          ? Colors.grey[900]!.withOpacity(0.95) 
                          : Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                      border: Border.all(
                        color: isDarkMode 
                            ? Colors.grey[700]!.withOpacity(0.3) 
                            : primaryColor.withOpacity(0.2),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Иконка трофея
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: primaryColor,
                            boxShadow: [
                              BoxShadow(
                                color: primaryColor.withOpacity(0.5),
                                blurRadius: 12,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.emoji_events,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Игра окончена!',
                          style: TextStyle(
                            color: isDarkMode ? Colors.white : Colors.black87,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: primaryContainerColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: primaryColor.withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            'Счет: $score',
                            style: TextStyle(
                              color: isDarkMode ? Colors.white : Colors.black87,
                              fontSize: 24,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Рекорд: $highScore',
                          style: TextStyle(
                            color: isDarkMode ? Colors.white70 : Colors.black54,
                            fontSize: 18,
                            fontWeight: score >= highScore ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        
                        // Новый рекорд индикатор
                        if (score >= highScore && score > 0) 
                          Container(
                            margin: const EdgeInsets.only(top: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.amber, Colors.orange],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.amber.withOpacity(0.6),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.emoji_events,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                TweenAnimationBuilder<double>(
                                  duration: const Duration(milliseconds: 1500),
                                  tween: Tween<double>(begin: 0.9, end: 1.0),
                                  curve: Curves.elasticOut,
                                  builder: (context, value, child) {
                                    return Transform.scale(
                                      scale: value,
                                      child: Text(
                                        'Новый рекорд!',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          shadows: [
                                            Shadow(
                                              color: Colors.black26,
                                              blurRadius: 2,
                                              offset: const Offset(1, 1),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          
                        const SizedBox(height: 32),
                        ElevatedButton(
                          onPressed: () {
                            startNewGame();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                          ),
                          child: const Text(
                            'Новая игра',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  // Виджет для отображения блока
  Widget _buildBlockWidget(Block block) {
    // Определяем размер стороны блока
    int maxSize = 0;
    for (var row in block.shape) {
      if (row.length > maxSize) {
        maxSize = row.length;
      }
    }
    maxSize = math.max(maxSize, block.shape.length);
    
    // Размер ячейки с учетом отступов (ограничиваем максимальный размер)
    final double blockCellSize = (math.min(30, 90 / maxSize)).floorToDouble();
    
    return Center(
      child: Container(
        width: blockCellSize * maxSize,
        height: blockCellSize * block.shape.length,
        child: GridView.builder(
          physics: NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: maxSize,
            childAspectRatio: 1.0,
            crossAxisSpacing: 0,
            mainAxisSpacing: 0,
          ),
          itemCount: maxSize * block.shape.length,
          itemBuilder: (context, index) {
            final int i = index ~/ maxSize;
            final int j = index % maxSize;
            
            // Проверяем, есть ли в этой позиции ячейка блока
            final bool hasCell = i < block.shape.length && 
                               j < block.shape[i].length && 
                               block.shape[i][j];
            
            if (!hasCell) {
              return SizedBox(); // Пустая ячейка
            }
            
            return Container(
              margin: EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: block.color,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          },
        ),
      ),
    );
  }
  
  // Виджет для отображения перетаскиваемого блока
  Widget _buildDraggedBlockWidget(Block block) {
    final int maxWidth = block.shape[0].length;
    final int maxHeight = block.shape.length;
    final double cellSizeForDrag = 25.0;
    
    return Container(
      width: maxWidth * cellSizeForDrag,
      height: maxHeight * cellSizeForDrag,
      child: GridView.builder(
        physics: NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: maxWidth,
          childAspectRatio: 1.0,
          crossAxisSpacing: 0,
          mainAxisSpacing: 0,
        ),
        itemCount: maxWidth * maxHeight,
        itemBuilder: (context, index) {
          final int i = index ~/ maxWidth;
          final int j = index % maxWidth;
          
          if (i >= block.shape.length || j >= block.shape[i].length || !block.shape[i][j]) {
            return SizedBox(); // Пустая ячейка
          }
          
          return Container(
            margin: EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: block.color,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 2,
                  spreadRadius: 0,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildNewGameDialog(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 16,
      backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Новая игра',
              style: TextStyle(
                color: isDarkMode ? Colors.white : Colors.black87,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Вы уверены, что хотите начать новую игру?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDarkMode ? Colors.white70 : Colors.black54,
                  fontSize: 16,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDarkMode ? Colors.white60 : Colors.black45,
                    side: BorderSide(
                      color: isDarkMode ? Colors.white30 : Colors.black26,
                      width: 1.5,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Отмена',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    startNewGame();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Начать',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  // Оценка сложности блока для текущей доски
  int _estimateBlockComplexity(Block block) {
    int placementOptions = 0;
    int maxRow = boardSize - block.shape.length;
    int maxCol = boardSize - block.shape[0].length;
    
    // Подсчитываем количество мест, где можно разместить блок
    for (int row = 0; row <= maxRow; row++) {
      for (int col = 0; col <= maxCol; col++) {
        if (_canPlaceBlockAt(block, row, col)) {
          placementOptions++;
        }
      }
    }
    
    // Вычисляем размер блока (количество ячеек)
    int blockSize = 0;
    for (var row in block.shape) {
      for (var cell in row) {
        if (cell) blockSize++;
      }
    }
    
    // Блоки большего размера дают больше очков, но сложнее разместить
    // Возвращаем сложность - больше значение = блок сложнее разместить
    // но даёт больше очков
    if (placementOptions == 0) {
      return -1; // Блок невозможно разместить
    } else {
      // Компромисс между размером и количеством мест для размещения
      return (blockSize * 10) ~/ placementOptions;
    }
  }

  // Получение цвета для уровня
  Color _getLevelColor(int level) {
    if (level <= 1) {
      return Colors.blue;
    } else if (level <= 3) {
      return Colors.green;
    } else if (level < 5) {
      return Colors.orange;
    } else if (level < 10) {
      return Colors.deepOrange;
    } else if (level < 15) {
      return Colors.red;
    } else if (level < 20) {
      return Colors.purple;
    } else if (level < 25) {
      return Colors.pink;
    } else if (level < 30) {
      return Colors.indigo;
    } else if (level < 40) {
      return Colors.teal;
    } else if (level < 50) {
      return Colors.amber;
    } else if (level < 60) {
      return Colors.brown;
    } else if (level < 70) {
      return Colors.cyan;
    } else if (level < 80) {
      return Colors.lime;
    } else if (level < 90) {
      return Colors.deepPurple;
    } else if (level < 100) {
      return Color.fromARGB(255, 255, 215, 0);
    } else if (level < 110) {
      return Color.fromARGB(255, 255, 215, 0);
    } else {
      return Color.fromARGB(255, 255, 215, 0);
    }
  }
} 