import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' show Random;
import '../models/background_particle.dart';
import '../painters/background_painter.dart';

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
  late Timer _timer;
  late List<BackgroundParticle> particles = [];
  final int particleCount = 40; // Количество частиц
  bool _initialized = false;
  
  @override
  void initState() {
    super.initState();
    
    // Запускаем таймер для анимации
    _timer = Timer.periodic(Duration(milliseconds: 50), _updateParticles);
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _generateParticles();
      _initialized = true;
    }
  }
  
  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
  
  void _generateParticles() {
    particles = [];
    
    final Size screenSize = MediaQuery.of(context).size;
    for (int i = 0; i < particleCount; i++) {
      particles.add(BackgroundParticle.createRandom(
        screenSize,
        widget.isDarkMode,
      ));
    }
  }
  
  void _updateParticles(Timer timer) {
    if (!mounted || particles.isEmpty) return;
    
    setState(() {
      final Size screenSize = MediaQuery.of(context).size;
      for (final particle in particles) {
        particle.update(screenSize);
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    if (particles.isEmpty) {
      return Container(); // Пустой контейнер, пока частицы не созданы
    }
    
    return RepaintBoundary(
      child: CustomPaint(
        painter: BackgroundPainter(
          particles: particles,
          isDarkMode: widget.isDarkMode,
        ),
        size: Size.infinite,
      ),
    );
  }
} 