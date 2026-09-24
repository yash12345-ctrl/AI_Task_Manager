import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/task_model.dart';

class ExportService {
  static Future<void> exportToJson(List<Task> tasks) async {
    final jsonList = tasks.map((t) => t.toJson()).toList();
    final jsonString = const JsonEncoder.withIndent('  ').convert(jsonList);

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/tasks_export.json');
    await file.writeAsString(jsonString);

    await OpenFilex.open(file.path);
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

    await OpenFilex.open(file.path);
  }

  static Future<void> exportToPdf(List<Task> tasks) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Header(level: 0, child: pw.Text("Task Export")),
            pw.TableHelper.fromTextArray(
              context: context,
              data: <List<String>>[
                <String>['Title', 'Due Date', 'Priority', 'Status'],
              ]..addAll(tasks.map((t) => [
                t.title,
                t.dueDate.toIso8601String().split('T')[0],
                t.priority,
                t.isCompleted ? 'Done' : 'Active'
              ])),
            ),
          ];
        },
      ),
    );

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/tasks_export.pdf');
    await file.writeAsBytes(await pdf.save());

    await OpenFilex.open(file.path);
  }
}
