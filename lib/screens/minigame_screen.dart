import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:math' show Random;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// Модель для игровой клетки
class Cell {
  bool isFilled = false;
  Color color = Colors.transparent;
  
  // Конструктор по умолчанию
  Cell();
  
  // Конструктор для создания клетки из JSON
  Cell.fromJson(Map<String, dynamic> json)
      : isFilled = json['isFilled'] ?? false,
        color = json['color'] != null
            ? Color(json['color'])
            : Colors.transparent;
  
  // Метод для преобразования в JSON
  Map<String, dynamic> toJson() => {
    'isFilled': isFilled,
    'color': color.value,
  };
}

// Модель для блока
class Block {
  List<List<bool>> shape; // Форма блока (матрица true/false)
  Color color;
  int size;
  
  Block({required this.shape, required this.color, required this.size});
  
  // Конструктор для создания блока из JSON
  Block.fromJson(Map<String, dynamic> json)
      : shape = (json['shape'] as List)
            .map((row) => (row as List).map((cell) => cell as bool).toList())
            .toList(),
        color = Color(json['color']),
        size = json['size'];
  
  // Метод для преобразования в JSON
  Map<String, dynamic> toJson() => {
    'shape': shape,
    'color': color.value,
    'size': size,
  };
}

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

// Состояния игры
enum GameState {
  notStarted,
  playing,
  gameOver
}

// Дополнительный painter для feedback при перетаскивании
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
    final rows = block.shape.length;
    final cols = block.shape[0].length;
    
    final fillPaint = Paint()
      ..color = color.withOpacity(0.8)
      ..style = PaintingStyle.fill;
      
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    
    // Рисуем каждую ячейку блока
    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < cols; j++) {
        if (block.shape[i][j]) {
          final Rect rect = Rect.fromLTWH(
            j * cellSize, 
            i * cellSize, 
            cellSize, 
            cellSize
          );
          
          // Рисуем прямоугольник с закругленными углами
          final RRect roundedRect = RRect.fromRectAndRadius(
            rect.deflate(2), 
            const Radius.circular(6)
          );
          
          // Заполняем ячейку
          canvas.drawRRect(roundedRect, fillPaint);
          
          // Рисуем границу
          canvas.drawRRect(roundedRect, borderPaint);
          
          // Добавляем декоративный элемент в центре
          canvas.drawCircle(
            rect.center, 
            cellSize * 0.2, 
            Paint()
              ..color = Colors.white.withOpacity(0.8)
              ..style = PaintingStyle.fill
          );
        }
      }
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MinigameScreen extends StatefulWidget {
  const MinigameScreen({super.key});

  @override
  State<MinigameScreen> createState() => _MinigameScreenState();
}

class _MinigameScreenState extends State<MinigameScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // Константы игры
  static const int boardSize = 8; // Размер доски
  static const int maxBlockCount = 3; // Максимум блоков для выбора
  
  // Игровая доска
  late List<List<Cell>> board;
  
  // Доступные блоки для размещения
  List<Block> availableBlocks = []; // Инициализируем пустым списком
  int placedBlocksCount = 0;
  
  // Текущий выбранный блок
  Block? selectedBlock;
  int selectedBlockIndex = -1;
  
  // Счет игры
  int score = 0;
  int highScore = 0;
  
  // Состояние игры
  GameState gameState = GameState.notStarted;
  
  // Анимация
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;
  
  // Генератор случайных чисел
  final Random random = Random();
  
  // Флаг для светлой/тёмной темы
  bool _isDarkMode = false;
  
  // Добавляем переменные для отслеживания перетаскивания
  bool isDragging = false;
  int previewRow = -1;
  int previewCol = -1;
  Block? draggedBlock;
  
  // Добавляем GlobalKey для получения размеров игрового поля
  final GlobalKey _boardKey = GlobalKey();
  
  // Переменные для анимации исчезающих линий
  List<int> animatingRows = [];
  List<int> animatingCols = [];
  bool isAnimatingLines = false;
  double lineOpacity = 1.0;
  
  // Переменные для подсветки рядов и столбцов, которые будут заполнены
  List<int> highlightRows = [];
  List<int> highlightCols = [];
  
  // Переменные для отображения комбо и бонусных очков
  int comboCount = 0;
  int lastLinesClearedCount = 0;
  int bonusPoints = 0;
  bool showComboAnimation = false;
  
  @override
  void initState() {
    super.initState();
    
    // Инициализация базовых структур данных
    board = List.generate(
      boardSize, 
      (_) => List.generate(
        boardSize, 
        (_) => Cell(),
      ),
    );
    
    // Добавляем обработчик жизненного цикла приложения
    WidgetsBinding.instance.addObserver(this);
    
    // Инициализация контроллера анимации
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    
    // Добавляем пульсирующую анимацию для подсветки
    _pulseAnimation = Tween<double>(begin: 0.4, end: 0.7).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
    
    // Зацикливаем анимацию
    _animationController.repeat(reverse: true);
    
    // Загружаем состояние игры
    _initGameLoadState();
  }
  
  @override
  void dispose() {
    // Удаляем обработчик жизненного цикла
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    super.dispose();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Безопасно получаем тему здесь
    _isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    // Обновляем цвета блоков
    if (availableBlocks.isNotEmpty) {
      setState(() {
        _updateBlockColors();
      });
    }
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Проверяем состояние жизненного цикла приложения
    if (state == AppLifecycleState.resumed) {
      // Приложение вернулось с фона - проверяем наличие анимирующихся линий
      if (isAnimatingLines && (animatingRows.isNotEmpty || animatingCols.isNotEmpty)) {
        // Немедленно завершаем анимацию и очищаем линии
        _finishLineAnimation(animatingRows, animatingCols);
      }
    } else if (state == AppLifecycleState.paused) {
      // Приложение уходит в фон - принудительно очищаем анимирующиеся линии
      if (isAnimatingLines && (animatingRows.isNotEmpty || animatingCols.isNotEmpty)) {
        _finishLineAnimation(animatingRows, animatingCols);
      }
    }
  }
  
  // Инициализация и загрузка состояния игры
  Future<void> _initGameLoadState() async {
    await _loadHighScore(); // Сначала загружаем рекорд
    await _loadGameState(); // Затем загружаем состояние игры или создаем новую
  }
  
  // Загружаем лучший результат
  Future<void> _loadHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      highScore = prefs.getInt('minigame_high_score') ?? 0;
    });
  }
  
  // Сохраняем лучший результат
  Future<void> _saveHighScore() async {
    if (score > highScore) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('minigame_high_score', score);
      setState(() {
        highScore = score;
      });
    }
  }
  
  // Генерируем доступные блоки
  void _generateBlocks() {
    // Очищаем текущие блоки, если они все размещены
    if (availableBlocks.isEmpty || placedBlocksCount >= maxBlockCount) {
      availableBlocks = [];
      placedBlocksCount = 0;
      
      for (int i = 0; i < maxBlockCount; i++) {
        availableBlocks.add(_createRandomBlock());
      }
    }
  }
  
  // Создаем случайный блок
  Block _createRandomBlock() {
    // Получаем случайную профессию
    final professionType = ProfessionType.values[random.nextInt(ProfessionType.values.length)];
    // Используем сохраненный флаг темы вместо Theme.of(context)
    final color = professionType.getColor(_isDarkMode);
    
    // Определяем размер блока и форму
    final int blockType = random.nextInt(10); // Расширяем типы блоков
    
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
  
  // Обновляем цвета блоков при изменении темы
  void _updateBlockColors() {
    for (var i = 0; i < availableBlocks.length; i++) {
      // Создаем новый блок с тем же типом, но с обновленным цветом
      final oldBlock = availableBlocks[i];
      
      // Пытаемся определить тип профессии по текущему цвету
      ProfessionType? profession;
      for (var type in ProfessionType.values) {
        if (oldBlock.color == type.lightColor || oldBlock.color == type.darkColor) {
          profession = type;
          break;
        }
      }
      
      // Если нашли профессию, обновляем цвет
      if (profession != null) {
        availableBlocks[i] = Block(
          shape: oldBlock.shape,
          color: profession.getColor(_isDarkMode),
          size: oldBlock.size,
        );
      }
    }
  }
  
  // Проверяем, можно ли разместить блок в указанной позиции
  bool _canPlaceBlock(Block block, int row, int col) {
    // Проверка, что позиция находится в пределах доски
    if (row < 0 || col < 0 || row + block.shape.length > boardSize || col + block.shape[0].length > boardSize) {
      return false;
    }
    
    // Обходим каждую ячейку блока
    bool hasAtLeastOneCell = false;
    
    for (int i = 0; i < block.shape.length; i++) {
      for (int j = 0; j < block.shape[i].length; j++) {
        // Если ячейка блока заполнена
        if (block.shape[i][j]) {
          hasAtLeastOneCell = true;
          final int boardRow = row + i;
          final int boardCol = col + j;
          
          // Проверка на выход за границы доски
          if (boardRow < 0 || boardRow >= boardSize || boardCol < 0 || boardCol >= boardSize) {
            return false;
          }
          
          // Проверка, что ячейка доски не занята
          if (board[boardRow][boardCol].isFilled) {
            return false;
          }
        }
      }
    }
    
    // Проверяем, что блок имеет хотя бы одну ячейку
    return hasAtLeastOneCell;
  }
  
  // Сохраняем состояние игры
  Future<void> _saveGameState() async {
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
  Future<void> _loadGameState() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Пытаемся загрузить сохраненное состояние
    final savedStateJson = prefs.getString('minigame_saved_state');
    if (savedStateJson == null) {
      // Если сохранений нет, инициализируем новую игру
      _initNewGame();
      return;
    }
    
    try {
      final gameStateMap = jsonDecode(savedStateJson) as Map<String, dynamic>;
      
      // Загружаем счет
      score = gameStateMap['score'] ?? 0;
      
      // Загружаем placedBlocksCount
      placedBlocksCount = gameStateMap['placedBlocksCount'] ?? 0;
      
      // Загружаем gameState
      final savedGameState = gameStateMap['gameState'] ?? 0;
      gameState = GameState.values[savedGameState];
      
      // Восстанавливаем игровую доску
      final boardData = gameStateMap['board'] as List;
      board = List.generate(
        boardSize,
        (i) => List.generate(
          boardSize,
          (j) => Cell.fromJson(boardData[i][j]),
        ),
      );
      
      // Восстанавливаем доступные блоки
      final blocksData = gameStateMap['availableBlocks'] as List;
      availableBlocks = blocksData.map((blockData) => Block.fromJson(blockData)).toList();
      
      // Если игра была закончена или нет доступных блоков, начинаем новую
      if (gameState == GameState.gameOver || availableBlocks.isEmpty) {
        gameState = GameState.notStarted;
      }
      
      // Если состояние notStarted, убеждаемся, что у нас есть блоки
      if (gameState == GameState.notStarted) {
        _initNewGame();
      }
      
    } catch (e) {
      // В случае ошибки загрузки, инициализируем новую игру
      _initNewGame();
    }
  }
  
  // Инициализируем новую игру
  void _initNewGame() {
    // Очищаем доску
    for (int i = 0; i < boardSize; i++) {
      for (int j = 0; j < boardSize; j++) {
        board[i][j].isFilled = false;
        board[i][j].color = Colors.transparent;
      }
    }
    
    // Сбрасываем счетчики
    score = 0;
    placedBlocksCount = 0;
    
    // Генерируем начальные блоки, если их нет
    if (availableBlocks.isEmpty) {
      _generateBlocks();
    }
    
    // Устанавливаем состояние "не начато"
    if (gameState != GameState.playing) {
      gameState = GameState.notStarted;
    }
  }
  
  // Заменяем старый метод _initGame на _initNewGame
  void _initGame() {
    _initNewGame();
  }
  
  // Обновляем методы запуска и перезапуска игры
  void _startGame() {
    setState(() {
      score = 0;
      _initNewGame(); // Заменяем _initGame на _initNewGame
      gameState = GameState.playing;
      _saveGameState();
    });
  }
  
  void _restartGame() {
    setState(() {
      score = 0;
      
      // Очищаем доску
      for (int i = 0; i < boardSize; i++) {
        for (int j = 0; j < boardSize; j++) {
          board[i][j].isFilled = false;
          board[i][j].color = Colors.transparent;
        }
      }
      
      // Полностью сбрасываем состояние игры и доступные блоки
      placedBlocksCount = 0;
      availableBlocks.clear();
      _generateBlocks();
      
      gameState = GameState.playing;
      _saveGameState();
    });
  }
  
  // Проверяем заполненные строки и столбцы
  void _checkLines() {
    List<int> fullRows = [];
    List<int> fullCols = [];
    
    // Проверяем строки
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
    
    // Проверяем столбцы
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
    
    // Немедленно начисляем очки в системе и обновляем состояние
    int clearedLines = fullRows.length + fullCols.length;
    if (clearedLines > 0) {
      // Создаем структуру полных линий для анимации
      if (fullRows.isNotEmpty || fullCols.isNotEmpty) {
        setState(() {
          animatingRows = fullRows;
          animatingCols = fullCols;
          isAnimatingLines = true;
          lineOpacity = 1.0;
        });
        
        // Рассчитываем очки с комбо
        _calculateAndApplyScore(clearedLines);
        
        // Сразу очищаем линии в системе, но с анимацией для пользователя
        _clearLinesInSystem(fullRows, fullCols);
        
        // Запускаем анимацию исчезновения линий для пользователя
        _animateLineClearing(fullRows, fullCols);
      }
    } else {
      // Сбрасываем комбо, если нет собранных линий
      comboCount = 0;
    }
  }
  
  // Очищаем линии в системе сразу, но сохраняем визуальное представление для анимации
  void _clearLinesInSystem(List<int> rows, List<int> cols) {
    // Очищаем заполненные строки в копии доски
    List<List<Cell>> boardCopy = List.generate(
      boardSize,
      (i) => List.generate(
        boardSize,
        (j) => Cell()..isFilled = board[i][j].isFilled..color = board[i][j].color,
      ),
    );
    
    // Очищаем заполненные строки в копии
    for (int row in rows) {
      for (int j = 0; j < boardSize; j++) {
        boardCopy[row][j].isFilled = false;
        boardCopy[row][j].color = Colors.transparent;
      }
    }
    
    // Очищаем заполненные столбцы в копии
    for (int col in cols) {
      for (int i = 0; i < boardSize; i++) {
        boardCopy[i][col].isFilled = false;
        boardCopy[i][col].color = Colors.transparent;
      }
    }
    
    // Обновляем внутреннюю игровую логику с очищенной доской
    // но визуально доска пока остается с заполненными линиями для анимации
    setState(() {
      board = boardCopy;
    });
  }
  
  // Рассчитываем и применяем очки с учетом комбо
  void _calculateAndApplyScore(int clearedLines) {
    if (!mounted) return; // Проверка mounted перед обновлением состояния
    
    // Базовые очки за линию
    int basePoints = 10;
    int totalPoints = basePoints * clearedLines;
    
    // Проверяем, увеличился ли счетчик комбо
    if (lastLinesClearedCount > 0) {
      // Увеличиваем комбо, если в предыдущем ходу тоже были собраны линии
      comboCount++;
    } else {
      // Сбрасываем комбо, если в предыдущем ходу не было собранных линий
      comboCount = 1; // Первое комбо
    }
    
    // Бонус за несколько линий сразу
    if (clearedLines >= 2) {
      totalPoints = (totalPoints * 1.5).toInt(); // Бонус за 2+ линии
    }
    if (clearedLines >= 3) {
      totalPoints = (totalPoints * 1.5).toInt(); // Дополнительный бонус за 3+ линий
    }
    
    // Бонус за комбо (последовательные ходы с собранными линиями)
    int comboBonus = 0;
    if (comboCount > 1) {
      comboBonus = totalPoints ~/ 2 * (comboCount - 1); // 50% бонус за каждый ход в комбо после первого
      totalPoints += comboBonus;
    }
    
    // Сохраняем количество собранных линий для следующего хода
    lastLinesClearedCount = clearedLines;
    
    // Безопасно обновляем счет и бонус для отображения
    try {
      if (mounted) { // Дополнительная проверка mounted
        setState(() {
          score += totalPoints;
          bonusPoints = totalPoints;
          showComboAnimation = clearedLines >= 2 || comboCount > 1;
        });
      }
    } catch (e) {
      debugPrint('Ошибка при обновлении счета: $e');
    }
    
    // Сохраняем высокий счет
    _saveHighScore();
  }
  
  // Анимация исчезновения заполненных линий
  void _animateLineClearing(List<int> rows, List<int> cols) {
    if (!mounted) return; // Проверка mounted перед началом анимации

    // Начинаем с полной непрозрачности
    double opacity = 1.0;
    
    // Создаем анимацию мигания для привлечения внимания
    void animateFlash() {
      if (!mounted) return; // Проверка mounted перед запуском отложенного действия
      
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted) return;
        
        try {
          setState(() {
            lineOpacity = opacity;
          });
          
          opacity -= 0.1;
          
          if (opacity > 0) {
            animateFlash();
          } else {
            // Когда анимация завершена, визуально очищаем линии
            _finishLineAnimation(rows, cols);
          }
        } catch (e) {
          debugPrint('Ошибка в анимации исчезновения линий: $e');
          // В случае ошибки немедленно завершаем анимацию
          _finishLineAnimation(rows, cols);
        }
      });
    }
    
    // Запускаем анимацию
    animateFlash();
    
    // Скрываем анимацию комбо через 1.5 секунды
    if (showComboAnimation && mounted) {
      try {
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            setState(() {
              showComboAnimation = false;
            });
          }
        });
      } catch (e) {
        debugPrint('Ошибка при скрытии анимации комбо: $e');
      }
    }
  }
  
  // Завершаем анимацию линий и сбрасываем флаги
  void _finishLineAnimation(List<int> rows, List<int> cols) {
    if (!mounted) return; // Проверка mounted перед обновлением состояния
    
    try {
      setState(() {
        isAnimatingLines = false;
        animatingRows = [];
        animatingCols = [];
      });
    } catch (e) {
      debugPrint('Ошибка при завершении анимации линий: $e');
    }
  }
  
  // Проверяем, можно ли продолжить игру
  bool _canContinueGame() {
    // Если нет доступных блоков, но будут сгенерированы новые, игра может продолжаться
    if (availableBlocks.isEmpty) {
      return true;
    }
    
    // Проверяем, что хотя бы один из доступных блоков можно разместить на доске
    for (Block block in availableBlocks) {
      for (int i = 0; i < boardSize; i++) {
        for (int j = 0; j < boardSize; j++) {
          if (_canPlaceBlock(block, i, j)) {
            return true;
          }
        }
      }
    }
    
    return false;
  }
  
  // Строим игровую доску
  Widget _buildGameBoard(bool isDarkMode, Color surfaceColor, Color primaryColor, double cellSize) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Stack(
        children: [
          Container(
            key: _boardKey, // Добавляем ключ для доступа к размерам
            decoration: BoxDecoration(
              color: isDarkMode 
                  ? Colors.grey[850]!.withOpacity(0.5) 
                  : Colors.grey[100]!.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  // Базовая сетка
                  GridView.builder(
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: boardSize,
                      childAspectRatio: 1.0, // Важно для корректных квадратных ячеек
                    ),
                    itemCount: boardSize * boardSize,
                    itemBuilder: (context, index) {
                      final int row = index ~/ boardSize;
                      final int col = index % boardSize;
                      return _buildCell(row, col, isDarkMode);
                    },
                  ),
                  
                  // Превью размещения блока
                  if (isDragging && draggedBlock != null)
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // Используем точный размер ячейки на основе размера контейнера
                          final double actualCellSize = constraints.maxWidth / boardSize;
                          
                          return DragTarget<Block>(
                            // Будем принимать блок при любом событии перетаскивания
                            onWillAcceptWithDetails: (details) {
                              final Block block = details.data;
                              // Только обновляем превью, не принимаем/отклоняем блок
                              _updatePreview(block, details.offset);
                              // Всегда возвращаем true, чтобы DragTarget отслеживал событие
                              return true;
                            },
                            onAcceptWithDetails: (details) {
                              final Block block = details.data;
                              
                              // Размещаем блок только если есть корректная позиция и можно разместить
                              if (previewRow >= 0 && previewCol >= 0 && 
                                  _canPlaceBlock(block, previewRow, previewCol)) {
                                _placeBlock(block, previewRow, previewCol);
                              }
                              
                              _resetPreview();
                            },
                            onLeave: (_) {
                              // Не сбрасываем превью сразу при покидании области
                            },
                            builder: (context, candidateData, rejectedData) {
                              return Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerMove: (event) {
                                  if (draggedBlock != null) {
                                    _updatePreview(draggedBlock!, event.position);
                                  }
                                },
                                onPointerUp: (event) {
                                  // Дополнительная проверка при отпускании указателя
                                  if (draggedBlock != null && previewRow >= 0 && previewCol >= 0 && 
                                      _canPlaceBlock(draggedBlock!, previewRow, previewCol)) {
                                    _placeBlock(draggedBlock!, previewRow, previewCol);
                                  }
                                  _resetPreview();
                                },
                                child: AnimatedBuilder(
                                  animation: _pulseAnimation,
                                  builder: (context, child) {
                                    return CustomPaint(
                                      size: Size(constraints.maxWidth, constraints.maxWidth), // Квадратная доска
                                      painter: BlockPreviewPainter(
                                        block: draggedBlock!,
                                        row: previewRow,
                                        col: previewCol,
                                        boardSize: boardSize,
                                        cellSize: actualCellSize,
                                        color: primaryColor.withOpacity(_pulseAnimation.value),
                                        isValid: _canPlaceBlock(draggedBlock!, previewRow, previewCol),
                                      ),
                                    );
                                  }
                                ),
                              );
                            },
                          );
                        }
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          // Анимация комбо и бонусных очков
          if (showComboAnimation && mounted)
            Positioned(
              top: 10,
              right: 10,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value > 0.8 ? (1.0 - (value - 0.8) * 5) : value * 1.25, // Появление и исчезновение
                    child: Transform.scale(
                      scale: 0.8 + value * 0.5, // Анимация увеличения
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: comboCount > 1 
                              ? Colors.orange.withOpacity(0.9) 
                              : Colors.green.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: (comboCount > 1 ? Colors.orange : Colors.green).withOpacity(0.5),
                              blurRadius: 15,
                              spreadRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              comboCount > 1 
                                  ? 'КОМБО x$comboCount!' 
                                  : (lastLinesClearedCount > 1 ? 'БОНУС!' : '+$bonusPoints'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                shadows: [
                                  Shadow(
                                    offset: Offset(1, 1),
                                    blurRadius: 3,
                                    color: Colors.black54,
                                  ),
                                ],
                              ),
                            ),
                            if (comboCount > 1 || lastLinesClearedCount > 1)
                              Text(
                                '+$bonusPoints',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22,
                                  shadows: [
                                    Shadow(
                                      offset: Offset(1, 1),
                                      blurRadius: 3,
                                      color: Colors.black54,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
  
  // Строим ячейку доски
  Widget _buildCell(int row, int col, bool isDarkMode) {
    final cell = board[row][col];
    final bool isAnimating = animatingRows.contains(row) || animatingCols.contains(col);
    final bool isHighlighted = highlightRows.contains(row) || highlightCols.contains(col);
    
    return AnimatedOpacity(
      opacity: isAnimating ? lineOpacity : 1.0,
      duration: const Duration(milliseconds: 50),
      child: Container(
        margin: EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: cell.isFilled 
              ? isAnimating 
                ? cell.color.withOpacity(lineOpacity * 0.8)
                : cell.color.withOpacity(0.8) 
              : isHighlighted
                ? (isDarkMode ? Colors.amber.withOpacity(0.25) : Colors.amber.withOpacity(0.15))
                : isDarkMode 
                    ? Colors.grey[900]!.withOpacity(0.6) 
                    : Colors.white.withOpacity(0.6),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isHighlighted
                ? Colors.amber
                : isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
            width: isHighlighted ? 1.5 : 1,
          ),
        ),
        child: isAnimating && cell.isFilled
            ? Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 10 * lineOpacity,
                  height: 10 * lineOpacity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              )
            : isHighlighted && !cell.isFilled
              ? Center(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                  ),
                )
              : null,
      ),
    );
  }
  
  // Строим подсветку ячейки доски
  Widget _buildCellHighlight(int row, int col, bool isDarkMode, Color primaryColor) {
    // Больше не используем этот метод для подсветки ячеек
    return Container(); // Пустой контейнер
  }
  
  // Строим селектор блоков
  Widget _buildBlockSelector(bool isDarkMode, Color surfaceColor, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      decoration: BoxDecoration(
        color: isDarkMode 
            ? Colors.grey[900]!.withOpacity(0.7) 
            : Colors.white.withOpacity(0.7),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (int i = 0; i < availableBlocks.length; i++)
            Draggable<Block>(
              maxSimultaneousDrags: 1, // Разрешаем только одно перетаскивание за раз
              dragAnchorStrategy: (draggable, context, position) {
                // Возвращаем центр виджета для лучшего позиционирования
                final RenderBox renderObject = context.findRenderObject() as RenderBox;
                return Offset(renderObject.size.width / 2, renderObject.size.height / 2);
              },
              data: availableBlocks[i],
              feedback: _buildBlockFeedback(availableBlocks[i], isDarkMode, primaryColor),
              childWhenDragging: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                ),
              ),
              onDragStarted: () {
                setState(() {
                  selectedBlock = availableBlocks[i];
                  selectedBlockIndex = i;
                  isDragging = true;
                  draggedBlock = availableBlocks[i];
                  
                  // Сбрасываем позицию предпросмотра
                  previewRow = -1;
                  previewCol = -1;
                });
              },
              onDragUpdate: (details) {
                // Обновляем превью при каждом изменении положения
                if (draggedBlock != null) {
                  _updatePreview(draggedBlock!, details.globalPosition);
                }
              },
              onDraggableCanceled: (_, __) {
                setState(() {
                  _resetPreview();
                });
              },
              onDragEnd: (details) {
                // Проверяем, был ли блок размещен, если нет - сбрасываем превью
                if (details.wasAccepted == false && draggedBlock != null && 
                    previewRow >= 0 && previewCol >= 0 && 
                    _canPlaceBlock(draggedBlock!, previewRow, previewCol)) {
                  // Если перетаскивание закончилось, но блок можно разместить - размещаем его
                  _placeBlock(draggedBlock!, previewRow, previewCol);
                }
                
                setState(() {
                  _resetPreview();
                });
              },
              onDragCompleted: () {
                // Очищаем после успешного размещения
                setState(() {
                  _resetPreview();
                });
              },
              child: _buildBlockPreview(availableBlocks[i], isDarkMode: isDarkMode),
            ),
        ],
      ),
    );
  }
  
  // Виджет для отображения блока при перетаскивании (feedback)
  Widget _buildBlockFeedback(Block block, bool isDarkMode, Color primaryColor) {
    final int rows = block.shape.length;
    final int cols = block.shape[0].length;
    final double cellSize = 36.0; // Увеличиваем размер для лучшей видимости
    
    return Material(
      color: Colors.transparent,
      elevation: 12, // Увеличиваем тень
      shadowColor: Colors.black54,
      child: Container(
        width: cellSize * cols,
        height: cellSize * rows,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: CustomPaint(
            size: Size(cellSize * cols, cellSize * rows),
            painter: FeedbackBlockPainter(
              block: block,
              cellSize: cellSize,
              color: block.color,
              isDarkMode: isDarkMode,
            ),
          ),
        ),
      ),
    );
  }
  
  // Строим предпросмотр блока
  Widget _buildBlockPreview(Block block, {bool isPreview = false, required bool isDarkMode}) {
    final int rows = block.shape.length;
    final int cols = block.shape[0].length;
    final double cellSize = isPreview ? 24.0 : 20.0;
    
    return Container(
      width: 100,
      height: 100,
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: isDarkMode 
            ? Colors.grey[850]!.withOpacity(0.7) 
            : Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        boxShadow: isPreview
            ? [BoxShadow(color: Colors.black26, blurRadius: 8.0, spreadRadius: 2.0)]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4.0,
                  offset: const Offset(0, 2),
                )
              ],
      ),
      child: Center(
        child: SizedBox(
          width: cellSize * cols,
          height: cellSize * rows,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              childAspectRatio: 1.0,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            itemCount: rows * cols,
            itemBuilder: (context, index) {
              final int r = index ~/ cols;
              final int c = index % cols;
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: block.shape[r][c] 
                      ? Colors.transparent 
                      : Colors.transparent,
                  border: Border.all(
                    color: block.shape[r][c]
                        ? block.color
                        : (isDarkMode ? Colors.grey[700]! : Colors.grey[300]!),
                    width: block.shape[r][c] ? 2 : 1,
                  ),
                ),
                child: block.shape[r][c]
                    ? Center(
                        child: Container(
                          width: cellSize * 0.6,
                          height: cellSize * 0.6,
                          decoration: BoxDecoration(
                            color: block.color.withOpacity(0.7),
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              );
            },
          ),
        ),
      ),
    );
  }
  
  // Завершаем игру
  void _gameOver() {
    _saveHighScore();
    _markGameAsOver();
    
    // Добавляем задержку перед показом экрана окончания игры
    // Это даст пользователю возможность увидеть последний ход
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          gameState = GameState.gameOver;
        });
      }
    });
  }

  // Добавляем методы для начальной страницы
  Future<bool> _hasSavedGame() async {
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

  // Начинаем новую игру и очищаем сохранение
  void _startNewGame() {
    setState(() {
      // Очищаем сохраненную игру
      _clearSavedGame();
      
      // Очищаем доску
      for (int i = 0; i < boardSize; i++) {
        for (int j = 0; j < boardSize; j++) {
          board[i][j].isFilled = false;
          board[i][j].color = Colors.transparent;
        }
      }
      
      // Полностью сбрасываем состояние игры
      score = 0;
      placedBlocksCount = 0;
      
      // Очищаем старые блоки и создаём новые
      availableBlocks.clear();
      _generateBlocks();
      
      // Переходим в состояние игры
      gameState = GameState.playing;
    });
  }

  // Продолжаем сохраненную игру
  void _continueGame() async {
    await _loadGameState();
    setState(() {
      gameState = GameState.playing;
    });
  }

  // Очистка сохраненной игры
  Future<void> _clearSavedGame() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('minigame_saved_state');
  }

  // Обновление превью размещения блока
  bool _updatePreview(Block block, Offset pointerPosition) {
    // Получаем глобальные координаты игрового поля
    final RenderBox? boardBox = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (boardBox == null) return false;

    // Получаем локальные координаты указателя относительно игрового поля
    final Offset localPosition = boardBox.globalToLocal(pointerPosition);
    
    // Определяем границы игрового поля
    final double boardWidth = boardBox.size.width;
    final double boardHeight = boardBox.size.height;
    
    // Проверяем, находится ли указатель в пределах игрового поля
    if (localPosition.dx < 0 || localPosition.dx > boardWidth || 
        localPosition.dy < 0 || localPosition.dy > boardHeight) {
      // Указатель за пределами игрового поля
      setState(() {
        previewRow = -1;
        previewCol = -1;
        isDragging = false;
        highlightRows = [];
        highlightCols = [];
      });
      return false;
    }
    
    // Рассчитываем размер ячейки
    final cellSize = boardWidth / boardSize;
    
    // Рассчитываем строку и столбец на основе локального положения 
    int newRow = (localPosition.dy / cellSize).floor();
    int newCol = (localPosition.dx / cellSize).floor();
    
    // Блок должен располагаться вокруг курсора, поэтому вычитаем половину размера блока
    int adjustedRow = newRow - (block.shape.length ~/ 2);
    int adjustedCol = newCol - (block.shape[0].length ~/ 2);
    
    // Ограничиваем координаты, чтобы блок не выходил за пределы доски
    adjustedRow = math.max(0, math.min(adjustedRow, boardSize - block.shape.length));
    adjustedCol = math.max(0, math.min(adjustedCol, boardSize - block.shape[0].length));
    
    // Проверяем, можно ли разместить блок
    bool canPlace = _canPlaceBlock(block, adjustedRow, adjustedCol);
    
    // Обновляем подсветку линий, которые будут заполнены после размещения блока
    _updateHighlightLinesForBlock(block, adjustedRow, adjustedCol);
    
    // Обновляем состояние только если позиция изменилась
    if (previewRow != adjustedRow || previewCol != adjustedCol || isDragging == false || draggedBlock != block) {
      setState(() {
        previewRow = adjustedRow;
        previewCol = adjustedCol;
        isDragging = true;
        draggedBlock = block;
      });
    }
    
    return canPlace;
  }
  
  // Проверяем и обновляем подсветку линий, которые будут заполнены после размещения блока
  void _updateHighlightLinesForBlock(Block block, int row, int col) {
    // Сначала проверяем, можно ли разместить блок в указанной позиции
    if (!_canPlaceBlock(block, row, col)) {
      setState(() {
        highlightRows = [];
        highlightCols = [];
      });
      return;
    }
    
    // Копируем текущее состояние доски для проверки
    List<List<bool>> tempBoard = List.generate(
      boardSize, 
      (i) => List.generate(
        boardSize, 
        (j) => board[i][j].isFilled,
      ),
    );
    
    // Симулируем размещение блока на временной доске
    for (int i = 0; i < block.shape.length; i++) {
      for (int j = 0; j < block.shape[i].length; j++) {
        if (block.shape[i][j]) {
          int boardRow = row + i;
          int boardCol = col + j;
          
          // Проверяем границы
          if (boardRow >= 0 && boardRow < boardSize && boardCol >= 0 && boardCol < boardSize) {
            tempBoard[boardRow][boardCol] = true;
          }
        }
      }
    }
    
    // Находим заполненные строки
    List<int> newHighlightRows = [];
    for (int i = 0; i < boardSize; i++) {
      bool isRowFull = true;
      for (int j = 0; j < boardSize; j++) {
        if (!tempBoard[i][j]) {
          isRowFull = false;
          break;
        }
      }
      if (isRowFull) {
        newHighlightRows.add(i);
      }
    }
    
    // Находим заполненные столбцы
    List<int> newHighlightCols = [];
    for (int j = 0; j < boardSize; j++) {
      bool isColFull = true;
      for (int i = 0; i < boardSize; i++) {
        if (!tempBoard[i][j]) {
          isColFull = false;
          break;
        }
      }
      if (isColFull) {
        newHighlightCols.add(j);
      }
    }
    
    // Обновляем состояние только если подсветка изменилась
    if (!_listEquals(highlightRows, newHighlightRows) || !_listEquals(highlightCols, newHighlightCols)) {
      setState(() {
        highlightRows = newHighlightRows;
        highlightCols = newHighlightCols;
      });
    }
  }
  
  // Вспомогательная функция для сравнения списков
  bool _listEquals(List<int> list1, List<int> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) return false;
    }
    return true;
  }

  // Размещаем блок на игровой доске
  void _placeBlock(Block block, int row, int col) {
    // Проверяем, что координаты находятся в допустимом диапазоне
    if (row < 0 || col < 0 || row >= boardSize || col >= boardSize) {
      return;
    }

    // Проверяем, что блок можно поместить в указанную позицию
    if (!_canPlaceBlock(block, row, col)) {
      return;
    }

    // Вычисляем размер размещаемого блока (количество ячеек)
    int blockSize = block.shape.fold(0, (sum, row) => sum + row.where((cell) => cell).length);

    try {
      // Размещаем блок на доске
      for (int i = 0; i < block.shape.length; i++) {
        for (int j = 0; j < block.shape[i].length; j++) {
          if (block.shape[i][j]) {
            int boardRow = row + i;
            int boardCol = col + j;
            
            // Дополнительная проверка границ
            if (boardRow >= 0 && boardRow < boardSize && 
                boardCol >= 0 && boardCol < boardSize) {
              board[boardRow][boardCol].isFilled = true;
              board[boardRow][boardCol].color = block.color;
            }
          }
        }
      }

      // Обновляем состояние и проверяем завершение игры
      setState(() {
        // Удаляем размещенный блок из доступных блоков
        availableBlocks.remove(block);
        placedBlocksCount++;
        
        // Сбрасываем состояние перетаскивания
        draggedBlock = null;
        isDragging = false;
        
        // Сбрасываем подсветку линий
        highlightRows = [];
        highlightCols = [];
        
        // Обновляем счет - считаем количество true ячеек в матрице формы блока
        score += blockSize;
        
        // Показываем анимацию +1 за каждую ячейку
        _showBlockPlacementPoints(block, row, col, blockSize);

        // Проверяем заполненные линии
        _checkLines();
        
        // Генерируем новые блоки если нужно
        _generateBlocks();
        
        // Проверяем возможность продолжения
        if (!_canContinueGame()) {
          _gameOver();
        }
      });

      // Запускаем анимацию размещения
      _animationController.reset();
      _animationController.forward();
      
      // Сохраняем состояние игры
      _saveGameState();
    } catch (e) {
      // Обрабатываем любые ошибки при размещении блока
      debugPrint('Ошибка при размещении блока: $e');
    }
  }

  // Показываем анимацию начисления очков при размещении блока
  void _showBlockPlacementPoints(Block block, int startRow, int startCol, int points) {
    if (!mounted) return; // Проверка mounted перед показом анимации
    
    try {
      // Получаем глобальные координаты игрового поля
      final RenderBox? boardBox = _boardKey.currentContext?.findRenderObject() as RenderBox?;
      if (boardBox == null) return;

      // Определяем центр размещенного блока для позиционирования эффекта
      double centerX = 0;
      double centerY = 0;
      int cellCount = 0;

      for (int i = 0; i < block.shape.length; i++) {
        for (int j = 0; j < block.shape[i].length; j++) {
          if (block.shape[i][j]) {
            centerX += (startCol + j);
            centerY += (startRow + i);
            cellCount++;
          }
        }
      }

      // Находим средние координаты
      if (cellCount > 0) {
        centerX = centerX / cellCount;
        centerY = centerY / cellCount;
      }

      // Размер ячейки для позиционирования
      final double cellSize = boardBox.size.width / boardSize;
      
      // Предварительно объявляем переменную
      late OverlayEntry entry;
      
      // Добавляем виджет с анимацией +N очков
      entry = OverlayEntry(
        builder: (context) {
          return Positioned(
            left: boardBox.localToGlobal(Offset.zero).dx + centerX * cellSize,
            top: boardBox.localToGlobal(Offset.zero).dy + centerY * cellSize - 20,
            child: PointsAnimation(
              key: GlobalKey(),
              points: points,
              color: block.color,
              onComplete: () {
                // Удаляем оверлей после завершения анимации
                try {
                  entry.remove();
                } catch (e) {
                  debugPrint('Ошибка при удалении оверлей анимации очков: $e');
                }
              },
            ),
          );
        }
      );
      
      // Безопасно вставляем оверлей
      final overlayState = Overlay.of(context);
      if (overlayState != null && mounted) {
        overlayState.insert(entry);
      }
    } catch (e) {
      debugPrint('Ошибка при показе анимации очков: $e');
    }
  }
  
  // Улучшаем метод сброса превью для более надежной работы
  void _resetPreview() {
    if (mounted) {
      setState(() {
        previewRow = -1;
        previewCol = -1;
        isDragging = false;
        draggedBlock = null;
        highlightRows = [];
        highlightCols = [];
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    // Обновляем флаг темы при каждой перерисовке
    _isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    final primaryColor = Theme.of(context).colorScheme.primary;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final textColor = Theme.of(context).colorScheme.onSurface;
    
    return Scaffold(
      appBar: gameState == GameState.playing 
      ? AppBar(
          title: _buildScoreWidget(_isDarkMode, primaryColor), // Красивый виджет счёта
          elevation: 0,
          centerTitle: true,
          // Добавляем кнопку назад для возврата в меню
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              setState(() {
                gameState = GameState.notStarted;
                _saveGameState();
              });
            },
            tooltip: 'Вернуться в меню',
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _restartGame,
              tooltip: 'Новая игра',
            ),
          ],
        )
      : AppBar(
          title: const Text('Мини игра'),
          elevation: 0,
        ),
      body: Stack(
        children: [
          // Анимированный фон на заднем плане
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBackgroundWidget(isDarkMode: _isDarkMode),
            ),
          ),
          
          // Основной контент поверх фона
          LayoutBuilder(
            builder: (context, constraints) {
              // Сохраняем размеры доски для корректных расчетов
              final boardWidth = constraints.maxWidth;
              final boardHeight = constraints.maxHeight;
              final cellSize = boardWidth / boardSize;
              
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: _isDarkMode
                        ? [Colors.black87.withOpacity(0.5), Colors.black54.withOpacity(0.5)]
                        : [Colors.blue.shade50.withOpacity(0.5), Colors.white.withOpacity(0.5)],
                  ),
                ),
                child: _buildGameContent(_isDarkMode, primaryColor, surfaceColor, textColor, cellSize),
              );
            }
          ),
        ],
      ),
    );
  }
  
  // Красивый виджет для отображения счёта и рекорда
  Widget _buildScoreWidget(bool isDarkMode, Color primaryColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.grey[800] : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.star,
                color: Colors.amber,
                size: 20,
              ),
              SizedBox(width: 4),
              Text(
                '$score',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 8),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.grey[850] : Colors.grey[100],
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.emoji_events,
                color: Colors.orange,
                size: 20,
              ),
              SizedBox(width: 4),
              Text(
                '$highScore',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  // Строим содержимое игры в зависимости от состояния
  Widget _buildGameContent(bool isDarkMode, Color primaryColor, Color surfaceColor, Color textColor, double cellSize) {
    switch (gameState) {
      case GameState.notStarted:
        return _buildStartScreen(isDarkMode, primaryColor, textColor);
      case GameState.playing:
        return _buildGameScreen(isDarkMode, surfaceColor, primaryColor, cellSize);
      case GameState.gameOver:
        return _buildGameOverScreen(isDarkMode, primaryColor, textColor);
    }
  }
  
  // Начальный экран
  Widget _buildStartScreen(bool isDarkMode, Color primaryColor, Color textColor) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDarkMode 
              ? [Colors.grey[900]!.withOpacity(0.6), Colors.black.withOpacity(0.6)]
              : [Colors.blue[100]!.withOpacity(0.6), Colors.blue[50]!.withOpacity(0.6)],
        ),
      ),
      child: Center(
        child: Card(
          elevation: 12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          color: isDarkMode 
              ? Colors.grey[850]!.withOpacity(0.8) 
              : Colors.white.withOpacity(0.8),
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Отображаем рекорд сверху
                if (highScore > 0)
                  Container(
                    margin: const EdgeInsets.only(bottom: 24),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.emoji_events, color: primaryColor, size: 28),
                        const SizedBox(width: 8),
                        Text(
                          'Рекорд: $highScore',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                
                // Новая иконка, более соответствующая игре
                Icon(
                  Icons.app_registration, // Иконка, больше подходящая для игры
                  size: 80,
                  color: primaryColor,
                ),
                const SizedBox(height: 24),
                
                const SizedBox(height: 32),

                // Добавляем проверку наличия сохраненной игры и что она не завершена
                FutureBuilder<Map<String, dynamic>>(
                  future: _getGameStatus(),
                  builder: (context, snapshot) {
                    final Map<String, dynamic> gameStatus = snapshot.data ?? {'hasSavedGame': false, 'isGameOver': false};
                    final bool hasSavedGame = gameStatus['hasSavedGame'];
                    final bool isGameOver = gameStatus['isGameOver'];
                    
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton(
                          onPressed: _startNewGame,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: isDarkMode ? Colors.white : Colors.black87,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            minimumSize: const Size(240, 60),
                          ),
                          child: const Text(
                            'НОВАЯ ИГРА',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        
                        // Показываем кнопку продолжить только если есть сохраненная игра и она не завершена
                        if (hasSavedGame && !isGameOver) ...[
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: _continueGame,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: primaryColor,
                              side: BorderSide(color: primaryColor, width: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              minimumSize: const Size(240, 60),
                            ),
                            child: const Text(
                              'ПРОДОЛЖИТЬ',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  // Экран игры
  Widget _buildGameScreen(bool isDarkMode, Color surfaceColor, Color primaryColor, double cellSize) {
    return Column(
      children: [
        // Игровая доска занимает большую часть экрана
        Expanded(
          flex: 5,
          child: _buildGameBoard(isDarkMode, surfaceColor, primaryColor, cellSize),
        ),
        // Селектор блоков занимает меньшую часть
        SizedBox(
          height: 120, // Увеличиваем высоту для селектора блоков
          child: _buildBlockSelector(isDarkMode, surfaceColor, primaryColor),
        ),
      ],
    );
  }
  
  // Экран окончания игры
  Widget _buildGameOverScreen(bool isDarkMode, Color primaryColor, Color textColor) {
    return Center(
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        color: isDarkMode 
            ? Colors.grey[850]!.withOpacity(0.8) 
            : Colors.white.withOpacity(0.8),
        margin: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.emoji_events,
                size: 64,
                color: primaryColor,
              ),
              const SizedBox(height: 16),
              Text(
                'Игра окончена!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Ваш счет: $score',
                style: TextStyle(
                  fontSize: 20,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Лучший результат: $highScore',
                style: TextStyle(
                  fontSize: 18,
                  color: primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      // При возврате в меню после проигрыша сохраняем состояние как проигранное
                      _markGameAsOver();
                      setState(() {
                        gameState = GameState.notStarted;
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      side: BorderSide(color: primaryColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Главное меню',
                      style: TextStyle(
                        color: primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _restartGame,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: isDarkMode ? Colors.white : Colors.black87,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Играть снова',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Добавляем метод для маркировки игры как проигранной
  Future<void> _markGameAsOver() async {
    final prefs = await SharedPreferences.getInstance();
    final savedStateJson = prefs.getString('minigame_saved_state');
    if (savedStateJson != null) {
      try {
        final gameStateMap = jsonDecode(savedStateJson) as Map<String, dynamic>;
        gameStateMap['isGameOver'] = true;
        await prefs.setString('minigame_saved_state', jsonEncode(gameStateMap));
      } catch (e) {
        // Игнорируем ошибки
      }
    }
  }

  // Получаем статус игры (сохранена ли и не закончена ли)
  Future<Map<String, dynamic>> _getGameStatus() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Пытаемся загрузить сохраненное состояние
    final savedStateJson = prefs.getString('minigame_saved_state');
    if (savedStateJson == null) {
      return {'hasSavedGame': false, 'isGameOver': false};
    }
    
    try {
      final gameStateMap = jsonDecode(savedStateJson) as Map<String, dynamic>;
      final savedGameState = gameStateMap['gameState'] ?? 0;
      final isGameOver = gameStateMap['isGameOver'] ?? false;
      
      return {
        'hasSavedGame': GameState.values[savedGameState] == GameState.playing,
        'isGameOver': isGameOver || GameState.values[savedGameState] == GameState.gameOver,
      };
    } catch (e) {
      return {'hasSavedGame': false, 'isGameOver': false};
    }
  }
}

// Класс для анимированного фона
class AnimatedBackgroundWidget extends StatefulWidget {
  final bool isDarkMode;
  
  const AnimatedBackgroundWidget({
    Key? key,
    required this.isDarkMode,
  }) : super(key: key);

  @override
  State<AnimatedBackgroundWidget> createState() => _AnimatedBackgroundWidgetState();
}

class _AnimatedBackgroundWidgetState extends State<AnimatedBackgroundWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<BackgroundParticle> particles;
  final int particleCount = 40; // Увеличиваем количество частиц для большей хаотичности
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60), // Увеличиваем продолжительность для более плавного движения
    )..repeat();
    
    // Создаем частицы с разными временными параметрами
    particles = List.generate(particleCount, (_) => BackgroundParticle.random());
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return RepaintBoundary(
          child: CustomPaint(
            painter: BackgroundPainter(
              particles: particles,
              animationValue: _controller.value,
              isDarkMode: widget.isDarkMode,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }
}

// Класс для частицы фона
class BackgroundParticle {
  Offset startPosition;
  Offset endPosition;
  final double size;
  final Color color;
  final double speed;
  final double opacity;
  double startTime; // Начальное время для плавной анимации
  double direction; // Направление движения (для внесения хаотичности)
  
  BackgroundParticle({
    required this.startPosition,
    required this.endPosition,
    required this.size,
    required this.color,
    required this.speed,
    required this.opacity,
    required this.startTime,
    required this.direction,
  });
  
  factory BackgroundParticle.random() {
    final random = Random();
    
    return BackgroundParticle(
      startPosition: Offset(
        random.nextDouble() * 1.2 - 0.1, // Может начинаться немного за экраном
        random.nextDouble() * 1.2 - 0.1,
      ),
      endPosition: Offset(
        random.nextDouble() * 1.2 - 0.1,
        random.nextDouble() * 1.2 - 0.1,
      ),
      size: random.nextDouble() * 20 + 10, // От 10 до 30
      color: HSLColor.fromAHSL(
        0.7, // Увеличиваем непрозрачность
        random.nextDouble() * 360, // Случайный оттенок
        0.7, // Насыщенность
        0.7, // Яркость
      ).toColor(),
      speed: random.nextDouble() * 0.3 + 0.02, // От 0.02 до 0.32 - более плавное движение
      opacity: random.nextDouble() * 0.3 + 0.1, // Случайная прозрачность
      startTime: random.nextDouble(), // Случайное начальное время для эффекта разнообразия
      direction: random.nextDouble() * math.pi * 2, // Случайное направление в радианах
    );
  }
  
  Offset getPosition(double animationValue) {
    // Изменяем позицию с учетом скорости и начального времени
    final adjustedValue = ((animationValue + startTime) * speed) % 1.0;
    
    // Добавляем синусоидальное движение в направлении direction для хаотичности
    final chaosValue = math.sin(adjustedValue * math.pi * 4) * 0.05;
    final chaosOffset = Offset(
      math.cos(direction) * chaosValue,
      math.sin(direction) * chaosValue
    );
    
    // Используем синусоидальный переход для более плавного движения
    final transition = (math.sin((adjustedValue * math.pi - math.pi / 2)) + 1) / 2;
    
    // Основная позиция с добавлением хаотичности
    final basePosition = Offset.lerp(startPosition, endPosition, transition)!;
    
    // Если почти завершили цикл, генерируем новую конечную точку, но сохраняем текущую как начальную
    if (adjustedValue > 0.8) {
      final random = Random();
      final fadeOutFactor = (1.0 - (adjustedValue - 0.8) * 5); // Фактор затухания от 1.0 до 0.0
      
      // Если полностью завершили цикл, обновляем параметры
      if (adjustedValue > 0.99) {
        startPosition = endPosition;
        endPosition = Offset(
          random.nextDouble() * 1.2 - 0.1,
          random.nextDouble() * 1.2 - 0.1,
        );
        startTime = (animationValue + 0.02) % 1.0; // Небольшой сдвиг для плавного перехода
        direction = random.nextDouble() * math.pi * 2; // Обновляем направление для большей хаотичности
      }
      
      // Возвращаем позицию с учетом затухания
      return basePosition + chaosOffset * fadeOutFactor;
    }
    
    return basePosition + chaosOffset;
  }
  
  // Получаем текущую прозрачность в зависимости от анимации
  double getCurrentOpacity(double animationValue) {
    final cyclePosition = ((animationValue + startTime) * speed) % 1.0;
    
    // Плавно изменяем прозрачность
    if (cyclePosition < 0.02) {
      // Плавное появление в начале траектории (первые 2%)
      return opacity * (cyclePosition * 50); // 0.02 * 50 = 1.0
    } else if (cyclePosition > 0.8) {
      // Плавное затухание в конце траектории (после 80%)
      return opacity * (1.0 - (cyclePosition - 0.8) * 5); // 0.2 * 5 = 1.0
    } else {
      // Нормальная прозрачность в середине траектории
      return opacity;
    }
  }
}

// Художник для анимированного фона
class BackgroundPainter extends CustomPainter {
  final List<BackgroundParticle> particles;
  final double animationValue;
  final bool isDarkMode;
  
  BackgroundPainter({
    required this.particles,
    required this.animationValue,
    required this.isDarkMode,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      final position = particle.getPosition(animationValue);
      final currentOpacity = particle.getCurrentOpacity(animationValue);
      
      // Преобразуем нормализованную позицию в пиксели
      final pixelPosition = Offset(
        position.dx * size.width,
        position.dy * size.height,
      );
      
      // Рисуем частицу как градиентный круг с мягкими краями
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            particle.color.withOpacity(currentOpacity),
            particle.color.withOpacity(0.0),
          ],
          stops: [0.3, 1.0], // Добавляем остановки для более резкого градиента
        ).createShader(Rect.fromCircle(
          center: pixelPosition,
          radius: particle.size,
        ));
      
      canvas.drawCircle(
        pixelPosition,
        particle.size,
        paint,
      );
      
      // Рисуем блики для более привлекательного эффекта
      if (particle.size > 15) {
        final blickPaint = Paint()
          ..color = Colors.white.withOpacity(currentOpacity * 0.4)
          ..style = PaintingStyle.fill;
        
        canvas.drawCircle(
          Offset(
            pixelPosition.dx - particle.size * 0.2,
            pixelPosition.dy - particle.size * 0.2,
          ),
          particle.size * 0.3,
          blickPaint,
        );
      }
    }
  }
  
  @override
  bool shouldRepaint(covariant BackgroundPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

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
    // Не рисуем если не находимся на доске или нет допустимой позиции
    if (row < 0 || col < 0) return;

    // Рисуем только если можно разместить блок
    if (!isValid) return;

    final Paint borderPaint = Paint()
      ..color = Colors.green.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final Paint fillPaint = Paint()
      ..color = Colors.green.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    // Проходимся по всем ячейкам блока
    for (int i = 0; i < block.shape.length; i++) {
      for (int j = 0; j < block.shape[i].length; j++) {
        if (block.shape[i][j]) {
          final int boardRow = row + i;
          final int boardCol = col + j;
          
          // Проверяем, что ячейка находится в пределах игрового поля
          if (boardRow >= 0 && boardRow < boardSize && boardCol >= 0 && boardCol < boardSize) {
            // Рисуем заполнение
            final Rect fillRect = Rect.fromLTWH(
              boardCol * cellSize,
              boardRow * cellSize,
              cellSize,
              cellSize,
            );
            canvas.drawRect(fillRect, fillPaint);
            
            // Рисуем границу
            final Rect borderRect = Rect.fromLTWH(
              boardCol * cellSize,
              boardRow * cellSize,
              cellSize,
              cellSize,
            );
            canvas.drawRect(borderRect, borderPaint);
            
            // Добавляем внутренний маркер для лучшей видимости
            final Rect innerRect = Rect.fromLTWH(
              boardCol * cellSize + cellSize * 0.25,
              boardRow * cellSize + cellSize * 0.25,
              cellSize * 0.5,
              cellSize * 0.5,
            );
            canvas.drawRect(
              innerRect, 
              Paint()
                ..color = Colors.green.withOpacity(0.8)
                ..style = PaintingStyle.fill
            );
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is BlockPreviewPainter) {
      return oldDelegate.row != row ||
          oldDelegate.col != col ||
          oldDelegate.isValid != isValid ||
          oldDelegate.color != color;
    }
    return true;
  }
} 

// Добавляем класс анимации очков в конец файла
class PointsAnimation extends StatefulWidget {
  final int points;
  final Color color;
  final VoidCallback onComplete;

  const PointsAnimation({
    Key? key,
    required this.points,
    required this.color,
    required this.onComplete,
  }) : super(key: key);

  @override
  State<PointsAnimation> createState() => _PointsAnimationState();
}

class _PointsAnimationState extends State<PointsAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _positionAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.0), weight: 60),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0), weight: 20),
    ]).animate(_controller);

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.5, end: 1.3), weight: 30),
      TweenSequenceItem(tween: Tween<double>(begin: 1.3, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.8), weight: 20),
    ]).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _positionAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -50),
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    try {
      _controller.forward().then((_) {
        if (mounted) {
          widget.onComplete();
        }
      });
    } catch (e) {
      debugPrint('Ошибка при запуске анимации очков: $e');
      // В случае ошибки, все равно пытаемся вызвать onComplete
      widget.onComplete();
    }
  }

  @override
  void dispose() {
    try {
      _controller.dispose();
    } catch (e) {
      debugPrint('Ошибка при очистке контроллера анимации: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: _positionAnimation.value,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  '+${widget.points}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    shadows: [
                      Shadow(
                        offset: Offset(1, 1),
                        blurRadius: 2,
                        color: Colors.black54,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
} 