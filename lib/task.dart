import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'widgets/top_bar.dart';
import 'widgets/bottom_bar.dart';
import 'add_task/add_task.dart';
import 'ai_task_analysis/ai_insights_card.dart';
import 'ai_task_analysis/ai_calendar.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';


class Subtask {
  final String id;
  String title;
  bool isCompleted;

  Subtask({
    required this.id,
    required this.title,
    this.isCompleted = false,
  });

  factory Subtask.fromJson(Map<String, dynamic> json) {
    return Subtask(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      isCompleted: json['isCompleted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'isCompleted': isCompleted,
    };
  }
}

class Project {
  final String id;
  String name;
  String? parentId; // For nested projects

  Project({
    required this.id,
    required this.name,
    this.parentId,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      parentId: json['parentId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'parentId': parentId,
    };
  }
}

class Task {
  final String id;
  final String title;
  final DateTime dueDate;
  final String priority;
  final String category;
  bool isCompleted;
  
  String? projectId;
  List<String> tags;
  List<Subtask> subtasks;
  int orderIndex;

  Task({
    required this.id,
    required this.title,
    required this.dueDate,
    required this.priority,
    required this.category,
    this.isCompleted = false,
    this.projectId,
    this.tags = const [],
    this.subtasks = const [],
    this.orderIndex = 0,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      dueDate: DateTime.parse(json['dueDate'] as String),
      priority: _mapOldPriority(json['priority'] as String? ?? 'Medium'),
      category: json['category'] as String? ?? 'Work',
      isCompleted: json['isCompleted'] as bool? ?? false,
      projectId: json['projectId'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      subtasks: (json['subtasks'] as List<dynamic>?)?.map((e) => Subtask.fromJson(e)).toList() ?? [],
      orderIndex: json['orderIndex'] as int? ?? 0,
    );
  }

  static String _mapOldPriority(String oldPriority) {
    switch (oldPriority.toLowerCase()) {
      case 'high': return 'P1';
      case 'medium': return 'P2';
      case 'low': return 'P3';
      case 'p1': return 'P1';
      case 'p2': return 'P2';
      case 'p3': return 'P3';
      case 'p4': return 'P4';
      default: return 'P4';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'dueDate': dueDate.toIso8601String(),
      'priority': priority,
      'category': category,
      'isCompleted': isCompleted,
      'projectId': projectId,
      'tags': tags,
      'subtasks': subtasks.map((e) => e.toJson()).toList(),
      'orderIndex': orderIndex,
    };
  }
}

class TaskPage extends StatefulWidget {
  const TaskPage({super.key});

  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  bool _isPageLoading = true;
  List<Task> _allTasks = [];
  List<Project> _allProjects = [];
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
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final String? projectsJson = prefs.getString('projects');
      if (projectsJson != null) {
        final List<dynamic> decodedProjects = jsonDecode(projectsJson);
        _allProjects = decodedProjects.map((e) => Project.fromJson(e as Map<String, dynamic>)).toList();
      }

      final String? tasksJson = prefs.getString('tasks');
      if (tasksJson != null) {
        final List<dynamic> decoded = jsonDecode(tasksJson);
        _allTasks = decoded.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      print("Error loading data: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isPageLoading = false;
        });
        _fetchAISuggestions(_allTasks);
      }
    }
  }

  Future<void> _saveData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String tasksJson = jsonEncode(_allTasks.map((t) => t.toJson()).toList());
      await prefs.setString('tasks', tasksJson);
      
      final String projectsJson = jsonEncode(_allProjects.map((p) => p.toJson()).toList());
      await prefs.setString('projects', projectsJson);
    } catch (e) {
      print("Error saving data: $e");
    }
  }

  @override
  void dispose() {
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
          "https://api.groq.com/openai/v1/chat/completions",
        ),
        headers: {
          "Authorization": "Bearer ${dotenv.env['GROQ_API_KEY']}",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "model": "gpt-oss-20b",
          "messages": [
            {
              "role": "user",
              "content": "You are a smart task assistant. Based on these tasks: $taskData\nGive 3 useful suggestions."
            }
          ]
        }),
      );
      if (mounted) {
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

        
          final aiText = data['choices']?[0]?['message']?['content'] ?? "No suggestions.";

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

  void _toggleTaskCompletion(Task task) async {
    setState(() {
      task.isCompleted = !task.isCompleted;
    });
    await _saveData();
    _fetchAISuggestions(_allTasks);
  }

  void _deleteTask(Task task) async {
    setState(() {
      _allTasks.removeWhere((t) => t.id == task.id);
    });
    await _saveData();
    _fetchAISuggestions(_allTasks);
  }

  void _showAddTaskDialog() {
    showAddTaskBottomSheet(
      context,
      _allProjects,
      (Task newTask) async {
        newTask.orderIndex = _allTasks.length;
        setState(() {
          _allTasks.add(newTask);
        });
        await _saveData();
        _fetchAISuggestions(_allTasks);
      },
      (Project newProject) async {
        setState(() {
          _allProjects.add(newProject);
        });
        await _saveData();
      },
    );
  }

  void _showAICalendar(List<Task> allTasks) {
    showPremiumAICalendar(context, allTasks);
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case "P1":
        return Colors.red;
      case "P2":
        return Colors.orange;
      case "P3":
        return Colors.blue;
      case "P4":
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

    filteredTasks.sort((a, b) {
      switch (_sortBy) {
        case 'Priority':
          return a.priority.compareTo(b.priority); // P1 < P2 < P3 < P4
        case 'Title':
          return a.title.compareTo(b.title);
        case 'Custom':
          return a.orderIndex.compareTo(b.orderIndex);
        case 'DueDate':
        default:
          return a.dueDate.compareTo(b.dueDate);
      }
    });
    return filteredTasks;
  }

  Widget _buildActiveTasks(List<Task> activeTasks, bool isWide) {
    if (_sortBy != 'Custom') {
      return Column(
        children: activeTasks.map((task) => _buildTaskTile(task, isWide: isWide)).toList(),
      );
    }
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      onReorder: (oldIndex, newIndex) async {
        if (newIndex > oldIndex) newIndex -= 1;
        final Task item = activeTasks.removeAt(oldIndex);
        activeTasks.insert(newIndex, item);
        
        for (int i = 0; i < activeTasks.length; i++) {
          activeTasks[i].orderIndex = i;
        }
        
        setState(() {});
        await _saveData();
      },
      children: activeTasks.map((task) {
        return Container(
          key: ValueKey(task.id),
          child: _buildTaskTile(task, isWide: isWide),
        );
      }).toList(),
    );
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
      backgroundColor: const Color(0xFFF4F7FC), // premium light gray/blue
      extendBody: true,
      appBar: PremiumTopBar(
        title: "My Tasks",
        onCalendarPressed: () => _showAICalendar(_allTasks),
      ),
      bottomNavigationBar: PremiumBottomBar(
        onAddPressed: _showAddTaskDialog,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.only(
            left: horizontalPadding,
            right: horizontalPadding,
            top: 16,
            bottom: 120, // Padding for floating bottom bar
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Premium AI Suggestions Card
              AiInsightsCard(isLoading: _isLoadingAI, suggestions: _aiSuggestions),
              const SizedBox(height: 24),


              // Sleek Sorting Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['DueDate', 'Priority', 'Title', 'Custom'].map((sortOption) {
                    final isSelected = _sortBy == sortOption;
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: ChoiceChip(
                        label: Text(sortOption),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) setState(() => _sortBy = sortOption);
                        },
                        selectedColor: Colors.black87,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: isSelected ? Colors.transparent : Colors.grey.shade300,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),

              // Task List
              if (activeTasks.isEmpty && completedTasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: Text(
                      "Your day looks clear.\nTap the + to add a task!",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16,
                          color: Colors.black45,
                          fontWeight: FontWeight.w500,
                          height: 1.5),
                    ),
                  ),
                )
              else ...[
                _buildActiveTasks(activeTasks, isWide),
                if (completedTasks.isNotEmpty)
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded: true,
                      tilePadding: EdgeInsets.zero,
                      title: const Text(
                        "Completed",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.black45,
                          fontSize: 18,
                        ),
                      ),
                      children: completedTasks.map((task) => _buildTaskTile(task, isWide: isWide)).toList(),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskTile(Task task, {required bool isWide}) {
    int completedSubtasks = task.subtasks.where((s) => s.isCompleted).length;
    int totalSubtasks = task.subtasks.length;
    double progress = totalSubtasks == 0 ? 0 : completedSubtasks / totalSubtasks;

    String? projectName;
    if (task.projectId != null) {
      final project = _allProjects.firstWhere(
        (p) => p.id == task.projectId,
        orElse: () => Project(id: '', name: ''),
      );
      if (project.id.isNotEmpty) projectName = project.name;
    }

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
                if (totalSubtasks > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(task.isCompleted ? Colors.grey : Colors.blueAccent),
                          borderRadius: BorderRadius.circular(4),
                          minHeight: 6,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "$completedSubtasks/$totalSubtasks",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: task.isCompleted ? Colors.grey : Colors.blueAccent,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
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
                    if (projectName != null)
                      Chip(
                        label: Text(projectName),
                        backgroundColor: Colors.purple.withOpacity(0.1),
                        labelStyle: TextStyle(
                            color: Colors.purple, fontWeight: FontWeight.bold, fontSize: isWide ? 15 : 13),
                      ),
                    ...task.tags.map((tag) => Chip(
                          label: Text(tag),
                          backgroundColor: Colors.grey.withOpacity(0.15),
                          labelStyle: TextStyle(
                              color: Colors.grey.shade800, fontWeight: FontWeight.w600, fontSize: isWide ? 15 : 13),
                        )),
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
          "https://api.groq.com/openai/v1/chat/completions",
        ),
        headers: {
          "Authorization": "Bearer ${dotenv.env['GROQ_API_KEY']}",
          "Content-Type": "application/json"
        },
        body: jsonEncode({
          "model": "gpt-oss-20b",
          "messages": [
            {"role": "user", "content": intro}
          ]
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);

        final text = data['choices']?[0]?['message']?['content'] ?? "No plan generated.";

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
      "role": "system",
      "content": "You are an expert productivity and project coach. Help with step-by-step, practical advice. Keep answers concise with checklists when useful.\n\n"
                 "Task Context:\nTitle: ${task.title}\nDue: ${DateFormat.yMMMd().format(task.dueDate)}\nPriority: ${task.priority}\nCategory: ${task.category}"
    });

    for (final msg in _messages) {
      contents.add({
        "role": msg["role"] == "model" ? "assistant" : "user",
        "content": msg["text"],
      });
    }

    try {
      final res = await http.post(
        Uri.parse(
          "https://api.groq.com/openai/v1/chat/completions",
        ),
        headers: {
          "Authorization": "Bearer ${dotenv.env['GROQ_API_KEY']}",
          "Content-Type": "application/json"
        },
        body: jsonEncode({
          "model": "gpt-oss-20b",
          "messages": contents
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);

        final text = data['choices']?[0]?['message']?['content'] ?? "…";

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
