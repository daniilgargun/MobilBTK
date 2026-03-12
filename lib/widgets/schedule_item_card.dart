import 'package:flutter/material.dart';
import '../models/schedule_model.dart';
import '../models/lesson_time_model.dart';

// Карточка для одной пары в расписании
// Показывает всю инфу о паре - номер, время, группу, препода и кабинет

class ScheduleItemCard extends StatelessWidget {
  final ScheduleItem item;
  final DateTime date;
  final int index;
  final bool isCompact; // Для сетки

  static const Duration _animationDuration = Duration(milliseconds: 300);

  const ScheduleItemCard({
    super.key,
    required this.item,
    required this.date,
    required this.index,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = _getAccentColor(context, item);
    final showSubgroup = item.subgroup != null && item.subgroup != "0";
    final dayType = LessonTime.getDayType(date.weekday);
    final timeRange = LessonTime.getTimeRangeString(item.lessonNumber, dayType);
    final double leftPadding = isCompact ? 12.0 : 16.0;
    final double topPadding = isCompact ? 6.0 : 12.0;
    final double rightPadding = isCompact ? 8.0 : 12.0;
    final double bottomPadding = isCompact ? 6.0 : 12.0;

    // Создаем семантическое описание для accessibility
    final semanticLabel = '${item.lessonNumber} пара, ${item.subject}, '
        'преподаватель ${item.teacher}, кабинет ${item.classroom}, '
        'группа ${item.group}${showSubgroup ? ', подгруппа ${item.subgroup}' : ''}';

    return Semantics(
      label: semanticLabel,
      child: AnimatedOpacity(
        opacity: 1.0,
        duration: _animationDuration,
        child: Card(
          margin: isCompact
              ? const EdgeInsets.all(4)
              : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                padding: EdgeInsets.fromLTRB(
                  leftPadding,
                  topPadding,
                  rightPadding,
                  bottomPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Заголовок с номером пары и временем
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${item.lessonNumber} пара',
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (timeRange.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '($timeRange)',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.secondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: isCompact ? 4 : 8),

                    // Информация о группе и подгруппе
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.group,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (showSubgroup)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isCompact ? 'Пг ${item.subgroup}' : 'Подгруппа ${item.subgroup}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onTertiaryContainer,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: isCompact ? 4 : 8),

                    // Название предмета
                    Flexible(
                      child: Text(
                        item.subject,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(height: isCompact ? 4 : 8),

                    // Преподаватель и аудитория
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item.teacher,
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.room_outlined,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.classroom,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                            overflow: TextOverflow.ellipsis,
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
