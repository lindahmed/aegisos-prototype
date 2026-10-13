import '../models/calendar_event.dart';
import 'api_service.dart';

class LocalStudyPlanner {
  const LocalStudyPlanner._();

  static Future<StudentCalendarEvent> addNextAvailable({
    required ApiService apiService,
    required String studentId,
    required String courseName,
    String? courseId,
    String reason = 'Added from Aegis Advisor.',
    Duration duration = const Duration(minutes: 90),
  }) async {
    final results = await Future.wait<Object>([
      apiService.getStudentAcademics(studentId),
      StudentCalendarStore.load(studentId),
    ]);
    final academics = results[0] as Map<String, dynamic>;
    final saved = results[1] as List<StudentCalendarEvent>;
    final busy = [
      ...StudentCalendarBuilder.academicEvents(academics),
      ...saved,
    ];
    final start = StudentCalendarBuilder.nextAvailableStudySlot(
      events: busy,
      duration: duration,
    );
    final event = StudentCalendarEvent(
      id: 'ai-action:${DateTime.now().microsecondsSinceEpoch}',
      title: 'Study $courseName',
      description: reason,
      startAt: start,
      endAt: start.add(duration),
      type: StudentCalendarEventType.studySession,
      source: StudentCalendarEventSource.ai,
      courseId: courseId,
    );
    await StudentCalendarStore.save(studentId, [...saved, event]);
    return event;
  }
}
