import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../task.dart';

void showAddTaskBottomSheet(
  BuildContext context,
  List<Project> allProjects,
  Function(Task newTask) onTaskAdded,
  Function(Project newProject) onProjectAdded,
) {
  String title = '';
  DateTime dueDate = DateTime.now();
  TimeOfDay? dueTime;
  DateTime? startDate;
  Recurrence recurrence = Recurrence.none;
  int reminderMinutes = 0;
  String priority = 'P2';
  String category = 'Work';
  String? selectedProjectId;
  List<String> tags = [];
  List<Subtask> subtasks = [];
  final tagController = TextEditingController();
  final subtaskController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  final uuid = const Uuid();

  Future<void> showAddProjectDialog(BuildContext ctx, Function(void Function()) setModalState) async {
    String newProjectName = '';
    return showDialog(
      context: ctx,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("New Project", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
          content: TextField(
            decoration: InputDecoration(
              labelText: "Project Name",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.folder, color: Colors.purple),
            ),
            onChanged: (val) => newProjectName = val,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                if (newProjectName.trim().isNotEmpty) {
                  final newProject = Project(
                    id: uuid.v4(),
                    name: newProjectName.trim(),
                  );
                  onProjectAdded(newProject);
                  setModalState(() {});
                  Navigator.pop(dialogCtx);
                }
              },
              child: const Text("Add", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  final bool isWide = MediaQuery.of(context).size.width > 650;
  
  Widget buildContent(BuildContext context, StateSetter setModalState, ScrollController controller) {
    return LayoutBuilder(builder: (context, constraints) {
      return Container(
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
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            height: 5,
                            width: 40,
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: Colors.grey,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const Center(
                          child: Text(
                            "Add New Task",
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue),
                          ),
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
                          onSaved: (val) => title = val!,
                        ),
                        const SizedBox(height: 15),
                        Row(
                          children: [
                            Expanded(
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text("Due Date"),
                                subtitle: Text(DateFormat.yMMMd().format(dueDate)),
                                trailing: const Icon(Icons.calendar_today, color: Colors.blue, size: 20),
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: dueDate,
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null && picked != dueDate) {
                                    setModalState(() {
                                      dueDate = picked;
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text("Time"),
                                subtitle: Text(dueTime?.format(context) ?? "Set time"),
                                trailing: const Icon(Icons.access_time, color: Colors.blue, size: 20),
                                onTap: () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: dueTime ?? TimeOfDay.now(),
                                  );
                                  if (picked != null) {
                                    setModalState(() {
                                      dueTime = picked;
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text("Start Date (Optional)"),
                          subtitle: Text(startDate != null ? DateFormat.yMMMd().format(startDate!) : "For timeline view"),
                          trailing: const Icon(Icons.start, color: Colors.blue, size: 20),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: startDate ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setModalState(() {
                                startDate = picked;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<Recurrence>(
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Recurrence',
                            prefixIcon: const Icon(Icons.repeat, color: Colors.blue),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          value: recurrence,
                          items: const [
                            DropdownMenuItem(value: Recurrence.none, child: Text("None")),
                            DropdownMenuItem(value: Recurrence.daily, child: Text("Daily")),
                            DropdownMenuItem(value: Recurrence.weekdays, child: Text("Weekdays")),
                            DropdownMenuItem(value: Recurrence.weekly, child: Text("Weekly")),
                            DropdownMenuItem(value: Recurrence.monthly, child: Text("Monthly")),
                          ],
                          onChanged: (val) {
                            if (val != null) setModalState(() => recurrence = val);
                          },
                        ),
                        const SizedBox(height: 15),
                        DropdownButtonFormField<int>(
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Reminder',
                            prefixIcon: const Icon(Icons.notifications, color: Colors.blue),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          value: reminderMinutes,
                          items: const [
                            DropdownMenuItem(value: 0, child: Text("No reminder")),
                            DropdownMenuItem(value: 10, child: Text("10 minutes before")),
                            DropdownMenuItem(value: 30, child: Text("30 minutes before")),
                            DropdownMenuItem(value: 60, child: Text("1 hour before")),
                            DropdownMenuItem(value: 1440, child: Text("1 day before")),
                          ],
                          onChanged: (val) {
                            if (val != null) setModalState(() => reminderMinutes = val);
                          },
                        ),
                        const SizedBox(height: 15),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: priority,
                                decoration: InputDecoration(
                                  labelText: "Priority",
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  prefixIcon: const Icon(Icons.flag, color: Colors.orange),
                                ),
                                items: ["P1", "P2", "P3", "P4"]
                                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                    .toList(),
                                onChanged: (val) => setModalState(() => priority = val!),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: category,
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
                                onChanged: (val) => setModalState(() => category = val!),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String?>(
                                isExpanded: true,
                                value: selectedProjectId,
                                decoration: InputDecoration(
                                  labelText: "Project (Optional)",
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  prefixIcon: const Icon(Icons.folder, color: Colors.purple),
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text("No Project"),
                                  ),
                                  ...allProjects.map((p) => DropdownMenuItem<String?>(
                                    value: p.id,
                                    child: Text(p.name),
                                  ))
                                ],
                                onChanged: (val) => setModalState(() => selectedProjectId = val),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_box, color: Colors.purple, size: 30),
                              onPressed: () async {
                                await showAddProjectDialog(context, setModalState);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        TextFormField(
                          controller: tagController,
                          decoration: InputDecoration(
                            labelText: "Add Tag",
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: const Icon(Icons.tag, color: Colors.grey),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.add_circle, color: Colors.blue),
                              onPressed: () {
                                if (tagController.text.trim().isNotEmpty) {
                                  setModalState(() {
                                    tags.add(tagController.text.trim());
                                    tagController.clear();
                                  });
                                }
                              },
                            ),
                          ),
                          onFieldSubmitted: (val) {
                            if (val.trim().isNotEmpty) {
                              setModalState(() {
                                tags.add(val.trim());
                                tagController.clear();
                              });
                            }
                          },
                        ),
                        if (tags.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Wrap(
                              spacing: 6,
                              children: tags.map((tag) => Chip(
                                label: Text(tag),
                                onDeleted: () {
                                  setModalState(() => tags.remove(tag));
                                },
                              )).toList(),
                            ),
                          ),
                        const SizedBox(height: 15),
                        TextFormField(
                          controller: subtaskController,
                          decoration: InputDecoration(
                            labelText: "Add Subtask",
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: const Icon(Icons.checklist, color: Colors.grey),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.add_circle, color: Colors.blue),
                              onPressed: () {
                                if (subtaskController.text.trim().isNotEmpty) {
                                  setModalState(() {
                                    subtasks.add(Subtask(
                                      id: uuid.v4(),
                                      title: subtaskController.text.trim(),
                                    ));
                                    subtaskController.clear();
                                  });
                                }
                              },
                            ),
                          ),
                          onFieldSubmitted: (val) {
                            if (val.trim().isNotEmpty) {
                              setModalState(() {
                                subtasks.add(Subtask(
                                  id: uuid.v4(),
                                  title: val.trim(),
                                ));
                                subtaskController.clear();
                              });
                            }
                          },
                        ),
                        if (subtasks.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              children: subtasks.map((st) => ListTile(
                                dense: true,
                                leading: const Icon(Icons.subdirectory_arrow_right),
                                title: Text(st.title),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () {
                                    setModalState(() => subtasks.remove(st));
                                  },
                                ),
                              )).toList(),
                            ),
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
                            onPressed: () {
                              if (formKey.currentState!.validate()) {
                                formKey.currentState!.save();
                                final newTask = Task(
                                  id: uuid.v4(),
                                  title: title,
                                  dueDate: dueTime != null 
                                      ? DateTime(dueDate.year, dueDate.month, dueDate.day, dueTime!.hour, dueTime!.minute)
                                      : dueDate,
                                  priority: priority,
                                  category: category,
                                  isCompleted: false,
                                  projectId: selectedProjectId,
                                  tags: tags.toList(),
                                  subtasks: subtasks.toList(),
                                  orderIndex: 0,
                                  hasTime: dueTime != null,
                                  recurrence: recurrence,
                                  reminderMinutes: reminderMinutes,
                                );
                                onTaskAdded(newTask);
                                Navigator.pop(context);
                              }
                            },
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
              );
    });
  }

  if (isWide) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
          child: StatefulBuilder(
            builder: (context, setModalState) => ClipRRect(
              borderRadius: BorderRadius.circular(25),
              child: buildContent(context, setModalState, ScrollController()),
            )
          ),
        ),
      ),
    );
  } else {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.9,
            maxChildSize: 0.95,
            minChildSize: 0.6,
            builder: (_, controller) => buildContent(context, setModalState, controller),
          );
        });
      },
    );
  }
}
