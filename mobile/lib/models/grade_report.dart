class StudentGradeReport {
  const StudentGradeReport({
    required this.cumulativeGpa,
    required this.completedCourses,
    required this.semesters,
    required this.records,
  });

  factory StudentGradeReport.fromJson(Map<String, dynamic> json) {
    final student = json['student'] as Map<String, dynamic>? ?? const {};
    return StudentGradeReport(
      cumulativeGpa: (student['gpa'] as num?)?.toDouble(),
      completedCourses: (json['completed_courses'] as num?)?.toInt() ?? 0,
      semesters: (json['semesters'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                SemesterGradeSummary.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      records: (json['records'] as List<dynamic>? ?? const [])
          .map(
            (item) => StudentGradeRecord.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  final double? cumulativeGpa;
  final int completedCourses;
  final List<SemesterGradeSummary> semesters;
  final List<StudentGradeRecord> records;
}

class SemesterGradeSummary {
  const SemesterGradeSummary({
    required this.semester,
    required this.gpa,
    required this.coursesGraded,
    required this.standing,
  });

  factory SemesterGradeSummary.fromJson(Map<String, dynamic> json) {
    return SemesterGradeSummary(
      semester: json['semester'] as String,
      gpa: (json['gpa'] as num?)?.toDouble(),
      coursesGraded: (json['courses_graded'] as num?)?.toInt() ?? 0,
      standing: json['standing'] as String? ?? 'In Progress',
    );
  }

  final String semester;
  final double? gpa;
  final int coursesGraded;
  final String standing;
}

class StudentGradeRecord {
  const StudentGradeRecord({
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.semester,
    required this.enrollmentStatus,
    required this.courseworkMark,
    required this.week7ExamMark,
    required this.week12ExamMark,
    required this.finalExamMark,
    required this.totalScore,
    required this.letterGrade,
    required this.gpaPoints,
    required this.gradeSource,
    required this.gradePosted,
  });

  factory StudentGradeRecord.fromJson(Map<String, dynamic> json) {
    double? number(String key) => (json[key] as num?)?.toDouble();
    final courseworkMark = number('coursework_mark');
    final week7ExamMark = number('week7_exam_mark');
    final week12ExamMark = number('week12_exam_mark');
    final finalExamMark = number('final_exam_mark');
    final letterGrade = json['letter_grade'] as String?;
    final inferredSource =
        courseworkMark != null ||
            week7ExamMark != null ||
            week12ExamMark != null ||
            finalExamMark != null
        ? 'gradebook'
        : letterGrade != null
        ? 'transcript'
        : 'none';
    return StudentGradeRecord(
      courseId: json['course_id'].toString(),
      courseCode: (json['course_code'] ?? json['course_id']).toString(),
      courseName: json['course_name'] as String,
      semester: json['semester'] as String,
      enrollmentStatus: json['enrollment_status'] as String? ?? 'Current',
      courseworkMark: courseworkMark,
      week7ExamMark: week7ExamMark,
      week12ExamMark: week12ExamMark,
      finalExamMark: finalExamMark,
      totalScore: number('total_score'),
      letterGrade: letterGrade,
      gpaPoints: number('gpa_points'),
      gradeSource: json['grade_source'] as String? ?? inferredSource,
      gradePosted: json['grade_posted'] as bool? ?? letterGrade != null,
    );
  }

  final String courseId;
  final String courseCode;
  final String courseName;
  final String semester;
  final String enrollmentStatus;
  final double? courseworkMark;
  final double? week7ExamMark;
  final double? week12ExamMark;
  final double? finalExamMark;
  final double? totalScore;
  final String? letterGrade;
  final double? gpaPoints;
  final String gradeSource;
  final bool gradePosted;
}
