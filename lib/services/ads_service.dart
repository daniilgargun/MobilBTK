/*
 * Copyright (c) 2024 Daniil Gargun. All rights reserved.
 * Author: Daniil Gargun | Telegram: @Daniilgargun | Email: daniilgorgun38@gmail.com
 */

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:yandex_mobileads/mobile_ads.dart';

import 'remote_config_service.dart';

/// Реклама с вознаграждением («поддержать разработчика»).
///
/// Переписан под Yandex Mobile Ads 8.x:
/// `MobileAds` → `YandexAds`, `RewardedAdLoader.create()` → обычный
/// конструктор, `loadAd()` теперь возвращает готовый `RewardedAd`
/// вместо доставки результата через колбэки.
class AdsService {
  static final AdsService _instance = AdsService._internal();
  factory AdsService() => _instance;
  AdsService._internal();

  // ID рекламного блока
  static const String _rewardedAdUnitId = 'R-M-14828109-1';

  static const Duration _loadTimeout = Duration(seconds: 20);

  bool _isInitialized = false;

  /// Сколько раз подряд не удалось загрузить объявление.
  int _consecutiveFailures = 0;

  /// Сколько раз пробуем повторить загрузку, прежде чем сдаться до
  /// следующего запуска приложения.
  static const int _maxRetries = 4;

  Timer? _retryTimer;

  final ValueNotifier<bool> _available = ValueNotifier<bool>(true);

  /// Есть ли смысл показывать блок «поддержать разработчика».
  ///
  /// Становится false, если реклама выключена удалённым конфигом, если SDK
  /// не инициализировался или если объявления перестали загружаться. Раньше
  /// блок был виден всегда, и при недоступной рекламе пользователь нажимал
  /// кнопку, ждал и получал «Не удалось загрузить рекламу» — выглядело как
  /// поломка приложения.
  ValueListenable<bool> get availability => _available;

  final RewardedAdLoader _rewardedAdLoader = RewardedAdLoader();

  RewardedAd? _rewardedAd;

  /// Показ уже идёт — повторный показ и параллельная загрузка запрещены.
  bool _isAdShowing = false;

  /// Загрузка уже идёт. Раньше несколько параллельных вызовов
  /// `_loadRewardedAd()` могли создать несколько объявлений и потерять
  /// ссылку на предыдущее, не уничтожив его.
  Future<void>? _pendingLoad;

  /// Инициализация SDK.
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Выключатель на случай, если рекламная сеть перестанет работать или
    // изменит условия: убрать блок можно из консоли, без обновления.
    if (!RemoteConfigService().config.adsEnabled) {
      _available.value = false;
      debugPrint('⏸️ Реклама отключена удалённым конфигом');
      return;
    }

    try {
      await YandexAds.initialize();
      _isInitialized = true;
      _consecutiveFailures = 0;
      debugPrint('✅ Яндекс.Ads успешно инициализирован');

      // Предзагружаем первое объявление, но не ждём его.
      unawaited(_loadRewardedAd());
    } catch (e) {
      debugPrint('❌ Ошибка при инициализации Яндекс.Ads: $e');
      _isInitialized = false;
      _available.value = false;
    }
  }

  /// Регистрирует исход загрузки.
  ///
  /// Блок поддержки прячется сразу при первой неудаче, а не после серии:
  /// за один сеанс приложение обычно делает ровно одну попытку загрузки,
  /// так что «после трёх неудач подряд» не наступало бы никогда. Чтобы
  /// разовый сбой сети не прятал блок до перезапуска, загрузка повторяется
  /// с нарастающей паузой, и при успехе блок возвращается.
  void _registerLoadResult({required bool success}) {
    if (success) {
      _consecutiveFailures = 0;
      _retryTimer?.cancel();
      _available.value = true;
      return;
    }

    _consecutiveFailures++;
    _available.value = false;

    if (_consecutiveFailures > _maxRetries) return;

    _retryTimer?.cancel();
    _retryTimer = Timer(
      Duration(seconds: 30 * _consecutiveFailures),
      () => unawaited(_loadRewardedAd()),
    );
  }

  /// Безопасно уничтожает текущее объявление.
  Future<void> _safeDestroyAd() async {
    final adToDestroy = _rewardedAd;
    _rewardedAd = null;
    if (adToDestroy == null) return;

    try {
      await adToDestroy.destroy();
    } catch (e) {
      debugPrint('⚠️ Ошибка при уничтожении рекламы: $e');
    }
  }

  /// Загружает объявление. Повторные вызовы во время загрузки
  /// присоединяются к уже идущей.
  Future<void> _loadRewardedAd() {
    final pending = _pendingLoad;
    if (pending != null) return pending;

    final future = _doLoadRewardedAd().whenComplete(() {
      _pendingLoad = null;
    });
    _pendingLoad = future;
    return future;
  }

  Future<void> _doLoadRewardedAd() async {
    if (!_isInitialized || _isAdShowing || _rewardedAd != null) return;

    try {
      final ad = await _rewardedAdLoader
          .loadAd(adRequest: const AdRequest(adUnitId: _rewardedAdUnitId))
          .timeout(_loadTimeout);

      // Пока грузились, показ мог начаться — тогда объявление не нужно.
      if (_isAdShowing) {
        await ad.destroy();
        return;
      }

      _rewardedAd = ad;
      _registerLoadResult(success: true);
      debugPrint('✅ Реклама с вознаграждением загружена');
    } on AdRequestError catch (e) {
      debugPrint('⚠️ Ошибка загрузки рекламы: ${e.description}');
      _rewardedAd = null;
      _registerLoadResult(success: false);
    } on TimeoutException {
      debugPrint('⚠️ Таймаут загрузки рекламы');
      _rewardedAd = null;
      _registerLoadResult(success: false);
    } catch (e) {
      debugPrint('⚠️ Не удалось загрузить рекламу: $e');
      _rewardedAd = null;
      _registerLoadResult(success: false);
    }
  }

  /// Показывает объявление и возвращает true, если пользователь досмотрел его
  /// до конца и получил вознаграждение.
  Future<bool> showRewardedAd() async {
    if (_isAdShowing) {
      debugPrint('⏭️ Реклама уже показывается');
      return false;
    }

    if (!_isInitialized) {
      await initialize();
      if (!_isInitialized) return false;
    }

    if (_rewardedAd == null) {
      await _loadRewardedAd();
      if (_rewardedAd == null) {
        debugPrint('⚠️ Не удалось загрузить рекламу для показа');
        return false;
      }
    }

    final adToShow = _rewardedAd;
    if (adToShow == null) return false;

    _isAdShowing = true;
    var rewarded = false;

    try {
      await adToShow.setAdEventListener(
        eventListener: RewardedAdEventListener(
          onAdShown: () => debugPrint('▶️ Реклама показана'),
          onAdFailedToShow: (error) =>
              debugPrint('⚠️ Ошибка показа рекламы: ${error.description}'),
          onAdDismissed: () => debugPrint('⏹️ Реклама закрыта'),
          onAdClicked: () => debugPrint('👆 Клик по рекламе'),
          onAdImpression: (_) => debugPrint('👁️ Показ засчитан'),
          onRewarded: (reward) {
            debugPrint('🎁 Награда: ${reward.amount} ${reward.type}');
            rewarded = true;
          },
        ),
      );

      await adToShow.show();

      final rewardResult = await adToShow.waitForDismiss();
      if (rewardResult != null) {
        rewarded = true;
      }

      return rewarded;
    } catch (e) {
      debugPrint('❌ Ошибка при показе рекламы: $e');
      return false;
    } finally {
      _isAdShowing = false;
      // Объявление одноразовое: уничтожаем и готовим следующее.
      await _safeDestroyAd();
      unawaited(_loadRewardedAd());
    }
  }

  /// Готово ли объявление к показу.
  Future<bool> isAdAvailable() async {
    if (_isAdShowing) return false;

    if (!_isInitialized) {
      await initialize();
      if (!_isInitialized) return false;
    }

    if (_rewardedAd == null) {
      await _loadRewardedAd();
    }

    return _rewardedAd != null && !_isAdShowing;
  }
}
