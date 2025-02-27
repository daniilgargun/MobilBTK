import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/material.dart';
import '../widgets/error_snackbar.dart';
import '../providers/schedule_provider.dart';
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final _connectivity = Connectivity();
  late Box<String> _cache;
  bool _lastKnownStatus = true;
  static bool _hasShownOfflineWarning = false;  // Статическое поле для отслеживания уведомления

  Future<void> init() async {
    await Hive.initFlutter();
    _cache = await Hive.openBox<String>('schedule_cache');
    _lastKnownStatus = await isOnline();
    _connectivity.onConnectivityChanged.listen(_handleConnectivityChange);
  }

  void _handleConnectivityChange(ConnectivityResult result) async {
    final isOnlineNow = result != ConnectivityResult.none;
    
    if (isOnlineNow != _lastKnownStatus) {
      _lastKnownStatus = isOnlineNow;
      
      if (isOnlineNow) {
        _hasShownOfflineWarning = false;
        try {
          await ScheduleProvider().updateSchedule(silent: true);
        } catch (e) {
          debugPrint('Ошибка обновления: $e');
        }
      }
    }
  }

  Future<bool> isOnline() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _lastKnownStatus = result != ConnectivityResult.none;
      return _lastKnownStatus;
    } catch (e) {
      return false;
    }
  }

  bool get lastKnownStatus => _lastKnownStatus;

  void showOfflineWarning(BuildContext context) {
    if (!_lastKnownStatus && !_hasShownOfflineWarning) {
      _hasShownOfflineWarning = true;
      CustomSnackBar.showWarning(
        context,
        'Нет подключения к интернету. Работа в офлайн режиме.',
      );
    }
  }

  Future<void> cacheData(String key, String data) async {
    await _cache.put(key, data);
  }

  String? getCachedData(String key) {
    return _cache.get(key);
  }

  Future<void> clearCache() async {
    await _cache.clear();
  }

  Stream<ConnectivityResult> get onConnectivityChanged => 
      _connectivity.onConnectivityChanged;
} 