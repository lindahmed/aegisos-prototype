export interface Advisor {
  id: string
  name: string
  title: string
  department: string
  email: string
  phone: string
  office: string
  officeHours: string
  bio: string
}

export const advisors: Advisor[] = [
  {
    id: 'adv1',
    name: 'Dr. Mona El-Sherif',
    title: 'Academic Advisor',
    department: 'Computer Science & Engineering',
    email: 'm.elsherif@aast.edu',
    phone: '+20 3 555 0142',
    office: 'Building C, Room 214',
    officeHours: 'Sun & Tue, 11:00 AM – 1:00 PM',
    bio: 'Handles registration holds, course substitutions, and academic probation plans for CSE students.',
  },
  {
    id: 'adv2',
    name: 'Dr. Hassan Fathy',
    title: 'Academic Advisor',
    department: 'Electrical & Communication Engineering',
    email: 'h.fathy@aast.edu',
    phone: '+20 3 555 0187',
    office: 'Building B, Room 108',
    officeHours: 'Mon & Wed, 10:00 AM – 12:00 PM',
    bio: 'Primary advisor for ECE undergraduates; also coordinates minor-study applications.',
  },
  {
    id: 'adv3',
    name: 'Eng. Nourhan Adel',
    title: 'Academic Advisor',
    department: 'Business Informatics',
    email: 'n.adel@aast.edu',
    phone: '+20 3 555 0163',
    office: 'Building A, Room 305',
    officeHours: 'Sun–Thu, 9:00 AM – 10:30 AM',
    bio: 'Supports course planning, internship credit approvals, and graduation audits.',
  },
  {
    id: 'adv4',
    name: 'Dr. Youssef Kamel',
    title: 'Senior Academic Advisor',
    department: 'Maritime Studies',
    email: 'y.kamel@aast.edu',
    phone: '+20 3 555 0129',
    office: 'Building D, Room 12',
    officeHours: 'Tue & Thu, 1:00 PM – 3:00 PM',
    bio: 'Oversees academic planning for Maritime Studies and cross-department transfers.',
  },
  {
    id: 'adv5',
    name: 'Dr. Salma Ibrahim',
    title: 'Academic Advisor',
    department: 'Basic & Applied Sciences',
    email: 's.ibrahim@aast.edu',
    phone: '+20 3 555 0155',
    office: 'Building A, Room 118',
    officeHours: 'Mon, Wed & Sun, 11:30 AM – 1:00 PM',
    bio: 'Advises first- and second-year students before they declare a major department.',
  },
]

export const advisorDepartments = ['All', ...Array.from(new Set(advisors.map((a) => a.department)))]
