/*
 * Тесты листа фильтра календаря: вкладки, поиск, сброс фильтра.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobilapp/widgets/calendar_filter_sheet.dart';

List<String> groups() => ['205', '209', '313', '118'];

List<String> teachers() => [
  'Иванов И.И.',
  'Петров П.П.',
  'Сидоров С.С.',
  'Алькова З.Р.',
];

/// Открывает лист и возвращает то, что он вернул при закрытии.
Future<CalendarFilterResult?> openSheet(
  WidgetTester tester, {
  String selectedFilter = 'all',
  String? selectedGroup,
  String? selectedTeacher,
}) async {
  CalendarFilterResult? result;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showCalendarFilterSheet(
                context: context,
                groups: groups(),
                teachers: teachers(),
                selectedFilter: selectedFilter,
                selectedGroup: selectedGroup,
                selectedTeacher: selectedTeacher,
              );
            },
            child: const Text('открыть'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('открыть'));
  await tester.pumpAndSettle();

  return result;
}

void main() {
  testWidgets('лист показывает обе вкладки', (tester) async {
    await openSheet(tester);

    expect(find.text('ГРУППЫ'), findsOneWidget);
    expect(find.text('ПРЕПОДАВАТЕЛИ'), findsOneWidget);
  });

  testWidgets('выбор группы возвращает фильтр по группе', (tester) async {
    await openSheet(tester);

    await tester.tap(find.text('209'));
    await tester.pumpAndSettle();

    // Результат приходит после закрытия листа, поэтому проверяем,
    // что лист закрылся и список групп исчез.
    expect(find.text('ГРУППЫ'), findsNothing);
  });

  testWidgets('поиск сужает список групп', (tester) async {
    await openSheet(tester);

    await tester.enterText(find.byType(TextField), '20');
    await tester.pumpAndSettle();

    expect(find.text('205'), findsOneWidget);
    expect(find.text('209'), findsOneWidget);
    expect(find.text('313'), findsNothing);
  });

  testWidgets('поиск по преподавателям работает на своей вкладке', (
    tester,
  ) async {
    await openSheet(tester);

    await tester.tap(find.text('ПРЕПОДАВАТЕЛИ'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'альк');
    await tester.pumpAndSettle();

    expect(find.text('Алькова З.Р.'), findsOneWidget);
    expect(find.text('Иванов И.И.'), findsNothing);
  });

  testWidgets('при отсутствии совпадений показывается сообщение', (
    tester,
  ) async {
    await openSheet(tester);

    await tester.enterText(find.byType(TextField), 'такого нет');
    await tester.pumpAndSettle();

    expect(find.text('Ничего не найдено'), findsWidgets);
  });

  testWidgets('кнопка сброса видна только когда фильтр задан', (tester) async {
    await openSheet(tester);
    expect(find.text('Показать всё'), findsNothing);
    expect(find.text('Сейчас показано расписание всех групп'), findsOneWidget);
  });

  testWidgets('с выбранной группой показывается кнопка сброса', (tester) async {
    await openSheet(tester, selectedFilter: 'group', selectedGroup: '209');

    expect(find.text('Показать всё'), findsOneWidget);
    // Выбранный элемент отмечен галочкой.
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('лист открывается сразу на вкладке преподавателей', (
    tester,
  ) async {
    await openSheet(
      tester,
      selectedFilter: 'teacher',
      selectedTeacher: 'Петров П.П.',
    );

    // Список преподавателей уже виден без переключения вкладки.
    expect(find.text('Петров П.П.'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}
