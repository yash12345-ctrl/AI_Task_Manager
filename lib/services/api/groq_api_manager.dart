import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GroqApiManager {
  // Singleton instance
  static final GroqApiManager _instance = GroqApiManager._internal();
  factory GroqApiManager() => _instance;
  GroqApiManager._internal();

  // Maintain our API Keys and current index
  List<String> _apiKeys = [];
  int _currentKeyIndex = 0;

  // Remote config limit simulation. In a real scenario, you could fetch this from Firebase.
  // For now, it's a constant we can easily adjust.
  final int defaultDailyAiLimit = 10; 

  // Initialize keys from .env
  void initialize() {
    final key1 = dotenv.env['GROQ_API_KEY_1'];
    final key2 = dotenv.env['GROQ_API_KEY_2'];
    final key3 = dotenv.env['GROQ_API_KEY_3'];
    final key4 = dotenv.env['GROQ_API_KEY_4'];

    if (key1 != null && key1.isNotEmpty) _apiKeys.add(key1);
    if (key2 != null && key2.isNotEmpty) _apiKeys.add(key2);
    if (key3 != null && key3.isNotEmpty) _apiKeys.add(key3);
    if (key4 != null && key4.isNotEmpty) _apiKeys.add(key4);

    if (_apiKeys.isEmpty) {
      print("WARNING: No Groq API keys found in .env");
    }
  }

  /// Check if the user has reached their daily limit
  Future<bool> _hasReachedDailyLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0]; // YYYY-MM-DD
    
    final storedDate = prefs.getString('ai_usage_date');
    int usageCount = prefs.getInt('ai_usage_count') ?? 0;

    if (storedDate != today) {
      // It's a new day! Reset the counter.
      await prefs.setString('ai_usage_date', today);
      await prefs.setInt('ai_usage_count', 0);
      return false;
    }

    return usageCount >= defaultDailyAiLimit;
  }

  /// Increment the daily usage counter
  Future<void> _incrementUsage() async {
    final prefs = await SharedPreferences.getInstance();
    int usageCount = prefs.getInt('ai_usage_count') ?? 0;
    await prefs.setInt('ai_usage_count', usageCount + 1);
  }

  /// Makes a request to Groq, rotating keys on 429
  Future<String?> fetchAISuggestions(List<Map<String, dynamic>> taskData) async {
    if (await _hasReachedDailyLimit()) {
      return "LIMIT_REACHED";
    }

    if (_apiKeys.isEmpty) {
      return "⚠️ Error: No API keys configured.";
    }

    // Try up to the number of keys we have (to avoid infinite loops if ALL are exhausted)
    for (int attempts = 0; attempts < _apiKeys.length; attempts++) {
      final currentKey = _apiKeys[_currentKeyIndex];
      
      try {
        final taskJson = jsonEncode(taskData);
        final response = await http.post(
          Uri.parse("https://api.groq.com/openai/v1/chat/completions"),
          headers: {
            "Authorization": "Bearer $currentKey",
            "Content-Type": "application/json",
          },
          body: jsonEncode({
            "model": "openai/gpt-oss-20b", // Updated Groq model name
            "messages": [
              {
                "role": "system",
                "content": "You are a smart, concise task assistant."
              },
              {
                "role": "user",
                "content": "I have ${taskData.length} pending tasks: $taskJson\nFor EACH task, provide exactly 1 short, actionable suggestion. Format your response as exactly ${taskData.length} lines of plain text. Do not include numbers, bullet points, or any introductory/concluding remarks."
              }
            ]
          }),
        );

        if (response.statusCode == 200) {
          // Success!
          await _incrementUsage(); // Only count successful requests towards user limit
          final data = jsonDecode(response.body);
          return data['choices']?[0]?['message']?['content'] ?? "";
        } 
        else if (response.statusCode == 429) {
          // Rate Limit Hit! Rotate the key and try again in the next loop iteration
          print("Key $_currentKeyIndex hit 429 Limit. Rotating...");
          _currentKeyIndex = (_currentKeyIndex + 1) % _apiKeys.length;
          continue; // Loop again with the next key
        } 
        else {
          // Other API error (e.g., 400 Bad Request, 500 Server Error)
          print("Groq API Error: ${response.statusCode} - ${response.body}");
          return "⚠️ API Error: ${response.statusCode}";
        }
      } catch (e) {
        print("Exception during Groq API call: $e");
        return "⚠️ Network Error";
      }
    }

    // If we exit the loop, ALL keys returned 429
    return "ALL_KEYS_EXHAUSTED";
  }

  /// Generic method for generating a single text response (like Task Analysis)
  Future<String?> generateAIResponse(String prompt) async {
    if (await _hasReachedDailyLimit()) {
      return "LIMIT_REACHED";
    }

    if (_apiKeys.isEmpty) {
      return "⚠️ Error: No API keys configured.";
    }

    for (int attempts = 0; attempts < _apiKeys.length; attempts++) {
      final currentKey = _apiKeys[_currentKeyIndex];
      
      try {
        final response = await http.post(
          Uri.parse("https://api.groq.com/openai/v1/chat/completions"),
          headers: {
            "Authorization": "Bearer $currentKey",
            "Content-Type": "application/json",
          },
          body: jsonEncode({
            "model": "openai/gpt-oss-20b",
            "messages": [
              {
                "role": "system",
                "content": "You are a highly capable AI assistant."
              },
              {
                "role": "user",
                "content": prompt
              }
            ]
          }),
        );

        if (response.statusCode == 200) {
          await _incrementUsage();
          final data = jsonDecode(response.body);
          return data['choices']?[0]?['message']?['content'] ?? "";
        } 
        else if (response.statusCode == 429) {
          print("Key $_currentKeyIndex hit 429 Limit. Rotating...");
          _currentKeyIndex = (_currentKeyIndex + 1) % _apiKeys.length;
          continue;
        } 
        else {
          print("Groq API Error: ${response.statusCode} - ${response.body}");
          return "⚠️ API Error: ${response.statusCode}";
        }
      } catch (e) {
        print("Exception during Groq API call: $e");
        return "⚠️ Network Error";
      }
    }
    return "ALL_KEYS_EXHAUSTED";
  }
}
