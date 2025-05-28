import 'package:flutter/material.dart';

// Класс для анимации очков
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
      duration: const Duration(milliseconds: 1000), // Увеличиваем длительность
    );

    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.0), weight: 70),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0), weight: 15),
    ]).animate(_controller);

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.5, end: 1.4), weight: 20),
      TweenSequenceItem(tween: Tween<double>(begin: 1.4, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.8), weight: 15),
    ]).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    ));

    _positionAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -60), // Увеличиваем высоту подъема
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuint, // Используем более плавную кривую
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
        try {
          // Гарантируем, что значение opacity в допустимом диапазоне [0.0, 1.0]
          final double safeOpacity = _opacityAnimation.value < 0.0 ? 0.0 : (_opacityAnimation.value > 1.0 ? 1.0 : _opacityAnimation.value);
          
          return Transform.translate(
            offset: _positionAnimation.value,
            child: Opacity(
              opacity: safeOpacity,
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 6,
                        spreadRadius: 1,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '+${widget.points}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18, // Увеличиваем размер шрифта
                      shadows: [
                        Shadow(
                          offset: Offset(1, 1),
                          blurRadius: 3,
                          color: Colors.black54,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        } catch (e) {
          // В случае ошибки, возвращаем пустой контейнер
          debugPrint('Ошибка при построении анимации: $e');
          return Container();
        }
      },
    );
  }
} 