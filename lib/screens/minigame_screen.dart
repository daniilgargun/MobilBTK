import 'package:flutter/material.dart';

class MinigameScreen extends StatefulWidget {
  const MinigameScreen({super.key});

  @override
  State<MinigameScreen> createState() => _MinigameScreenState();
}

class _MinigameScreenState extends State<MinigameScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мини-игра'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.videogame_asset,
              size: 100,
              color: Colors.amber,
            ),
            const SizedBox(height: 20),
            const Text(
              'Мини-игра будет доступна скоро!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Поздравляем! Вы разблокировали мини-игру, найдя все пасхалки.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Информация о пасхалках'),
                    content: const Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Найденные пасхалки:'),
                        SizedBox(height: 10),
                        Text('1. Тройное нажатие на версию приложения'),
                        Text('2. Поиск по секретному слову "minigame"'),
                        Text('3. Двойное нажатие на воскресенье в календаре'),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Закрыть'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('О пасхалках'),
            ),
          ],
        ),
      ),
    );
  }
} 