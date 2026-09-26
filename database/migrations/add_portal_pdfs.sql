-- Run on the PostgreSQL/Supabase database before deploying the PDF API.
-- Assign courses with INSERT INTO portal_instructor_courses (instructor_id, course_id)
-- VALUES ('104217', 'REAL_COURSE_CODE') ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS portal_instructor_courses (
    instructor_id TEXT NOT NULL,
    course_id TEXT NOT NULL REFERENCES courses(course_code),
    PRIMARY KEY (instructor_id, course_id)
);

CREATE TABLE IF NOT EXISTS portal_pdfs (
    pdf_id TEXT PRIMARY KEY,
    instructor_id TEXT NOT NULL,
    course_id TEXT REFERENCES courses(course_code),
    title TEXT NOT NULL,
    description TEXT,
    original_filename TEXT NOT NULL,
    storage_path TEXT NOT NULL UNIQUE,
    size_bytes BIGINT NOT NULL CHECK (size_bytes > 0),
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_portal_pdfs_course ON portal_pdfs(course_id, uploaded_at DESC);
CREATE INDEX IF NOT EXISTS idx_portal_pdfs_instructor ON portal_pdfs(instructor_id, uploaded_at DESC);
