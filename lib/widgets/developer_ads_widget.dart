import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ads_service.dart';

class DeveloperAdsWidget extends StatefulWidget {
  final VoidCallback? onCookieCountUpdated;
  
  const DeveloperAdsWidget({
    super.key, 
    this.onCookieCountUpdated,
  });

  @override
  State<DeveloperAdsWidget> createState() => _DeveloperAdsWidgetState();
}

class _DeveloperAdsWidgetState extends State<DeveloperAdsWidget> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  int _cookieCount = 0;
  bool _showThankYou = false;

  @override
  void initState() {
    super.initState();
    _loadCookieCount();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.elasticOut,
      ),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeIn,
      ),
    );

    // Автоматически запускаем рекламу при открытии диалога
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showRewardedAd();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadCookieCount() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _cookieCount = prefs.getInt('cookie_count') ?? 0;
      });
    }
  }

  Future<void> _saveCookieCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('cookie_count', _cookieCount);
  }

  void _showThankYouAnimation() {
    setState(() {
      _showThankYou = true;
    });
    _controller.forward().then((_) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.pop(context);
        }
      });
    });
  }

  Future<void> _showRewardedAd() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await AdsService().showRewardedAd();
      
      if (!mounted) return;

      if (result) {
        setState(() {
          _cookieCount++;
        });
        await _saveCookieCount();
        
        // Уведомляем родительский виджет об обновлении счетчика
        widget.onCookieCountUpdated?.call();
        
        _showThankYouAnimation();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Не удалось загрузить рекламу. Попробуйте позже.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Произошла ошибка: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showThankYou) {
      return Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 8,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          builder: (context, value, child) {
            return Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.primaryContainer,
                    Theme.of(context).colorScheme.secondaryContainer,
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.amber.withAlpha((0.2 * 255).toInt()),
                          shape: BoxShape.circle,
                        ),
                      ),
                      ScaleTransition(
                        scale: _scaleAnimation,
                        child: const Icon(
                          Icons.cookie,
                          size: 80,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FadeTransition(
                    opacity: _opacityAnimation,
                    child: ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context).colorScheme.tertiary,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds),
                      child: const Text(
                        'Спасибо за печеньку!',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FadeTransition(
                    opacity: _opacityAnimation,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface.withAlpha((0.7 * 255).toInt()),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha((0.1 * 255).toInt()),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        'Всего пожертвовано печенек: $_cookieCount',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Поддержите разработчика, посмотрев рекламу!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withAlpha((0.7 * 255).toInt()),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(
                      'Загрузка рекламы...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: _showRewardedAd,
                icon: const Icon(Icons.cookie),
                label: const Text('Посмотреть рекламу'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Всего пожертвовано печенек: $_cookieCount',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}