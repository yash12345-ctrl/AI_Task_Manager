import 'dart:typed_data';
import 'package:alarm/alarm.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/task_model.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('ic_notification');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const LinuxInitializationSettings linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open notification',
    );
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings, 
      iOS: iosSettings,
      linux: linuxSettings,
    );

    await _notificationsPlugin.initialize(settings: initSettings);

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> scheduleTaskReminder(Task task) async {
    if (!task.hasTime || task.isCompleted) return;

    final DateTime scheduledDate = task.dueDate.subtract(Duration(minutes: task.reminderMinutes));

    if (scheduledDate.isBefore(DateTime.now())) return;

    final alarmSettings = AlarmSettings(
      id: task.id.hashCode.abs(), // IDs must be positive integers
      dateTime: scheduledDate,
      assetAudioPath: 'assets/alarm.mp3',
      loopAudio: true,
      vibrate: true,
      volumeSettings: const VolumeSettings.fixed(volume: 0.8),
      notificationSettings: NotificationSettings(
        title: 'Upcoming Task: ${task.title}',
        body: task.reminderMinutes > 0 
            ? 'Due in ${task.reminderMinutes} minutes!' 
            : 'Due now!',
        stopButton: 'Stop',
      ),
    );

    await Alarm.set(alarmSettings: alarmSettings);
  }

  Future<void> cancelReminder(String taskId) async {
    await Alarm.stop(taskId.hashCode.abs());
  }
}
