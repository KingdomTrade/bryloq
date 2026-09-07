import 'package:flutter/material.dart';

import '../models/saydo_task.dart';

class SearchHistoryScreen extends StatefulWidget {
  final List<SayDoTask> tasks;

  const SearchHistoryScreen({
    super.key,
    required this.tasks,
  });

  @override
  State<SearchHistoryScreen> createState() =>
      _SearchHistoryScreenState();
}

class _SearchHistoryScreenState extends State<SearchHistoryScreen> {
  final TextEditingController _searchController =
      TextEditingController();

  String _filter = 'all';
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SayDoTask> get _results {
    final query = _query.trim().toLowerCase();

    final items = widget.tasks.where((task) {
      if (!_matchesFilter(task)) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final searchable = [
        task.title,
        task.type,
        task.date ?? '',
        task.time ?? '',
        task.priority,
        task.notes ?? '',
        task.recurrence ?? '',
        task.reminder ?? '',
      ].join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();

    items.sort((a, b) {
      if (a.completed != b.completed) {
        return a.completed ? 1 : -1;
      }

      final aDate = '${a.date ?? '9999-99-99'} ${a.time ?? '99:99'}';
      final bDate = '${b.date ?? '9999-99-99'} ${b.time ?? '99:99'}';

      final compare = aDate.compareTo(bDate);

      if (compare != 0) {
        return compare;
      }

      return b.createdAt.compareTo(a.createdAt);
    });

    return items;
  }

  bool _matchesFilter(SayDoTask task) {
    switch (_filter) {
      case 'active':
        return !task.completed;
      case 'completed':
        return task.completed;
      case 'notes':
        return task.type == 'note';
      case 'scheduled':
        return task.date?.trim().isNotEmpty == true;
      default:
        return true;
    }
  }

  int _countWhere(bool Function(SayDoTask task) test) {
    return widget.tasks.where(test).length;
  }

  String _subtitle(SayDoTask task) {
    final parts = <String>[];

    if (task.date?.trim().isNotEmpty == true) {
      parts.add(task.date!.trim());
    }

    if (task.time?.trim().isNotEmpty == true) {
      parts.add(task.time!.trim());
    }

    parts.add(
      task.type.replaceAll('_', ' ').toUpperCase(),
    );

    if (task.recurring) {
      parts.add(
        task.recurrence?.trim().isNotEmpty == true
            ? task.recurrence!.trim()
            : 'Recurring',
      );
    }

    if (task.priority == 'high') {
      parts.add('High priority');
    }

    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final activeCount = _countWhere((task) => !task.completed);
    final completedCount = _countWhere((task) => task.completed);
    final notesCount = _countWhere((task) => task.type == 'note');

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F8FC),
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Search & history',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (value) {
                  setState(() {
                    _query = value;
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search tasks, notes, dates, reminders...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _query = '';
                            });
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _filterChip('all', 'All ${widget.tasks.length}'),
                  _filterChip('active', 'Active $activeCount'),
                  _filterChip('completed', 'Done $completedCount'),
                  _filterChip('notes', 'Notes $notesCount'),
                  _filterChip('scheduled', 'Scheduled'),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${results.length} ${results.length == 1 ? 'result' : 'results'}',
                      style: const TextStyle(
                        color: Color(0xFF8E8B95),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Text(
                    'Tap a result to edit',
                    style: TextStyle(
                      color: Color(0xFF8E8B95),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: results.isEmpty
                  ? _emptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                      itemCount: results.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        return _resultTile(results[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(
    String value,
    String label,
  ) {
    final selected = _filter == value;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: selected,
        onSelected: (_) {
          setState(() {
            _filter = value;
          });
        },
        label: Text(label),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: selected
              ? const Color(0xFF5548EB)
              : const Color(0xFF67646E),
        ),
        selectedColor: const Color(0xFFEDEAFF),
        backgroundColor: Colors.white,
        side: BorderSide(
          color: selected
              ? const Color(0xFFCFC9FF)
              : const Color(0xFFE9E7EF),
        ),
      ),
    );
  }

  Widget _resultTile(SayDoTask task) {
    final notes = task.notes?.trim();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        borderRadius: BorderRadius.circular(19),
        onTap: () {
          Navigator.pop(context, task);
        },
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: task.completed
                      ? const Color(0xFFE7F6EC)
                      : const Color(0xFFF0EEFF),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  task.completed
                      ? Icons.check_rounded
                      : _iconForTask(task.type),
                  color: task.completed
                      ? const Color(0xFF319B5D)
                      : const Color(0xFF6558F5),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              decoration: task.completed
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: task.completed
                                  ? Colors.grey
                                  : const Color(0xFF24232A),
                            ),
                          ),
                        ),
                        if (task.completed)
                          const Text(
                            'DONE',
                            style: TextStyle(
                              color: Color(0xFF319B5D),
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _subtitle(task),
                      style: const TextStyle(
                        color: Color(0xFF8E8B95),
                        fontSize: 11,
                      ),
                    ),
                    if (notes != null && notes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        notes,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF67646E),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFB4B0BE),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: Color(0xFFB4B0BE),
            ),
            SizedBox(height: 12),
            Text(
              'Nothing matched',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'Try another word or filter.',
              style: TextStyle(
                color: Color(0xFF8E8B95),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForTask(String type) {
    switch (type) {
      case 'reminder':
        return Icons.notifications_outlined;
      case 'appointment':
        return Icons.calendar_month_outlined;
      case 'event':
        return Icons.event_outlined;
      case 'shopping':
        return Icons.shopping_bag_outlined;
      case 'routine':
        return Icons.repeat_rounded;
      case 'note':
        return Icons.lightbulb_outline_rounded;
      case 'follow_up':
        return Icons.schedule_send_outlined;
      default:
        return Icons.check_circle_outline_rounded;
    }
  }
}
