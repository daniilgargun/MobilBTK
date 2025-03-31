import 'package:flutter/material.dart';
import 'dart:math';
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
  
  // Проверяем, можно ли разместить блок на доске
  bool _canPlaceBlock(Block block, int row, int col) {
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
        totalPoints = (totalPoints * 1.5).toInt(); // Дополнительный бонус за 3+ линии
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
  
  // Проверяем, можно ли разместить блок на доске и обновляем предпросмотр
  bool _updatePreview(Block block, Offset position) {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    
    final localPosition = box.globalToLocal(position);
    final boardWidth = box.size.width;
    final boardHeight = box.size.height;
    final double cellSize = min(boardWidth, boardHeight) / boardSize;
    
    // Определяем начало игрового поля с учетом паддинга
    final double boardStartX = 16.0; // Соответствует паддингу в _buildGameBoard
    final double boardStartY = 16.0;
    
    // Корректируем локальную позицию с учетом начала доски
    final adjustedX = localPosition.dx - boardStartX;
    final adjustedY = localPosition.dy - boardStartY;
    
    // Определяем центр блока относительно курсора
    final int blockCenterRow = block.shape.length ~/ 2;
    final int blockCenterCol = block.shape[0].length ~/ 2;
    
    // Вычисляем позицию с учетом центрирования блока
    final int col = (adjustedX / cellSize).floor() - blockCenterCol;
    final int row = (adjustedY / cellSize).floor() - blockCenterRow;
    
    // Проверяем возможность размещения
    bool canPlace = _canPlaceBlock(block, row, col);
    
    setState(() {
      previewRow = row;
      previewCol = col;
    });
    
    return canPlace;
  }
  
  // Сбрасываем превью
  void _resetPreview() {
    setState(() {
      previewRow = -1;
      previewCol = -1;
      isDragging = false;
      draggedBlock = null;
    });
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
    return Center(
      child: Column(
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
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Размещайте блоки разных цветов и форм,\nзаполняйте строки и столбцы для получения очков!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: textColor.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _startGame,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: isDarkMode ? Colors.white : Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'НАЧАТЬ ИГРУ',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (highScore > 0)
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
    );
  }
  
  // Экран игры
  Widget _buildGameScreen(bool isDarkMode, Color surfaceColor, Color primaryColor, double cellSize) {
    return Column(
      children: [
        // Игровая доска
        Expanded(
          flex: 3,
          child: Stack(
            children: [
              _buildGameBoard(isDarkMode, surfaceColor, primaryColor, cellSize),
              // Кнопка "Назад" в верхнем левом углу
              Positioned(
                top: 16,
                left: 16,
                child: Container(
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.grey[800] : Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: IconButton(
                    icon: Icon(
                      Icons.arrow_back,
                      color: primaryColor,
                    ),
                    onPressed: () {
                      setState(() {
                        gameState = GameState.notStarted;
                        _saveGameState();
                      });
                    },
                    tooltip: 'Вернуться в меню',
                  ),
                ),
              ),
            ],
          ),
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
  
  // Строим игровую доску
  Widget _buildGameBoard(bool isDarkMode, Color surfaceColor, Color primaryColor, double cellSize) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Container(
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
                ),
                itemCount: boardSize * boardSize,
                itemBuilder: (context, index) {
                  final int row = index ~/ boardSize;
                  final int col = index % boardSize;
                  return _buildCell(row, col, isDarkMode);
                },
              ),
              
              // Превью размещения блока - следует за движением
              if (isDragging && draggedBlock != null)
                Positioned.fill(
                  child: DragTarget<Block>(
                    onWillAcceptWithDetails: (details) {
                      final Block block = details.data;
                      return _updatePreview(block, details.offset);
                    },
                    onAcceptWithDetails: (details) {
                      final Block block = details.data;
                      
                      // Определяем ячейку доски
                      if (previewRow >= 0 && previewCol >= 0) {
                        _placeBlock(block, previewRow, previewCol);
                      }
                      
                      _resetPreview();
                    },
                    onLeave: (_) {
                      _resetPreview();
                    },
                    builder: (context, candidateData, rejectedData) {
                      return MouseRegion(
                        onHover: (event) {
                          _updatePreview(draggedBlock!, event.position);
                        },
                        child: AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, child) {
                            return CustomPaint(
                              painter: BlockPreviewPainter(
                                block: draggedBlock!,
                                row: previewRow,
                                col: previewCol,
                                boardSize: boardSize,
                                cellSize: cellSize,
                                color: primaryColor.withOpacity(_pulseAnimation.value),
                                isValid: _canPlaceBlock(draggedBlock!, previewRow, previewCol),
                              ),
                            );
                          }
                        ),
                      );
                    },
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
                      });
                    },
                    onDraggableCanceled: (_, __) {
                      _resetPreview();
                    },
                    onDragEnd: (_) {
                      _resetPreview();
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
    final double cellSize = 30.0; // Увеличиваем размер для лучшей видимости
    
    return Material(
      color: Colors.transparent,
      elevation: 10, // Добавляем тень
      shadowColor: Colors.black54,
      child: Container(
        width: cellSize * cols,
        height: cellSize * rows,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: GridView.builder(
          padding: EdgeInsets.zero,
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
            if (block.shape[r][c]) {
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: block.color.withOpacity(0.7),
                  border: Border.all(
                    color: primaryColor,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Container(
                    width: cellSize * 0.5,
                    height: cellSize * 0.5,
                    decoration: BoxDecoration(
                      color: block.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            } else {
              return SizedBox.shrink(); // Пустой виджет вместо Container()
            }
          },
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
  
  // Размещаем блок на доске
  void _placeBlock(Block block, int row, int col) {
    // Проверяем возможность размещения еще раз перед фактическим размещением
    if (!_canPlaceBlock(block, row, col)) {
      // Если не можем разместить, просто выходим
      return;
    }
    
    // Размещаем блок
    for (int i = 0; i < block.shape.length; i++) {
      for (int j = 0; j < block.shape[i].length; j++) {
        if (block.shape[i][j]) {
          if (row + i >= 0 && row + i < boardSize && col + j >= 0 && col + j < boardSize) {
            board[row + i][col + j].isFilled = true;
            board[row + i][col + j].color = block.color;
          }
        }
      }
    }
    
    // Запускаем анимацию размещения
    _animationController.reset();
    _animationController.forward();
    
    // Проверяем заполненные строки и столбцы
    _checkLines();
    
    // Удаляем использованный блок
    setState(() {
      if (selectedBlockIndex >= 0 && selectedBlockIndex < availableBlocks.length) {
        availableBlocks.removeAt(selectedBlockIndex);
        placedBlocksCount++;
      }
      selectedBlock = null;
      selectedBlockIndex = -1;
      
      // Генерируем новые блоки, если все размещены
      _generateBlocks();
    });
    
    // Проверяем, можно ли продолжить игру
    if (!_canContinueGame()) {
      _gameOver();
    }
    
    // Сохраняем состояние игры
    _saveGameState();
  }
  
  // Завершаем игру
  void _gameOver() {
    _saveHighScore();
    setState(() {
      gameState = GameState.gameOver;
    });
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