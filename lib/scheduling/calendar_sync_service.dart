import 'package:device_calendar/device_calendar.dart' as dc;
import '../models/task_model.dart';
import 'package:timezone/timezone.dart' as tz;

class CalendarSyncService {
  static final CalendarSyncService _instance = CalendarSyncService._internal();
  factory CalendarSyncService() => _instance;
  CalendarSyncService._internal();

  final dc.DeviceCalendarPlugin _deviceCalendarPlugin = dc.DeviceCalendarPlugin();
  
  // A mapping to link our Task ID with Calendar Event ID (for two-way sync updates)
  // In a real app, you would persist this in the local database.
  final Map<String, String> _syncMap = {};

  Future<bool> requestPermissions() async {
    var permissionsGranted = await _deviceCalendarPlugin.hasPermissions();
    if (permissionsGranted.isSuccess && !permissionsGranted.data!) {
      permissionsGranted = await _deviceCalendarPlugin.requestPermissions();
      if (!permissionsGranted.isSuccess || !permissionsGranted.data!) {
        return false;
      }
    }
    return true;
  }

  Future<List<dc.Calendar>> getCalendars() async {
    final hasPermissions = await requestPermissions();
    if (!hasPermissions) return [];

    final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
    if (calendarsResult.isSuccess && calendarsResult.data != null) {
      return calendarsResult.data!.where((c) => !c.isReadOnly!).toList();
    }
    return [];
  }

  /// Pushes a task to the default/selected calendar
  Future<String?> pushTaskToCalendar(Task task, dc.Calendar calendar) async {
    if (!task.hasTime) return null; // We only sync tasks with specific times

    final hasPermissions = await requestPermissions();
    if (!hasPermissions) return null;

    final existingEventId = _syncMap[task.id];
    
    final event = dc.Event(
      calendar.id,
      eventId: existingEventId,
    );

    event.title = task.title;
    event.description = "Task from AI Task Manager\nPriority: ${task.priority}";
    
    // Convert to tz.TZDateTime
    final start = tz.TZDateTime.from(task.startDate ?? task.dueDate, tz.local);
    final end = tz.TZDateTime.from(task.dueDate, tz.local);
    
    // Ensure end is after start, or just give a default duration
    event.start = start;
    event.end = end.isBefore(start) ? start.add(const Duration(hours: 1)) : end;
    
    // Save to calendar
    final result = await _deviceCalendarPlugin.createOrUpdateEvent(event);
    if (result!.isSuccess && result.data != null) {
      _syncMap[task.id] = result.data!;
      return result.data;
    }
    return null;
  }

  /// Pulls events from a calendar and converts them to Tasks
  Future<List<Task>> pullEventsFromCalendar(dc.Calendar calendar, {DateTime? startDate, DateTime? endDate}) async {
    final hasPermissions = await requestPermissions();
    if (!hasPermissions) return [];

    final start = startDate ?? DateTime.now().subtract(const Duration(days: 30));
    final end = endDate ?? DateTime.now().add(const Duration(days: 90));

    final retrieveEventsParams = dc.RetrieveEventsParams(
      startDate: start,
      endDate: end,
    );

    final eventsResult = await _deviceCalendarPlugin.retrieveEvents(calendar.id, retrieveEventsParams);
    
    List<Task> importedTasks = [];

    if (eventsResult.isSuccess && eventsResult.data != null) {
      for (var event in eventsResult.data!) {
        // Find if this event is already a task in our system
        final existingTaskId = _syncMap.entries.where((e) => e.value == event.eventId).map((e) => e.key).firstOrNull;
        
        if (existingTaskId != null) {
          // Event already exists, we might want to update it (omitted for brevity)
          continue;
        }

        // It's a new event from the calendar, let's create a task
        final newTask = Task(
          id: 'cal_${event.eventId ?? DateTime.now().millisecondsSinceEpoch}',
          title: event.title ?? 'New Calendar Event',
          dueDate: event.end ?? DateTime.now().add(const Duration(hours: 1)),
          priority: 'P2',
          category: 'Calendar',
          hasTime: true,
          startDate: event.start,
        );

        _syncMap[newTask.id] = event.eventId!;
        importedTasks.add(newTask);
      }
    }

    return importedTasks;
  }

  /// Synchronize all tasks with a specific calendar
  Future<List<Task>> syncWithCalendar(List<Task> currentTasks, dc.Calendar calendar) async {
    // 1. Push all app tasks to Calendar
    for (var task in currentTasks) {
      if (task.hasTime && !task.isCompleted) {
        await pushTaskToCalendar(task, calendar);
      }
    }

    // 2. Pull all events from Calendar and convert to Tasks
    final importedTasks = await pullEventsFromCalendar(calendar);
    
    return importedTasks; // Return new tasks to add to the app's state
  }
}
