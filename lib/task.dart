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
import 'calendar/calendar_page.dart';
import "ai_task_analysis/task_analysis_page.dart";
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'models/task_model.dart';
import 'services/export_service.dart';
import 'settings/settings_page.dart';
import 'scheduling/notification_service.dart';
import 'scheduling/recurrence_manager.dart';
import 'scheduling/calendar_sync_service.dart';
export 'models/task_model.dart';
import 'services/api/groq_api_manager.dart';
import 'package:in_app_update/in_app_update.dart';


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
  String _userName = 'User';


  bool _isLoadingAI = false;
  List<String> _aiSuggestions = [];


  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadData();
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   _checkForUpdate();
    // });
  }

  Future<void> _checkForUpdate() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        if (info.immediateUpdateAllowed) {
          await InAppUpdate.performImmediateUpdate();
        } else if (info.flexibleUpdateAllowed) {
          await InAppUpdate.startFlexibleUpdate();
          await InAppUpdate.completeFlexibleUpdate();
        }
      }
    } catch (e) {
      print("InAppUpdate Error: $e");
    }
  }

  Future<void> _loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      _userName = prefs.getString('userName') ?? 'User';

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

  void _openCalendarPage({bool showHint = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PremiumCalendarPage(
          tasks: _allTasks,
          onSync: _syncWithCalendar,
          showSyncHint: showHint,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _syncWithCalendar() async {
    final calendars = await CalendarSyncService().getCalendars();
    if (calendars.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No calendars found or permission denied.')),
        );
      }
      return;
    }

    // Let the user choose a calendar (simplification: use the first writable one for now, or show a dialog)
    final selectedCalendar = await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Calendar to Sync'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: calendars.length,
              itemBuilder: (context, index) {
                final calendar = calendars[index];
                return ListTile(
                  title: Text(calendar.name ?? 'Unnamed Calendar'),
                  subtitle: Text(calendar.accountName ?? ''),
                  onTap: () => Navigator.of(context).pop(calendar),
                );
              },
            ),
          ),
        );
      }
    );

    if (selectedCalendar == null) return;

    if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Syncing with calendar...')),
       );
    }

    final importedTasks = await CalendarSyncService().syncWithCalendar(_allTasks, selectedCalendar);

    if (mounted) {
      setState(() {
        for (var importedTask in importedTasks) {
          // If task ID doesn't exist, add it
          if (!_allTasks.any((t) => t.id == importedTask.id)) {
            _allTasks.add(importedTask);
          }
        }
      });
      _saveData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Synced! Imported ${importedTasks.length} events.')),
      );
    }
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

        final aiText = await GroqApiManager().fetchAISuggestions(taskData);
        
        if (aiText != null && aiText.isNotEmpty) {
          if (aiText == "LIMIT_REACHED" || aiText == "ALL_KEYS_EXHAUSTED") {
             if (currentSuggestions.isEmpty) {
               currentSuggestions = ["🧠 AI Limit Reached for today. Don't worry, you can still manage your tasks manually!"];
             }
          } else if (aiText.startsWith("⚠️")) {
             if (currentSuggestions.isEmpty) {
               currentSuggestions = ["The AI is currently on a coffee break. You're on your own, good luck! ☕"];
             }
          } else {
            final newSuggestions = aiText
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
          }
        } else {
          if (currentSuggestions.isEmpty) {
            currentSuggestions = ["⚠️ Failed to fetch AI suggestions."];
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

  List<Task> _getProcessedTasks(List<Task> allTasks, bool isCompletedList) {
    List<Task> filteredTasks = allTasks.where((task) {
      // 1. Basic completion split
      if (isCompletedList && !task.isCompleted) return false;
      if (!isCompletedList && task.isCompleted) return false;

      // 2. View Filter
      if (_currentView == 'Today') {
        if (isCompletedList) return false;
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final taskDate = DateTime(task.dueDate.year, task.dueDate.month, task.dueDate.day);
        if (taskDate.isAfter(today)) return false; 
      } else if (_currentView == 'Upcoming') {
        if (isCompletedList) return false;
        final now = DateTime.now();
        final tomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
        final nextWeek = tomorrow.add(const Duration(days: 6));
        final taskDate = DateTime(task.dueDate.year, task.dueDate.month, task.dueDate.day);
        if (taskDate.isBefore(tomorrow) || taskDate.isAfter(nextWeek)) return false;
      } else if (_currentView == 'Completed') {
        if (!isCompletedList) return false;
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
        userName: _userName,
        onSearchPressed: _showSearchAndFilterSheet,
        onSyncPressed: _openCalendarPage,
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


              // Modern Filter & View Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: ['All', 'Today', 'Upcoming', 'Completed'].map((view) {
                          final isSelected = _currentView == view;
                          return GestureDetector(
                            onTap: () => setState(() => _currentView = view),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(right: 12),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.black87 : Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: isSelected
                                    ? [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))]
                                    : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))],
                              ),
                              child: Text(
                                view,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.black87,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Filter & Sort Button
                  GestureDetector(
                    onTap: _showViewOptionsSheet,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: const Icon(Icons.tune_rounded, color: Colors.black87, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

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

              else if (_viewMode == 'Calendar')
                _buildCalendarView(activeTasks, completedTasks)
              else if (_viewMode == 'Timeline')
                _buildTimelineView(activeTasks, completedTasks)
              else ...[
                if (_currentView == 'Completed')
                  Column(children: completedTasks.map((task) => _buildTaskTile(task, isWide: isWide)).toList())
                else if (_currentView == 'All')
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildActiveTasks(activeTasks, isWide),
                      if (completedTasks.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Padding(
                          padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                          child: Text("COMPLETED", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                        ),
                        Column(children: completedTasks.map((task) => _buildTaskTile(task, isWide: isWide)).toList()),
                      ]
                    ]
                  )
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

  void _showViewOptionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text("View Options", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 24),
                  const Text("LAYOUT", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black45, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: ['List', 'Calendar', 'Timeline'].map((mode) {
                      final isSelected = _viewMode == mode;
                      return ChoiceChip(
                        label: Text(mode),
                        selected: isSelected,
                        onSelected: (selected) async {
                          if (selected) {
                            setSheetState(() => _viewMode = mode);
                            setState(() => _viewMode = mode);
                            final prefs = await SharedPreferences.getInstance();
                            prefs.setString('viewMode', mode);
                          }
                        },
                        selectedColor: Colors.black87,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey.shade300),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  const Text("SORT BY", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black45, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: ['DueDate', 'Priority', 'Title', 'Custom'].map((sortOption) {
                      final isSelected = _sortBy == sortOption;
                      return ChoiceChip(
                        label: Text(sortOption),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setSheetState(() => _sortBy = sortOption);
                            setState(() => _sortBy = sortOption);
                          }
                        },
                        selectedColor: Colors.black87,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey.shade300),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Apply", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          }
        );
      },
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
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          _snoozeTask(task);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task snoozed for 1 day')));
          }
          return false; // Slide back instead of removing from tree
        }
        return true;
      },
      onDismissed: (direction) {
        if (direction == DismissDirection.endToStart) {
          _deleteTask(task);
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          tasks: _allTasks,
          userName: _userName,
          onNameChanged: (newName) async {
            setState(() {
              _userName = newName;
            });
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('userName', newName);
          },
          onOpenCalendar: () {
            // Close Settings page first
            Navigator.pop(context);
            // Open Calendar page with hint
            _openCalendarPage(showHint: true);
          },
        ),
      ),
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
