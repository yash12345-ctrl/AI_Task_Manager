import 'package:flutter/material.dart';

enum Recurrence { none, daily, weekly, monthly, weekdays }

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
  DateTime dueDate;
  final String priority;
  final String category;
  bool isCompleted;
  String status;
  DateTime? startDate;
  List<String> dependencies;
  
  String? projectId;
  List<String> tags;
  List<Subtask> subtasks;
  int orderIndex;

  // New Scheduling properties
  final bool hasTime;
  final Recurrence recurrence;
  final int reminderMinutes;

  Task({
    required this.id,
    required this.title,
    required this.dueDate,
    required this.priority,
    required this.category,
    this.isCompleted = false,
    this.status = 'Todo',
    this.startDate,
    this.dependencies = const [],
    this.projectId,
    this.tags = const [],
    this.subtasks = const [],
    this.orderIndex = 0,
    this.hasTime = false,
    this.recurrence = Recurrence.none,
    this.reminderMinutes = 0,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      dueDate: DateTime.parse(json['dueDate'] as String),
      priority: _mapOldPriority(json['priority'] as String? ?? 'Medium'),
      category: json['category'] as String? ?? 'Work',
      isCompleted: json['isCompleted'] as bool? ?? false,
      status: json['status'] as String? ?? 'Todo',
      startDate: json['startDate'] != null ? DateTime.parse(json['startDate'] as String) : null,
      dependencies: (json['dependencies'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      projectId: json['projectId'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      subtasks: (json['subtasks'] as List<dynamic>?)?.map((e) => Subtask.fromJson(e)).toList() ?? [],
      orderIndex: json['orderIndex'] as int? ?? 0,
      hasTime: json['hasTime'] as bool? ?? false,
      recurrence: Recurrence.values.firstWhere(
        (e) => e.name == (json['recurrence'] as String? ?? 'none'),
        orElse: () => Recurrence.none,
      ),
      reminderMinutes: json['reminderMinutes'] as int? ?? 0,
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
      'status': status,
      'startDate': startDate?.toIso8601String(),
      'dependencies': dependencies,
      'projectId': projectId,
      'tags': tags,
      'subtasks': subtasks.map((e) => e.toJson()).toList(),
      'orderIndex': orderIndex,
      'hasTime': hasTime,
      'recurrence': recurrence.name,
      'reminderMinutes': reminderMinutes,
    };
  }
}
