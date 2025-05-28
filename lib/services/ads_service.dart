import 'package:flutter/material.dart';
import 'package:yandex_mobileads/mobile_ads.dart';

class AdsService {
  static final AdsService _instance = AdsService._internal();
  factory AdsService() => _instance;
  AdsService._internal();

  bool _isInitialized = false;
  
  // ID рекламных блоков
  static const String _rewardedAdUnitId = 'R-M-14828109-1';

  // Экземпляр загрузчика рекламы
  RewardedAdLoader? _rewardedAdLoader;
  
  // Загруженная реклама с вознаграждением
  RewardedAd? _rewardedAd;
  
  // Флаг, указывающий, что реклама в процессе показа
  bool _isAdShowing = false;

  // Инициализация SDK
  Future<void> initialize() async {
    // Если уже инициализировано, не делаем повторную инициализацию
    if (_isInitialized) return;
    
    try {
      // Инициализируем SDK с обработкой возможных ошибок
      await MobileAds.initialize();
      _isInitialized = true;
      debugPrint('Яндекс.Ads успешно инициализирован');
      
      // Создаем загрузчик рекламы
      await _createRewardedAdLoader();
    } catch (e) {
      // Логируем ошибку, но не позволяем приложению упасть
      debugPrint('Ошибка при инициализации Яндекс.Ads: $e');
      _isInitialized = false; // Помечаем, что инициализация не удалась
    }
  }

  // Безопасное уничтожение рекламы
  Future<void> _safeDestroyAd() async {
    try {
      final adToDestroy = _rewardedAd;
      if (adToDestroy != null) {
        _rewardedAd = null; // Сначала обнуляем ссылку
        await Future.delayed(const Duration(milliseconds: 100)); // Небольшая задержка
        adToDestroy.destroy(); // Затем уничтожаем
      }
    } catch (e) {
      debugPrint('Ошибка при уничтожении рекламы: $e');
    }
  }

  // Создание загрузчика рекламы с вознаграждением
  Future<void> _createRewardedAdLoader() async {
    try {
      _rewardedAdLoader = await RewardedAdLoader.create(
        onAdLoaded: (RewardedAd rewardedAd) {
          debugPrint('Реклама с вознаграждением загружена');
          // Если уже есть загруженная реклама, уничтожаем старую
          if (_rewardedAd != null && _rewardedAd != rewardedAd) {
            _safeDestroyAd();
          }
          _rewardedAd = rewardedAd;
        },
        onAdFailedToLoad: (error) {
          debugPrint('Ошибка загрузки рекламы с вознаграждением: ${error.description}');
          _rewardedAd = null;
        },
      );
      
      // После успешного создания загрузчика сразу загружаем рекламу
      await _loadRewardedAd();
    } catch (e) {
      debugPrint('Ошибка при создании загрузчика рекламы: $e');
    }
  }

  // Загрузка рекламы с вознаграждением
  Future<void> _loadRewardedAd() async {
    if (!_isInitialized) {
      debugPrint('SDK не инициализирован, пропускаем загрузку рекламы');
      return;
    }
    
    // Если реклама уже показывается, не пытаемся загрузить новую
    if (_isAdShowing) {
      debugPrint('Реклама в процессе показа, пропускаем загрузку новой');
      return;
    }
    
    if (_rewardedAdLoader == null) {
      debugPrint('Загрузчик рекламы не создан, создаем новый');
      await _createRewardedAdLoader();
      if (_rewardedAdLoader == null) {
        debugPrint('Не удалось создать загрузчик рекламы');
        return;
      }
    }
    
    try {
      await _rewardedAdLoader?.loadAd(
        adRequestConfiguration: AdRequestConfiguration(
          adUnitId: _rewardedAdUnitId,
        ),
      );
    } catch (e) {
      debugPrint('Ошибка при загрузке рекламы с вознаграждением: $e');
    }
  }

  // Показ рекламы с вознаграждением
  Future<bool> showRewardedAd() async {
    // Если уже показываем рекламу, не запускаем новый показ
    if (_isAdShowing) {
      debugPrint('Реклама уже показывается, пропускаем повторный показ');
      return false;
    }
    
    // Если SDK не инициализирован, пытаемся инициализировать
    if (!_isInitialized) {
      debugPrint('SDK не инициализирован, пытаемся инициализировать');
      await initialize();
      
      // Если инициализация не удалась, выходим
      if (!_isInitialized) {
        debugPrint('Не удалось инициализировать SDK, показ рекламы невозможен');
        return false;
      }
    }
    
    // Если реклама не загружена, пытаемся загрузить
    if (_rewardedAd == null) {
      debugPrint('Реклама не загружена, пытаемся загрузить');
      await _loadRewardedAd();
      
      // Даем немного времени на загрузку рекламы
      await Future.delayed(const Duration(seconds: 1));
      
      // Если реклама все еще не загружена, выходим
      if (_rewardedAd == null) {
        debugPrint('Не удалось загрузить рекламу');
        return false;
      }
    }
    
    bool rewarded = false;
    _isAdShowing = true; // Устанавливаем флаг, что реклама показывается
    
    try {
      RewardedAd? adToShow = _rewardedAd;
      
      if (adToShow == null) {
        _isAdShowing = false;
        return false;
      }
      
      // Устанавливаем слушатель событий рекламы
      adToShow.setAdEventListener(
        eventListener: RewardedAdEventListener(
          onAdShown: () {
            debugPrint('Реклама показана');
          },
          onAdFailedToShow: (error) {
            debugPrint('Ошибка показа рекламы: ${error.description}');
            _isAdShowing = false;
            
            // Безопасное уничтожение рекламы с отложенным запуском загрузки новой
            Future.microtask(() async {
              await _safeDestroyAd();
              await Future.delayed(const Duration(milliseconds: 300));
              await _loadRewardedAd();
            });
          },
          onAdDismissed: () {
            debugPrint('Реклама закрыта');
            _isAdShowing = false;
            
            // Безопасное уничтожение рекламы с отложенным запуском загрузки новой
            Future.microtask(() async {
              await _safeDestroyAd();
              await Future.delayed(const Duration(milliseconds: 300));
              await _loadRewardedAd();
            });
          },
          onAdClicked: () {
            debugPrint('Клик по рекламе');
          },
          onAdImpression: (data) {
            debugPrint('Показ рекламы');
          },
          onRewarded: (reward) {
            debugPrint('Награда получена: ${reward.amount} ${reward.type}');
            rewarded = true;
          },
        ),
      );
      
      // Показываем рекламу
      await adToShow.show();
      
      try {
        // Ждем завершения просмотра
        final rewardResult = await adToShow.waitForDismiss();
        
        // Если получили награду
        if (rewardResult != null) {
          debugPrint('Получено ${rewardResult.amount} ${rewardResult.type}');
          rewarded = true;
        }
      } catch (e) {
        debugPrint('Ошибка ожидания завершения рекламы: $e');
      }
      
      return rewarded;
    } catch (e) {
      debugPrint('Ошибка при показе рекламы: $e');
      // В случае ошибки очищаем ресурсы
      _isAdShowing = false;
      await _safeDestroyAd();
      return false;
    } finally {
      // Гарантируем, что флаг будет сброшен
      _isAdShowing = false;
      // И запустим загрузку новой рекламы через некоторое время
      Future.delayed(const Duration(milliseconds: 500), _loadRewardedAd);
    }
  }

  // Проверка доступности рекламы
  Future<bool> isAdAvailable() async {
    // Если реклама показывается, возвращаем false
    if (_isAdShowing) {
      return false;
    }
    
    if (!_isInitialized) {
      try {
        await initialize();
      } catch (e) {
        debugPrint('Ошибка при инициализации SDK: $e');
        return false;
      }
      
      if (!_isInitialized) {
        return false;
      }
    }
    
    if (_rewardedAd == null) {
      try {
        await _loadRewardedAd();
        // Даем время на загрузку рекламы
        await Future.delayed(const Duration(seconds: 1));
      } catch (e) {
        debugPrint('Ошибка при загрузке рекламы: $e');
      }
    }
    
    return _rewardedAd != null && !_isAdShowing;
  }
} 