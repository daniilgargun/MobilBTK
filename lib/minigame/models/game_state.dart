// Состояния игры
enum GameState {
  notStarted,   // Игра еще не началась
  playing,      // Игра запущена
  paused,       // Игра приостановлена
  gameOver,     // Игра окончена
  waitForResurrection, // Ожидание выбора воскрешения
  loadingAd,    // Загрузка рекламы
} 