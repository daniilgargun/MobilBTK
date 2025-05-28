import 'package:flutter/material.dart';
import '../models/lesson_time_model.dart';

class BellScheduleDialog extends StatelessWidget {
  const BellScheduleDialog({super.key});

  Widget _buildTimeRow(String title, String time1, String time2) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Номер пары по центру
          SizedBox(
            width: 30,
            child: Center(
              child: Builder(
                builder: (context) => Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: Theme.of(context).brightness == Brightness.light 
                        ? Colors.black87 
                        : Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Времена в два ряда
          Expanded(
            child: Builder(
              builder: (context) => DefaultTextStyle(
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.2,
                  letterSpacing: -0.5,
                  color: Theme.of(context).brightness == Brightness.light 
                      ? Colors.black87 
                      : Colors.white,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      time1,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text(
                      time2,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
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
                  LessonTime.getDaysWithSameSchedule("normal"), 
                  LessonTime.getLessonTimesForUI("normal"),
                ),
                const SizedBox(height: 16),
                _buildDaySchedule(
                  context, 
                  LessonTime.getDaysWithSameSchedule("tuesday"), 
                  LessonTime.getLessonTimesForUI("tuesday"),
                  specialHour: LessonTime.getSpecialHourInfo("tuesday"),
                ),
                const SizedBox(height: 16),
                _buildDaySchedule(
                  context, 
                  LessonTime.getDaysWithSameSchedule("thursday"), 
                  LessonTime.getLessonTimesForUI("thursday"),
                  specialHour: LessonTime.getSpecialHourInfo("thursday"),
                ),
                const SizedBox(height: 16),
                _buildDaySchedule(
                  context, 
                  LessonTime.getDaysWithSameSchedule("saturday"), 
                  LessonTime.getLessonTimesForUI("saturday"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDaySchedule(BuildContext context, String title, List<(String, String, String)> times, {Map<String, String>? specialHour}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          decoration: BoxDecoration(
            color: (isDark 
                ? colorScheme.primaryContainer.withOpacity(0.2)
                : colorScheme.primaryContainer.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 5),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                fit: FlexFit.tight,
                child: Column(
                  children: times.take(3).map((time) => 
                    _buildTimeRow(time.$1, time.$2, time.$3)
                  ).toList(),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                fit: FlexFit.tight,
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
              color: (isDark 
                  ? colorScheme.primaryContainer.withOpacity(0.2)
                  : colorScheme.primaryContainer.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "${specialHour['name']}: ${specialHour['time']}",
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
} 