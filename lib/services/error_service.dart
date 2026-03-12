import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Типы ошибок в приложении
enum ErrorType {
  network, // Сетевые ошибки
  parsing, // Ошибки парсинга данных
  database, // Ошибки базы данных
  cache, // Ошибки кэширования
  validation, // Ошибки валидации
  unknown, // Неизвестные ошибки
}

/// Уровни критичности ошибок
enum ErrorSeverity {
  low, // Низкая - не влияет на основную функциональность
  medium, // Средняя - частично влияет на функциональность
  high, // Высокая - серьезно влияет на функциональность
  critical, // Критическая - приложение не может работать
}

/// Модель ошибки
class AppError {
  final String message;
  final String? details;
  final ErrorType type;
  final ErrorSeverity severity;
  final DateTime timestamp;
  final StackTrace? stackTrace;
  final String? context;

  AppError({
    required this.message,
    this.details,
    required this.type,
    required this.severity,
    DateTime? timestamp,
    this.stackTrace,
    this.context,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    return 'AppError(type: $type, severity: $severity, message: $message, context: $context)';
  }
}

/// Централизованный сервис для обработки ошибок
/// Обеспечивает единообразную обработку и отображение ошибок
class ErrorService {
  static final ErrorService _instance = ErrorService._internal();
  factory ErrorService() => _instance;
  ErrorService._internal();

  /// Обрабатывает ошибку и возвращает пользовательское сообщение
  AppError handleError(
    dynamic error, {
    String? context,
    ErrorType? type,
    ErrorSeverity? severity,
    StackTrace? stackTrace,
  }) {
    final errorType = type ?? _determineErrorType(error);
    final errorSeverity = severity ?? _determineErrorSeverity(error, errorType);
    final userMessage = _generateUserMessage(error, errorType);
    final details = _extractErrorDetails(error);

    final appError = AppError(
      message: userMessage,
      details: details,
      type: errorType,
      severity: errorSeverity,
      stackTrace: stackTrace,
      context: context,
    );

    // Логируем ошибку
    _logError(appError, error);

    return appError;
  }

  /// Определяет тип ошибки по исключению
  ErrorType _determineErrorType(dynamic error) {
    if (error is FormatException) {
      return ErrorType.parsing;
    } else if (error.toString().contains('SocketException') ||
        error.toString().contains('ClientException') ||
        error.toString().contains('TimeoutException')) {
      return ErrorType.network;
    } else if (error.toString().contains('DatabaseException') ||
        error.toString().contains('SQLite')) {
      return ErrorType.database;
    } else if (error.toString().contains('cache') ||
        error.toString().contains('Cache')) {
      return ErrorType.cache;
    } else {
      return ErrorType.unknown;
    }
  }

  /// Определяет уровень критичности ошибки
  ErrorSeverity _determineErrorSeverity(dynamic error, ErrorType type) {
    switch (type) {
      case ErrorType.network:
        return ErrorSeverity.medium;
      case ErrorType.parsing:
        return ErrorSeverity.medium;
      case ErrorType.database:
        return ErrorSeverity.high;
      case ErrorType.cache:
        return ErrorSeverity.low;
      case ErrorType.validation:
        return ErrorSeverity.low;
      case ErrorType.unknown:
        return ErrorSeverity.medium;
    }
  }

  /// Генерирует понятное пользователю сообщение об ошибке
  String _generateUserMessage(dynamic error, ErrorType type) {
    switch (type) {
      case ErrorType.network:
        return 'Проблема с подключением к интернету';
      case ErrorType.parsing:
        return 'Ошибка обработки данных расписания';
      case ErrorType.database:
        return 'Ошибка при работе с локальными данными';
      case ErrorType.cache:
        return 'Ошибка кэширования данных';
      case ErrorType.validation:
        return 'Некорректные данные';
      case ErrorType.unknown:
        return 'Произошла неожиданная ошибка';
    }
  }

  /// Извлекает детали ошибки для отладки
  String? _extractErrorDetails(dynamic error) {
    if (error == null) return null;

    final errorString = error.toString();
    if (errorString.length > 500) {
      return '${errorString.substring(0, 500)}...';
    }
    return errorString;
  }

  /// Логирует ошибку в консоль
  void _logError(AppError appError, dynamic originalError) {
    final severity = appError.severity.name.toUpperCase();
    final type = appError.type.name.toUpperCase();

    debugPrint('🚨 [$severity] [$type] ${appError.message}');

    if (appError.context != null) {
      debugPrint('📍 Контекст: ${appError.context}');
    }

    if (appError.details != null) {
      debugPrint('🔍 Детали: ${appError.details}');
    }

    if (appError.stackTrace != null &&
        appError.severity == ErrorSeverity.high) {
      debugPrint('📚 Stack trace:');
      final stackLines = appError.stackTrace.toString().split('\n');
      for (final line in stackLines.take(5)) {
        debugPrint('  $line');
      }
    }

    debugPrint('⏰ Время: ${appError.timestamp}');
    debugPrint('---');
  }

  /// Показывает ошибку пользователю через SnackBar
  void showErrorSnackBar(BuildContext context, AppError error) {
    if (!context.mounted) return;

    final color = _getErrorColor(error.severity);
    final icon = _getErrorIcon(error.type);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    error.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (error.details != null &&
                      error.severity != ErrorSeverity.low)
                    Text(
                      error.details!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: color,
        duration: _getSnackBarDuration(error.severity),
        action: error.severity == ErrorSeverity.high ||
                error.severity == ErrorSeverity.critical
            ? SnackBarAction(
                label: 'Подробнее',
                textColor: Colors.white,
                onPressed: () => _showErrorDialog(context, error),
              )
            : null,
      ),
    );
  }

  /// Показывает детальный диалог ошибки
  void _showErrorDialog(BuildContext context, AppError error) {
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(_getErrorIcon(error.type),
                color: _getErrorColor(error.severity)),
            const SizedBox(width: 8),
            const Text('Ошибка'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error.message,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (error.details != null) ...[
              const SizedBox(height: 8),
              const Text('Детали:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(error.details!),
            ],
            if (error.context != null) ...[
              const SizedBox(height: 8),
              const Text('Контекст:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(error.context!),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  /// Возвращает цвет для уровня критичности
  Color _getErrorColor(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.low:
        return Colors.blue;
      case ErrorSeverity.medium:
        return Colors.orange;
      case ErrorSeverity.high:
        return Colors.red;
      case ErrorSeverity.critical:
        return Colors.red.shade900;
    }
  }

  /// Возвращает иконку для типа ошибки
  IconData _getErrorIcon(ErrorType type) {
    switch (type) {
      case ErrorType.network:
        return Icons.wifi_off;
      case ErrorType.parsing:
        return Icons.data_usage;
      case ErrorType.database:
        return Icons.storage;
      case ErrorType.cache:
        return Icons.cached;
      case ErrorType.validation:
        return Icons.warning;
      case ErrorType.unknown:
        return Icons.error;
    }
  }

  /// Возвращает длительность показа SnackBar
  Duration _getSnackBarDuration(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.low:
        return const Duration(seconds: 2);
      case ErrorSeverity.medium:
        return const Duration(seconds: 4);
      case ErrorSeverity.high:
        return const Duration(seconds: 6);
      case ErrorSeverity.critical:
        return const Duration(seconds: 8);
    }
  }

  /// Создает ошибку сети
  AppError createNetworkError(String message,
      {String? details, String? context}) {
    return AppError(
      message: message,
      details: details,
      type: ErrorType.network,
      severity: ErrorSeverity.medium,
      context: context,
    );
  }

  /// Создает ошибку парсинга
  AppError createParsingError(String message,
      {String? details, String? context}) {
    return AppError(
      message: message,
      details: details,
      type: ErrorType.parsing,
      severity: ErrorSeverity.medium,
      context: context,
    );
  }

  /// Создает ошибку базы данных
  AppError createDatabaseError(String message,
      {String? details, String? context}) {
    return AppError(
      message: message,
      details: details,
      type: ErrorType.database,
      severity: ErrorSeverity.high,
      context: context,
    );
  }
}
