import 'package:flutter/material.dart';
import '../models/schedule_model.dart';
import '../models/lesson_time_model.dart';

// Карточка для одной пары в расписании
// Показывает всю инфу о паре - номер, время, группу, препода и кабинет

class ScheduleItemCard extends StatelessWidget {
  final ScheduleItem item;
  final DateTime date;
  final int index;

  static const Duration _animationDuration = Duration(milliseconds: 300);

  const ScheduleItemCard({
    super.key,
    required this.item,
    required this.date,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = _getAccentColor(context, item);
    final showSubgroup = item.subgroup != null && item.subgroup != "0";
    final dayType = LessonTime.getDayType(date.weekday);
    final times = LessonTime.getTimesForLesson(item.lessonNumber, dayType);
    
    return AnimatedOpacity(
      opacity: 1.0,
      duration: _animationDuration,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 6,
              child: Container(
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Заголовок с номером пары и временем
                  Row(
                    children: [
                      Text(
                        '${item.lessonNumber} пара',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(width: 8),
                      if (times.isNotEmpty)
                        Text(
                          '(${times[0].start} - ${times[1].end})',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  // Информация о группе и подгруппе
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item.group,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (showSubgroup) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Подгруппа ${item.subgroup}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  // Название предмета
                  Text(
                    item.subject,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // Преподаватель и аудитория
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.teacher,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        Icons.room_outlined,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.classroom,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Выбираем цвет полоски слева
  // Синий - практика
  // Красный - пары Соловья
  // Зеленый - все остальное
  Color _getAccentColor(BuildContext context, ScheduleItem item) {
    if (item.subject.toLowerCase().contains('пр')) {
      return const Color(0xFF2196F3); // Синий для практических
    } else if (item.teacher.toLowerCase().contains('соловей')) {
      return const Color(0xFFF44336); // Красный для Соловья
    }
    return const Color(0xFF4CAF50); // Зеленый по умолчанию
  }
} 