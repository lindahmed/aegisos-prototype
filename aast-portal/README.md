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

`backend.portal_pdf_service` handles PDFs separately from the academic API. The Staff Portal's **Course Materials** page accepts PDFs up to 10 MB. Students see them in **Services → New Moodle** as well as **Documents**; both refresh on focus or every 30 seconds. PDF files and JSON metadata live in `workspace/materials/portal-pdfs` by default. No database connection, migration, or academic table change is used.

The current audience is **All students**. Course-specific uploads are disabled until a trusted instructor/course assignment source is provided; they are never silently made public. Only the owning instructor can view or delete a staff PDF. Any confirmed, academic-API-recognized student account can view a general PDF. All file endpoints check Supabase Auth on the server.

Local setup:

1. In the repository root `.env`, set `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `AEGIS_STAFF_IDS` (see `.env.example`). The student and staff portals must use the same Supabase project. Do not put the service-role key in the Vite app.
2. In `aast-portal/.env`, set `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, and `VITE_PDF_API_BASE_URL=http://127.0.0.1:8000`. Leave `VITE_API_BASE_URL` unset to keep academic data on the original Railway API. Restart Vite after changing `.env`.
3. From the repository root, run `python -m uvicorn backend.portal_pdf_service:app --host 127.0.0.1 --port 8000`. Separately run `npm run dev -- --host 127.0.0.1 --port 5174` in `aast-portal`.
4. Sign in as staff and upload a PDF. Sign in as a student and open **Services → New Moodle** to see it. Run `python -m pytest backend/test_portal_pdf_service.py -q` for automated upload, persistence, visibility, download, deletion, permission, and invalid-file checks.

For students on other devices, deploy this PDF service at a network-accessible HTTPS URL, set `VITE_PDF_API_BASE_URL` to that URL, set `AEGIS_PORTAL_ORIGINS` to the portal origin, and use a persistent private volume for `AEGIS_PDF_STORAGE_ROOT`. A `127.0.0.1` URL works only on the same machine; ephemeral host storage would lose uploaded files.
