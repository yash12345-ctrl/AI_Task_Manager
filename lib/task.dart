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
import "ai_task_analysis/task_analysis_page.dart";
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'models/task_model.dart';
import 'services/export_service.dart';
import 'scheduling/notification_service.dart';
import 'scheduling/recurrence_manager.dart';
export 'models/task_model.dart';


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
  String _currentView = 'All'; 
  String _viewMode = 'List'; // List, Kanban, Calendar, Timeline
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  String _searchQuery = '';
  String? _filterPriority;
  String? _filterCategory;


  bool _isLoadingAI = false;
  List<String> _aiSuggestions = [];


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
    final pendingTasks = tasks.where((t) => !t.isCompleted).toList();
    
    if (pendingTasks.isEmpty) {
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
      final prefs = await SharedPreferences.getInstance();
      List<Task> tasksToFetch = [];
      List<String> currentSuggestions = [];
      
      // Load cached suggestions
      for (final task in pendingTasks) {
        final cached = prefs.getString('ai_insight_${task.id}');
        if (cached != null && cached.isNotEmpty) {
          currentSuggestions.add(cached);
        } else {
          tasksToFetch.add(task);
        }
      }

      // Fetch only for tasks missing a cached suggestion
      if (tasksToFetch.isNotEmpty) {
        final taskData = tasksToFetch
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
            "model": "openai/gpt-oss-20b",
            "messages": [
              {
                "role": "user",
                "content": "You are a smart task assistant. I have ${taskData.length} pending tasks: $taskData\nFor EACH task, provide exactly 1 short, actionable suggestion. Format your response as exactly ${taskData.length} lines of plain text. Do not include numbers, bullet points, or any introductory/concluding remarks."
              }
            ]
          }),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final aiText = data['choices']?[0]?['message']?['content'] ?? "";

          final newSuggestions = (aiText as String)
              .split("\n")
              .map((s) => s.replaceAll(RegExp(r'^[\d\.\-\*]+\s*'), '').trim())
              .where((s) => s.isNotEmpty)
              .take(tasksToFetch.length)
              .toList();

          // Save fetched suggestions to cache
          for (int i = 0; i < newSuggestions.length; i++) {
            final task = tasksToFetch[i];
            final suggestion = newSuggestions[i];
            await prefs.setString('ai_insight_${task.id}', suggestion);
          }

          // Rebuild final list in order
          currentSuggestions = [];
          for (final task in pendingTasks) {
            final cached = prefs.getString('ai_insight_${task.id}');
            if (cached != null && cached.isNotEmpty) {
              currentSuggestions.add(cached);
            }
          }
        } else {
          if (currentSuggestions.isEmpty) {
            currentSuggestions = ["⚠️ Failed to fetch AI suggestions. (${response.statusCode})"];
          }
        }
      }

      if (mounted) {
        setState(() {
          _aiSuggestions = currentSuggestions.isEmpty ? ["No suggestions."] : currentSuggestions;
        });
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
      if (task.isCompleted) {
        final nextTask = RecurrenceManager.spawnNextTask(task);
        if (nextTask != null) {
          _allTasks.add(nextTask);
          NotificationService().scheduleTaskReminder(nextTask);
        }
      }
    });
    final prefs = await SharedPreferences.getInstance();
    if (task.isCompleted) {
      await prefs.remove('ai_insight_${task.id}');
      await prefs.remove('ai_plan_${task.id}');
    }
    await _saveData();
    _fetchAISuggestions(_allTasks);
  }

  void _snoozeTask(Task task) async {
    setState(() {
      task.dueDate = task.dueDate.add(const Duration(days: 1));
    });
    await _saveData();
    NotificationService().scheduleTaskReminder(task);
    _fetchAISuggestions(_allTasks);
  }

  void _deleteTask(Task task) async {
    setState(() {
      _allTasks.removeWhere((t) => t.id == task.id);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ai_insight_${task.id}');
    await prefs.remove('ai_plan_${task.id}');
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

  List<Task> _getProcessedTasks(List<Task> allTasks, bool isCompleted) {
    List<Task> filteredTasks = allTasks.where((task) {
      // 1. Basic completion filter (if called for active tasks)
      if (isCompleted && _currentView != 'Completed') return false; 
      if (!isCompleted && task.isCompleted) return false;

      // 2. View Filter
      if (_currentView == 'Today') {
        if (task.isCompleted) return false;
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final taskDate = DateTime(task.dueDate.year, task.dueDate.month, task.dueDate.day);
        if (taskDate.isAfter(today)) return false; 
      } else if (_currentView == 'Upcoming') {
        if (task.isCompleted) return false;
        final now = DateTime.now();
        final tomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
        final nextWeek = tomorrow.add(const Duration(days: 6));
        final taskDate = DateTime(task.dueDate.year, task.dueDate.month, task.dueDate.day);
        if (taskDate.isBefore(tomorrow) || taskDate.isAfter(nextWeek)) return false;
      } else if (_currentView == 'Completed') {
        if (!task.isCompleted) return false;
      }

      // 3. Search & Advanced Filters
      if (_searchQuery.isNotEmpty) {
        if (!task.title.toLowerCase().contains(_searchQuery.toLowerCase()) && 
            !task.category.toLowerCase().contains(_searchQuery.toLowerCase())) {
          return false;
        }
      }
      if (_filterPriority != null && _filterPriority != 'All' && task.priority != _filterPriority) return false;
      if (_filterCategory != null && _filterCategory != 'All' && task.category != _filterCategory) return false;

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

    final mainScaffold = Scaffold(
      backgroundColor: const Color(0xFFF4F7FC), // premium light gray/blue
      extendBody: true,
      appBar: PremiumTopBar(
        title: "My Tasks",
        onCalendarPressed: () => _showAICalendar(_allTasks),
        onSearchPressed: _showSearchAndFilterSheet,
      ),
      bottomNavigationBar: isWide ? null : PremiumBottomBar(
        onAddPressed: _showAddTaskDialog,
        onSettingsPressed: _showSettingsSheet,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: SingleChildScrollView(
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


              // View Selector
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['All', 'Today', 'Upcoming', 'Completed'].map((view) {
                    final isSelected = _currentView == view;
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: ChoiceChip(
                        label: Text(view),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) setState(() => _currentView = view);
                        },
                        selectedColor: Colors.blueAccent,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey.shade300),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),

              // View Mode Selector
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['List', 'Kanban', 'Calendar', 'Timeline'].map((mode) {
                    final isSelected = _viewMode == mode;
                    return Padding(
                      padding: const EdgeInsets.only(right: 10, bottom: 16),
                      child: ChoiceChip(
                        label: Text(mode),
                        selected: isSelected,
                        onSelected: (selected) async {
                          if (selected) {
                            setState(() => _viewMode = mode);
                            final prefs = await SharedPreferences.getInstance();
                            prefs.setString('viewMode', mode);
                          }
                        },
                        selectedColor: Colors.deepPurpleAccent,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey.shade300),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

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
              else if (_viewMode == 'Kanban')
                _buildKanbanView(activeTasks, completedTasks)
              else if (_viewMode == 'Calendar')
                _buildCalendarView(activeTasks, completedTasks)
              else if (_viewMode == 'Timeline')
                _buildTimelineView(activeTasks, completedTasks)
              else ...[
                if (_currentView == 'Completed')
                  Column(children: completedTasks.map((task) => _buildTaskTile(task, isWide: isWide)).toList())
                else
                  _buildActiveTasks(activeTasks, isWide),
              ],
            ],
          ), // Column
        ), // SingleChildScrollView
      ), // ConstrainedBox
    ), // Center
  ), // LayoutBuilder
); // Scaffold

if (isWide) {
  return Scaffold(
    backgroundColor: const Color(0xFFF4F7FC),
    body: Row(
      children: [
        NavigationRail(
          backgroundColor: Colors.white,
          selectedIndex: 0,
          onDestinationSelected: (int index) {
            if (index == 1) _showSettingsSheet();
          },
          labelType: NavigationRailLabelType.all,
          leading: Padding(
            padding: const EdgeInsets.only(bottom: 20.0, top: 20),
            child: FloatingActionButton(
              elevation: 0,
              backgroundColor: Colors.blueAccent,
              onPressed: _showAddTaskDialog,
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
          destinations: const [
            NavigationRailDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard_rounded, color: Colors.blueAccent),
              label: Text('Tasks'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded, color: Colors.blueAccent),
              label: Text('Settings'),
            ),
          ],
        ),
        const VerticalDivider(thickness: 1, width: 1, color: Colors.black12),
        Expanded(child: mainScaffold),
      ],
    ),
  );
}
return mainScaffold;
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
      direction: DismissDirection.horizontal,
      onDismissed: (direction) {
        if (direction == DismissDirection.endToStart) {
          _deleteTask(task);
        } else if (direction == DismissDirection.startToEnd) {
          _snoozeTask(task);
        }
      },
      background: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(18)),
        child: const Align(alignment: Alignment.centerLeft, child: Icon(Icons.snooze, color: Colors.white)),
      ),
      secondaryBackground: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(18)),
        child: const Align(alignment: Alignment.centerRight, child: Icon(Icons.delete, color: Colors.white)),
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
                Builder(
                  builder: (context) {
                    bool isOverdue = !task.isCompleted && task.dueDate.isBefore(DateTime.now());
                    String dueString = task.hasTime 
                        ? DateFormat('MMM d, h:mm a').format(task.dueDate)
                        : DateFormat.yMMMd().format(task.dueDate);
                    if (task.recurrence != Recurrence.none) {
                       dueString += " (Recurring)";
                    }
                    return Text(
                      isOverdue ? "Overdue: $dueString" : "Due: $dueString",
                      style: TextStyle(
                        color: task.isCompleted ? Colors.grey : (isOverdue ? Colors.red.shade700 : Colors.black54),
                        fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
                      ),
                    );
                  }
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

  void _showSearchAndFilterSheet() {
    final bool isWide = MediaQuery.of(context).size.width > 650;
    
    Widget buildContent(BuildContext context, StateSetter setModalState) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Search & Filter", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  TextField(
                    decoration: InputDecoration(
                      hintText: "Search tasks...",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (val) {
                      setModalState(() => _searchQuery = val);
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _filterPriority,
                    decoration: InputDecoration(
                      labelText: "Filter by Priority",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: ["All", "P1", "P2", "P3", "P4"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (val) {
                      setModalState(() => _filterPriority = val == "All" ? null : val);
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _filterCategory,
                    decoration: InputDecoration(
                      labelText: "Filter by Category",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: ["All", "Work", "Personal", "Study"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (val) {
                      setModalState(() => _filterCategory = val == "All" ? null : val);
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        backgroundColor: Colors.blueAccent,
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Done", style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
    }

    if (isWide) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: StatefulBuilder(builder: buildContent),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => StatefulBuilder(builder: buildContent),
      );
    }
  }

  void _showSettingsSheet() {
    final bool isWide = MediaQuery.of(context).size.width > 650;
    final Widget content = Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Settings", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.data_object, color: Colors.blueAccent),
                title: const Text("Export to JSON"),
                subtitle: const Text("Raw data for backups or APIs"),
                onTap: () {
                  Navigator.pop(context);
                  ExportService.exportToJson(_allTasks);
                },
              ),
              ListTile(
                leading: const Icon(Icons.table_chart, color: Colors.green),
                title: const Text("Export to CSV"),
                subtitle: const Text("Spreadsheet compatible format"),
                onTap: () {
                  Navigator.pop(context);
                  ExportService.exportToCsv(_allTasks);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );

    if (isWide) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: ClipRRect(borderRadius: BorderRadius.circular(28), child: content),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => content,
      );
    }
  }

  Widget _buildKanbanView(List<Task> active, List<Task> completed) {
    final all = [...active, ...completed];
    final todo = all.where((t) => t.status == 'Todo').toList();
    final inProgress = all.where((t) => t.status == 'In Progress').toList();
    final done = all.where((t) => t.status == 'Done').toList();

    return LayoutBuilder(builder: (context, constraints) {
      final bool expand = constraints.maxWidth > (320 * 3 + 16 * 2);
      final Widget row = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          expand ? Expanded(child: _buildKanbanColumn('Todo', todo, expand)) : _buildKanbanColumn('Todo', todo, expand),
          expand ? Expanded(child: _buildKanbanColumn('In Progress', inProgress, expand)) : _buildKanbanColumn('In Progress', inProgress, expand),
          expand ? Expanded(child: _buildKanbanColumn('Done', done, expand)) : _buildKanbanColumn('Done', done, expand),
        ],
      );
      if (expand) return row;
      return SingleChildScrollView(scrollDirection: Axis.horizontal, child: row);
    });
  }

  Widget _buildKanbanColumn(String title, List<Task> tasks, bool expanded) {
    return DragTarget<Task>(
      onWillAccept: (data) => true,
      onAccept: (task) {
        if (task.status == title) return;
        setState(() {
          task.status = title;
          if (title == 'Done') {
            task.isCompleted = true;
          } else {
            task.isCompleted = false;
          }
        });
        _saveData();
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          width: expanded ? null : 320,
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: candidateData.isNotEmpty ? Colors.blue.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text("${tasks.length}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    )
                  ],
                ),
              ),
              ...tasks.map((task) => Draggable<Task>(
                data: task,
                feedback: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.transparent,
                  child: SizedBox(
                    width: expanded ? (MediaQuery.of(context).size.width / 3) - 30 : 320,
                    child: _buildTaskTile(task, isWide: false),
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.3,
                  child: _buildTaskTile(task, isWide: false),
                ),
                child: _buildTaskTile(task, isWide: false),
              )),
              const SizedBox(height: 100), // padding for empty state drag target
            ],
          ),
        );
      },
    );
  }

  Widget _buildCalendarView(List<Task> active, List<Task> completed) {
    final allTasks = [...active, ...completed];
    
    Map<DateTime, List<Task>> groupedTasks = {};
    for (var task in allTasks) {
      final date = DateTime(task.dueDate.year, task.dueDate.month, task.dueDate.day);
      if (groupedTasks[date] == null) groupedTasks[date] = [];
      groupedTasks[date]!.add(task);
    }

    final targetDay = _selectedDay ?? _focusedDay;
    final selectedTasks = groupedTasks[DateTime(targetDay.year, targetDay.month, targetDay.day)] ?? [];

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay; 
              });
            },
            eventLoader: (day) => groupedTasks[DateTime(day.year, day.month, day.day)] ?? [],
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              selectedDecoration: const BoxDecoration(
                color: Colors.blueAccent,
                shape: BoxShape.circle,
              ),
              markerDecoration: const BoxDecoration(
                color: Colors.deepPurple,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (selectedTasks.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Text("No tasks for this day.", style: TextStyle(color: Colors.grey)),
          )
        else
          ...selectedTasks.map((task) => _buildTaskTile(task, isWide: false)),
      ],
    );
  }

  String _monthName(int m) => ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m-1];

  Widget _buildTimelineView(List<Task> active, List<Task> completed) {
    final allTasks = [...active, ...completed];
    if (allTasks.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("No tasks available for timeline.")));

    DateTime minDate = allTasks.map((t) => t.startDate ?? t.dueDate).reduce((a, b) => a.isBefore(b) ? a : b);
    DateTime maxDate = allTasks.map((t) => t.dueDate).reduce((a, b) => a.isAfter(b) ? a : b);
    
    minDate = minDate.subtract(const Duration(days: 2));
    maxDate = maxDate.add(const Duration(days: 5));
    final totalDays = maxDate.difference(minDate).inDays;

    final double dayWidth = 60.0;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: List.generate(totalDays, (index) {
                final date = minDate.add(Duration(days: index));
                final isToday = date.year == DateTime.now().year && date.month == DateTime.now().month && date.day == DateTime.now().day;
                return Container(
                  width: dayWidth,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isToday ? Colors.blue.withOpacity(0.1) : Colors.transparent,
                    border: Border(right: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Column(
                    children: [
                      Text("${date.day}", style: TextStyle(fontWeight: FontWeight.bold, color: isToday ? Colors.blue : Colors.black87)),
                      Text(_monthName(date.month), style: TextStyle(fontSize: 10, color: isToday ? Colors.blueAccent : Colors.grey)),
                    ],
                  ),
                );
              }),
            ),
            const Divider(height: 1),
            const SizedBox(height: 16),
            ...allTasks.map((task) {
              final start = task.startDate ?? task.dueDate;
              final end = task.dueDate;
              
              int offsetDays = start.difference(minDate).inDays;
              if (offsetDays < 0) offsetDays = 0;
              
              int durationDays = end.difference(start).inDays + 1;
              if (durationDays < 1) durationDays = 1;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    SizedBox(width: offsetDays * dayWidth),
                    Container(
                      width: durationDays * dayWidth - 8,
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        color: task.isCompleted ? Colors.green.shade400 : Colors.deepPurpleAccent,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                           BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))
                        ]
                      ),
                      child: Text(
                        task.title,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
