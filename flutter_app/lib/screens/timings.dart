// lib/timings.dart

// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Event {
  final String title;
  final TimeOfDay start;
  final TimeOfDay end;

  Event({required this.title, required this.start, required this.end});

  Map<String, dynamic> toJson() => {
        'title': title,
        'start': {'hour': start.hour, 'minute': start.minute},
        'end': {'hour': end.hour, 'minute': end.minute},
      };

  static Event fromJson(Map<String, dynamic> j) {
    final s = j['start'];
    final e = j['end'];
    return Event(
      title: j['title'],
      start: TimeOfDay(hour: s['hour'], minute: s['minute']),
      end: TimeOfDay(hour: e['hour'], minute: e['minute']),
    );
  }
}

enum CalendarView { day, week, month }

class TimingsScreen extends StatefulWidget {
  const TimingsScreen({super.key});

  @override
  State<TimingsScreen> createState() => _TimingsScreenState();
}

class _TimingsScreenState extends State<TimingsScreen> {
  DateTime _focusedDate = DateTime.now();
  CalendarView _view = CalendarView.week;

  final Map<String, List<Event>> _events = {};
  late SharedPreferences _prefs;

  final Color _anaBackground = const Color(0xFFF3ECDE);
  final Color _anaCard = const Color(0xFFBD9F72);
  final Color _anaAccent = const Color(0xFF8C6F4D);
  final Color _anaText = Colors.black87;

  @override
  void initState() {
    super.initState();
    _loadStoredEvents();
  }

  Future<void> _loadStoredEvents() async {
    _prefs = await SharedPreferences.getInstance();
    final stored = _prefs.getString('timings_events');
    if (stored != null) {
      final Map<String, dynamic> decoded = jsonDecode(stored);
      setState(() {
        for (var entry in decoded.entries) {
          final list = (entry.value as List)
              .map((e) => Event.fromJson(e as Map<String, dynamic>))
              .toList();
          _events[entry.key] = list;
        }
      });
    }
  }

  Future<void> _persistEvents() async {
    final Map<String, dynamic> toStore = {};
    for (var entry in _events.entries) {
      toStore[entry.key] = entry.value.map((e) => e.toJson()).toList();
    }
    await _prefs.setString('timings_events', jsonEncode(toStore));
  }

  String _dateKey(DateTime d) =>
      "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  List<Event> get _selectedDayEvents => _events[_dateKey(_focusedDate)] ?? [];

  void _addEventForFocusedDay() async {
    final titleController = TextEditingController();
    TimeOfDay start = TimeOfDay.now();
    TimeOfDay end = TimeOfDay(hour: (start.hour + 1) % 24, minute: start.minute);

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (c, setDialogState) {
          return AlertDialog(
            backgroundColor: _anaBackground,
            title: const Text('Add Event'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: start,
                          );
                          if (picked != null) {
                            setDialogState(() {
                              start = picked;
                              if (_timeOfDayToMinutes(end) <=
                                  _timeOfDayToMinutes(start)) {
                                end = TimeOfDay(
                                    hour: (start.hour + 1) % 24,
                                    minute: start.minute);
                              }
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 7, horizontal: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: _anaAccent.withOpacity(0.7)),
                          ),
                          child: Text(
                            'Start: ${start.format(context)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: end,
                          );
                          if (picked != null) {
                            setDialogState(() {
                              end = picked;
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 7, horizontal: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: _anaAccent.withOpacity(0.7)),
                          ),
                          child: Text(
                            'End: ${end.format(context)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final title = titleController.text.trim();
                  if (title.isEmpty) return;
                  final key = _dateKey(_focusedDate);
                  final event = Event(title: title, start: start, end: end);
                  setState(() {
                    _events.putIfAbsent(key, () => []).add(event);
                  });
                  _persistEvents();
                  Navigator.pop(ctx);
                },
                child: const Text('Add'),
              ),
            ],
          );
        });
      },
    );
  }

  int _timeOfDayToMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  void _goPrevious() {
    setState(() {
      if (_view == CalendarView.day) {
        _focusedDate = _focusedDate.subtract(const Duration(days: 1));
      } else if (_view == CalendarView.week) {
        _focusedDate = _focusedDate.subtract(const Duration(days: 7));
      } else {
        _focusedDate = DateTime(
          _focusedDate.year,
          _focusedDate.month - 1,
          _focusedDate.day,
        );
      }
    });
  }

  void _goNext() {
    setState(() {
      if (_view == CalendarView.day) {
        _focusedDate = _focusedDate.add(const Duration(days: 1));
      } else if (_view == CalendarView.week) {
        _focusedDate = _focusedDate.add(const Duration(days: 7));
      } else {
        _focusedDate = DateTime(
          _focusedDate.year,
          _focusedDate.month + 1,
          _focusedDate.day,
        );
      }
    });
  }

  List<DateTime> _daysInWeek(DateTime reference) {
    final start = reference.subtract(Duration(days: reference.weekday - 1));
    return List.generate(7, (i) => start.add(Duration(days: i)));
  }

  List<DateTime> _daysInMonth(DateTime reference) {
    final first = DateTime(reference.year, reference.month, 1);
    final nextMonth = DateTime(reference.year, reference.month + 1, 1);
    final days = nextMonth.difference(first).inDays;
    return List.generate(days,
        (i) => DateTime(reference.year, reference.month, i + 1));
  }

  String _titleForFocused() {
    if (_view == CalendarView.day) {
      return "${_focusedDate.day}/${_focusedDate.month}/${_focusedDate.year}";
    } else if (_view == CalendarView.week) {
      final week = _daysInWeek(_focusedDate);
      final start = week.first;
      final end = week.last;
      return "${start.day}/${start.month} - ${end.day}/${end.month}";
    } else {
      return "${_focusedDate.month}/${_focusedDate.year}";
    }
  }

  Widget _viewToggleButton(CalendarView mode, String label) {
    final selected = _view == mode;
    return GestureDetector(
      onTap: () => setState(() => _view = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? _anaAccent : _anaCard.withOpacity(0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 13,
              color: selected ? Colors.white : _anaText,
              fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _weekdayName(int w) {
    const names = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
    return names[(w - 1) % 7];
  }

  String _weekdayShort(int w) => _weekdayName(w).substring(0, 3);

  String _monthName(int m) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return names[(m - 1) % 12];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _anaBackground,
      appBar: AppBar(
        backgroundColor: _anaBackground,
        elevation: 0,
        titleSpacing: 0,
        title: const Text('Calendar'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 2.0),
            child: IconButton(
              tooltip: 'Add Event',
              onPressed: _addEventForFocusedDay,
              icon: const Icon(Icons.add),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 48),
            ),
          )
        ],
        foregroundColor: Colors.black87,
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
          child: Column(
            children: [
              Row(
                children: [
                  _viewToggleButton(CalendarView.day, 'Day'),
                  const SizedBox(width: 6),
                  _viewToggleButton(CalendarView.week, 'Week'),
                  const SizedBox(width: 6),
                  _viewToggleButton(CalendarView.month, 'Month'),
                  const Spacer(),
                  IconButton(
                    onPressed: _goPrevious,
                    icon: const Icon(Icons.chevron_left),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.0),
                      child: Text(
                        _titleForFocused(),
                        overflow: TextOverflow.visible,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: _anaText),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _goNext,
                    icon: const Icon(Icons.chevron_right),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: _anaCard.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(5),
                  child: _buildCalendarBody(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarBody() {
    switch (_view) {
      case CalendarView.day:
        return _buildDayView();
      case CalendarView.week:
        return _buildWeekView();
      case CalendarView.month:
        return _buildMonthView();
    }
  }

  Widget _dayHeader(DateTime d) {
    return Row(
      children: [
        Text(
          _weekdayName(d.weekday),
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold, color: _anaText),
        ),
        const SizedBox(width: 6),
        Text(
          '${d.day} ${_monthName(d.month)} ${d.year}',
          style: TextStyle(color: _anaText.withOpacity(0.9)),
        ),
      ],
    );
  }

  Widget _buildDayView() {
    final events = _selectedDayEvents;
    if (events.isEmpty) {
      return Center(
        child: Text(
          'No events',
          style: TextStyle(color: _anaText.withOpacity(0.6)),
        ),
      );
    }
    return Column(
      children: [
        _dayHeader(_focusedDate),
        const SizedBox(height: 4),
        Expanded(
          child: ListView.builder(
            itemCount: events.length,
            itemBuilder: (ctx, i) {
              final e = events[i];
              return Card(
                color: Colors.white,
                margin: const EdgeInsets.symmetric(vertical: 3),
                child: ListTile(
                  title: Text(e.title),
                  subtitle: Text(
                      '${e.start.format(context)} - ${e.end.format(context)}'),
                  onTap: () async {
                    final delete = await showDialog<bool>(
                      context: context,
                      builder: (dctx) {
                        return AlertDialog(
                          backgroundColor: _anaBackground,
                          title: const Text('Delete Event?'),
                          content: Text(
                              '${e.title}\n${e.start.format(context)} - ${e.end.format(context)}'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(dctx, false),
                                child: const Text('Cancel')),
                            TextButton(
                              onPressed: () => Navigator.pop(dctx, true),
                              child: const Text(
                                'Delete',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                    if (delete == true) {
                      final key = _dateKey(_focusedDate);
                      setState(() {
                        _events[key]?.removeAt(i);
                      });
                      _persistEvents();
                    }
                  },
                ),
              );
            },
          ),
        )
      ],
    );
  }

  Widget _buildWeekView() {
    final weekDays = _daysInWeek(_focusedDate);
    return Column(
      children: [
        // equal-width seven day buttons
        Row(
          children: weekDays.map((day) {
            final isSelected = _isSameDate(day, _focusedDate);
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _focusedDate = day),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _anaAccent
                        : Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _weekdayShort(day.weekday),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: isSelected ? Colors.white : _anaText),
                      ),
                      Text(
                        '${day.day}',
                        style: TextStyle(
                            fontSize: 12,
                            color: isSelected ? Colors.white : _anaText),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 3),
        Expanded(child: _buildDayView()),
      ],
    );
  }

  Widget _buildMonthView() {
    final monthDays = _daysInMonth(_focusedDate);
    final firstWeekday =
        DateTime(_focusedDate.year, _focusedDate.month, 1).weekday;
    final leadingEmpty = firstWeekday - 1;

    return Column(
      children: [
        // ✅ increase calendar grid height
        Flexible(
          flex: 3, // was 2
          child: GridView.builder(
            physics: const ClampingScrollPhysics(),
            itemCount: monthDays.length + leadingEmpty,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4, // slightly more spacing
              crossAxisSpacing: 4, // slightly more spacing
            ),
            itemBuilder: (ctx, index) {
              if (index < leadingEmpty) {
                return const SizedBox();
              }
              final day = monthDays[index - leadingEmpty];
              final key = _dateKey(day);
              final hasEvents =
                  _events.containsKey(key) && _events[key]!.isNotEmpty;
              final isSelected = _isSameDate(day, _focusedDate);
              return GestureDetector(
                onTap: () => setState(() => _focusedDate = day),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected ? _anaAccent : Colors.white,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: _anaAccent.withOpacity(0.5)),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          '${day.day}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                            color: isSelected ? Colors.white : _anaText,
                          ),
                        ),
                      ),
                      if (hasEvents)
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        // ✅ slightly smaller event list
        Flexible(
          flex: 2, // was 3
          child: _buildDayView(),
        ),
      ],
    );
  }
}
