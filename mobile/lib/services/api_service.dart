import 'dart:convert';

import 'package:http/http.dart' as http;

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
    defaultValue: 'http://10.0.2.2:8000',
  );

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

  void close() => _client.close();
}

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
