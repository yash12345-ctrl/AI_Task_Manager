import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/task_model.dart';

class ExportService {
  static Future<void> exportToJson(List<Task> tasks) async {
    final jsonList = tasks.map((t) => t.toJson()).toList();
    final jsonString = const JsonEncoder.withIndent('  ').convert(jsonList);

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/tasks_export.json');
    await file.writeAsString(jsonString);

    await Share.shareXFiles([XFile(file.path)], subject: 'My Tasks Export (JSON)');
  }

  static Future<void> exportToCsv(List<Task> tasks) async {
    List<List<dynamic>> rows = [];
    
    rows.add([
      'ID', 'Title', 'Due Date', 'Priority', 'Category', 
      'Status', 'Tags', 'Subtasks Count', 'Recurrence'
    ]);

    for (var task in tasks) {
      rows.add([
        task.id,
        task.title,
        task.dueDate.toIso8601String(),
        task.priority,
        task.category,
        task.isCompleted ? 'Completed' : 'Active',
        task.tags.join('; '),
        task.subtasks.length,
        task.recurrence.name,
      ]);
    }

    String csv = const ListToCsvConverter().convert(rows);

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/tasks_export.csv');
    await file.writeAsString(csv);

    await Share.shareXFiles([XFile(file.path)], subject: 'My Tasks Export (CSV)');
  }
}
