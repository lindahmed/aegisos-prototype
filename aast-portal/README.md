# AAST Portal

A unified web portal for the Arab Academy for Science, Technology & Maritime Transport, merging the former
**AAST Student Portal** and **AAST Staff Portal** into a single application with one login flow.

## Signing in

The login page is a two-step flow:

1. **Choose who you are** — Student or Staff.
2. **Enter your credentials** — the form labels adapt to the chosen role (Registration Number + PIN for
   students, Employee Number + Password for staff).

### Demo credentials (mock authentication, no real university connection)

| Role    | ID           | Password   |
| ------- | ------------ | ---------- |
| Student | `220104417`  | `1234`     |
| Staff   | `104217`     | `demo1234` |

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

- Default backend base URL: `http://127.0.0.1:8000`
- Override with `VITE_API_BASE_URL` if the API runs elsewhere.
- Demo student portal login `220104417` is linked to academic student record `231027905` in the backend seed data.

### Gradebook endpoints used by the portal

- `GET /portal/courses`
- `GET /portal/courses/{course_id}/grades`
- `PUT /portal/courses/{course_id}/grades`
- `GET /portal/students/{student_id}/grades`

This gives the staff portal and student portal one shared database path for grade entry and grade viewing.
