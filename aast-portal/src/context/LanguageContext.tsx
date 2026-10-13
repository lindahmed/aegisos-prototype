import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'

export type Language = 'en' | 'ar'

const STORAGE_KEY = 'aast-portal-language'

const arabicTranslations: Record<string, string> = {
  'AAST Portal': 'بوابة الأكاديمية',
  'AAST Portal home': 'الصفحة الرئيسية لبوابة الأكاديمية',
  'Student Portal': 'بوابة الطالب',
  'Staff Portal': 'بوابة أعضاء هيئة التدريس',
  'Student navigation': 'تنقل الطالب',
  'Staff navigation': 'تنقل أعضاء هيئة التدريس',
  'Breadcrumb': 'مسار التنقل',
  'Switch to Arabic': 'التبديل إلى العربية',
  'Switch to English': 'التبديل إلى الإنجليزية',
  'Dashboard': 'لوحة التحكم',
  'Overview': 'نظرة عامة',
  'Academics': 'الشؤون الأكاديمية',
  'Academic': 'أكاديمي',
  'Campus': 'الحرم الجامعي',
  'Account': 'الحساب',
  'Services': 'الخدمات',
  'All Services': 'جميع الخدمات',
  'Courses': 'المقررات',
  'My Courses': 'مقرراتي',
  'Course Sections': 'الشُعب الدراسية',
  'Course Materials': 'مواد المقرر',
  'Calendar': 'التقويم',
  'My Calendar': 'تقويمي',
  'Registration': 'التسجيل',
  'Course Registration': 'تسجيل المقررات',
  'Exams': 'الاختبارات',
  'Exam Schedule': 'جدول الاختبارات',
  'Exam Results': 'نتائج الاختبارات',
  'Exam Committees': 'لجان الاختبارات',
  'Exam Requests': 'طلبات الاختبارات',
  'Advisors': 'المرشدون',
  'Academic Advisors': 'المرشدون الأكاديميون',
  'Documents': 'المستندات',
  'Grades': 'الدرجات',
  'Attendance': 'الحضور',
  'Fees': 'الرسوم',
  'Fees & Financial': 'الرسوم والشؤون المالية',
  'Announcements': 'الإعلانات',
  'Notifications': 'الإشعارات',
  'Reports': 'التقارير',
  'Reports & Statistics': 'التقارير والإحصاءات',
  'Support': 'الدعم',
  'Support and inquiries': 'الدعم والاستفسارات',
  'Support and Inquiries': 'الدعم والاستفسارات',
  'Schedule': 'الجدول',
  'My Schedule': 'جدولي',
  'College Schedule': 'جدول الكلية',
  'Students': 'الطلاب',
  'Student List': 'قائمة الطلاب',
  'Student Search': 'البحث عن طالب',
  'Student Information': 'بيانات الطالب',
  'Academic Record': 'السجل الأكاديمي',
  'Student Requests': 'طلبات الطلاب',
  'Case Management': 'إدارة الحالات',
  'Requests': 'الطلبات',
  'Staff Services': 'خدمات أعضاء هيئة التدريس',
  'Profile': 'الملف الشخصي',
  'My Profile': 'ملفي الشخصي',
  'Update Data': 'تحديث البيانات',
  'Change Password': 'تغيير كلمة المرور',
  'Settings': 'الإعدادات',
  'View all': 'عرض الكل',
  'Loading notifications…': 'جارٍ تحميل الإشعارات…',
  'You are all caught up.': 'لا توجد إشعارات جديدة.',
  'Sign out': 'تسجيل الخروج',
  'Student': 'طالب',
  'Staff': 'عضو هيئة تدريس',
  'Search…': 'بحث…',
  'Clear search': 'مسح البحث',
  'Search services…': 'البحث في الخدمات…',
  'Search courses': 'البحث في المقررات',
  'Search advisors': 'البحث عن المرشدين',
  'Search by name or ID': 'البحث بالاسم أو الرقم',
  'Filters': 'عوامل التصفية',
  'Active': 'نشط',
  'Upcoming': 'قادم',
  'Completed': 'مكتمل',
  'Pending': 'قيد الانتظار',
  'Approved': 'مقبول',
  'Rejected': 'مرفوض',
  'Waitlisted': 'قائمة الانتظار',
  'On Track': 'على المسار الصحيح',
  'At Risk': 'معرّض للخطر',
  'Failing': 'متعثر',
  'Excellent': 'ممتاز',
  'In Progress': 'قيد الدراسة',
  'Previous': 'السابق',
  'Next': 'التالي',
  'Back': 'رجوع',
  'Cancel': 'إلغاء',
  'Save': 'حفظ',
  'Submit': 'إرسال',
  'Edit': 'تعديل',
  'Delete': 'حذف',
  'View': 'عرض',
  'Download': 'تنزيل',
  'Add event': 'إضافة حدث',
  'Plan with AI': 'التخطيط بالذكاء الاصطناعي',
  'Mark all as read': 'تحديد الكل كمقروء',
  'Sign In': 'تسجيل الدخول',
  'Sign in to your portal': 'سجّل الدخول إلى بوابتك',
  'First, tell us who you are.': 'أولاً، أخبرنا عن صفتك.',
  "I'm a student": 'أنا طالب',
  "I'm a staff member": 'أنا من أعضاء هيئة التدريس',
  'Registration Number': 'رقم التسجيل',
  'Employee Number': 'الرقم الوظيفي',
  'Login failed.': 'تعذّر تسجيل الدخول.',
  'Trouble signing in?': 'هل تواجه مشكلة في تسجيل الدخول؟',
  'Contact IT support': 'تواصل مع الدعم التقني',
  'One portal, for students & staff.': 'بوابة واحدة للطلاب وأعضاء هيئة التدريس.',
  'Sign in with your university account to access courses, grades, schedules, and university services — whether you study here or teach here.': 'سجّل الدخول بحسابك الجامعي للوصول إلى المقررات والدرجات والجداول وخدمات الجامعة، سواء كنت تدرس هنا أو تُدرّس فيها.',
  '© 2026 Arab Academy for Science, Technology & Maritime Transport. All rights reserved.': '© 2026 الأكاديمية العربية للعلوم والتكنولوجيا والنقل البحري. جميع الحقوق محفوظة.',
  'Register for courses, track grades, view your schedule, and manage tuition.': 'سجّل المقررات، وتابع الدرجات، واطّلع على جدولك، وأدر الرسوم الدراسية.',
  'Manage courses, attendance, grades, exam schedules, and student records.': 'أدر المقررات والحضور والدرجات وجداول الاختبارات وسجلات الطلاب.',
  'Everything you need to manage your student life, in one directory.': 'كل ما تحتاجه لإدارة حياتك الجامعية في مكان واحد.',
  'Important lecture changes and academic updates.': 'تغييرات المحاضرات المهمة وآخر المستجدات الأكاديمية.',
  'University, academic, and department-wide notices.': 'إعلانات الجامعة والشؤون الأكاديمية والأقسام.',
  'Academic records, transcripts, and financial statements.': 'السجلات الأكاديمية وكشوف الدرجات والبيانات المالية.',
  'Review your current balance and invoice history.': 'راجع رصيدك الحالي وسجل الفواتير.',
  'Find and contact the academic advisor for your department or program.': 'ابحث عن المرشد الأكاديمي لقسمك أو برنامجك وتواصل معه.',
  'Your assigned course sections across all semesters.': 'الشُعب الدراسية المسندة إليك عبر جميع الفصول.',
  'Search and browse students across your assigned sections.': 'ابحث وتصفح الطلاب في الشُعب المسندة إليك.',
  'Exam schedule, results, and committee assignments.': 'جدول الاختبارات والنتائج وتكليفات اللجان.',
  'Academic, attendance, and grade insights across your courses.': 'مؤشرات أكاديمية وتحليلات للحضور والدرجات في مقرراتك.',
  'Administrative and support services available to faculty and staff.': 'الخدمات الإدارية وخدمات الدعم المتاحة لأعضاء هيئة التدريس والموظفين.',
  'Manage your notification and portal preferences.': 'إدارة تفضيلات الإشعارات والبوابة.',
  'Your personal, academic, and contact information.': 'بياناتك الشخصية والأكاديمية وبيانات التواصل.',
  'View and manage your personal, academic, and contact information.': 'عرض وإدارة بياناتك الشخصية والأكاديمية وبيانات التواصل.',
  'Update your contact information.': 'تحديث بيانات التواصل الخاصة بك.',
  'Update the password for your staff portal account.': 'تحديث كلمة مرور حساب بوابة أعضاء هيئة التدريس.',
  'Requests, academic updates, and department notices.': 'الطلبات والمستجدات الأكاديمية وإعلانات القسم.',
  'Grade updates, registration alerts, and system notices.': 'تحديثات الدرجات وتنبيهات التسجيل وإشعارات النظام.',
  "Track requests you've submitted and requests awaiting your review.": 'تابع طلباتك والطلبات التي تنتظر مراجعتك.',
  'Reach out to IT, HR, or academic affairs with a question or issue.': 'تواصل مع تقنية المعلومات أو الموارد البشرية أو الشؤون الأكاديمية لأي استفسار أو مشكلة.',
  'Master timetables published across departments in the college.': 'الجداول الرئيسية المنشورة لأقسام الكلية.',
  'Your weekly teaching schedule for Fall 2026.': 'جدول التدريس الأسبوعي لفصل خريف 2026.',
  'Add or drop courses for Fall 2026. Changes are saved instantly.': 'أضف أو احذف مقررات فصل خريف 2026. تُحفظ التغييرات فورًا.',
  'Could not load your academic data.': 'تعذّر تحميل بياناتك الأكاديمية.',
  'Loading your academic data…': 'جارٍ تحميل بياناتك الأكاديمية…',
  'Loading your profile…': 'جارٍ تحميل ملفك الشخصي…',
  'Loading…': 'جارٍ التحميل…',
  'No announcements': 'لا توجد إعلانات',
  'No services found': 'لم يتم العثور على خدمات',
  'No students found': 'لم يتم العثور على طلاب',
  'No advisors found': 'لم يتم العثور على مرشدين',
  'Try a different search term.': 'جرّب عبارة بحث مختلفة.',
  'Try a different search term or filter.': 'جرّب عبارة بحث أو عامل تصفية مختلفًا.',
  'Language': 'اللغة',
  'English': 'الإنجليزية',
  'Arabic': 'العربية',
  'Choose your preferred portal display language.': 'اختر لغة عرض البوابة المفضلة لديك.',
  'Language preference updated.': 'تم تحديث تفضيل اللغة.',
  'Course': 'المقرر',
  'Coursework (/10)': 'أعمال الفصل (/10)',
  'Week 7 exam (/30)': 'اختبار الأسبوع 7 (/30)',
  'Week 12 exam (/20)': 'اختبار الأسبوع 12 (/20)',
  'Final exam (/40)': 'الاختبار النهائي (/40)',
  'Total (/100)': 'المجموع (/100)',
  'Grade': 'التقدير',
  'GPA': 'المعدل التراكمي',
  'Instructor': 'المحاضر',
  'Room': 'القاعة',
  'Credits': 'الساعات',
  'Status': 'الحالة',
  'Action': 'الإجراء',
  'Drop': 'حذف',
  'Section': 'الشعبة',
  'Date': 'التاريخ',
  'Time': 'الوقت',
  'Type': 'النوع',
  'ID': 'الرقم',
  'Level': 'المستوى',
  'Sun': 'الأحد',
  'Mon': 'الاثنين',
  'Tue': 'الثلاثاء',
  'Wed': 'الأربعاء',
  'Thu': 'الخميس',
  'Notification Preferences': 'تفضيلات الإشعارات',
  'Email Notifications': 'إشعارات البريد الإلكتروني',
  'Receive email copies of important portal notifications.': 'استلم نسخًا بالبريد الإلكتروني من إشعارات البوابة المهمة.',
  'Student Request Alerts': 'تنبيهات طلبات الطلاب',
  'Get notified immediately when a student submits a request.': 'استلم إشعارًا فور إرسال أحد الطلاب طلبًا.',
  'Weekly Summary Digest': 'الملخص الأسبوعي',
  'Receive a weekly summary of attendance and grading activity.': 'استلم ملخصًا أسبوعيًا لنشاط الحضور والدرجات.',
  'Open Registration': 'فتح التسجيل',
  'Registered Courses': 'المقررات المسجلة',
  'No registered courses found in the academic database.': 'لا توجد مقررات مسجلة في قاعدة البيانات الأكاديمية.',
  'Health': 'المؤشر',
  "Today's Classes": 'محاضرات اليوم',
  "Today's Schedule": 'جدول اليوم',
  'Full calendar': 'التقويم الكامل',
  'Full schedule': 'الجدول الكامل',
  'No classes scheduled for today. Enjoy the break.': 'لا توجد محاضرات اليوم. استمتع بالراحة.',
  'No classes scheduled for today.': 'لا توجد محاضرات اليوم.',
  'Upcoming Exams': 'الاختبارات القادمة',
  'All': 'الكل',
  'No new announcements.': 'لا توجد إعلانات جديدة.',
  'Quick Actions': 'إجراءات سريعة',
  'Transcript': 'كشف الدرجات',
  'Pay Fees': 'دفع الرسوم',
  'GPA Calculator': 'حاسبة المعدل',
  'Clinic Booking': 'حجز العيادة',
  'Take Attendance': 'تسجيل الحضور',
  'Assigned Courses': 'المقررات المسندة',
  'Total Students': 'إجمالي الطلاب',
  'Across all sections': 'في جميع الشُعب',
  'Pending Requests': 'الطلبات المعلقة',
  'Unread Notifications': 'الإشعارات غير المقروءة',
  'Enter Grades': 'إدخال الدرجات',
  'View Schedule': 'عرض الجدول',
  'View Students': 'عرض الطلاب',
  'Submit Request': 'إرسال طلب',
  'No data': 'لا توجد بيانات',
  'Critical': 'حرج',
  'students': 'طلاب',
}

function translateDynamic(value: string): string | undefined {
  const welcome = value.match(/^Welcome back, (.+)$/)
  if (welcome) return `مرحبًا بعودتك، ${welcome[1]}`

  const signInAs = value.match(/^Sign in as (student|staff)$/)
  if (signInAs) return signInAs[1] === 'student' ? 'تسجيل الدخول كطالب' : 'تسجيل الدخول كعضو هيئة تدريس'

  const enterId = value.match(/^Enter your (.+) to continue\.$/)
  if (enterId) return `أدخل ${arabicTranslations[enterId[1]] ?? enterId[1]} للمتابعة.`

  const coursesFor = value.match(/^Your enrolled courses for (.+)\.$/)
  if (coursesFor) return `مقرراتك المسجلة لفصل ${coursesFor[1]}.`

  return undefined
}

interface LanguageContextValue {
  language: Language
  isRtl: boolean
  setLanguage: (language: Language) => void
  toggleLanguage: () => void
  t: (value: string) => string
}

const LanguageContext = createContext<LanguageContextValue | null>(null)

export function LanguageProvider({ children }: { children: ReactNode }) {
  const [language, setLanguage] = useState<Language>(() => {
    const saved = window.localStorage.getItem(STORAGE_KEY)
    return saved === 'ar' ? 'ar' : 'en'
  })

  useEffect(() => {
    window.localStorage.setItem(STORAGE_KEY, language)
    document.documentElement.lang = language
    document.documentElement.dir = language === 'ar' ? 'rtl' : 'ltr'
  }, [language])

  const value = useMemo<LanguageContextValue>(() => ({
    language,
    isRtl: language === 'ar',
    setLanguage,
    toggleLanguage: () => setLanguage((current) => current === 'en' ? 'ar' : 'en'),
    t: (text) => language === 'ar' ? arabicTranslations[text] ?? translateDynamic(text) ?? text : text,
  }), [language])

  return <LanguageContext.Provider value={value}>{children}</LanguageContext.Provider>
}

export function useLanguage() {
  const context = useContext(LanguageContext)
  if (!context) throw new Error('useLanguage must be used within LanguageProvider')
  return context
}
