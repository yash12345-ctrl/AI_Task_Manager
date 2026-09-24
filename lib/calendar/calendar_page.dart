import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../models/task_model.dart';

class PremiumCalendarPage extends StatefulWidget {
  final List<Task> tasks;
  final Future<void> Function() onSync;
  final bool showSyncHint;

  const PremiumCalendarPage({
    super.key,
    required this.tasks,
    required this.onSync,
    this.showSyncHint = false,
  });

  @override
  State<PremiumCalendarPage> createState() => _PremiumCalendarPageState();
}

class _PremiumCalendarPageState extends State<PremiumCalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    if (widget.showSyncHint) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Tap the sync icon at the top right to get updated! 🔄'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.blue.shade800,
            duration: const Duration(seconds: 4),
          ),
        );
      });
    }
  }

  List<Task> _getTasksForDay(DateTime day) {
    return widget.tasks.where((task) {
      return isSameDay(task.dueDate, day);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final selectedTasks = _getTasksForDay(_selectedDay ?? _focusedDay);
    final completedCount = selectedTasks.where((t) => t.isCompleted).length;
    final remainingCount = selectedTasks.length - completedCount;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AppBar(
              elevation: 0,
              backgroundColor: Colors.white.withOpacity(0.6),
              foregroundColor: Colors.black87,
              title: const Text('Schedule', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              centerTitle: true,
              actions: [
                _isSyncing
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                      )
                    : IconButton(
                        icon: const Icon(Icons.sync_rounded, color: Colors.blueAccent),
                        tooltip: 'Sync with Device Calendar',
                        onPressed: () async {
                          setState(() => _isSyncing = true);
                          await widget.onSync();
                          if (mounted) {
                            setState(() => _isSyncing = false);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Calendar Synced!')));
                          }
                        },
                      ),
              ],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFFF0F4F8), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: TableCalendar<Task>(
                  firstDay: DateTime.utc(2020, 10, 16),
                  lastDay: DateTime.utc(2030, 3, 14),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                  },
                  eventLoader: _getTasksForDay,
                  daysOfWeekStyle: DaysOfWeekStyle(
                    weekdayStyle: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
                    weekendStyle: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black38),
                  ),
                  calendarStyle: CalendarStyle(
                    todayDecoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    todayTextStyle: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
                    selectedDecoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Colors.blueAccent, Colors.lightBlue]),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.blueAccent.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4)),
                      ],
                    ),
                    markerDecoration: const BoxDecoration(
                      color: Colors.deepPurpleAccent,
                      shape: BoxShape.circle,
                    ),
                    markersMaxCount: 1,
                  ),
                  headerStyle: const HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                    titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                    leftChevronIcon: Icon(Icons.chevron_left_rounded, color: Colors.black87),
                    rightChevronIcon: Icon(Icons.chevron_right_rounded, color: Colors.black87),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedDay != null ? DateFormat.EEEE().format(_selectedDay!) : 'Tasks',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade500),
                        ),
                        Text(
                          _selectedDay != null ? DateFormat.MMMMd().format(_selectedDay!) : '',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.black87, letterSpacing: -0.5),
                        ),
                      ],
                    ),
                    if (selectedTasks.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: remainingCount == 0 ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          remainingCount == 0 ? "All Done!" : "$remainingCount remaining",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: remainingCount == 0 ? Colors.green.shade700 : Colors.orange.shade700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: selectedTasks.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.event_available_rounded, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(
                              'Free day!',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'No tasks scheduled',
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: selectedTasks.length,
                        itemBuilder: (context, index) {
                          final task = selectedTasks[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey.shade100, width: 1.5),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
                              ],
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: _getPriorityColor(task.priority).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: task.isCompleted ? Colors.grey : _getPriorityColor(task.priority),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(
                                task.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                                  color: task.isCompleted ? Colors.grey.shade400 : Colors.black87,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Row(
                                  children: [
                                    if (task.category.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          task.category,
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                                        ),
                                      ),
                                    if (task.category.isNotEmpty) const SizedBox(width: 8),
                                    if (task.hasTime)
                                      Row(
                                        children: [
                                          Icon(Icons.access_time_rounded, size: 12, color: Colors.grey.shade500),
                                          const SizedBox(width: 4),
                                          Text(
                                            DateFormat.Hm().format(task.dueDate),
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                              trailing: task.isCompleted
                                  ? const Icon(Icons.check_circle_rounded, color: Colors.green, size: 28)
                                  : Icon(Icons.circle_outlined, color: Colors.grey.shade300, size: 28),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case "P1": return Colors.redAccent;
      case "P2": return Colors.orangeAccent;
      case "P3": return Colors.blueAccent;
      default: return Colors.greenAccent;
    }
  }
}
