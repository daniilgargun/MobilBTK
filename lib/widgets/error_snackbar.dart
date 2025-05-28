import 'package:flutter/material.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

class CustomSnackBar {
  // Всплывающие уведомления разных типов
  // Использую библиотеку awesome_snackbar_content для красивого дизайна

  // Показывает уведомление с заголовком и текстом
  static void show({
    required BuildContext context,
    required String title,
    required String message,
    ContentType contentType = ContentType.failure,
  }) {
    final snackBar = SnackBar(
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      content: AwesomeSnackbarContent(
        title: title,
        message: message,
        contentType: contentType,
      ),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }

  // Красное уведомление для ошибок
  static void showError(BuildContext context, String message) {
    show(
      context: context,
      title: 'Ошибка',
      message: message,
      contentType: ContentType.failure,
    );
  }

  // Зеленое уведомление для успешных действий
  static void showSuccess(BuildContext context, String message) {
    show(
      context: context,
      title: 'Успешно',
      message: message,
      contentType: ContentType.success,
    );
  }

  // Желтое уведомление для предупреждений
  static void showWarning(BuildContext context, String message) {
    show(
      context: context,
      title: 'Внимание',
      message: message,
      contentType: ContentType.warning,
    );
  }

  // Показывает предупреждение что нет интернета
  static void showOfflineMode(BuildContext context) {
    showWarning(
      context,
      'Нет подключения к интернету. Приложение работает в офлайн режиме. '
      'Показаны последние сохранённые данные.',
    );
  }
} 