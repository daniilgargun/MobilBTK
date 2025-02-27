import 'package:flutter/material.dart';
import '../models/lesson_time_model.dart';

class BellScheduleDialog extends StatelessWidget {
  const BellScheduleDialog({super.key});

  Widget _buildTimeRow(String title, String time1, String time2) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Номер пары по центру
          SizedBox(
            width: 45,
            child: Center(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w500)
              ),
            ),
          ),
          // Времена в два ряда
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(time1),
                Text(time2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.95,
        constraints: const BoxConstraints(
          maxWidth: 400,
          maxHeight: 600,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.schedule, 
                      color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Расписание звонков',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildDaySchedule(
                  context, 
                  'Понедельник, среда, пятница', 
                  LessonTime.lessonTimes['normal']!,
                ),
                const SizedBox(height: 16),
                _buildDaySchedule(
                  context, 
                  'Вторник', 
                  LessonTime.lessonTimes['tuesday']!,
                  specialHour: 'Классный час: 14:10-14:55',
                ),
                const SizedBox(height: 16),
                _buildDaySchedule(
                  context, 
                  'Четверг', 
                  LessonTime.lessonTimes['thursday']!,
                  specialHour: 'Час информации: 14:10-14:35',
                ),
                const SizedBox(height: 16),
                _buildDaySchedule(
                  context, 
                  'Суббота', 
                  LessonTime.lessonTimes['saturday']!,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDaySchedule(BuildContext context, String title, List<LessonTime> times, {String? specialHour}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Левая колонка (1-3 пары)
            Expanded(
              child: Column(
                children: [
                  _buildTimeRow(
                    '1 пар',
                    '8:00-8:45',
                    '8:55-9:40',
                  ),
                  _buildTimeRow(
                    '2 пар',
                    '9:50-10:35',
                    '11:00-11:45',
                  ),
                  _buildTimeRow(
                    '3 пар',
                    '12:20-13:05',
                    '13:15-14:00',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Правая колонка (4-6 пары)
            Expanded(
              child: Column(
                children: [
                  _buildTimeRow(
                    '4 пар',
                    '14:10-14:55',
                    '15:05-15:50',
                  ),
                  _buildTimeRow(
                    '5 пар',
                    '16:00-16:45',
                    '16:55-17:40',
                  ),
                  _buildTimeRow(
                    '6 пар',
                    '17:50-18:35',
                    '18:40-19:25',
                  ),
                ],
              ),
            ),
          ],
        ),
        if (specialHour != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              specialHour,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
} 