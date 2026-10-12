import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/advisor_message.dart';
import '../models/grade_report.dart';
import '../models/group_schedule.dart';
import '../models/portal_message.dart';
import '../models/semester_plan.dart';
import '../models/student.dart';
import '../models/student_course_schedule.dart';
import '../models/student_group_schedule.dart';
import '../models/student_notification.dart';
import '../models/weekly_plan.dart';

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

  /// Production builds use the public Railway service by default.
  /// Override this only when intentionally testing another API with:
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
        'Could not reach UNI Track. Check that the service is running and the API URL is correct.',
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
        'The configured address is not the UNI Track service. Check the API URL.',
      );
    }

    throw ApiException(
      'The server could not sign you in (${response.statusCode}).',
    );
  }

  Future<Student> loginStudent(String studentId, String password) async {
    final normalizedId = studentId.trim();
    if (normalizedId.isEmpty) {
      throw const ApiException('Enter your student ID.');
    }
    if (password.isEmpty) {
      throw const ApiException('Enter your password.');
    }

    final parsedBaseUrl = Uri.parse(baseUrl);
    final uri = parsedBaseUrl.replace(
      pathSegments: [
        ...parsedBaseUrl.pathSegments.where((segment) => segment.isNotEmpty),
        'student',
        'login',
      ],
    );

    late http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'student_id': normalizedId,
              'password': password,
            }),
          )
          // Production password verification can be slower while Railway wakes
          // the database. Keep login alive long enough to receive the real
          // authentication result instead of reporting a network failure.
          .timeout(const Duration(seconds: 90));
    } on TimeoutException {
      throw const ApiException(
        'The sign-in service took too long to respond. Please try again.',
      );
    } on Exception {
      throw const ApiException(
        'Could not reach UNI Track. Check your connection and try again.',
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
    if (response.statusCode == 401) {
      throw const ApiException('Incorrect student ID or password.');
    }
    throw ApiException(
      _errorDetail(
        response,
        'The server could not sign you in (${response.statusCode}).',
      ),
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
        'Could not reach Aegis AI. Check your connection and try again.',
      );
    }

    if (response.statusCode == 200) {
      try {
        return AdvisorReply.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      } on FormatException {
        throw const ApiException('Aegis AI returned an invalid response.');
      } on TypeError {
        throw const ApiException('Aegis AI returned an invalid response.');
      }
    }

    throw ApiException(
      _errorDetail(
        response,
        'Aegis AI could not answer your question (${response.statusCode}).',
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

  Future<Map<String, dynamic>> simulateAssessmentGrade({
    required String studentId,
    required String courseId,
    required String assessmentId,
    required double hypotheticalGrade,
  }) async {
    final normalizedId = Uri.encodeComponent(studentId.trim());
    final uri = Uri.parse('$baseUrl/progress/$normalizedId/what-if');
    late http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'type': 'assessment_grade',
              'course_id': courseId,
              'assessment_id': assessmentId,
              'hypothetical_grade': hypotheticalGrade,
            }),
          )
          .timeout(const Duration(seconds: 120));
    } on Exception {
      throw const ApiException(
        'Could not run the what-if simulation. Check your connection and try again.',
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        _errorDetail(
          response,
          'What-if simulation could not complete (${response.statusCode}).',
        ),
      );
    }
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on Exception {
      throw const ApiException('The server returned invalid simulation data.');
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

  Future<Uint8List> speakAdvisor({
    required String text,
    String language = 'english',
  }) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      throw const ApiException('There is no Advisor response to speak.');
    }

    final parsedBaseUrl = Uri.parse(baseUrl);
    final uri = parsedBaseUrl.replace(
      pathSegments: [
        ...parsedBaseUrl.pathSegments.where((segment) => segment.isNotEmpty),
        'advisor',
        'speak',
      ],
      queryParameters: {'text': normalizedText, 'language': language},
    );

    late http.Response response;
    try {
      response = await _client.post(uri).timeout(const Duration(seconds: 60));
    } on Exception {
      throw const ApiException(
        'Could not load the Advisor voice response. Try again.',
      );
    }

    if (response.statusCode != 200) {
      throw ApiException(
        _errorDetail(
          response,
          'Advisor voice could not speak the response (${response.statusCode}).',
        ),
      );
    }

    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return base64Decode(payload['audio_base64'] as String);
    } on Exception {
      throw const ApiException('Advisor voice returned invalid audio.');
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

  Future<StudentGroupScheduleReport> getStudentGroupSchedule(
    String studentId, {
    bool forceRefresh = false,
  }) async {
    final normalizedId = Uri.encodeComponent(studentId.trim());
    final uri = Uri.parse('$baseUrl/portal/students/$normalizedId/schedule');
    late http.Response response;
    try {
      response = await _get(
        uri,
        cacheFor: const Duration(minutes: 1),
        forceRefresh: forceRefresh,
      );
    } on Exception {
      throw const ApiException(
        'Could not load your university schedule. Check your connection and try again.',
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        _errorDetail(
          response,
          'Could not load your university schedule (${response.statusCode}).',
        ),
      );
    }
    try {
      return StudentGroupScheduleReport.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on Exception {
      throw const ApiException('The server returned invalid schedule data.');
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

  /// The student's common group schedule plus the names of everyone who shares it.
  /// The first visit builds the group on the server, so this allows a longer wait.
  Future<GroupSchedule> getGroupSchedule(String studentId) async {
    final normalizedId = Uri.encodeComponent(studentId.trim());
    final uri = Uri.parse('$baseUrl/portal/students/$normalizedId/schedule');
    late http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 45));
    } on Exception {
      throw const ApiException(
        'Could not load your schedule. Check your connection and try again.',
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        _errorDetail(
          response,
          'Could not load your schedule (${response.statusCode}).',
        ),
      );
    }
    try {
      return GroupSchedule.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on Exception {
      throw const ApiException('The server returned invalid schedule data.');
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

  Future<List<MessageContact>> getMessageContacts(String studentId) async {
    final uri = Uri.parse('$baseUrl/messages/contacts').replace(
      queryParameters: {'actor_type': 'student', 'actor_id': studentId.trim()},
    );
    late http.Response response;
    try {
      response = await _get(uri, cacheFor: const Duration(minutes: 5));
    } on Exception {
      throw const ApiException(
        'Could not load your contacts. Check your connection and try again.',
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        _errorDetail(
          response,
          'Could not load your contacts (${response.statusCode}).',
        ),
      );
    }
    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final contacts = payload['contacts'] as List<dynamic>? ?? const [];
      return contacts
          .map(
            (contact) =>
                MessageContact.fromJson(contact as Map<String, dynamic>),
          )
          .where((contact) => contact.id.isNotEmpty)
          .toList();
    } on Exception {
      throw const ApiException('The server returned invalid contact data.');
    }
  }

  Future<List<PortalMessage>> getMessages(String studentId) async {
    final uri = Uri.parse('$baseUrl/messages').replace(
      queryParameters: {'actor_type': 'student', 'actor_id': studentId.trim()},
    );
    late http.Response response;
    try {
      response = await _get(
        uri,
        cacheFor: const Duration(seconds: 5),
        forceRefresh: true,
      );
    } on Exception {
      throw const ApiException(
        'Could not load your messages. Check your connection and try again.',
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        _errorDetail(
          response,
          'Could not load your messages (${response.statusCode}).',
        ),
      );
    }
    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final messages = payload['messages'] as List<dynamic>? ?? const [];
      return messages
          .map(
            (message) =>
                PortalMessage.fromJson(message as Map<String, dynamic>),
          )
          .where((message) => message.messageId.isNotEmpty)
          .toList();
    } on Exception {
      throw const ApiException('The server returned invalid message data.');
    }
  }

  Future<PortalMessage> sendMessage({
    required String studentId,
    required MessageContact recipient,
    required String body,
  }) async {
    final normalizedBody = body.trim();
    if (normalizedBody.isEmpty) {
      throw const ApiException('Write a message first.');
    }
    final uri = Uri.parse('$baseUrl/messages');
    late http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'sender_type': 'student',
              'sender_id': studentId.trim(),
              'recipient_type': recipient.type,
              'recipient_id': recipient.id,
              'is_broadcast': false,
              'body': normalizedBody,
            }),
          )
          .timeout(const Duration(seconds: 20));
    } on Exception {
      throw const ApiException(
        'Could not send your message. Check your connection and try again.',
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        _errorDetail(
          response,
          'Could not send your message (${response.statusCode}).',
        ),
      );
    }
    _responseCache.remove(Uri.parse('$baseUrl/messages').toString());
    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return PortalMessage.fromJson(payload['message'] as Map<String, dynamic>);
    } on Exception {
      throw const ApiException('The server returned invalid message data.');
    }
  }

  Future<PortalMessage> sendMessageAttachment({
    required String studentId,
    required MessageContact recipient,
    required String filename,
    required Uint8List bytes,
    String body = '',
  }) async {
    if (bytes.isEmpty) {
      throw const ApiException('The selected document is empty.');
    }
    if (bytes.length > 10 * 1024 * 1024) {
      throw const ApiException('Documents must be 10 MB or smaller.');
    }
    final uri = Uri.parse('$baseUrl/messages/attachments');
    late http.Response response;
    try {
      final request = http.MultipartRequest('POST', uri)
        ..fields.addAll({
          'sender_type': 'student',
          'sender_id': studentId.trim(),
          'recipient_type': recipient.type,
          'recipient_id': recipient.id,
          'body': body.trim(),
        })
        ..files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: filename),
        );
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 60));
      response = await http.Response.fromStream(streamed);
    } on Exception {
      throw const ApiException(
        'Could not send your document. Check your connection and try again.',
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        _errorDetail(
          response,
          'Could not send your document (${response.statusCode}).',
        ),
      );
    }
    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return PortalMessage.fromJson(payload['message'] as Map<String, dynamic>);
    } on Exception {
      throw const ApiException('The server returned invalid message data.');
    }
  }

  Future<void> markMessagesRead({
    required String studentId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) return;
    final uri = Uri.parse('$baseUrl/messages/read');
    late http.Response response;
    try {
      response = await _client
          .put(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'actor_type': 'student',
              'actor_id': studentId.trim(),
              'message_ids': messageIds,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } on Exception {
      throw const ApiException(
        'Could not update your messages. Check your connection and try again.',
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        _errorDetail(
          response,
          'Could not update your messages (${response.statusCode}).',
        ),
      );
    }
  }

  Future<WeeklyPlan> getWeeklyPlan(
    String studentId, {
    bool forceRefresh = false,
  }) async {
    final normalizedId = Uri.encodeComponent(studentId.trim());
    final uri = Uri.parse('$baseUrl/portal/students/$normalizedId/weekly-plan');
    late http.Response response;
    try {
      response = await _get(
        uri,
        cacheFor: const Duration(seconds: 30),
        forceRefresh: forceRefresh,
      );
    } on Exception {
      throw const ApiException(
        'Could not load your weekly plan. Check your connection and try again.',
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        _errorDetail(
          response,
          'Could not load your weekly plan (${response.statusCode}).',
        ),
      );
    }
    try {
      return WeeklyPlan.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on Exception {
      throw const ApiException('The server returned invalid weekly plan data.');
    }
  }

  Future<WeeklyPlanItem> setWeeklyPlanItemStatus({
    required String studentId,
    required String taskId,
    required bool completed,
  }) async {
    final normalizedId = Uri.encodeComponent(studentId.trim());
    final normalizedTaskId = Uri.encodeComponent(taskId);
    final uri = Uri.parse(
      '$baseUrl/portal/students/$normalizedId/weekly-plan/$normalizedTaskId',
    );
    late http.Response response;
    try {
      response = await _client
          .put(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'status': completed ? 'completed' : 'pending'}),
          )
          .timeout(const Duration(seconds: 15));
    } on Exception {
      throw const ApiException(
        'Could not save this task. Check your connection and try again.',
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        _errorDetail(
          response,
          'Could not save this task (${response.statusCode}).',
        ),
      );
    }
    _responseCache.remove(
      Uri.parse('$baseUrl/portal/students/$normalizedId/weekly-plan')
          .toString(),
    );
    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return WeeklyPlanItem.fromJson(payload['item'] as Map<String, dynamic>);
    } on Exception {
      throw const ApiException('The server returned invalid weekly task data.');
    }
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
