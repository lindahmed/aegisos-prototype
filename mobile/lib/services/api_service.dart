import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/advisor_message.dart';
import '../models/grade_report.dart';
import '../models/semester_plan.dart';
import '../models/student.dart';
import '../models/student_course_schedule.dart';
import '../models/student_notification.dart';

class ApiService {
  factory ApiService({http.Client? client, String? baseUrl}) {
    if (client == null && baseUrl == null) return shared;
    return ApiService._(
      client: client ?? http.Client(),
      baseUrl: baseUrl ?? defaultBaseUrl,
    );
  }

  ApiService._({
    required this._client,
    required String baseUrl,
    this._shared = false,
  }) : baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), '');

  /// Android emulators reach the development machine through 10.0.2.2.
  /// Port 8001 is reserved for AegisOS so another local service on 8000 cannot
  /// be mistaken for this API.
  /// Override this for a physical device or deployed API with:
  /// --dart-define=API_BASE_URL=https://api.example.com
  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://web-production-3a6ad.up.railway.app',
  );

  /// One keep-alive client is reused across login and every student screen.
  static final ApiService shared = ApiService._(
    client: http.Client(),
    baseUrl: defaultBaseUrl,
    shared: true,
  );

  final http.Client _client;
  final bool _shared;
  final String baseUrl;
  final Map<String, _ResponseCacheEntry> _responseCache = {};
  final Map<String, Future<http.Response>> _requestsInFlight = {};

  Future<http.Response> _get(
    Uri uri, {
    required Duration cacheFor,
    bool forceRefresh = false,
  }) async {
    final key = uri.toString();
    final cached = _responseCache[key];
    if (!forceRefresh && cached != null && cached.isFresh) {
      return cached.response;
    }

    final pending = _requestsInFlight[key];
    if (pending != null) return pending;

    final request = _client.get(uri).timeout(const Duration(seconds: 15));
    _requestsInFlight[key] = request;
    try {
      final response = await request;
      if (response.statusCode == 200) {
        _responseCache[key] = _ResponseCacheEntry(
          response,
          DateTime.now().add(cacheFor),
        );
      }
      return response;
    } finally {
      _requestsInFlight.remove(key);
    }
  }

  Future<Student> getStudent(
    String studentId, {
    bool forceRefresh = false,
  }) async {
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
      response = await _get(
        uri,
        cacheFor: const Duration(minutes: 5),
        forceRefresh: forceRefresh,
      );
    } on Exception {
      throw const ApiException(
        'Could not reach AegisOS. Check that the backend is running and the API URL is correct.',
      );
    }

    if (response.statusCode == 200) {
      try {
        return Student.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      } on FormatException {
        throw const ApiException('The server returned an invalid response.');
      } on TypeError {
        throw const ApiException(
          'The server returned an invalid student record.',
        );
      }
    }

    if (response.statusCode == 404) {
      final detail = _errorDetail(response, '');
      if (detail.toLowerCase() == 'student not found') {
        throw const ApiException('Student ID not found.');
      }
      throw const ApiException(
        'The configured address is not the AegisOS API. Check the API URL.',
      );
    }

    throw ApiException(
      'The server could not sign you in (${response.statusCode}).',
    );
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

  Future<Map<String, dynamic>> getStudentAcademics(
    String studentId, {
    bool forceRefresh = false,
  }) async {
    final normalizedId = Uri.encodeComponent(studentId.trim());
    // The calendar only needs the current progress twin (courses, assessments,
    // risks, and week). Reuse the dashboard route and its cache instead of the
    // heavier academics aggregate, which also rebuilds the full grade report.
    final uri = Uri.parse('$baseUrl/progress/$normalizedId');
    late http.Response response;
    try {
      response = await _get(
        uri,
        cacheFor: const Duration(minutes: 1),
        forceRefresh: forceRefresh,
      );
    } on Exception {
      throw const ApiException(
        'Could not load academic progress. Check your connection and try again.',
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        _errorDetail(
          response,
          'Could not load academic progress (${response.statusCode}).',
        ),
      );
    }
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on Exception {
      throw const ApiException(
        'The server returned invalid academic progress data.',
      );
    }
  }

  Future<Map<String, dynamic>> getStudentProgress(
    String studentId, {
    bool forceRefresh = false,
  }) async {
    final normalizedId = Uri.encodeComponent(studentId.trim());
    final uri = Uri.parse('$baseUrl/progress/$normalizedId');
    late http.Response response;
    try {
      response = await _get(
        uri,
        cacheFor: const Duration(seconds: 30),
        forceRefresh: forceRefresh,
      );
    } on Exception {
      throw const ApiException(
        'Could not load live progress. Check your connection and try again.',
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        _errorDetail(
          response,
          'Could not load live progress (${response.statusCode}).',
        ),
      );
    }
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on Exception {
      throw const ApiException('The server returned invalid progress data.');
    }
  }

  Future<StudentGradeReport> getStudentGrades(
    String studentId, {
    bool forceRefresh = false,
  }) async {
    final normalizedId = Uri.encodeComponent(studentId.trim());
    final uri = Uri.parse('$baseUrl/portal/students/$normalizedId/grades');
    late http.Response response;
    try {
      response = await _get(
        uri,
        cacheFor: const Duration(minutes: 1),
        forceRefresh: forceRefresh,
      );
    } on Exception {
      throw const ApiException(
        'Could not load grades. Check your connection and try again.',
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        _errorDetail(
          response,
          'Could not load grades (${response.statusCode}).',
        ),
      );
    }
    try {
      return StudentGradeReport.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on Exception {
      throw const ApiException('The server returned invalid grade data.');
    }
  }

  Future<StudentCoursesReport> getStudentCourses(
    String studentId, {
    bool forceRefresh = false,
  }) async {
    final normalizedId = Uri.encodeComponent(studentId.trim());
    final uri = Uri.parse('$baseUrl/portal/students/$normalizedId/courses');
    late http.Response response;
    try {
      response = await _get(
        uri,
        cacheFor: const Duration(minutes: 1),
        forceRefresh: forceRefresh,
      );
    } on Exception {
      throw const ApiException(
        'Could not load your courses. Check your connection and try again.',
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        _errorDetail(
          response,
          'Could not load your courses (${response.statusCode}).',
        ),
      );
    }
    try {
      return StudentCoursesReport.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on Exception {
      throw const ApiException('The server returned invalid course data.');
    }
  }

  Future<SemesterPlan> getSemesterPlan(
    String studentId, {
    int maxCredits = 18,
    bool forceRefresh = false,
  }) async {
    final normalizedId = Uri.encodeComponent(studentId.trim());
    final uri = Uri.parse(
      '$baseUrl/portal/students/$normalizedId/semester-plan',
    ).replace(queryParameters: {'max_credits': '$maxCredits'});
    late http.Response response;
    try {
      response = await _get(
        uri,
        cacheFor: const Duration(minutes: 5),
        forceRefresh: forceRefresh,
      );
    } on Exception {
      throw const ApiException(
        'Could not load your semester plan. Check your connection and try again.',
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        _errorDetail(
          response,
          'Could not load your semester plan (${response.statusCode}).',
        ),
      );
    }
    try {
      return SemesterPlan.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on Exception {
      throw const ApiException('The server returned invalid planner data.');
    }
  }

  Future<List<StudentNotification>> getStudentNotifications(
    String studentId, {
    bool forceRefresh = false,
  }) async {
    final normalizedId = Uri.encodeComponent(studentId.trim());
    final uri = Uri.parse(
      '$baseUrl/portal/students/$normalizedId/notifications',
    );
    late http.Response response;
    try {
      response = await _get(
        uri,
        cacheFor: const Duration(minutes: 1),
        forceRefresh: forceRefresh,
      );
    } on Exception {
      throw const ApiException(
        'Could not load notifications. Check your connection and try again.',
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        _errorDetail(
          response,
          'Could not load notifications (${response.statusCode}).',
        ),
      );
    }
    final notificationsUri = Uri.parse(
      '$baseUrl/portal/students/$normalizedId/notifications',
    );
    _responseCache[notificationsUri.toString()] = _ResponseCacheEntry(
      response,
      DateTime.now().add(const Duration(minutes: 1)),
    );
    return _decodeNotifications(response);
  }

  Future<List<StudentNotification>> setNotificationsRead({
    required String studentId,
    required List<String> notificationIds,
    required bool read,
  }) async {
    if (notificationIds.isEmpty) return getStudentNotifications(studentId);
    final normalizedId = Uri.encodeComponent(studentId.trim());
    final uri = Uri.parse(
      '$baseUrl/portal/students/$normalizedId/notifications/read',
    );
    late http.Response response;
    try {
      response = await _client
          .put(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'notification_ids': notificationIds,
              'read': read,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } on Exception {
      throw const ApiException(
        'Could not update notifications. Check your connection and try again.',
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        _errorDetail(
          response,
          'Could not update notifications (${response.statusCode}).',
        ),
      );
    }
    return _decodeNotifications(response);
  }

  static List<StudentNotification> _decodeNotifications(
    http.Response response,
  ) {
    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final items = payload['notifications'] as List<dynamic>? ?? const [];
      return items
          .map(
            (item) =>
                StudentNotification.fromJson(item as Map<String, dynamic>),
          )
          .toList();
    } catch (_) {
      throw const ApiException(
        'The server returned invalid notification data.',
      );
    }
  }

  void close() {
    if (_shared) return;
    _responseCache.clear();
    _requestsInFlight.clear();
    _client.close();
  }
}

class _ResponseCacheEntry {
  const _ResponseCacheEntry(this.response, this.expiresAt);

  final http.Response response;
  final DateTime expiresAt;

  bool get isFresh => DateTime.now().isBefore(expiresAt);
}

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
