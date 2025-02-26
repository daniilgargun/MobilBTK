import 'package:flutter/material.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

class CustomSnackBar {
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

  static void showError(BuildContext context, String message) {
    show(
      context: context,
      title: 'Ошибка',
      message: message,
      contentType: ContentType.failure,
    );
  }

  static void showSuccess(BuildContext context, String message) {
    show(
      context: context,
      title: 'Успешно',
      message: message,
      contentType: ContentType.success,
    );
  }

  static void showWarning(BuildContext context, String message) {
    show(
      context: context,
      title: 'Внимание',
      message: message,
      contentType: ContentType.warning,
    );
  }

  static void showOfflineMode(BuildContext context) {
    showWarning(
      context,
      'Нет подключения к интернету. Приложение работает в офлайн режиме. '
      'Показаны последние сохранённые данные.',
    );
  }
} 