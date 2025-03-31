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

class _MinigameScreenState extends State<MinigameScreen> with SingleTickerProviderStateMixin {
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
  void dispose() {
    _animationController.dispose();
    super.dispose();
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
        if (block.shape[i][j] == 1) {
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
      _initNewGame(); // Заменяем _initGame на _initNewGame
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
    
    // Очищаем заполненные строки и столбцы
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
    
    // Начисляем очки
    int clearedLines = fullRows.length + fullCols.length;
    if (clearedLines > 0) {
      // Даем бонус за несколько линий сразу
      int basePoints = 10;
      int totalPoints = basePoints * clearedLines;
      
      if (clearedLines >= 2) {
        totalPoints = (totalPoints * 1.5).toInt(); // Бонус за 2+ линии
      }
      if (clearedLines >= 3) {
        totalPoints = (totalPoints * 1.5).toInt(); // Дополнительный бонус за 3+ линий
      }
      
      setState(() {
        score += totalPoints;
      });
      
      _saveHighScore();
    }
  }
  
  // Проверяем, можно ли продолжить игру
  bool _canContinueGame() {
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
      child: Container(
        key: _boardKey, // Добавляем ключ для доступа к размерам
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.grey[850] : Colors.grey[100],
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
                        onWillAccept: (block) => block != null,
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
    );
  }
  
  // Строим ячейку доски
  Widget _buildCell(int row, int col, bool isDarkMode) {
    final cell = board[row][col];
    
    return Container(
      margin: EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: cell.isFilled 
            ? cell.color // Убираем прозрачность, чтобы не мигали
            : isDarkMode ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
          width: 1,
        ),
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
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[900] : Colors.white,
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
      child: Column(
        children: [
          Text(
            'Доступные блоки',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
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
                      width: 80,
                      height: 80,
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
    final double cellSize = isPreview ? 20.0 : 16.0;
    
    return Container(
      width: 80,
      height: 80,
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[850] : Colors.white,
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
    setState(() {
      gameState = GameState.gameOver;
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

    try {
      // Размещаем блок на доске
      for (int i = 0; i < block.shape.length; i++) {
        for (int j = 0; j < block.shape[i].length; j++) {
          if (block.shape[i][j] == 1) {
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
        
        // Обновляем счет
        score += block.shape.expand((row) => row).where((cell) => cell == 1).length;
        
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
  
  // Улучшаем метод сброса превью для более надежной работы
  void _resetPreview() {
    if (mounted) {
      setState(() {
        previewRow = -1;
        previewCol = -1;
        isDragging = false;
        draggedBlock = null;
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
      appBar: AppBar(
        title: const Text('КолледжБлоки'),
        elevation: 0,
        // Добавляем кнопку назад в appBar для состояния игры
        leading: gameState == GameState.playing 
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    gameState = GameState.notStarted;
                    _saveGameState();
                  });
                },
                tooltip: 'Вернуться в меню',
              )
            : null,
        actions: [
          // Отображаем текущий счет и лучший результат
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Center(
              child: Text(
                'Счет: $score | Рекорд: $highScore',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Сохраняем размеры доски для корректных расчетов
          final boardWidth = constraints.maxWidth;
          final boardHeight = constraints.maxHeight * 0.75; // 75% для игровой доски
          final cellSize = boardWidth / boardSize;
          
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: _isDarkMode
                    ? [Colors.black87, Colors.black54]
                    : [Colors.blue.shade50, Colors.white],
              ),
            ),
            child: _buildGameContent(_isDarkMode, primaryColor, surfaceColor, textColor, cellSize),
          );
        }
      ),
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
              ? [Colors.grey[900]!, Colors.black]
              : [Colors.blue[100]!, Colors.blue[50]!],
        ),
      ),
      child: Center(
        child: Card(
          elevation: 12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          color: isDarkMode ? Colors.grey[850] : Colors.white,
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.grid_4x4,
                  size: 80,
                  color: primaryColor,
                ),
                const SizedBox(height: 24),
                Text(
                  'КолледжБлоки',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.grey[800] : Colors.blue[50],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'Размещайте блоки разных цветов и форм,\nзаполняйте строки и столбцы для получения очков!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: textColor.withOpacity(0.9),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Добавляем проверку наличия сохраненной игры
                FutureBuilder<bool>(
                  future: _hasSavedGame(),
                  builder: (context, snapshot) {
                    final bool hasSavedGame = snapshot.data ?? false;
                    
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
                        
                        if (hasSavedGame) ...[
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

                const SizedBox(height: 24),
                if (highScore > 0)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.emoji_events, color: primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          'Ваш рекорд: $highScore',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
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
        // Игровая доска
        Expanded(
          flex: 3,
          child: _buildGameBoard(isDarkMode, surfaceColor, primaryColor, cellSize),
        ),
        // Доступные блоки
        Expanded(
          flex: 1,
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

    final Paint borderPaint = Paint()
      ..color = isValid ? Colors.green.withOpacity(0.8) : Colors.red.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final Paint fillPaint = Paint()
      ..color = isValid ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    // Проходимся по всем ячейкам блока
    for (int i = 0; i < block.shape.length; i++) {
      for (int j = 0; j < block.shape[i].length; j++) {
        if (block.shape[i][j] == 1) {
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