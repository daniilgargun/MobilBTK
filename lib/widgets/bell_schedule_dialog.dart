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
          // Времена в два ряда с монопространственным шрифтом
          Expanded(
            child: DefaultTextStyle(
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                height: 1.2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(time1),
                  Text(time2),
                ],
              ),
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
                  [
                    ('1)', '8:00-8:45', '8:55-9:40'),
                    ('2)', '9:50-10:35', '11:00-11:45'),
                    ('3)', '12:20-13:05', '13:15-14:00'),
                    ('4)', '14:10-14:55', '15:05-15:50'),
                    ('5)', '16:00-16:45', '16:55-17:40'),
                    ('6)', '17:50-18:35', '18:40-19:25'),
                  ],
                ),
                const SizedBox(height: 16),
                _buildDaySchedule(
                  context, 
                  'Вторник', 
                  [
                    ('1)', '8:00-8:45', '8:55-9:40'),
                    ('2)', '9:50-10:35', '11:00-11:45'),
                    ('3)', '12:20-13:05', '13:15-14:00'),
                    ('4)', '15:05-15:50', '16:00-16:45'),
                    ('5)', '16:55-17:40', '17:50-18:35'),
                    ('6)', '18:45-19:30', '19:35-20:20'),
                  ],
                  specialHour: 'Классный час: 14:10-14:55',
                ),
                const SizedBox(height: 16),
                _buildDaySchedule(
                  context, 
                  'Четверг', 
                  [
                    ('1)', '8:00-8:45', '8:55-9:40'),
                    ('2)', '9:50-10:35', '11:00-11:45'),
                    ('3)', '12:20-13:05', '13:15-14:00'),
                    ('4)', '14:45-15:30', '15:40-16:25'),
                    ('5)', '16:35-17:20', '17:30-18:15'),
                    ('6)', '18:25-19:10', '19:15-20:00'),
                  ],
                  specialHour: 'Часы информации: 14:10-14:35',
                ),
                const SizedBox(height: 16),
                _buildDaySchedule(
                  context, 
                  'Суббота', 
                  [
                    ('1)', '8:00-8:45', '8:55-9:40'),
                    ('2)', '9:50-10:35', '10:45-11:30'),
                    ('3)', '11:50-12:35', '12:40-13:25'),
                    ('4)', '13:35-14:20', '14:25-15:10'),
                    ('5)', '15:20-16:05', '16:10-16:55'),
                    ('6)', '17:05-17:50', '17:55-18:40'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDaySchedule(BuildContext context, String title, List<(String, String, String)> times, {String? specialHour}) {
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
        IntrinsicHeight( // Добавляем для выравнивания высоты колонок
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Левая колонка (1-3 пары)
              Expanded(
                child: Column(
                  children: times.take(3).map((time) => 
                    _buildTimeRow(time.$1, time.$2, time.$3)
                  ).toList(),
                ),
              ),
              const SizedBox(width: 16), // Увеличиваем расстояние между колонками
              // Правая колонка (4-6 пары)
              Expanded(
                child: Column(
                  children: times.skip(3).take(3).map((time) => 
                    _buildTimeRow(time.$1, time.$2, time.$3)
                  ).toList(),
                ),
              ),
            ],
          ),
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