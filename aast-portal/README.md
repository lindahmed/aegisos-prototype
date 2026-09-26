# AAST Portal

A unified web portal for the Arab Academy for Science, Technology & Maritime Transport, merging the former
**AAST Student Portal** and **AAST Staff Portal** into a single application with one login flow.

## Signing in

The login page is a two-step flow:

1. **Choose who you are** — Student or Staff.
2. **Enter your credentials** — the form labels adapt to the chosen role (Registration Number + PIN for
   students, Employee Number + Password for staff).

Both roles now sign in through Supabase Auth using the hidden ID based email described below. The account must exist in the configured Supabase project; the former demo passwords are not portal credentials.

## Tech stack

- [React 18](https://react.dev) + [TypeScript](https://www.typescriptlang.org)
- [Vite](https://vitejs.dev)
- [React Router](https://reactrouter.com)
- [Tailwind CSS](https://tailwindcss.com)
- [lucide-react](https://lucide.dev) icons

## Project structure

```
src/
├── App.tsx                    # Root routing — mounts the portal matching the logged-in role
├── main.tsx                   # Entry point
├── index.css                  # Shared global styles (Tailwind)
├── context/AuthContext.tsx    # Unified auth: role ('student' | 'staff'), login, logout
├── pages/Login.tsx            # Two-step login: role selection, then ID + password
├── router/ProtectedRoute.tsx  # Redirects unauthenticated visitors to /login
├── components/ui/             # Components shared by both portals (Button)
├── student/                   # Student portal (pages, components, data, types)
│   └── StudentRoutes.tsx      # Student routes + student ToastProvider
└── staff/                     # Staff portal (pages, components, data, types)
    └── StaffRoutes.tsx        # Staff routes + staff ToastProvider
```

Import aliases: `@/` → `src/`, `@student/` → `src/student/`, `@staff/` → `src/staff/`.

Both portals keep their original top-level paths (`/`, `/courses`, `/grades`, …). Only the routes of the
logged-in role are mounted at a time, so the paths never collide.

## Getting started

```bash
npm install
npm run dev      # start the dev server
npm run build    # type-check and build for production
npm run preview  # preview the production build
```

## Backend connection

The portal grade pages now read and write through the existing FastAPI backend instead of local mock grade data.

- Default backend base URL: `https://web-production-3a6ad.up.railway.app`
- Override with `VITE_API_BASE_URL` to use a local backend or another API. The retired
  `backend-production-6069` Railway URL is automatically replaced in production.
- Demo student portal login `220104417` is linked to academic student record `231027905` in the backend seed data.

### Gradebook endpoints used by the portal

- `GET /portal/courses`
- `GET /portal/courses/{course_id}/grades`
- `PUT /portal/courses/{course_id}/grades`
- `GET /portal/students/{student_id}/grades`

This gives the staff portal and student portal one shared database path for grade entry and grade viewing.

## Instructor PDFs

The Staff Portal's **Course Materials** page uploads PDFs (maximum 10 MB) to the FastAPI server's private material directory. The Student Portal's **Documents** page lists eligible PDFs and refreshes when focused or every 30 seconds. Course PDFs are visible only to students with a `Current` enrollment; PDFs without a course are visible to all signed-in students. View and download requests check permissions again on the server.

Setup:

1. Configure the backend with `DATABASE_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `AEGIS_STAFF_IDS`, and `AEGIS_MATERIAL_STORAGE_ROOT` (see the repository root `.env.example`). Put the material directory on a persistent private volume in production. Every API replica must access the same volume.
2. Configure this Vite app from `aast-portal/.env.example` with the same Supabase project and the backend URL. Restart the Vite server after changing env values.
3. Start the backend; its database initialization creates `portal_pdfs` and `portal_instructor_courses` in PostgreSQL or SQLite. For a manual PostgreSQL deployment, run `database/migrations/add_portal_pdfs.sql` once before deploying the new backend.
4. Create each staff user in Supabase Auth using the administrator interface with email `<employee_id>@staff.aegisos.local`. Set **app_metadata** (administrator controlled, not user metadata) to `{"portal_role":"staff","portal_id":"<employee_id>"}`. Add the employee ID to `AEGIS_STAFF_IDS`. Existing student Auth accounts must be linked to `user_profiles` in PostgreSQL; the local SQLite prototype requires administrator set `app_metadata` of `{"portal_role":"student","portal_id":"<student_id>"}` on each student account.
5. Assign real course codes to instructors in the database, for example `INSERT INTO portal_instructor_courses (instructor_id, course_id) VALUES ('104217', 'CAI3101') ON CONFLICT DO NOTHING;`. Use a `course_id` present in the database's `courses` table (or `course_offerings` for SQLite). Staff can upload course PDFs only for assigned courses. A PDF with no course is shared with all signed-in students.

The old staff demo password endpoint remains for existing integrations, but portal sign-in now uses Supabase Auth for staff. The PDF endpoints never accept the demo password. To verify locally, sign in as an assigned instructor, upload a PDF, then sign in as one enrolled and one unenrolled student and compare the Documents page. `python -m pytest backend/test_portal_pdfs.py -q` exercises upload, storage, visibility, view, download, permissions, deletion, and invalid files.
