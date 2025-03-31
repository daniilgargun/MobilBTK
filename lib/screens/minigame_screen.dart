import 'package:flutter/material.dart';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

// Модель для игровой клетки
class Cell {
  bool isFilled = false;
  Color color = Colors.transparent;
}

// Модель для блока
class Block {
  List<List<bool>> shape; // Форма блока (матрица true/false)
  Color color;
  int size;
  
  Block({required this.shape, required this.color, required this.size});
}

// Перечисление профессий для блоков
enum ProfessionType {
  it(Colors.blue, 'IT и программирование'),
  cooking(Colors.red, 'Пищевая промышленность'),
  logistics(Colors.green, 'Логистика'),
  law(Colors.amber, 'Правоведение'),
  marketing(Colors.orange, 'Маркетинг'),
  baking(Colors.brown, 'Хлебобулочные изделия'),
  meat(Colors.deepOrange, 'Мясное производство');
  
  final Color color;
  final String label;
  
  const ProfessionType(this.color, this.label);
}

class MinigameScreen extends StatefulWidget {
  const MinigameScreen({super.key});

  @override
  State<MinigameScreen> createState() => _MinigameScreenState();
}

class _MinigameScreenState extends State<MinigameScreen> {
  // Константы игры
  static const int boardSize = 8; // Размер доски
  static const int maxBlockCount = 3; // Максимум блоков для выбора
  
  // Игровая доска
  late List<List<Cell>> board;
  
  // Доступные блоки для размещения
  late List<Block> availableBlocks;
  
  // Текущий выбранный блок
  Block? selectedBlock;
  int selectedBlockIndex = -1;
  
  // Счет игры
  int score = 0;
  int highScore = 0;
  
  // Генератор случайных чисел
  final Random random = Random();
  
  @override
  void initState() {
    super.initState();
    _initGame();
    _loadHighScore();
  }
  
  // Инициализируем игру
  void _initGame() {
    // Создаем пустую игровую доску
    board = List.generate(
      boardSize, 
      (_) => List.generate(
        boardSize, 
        (_) => Cell(),
      ),
    );
    
    // Генерируем начальные блоки
    _generateBlocks();
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
    availableBlocks = [];
    
    for (int i = 0; i < maxBlockCount; i++) {
      availableBlocks.add(_createRandomBlock());
    }
  }
  
  // Создаем случайный блок
  Block _createRandomBlock() {
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
  
  // Размещаем блок на доске
  void _placeBlock(Block block, int row, int col) {
    // Размещаем блок
    for (int i = 0; i < block.shape.length; i++) {
      for (int j = 0; j < block.shape[i].length; j++) {
        if (block.shape[i][j]) {
          board[row + i][col + j].isFilled = true;
          board[row + i][col + j].color = block.color;
        }
      }
    }
    
    // Проверяем заполненные строки и столбцы
    _checkLines();
    
    // Удаляем использованный блок и генерируем новый
    setState(() {
      availableBlocks.removeAt(selectedBlockIndex);
      availableBlocks.add(_createRandomBlock());
      selectedBlock = null;
      selectedBlockIndex = -1;
    });
    
    // Проверяем, можно ли продолжить игру
    if (!_canContinueGame()) {
      _gameOver();
    }
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
  
  // Завершаем игру
  void _gameOver() {
    _saveHighScore();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Игра окончена!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Ваш счет: $score'),
            Text('Лучший результат: $highScore'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _restartGame();
            },
            child: const Text('Играть снова'),
          ),
        ],
      ),
    );
  }
  
  // Перезапускаем игру
  void _restartGame() {
    setState(() {
      score = 0;
      _initGame();
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('КолледжБлоки'),
        actions: [
          // Отображаем текущий счет и лучший результат
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Center(
              child: Text(
                'Счет: $score | Рекорд: $highScore',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Игровая доска
          Expanded(
            flex: 3,
            child: _buildGameBoard(),
          ),
          // Доступные блоки
          Expanded(
            flex: 1,
            child: _buildBlockSelector(),
          ),
        ],
      ),
    );
  }
  
  // Строим игровую доску
  Widget _buildGameBoard() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: DragTarget<Block>(
        onWillAccept: (data) => true,
        onAcceptWithDetails: (details) {
          final Block block = details.data;
          // Определяем координаты на доске
          final RenderBox box = context.findRenderObject() as RenderBox;
          final localPosition = box.globalToLocal(details.offset);
          
          // Определяем ячейку доски
          final double cellSize = box.size.width / boardSize;
          final int row = (localPosition.dy / cellSize).floor();
          final int col = (localPosition.dx / cellSize).floor();
          
          // Проверяем и размещаем блок
          if (_canPlaceBlock(block, row, col)) {
            _placeBlock(block, row, col);
          }
        },
        builder: (context, candidateData, rejectedData) {
          return GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: boardSize,
            ),
            itemCount: boardSize * boardSize,
            itemBuilder: (context, index) {
              final int row = index ~/ boardSize;
              final int col = index % boardSize;
              return _buildCell(row, col);
            },
          );
        },
      ),
    );
  }
  
  // Строим ячейку доски
  Widget _buildCell(int row, int col) {
    final cell = board[row][col];
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        color: cell.isFilled ? cell.color : Colors.white,
      ),
    );
  }
  
  // Строим селектор блоков
  Widget _buildBlockSelector() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        border: const Border(
          top: BorderSide(color: Colors.grey),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (int i = 0; i < availableBlocks.length; i++)
            Draggable<Block>(
              data: availableBlocks[i],
              feedback: _buildBlockPreview(availableBlocks[i], isPreview: true),
              childWhenDragging: Container(
                width: 80,
                height: 80,
                color: Colors.grey[300],
              ),
              onDragStarted: () {
                setState(() {
                  selectedBlock = availableBlocks[i];
                  selectedBlockIndex = i;
                });
              },
              child: _buildBlockPreview(availableBlocks[i]),
            ),
        ],
      ),
    );
  }
  
  // Строим предпросмотр блока
  Widget _buildBlockPreview(Block block, {bool isPreview = false}) {
    final int rows = block.shape.length;
    final int cols = block.shape[0].length;
    final double cellSize = isPreview ? 24.0 : 20.0;
    
    return Container(
      width: 80,
      height: 80,
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8.0),
        boxShadow: isPreview
            ? [BoxShadow(color: Colors.black26, blurRadius: 4.0)]
            : null,
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
            ),
            itemCount: rows * cols,
            itemBuilder: (context, index) {
              final int r = index ~/ cols;
              final int c = index % cols;
              return Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  color: block.shape[r][c] ? block.color : Colors.transparent,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
} 