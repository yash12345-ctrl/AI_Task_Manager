import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../task.dart';
import '../services/api/groq_api_manager.dart';
class TaskAnalysisPage extends StatefulWidget {
  final Task task;
  const TaskAnalysisPage({super.key, required this.task});

  @override
  State<TaskAnalysisPage> createState() => _TaskAnalysisPageState();
}

class _TaskAnalysisPageState extends State<TaskAnalysisPage> {
  bool _loadingPlan = true;
  String _planText = '';

  @override
  void initState() {
    super.initState();
    _fetchQuickPlan();
  }

  Future<void> _fetchQuickPlan({bool forceRefresh = false}) async {
    setState(() {
      _loadingPlan = true;
      if (forceRefresh) _planText = '';
    });

    final task = widget.task;
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'ai_plan_${task.id}';

    if (!forceRefresh) {
      final cachedPlan = prefs.getString(cacheKey);
      if (cachedPlan != null && cachedPlan.isNotEmpty) {
        setState(() {
          _planText = cachedPlan;
          _loadingPlan = false;
        });
        return;
      }
    }
    final intro =
        "You are an expert task coach. Create a concise, actionable plan using markdown with steps, estimates, checkpoints, risks, and tools for this single task.\n"
        "IMPORTANT: Do NOT use markdown tables, as they do not render well on mobile. Use bulleted lists instead.\n"
        "Task Details:\n"
        "- Title: ${task.title}\n"
        "- Due: ${DateFormat.yMMMd().format(task.dueDate)}\n"
        "- Priority: ${task.priority}\n"
        "- Category: ${task.category}\n";

    try {
      final text = await GroqApiManager().generateAIResponse(intro);

      if (text != null && text.isNotEmpty) {
        if (text == "LIMIT_REACHED" || text == "ALL_KEYS_EXHAUSTED") {
          setState(() {
            _planText = "🧠 AI Limit Reached for today. Don't worry, you can still manage your tasks manually!";
          });
        } else if (text.startsWith("⚠️")) {
          setState(() {
            _planText = text;
          });
        } else {
          final trimmedText = text.toString().trim();
          await prefs.setString(cacheKey, trimmedText);
          setState(() {
            _planText = trimmedText;
          });
        }
      } else {
        setState(() {
          _planText = "⚠️ Failed to generate plan.";
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

  Widget _styledCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.06), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 24,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isWide = media.size.width > 650;
    final horizontalPadding = isWide ? 40.0 : 16.0;

    final task = widget.task;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "AI Task Analysis",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 8),
                child: _styledCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: TextStyle(
                          fontSize: isWide ? 22 : 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: isWide ? 12 : 8,
                        runSpacing: 8,
                        children: [
                          _pill(Icons.event, "Due: ${DateFormat.yMMMd().format(task.dueDate)}", isWide),
                          _pill(Icons.flag, "Priority: ${task.priority}", isWide),
                          _pill(Icons.category, "Category: ${task.category}", isWide),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 8),
                  children: [
                    _styledCard(
                      child: _loadingPlan
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: CircularProgressIndicator(color: Colors.blue),
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      "Quick Plan 🗺️",
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      onPressed: () => _fetchQuickPlan(forceRefresh: true),
                                      icon: const Icon(Icons.refresh, size: 22, color: Colors.black87),
                                      tooltip: "Regenerate",
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                MarkdownBody(
                                  data: _planText,
                                  selectable: true,
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
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
        border: Border.all(color: Colors.blue.withOpacity(0.15)),
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
              fontWeight: FontWeight.w700,
              fontSize: isWide ? 14 : 12,
            ),
          ),
        ],
      ),
    );
  }
}
