// Документация для мини-игры КолледжБлоки
// Эта игра реализует подобие популярной головоломки Блок Бласт (Block Blast)

/// # Мини-игра "КолледжБлоки"
/// 
/// ## Описание
/// "КолледжБлоки" - это пазл-игра, где игрок располагает блоки разных форм и цветов на сетке 8x8.
/// Каждый цвет представляет определенную специальность в колледже. Цель игры - заполнять 
/// горизонтальные и вертикальные линии, чтобы они исчезали и игрок получал очки.
/// 
/// ## Игровая механика
/// 1. **Игровое поле**: Сетка 8x8 клеток.
/// 2. **Блоки**: Игроку предлагается выбор из трех случайных блоков различных форм:
///    - 1x1 (одиночный квадрат)
///    - 2x1 (горизонтальный прямоугольник)
///    - 1x2 (вертикальный прямоугольник)
///    - 2x2 (квадрат из 4 клеток)
///    - L-образный блок
///    - Г-образный блок
/// 3. **Цвета блоков**: Каждый блок имеет цвет, соответствующий определенной профессии/специальности.
/// 4. **Размещение блоков**: Игрок перетаскивает блоки из нижней панели на игровое поле.
/// 5. **Очки**: Когда полностью заполняется горизонтальная или вертикальная линия, она исчезает, и игрок получает очки.
///    - За одну линию: 10 очков
///    - За две линии одновременно: 30 очков (бонус x1.5)
///    - За три и более линий: 45+ очков (дополнительный бонус x1.5)
/// 6. **Конец игры**: Игра заканчивается, когда нет возможности разместить ни один из доступных блоков.
/// 
/// ## Профессии и цвета
/// - **IT и программирование** - Синий
/// - **Пищевая промышленность** - Красный
/// - **Логистика** - Зеленый
/// - **Правоведение** - Янтарный
/// - **Маркетинг** - Оранжевый
/// - **Хлебобулочные изделия** - Коричневый
/// - **Мясное производство** - Темно-оранжевый
/// 
/// ## Сохранение результатов
/// Лучший результат игрока сохраняется с помощью SharedPreferences и отображается в верхней части экрана.
/// 
/// ## Разблокировка игры
/// Игра становится доступной только после нахождения всех трех пасхалок в приложении:
/// 1. Тройное нажатие на версию приложения
/// 2. Поиск по секретному слову "minigame"
/// 3. Двойное нажатие на воскресенье в календаре
/// 
/// ## Технические особенности реализации
/// - Игра использует систему перетаскивания Flutter (Draggable и DragTarget)
/// - Генерация случайных блоков с помощью Random()
/// - Проверка возможности размещения блоков с учетом их формы и границ поля
/// - Обнаружение заполненных линий с помощью циклов проверки
/// - Система начисления очков с бонусами за множественные линии
/// 
/// ## Планы на будущее
/// - Добавить анимации исчезновения линий
/// - Реализовать звуковые эффекты
/// - Добавить систему достижений
/// - Добавить блоки специальных форм и возможностей
/// - Реализовать локальную таблицу рекордов 