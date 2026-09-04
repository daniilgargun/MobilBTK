/*
 * Copyright (c) 2024 Daniil Gargun. All rights reserved.
 * Author: Daniil Gargun | Telegram: @Daniilgargun | Email: daniilgorgun38@gmail.com
 */

import 'package:flutter/material.dart';

/// Что выбрал пользователь в листе фильтра календаря.
class CalendarFilterResult {
  /// 'all' | 'group' | 'teacher'
  final String filter;
  final String? group;
  final String? teacher;

  const CalendarFilterResult({required this.filter, this.group, this.teacher});

  const CalendarFilterResult.all()
    : filter = 'all',
      group = null,
      teacher = null;
}

/// Нижний лист выбора фильтра календаря.
///
/// Раньше это были два диалога подряд: сначала «Фильтр» с тремя пунктами,
/// затем отдельное окно со списком. Теперь всё в одном листе: кнопка
/// «Показать всё» сверху и две вкладки со списками и поиском.
Future<CalendarFilterResult?> showCalendarFilterSheet({
  required BuildContext context,
  required List<String> groups,
  required List<String> teachers,
  required String selectedFilter,
  String? selectedGroup,
  String? selectedTeacher,
}) {
  return showModalBottomSheet<CalendarFilterResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _CalendarFilterSheet(
      groups: groups,
      teachers: teachers,
      selectedFilter: selectedFilter,
      selectedGroup: selectedGroup,
      selectedTeacher: selectedTeacher,
    ),
  );
}

class _CalendarFilterSheet extends StatefulWidget {
  final List<String> groups;
  final List<String> teachers;
  final String selectedFilter;
  final String? selectedGroup;
  final String? selectedTeacher;

  const _CalendarFilterSheet({
    required this.groups,
    required this.teachers,
    required this.selectedFilter,
    required this.selectedGroup,
    required this.selectedTeacher,
  });

  @override
  State<_CalendarFilterSheet> createState() => _CalendarFilterSheetState();
}

class _CalendarFilterSheetState extends State<_CalendarFilterSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> _filtered(List<String> items) {
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return items;
    return items
        .where((item) => item.toLowerCase().contains(needle))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAll = widget.selectedFilter == 'all';

    // Открываем сразу на той вкладке, которая уже выбрана.
    final initialIndex = widget.selectedFilter == 'teacher' ? 1 : 0;

    return DefaultTabController(
      length: 2,
      initialIndex: initialIndex,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Фильтр расписания',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (!isAll)
                      TextButton.icon(
                        onPressed: () => Navigator.pop(
                          context,
                          const CalendarFilterResult.all(),
                        ),
                        icon: const Icon(Icons.clear_all, size: 18),
                        label: const Text('Показать всё'),
                      ),
                  ],
                ),
              ),

              if (isAll)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'Сейчас показано расписание всех групп',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),

              TabBar(
                tabs: const [
                  Tab(text: 'ГРУППЫ'),
                  Tab(text: 'ПРЕПОДАВАТЕЛИ'),
                ],
                onTap: (_) {
                  // Запрос относится к конкретному списку, поэтому при
                  // переключении вкладки его логично сбросить.
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Поиск',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            tooltip: 'Очистить',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              Expanded(
                child: TabBarView(
                  children: [
                    _buildList(
                      items: _filtered(widget.groups),
                      selected: widget.selectedFilter == 'group'
                          ? widget.selectedGroup
                          : null,
                      onSelect: (value) => Navigator.pop(
                        context,
                        CalendarFilterResult(filter: 'group', group: value),
                      ),
                      emptyText: 'Список групп пуст',
                    ),
                    _buildList(
                      items: _filtered(widget.teachers),
                      selected: widget.selectedFilter == 'teacher'
                          ? widget.selectedTeacher
                          : null,
                      onSelect: (value) => Navigator.pop(
                        context,
                        CalendarFilterResult(filter: 'teacher', teacher: value),
                      ),
                      emptyText: 'Список преподавателей пуст',
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

  Widget _buildList({
    required List<String> items,
    required String? selected,
    required ValueChanged<String> onSelect,
    required String emptyText,
  }) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _query.isEmpty ? emptyText : 'Ничего не найдено',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isSelected = item == selected;

        return ListTile(
          title: Text(item),
          selected: isSelected,
          trailing: isSelected
              ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
              : null,
          onTap: () => onSelect(item),
        );
      },
    );
  }
}
