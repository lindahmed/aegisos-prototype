import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/advisor_message.dart';
import '../models/student.dart';

class ApiService {
  ApiService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = (baseUrl ?? defaultBaseUrl).replaceFirst(RegExp(r'/$'), '');

  /// Android emulators reach the development machine through 10.0.2.2.
  /// Override this for a physical device or deployed API with:
  /// --dart-define=API_BASE_URL=https://api.example.com
  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
defaultValue: 'https://backend-production-6069.up.railway.app',  );

  final http.Client _client;
  final String baseUrl;

  Future<Student> getStudent(String studentId) async {
    final normalizedId = studentId.trim();
    if (normalizedId.isEmpty) {
      throw const ApiException('Enter your student ID.');
    }

    final parsedBaseUrl = Uri.parse(baseUrl);
    final uri = parsedBaseUrl.replace(
      pathSegments: [
        ...parsedBaseUrl.pathSegments.where((segment) => segment.isNotEmpty),
        'student',
        normalizedId,
      ],
    );

    late http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 15));
    } on Exception {
      throw const ApiException(
        'Could not reach AegisOS. Check that the backend is running and the API URL is correct.',
      );
    }

    if (response.statusCode == 200) {
      try {
        return Student.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
      } on FormatException {
        throw const ApiException('The server returned an invalid response.');
      } on TypeError {
        throw const ApiException('The server returned an invalid student record.');
      }
    }

    if (response.statusCode == 404) {
      throw const ApiException('Student ID not found.');
    }

    throw ApiException('The server could not sign you in (${response.statusCode}).');
  }

  Future<AdvisorReply> askAdvisor({
    required String studentId,
    required String message,
    required List<AdvisorMessage> history,
    String language = 'english',
  }) async {
    final normalizedMessage = message.trim();
    if (normalizedMessage.isEmpty) {
      throw const ApiException('Enter a question for your advisor.');
    }

    final parsedBaseUrl = Uri.parse(baseUrl);
    final uri = parsedBaseUrl.replace(
      pathSegments: [
        ...parsedBaseUrl.pathSegments.where((segment) => segment.isNotEmpty),
        'advisor',
      ],
    );
    final recentHistory = history.length <= 10
        ? history
        : history.sublist(history.length - 10);

    late http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'student_id': studentId,
              'message': normalizedMessage,
              'language': language,
              'history': recentHistory.map((item) => item.toJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 120));
    } on Exception {
      throw const ApiException(
        'Could not reach Advisor AI. Check that the backend is running and try again.',
      );
    }

    if (response.statusCode == 200) {
      try {
        return AdvisorReply.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      } on FormatException {
        throw const ApiException('Advisor AI returned an invalid response.');
      } on TypeError {
        throw const ApiException('Advisor AI returned an invalid response.');
      }
    }

    throw ApiException(
      _errorDetail(
        response,
        'Advisor AI could not answer your question (${response.statusCode}).',
      ),
    );
  }

  static String _errorDetail(http.Response response, String fallback) {
    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final detail = payload['detail'];
      return detail is String && detail.isNotEmpty ? detail : fallback;
    } catch (_) {
      return fallback;
    }
  }


  Future<Map<String, dynamic>> getStudentAcademics(String studentId) async {
    final normalizedId = Uri.encodeComponent(studentId.trim());
    final uri = Uri.parse("$baseUrl/portal/students/$normalizedId/academics");
    late http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 15));
    } on Exception {
      throw const ApiException('Could not load academic progress. Check your connection and try again.');
    }
    if (response.statusCode != 200) {
      throw ApiException(_errorDetail(response, 'Could not load academic progress (${response.statusCode}).'));
    }
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on Exception {
      throw const ApiException('The server returned invalid academic progress data.');
    }
  }

  void close() => _client.close();
}

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
