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

The Staff Portal's **Course Materials** page uploads PDFs up to 10 MB to the main API (`backend.app`). The instructor must select a course. Students see the PDF in **Services → New Moodle** and **Documents** only while their enrollment in that course is `Current`. Every list and file request checks Supabase Auth and current enrollment on the server.

Run `database/migrations/add_portal_pdfs.sql` on the academic PostgreSQL database and populate `portal_instructor_courses` with the instructor's course assignments. Configure the API with `DATABASE_URL`, `SUPABASE_URL`, and the Supabase publishable key as `SUPABASE_ANON_KEY`. The portal uses its normal `VITE_API_BASE_URL` for PDFs; when unset, it uses the Railway API URL. The separate `VITE_PDF_API_BASE_URL` setting is no longer used.

PDF metadata is stored in PostgreSQL. File bytes are stored under `AEGIS_MATERIAL_STORAGE_ROOT/portal-pdfs` (default `workspace/materials/portal-pdfs`). Mount persistent private storage at that path in production so deployments do not erase uploaded files. Run `python -m pytest backend/test_portal_pdfs.py -q` to check upload, course visibility, download, and permission behavior.
