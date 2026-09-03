/*
 * Виджет-тесты карточки пары: проверяем, что карточка не «разъезжается»
 * на длинных названиях и что подгруппа "0" (нет подгруппы) не показывается.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobilapp/models/schedule_model.dart';
import 'package:mobilapp/widgets/schedule_item_card.dart';

Widget wrap(Widget child, {Size size = const Size(400, 800)}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: size.width,
        height: size.height,
        child: SingleChildScrollView(child: child),
      ),
    ),
  );
}

ScheduleItem item({
  String subject = 'Математика',
  String teacher = 'Иванов И.И.',
  String classroom = '202',
  String? subgroup,
  int number = 1,
}) {
  return ScheduleItem(
    group: '205',
    lessonNumber: number,
    subject: subject,
    teacher: teacher,
    classroom: classroom,
    subgroup: subgroup,
  );
}

void main() {
  // Понедельник — обычный тип дня.
  final monday = DateTime(2026, 9, 7);

  testWidgets('показывает предмет, преподавателя, кабинет и группу', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(ScheduleItemCard(item: item(), date: monday, index: 0)),
    );

    expect(find.text('Математика'), findsOneWidget);
    expect(find.text('Иванов И.И.'), findsOneWidget);
    expect(find.text('202'), findsOneWidget);
    expect(find.text('205'), findsOneWidget);
    expect(find.text('1 пара'), findsOneWidget);
  });

  testWidgets('подгруппа "0" означает её отсутствие и не отображается', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ScheduleItemCard(
          item: item(subgroup: '0'),
          date: monday,
          index: 0,
        ),
      ),
    );

    expect(find.textContaining('Подгруппа'), findsNothing);
    expect(find.textContaining('Пг'), findsNothing);
  });

  testWidgets('реальная подгруппа отображается', (tester) async {
    await tester.pumpWidget(
      wrap(
        ScheduleItemCard(
          item: item(subgroup: '2'),
          date: monday,
          index: 0,
        ),
      ),
    );

    expect(find.text('Подгруппа 2'), findsOneWidget);
  });

  testWidgets('в компактном режиме подгруппа сокращается', (tester) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 190,
          height: 200,
          child: ScheduleItemCard(
            item: item(subgroup: '2'),
            date: monday,
            index: 0,
            isCompact: true,
          ),
        ),
      ),
    );

    expect(find.text('Пг 2'), findsOneWidget);
  });

  testWidgets('длинные названия не вызывают переполнения вёрстки', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ScheduleItemCard(
          item: item(
            subject: 'Основы алгоритмизации и программирования на языках высокого уровня',
            teacher: 'Александропулос-Константинопольский А.А.',
            classroom: 'корпус 2, аудитория 415-а',
          ),
          date: monday,
          index: 0,
        ),
      ),
    );

    // tester.takeException() вернёт FlutterError, если что-то вылезло
    // за пределы (RenderFlex overflow).
    expect(tester.takeException(), isNull);
  });

  testWidgets('на узком экране карточка тоже не переполняется', (tester) async {
    await tester.pumpWidget(
      wrap(
        ScheduleItemCard(
          item: item(
            subject:
                'Информационные технологии в профессиональной деятельности',
            teacher: 'Петрова-Водкина М.М.',
          ),
          date: monday,
          index: 0,
        ),
        size: const Size(320, 600),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('компактная карточка помещается в ячейку сетки', (tester) async {
    // Соотношение сторон сетки 1.5 при двух колонках на экране 1080px даёт
    // ячейку примерно 265x177 логических пикселей.
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 265,
          height: 177,
          child: ScheduleItemCard(
            item: item(
              subject: 'Основы алгоритмизации и программирования',
              teacher: 'Александропулос А.А.',
              subgroup: '2',
            ),
            date: monday,
            index: 0,
            isCompact: true,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('карточка доступна для скринридера', (tester) async {
    await tester.pumpWidget(
      wrap(ScheduleItemCard(item: item(), date: monday, index: 0)),
    );

    expect(
      find.bySemanticsLabel(
        '1 пара, Математика, преподаватель Иванов И.И., '
        'кабинет 202, группа 205',
      ),
      findsOneWidget,
    );
  });
}
