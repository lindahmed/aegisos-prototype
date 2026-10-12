import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _languagePreferenceKey = 'app_language';

class AppLanguageController extends ValueNotifier<Locale> {
  AppLanguageController() : super(const Locale('en'));

  bool get isArabic => value.languageCode == 'ar';
  String get advisorLanguage => isArabic ? 'arabic' : 'english';

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    value = Locale(
      preferences.getString(_languagePreferenceKey) == 'ar' ? 'ar' : 'en',
    );
  }

  Future<void> setLanguage(String languageCode) async {
    final normalized = languageCode == 'ar' ? 'ar' : 'en';
    if (value.languageCode != normalized) value = Locale(normalized);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_languagePreferenceKey, normalized);
  }
}

final appLanguageController = AppLanguageController();

bool get isArabicApp => appLanguageController.isArabic;

bool containsArabic(String text) =>
    RegExp(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]').hasMatch(text);

String tr(String english, [String? arabic]) {
  if (!isArabicApp) return english;
  if (arabic != null) return arabic;
  return _translateDynamic(english);
}

String _translateDynamic(String text) {
  final exact = _arabicText[text];
  if (exact != null) return exact;

  final week = RegExp(r'^Week (\d+) of (\d+)$').firstMatch(text);
  if (week != null) return 'الأسبوع ${week.group(1)} من ${week.group(2)}';

  final semesterProgress = RegExp(r'^(\d+)% of the semester timeline$')
      .firstMatch(text);
  if (semesterProgress != null) {
    return '${semesterProgress.group(1)}٪ من الفصل الدراسي';
  }

  final risks = RegExp(
    r'^(\d+) risks? · Tap to see why and recommended actions$',
  ).firstMatch(text);
  if (risks != null) {
    return '${risks.group(1)} مخاطر · اضغطي لمعرفة السبب والإجراءات المقترحة';
  }

  final priorities = RegExp(r'^(\d+) / (\d+) priorities completed$')
      .firstMatch(text);
  if (priorities != null) {
    return 'اكتمل ${priorities.group(1)} من ${priorities.group(2)} أولويات';
  }

  final greeting = RegExp(r'^Hi (.+), what can I help you solve\?$')
      .firstMatch(text);
  if (greeting != null) return 'أهلًا ${greeting.group(1)}، كيف أقدر أساعدك؟';

  final advisorGreeting = RegExp(r'^How can I help, (.+)\?$').firstMatch(text);
  if (advisorGreeting != null) {
    return 'كيف أقدر أساعدك يا ${advisorGreeting.group(1)}؟';
  }

  final study = RegExp(r'^Study (.+)$').firstMatch(text);
  if (study != null) return 'مذاكرة ${study.group(1)}';

  final selected = RegExp(r'^(\d+) selected$').firstMatch(text);
  if (selected != null) return 'تم اختيار ${selected.group(1)}';

  final credits = RegExp(r'^(\d+) / (\d+) CREDITS$').firstMatch(text);
  if (credits != null) return '${credits.group(1)} / ${credits.group(2)} ساعة';

  final semesterWeek = RegExp(r'^(.+) · Week (\d+)$').firstMatch(text);
  if (semesterWeek != null) {
    return '${semesterWeek.group(1)} · الأسبوع ${semesterWeek.group(2)}';
  }

  final registeredCourses = RegExp(r'^(\d+) registered courses?$')
      .firstMatch(text);
  if (registeredCourses != null) {
    return '${registeredCourses.group(1)} مقرر مسجل';
  }

  final activeCourses = RegExp(r'^(\d+) active courses?$').firstMatch(text);
  if (activeCourses != null) return '${activeCourses.group(1)} مقرر نشط';

  final enrolledCourses = RegExp(r'^(\d+) enrolled courses?$').firstMatch(text);
  if (enrolledCourses != null) {
    return '${enrolledCourses.group(1)} مقرر مسجل';
  }

  final activeCourseOwner = RegExp(r'^(.+), these are your active courses\.$')
      .firstMatch(text);
  if (activeCourseOwner != null) {
    return '${activeCourseOwner.group(1)}، هذه هي مقرراتك النشطة.';
  }

  final classmates = RegExp(r'^(\d+) classmates$').firstMatch(text);
  if (classmates != null) return '${classmates.group(1)} زملاء';

  final group = RegExp(r'^Group (.+)$').firstMatch(text);
  if (group != null) return 'المجموعة ${group.group(1)}';

  final weekPlan = RegExp(r'^WEEK (\d+) PLAN$').firstMatch(text);
  if (weekPlan != null) return 'خطة الأسبوع ${weekPlan.group(1)}';

  final focus = RegExp(r'^(.+), focus on what matters most\.$')
      .firstMatch(text);
  if (focus != null) return '${focus.group(1)}، ركّزي على الأهم الآن.';

  final remainingPriority = RegExp(
    r'^(\d+) priorit(?:y|ies) remaining this week\.$',
  ).firstMatch(text);
  if (remainingPriority != null) {
    return 'متبقي ${remainingPriority.group(1)} من الأولويات هذا الأسبوع.';
  }

  final currentGpa = RegExp(r'^Current GPA: (.+)$').firstMatch(text);
  if (currentGpa != null) return 'المعدل الحالي: ${currentGpa.group(1)}';

  final hypotheticalGrade = RegExp(r'^Hypothetical grade: (.+)$')
      .firstMatch(text);
  if (hypotheticalGrade != null) {
    return 'الدرجة الافتراضية: ${hypotheticalGrade.group(1)}';
  }

  final impact = RegExp(r'^Impact: (.+)$').firstMatch(text);
  if (impact != null) return 'التأثير: ${impact.group(1)}';

  final semesterNumber = RegExp(r'^SEMESTER (\d+) OF (\d+)$').firstMatch(text);
  if (semesterNumber != null) {
    return 'الفصل ${semesterNumber.group(1)} من ${semesterNumber.group(2)}';
  }

  final curriculum = RegExp(r'^Curriculum S(.+)$').firstMatch(text);
  if (curriculum != null) return 'الخطة الدراسية - فصل ${curriculum.group(1)}';

  final creditHours = RegExp(r'^(\d+) CR$').firstMatch(text);
  if (creditHours != null) return '${creditHours.group(1)} ساعات';

  final courseCount = RegExp(
    r'^(\d+) courses · blocked courses show what is missing$',
  ).firstMatch(text);
  if (courseCount != null) {
    return '${courseCount.group(1)} مقررات · المقررات غير المتاحة توضح المتطلبات الناقصة';
  }

  final termSummary = RegExp(r'^(\d+) courses · (\d+) estimated credits$')
      .firstMatch(text);
  if (termSummary != null) {
    return '${termSummary.group(1)} مقررات · ${termSummary.group(2)} ساعة تقديرية';
  }

  final routePlan = RegExp(r'^(.+) plan$').firstMatch(text);
  if (routePlan != null) return 'خطة ${routePlan.group(1)}';

  final activeRisks = RegExp(r'^(\d+) active risks?$').firstMatch(text);
  if (activeRisks != null) return '${activeRisks.group(1)} مخاطر نشطة';

  final courseRisks = RegExp(r'^(.+) risks$').firstMatch(text);
  if (courseRisks != null) return 'مخاطر ${courseRisks.group(1)}';

  final explainedRisk = RegExp(r'^(.+) risk explained$').firstMatch(text);
  if (explainedRisk != null) return 'شرح مخاطر ${explainedRisk.group(1)}';

  final riskCount = RegExp(
    r'^(\d+) active risks? with clear reasons and next actions\.$',
  ).firstMatch(text);
  if (riskCount != null) {
    return '${riskCount.group(1)} مخاطر نشطة مع أسباب واضحة وخطوات مقترحة.';
  }

  final lowAssessment = RegExp(
    r'^(.+) is ([\d.]+)%, below the configured ([\d.]+)% threshold\.$',
  ).firstMatch(text);
  if (lowAssessment != null) {
    if (lowAssessment.group(1) == 'Assignment average' ||
        lowAssessment.group(1) == 'Lab average') {
      final type = lowAssessment.group(1) == 'Lab average'
          ? 'المعمل'
          : 'التكليفات';
      return 'متوسط $type ${lowAssessment.group(2)}٪، وهو أقل من الحد المحدد ${lowAssessment.group(3)}٪.';
    }
    return '${lowAssessment.group(1)} درجته ${lowAssessment.group(2)}٪، وهي أقل من الحد المحدد ${lowAssessment.group(3)}٪.';
  }

  final courseworkDrop = RegExp(
    r'^(.+) is ([\d.]+) percentage points below the recorded coursework average of ([\d.]+)%\.$',
  ).firstMatch(text);
  if (courseworkDrop != null) {
    return '${courseworkDrop.group(1)} أقل بـ ${courseworkDrop.group(2)} نقطة مئوية من متوسط أعمال الفصل المسجل ${courseworkDrop.group(3)}٪.';
  }

  final averageRisk = RegExp(
    r'^(Assignment|Lab) average is ([\d.]+)%, below the configured ([\d.]+)% threshold\.$',
  ).firstMatch(text);
  if (averageRisk != null) {
    final type = averageRisk.group(1) == 'Lab' ? 'المعمل' : 'التكليفات';
    return 'متوسط $type ${averageRisk.group(2)}٪، وهو أقل من الحد المحدد ${averageRisk.group(3)}٪.';
  }

  final lectureBacklog = RegExp(
    r'^(\d+) of (\d+) available lectures are not marked complete\.$',
  ).firstMatch(text);
  if (lectureBacklog != null) {
    return '${lectureBacklog.group(1)} من ${lectureBacklog.group(2)} محاضرات متاحة لم تُحدد كمكتملة.';
  }

  final missingGrades = RegExp(
    r'^(\d+) due assessment\(s\) do not have a recorded grade\.$',
  ).firstMatch(text);
  if (missingGrades != null) {
    return '${missingGrades.group(1)} تقييمات مستحقة ليس لها درجة مسجلة.';
  }

  final poorAssessments = RegExp(
    r'^(\d+) recorded assessments are below ([\d.]+)%\.$',
  ).firstMatch(text);
  if (poorAssessments != null) {
    return '${poorAssessments.group(1)} تقييمات مسجلة أقل من ${poorAssessments.group(2)}٪.';
  }

  final healthDecrease = RegExp(
    r'^Course health decreased from ([\d.]+) to ([\d.]+) since the previous snapshot\.$',
  ).firstMatch(text);
  if (healthDecrease != null) {
    return 'انخفض مستوى المقرر من ${healthDecrease.group(1)} إلى ${healthDecrease.group(2)} منذ آخر تحديث.';
  }

  final dueCoverage = RegExp(
    r'^(.+) is due in week (\d+)[; and]+ (\d+) covered lecture\(s\) are not complete\.$',
  ).firstMatch(text);
  if (dueCoverage != null) {
    return '${dueCoverage.group(1)} مستحق في الأسبوع ${dueCoverage.group(2)}، و${dueCoverage.group(3)} محاضرات ضمن المحتوى غير مكتملة.';
  }

  final deadlineCluster = RegExp(
    r'^(\d+) assessments are due in week (\d+); plan study time across them\.$',
  ).firstMatch(text);
  if (deadlineCluster != null) {
    return '${deadlineCluster.group(1)} تقييمات مستحقة في الأسبوع ${deadlineCluster.group(2)}؛ وزّعي وقت المذاكرة بينها.';
  }

  final healthHistory = RegExp(
    r'^Course health has declined for (\d+) consecutive snapshots from ([\d.]+) to ([\d.]+)\.$',
  ).firstMatch(text);
  if (healthHistory != null) {
    return 'انخفض مستوى المقرر خلال ${healthHistory.group(1)} تحديثات متتالية من ${healthHistory.group(2)} إلى ${healthHistory.group(3)}.';
  }

  final metric = RegExp(
    r'^(Course health|Previous health|Current weighted grade|Lecture completion): ([\d.]+)%$',
  ).firstMatch(text);
  if (metric != null) {
    final label = switch (metric.group(1)) {
      'Course health' => 'مستوى المقرر',
      'Previous health' => 'المستوى السابق',
      'Current weighted grade' => 'الدرجة الموزونة الحالية',
      _ => 'اكتمال المحاضرات',
    };
    return '$label: ${metric.group(2)}٪';
  }

  final maximumCredits = RegExp(
    r'^Remove a course to stay within the (\d+)-credit maximum\.$',
  ).firstMatch(text);
  if (maximumCredits != null) {
    return 'احذفي مقررًا للالتزام بحد ${maximumCredits.group(1)} ساعة.';
  }

  final monthYear = RegExp(r'^([A-Za-z]+) (\d{4})$').firstMatch(text);
  if (monthYear != null && _arabicText.containsKey(monthYear.group(1))) {
    return '${_arabicText[monthYear.group(1)]} ${monthYear.group(2)}';
  }

  final fullDate = RegExp(r'^([A-Za-z]+), ([A-Za-z]+) (\d+)$').firstMatch(text);
  if (fullDate != null) {
    final day = _arabicText[fullDate.group(1)] ?? fullDate.group(1)!;
    final month = _arabicText[fullDate.group(2)] ?? fullDate.group(2)!;
    return '$day، ${fullDate.group(3)} $month';
  }

  final timedStudyTask = RegExp(
    r'^(Today|Tomorrow|Later this week) · (\d+) min — (.+)$',
  ).firstMatch(text);
  if (timedStudyTask != null) {
    final timing = _arabicText[timedStudyTask.group(1)]!;
    final minutes = timedStudyTask.group(2)!;
    final instruction = _translateWeeklyInstruction(timedStudyTask.group(3)!);
    return '$timing · $minutes دقيقة — $instruction';
  }

  final reviewMistakes = RegExp(r'^Review (.+) mistakes$').firstMatch(text);
  if (reviewMistakes != null) {
    final subject = reviewMistakes.group(1)!;
    return 'راجعي أخطاء ${_arabicText[subject] ?? subject}';
  }

  final practiceQuestions = RegExp(r'^Practice (.+) questions$')
      .firstMatch(text);
  if (practiceQuestions != null) {
    final subject = practiceQuestions.group(1)!;
    return 'تدرّبي على أسئلة ${_arabicText[subject] ?? subject}';
  }

  final completeCoverage = RegExp(r'^Complete (.+) coverage$').firstMatch(text);
  if (completeCoverage != null) {
    final subject = completeCoverage.group(1)!;
    return 'أكملي تغطية ${_arabicText[subject] ?? subject}';
  }

  final startAssessment = RegExp(r'^Start (.+)$').firstMatch(text);
  if (startAssessment != null) {
    final subject = startAssessment.group(1)!;
    return 'ابدئي ${_arabicText[subject] ?? subject}';
  }

  final prepareAssessment = RegExp(r'^Prepare for (.+)$').firstMatch(text);
  if (prepareAssessment != null) {
    final subject = prepareAssessment.group(1)!;
    return 'استعدي لـ ${_arabicText[subject] ?? subject}';
  }

  final unreadMessages = RegExp(r'^(\d+) unread$').firstMatch(text);
  if (unreadMessages != null) {
    return '${unreadMessages.group(1)} رسائل غير مقروءة';
  }

  final meetingCount = RegExp(r'^(\d+) in meeting$').firstMatch(text);
  if (meetingCount != null) {
    return '${meetingCount.group(1)} في الاجتماع';
  }

  final meetingAttendance = RegExp(r'^(\d+) admitted · (\d+) waiting$')
      .firstMatch(text);
  if (meetingAttendance != null) {
    return '${meetingAttendance.group(1)} مشاركون · ${meetingAttendance.group(2)} في الانتظار';
  }

  final mediaOn = RegExp(r'^(Microphone|Camera|Screen sharing) on\.$')
      .firstMatch(text);
  if (mediaOn != null) {
    return '${_arabicText[mediaOn.group(1)] ?? mediaOn.group(1)} يعمل الآن.';
  }

  final mediaUnavailable = RegExp(
    r'^(Microphone|Camera|Screen sharing) unavailable: (.+)$',
  ).firstMatch(text);
  if (mediaUnavailable != null) {
    return '${_arabicText[mediaUnavailable.group(1)] ?? mediaUnavailable.group(1)} غير متاح: ${mediaUnavailable.group(2)}';
  }

  final yearLevel = RegExp(r'^Year (\d+)$').firstMatch(text);
  if (yearLevel != null) return 'السنة ${yearLevel.group(1)}';

  return text;
}

String _translateWeeklyInstruction(String instruction) {
  final exact = _arabicText[instruction];
  if (exact != null) return exact;
  final pending = RegExp(
    r'^finish the next incomplete lecture, make a short summary, and answer 3 recall questions\. Start with one of the (\d+) pending lectures\.$',
  ).firstMatch(instruction);
  if (pending != null) {
    return 'أكملي المحاضرة التالية غير المكتملة، واكتبي ملخصًا قصيرًا، ثم أجيبي عن 3 أسئلة استرجاع. ابدئي بواحدة من ${pending.group(1)} محاضرات متأخرة.';
  }
  return instruction;
}

const _arabicText = <String, String>{
  'Home': 'الرئيسية',
  'Today': 'اليوم',
  'Progress': 'التقدم',
  'Progress & Risks': 'التقدم والمخاطر',
  'AI Advisor': 'المستشار الذكي',
  'Academics': 'الدراسة',
  'Profile': 'الملف الشخصي',
  'Student Profile': 'الملف الشخصي',
  'Good morning': 'صباح الخير',
  'Good afternoon': 'مساء الخير',
  'Good evening': 'مساء الخير',
  "TODAY'S CALENDAR": 'تقويم اليوم',
  'No Calendar events scheduled for today.': 'لا توجد أحداث في تقويم اليوم.',
  'YOUR WEEK': 'أسبوعك',
  'Ask AI': 'اسألي الذكاء الاصطناعي',
  'WEEK PLANNER': 'مخطط الأسبوع',
  "Review priorities and complete this week's study tasks":
      'راجعي الأولويات وأكملي مهام المذاكرة لهذا الأسبوع',
  'Completed': 'المكتمل',
  'Courses': 'المقررات',
  'Course': 'المقرر',
  'Midterm': 'الاختبار النصفي',
  'Final exam': 'الاختبار النهائي',
  'exam': 'الاختبار',
  'Current semester': 'الفصل الحالي',
  'Fall': 'خريف',
  'Spring': 'ربيع',
  'Summer': 'صيف',
  'Winter': 'شتاء',
  'LIVE': 'مباشر',
  'Course performance': 'أداء المقررات',
  'Health, completion, and explained academic risks':
      'مستوى الأداء والإنجاز وشرح المخاطر الأكاديمية',
  'No live course progress is available yet.':
      'لا توجد بيانات مباشرة لتقدم المقررات حتى الآن.',
  'Lectures': 'المحاضرات',
  'Assessments': 'التقييمات',
  'Try asking': 'جرّبي أن تسألي',
  'Explain my academic progress': 'اشرح تقدمي الأكاديمي',
  'Plan what I should study today': 'خطط لما أذاكره اليوم',
  'Show my highest-priority course': 'اعرض المقرر الأعلى أولوية',
  'Start a conversation': 'ابدئي محادثة',
  'Ask about your courses, grades, risks, timetable, or study priorities. Answers use your current academic data.': 'اسألي عن المقررات أو الدرجات أو المخاطر أو الجدول أو أولويات المذاكرة. الإجابات تعتمد على بياناتك الأكاديمية الحالية.',
  'Ask about semester planning, careers, courses, or your academic progress.':
      'اسألي عن تخطيط الفصل أو المسار المهني أو المقررات أو تقدمك الأكاديمي.',
  'CORE ACADEMICS': 'البيانات الأكاديمية',
  'Classes and grades': 'المحاضرات والدرجات',
  'One clear place for official university information.':
      'مكان واحد واضح لمعلومات الجامعة الرسمية.',
  'Class Timetable': 'جدول المحاضرات',
  'Courses, lecture times, sections, labs, and rooms':
      'المقررات ومواعيد المحاضرات والسكاشن والمعامل والقاعات',
  'Grades': 'الدرجات',
  'Official marks, course grades, and semester GPA':
      'الدرجات الرسمية ونتائج المقررات والمعدل الفصلي',
  'PLAN & PREPARE': 'التخطيط والاستعداد',
  'Planning tools': 'أدوات التخطيط',
  'Personal planning, separate from your class timetable.':
      'تخطيطك الشخصي منفصل عن جدول المحاضرات.',
  'Calendar': 'التقويم',
  'Academic deadlines and events you add':
      'المواعيد الأكاديمية والأحداث التي تضيفينها',
  'Academic Roadmap': 'الخطة الأكاديمية',
  'Future courses, prerequisites, and graduation routes':
      'المقررات القادمة والمتطلبات ومسارات التخرج',
  'Grade Simulator': 'محاكي الدرجات',
  'Preview grade impact': 'اعرفي تأثير الدرجات المتوقعة',
  'Program': 'البرنامج',
  'Level': 'المستوى',
  'Sign out': 'تسجيل الخروج',
  'Notifications': 'الإشعارات',
  'Mark all read': 'تحديد الكل كمقروء',
  'All': 'الكل',
  'Unread': 'غير المقروء',
  'No notifications yet.': 'لا توجد إشعارات حتى الآن.',
  'No notifications in this view.': 'لا توجد إشعارات في هذا العرض.',
  'Add to Calendar': 'إضافة إلى التقويم',
  'View Courses': 'عرض المقررات',
  'Week Planner': 'مخطط الأسبوع',
  'Listening… Tap stop to send': 'أستمع… اضغطي إيقاف للإرسال',
  'Reading response aloud': 'جارٍ قراءة الرد بصوت عالٍ',
  'Stop speaking': 'إيقاف الصوت',
  'Ask your advisor...': 'اكتبي سؤالك للمستشار...',
  'Send': 'إرسال',
  'Add study session': 'إضافة جلسة مذاكرة',
  'Date': 'التاريخ',
  'Start time': 'وقت البداية',
  'Duration': 'المدة',
  '30 minutes': '30 دقيقة',
  '45 minutes': '45 دقيقة',
  '1 hour': 'ساعة',
  '1.5 hours': 'ساعة ونصف',
  '1 hour 30 minutes': 'ساعة ونصف',
  '2 hours': 'ساعتان',
  'Cancel': 'إلغاء',
  'Add to calendar': 'إضافة إلى التقويم',
  'Calendar event added.': 'تمت إضافة الحدث إلى التقويم.',
  'Add event': 'إضافة حدث',
  'Previous month': 'الشهر السابق',
  'Next month': 'الشهر التالي',
  'Exam': 'امتحان',
  'Deadline': 'موعد تسليم',
  'Study session': 'جلسة مذاكرة',
  'Personal': 'شخصي',
  'Personal event': 'حدث شخصي',
  'Add calendar event': 'إضافة حدث للتقويم',
  'Event title': 'عنوان الحدث',
  'Try again': 'حاولي مرة أخرى',
  'Weekly timetable': 'الجدول الأسبوعي',
  'Registered courses': 'المقررات المسجلة',
  'No active courses': 'لا توجد مقررات نشطة',
  'Provisional': 'مؤقت',
  'Refresh timetable': 'تحديث الجدول',
  'Enrolled Courses': 'المقررات المسجلة',
  'Refresh courses': 'تحديث المقررات',
  'Your courses': 'مقرراتك',
  'Only the courses currently registered to your account.':
      'المقررات المسجلة حاليًا في حسابك فقط.',
  'Enrolled': 'مسجل',
  'No enrolled courses were found.': 'لم يتم العثور على مقررات مسجلة.',
  'Student sign in': 'تسجيل دخول الطالب',
  'Use your university Student ID and password.':
      'استخدمي الرقم الجامعي وكلمة المرور.',
  'Student ID': 'الرقم الجامعي',
  'Password': 'كلمة المرور',
  'Sign in': 'تسجيل الدخول',
  'Secure connection to UNI Track': 'اتصال آمن بمنصة UNI Track',
  'Guide. Track. Evolve.': 'توجيه. متابعة. تطور.',
  'Your academic companion': 'رفيقك الأكاديمي',
  'STUDENT PORTAL': 'بوابة الطالب',
  'Welcome back': 'مرحبًا بعودتك',
  'Sign in to continue your academic journey.':
      'سجّلي الدخول لمتابعة رحلتك الأكاديمية.',
  'Your semester, progress, and AI advisor are ready.':
      'فصلك الدراسي وتقدمك ومستشارك الذكي جاهزون.',
  'Remember me': 'تذكرني',
  'Student ID only': 'الرقم الجامعي فقط',
  'Results & Grades': 'الدرجات',
  'Courses Achieved': 'المقررات المكتملة',
  '7th Week': 'الأسبوع السابع',
  '12th Week': 'الأسبوع الثاني عشر',
  'Course Work': 'أعمال الفصل',
  'Recommended courses': 'المقررات المقترحة',
  'No remaining recommended courses': 'لا توجد مقررات مقترحة متبقية',
  'Load & GPA preview': 'معاينة العبء والمعدل',
  'Credit-hour estimate': 'تقدير الساعات المعتمدة',
  'Schedule check': 'فحص الجدول',
  'Overlapping timetable slots are detected automatically.':
      'يتم اكتشاف تعارضات الجدول تلقائيًا.',
  'Accelerated Graduation Path': 'مسار التخرج المعجّل',
  'Credits': 'الساعات',
  'Projected GPA': 'المعدل المتوقع',
  'Regular terms': 'الفصول العادية',
  'Current GPA': 'المعدل الحالي',
  'Timetable data unavailable': 'بيانات الجدول غير متاحة',
  'Refresh plan': 'تحديث الخطة',
  'No assessments are available to simulate.':
      'لا توجد تقييمات متاحة للمحاكاة.',
  'Calculating…': 'جارٍ الحساب…',
  'Run simulation': 'تشغيل المحاكاة',
  'Weighted grade': 'الدرجة الموزونة',
  'Course health': 'مستوى المقرر',
  'Live academic update': 'آخر تحديث أكاديمي مباشر',
  'DATABASE': 'قاعدة البيانات',
  'Academic health': 'المستوى الأكاديمي',
  'Active risks': 'المخاطر النشطة',
  'CURRENT RECOMMENDATION': 'التوصية الحالية',
  'No recommendation is available yet.': 'لا توجد توصية متاحة حتى الآن.',
  'Latest recorded trend': 'أحدث اتجاه مسجل',
  'Latest advisor follow-up': 'أحدث متابعة من المستشار',
  'Week': 'الأسبوع',
  'improving': 'يتحسن',
  'stable': 'مستقر',
  'declining': 'يتراجع',
  'new': 'جديد',
  'active': 'نشط',
  'resolved': 'تمت المعالجة',
  'WHY?': 'لماذا؟',
  'RECOMMENDED ACTIONS': 'الإجراءات المقترحة',
  'Build Recovery Plan': 'إنشاء خطة تحسين',
  'Add Study Session': 'إضافة جلسة مذاكرة',
  'Fix This Risk': 'معالجة هذا الخطر',
  'Assessment': 'التقييم',
  'Semesters': 'الفصول الدراسية',
  'No semesters are available yet.': 'لا توجد فصول دراسية حتى الآن.',
  'No course results are available for this semester.':
      'لا توجد نتائج مقررات لهذا الفصل.',
  'Academic information': 'المعلومات الأكاديمية',
  'Expected average': 'المتوسط المتوقع',
  'BEST OPTION': 'أفضل اختيار',
  'Other curriculum courses': 'مقررات أخرى من الخطة الدراسية',
  'Prerequisites': 'المتطلبات السابقة',
  'Plan with confidence': 'خططي بثقة',
  'Select courses and preview the academic impact before registration.':
      'اختاري المقررات وراجعي تأثيرها الأكاديمي قبل التسجيل.',
  'Built from your curriculum, completed courses, and prerequisites.':
      'مبنية على خطتك الدراسية والمقررات المكتملة والمتطلبات السابقة.',
  'Your database record has no uncompleted curriculum courses to plan.':
      'لا توجد مقررات غير مكتملة في سجلك تحتاج إلى تخطيط.',
  'GPA below 2.0 activates a 9-credit limit—normally 3 courses.':
      'المعدل الأقل من 2.0 يفعّل حد 9 ساعات، أي 3 مقررات عادةً.',
  'Adjust the selected courses and expected average grade.':
      'عدّلي المقررات المختارة ومتوسط الدرجة المتوقع.',
  'Your 9-credit half-load route is the only available path until your GPA reaches 2.0.':
      'مسار 9 ساعات هو المسار المتاح حتى يصل معدلك إلى 2.0.',
  'Compare normal study, a higher workload, and each available summer.':
      'قارني بين الدراسة العادية والعبء الأعلى والفصول الصيفية المتاحة.',
  'No remaining terms': 'لا توجد فصول متبقية',
  'Route unavailable': 'المسار غير متاح',
  'UNAVAILABLE': 'غير متاح',
  'Half-load rule: because your GPA is below 2.0, you can select up to 9 credits—usually 3 courses. The limit is removed only after your GPA returns to 2.0 or higher.': 'قاعدة العبء المخفف: لأن معدلك أقل من 2.0 يمكنك اختيار 9 ساعات بحد أقصى، أي 3 مقررات عادةً. يُلغى الحد عندما يعود معدلك إلى 2.0 أو أكثر.',
  'Grade Impact Simulator': 'محاكي تأثير الدرجات',
  'TEST A FUTURE RESULT': 'اختبري نتيجة مستقبلية',
  'Read-only projection — no official grade is changed.':
      'توقع للعرض فقط — لن تتغير أي درجة رسمية.',
  'PROJECTED IMPACT': 'التأثير المتوقع',
  'Your priorities': 'أولوياتك',
  'Your progress is saved and a fresh plan appears each week.':
      'يُحفظ تقدمك وتظهر خطة جديدة كل أسبوع.',
  'No urgent risks or upcoming ungraded assessments were found.':
      'لا توجد مخاطر عاجلة أو تقييمات قريبة بدون درجات.',
  'You are on track': 'أنتِ على المسار الصحيح',
  'Academic deadlines appear automatically. Personal events are the ones you add here; weekly priorities stay in Week Planner.': 'تظهر المواعيد الأكاديمية تلقائيًا. الأحداث الشخصية هي التي تضيفينها هنا، وتبقى الأولويات الأسبوعية في مخطط الأسبوع.',
  'SELECTED DAY': 'اليوم المحدد',
  'No events on this day.': 'لا توجد أحداث في هذا اليوم.',
  'Notes (optional)': 'ملاحظات (اختياري)',
  'Event type': 'نوع الحدث',
  'Add event on selected day': 'إضافة حدث في اليوم المحدد',
  'Enter an event title.': 'اكتبي عنوان الحدث.',
  'Everything academic, organised': 'كل بياناتك الأكاديمية منظمة',
  'Open the exact record or planning tool you need.':
      'افتحي السجل أو أداة التخطيط التي تحتاجينها مباشرةً.',
  'Courses and timetable in one place': 'المقررات والجدول في مكان واحد',
  'My schedule group': 'مجموعة جدولي',
  'Waiting for university times': 'في انتظار مواعيد الجامعة',
  'Your timetable updates automatically from university data.':
      'يتحدث جدولك تلقائيًا من بيانات الجامعة.',
  'Class timetable not published yet': 'جدول المحاضرات لم يُنشر بعد',
  'Class times not published for your group':
      'مواعيد المحاضرات لم تُنشر لمجموعتك بعد',
  'Your registered courses are available below. Class days, times, and rooms will appear here automatically when the university publishes them.': 'مقرراتك المسجلة ظاهرة بالأسفل. ستظهر الأيام والمواعيد والقاعات تلقائيًا عندما تنشرها الجامعة.',
  'Your schedule group is available, but the university API currently returns no class-time slots for these courses.': 'مجموعة جدولك موجودة، لكن بيانات الجامعة لا تحتوي حاليًا على مواعيد لهذه المقررات.',
  'The detailed group timetable is temporarily unavailable. Course times shown above are still current.': 'تفاصيل جدول المجموعة غير متاحة مؤقتًا. المواعيد الظاهرة بالأعلى ما زالت الحالية.',
  'Some times are provisional and will update automatically when the university publishes final times.':
      'بعض المواعيد مؤقتة وستتحدث تلقائيًا عند نشر المواعيد النهائية.',
  'No current registrations were found in your university record.':
      'لم يتم العثور على تسجيلات حالية في سجلك الجامعي.',
  'Show password': 'إظهار كلمة المرور',
  'Hide password': 'إخفاء كلمة المرور',
  'Enter your student ID.': 'اكتبي الرقم الجامعي.',
  'Enter your password.': 'اكتبي كلمة المرور.',
  'Something went wrong. Please try again.': 'حدث خطأ. حاولي مرة أخرى.',
  'Still signing you in securely. The university service is taking longer than usual…':
      'ما زلنا نسجل دخولك بأمان. خدمة الجامعة تستغرق وقتًا أطول من المعتاد…',
  'Could not save the study session.': 'تعذر حفظ جلسة المذاكرة.',
  'Could not save the Calendar session.': 'تعذر حفظ جلسة التقويم.',
  'Refresh class timetable': 'تحديث جدول المحاضرات',
  'Discard recording': 'حذف التسجيل',
  'Stop and send recording': 'إيقاف التسجيل وإرساله',
  'Record a question': 'تسجيل سؤال',
  'Close notifications': 'إغلاق الإشعارات',
  'You are all caught up. No notifications match this filter.':
      'لا توجد إشعارات مطابقة لهذا الاختيار.',
  'AegisOS Student Companion': 'مساعد الطالب AegisOS',
  'Sunday': 'الأحد',
  'Monday': 'الاثنين',
  'Tuesday': 'الثلاثاء',
  'Wednesday': 'الأربعاء',
  'Thursday': 'الخميس',
  'Friday': 'الجمعة',
  'Saturday': 'السبت',
  'Sun': 'الأحد',
  'Mon': 'الاثنين',
  'Tue': 'الثلاثاء',
  'Wed': 'الأربعاء',
  'Thu': 'الخميس',
  'Fri': 'الجمعة',
  'Sat': 'السبت',
  'January': 'يناير',
  'February': 'فبراير',
  'March': 'مارس',
  'April': 'أبريل',
  'May': 'مايو',
  'June': 'يونيو',
  'July': 'يوليو',
  'August': 'أغسطس',
  'September': 'سبتمبر',
  'October': 'أكتوبر',
  'November': 'نوفمبر',
  'December': 'ديسمبر',
  'Help me plan my next semester': 'ساعدني في تخطيط الفصل القادم',
  'What careers match my major?': 'ما الوظائف المناسبة لتخصصي؟',
  'How can I improve my academic progress?': 'كيف أحسن تقدمي الأكاديمي؟',
  'Tomorrow': 'غدًا',
  'Later this week': 'لاحقًا هذا الأسبوع',
  'Strengthen assignment skills': 'قوّي مهارات حل التكليفات',
  'Practice the latest lab': 'تدرّبي على آخر معمل',
  'Catch up on pending lectures': 'عوضي المحاضرات المتأخرة',
  'Check overdue assessment work': 'راجعي التقييم المتأخر',
  'Run a focused revision session': 'اعملي جلسة مراجعة مركزة',
  "Reset this course's study plan": 'أعيدي تنظيم خطة مذاكرة المقرر',
  'Plan upcoming deadlines': 'خططي للمواعيد النهائية القادمة',
  'Restore your lecture pace': 'استعيدي انتظامك في المحاضرات',
  'Strengthen this course this week': 'قوّي مستواك في هذا المقرر هذا الأسبوع',
  'revisit the covered topics, redo difficult questions, and write down 3 weak points.': 'راجعي الموضوعات التي تمت تغطيتها، وأعيدي حل الأسئلة الصعبة، واكتبي 3 نقاط ضعف.',
  'solve 5 exam-style questions without notes, then check and correct every mistake.':
      'حلي 5 أسئلة بنمط الامتحان من غير ملاحظات، ثم راجعي وصححي كل خطأ.',
  'redo one weak assignment section and compare your solution with the course material.':
      'أعيدي جزءًا ضعيفًا من التكليف وقارني حلك بمادة المقرر.',
  'repeat the latest lab exercise from scratch and note anything you still need to ask about.': 'أعيدي تمرين المعمل الأخير من البداية وسجلي أي نقطة ما زلتِ تحتاجين للسؤال عنها.',
  'finish the next incomplete lecture, make a short summary, and answer 3 recall questions.': 'أكملي المحاضرة التالية غير المكتملة، واكتبي ملخصًا قصيرًا، ثم أجيبي عن 3 أسئلة استرجاع.',
  'confirm the submission or grade status, then write the exact next action and deadline.': 'تأكدي من حالة التسليم أو الدرجة، ثم اكتبي الخطوة التالية والموعد النهائي بدقة.',
  'choose the two weakest topics, review one worked example for each, then solve one question alone.': 'اختاري أضعف موضوعين، وراجعي مثالًا محلولًا لكل منهما، ثم حلي سؤالًا بنفسك.',
  'list unfinished work, choose the top two priorities, and reserve study blocks for both.': 'اكتبي الأعمال غير المكتملة، واختاري أهم أولويتين، وحددي وقت مذاكرة لكل منهما.',
  'finish one uncovered topic, summarize it in 5 lines, and solve 3 related questions.':
      'أنهي موضوعًا غير مغطى، ولخصيه في 5 سطور، ثم حلي 3 أسئلة مرتبطة به.',
  'review the requirements, finish the next covered topic, and begin the first section.':
      'راجعي المتطلبات، وأنهي الموضوع التالي، وابدئي الجزء الأول.',
  'split each assessment into small steps and assign one step to every available study block.':
      'قسّمي كل تقييم إلى خطوات صغيرة ووزعي خطوة على كل وقت مذاكرة متاح.',
  'complete the next lecture and schedule the following one before the end of the week.':
      'أكملي المحاضرة التالية وحددي موعدًا لما بعدها قبل نهاية الأسبوع.',
  'review your weakest topic, solve 3 practice questions, and record what still needs work.': 'راجعي أضعف موضوع لديك، وحلي 3 أسئلة تدريب، وسجلي ما يحتاج إلى عمل إضافي.',
  'review the requirements, complete the next section, and leave time for a final check.':
      'راجعي المتطلبات، وأكملي الجزء التالي، واتركي وقتًا للمراجعة النهائية.',
  'review the covered material and begin the first practice or work section.':
      'راجعي المادة التي تمت تغطيتها وابدئي أول جزء من التدريب أو العمل.',
  'LIVE DATA': 'بيانات مباشرة',
  'This course already has a priority in Week Planner.':
      'هذا المقرر موجود بالفعل ضمن أولويات مخطط الأسبوع.',
  'This course already has a priority in Week Planner. This calendar session will be an additional scheduled time.': 'هذا المقرر موجود بالفعل في مخطط الأسبوع. ستكون جلسة التقويم وقتًا إضافيًا للمذاكرة.',
  'AI SCHEDULED · URGENT': 'مجدول بالذكاء الاصطناعي · عاجل',
  'ACADEMIC CALENDAR': 'التقويم الأكاديمي',
  'MY EVENT': 'حدثي',
  'Messages': 'الرسائل',
  'Campus Messages': 'رسائل الجامعة',
  'Campus communication': 'التواصل الجامعي',
  'Chat with professors and classmates': 'تواصلي مع الأساتذة والزملاء',
  'Live Meetings': 'الاجتماعات المباشرة',
  'Host or join lectures and study rooms':
      'أنشئي أو انضمي إلى محاضرات وغرف مذاكرة',
  'Host or join a live meeting': 'أنشئي اجتماعًا مباشرًا أو انضمي إليه',
  'Start a room, approve participants, and control speaking and presenting permissions.':
      'ابدئي غرفة وتحكمي في قبول المشاركين وصلاحيات التحدث والعرض.',
  'HOST A MEETING': 'إنشاء اجتماع',
  'Meeting title': 'عنوان الاجتماع',
  'Start meeting': 'بدء الاجتماع',
  'JOIN A MEETING': 'الانضمام إلى اجتماع',
  'Meeting invitation': 'رابط دعوة الاجتماع',
  'Request to join': 'طلب الانضمام',
  'For nearby devices, keep the host and participants on the same Wi-Fi network. Internet meetings require the public WSS and TURN setup described by the desktop meeting service.': 'للأجهزة القريبة، يجب أن يكون المضيف والمشاركون على شبكة Wi‑Fi نفسها. الاجتماعات عبر الإنترنت تحتاج إعداد WSS وTURN العام الموجود في خدمة اجتماعات سطح المكتب.',
  'Participants': 'المشاركون',
  'INVITATION': 'الدعوة',
  'Copy invitation': 'نسخ الدعوة',
  'Invitation copied.': 'تم نسخ الدعوة.',
  'Mute': 'كتم الصوت',
  'Unmute': 'تشغيل الصوت',
  'Camera off': 'إيقاف الكاميرا',
  'Camera on': 'تشغيل الكاميرا',
  'Stop sharing': 'إيقاف المشاركة',
  'Share screen': 'مشاركة الشاشة',
  'Lower hand': 'خفض اليد',
  'Raise hand': 'رفع اليد',
  'Whiteboard': 'السبورة',
  'End': 'إنهاء',
  'Leave': 'مغادرة',
  'End meeting?': 'إنهاء الاجتماع؟',
  'Leave meeting?': 'مغادرة الاجتماع؟',
  'This will end the meeting for everyone.':
      'سيؤدي هذا إلى إنهاء الاجتماع للجميع.',
  'You can rejoin later with the invitation.':
      'يمكنك الانضمام مرة أخرى باستخدام الدعوة.',
  'End for everyone': 'إنهاء للجميع',
  'Mute all': 'كتم صوت الجميع',
  'Waiting for the host to approve your request':
      'في انتظار موافقة المضيف على طلبك',
  'Your camera and microphone stay off until you are admitted.':
      'ستظل الكاميرا والميكروفون متوقفين حتى يتم قبولك.',
  'Your meeting is live': 'اجتماعك مباشر الآن',
  'You are in the meeting': 'أنتِ داخل الاجتماع',
  'Share the invitation and approve participants when they arrive.':
      'شاركي الدعوة ووافقي على المشاركين عند وصولهم.',
  'Camera and shared screens will appear here.':
      'ستظهر الكاميرات والشاشات التي تتم مشاركتها هنا.',
  'Host': 'المضيف',
  'Waiting for approval': 'في انتظار الموافقة',
  'Speaking': 'يتحدث',
  'Muted': 'مكتوم الصوت',
  'May present': 'يمكنه العرض',
  'View only': 'مشاهدة فقط',
  'Speaking · May present': 'يتحدث · يمكنه العرض',
  'Speaking · View only': 'يتحدث · مشاهدة فقط',
  'Muted · May present': 'مكتوم الصوت · يمكنه العرض',
  'Muted · View only': 'مكتوم الصوت · مشاهدة فقط',
  'Revoke speaking': 'إلغاء صلاحية التحدث',
  'Allow speaking': 'السماح بالتحدث',
  'Revoke presenting': 'إلغاء صلاحية العرض',
  'Allow presenting': 'السماح بالعرض',
  'Remove': 'إزالة',
  'Admit': 'قبول',
  'Decline': 'رفض',
  'Clear whiteboard': 'مسح السبورة',
  'The host must allow presenting before you can draw.':
      'يجب أن يسمح لكِ المضيف بالعرض قبل الرسم.',
  'You': 'أنتِ',
  'Screen': 'الشاشة',
  'Microphone': 'الميكروفون',
  'Camera': 'الكاميرا',
  'Screen sharing': 'مشاركة الشاشة',
  'Host a meeting or paste an invitation.':
      'أنشئي اجتماعًا أو الصقي رابط دعوة.',
  'Starting meeting…': 'جارٍ بدء الاجتماع…',
  'Meeting started. Share the invitation and approve requests.':
      'بدأ الاجتماع. شاركي الدعوة ووافقي على الطلبات.',
  'Connecting to the host…': 'جارٍ الاتصال بالمضيف…',
  'Join request sent. Please wait for host approval.':
      'تم إرسال طلب الانضمام. انتظري موافقة المضيف.',
  'Meeting connection lost. Rejoin with your invitation.':
      'انقطع اتصال الاجتماع. أعيدي الانضمام باستخدام الدعوة.',
  'Meeting connection lost.': 'انقطع اتصال الاجتماع.',
  'The host declined your request.': 'رفض المضيف طلب انضمامك.',
  'The host disconnected. The lecture has ended.':
      'انقطع اتصال المضيف وانتهت المحاضرة.',
  'The host ended the lecture.': 'أنهى المضيف المحاضرة.',
  'The host removed you from the lecture.': 'أزالكِ المضيف من المحاضرة.',
  'Meeting ended.': 'انتهى الاجتماع.',
  'Cannot reach the meeting host.': 'تعذر الوصول إلى مضيف الاجتماع.',
  'Cannot reach the meeting host. Check the address and network.':
      'تعذر الوصول إلى مضيف الاجتماع. راجعي الرابط والشبكة.',
  'Paste a valid meeting invitation.': 'الصقي رابط دعوة صحيحًا.',
  'Paste the complete meeting invitation.': 'الصقي رابط الدعوة كاملًا.',
  'Use a ws:// or wss:// meeting address.':
      'استخدمي رابط اجتماع يبدأ بـ ws:// أو wss://.',
  'Wait for host approval.': 'انتظري موافقة المضيف.',
  'The host must allow you to speak.': 'يجب أن يسمح لكِ المضيف بالتحدث.',
  'The host must allow screen sharing.':
      'يجب أن يسمح لكِ المضيف بمشاركة الشاشة.',
  'Meeting is disconnected.': 'الاجتماع غير متصل.',
  'The meeting host did not provide media configuration.':
      'لم يرسل مضيف الاجتماع إعدادات الوسائط.',
  'Search professors or classmates': 'ابحثي عن أستاذ أو زميل',
  'Clear search': 'مسح البحث',
  'CONVERSATIONS': 'المحادثات',
  'Professor announcements': 'إعلانات الأساتذة',
  'Messages sent to all students': 'رسائل مرسلة لجميع الطلاب',
  'Professor': 'أستاذ',
  'Student': 'طالب',
  'You are all caught up.': 'اطّلعتِ على كل الرسائل.',
  'Refresh messages': 'تحديث الرسائل',
  'Write a message…': 'اكتبي رسالة…',
  'Send message': 'إرسال الرسالة',
  'Professor announcements are read-only.': 'إعلانات الأساتذة للقراءة فقط.',
  'Finish the next incomplete lecture.': 'أكملي المحاضرة التالية غير المكتملة.',
  'Reserve a focused study session.': 'حددي جلسة مذاكرة مركزة.',
  'Ask AI for a catch-up plan.':
      'اطلبي من الذكاء الاصطناعي خطة لتعويض التأخير.',
  'Review the weakest assessed topics.':
      'راجعي أضعف الموضوعات التي تم تقييمها.',
  'Redo practice questions without notes.':
      'أعيدي حل أسئلة التدريب دون ملاحظات.',
  'Schedule two short revision sessions.': 'حددي جلستين قصيرتين للمراجعة.',
  'Complete one uncovered topic first.': 'أكملي أولًا موضوعًا لم تتم تغطيته.',
  'Create a five-line summary.': 'اكتبي ملخصًا من خمسة أسطر.',
  'Solve three related questions.': 'حلي ثلاثة أسئلة مرتبطة بالموضوع.',
  'Review the risk evidence.': 'راجعي أسباب الخطر.',
  'Add one focused study session.': 'أضيفي جلسة مذاكرة مركزة.',
  'Use Week Planner to prioritize the next action.':
      'استخدمي مخطط الأسبوع لتحديد أولوية الخطوة التالية.',
  'Attach document': 'إرفاق مستند',
  'Remove attachment': 'إزالة المرفق',
  'Choose a PDF, Word, spreadsheet, presentation, or text document.':
      'اختاري ملف PDF أو Word أو جدولًا أو عرضًا تقديميًا أو ملفًا نصيًا.',
  'Documents must be 10 MB or smaller.':
      'يجب ألا يزيد حجم المستند عن 10 ميجابايت.',
  'The selected document is empty.': 'المستند المحدد فارغ.',
  'No message contacts are available yet.': 'لا توجد جهات اتصال متاحة بعد.',
  'Start the conversation with a clear question or update.':
      'ابدئي المحادثة بسؤال أو تحديث واضح.',
  'Unavailable': 'غير متاح',
  'Switch to light mode': 'التبديل إلى الوضع الفاتح',
  'Switch to dark mode': 'التبديل إلى الوضع الداكن',
};

class AppText extends StatelessWidget {
  const AppText(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Locale>(
    valueListenable: appLanguageController,
    builder: (context, appLocale, _) => Text(
      tr(data),
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale ?? appLocale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    ),
  );

  static TextSpan span(String text, {TextStyle? style}) =>
      TextSpan(text: tr(text), style: style);
}

class AppLanguageToggleButton extends StatelessWidget {
  const AppLanguageToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ValueListenableBuilder<Locale>(
      valueListenable: appLanguageController,
      builder: (context, locale, _) {
        final arabic = locale.languageCode == 'ar';
        return Semantics(
          label: arabic ? 'تغيير اللغة إلى الإنجليزية' : 'Switch to Arabic',
          button: true,
          child: InkWell(
            key: const Key('app-language-toggle'),
            onTap: () =>
                appLanguageController.setLanguage(arabic ? 'en' : 'ar'),
            borderRadius: BorderRadius.circular(22),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    arabic ? '🇬🇧' : '🇪🇬',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    arabic ? 'EN' : 'ع',
                    style: TextStyle(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
