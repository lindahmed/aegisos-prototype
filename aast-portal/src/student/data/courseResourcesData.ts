export interface CourseResource {
  type: 'book' | 'video'
  title: string
  author?: string
  /** Free-text notes shown under the title, e.g. edition, channel name, or why it's useful. */
  note?: string
  url?: string
}

/**
 * Curated supplemental learning resources (textbooks + video lectures) for specific courses,
 * keyed by course_id / course code (e.g. "CSE340"). Add more entries here as needed —
 * any course without a specific entry falls back to `genericCourseResources` below.
 */
export const courseResourcesByCourseId: Record<string, CourseResource[]> = {
  CSE340: [
    {
      type: 'book',
      title: 'Operating System Concepts',
      author: 'Silberschatz, Galvin & Gagne',
      note: '10th Edition — the standard reference for this course',
      url: 'https://www.os-book.com/',
    },
    {
      type: 'video',
      title: 'Operating Systems: Crash Course Computer Science',
      note: 'Short conceptual overview before diving into the textbook',
      url: 'https://www.youtube.com/watch?v=JHYnkiZFOc0',
    },
    {
      type: 'video',
      title: 'MIT 6.828: Operating System Engineering',
      note: 'Full lecture series, great for deep dives on scheduling & memory',
      url: 'https://pdos.csail.mit.edu/6.828/',
    },
  ],
  MTH250: [
    {
      type: 'book',
      title: 'Introduction to Probability and Statistics',
      author: 'Mendenhall, Beaver & Beaver',
      note: '14th Edition',
    },
    {
      type: 'video',
      title: 'Statistics 110: Probability',
      note: 'Harvard\u2019s full open course, taught by Joe Blitzstein',
      url: 'https://projects.iq.harvard.edu/stat110/home',
    },
  ],
}

/** Shown for any course that doesn't have a curated entry above. */
export const genericCourseResources: CourseResource[] = [
  {
    type: 'book',
    title: 'Check your course syllabus for the assigned textbook',
    note: 'Your instructor\u2019s materials list on the Materials tab is the authoritative source',
  },
  {
    type: 'video',
    title: 'Search MIT OpenCourseWare for this subject',
    note: 'Free lecture videos and notes for most core CS, math, and engineering topics',
    url: 'https://ocw.mit.edu/',
  },
  {
    type: 'video',
    title: 'Search Khan Academy for foundational topics',
    note: 'Good for filling gaps in prerequisite material',
    url: 'https://www.khanacademy.org/',
  },
]

export function getCourseResources(courseId: string): CourseResource[] {
  return courseResourcesByCourseId[courseId.replace(/\s+/g, '').toUpperCase()] ?? genericCourseResources
}
