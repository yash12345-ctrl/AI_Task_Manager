import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


const String GEMINI_API_KEY = "AIzaSyAPedjxWZPnu8qV4TqQJFtIYwiRR5CrQUc";


class Task {
  final String id;
  final String title;
  final DateTime dueDate;
  final String priority;
  final String category;
  bool isCompleted;

  Task({
    required this.id,
    required this.title,
    required this.dueDate,
    required this.priority,
    required this.category,
    this.isCompleted = false,
  });

  factory Task.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return Task(
      id: doc.id,
      title: data['title'] ?? '',
      dueDate: (data['dueDate'] as Timestamp).toDate(),
      priority: data['priority'] ?? 'Medium',
      category: data['category'] ?? 'Work',
      isCompleted: data['isCompleted'] ?? false,
    );
  }
}

class TaskPage extends StatefulWidget {
  const TaskPage({super.key});

  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  final CollectionReference _tasksCollection =
      FirebaseFirestore.instance.collection('tasks');

  late StreamSubscription _tasksSubscription;
  bool _isPageLoading = true;
  List<Task> _allTasks = [];

  final _formKey = GlobalKey<FormState>();
  String _title = '';
  DateTime _dueDate = DateTime.now();
  String _priority = 'Medium';
  String _category = 'Work';

  String _sortBy = 'DueDate';
  String _filterPriority = 'All';
  String _filterCategory = 'All';

  bool _isLoadingAI = false;
  List<String> _aiSuggestions = [];

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;

    _tasksSubscription = _tasksCollection.snapshots().listen((snapshot) {
      final tasks =
          snapshot.docs.map((doc) => Task.fromFirestore(doc)).toList();
      if (mounted) {
        setState(() {
          _allTasks = tasks;
          _isPageLoading = false;
        });
        _fetchAISuggestions(tasks); 
      }
    }, onError: (error) {
      if (mounted) {
        setState(() {
          _isPageLoading = false;
        });
        print("Error listening to tasks: $error");
      }
    });
  }

  @override
  void dispose() {
    _tasksSubscription.cancel();
    super.dispose();
  }

  Future<void> _fetchAISuggestions(List<Task> tasks) async {
    if (tasks.where((t) => !t.isCompleted).isEmpty) {
      if (mounted) {
        setState(() {
          _aiSuggestions = ["No pending tasks! 🎉 Add one to get started."];
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _isLoadingAI = true;
      });
    }
    try {
      final taskData = tasks
          .where((t) => !t.isCompleted)
          .map((t) => {
                "title": t.title,
                "dueDate": t.dueDate.toIso8601String(),
                "priority": t.priority,
                "category": t.category,
              })
          .toList();
      final response = await http.post(
        Uri.parse(
          "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key=$GEMINI_API_KEY",
        ),
        headers: {
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {
                  "text":
                      "You are a smart task assistant. Based on these tasks: $taskData\nGive 3 useful suggestions."
                }
              ]
            }
          ]
        }),
      );
      if (mounted) {
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

        
          final aiText = data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? "No suggestions.";

          setState(() {
            _aiSuggestions =
                (aiText as String).split("\n").where((s) => s.trim().isNotEmpty).toList();
          });
        } else {
          setState(() {
            _aiSuggestions = [
              "⚠️ Failed to fetch AI suggestions. (${response.statusCode})"
            ];
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _aiSuggestions = ["⚠️ Error: $e"];
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAI = false;
        });
      }
    }
  }

  void _addTask() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      await _tasksCollection.add({
        'title': _title,
        'dueDate': Timestamp.fromDate(_dueDate),
        'priority': _priority,
        'category': _category,
        'isCompleted': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      Navigator.pop(context);
    }
  }

  void _toggleTaskCompletion(Task task) async {
    await _tasksCollection.doc(task.id).update({
      'isCompleted': !task.isCompleted,
    });
  }

  void _deleteTask(Task task) async {
    await _tasksCollection.doc(task.id).delete();
  }

  void _showAddTaskDialog() {
    _title = '';
    _dueDate = DateTime.now();
    _priority = 'Medium';
    _category = 'Work';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return LayoutBuilder(
          builder: (context, constraints) {
            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              maxChildSize: 0.95,
              minChildSize: 0.6,
              builder: (_, controller) => Container(
                padding: EdgeInsets.symmetric(
                  horizontal: constraints.maxWidth < 500 ? 20 : 40,
                  vertical: constraints.maxHeight < 700 ? 20 : 35,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 20,
                      color: Colors.black26,
                      offset: Offset(0, -5),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  controller: controller,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        Container(
                          height: 5,
                          width: 40,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: Colors.grey,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        const Text(
                          "Add New Task",
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue),
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          decoration: InputDecoration(
                            labelText: "Task Title",
                            prefixIcon: const Icon(Icons.title, color: Colors.blue),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (val) => val == null || val.isEmpty ? "Enter a task title" : null,
                          onSaved: (val) => _title = val!,
                        ),
                        const SizedBox(height: 15),
                        StatefulBuilder(
                          builder: (context, setModalState) {
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text("Due Date"),
                              subtitle: Text(DateFormat.yMMMd().format(_dueDate)),
                              trailing: const Icon(Icons.calendar_today, color: Colors.blue),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _dueDate,
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null && picked != _dueDate) {
                                  setModalState(() {
                                    _dueDate = picked;
                                  });
                                }
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 15),
                        DropdownButtonFormField<String>(
                          value: _priority,
                          decoration: InputDecoration(
                            labelText: "Priority",
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: const Icon(Icons.flag, color: Colors.orange),
                          ),
                          items: ["High", "Medium", "Low"]
                              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (val) => _priority = val!,
                        ),
                        const SizedBox(height: 15),
                        DropdownButtonFormField<String>(
                          value: _category,
                          decoration: InputDecoration(
                            labelText: "Category",
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: const Icon(Icons.category, color: Colors.green),
                          ),
                          items: ["Work", "Personal", "Study"]
                              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (val) => _category = val!,
                        ),
                        const SizedBox(height: 25),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              minimumSize: Size(double.infinity, constraints.maxHeight < 700 ? 45 : 55),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              backgroundColor: Colors.blue,
                              elevation: 5,
                            ),
                            onPressed: _addTask,
                            child: const Text(
                              "Add Task",
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAICalendar(List<Task> allTasks) {
    showDialog(
      context: context,
      builder: (context) {
        return LayoutBuilder(
          builder: (context, constraints) {
            return StatefulBuilder(builder: (context, setDialogState) {
              List<Task> getTasksForDay(DateTime day) {
                return allTasks
                    .where((task) => isSameDay(task.dueDate, day))
                    .toList();
              }

              final List<Task> selectedTasks =
                  _selectedDay == null ? [] : getTasksForDay(_selectedDay!);

              String generateDailySummary(List<Task> tasks, DateTime selectedDay) {
                if (tasks.isEmpty) {
                  return "A clear day! Perfect for planning ahead. 🧘";
                }
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                final selected = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
                final daysUntilDue = selected.difference(today).inDays;

                tasks.sort((a, b) {
                  final priorityMap = {'High': 1, 'Medium': 2, 'Low': 3};
                  return priorityMap[a.priority]!.compareTo(priorityMap[b.priority]!);
                });
                final mostUrgentTask = tasks.first;
                if (daysUntilDue == 0) {
                  return "Due Today: Focus on '${mostUrgentTask.title}' (${mostUrgentTask.priority} priority).";
                }
                if (daysUntilDue == 1) {
                  return "Due Tomorrow: Prepare for '${mostUrgentTask.title}'. ⏰";
                }
                if (daysUntilDue > 1) {
                  return "Due in $daysUntilDue days: Plan for '${mostUrgentTask.title}'.";
                }
                if (daysUntilDue < 0) {
                  return "Overdue: ${tasks.length} task(s) were due on this day.";
                }
                return "You have ${tasks.length} task(s) on the agenda.";
              }

              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Container(
                  width: constraints.maxWidth < 500 ? double.infinity : 450,
                  padding: EdgeInsets.symmetric(
                    horizontal: constraints.maxWidth < 500 ? 10 : 24,
                    vertical: constraints.maxHeight < 700 ? 10 : 20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "AI Task Calendar 🗓️",
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                      ),
                      const SizedBox(height: 16),
                      TableCalendar<Task>(
                        firstDay: DateTime.utc(2020, 1, 1),
                        lastDay: DateTime.utc(2100, 12, 31),
                        focusedDay: _focusedDay,
                        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                        eventLoader: getTasksForDay,
                        onDaySelected: (selectedDay, focusedDay) {
                          setDialogState(() {
                            _selectedDay = selectedDay;
                            _focusedDay = focusedDay;
                          });
                        },
                        calendarStyle: CalendarStyle(
                          todayDecoration: BoxDecoration(
                            color: Colors.blue.shade200,
                            shape: BoxShape.circle,
                          ),
                          selectedDecoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                          markerDecoration: const BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                        headerStyle: const HeaderStyle(
                          formatButtonVisible: false,
                          titleCentered: true,
                          titleTextStyle: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.insights, color: Colors.blue, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                generateDailySummary(selectedTasks, _selectedDay ?? DateTime.now()),
                                style: const TextStyle(
                                    color: Colors.blue, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 24),
                      Expanded(
                        child: selectedTasks.isEmpty
                            ? const Center(
                                child: Text(
                                  "No tasks for this day.",
                                  style: TextStyle(color: Colors.grey),
                                ),
                              )
                            : ListView.builder(
                                itemCount: selectedTasks.length,
                                itemBuilder: (context, index) {
                                  final task = selectedTasks[index];
                                  return Card(
                                    color: _priorityColor(task.priority).withOpacity(0.1),
                                    elevation: 0,
                                    margin: const EdgeInsets.symmetric(vertical: 4),
                                    child: ListTile(
                                      title: Text(task.title,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      leading: Icon(
                                        Icons.circle,
                                        color: _priorityColor(task.priority),
                                        size: 12,
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              );
            });
          },
        );
      },
    );
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case "High":
        return Colors.red;
      case "Medium":
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  List<Task> _getProcessedTasks(List<Task> allTasks, bool completed) {
    List<Task> filteredTasks = allTasks.where((task) {
      if (task.isCompleted != completed) return false;
      if (_filterPriority != 'All' && task.priority != _filterPriority) {
        return false;
      }
      if (_filterCategory != 'All' && task.category != _filterCategory) {
        return false;
      }
      return true;
    }).toList();

    final priorityMap = {'High': 1, 'Medium': 2, 'Low': 3};
    filteredTasks.sort((a, b) {
      switch (_sortBy) {
        case 'Priority':
          return priorityMap[a.priority]!.compareTo(priorityMap[b.priority]!);
        case 'Title':
          return a.title.compareTo(b.title);
        case 'DueDate':
        default:
          return a.dueDate.compareTo(b.dueDate);
      }
    });
    return filteredTasks;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isWide = media.size.width > 650;
    final horizontalPadding = isWide ? 40.0 : 16.0;

    if (_isPageLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final activeTasks = _getProcessedTasks(_allTasks, false);
    final completedTasks = _getProcessedTasks(_allTasks, true);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text(
          "My Tasks",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            onPressed: () => _showAICalendar(_allTasks),
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: "AI Calendar",
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              16,
              horizontalPadding,
              0,
            ),
            child: Column(
              children: [
                Card(
                  elevation: 5,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _isLoadingAI
                        ? const Center(child: CircularProgressIndicator(color: Colors.blue))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "AI Suggestions 💡",
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue),
                              ),
                              const SizedBox(height: 12),
                              ..._aiSuggestions.map((s) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.bolt, color: Colors.orange, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(s)),
                                      ],
                                    ),
                                  )),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Sort By:", style: TextStyle(fontWeight: FontWeight.bold)),
                        DropdownButton<String>(
                          value: _sortBy,
                          underline: Container(),
                          items: ['DueDate', 'Priority', 'Title']
                              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _sortBy = val);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (activeTasks.isEmpty && completedTasks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                      child: Text(
                        "No tasks yet.\nTap + to add one!",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 18,
                            color: Colors.black45,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  )
                else ...[
                  ...activeTasks.map((task) => _buildTaskTile(task, isWide: isWide)),
                  if (completedTasks.isNotEmpty)
                    ExpansionTile(
                      initiallyExpanded: true,
                      title: const Text(
                        "Completed Tasks",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                      leading: const Icon(Icons.check_circle, color: Colors.green),
                      children: completedTasks.map((task) => _buildTaskTile(task, isWide: isWide)).toList(),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddTaskDialog,
        label: const Text("Add Task"),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.blue,
        elevation: 6,
      ),
    );
  }

  Widget _buildTaskTile(Task task, {required bool isWide}) {
    return Dismissible(
      key: Key(task.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _deleteTask(task),
      background: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Align(
          alignment: Alignment.centerRight,
          child: Icon(Icons.delete, color: Colors.white),
        ),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        margin: EdgeInsets.only(bottom: isWide ? 22 : 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [
              Colors.white,
              Colors.blue.shade50,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              offset: Offset(2, 3),
            ),
          ],
        ),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          contentPadding: EdgeInsets.symmetric(horizontal: isWide ? 26 : 16, vertical: 12),
          leading: Checkbox(
            activeColor: Colors.blue,
            value: task.isCompleted,
            onChanged: (val) {
              _toggleTaskCompletion(task);
            },
          ),
          title: Text(
            task.title,
            style: TextStyle(
              fontSize: isWide ? 20 : 18,
              fontWeight: FontWeight.bold,
              color: task.isCompleted ? Colors.grey : Colors.black87,
              decoration: task.isCompleted ? TextDecoration.lineThrough : null,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Due: ${DateFormat.yMMMd().format(task.dueDate)}",
                  style: TextStyle(
                      color: task.isCompleted ? Colors.grey : Colors.black54),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: isWide ? 10 : 6,
                  runSpacing: 6,
                  children: [
                    Chip(
                      label: Text(task.priority),
                      backgroundColor: _priorityColor(task.priority).withOpacity(0.1),
                      labelStyle: TextStyle(
                        color: _priorityColor(task.priority),
                        fontWeight: FontWeight.bold,
                        fontSize: isWide ? 15 : 13,
                      ),
                    ),
                    Chip(
                      label: Text(task.category),
                      backgroundColor: Colors.blue.withOpacity(0.1),
                      labelStyle: TextStyle(
                          color: Colors.blue, fontWeight: FontWeight.bold, fontSize: isWide ? 15 : 13),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TaskAnalysisPage(task: task),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: isWide ? 18 : 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: const BorderSide(color: Colors.blue),
                      ),
                      icon: const Icon(Icons.analytics, size: 18, color: Colors.blue),
                      label: Text(
                        "AI Analyse",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.blue,
                          fontSize: isWide ? 15 : 13,
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
          trailing: Icon(
            task.isCompleted
                ? Icons.check_circle
                : Icons.arrow_forward_ios,
            size: 20,
            color: task.isCompleted ? Colors.green : Colors.black38,
          ),
        ),
      ),
    );
  }
}


class TaskAnalysisPage extends StatefulWidget {
  final Task task;
  const TaskAnalysisPage({super.key, required this.task});

  @override
  State<TaskAnalysisPage> createState() => _TaskAnalysisPageState();
}

class _TaskAnalysisPageState extends State<TaskAnalysisPage> {
  bool _loadingPlan = true;
  String _planText = '';
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];

  @override
  void initState() {
    super.initState();
    _fetchQuickPlan();
  }

  Future<void> _fetchQuickPlan() async {
    setState(() {
      _loadingPlan = true;
      _planText = '';
    });

    final task = widget.task;
    final intro =
        "You are an expert task coach. Create a concise, actionable plan using markdown with steps, estimates, checkpoints, risks, and tools for this single task.\n"
        "Task Details:\n"
        "- Title: ${task.title}\n"
        "- Due: ${DateFormat.yMMMd().format(task.dueDate)}\n"
        "- Priority: ${task.priority}\n"
        "- Category: ${task.category}\n";

    try {
      final res = await http.post(
        Uri.parse(
          "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key=$GEMINI_API_KEY",
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": intro}
              ]
            }
          ]
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);

        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? "No plan generated.";

        setState(() {
          _planText = text.toString().trim();
        });
      } else {
        setState(() {
          _planText =
              "⚠️ Failed to generate plan. (${res.statusCode})";
        });
      }
    } catch (e) {
      setState(() {
        _planText = "⚠️ Error: $e";
      });
    } finally {
      setState(() {
        _loadingPlan = false;
      });
    }
  }

  Future<void> _sendChatMessage() async {
    final userText = _chatController.text.trim();
    if (userText.isEmpty) return;

    setState(() {
      _messages.add({"role": "user", "text": userText});
      _chatController.clear();
    });
    _scrollToBottom();

    final task = widget.task;
    final contents = <Map<String, dynamic>>[];

    contents.add({
      "parts": [
        {
          "text":
              "You are an expert productivity and project coach. Help with step-by-step, practical advice. Keep answers concise with checklists when useful."
        }
      ]
    });

    contents.add({
      "parts": [
        {
          "text":
              "Task Context:\nTitle: ${task.title}\nDue: ${DateFormat.yMMMd().format(task.dueDate)}\nPriority: ${task.priority}\nCategory: ${task.category}"
        }
      ]
    });

    for (final msg in _messages) {
      contents.add({
        "role": msg["role"],
        "parts": [
          {"text": msg["text"]}
        ],
      });
    }

    try {
      final res = await http.post(
        Uri.parse(
          "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key=$GEMINI_API_KEY",
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"contents": contents}),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);

        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? "…";

        setState(() {
          _messages.add({"role": "model", "text": text.toString().trim()});
        });
      } else {
        setState(() {
          _messages.add({
            "role": "model",
            "text": "⚠️ Request failed (${res.statusCode}). Try again."
          });
        });
      }
    } catch (e) {
      setState(() {
        _messages.add({
          "role": "model",
          "text": "⚠️ Error: $e"
        });
      });
    } finally {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isWide = media.size.width > 650;
    final horizontalPadding = isWide ? 40.0 : 16.0;

    final task = widget.task;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text(
          "AI Task Analysis",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue,
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(horizontalPadding, 16, horizontalPadding, 8),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: [Colors.white, Colors.blue.shade50],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(2, 3),
                    ),
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: Text(
                    task.title,
                    style: TextStyle(
                      fontSize: isWide ? 20 : 18,
                      fontWeight: FontWeight.bold
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Wrap(
                      spacing: isWide ? 12 : 8,
                      runSpacing: 8,
                      children: [
                        _pill(Icons.event, "Due: ${DateFormat.yMMMd().format(task.dueDate)}", isWide),
                        _pill(Icons.flag, "Priority: ${task.priority}", isWide),
                        _pill(Icons.category, "Category: ${task.category}", isWide),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 8,
                          offset: Offset(2, 3),
                        ),
                      ],
                    ),
                    child: _loadingPlan
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(color: Colors.blue),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Quick Plan 🗺️",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.blue,
                                ),
                              ),
                              const SizedBox(height: 10),
                              MarkdownBody(
                                data: _planText,
                                selectable: true,
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: _fetchQuickPlan,
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text("Regenerate"),
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 300,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 8,
                            offset: Offset(2, 3),
                          ),
                        ],
                      ),
                      child: ListView.builder(
                        controller: _scrollController,
                        itemCount: _messages.length,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        itemBuilder: (context, index) {
                          final m = _messages[index];
                          final isUser = m["role"] == "user";
                          return Align(
                            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                              padding: EdgeInsets.symmetric(vertical: 10, horizontal: isWide ? 18 : 14),
                              constraints: BoxConstraints(
                                maxWidth: media.size.width * (isWide ? 0.66 : 0.8),
                              ),
                              decoration: BoxDecoration(
                                color: isUser ? Colors.blue : Colors.blue.shade50,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                                  bottomRight: Radius.circular(isUser ? 4 : 16),
                                ),
                              ),
                              child: SelectableText(
                                m["text"] ?? "",
                                style: TextStyle(
                                  color: isUser ? Colors.white : Colors.black87,
                                  fontSize: isWide ? 15 : 13,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, isWide ? 20 : 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _chatController,
                        minLines: 1,
                        maxLines: 5,
                        decoration: InputDecoration(
                          hintText: "Ask how to complete this task…",
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: EdgeInsets.symmetric(horizontal: isWide ? 18 : 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Colors.black12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: _sendChatMessage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: EdgeInsets.symmetric(horizontal: isWide ? 18 : 14, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 3,
                      ),
                      icon: const Icon(Icons.send, size: 18, color: Colors.white),
                      label: const Text(
                        "Send",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String text, bool isWide) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isWide ? 12 : 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: isWide ? 18 : 16, color: Colors.blue),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: Colors.blue,
              fontWeight: FontWeight.w600,
              fontSize: isWide ? 15 : 13,
            ),
          ),
        ],
      ),
    );
  }
}
