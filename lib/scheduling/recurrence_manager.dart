import '../models/task_model.dart';
import 'package:uuid/uuid.dart';

class RecurrenceManager {
  static Task? spawnNextTask(Task completedTask) {
    if (completedTask.recurrence == Recurrence.none) return null;

    DateTime nextDate = completedTask.dueDate;
    
    switch (completedTask.recurrence) {
      case Recurrence.daily:
        nextDate = nextDate.add(const Duration(days: 1));
        break;
      case Recurrence.weekly:
        nextDate = nextDate.add(const Duration(days: 7));
        break;
      case Recurrence.monthly:
        nextDate = DateTime(nextDate.year, nextDate.month + 1, nextDate.day, nextDate.hour, nextDate.minute);
        break;
      case Recurrence.weekdays:
        do {
          nextDate = nextDate.add(const Duration(days: 1));
        } while (nextDate.weekday == DateTime.saturday || nextDate.weekday == DateTime.sunday);
        break;
      case Recurrence.none:
        return null;
    }

    return Task(
      id: const Uuid().v4(),
      title: completedTask.title,
      dueDate: nextDate,
      priority: completedTask.priority,
      category: completedTask.category,
      projectId: completedTask.projectId,
      tags: List.from(completedTask.tags),
      subtasks: completedTask.subtasks.map((s) => Subtask(id: const Uuid().v4(), title: s.title)).toList(),
      orderIndex: completedTask.orderIndex,
      hasTime: completedTask.hasTime,
      recurrence: completedTask.recurrence,
      reminderMinutes: completedTask.reminderMinutes,
    );
  }
}
