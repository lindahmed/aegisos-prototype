class WeeklyPlan {
  const WeeklyPlan({
    required this.studentId,
    required this.semester,
    required this.currentWeek,
    required this.items,
  });

  factory WeeklyPlan.fromJson(Map<String, dynamic> json) => WeeklyPlan(
    studentId: json['student_id'] as String,
    semester: json['semester'] as String,
    currentWeek: (json['current_week'] as num).toInt(),
    items: ((json['items'] as List<dynamic>?) ?? const [])
        .map((item) => WeeklyPlanItem.fromJson(item as Map<String, dynamic>))
        .toList(),
  );

  final String studentId;
  final String semester;
  final int currentWeek;
  final List<WeeklyPlanItem> items;

  WeeklyPlan replaceItem(WeeklyPlanItem replacement) => WeeklyPlan(
    studentId: studentId,
    semester: semester,
    currentWeek: currentWeek,
    items: items
        .map((item) => item.taskId == replacement.taskId ? replacement : item)
        .toList(),
  );
}

class WeeklyPlanItem {
  const WeeklyPlanItem({
    required this.taskId,
    required this.courseId,
    required this.courseName,
    required this.title,
    required this.detail,
    required this.taskType,
    required this.status,
    required this.position,
    this.completedAt,
  });

  factory WeeklyPlanItem.fromJson(Map<String, dynamic> json) {
    final completedAt = json['completed_at'] as String?;
    return WeeklyPlanItem(
      taskId: json['task_id'] as String,
      courseId: json['course_id'] as String,
      courseName: json['course_name'] as String,
      title: json['title'] as String,
      detail: json['detail'] as String,
      taskType: json['task_type'] as String,
      status: json['status'] as String,
      position: (json['position'] as num).toInt(),
      completedAt: completedAt == null ? null : DateTime.tryParse(completedAt),
    );
  }

  final String taskId;
  final String courseId;
  final String courseName;
  final String title;
  final String detail;
  final String taskType;
  final String status;
  final int position;
  final DateTime? completedAt;

  bool get isCompleted => status == 'completed';

  WeeklyPlanItem withStatus(String nextStatus) => WeeklyPlanItem(
    taskId: taskId,
    courseId: courseId,
    courseName: courseName,
    title: title,
    detail: detail,
    taskType: taskType,
    status: nextStatus,
    position: position,
    completedAt: nextStatus == 'completed' ? DateTime.now() : null,
  );
}
