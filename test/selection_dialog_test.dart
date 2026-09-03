/*
 * Тесты диалога выбора группы/преподавателя: поиск по длинному списку.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobilapp/widgets/selection_dialog.dart';

List<String> teachers(int count) =>
    List.generate(count, (i) => 'Преподаватель ${i + 1}');

Future<void> pumpDialog(
  WidgetTester tester, {
  required List<String> items,
  String? selected,
  ValueChanged<String>? onSelect,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SelectionDialog(
          title: 'Выберите преподавателя',
          items: items,
          selectedItem: selected,
          icon: Icons.person,
          onSelect: onSelect ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('на длинном списке появляется поле поиска', (tester) async {
    await pumpDialog(tester, items: teachers(30));
    expect(find.widgetWithText(TextField, 'Поиск'), findsOneWidget);
  });

  testWidgets('на коротком списке поле поиска не мешается', (tester) async {
    await pumpDialog(tester, items: ['205', '313', '118']);
    expect(find.widgetWithText(TextField, 'Поиск'), findsNothing);
  });

  testWidgets('поиск отбирает подходящие элементы', (tester) async {
    await pumpDialog(
      tester,
      items: ['Иванов И.И.', 'Петров П.П.', 'Сидоров С.С.', ...teachers(10)],
    );

    await tester.enterText(find.byType(TextField), 'петров');
    await tester.pump();

    expect(find.text('Петров П.П.'), findsOneWidget);
    expect(find.text('Иванов И.И.'), findsNothing);
  });

  testWidgets('поиск не зависит от регистра', (tester) async {
    await pumpDialog(tester, items: ['Иванов И.И.', ...teachers(10)]);

    await tester.enterText(find.byType(TextField), 'ИВАНОВ');
    await tester.pump();

    expect(find.text('Иванов И.И.'), findsOneWidget);
  });

  testWidgets('при отсутствии совпадений показывается сообщение', (
    tester,
  ) async {
    await pumpDialog(tester, items: teachers(20));

    await tester.enterText(find.byType(TextField), 'такого нет');
    await tester.pump();

    expect(find.text('Ничего не найдено'), findsOneWidget);
  });

  testWidgets('выбор элемента возвращает его значение', (tester) async {
    String? picked;
    await pumpDialog(
      tester,
      items: ['205', '313'],
      onSelect: (value) => picked = value,
    );

    await tester.tap(find.text('313'));
    await tester.pump();

    expect(picked, '313');
  });

  testWidgets('выбранный элемент отмечен галочкой', (tester) async {
    await pumpDialog(tester, items: ['205', '313'], selected: '313');
    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}
