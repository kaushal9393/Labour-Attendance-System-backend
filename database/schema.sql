-- ============================================================
-- GARAGE ATTENDANCE SYSTEM — NEON POSTGRESQL SCHEMA
-- Run this file in Neon SQL Editor top-to-bottom
-- ============================================================

-- STEP 1: Enable pgvector extension (REQUIRED before any table creation)
CREATE EXTENSION IF NOT EXISTS vector;

-- ============================================================
-- TABLE 1: companies
-- ============================================================
CREATE TABLE IF NOT EXISTS companies (
    id           SERIAL PRIMARY KEY,
    name         VARCHAR(100) NOT NULL,
    company_code VARCHAR(20) UNIQUE NOT NULL,  -- user-chosen, used in kiosk URL
    owner_phone  VARCHAR(20),
    plan         VARCHAR(20) DEFAULT 'free',   -- free / basic / premium
    status       VARCHAR(20) DEFAULT 'active', -- active / suspended
    created_at   TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- TABLE 2: admins
-- ============================================================
CREATE TABLE IF NOT EXISTS admins (
    id           SERIAL PRIMARY KEY,
    company_id   INT REFERENCES companies(id) ON DELETE CASCADE,
    name         VARCHAR(100) NOT NULL,
    email        VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,        -- bcrypt hashed
    created_at   TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- TABLE 3: employees
-- ============================================================
CREATE TABLE IF NOT EXISTS employees (
    id                SERIAL PRIMARY KEY,
    company_id        INT REFERENCES companies(id) ON DELETE CASCADE,
    name              VARCHAR(100) NOT NULL,
    phone             VARCHAR(15),
    monthly_salary    DECIMAL(10,2) NOT NULL,
    joining_date      DATE NOT NULL,
    profile_photo_url TEXT,                     -- Cloudinary URL
    status            VARCHAR(10) DEFAULT 'active', -- active / inactive
    created_at        TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- TABLE 4: face_vectors  (ArcFace 512-dim embeddings)
-- ============================================================
CREATE TABLE IF NOT EXISTS face_vectors (
    id          SERIAL PRIMARY KEY,
    employee_id INT REFERENCES employees(id) ON DELETE CASCADE,
    face_vector vector(512) NOT NULL,           -- ArcFace 512-dim embedding
    angle_type  VARCHAR(10) NOT NULL,           -- 'front', 'left', 'right'
    registered_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- TABLE 5: attendance
-- ============================================================
CREATE TABLE IF NOT EXISTS attendance (
    id              SERIAL PRIMARY KEY,
    employee_id     INT REFERENCES employees(id) ON DELETE CASCADE,
    company_id      INT REFERENCES companies(id) ON DELETE CASCADE,
    attendance_date DATE NOT NULL,
    check_in        TIMESTAMP,
    check_out       TIMESTAMP,
    status          VARCHAR(10) DEFAULT 'absent', -- present / late / absent
    match_score     DECIMAL(5,4),                 -- cosine similarity (0.0000-1.0000)
    created_at      TIMESTAMP DEFAULT NOW(),
    UNIQUE(employee_id, attendance_date)
);

-- ============================================================
-- TABLE 6: salary_records
-- ============================================================
CREATE TABLE IF NOT EXISTS salary_records (
    id               SERIAL PRIMARY KEY,
    employee_id      INT REFERENCES employees(id) ON DELETE CASCADE,
    month            INT NOT NULL CHECK (month BETWEEN 1 AND 12),
    year             INT NOT NULL CHECK (year >= 2020),
    working_days     INT NOT NULL,
    present_days     INT NOT NULL DEFAULT 0,
    late_days        INT NOT NULL DEFAULT 0,
    absent_days      INT NOT NULL DEFAULT 0,
    monthly_salary   DECIMAL(10,2) NOT NULL,
    per_day_salary   DECIMAL(10,2) NOT NULL,
    deduction_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    net_pay          DECIMAL(10,2) NOT NULL,
    generated_at     TIMESTAMP DEFAULT NOW(),
    UNIQUE(employee_id, month, year)
);

-- ============================================================
-- TABLE 7: settings
-- ============================================================
CREATE TABLE IF NOT EXISTS settings (
    id                      SERIAL PRIMARY KEY,
    company_id              INT REFERENCES companies(id) ON DELETE CASCADE UNIQUE,
    work_start_time         TIME DEFAULT '09:00:00',
    work_end_time           TIME DEFAULT '18:00:00',
    late_threshold_minutes  INT DEFAULT 15,
    working_days_per_week   INT DEFAULT 6,      -- 6 = Mon-Sat
    created_at              TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- PERFORMANCE INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_attendance_date          ON attendance(attendance_date);
CREATE INDEX IF NOT EXISTS idx_attendance_employee      ON attendance(employee_id);
CREATE INDEX IF NOT EXISTS idx_attendance_company       ON attendance(company_id);
CREATE INDEX IF NOT EXISTS idx_attendance_company_date  ON attendance(company_id, attendance_date);
CREATE INDEX IF NOT EXISTS idx_attendance_emp_date      ON attendance(employee_id, attendance_date);
CREATE INDEX IF NOT EXISTS idx_face_vectors_employee    ON face_vectors(employee_id);
CREATE INDEX IF NOT EXISTS idx_employees_company        ON employees(company_id);
CREATE INDEX IF NOT EXISTS idx_employees_company_status ON employees(company_id, status);
CREATE INDEX IF NOT EXISTS idx_employees_name           ON employees(name);
CREATE INDEX IF NOT EXISTS idx_face_angle               ON face_vectors(employee_id, angle_type);
CREATE INDEX IF NOT EXISTS idx_salary_employee          ON salary_records(employee_id);
CREATE INDEX IF NOT EXISTS idx_salary_month_year        ON salary_records(month, year);

-- ============================================================
-- ARCFACE VECTOR SIMILARITY FUNCTION
-- Returns the best matching employee for a given face vector
-- Uses cosine distance operator <=> from pgvector
-- similarity = 1 - cosine_distance  (range: 0..1, higher = better)
-- ============================================================
CREATE OR REPLACE FUNCTION find_matching_employee(
    query_vector  vector(512),
    threshold     FLOAT DEFAULT 0.80,
    p_company_id  INT   DEFAULT 1
)
RETURNS TABLE(
    employee_id   INT,
    employee_name VARCHAR,
    similarity    FLOAT,
    angle_type    VARCHAR
)
AS $$
BEGIN
    RETURN QUERY
    SELECT
        e.id                                      AS employee_id,
        e.name                                    AS employee_name,
        (1 - (fv.face_vector <=> query_vector))   AS similarity,
        fv.angle_type
    FROM face_vectors fv
    JOIN employees e ON e.id = fv.employee_id
    WHERE e.company_id = p_company_id
      AND e.status     = 'active'
      AND (1 - (fv.face_vector <=> query_vector)) >= threshold
    ORDER BY similarity DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- NO SEED DATA — multi-tenant SaaS, every company is created via signup.
-- ============================================================

-- ============================================================
-- CONNECTION STRING FORMAT FOR PYTHON ASYNCPG
-- DATABASE_URL=postgresql+asyncpg://user:pass@host/dbname?ssl=require
-- ============================================================
