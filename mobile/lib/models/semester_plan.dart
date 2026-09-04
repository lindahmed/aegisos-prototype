class PlanPrerequisite {
  const PlanPrerequisite({
    required this.courseCode,
    required this.courseName,
    required this.status,
  });

  factory PlanPrerequisite.fromJson(Map<String, dynamic> json) =>
      PlanPrerequisite(
        courseCode: json['course_code']?.toString() ?? '',
        courseName: json['course_name']?.toString() ?? 'Prerequisite',
        status: json['status']?.toString() ?? 'missing',
      );

  final String courseCode;
  final String courseName;
  final String status;
}

class PlanScheduleSlot {
  const PlanScheduleSlot({
    required this.day,
    required this.startMinute,
    required this.endMinute,
    this.location,
  });

  factory PlanScheduleSlot.fromJson(Map<String, dynamic> json) =>
      PlanScheduleSlot(
        day: json['day_of_week']?.toString() ?? '',
        startMinute: (json['start_minute'] as num?)?.toInt() ?? 0,
        endMinute: (json['end_minute'] as num?)?.toInt() ?? 0,
        location: json['location']?.toString(),
      );

  final String day;
  final int startMinute;
  final int endMinute;
  final String? location;
}

class PlanCourse {
  const PlanCourse({
    required this.id,
    required this.code,
    required this.name,
    required this.curriculumSemester,
    required this.courseType,
    required this.creditHours,
    required this.eligibility,
    required this.prerequisites,
    required this.schedule,
  });

  factory PlanCourse.fromJson(Map<String, dynamic> json) => PlanCourse(
    id: json['course_id']?.toString() ?? '',
    code: json['course_code']?.toString() ?? '',
    name: json['course_name']?.toString() ?? 'Course',
    curriculumSemester: (json['curriculum_semester'] as num?)?.toInt(),
    courseType: json['course_type']?.toString() ?? 'Required',
    creditHours: (json['credit_hours'] as num?)?.toInt() ?? 3,
    eligibility: json['eligibility']?.toString() ?? 'blocked',
    prerequisites: ((json['prerequisites'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PlanPrerequisite.fromJson)
        .toList(),
    schedule: ((json['schedule'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PlanScheduleSlot.fromJson)
        .toList(),
  );

  final String id;
  final String code;
  final String name;
  final int? curriculumSemester;
  final String courseType;
  final int creditHours;
  final String eligibility;
  final List<PlanPrerequisite> prerequisites;
  final List<PlanScheduleSlot> schedule;

  bool get canSelect => eligibility != 'blocked';
}

class PlanTerm {
  const PlanTerm({
    required this.semesterNumber,
    required this.label,
    required this.termType,
    required this.creditHours,
    required this.courses,
  });

  factory PlanTerm.fromJson(Map<String, dynamic> json) {
    final semesterNumber = (json['semester_number'] as num?)?.toInt();
    return PlanTerm(
      semesterNumber: semesterNumber,
      label:
          json['label']?.toString() ??
          (semesterNumber == null
              ? 'Extension term'
              : 'Semester $semesterNumber'),
      termType: json['term_type']?.toString() ?? 'regular',
      creditHours: (json['credit_hours'] as num?)?.toInt() ?? 0,
      courses: ((json['courses'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PlanCourse.fromJson)
          .toList(),
    );
  }

  final int? semesterNumber;
  final String label;
  final String termType;
  final int creditHours;
  final List<PlanCourse> courses;
}

class GraduationOption {
  const GraduationOption({
    required this.id,
    required this.title,
    required this.available,
    required this.maximumRegularCredits,
    required this.summerCredits,
    required this.summerAfterSemester,
    required this.regularSemesters,
    required this.summerTerms,
    required this.extensionTerms,
    required this.totalTerms,
    required this.savesRegularSemesters,
    required this.onTime,
    required this.note,
    required this.terms,
  });

  factory GraduationOption.fromJson(Map<String, dynamic> json) =>
      GraduationOption(
        id: json['id']?.toString() ?? 'normal',
        title: json['title']?.toString() ?? 'Normal route',
        available: json['available'] as bool? ?? true,
        maximumRegularCredits:
            (json['maximum_regular_credits'] as num?)?.toInt(),
        summerCredits: (json['summer_credits'] as num?)?.toInt() ?? 0,
        summerAfterSemester:
            (json['summer_after_semester'] as num?)?.toInt(),
        regularSemesters: (json['regular_semesters'] as num?)?.toInt() ?? 0,
        summerTerms: (json['summer_terms'] as num?)?.toInt() ?? 0,
        extensionTerms: (json['extension_terms'] as num?)?.toInt() ?? 0,
        totalTerms: (json['total_terms'] as num?)?.toInt() ?? 0,
        savesRegularSemesters:
            (json['saves_regular_semesters'] as num?)?.toInt() ?? 0,
        onTime: json['on_time'] as bool? ?? true,
        note: json['note']?.toString() ?? '',
        terms: ((json['terms'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(PlanTerm.fromJson)
            .toList(),
      );

  final String id;
  final String title;
  final bool available;
  final int? maximumRegularCredits;
  final int summerCredits;
  final int? summerAfterSemester;
  final int regularSemesters;
  final int summerTerms;
  final int extensionTerms;
  final int totalTerms;
  final int savesRegularSemesters;
  final bool onTime;
  final String note;
  final List<PlanTerm> terms;
}

class SemesterPlan {
  const SemesterPlan({
    required this.currentSemester,
    required this.nextSemester,
    required this.maximumProgramSemesters,
    required this.programSemestersRemaining,
    required this.currentGpa,
    required this.maximumCreditHours,
    required this.completedCreditHours,
    required this.recommendedCourses,
    required this.candidateCourses,
    required this.scheduleStatus,
    required this.scheduleNote,
    required this.creditNote,
    required this.remainingCourses,
    required this.minimumSemesters,
    required this.fitsStandardProgramLength,
    required this.graduationNote,
    required this.path,
    required this.halfLoad,
    required this.acceleratedAllowed,
    required this.graduationStatus,
    required this.bestOptionId,
    required this.graduationPolicyNote,
    required this.graduationOptions,
  });

  factory SemesterPlan.fromJson(Map<String, dynamic> json) {
    final projection =
        json['gpa_projection'] as Map<String, dynamic>? ?? const {};
    final creditPolicy =
        json['credit_policy'] as Map<String, dynamic>? ?? const {};
    final conflict =
        json['conflict_check'] as Map<String, dynamic>? ?? const {};
    final graduation =
        json['graduation_path'] as Map<String, dynamic>? ?? const {};
    final graduationChoices =
        json['graduation_options'] as Map<String, dynamic>? ?? const {};
    final currentSemester = ((json['current_semester'] as num?)?.toInt() ?? 1)
        .clamp(1, 8)
        .toInt();
    final maximumProgramSemesters =
        (json['maximum_program_semesters'] as num?)?.toInt() ?? 8;
    final maximumCreditHours =
        (json['maximum_credit_hours'] as num?)?.toInt() ?? 18;
    final legacyResponse = json['maximum_program_semesters'] == null;
    var recommendedCourses =
        ((json['recommended_courses'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(PlanCourse.fromJson)
            .toList();
    var candidateCourses =
        ((json['candidate_courses'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(PlanCourse.fromJson)
            .toList();
    var path = ((graduation['planned_semesters'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PlanTerm.fromJson)
        .where(
          (term) =>
              term.semesterNumber == null ||
              term.semesterNumber! <= maximumProgramSemesters,
        )
        .toList();

    // Older deployed planner responses can contain first-year courses and
    // semester numbers above eight for upper-year students. Keep the mobile
    // client safe while the shared backend rolls forward.
    if (legacyResponse) {
      bool belongsToCurrentStage(PlanCourse course) =>
          course.curriculumSemester == null ||
          course.curriculumSemester! >= currentSemester;
      candidateCourses = candidateCourses.where(belongsToCurrentStage).toList();
      recommendedCourses = recommendedCourses
          .where(belongsToCurrentStage)
          .toList();
      path = path
          .map(
            (term) => PlanTerm(
              semesterNumber: term.semesterNumber,
              label: term.label,
              termType: term.termType,
              creditHours: term.courses
                  .where(belongsToCurrentStage)
                  .fold(0, (total, course) => total + course.creditHours),
              courses: term.courses.where(belongsToCurrentStage).toList(),
            ),
          )
          .where((term) => term.courses.isNotEmpty)
          .toList();
      if (recommendedCourses.isEmpty &&
          currentSemester < maximumProgramSemesters) {
        var credits = 0;
        recommendedCourses = candidateCourses.where((course) {
          if (!course.canSelect ||
              credits + course.creditHours > maximumCreditHours) {
            return false;
          }
          credits += course.creditHours;
          return true;
        }).toList();
      }
      if (path.isEmpty && recommendedCourses.isNotEmpty) {
        path = [
          PlanTerm(
            semesterNumber: (currentSemester + 1)
                .clamp(1, maximumProgramSemesters)
                .toInt(),
            label:
                'Semester ${(currentSemester + 1).clamp(1, maximumProgramSemesters).toInt()}',
            termType: 'regular',
            creditHours: recommendedCourses.fold(
              0,
              (total, course) => total + course.creditHours,
            ),
            courses: recommendedCourses,
          ),
        ];
      }
    }
    final programSemestersRemaining =
        (json['program_semesters_remaining'] as num?)?.toInt() ??
        (maximumProgramSemesters - currentSemester)
            .clamp(0, maximumProgramSemesters)
            .toInt();
    final fitsStandardProgramLength = legacyResponse
        ? candidateCourses.length <=
              programSemestersRemaining * (maximumCreditHours ~/ 3)
        : graduation['fits_standard_program_length'] as bool? ?? true;
    var graduationOptions =
        ((graduationChoices['options'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(GraduationOption.fromJson)
            .toList();
    if (graduationOptions.isEmpty) {
      graduationOptions = [
        GraduationOption(
          id: 'normal',
          title: 'Normal route',
          available: true,
          maximumRegularCredits: maximumCreditHours,
          summerCredits: 0,
          summerAfterSemester: null,
          regularSemesters: path.length,
          summerTerms: 0,
          extensionTerms: 0,
          totalTerms: path.length,
          savesRegularSemesters: 0,
          onTime: fitsStandardProgramLength,
          note: graduation['note']?.toString() ?? '',
          terms: path,
        ),
      ];
    }
    return SemesterPlan(
      currentSemester: currentSemester,
      nextSemester:
          ((json['next_semester'] as num?)?.toInt() ?? currentSemester + 1)
              .clamp(1, maximumProgramSemesters)
              .toInt(),
      maximumProgramSemesters: maximumProgramSemesters,
      programSemestersRemaining: programSemestersRemaining,
      currentGpa: (json['current_gpa'] as num?)?.toDouble() ?? 0,
      maximumCreditHours: maximumCreditHours,
      completedCreditHours:
          (projection['completed_credit_hours'] as num?)?.toInt() ?? 0,
      recommendedCourses: recommendedCourses,
      candidateCourses: candidateCourses,
      scheduleStatus: conflict['status']?.toString() ?? 'unavailable',
      scheduleNote: conflict['note']?.toString() ?? '',
      creditNote: creditPolicy['note']?.toString() ?? '',
      remainingCourses: (graduation['remaining_courses'] as num?)?.toInt() ?? 0,
      minimumSemesters: legacyResponse
          ? ((graduation['minimum_semesters_after_current'] as num?)?.toInt() ??
                    path.length)
                .clamp(0, programSemestersRemaining)
                .toInt()
          : (graduation['minimum_semesters_after_current'] as num?)?.toInt() ??
                0,
      fitsStandardProgramLength: fitsStandardProgramLength,
      graduationNote: graduation['note']?.toString() ?? '',
      path: path,
      halfLoad: graduationChoices['half_load'] as bool? ?? false,
      acceleratedAllowed:
          graduationChoices['accelerated_allowed'] as bool? ?? true,
      graduationStatus:
          graduationChoices['student_status']?.toString() ?? 'on_track',
      bestOptionId:
          (graduationChoices['best_option_id'] ??
                  graduationChoices['fastest_option_id'] ??
                  'normal')
              .toString(),
      graduationPolicyNote:
          graduationChoices['policy_note']?.toString() ?? '',
      graduationOptions: graduationOptions,
    );
  }

  final int currentSemester;
  final int nextSemester;
  final int maximumProgramSemesters;
  final int programSemestersRemaining;
  final double currentGpa;
  final int maximumCreditHours;
  final int completedCreditHours;
  final List<PlanCourse> recommendedCourses;
  final List<PlanCourse> candidateCourses;
  final String scheduleStatus;
  final String scheduleNote;
  final String creditNote;
  final int remainingCourses;
  final int minimumSemesters;
  final bool fitsStandardProgramLength;
  final String graduationNote;
  final List<PlanTerm> path;
  final bool halfLoad;
  final bool acceleratedAllowed;
  final String graduationStatus;
  final String bestOptionId;
  final String graduationPolicyNote;
  final List<GraduationOption> graduationOptions;
}
