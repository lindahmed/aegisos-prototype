import type {
  Staff,
  CourseSection,
  Student,
  ScheduleSlot,
  ExamRecord,
  ExamCommittee,
  RequestRecord,
  Notification,
  Announcement,
} from '@staff/types'

export const staff: Staff = {
  id: 'STF-1042',
  staffId: '104217',
  fullName: 'Dr. Omar Fathallah',
  firstName: 'Omar',
  position: 'Associate Professor',
  academicRole: 'Course Coordinator — Software Engineering',
  department: 'Computer Engineering',
  college: 'College of Engineering & Technology',
  email: 'omar.fathallah@staff.aast.edu',
  phone: '+20 100 555 8842',
  office: 'Eng Building B — Room 312',
  avatarInitials: 'OF',
}

export const courseSections: CourseSection[] = [
  {
    id: 'sec1',
    code: 'CSE 301',
    title: 'Principles of Software Architecture',
    section: 'Sec 01',
    credits: 3,
    semester: 'Fall 2026',
    studentsCount: 37,
    schedule: [{ day: 'Sun', start: '09:00', end: '10:30' }, { day: 'Tue', start: '09:00', end: '10:30' }],
    room: 'Eng Building B — 214',
    status: 'Active',
    materials: [
      { name: 'Syllabus & Grading Policy', type: 'PDF' },
      { name: 'Week 6 — Layered Architecture', type: 'Slides' },
    ],
    assignments: [
      { name: 'Architecture Decision Record', due: 'Sep 02', submitted: 35, total: 37 },
      { name: 'Component Diagram Assignment', due: 'Sep 21', submitted: 20, total: 37 },
    ],
    announcements: [
      { title: 'Midterm review session added', date: '2026-08-24', body: 'An extra review session has been scheduled for Sep 8, 5 PM, room B-214.' },
    ],
  },
  {
    id: 'sec2',
    code: 'CSE 301',
    title: 'Principles of Software Architecture',
    section: 'Sec 02',
    credits: 3,
    semester: 'Fall 2026',
    studentsCount: 34,
    schedule: [{ day: 'Mon', start: '09:00', end: '10:30' }, { day: 'Wed', start: '09:00', end: '10:30' }],
    room: 'Eng Building B — 216',
    status: 'Active',
    materials: [{ name: 'Syllabus & Grading Policy', type: 'PDF' }],
    assignments: [{ name: 'Architecture Decision Record', due: 'Sep 02', submitted: 30, total: 34 }],
    announcements: [],
  },
  {
    id: 'sec3',
    code: 'CSE 450',
    title: 'Software Design Patterns',
    section: 'Sec 01',
    credits: 3,
    semester: 'Fall 2026',
    studentsCount: 28,
    schedule: [{ day: 'Sun', start: '11:00', end: '12:30' }, { day: 'Thu', start: '11:00', end: '12:30' }],
    room: 'Eng Building A — 108',
    status: 'Active',
    materials: [{ name: 'Design Patterns Reference Sheet', type: 'PDF' }],
    assignments: [{ name: 'Strategy Pattern Lab', due: 'Sep 12', submitted: 18, total: 28 }],
    announcements: [],
  },
  {
    id: 'sec4',
    code: 'CSE 210',
    title: 'Object-Oriented Programming',
    section: 'Sec 03',
    credits: 3,
    semester: 'Spring 2026',
    studentsCount: 40,
    schedule: [{ day: 'Tue', start: '13:00', end: '14:30' }],
    room: 'Eng Building A — 210',
    status: 'Completed',
    materials: [],
    assignments: [],
    announcements: [],
  },
]

const studentNames = [
  'Layla Ahmed El-Masry', 'Youssef Karim Adly', 'Mariam Hassan Reda', 'Ahmed Tarek Salem',
  'Nour Mohamed Fathy', 'Karim Sherif Anwar', 'Salma Adel Naguib', 'Omar Yasser Kabeel',
  'Farida Amr Zaki', 'Mostafa Hany Fouad', 'Rana Waleed Ismail', 'Ziad Mahmoud Elsayed',
  'Hana Khaled Mansour', 'Amir Nabil Gouda', 'Dina Ashraf Youssef', 'Adham Ehab Tawfik',
  'Malak Ahmed Rashad', 'Bassel Osama Farid', 'Jana Sameh Hosny', 'Seif Ayman Barakat',
]

export const students: Student[] = studentNames.map((name, i) => ({
  id: `st${i + 1}`,
  studentId: `2201${String(4400 + i).padStart(5, '0')}`,
  fullName: name,
  college: 'College of Engineering & Technology',
  department: 'Computer Engineering',
  level: 'Level 300 · Junior',
  section: i % 2 === 0 ? 'Sec 01' : 'Sec 02',
  email: `${name.split(' ')[0].toLowerCase()}.${name.split(' ')[1].toLowerCase()}@student.aast.edu`,
  attendancePct: [98, 95, 90, 88, 76, 65, 100, 92, 84, 70][i % 10],
  gradeStatus: (['Excellent', 'On Track', 'On Track', 'At Risk', 'Failing'] as const)[i % 5],
  courses: ['CSE 301', 'CSE 450'],
}))

export const scheduleSlots: ScheduleSlot[] = [
  { day: 'Sun', start: '09:00', end: '10:30', courseCode: 'CSE 301', courseTitle: 'Software Architecture', room: 'B-214', section: 'Sec 01', type: 'Lecture' },
  { day: 'Sun', start: '11:00', end: '12:30', courseCode: 'CSE 450', courseTitle: 'Design Patterns', room: 'A-108', section: 'Sec 01', type: 'Lecture' },
  { day: 'Mon', start: '09:00', end: '10:30', courseCode: 'CSE 301', courseTitle: 'Software Architecture', room: 'B-216', section: 'Sec 02', type: 'Lecture' },
  { day: 'Mon', start: '14:00', end: '15:30', courseCode: 'CSE 301', courseTitle: 'Office Hours', room: 'B-312', section: '—', type: 'Tutorial' },
  { day: 'Tue', start: '09:00', end: '10:30', courseCode: 'CSE 301', courseTitle: 'Software Architecture', room: 'B-214', section: 'Sec 01', type: 'Lecture' },
  { day: 'Wed', start: '09:00', end: '10:30', courseCode: 'CSE 301', courseTitle: 'Software Architecture', room: 'B-216', section: 'Sec 02', type: 'Lecture' },
  { day: 'Thu', start: '11:00', end: '12:30', courseCode: 'CSE 450', courseTitle: 'Design Patterns', room: 'A-108', section: 'Sec 01', type: 'Lecture' },
]

export const exams: ExamRecord[] = [
  { id: 'ex1', courseCode: 'CSE 301', courseTitle: 'Principles of Software Architecture', section: 'Sec 01', date: '2026-10-12', start: '09:00', end: '11:00', room: 'Exam Hall 1', type: 'Midterm', status: 'Upcoming' },
  { id: 'ex2', courseCode: 'CSE 301', courseTitle: 'Principles of Software Architecture', section: 'Sec 02', date: '2026-10-12', start: '09:00', end: '11:00', room: 'Exam Hall 2', type: 'Midterm', status: 'Upcoming' },
  { id: 'ex3', courseCode: 'CSE 450', courseTitle: 'Software Design Patterns', section: 'Sec 01', date: '2026-10-15', start: '13:00', end: '15:00', room: 'Exam Hall 1', type: 'Midterm', status: 'Upcoming' },
  { id: 'ex4', courseCode: 'CSE 210', courseTitle: 'Object-Oriented Programming', section: 'Sec 03', date: '2026-05-22', start: '09:00', end: '11:00', room: 'Exam Hall 3', type: 'Final', status: 'Completed' },
]

export const examCommittees: ExamCommittee[] = [
  { id: 'ec1', examCourse: 'MTH 250 — Probability & Statistics', role: 'Invigilator', date: '2026-10-16', room: 'Exam Hall 1' },
  { id: 'ec2', examCourse: 'CSE 340 — Operating Systems', role: 'Chief Invigilator', date: '2026-10-13', room: 'Exam Hall 2' },
  { id: 'ec3', examCourse: 'ENG 214 — Technical Report Writing', role: 'Committee Member', date: '2026-10-18', room: 'Exam Hall 3' },
]

export const requests: RequestRecord[] = [
  { id: 'req1', type: 'Leave Request', origin: 'staff', date: '2026-08-20', status: 'Approved', priority: 'Normal', details: 'Two-day academic conference leave, Oct 5–6.' },
  { id: 'req2', type: 'Room Change Request', origin: 'staff', date: '2026-08-22', status: 'Pending', priority: 'High', details: 'Requesting a larger room for CSE 301 Sec 01 due to enrollment increase.' },
  { id: 'req3', type: 'IT Support', origin: 'staff', date: '2026-08-18', status: 'In Progress', priority: 'Normal', details: 'Projector in B-214 intermittently loses signal.' },
  { id: 'req4', type: 'Grade Appeal Review', origin: 'student', originName: 'Ahmed Tarek Salem', date: '2026-08-25', status: 'Pending', priority: 'High', details: 'Student requests review of Assignment 2 grade in CSE 301.' },
  { id: 'req5', type: 'Attendance Excuse', origin: 'student', originName: 'Nour Mohamed Fathy', date: '2026-08-23', status: 'Pending', priority: 'Normal', details: 'Medical excuse submitted for Aug 20 absence, documentation attached.' },
  { id: 'req6', type: 'Makeup Exam Request', origin: 'student', originName: 'Karim Sherif Anwar', date: '2026-08-19', status: 'Completed', priority: 'Urgent', details: 'Approved makeup for missed midterm due to hospitalization.' },
]

export const notifications: Notification[] = [
  { id: 'n1', title: 'New grade appeal submitted — CSE 301', category: 'Requests', timestamp: '1h ago', read: false, body: 'Ahmed Tarek Salem submitted a grade appeal for Assignment 2.' },
  { id: 'n2', title: 'Department meeting rescheduled', category: 'Department', timestamp: '3h ago', read: false, body: 'The weekly CE department meeting moves to Wednesday 2 PM this week.' },
  { id: 'n3', title: 'Exam committee assignment confirmed', category: 'Academic', timestamp: '1d ago', read: false, body: 'You are assigned Chief Invigilator for CSE 340 on Oct 13.' },
  { id: 'n4', title: 'Faculty portal maintenance this weekend', category: 'System', timestamp: '2d ago', read: true, body: 'Brief downtime expected Saturday 2–4 AM.' },
  { id: 'n5', title: 'New university research grant announcement', category: 'University', timestamp: '4d ago', read: true, body: 'Applications for the 2027 internal research grant open next month.' },
]

export const announcements: Announcement[] = [
  { id: 'a1', title: 'Fall 2026 Grade Submission Deadline', category: 'Academic', date: '2026-08-24', body: 'All midterm grades must be submitted through the portal by October 20th. Late submissions require department head approval.', read: false },
  { id: 'a2', title: 'Faculty Development Workshop Series', category: 'University', date: '2026-08-20', body: 'A new series of teaching-excellence workshops begins in September. Registration is open to all academic staff.', read: false },
  { id: 'a3', title: 'CE Department Lab Equipment Upgrade', category: 'Department', date: '2026-08-17', body: 'The Software Engineering lab will receive new workstations over the mid-semester break. Expect limited access Oct 10–12.', read: true },
  { id: 'a4', title: 'Annual Faculty Recognition Ceremony', category: 'Events', date: '2026-08-12', body: 'This year\'s ceremony honoring outstanding faculty contributions will be held in the Main Auditorium on November 3rd.', read: true },
]
