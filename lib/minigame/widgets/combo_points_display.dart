import 'package:flutter/material.dart';
import 'dart:math' show pi, sin;

// Класс для отображения очков комбо
class ComboPointsDisplay extends StatefulWidget {
  final int comboCount;
  final int bonusPoints;
  final int linesCleared;
  final bool isDarkMode;
  final bool isSpecial;
  final bool isPartOfSeries;
  
  const ComboPointsDisplay({
    super.key,
    required this.comboCount,
    required this.bonusPoints,
    required this.linesCleared,
    this.isDarkMode = false,
    this.isSpecial = false,
    this.isPartOfSeries = false,
  });

  @override
  State<ComboPointsDisplay> createState() => _ComboPointsDisplayState();
}

class _ComboPointsDisplayState extends State<ComboPointsDisplay> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _slideAnimation;
  
  @override
  void initState() {
    super.initState();
    
    // Создаем контроллер анимации со сниженной длительностью
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    // Плавная анимация масштабирования
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.8, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.0), weight: 70),
    ]).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    
    // Анимация непрозрачности
    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.0), weight: 70),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.6), weight: 15),
    ]).animate(_animationController);
    
    // Анимация скольжения сверху
    _slideAnimation = Tween<double>(
      begin: -10.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    
    // Запускаем анимацию один раз
    _animationController.forward();
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  List<Color> _getGradientColors() {
    // Цвета для специальных комбо
    if (widget.isSpecial) {
      return widget.isDarkMode 
          ? [Colors.deepPurple.shade700, Colors.pink.shade900]
          : [Colors.deepPurple.shade500, Colors.pink.shade700];
    }
    
    // Цвета для серии
    if (widget.isPartOfSeries) {
      return widget.isDarkMode 
          ? [Colors.teal.shade700, Colors.blue.shade900]
          : [Colors.teal.shade500, Colors.blue.shade700];
    }
    
    // Стандартные цвета комбо
    if (widget.comboCount <= 1) {
      return widget.isDarkMode 
          ? [Colors.blueGrey.shade800, Colors.blueGrey.shade900]
          : [Colors.blueGrey.shade400, Colors.blueGrey.shade600];
    } else if (widget.comboCount < 3) {
      return widget.isDarkMode
          ? [Colors.blue.shade700, Colors.indigo.shade800]
          : [Colors.blue.shade500, Colors.indigo.shade600];
    } else if (widget.comboCount < 5) {
      return widget.isDarkMode 
          ? [Colors.purple.shade700, Colors.deepPurple.shade900]
          : [Colors.purple.shade500, Colors.deepPurple.shade700];
    } else if (widget.comboCount < 8) {
      return widget.isDarkMode
          ? [Colors.orange.shade700, Colors.deepOrange.shade900]
          : [Colors.orange.shade500, Colors.deepOrange.shade700];
    } else {
      return widget.isDarkMode
          ? [Colors.red.shade700, Colors.redAccent.shade700]
          : [Colors.red.shade500, Colors.redAccent.shade400];
    }
  }
  
  // Получить текст заголовка в зависимости от комбо
  String _getComboTitle() {
    if (widget.linesCleared >= 4) {
      return 'ТЕТРИС!';
    } else if (widget.linesCleared >= 3) {
      return 'ТРОЙНАЯ!';
    } else if (widget.comboCount >= 5) {
      return 'ОГНЕННОЕ КОМБО!';
    } else if (widget.comboCount >= 3) {
      return 'СУПЕР КОМБО!';
    } else if (widget.linesCleared >= 2) {
      return 'ДВОЙНАЯ!';
    } else if (widget.comboCount >= 2) {
      return 'КОМБО!';
    } else if (widget.isPartOfSeries) {
      return 'СЕРИЯ +1!'; // Уточняем, что это серия +1
    } else {
      return 'ЛИНИЯ!';
    }
  }

  // Получить иконку в зависимости от типа комбо
  IconData _getComboIcon() {
    if (widget.linesCleared >= 4) {
      return Icons.whatshot;
    } else if (widget.linesCleared >= 3 || widget.comboCount >= 5) {
      return Icons.bolt;
    } else if (widget.comboCount >= 3) {
      return Icons.flash_on;
    } else if (widget.linesCleared >= 2) {
      return Icons.star;
    } else if (widget.isPartOfSeries) {
      return Icons.add_task; // Значок продолжения серии
    } else {
      return Icons.add_circle;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        // Применяем минималистичные анимации
        return Transform.translate(
          offset: Offset(0, _slideAnimation.value),
          child: Opacity(
            opacity: _opacityAnimation.value * 0.85,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Material(
                type: MaterialType.transparency,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Основной контейнер комбо
                    Container(
                      constraints: BoxConstraints(
                        maxWidth: 120,
                        minWidth: 80,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _getGradientColors().map((color) => color.withOpacity(0.7)).toList(),
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 6,
                            spreadRadius: 0,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        border: widget.isSpecial ? Border.all(
                          color: Colors.white.withOpacity(0.4),
                          width: 1.5,
                        ) : null,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Заголовок комбо
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _getComboIcon(),
                                color: Colors.amber,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  _getComboTitle(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: widget.isSpecial ? 14 : 12,
                                    letterSpacing: 0.5,
                                    shadows: const [
                                      Shadow(
                                        color: Colors.black45,
                                        blurRadius: 2,
                                        offset: Offset(1, 1),
                                      ),
                                    ],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 4),
                          
                          // Отображение очков
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '+${widget.bonusPoints}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontSize: widget.isSpecial ? 18 : 16,
                                shadows: const [
                                  Shadow(
                                    color: Colors.black45,
                                    blurRadius: 2,
                                    offset: Offset(1, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          
                          // Отображение множителя комбо
                          if (widget.comboCount > 1 || widget.isPartOfSeries)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: widget.isPartOfSeries 
                                  ? Colors.teal.withOpacity(0.6) 
                                  : Colors.amber.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                widget.isPartOfSeries
                                  ? '+СЕРИЯ'
                                  : 'x${widget.comboCount}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    
                    // Минималистичный индикатор для особых комбо
                    if (widget.isSpecial)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.amber.withOpacity(0.6),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    );
  }
} 