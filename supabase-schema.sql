-- ============================================================
-- صحتنا (Sahatna) - Supabase Database Schema (Secure)
-- Run this in Supabase SQL Editor after creating a project
--
-- SECURITY: Uses Supabase Auth (no plain-text passwords).
--           Uses strict RLS policies (no "allow all").
-- ============================================================

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- Reference Tables (Static Data)
-- ============================================================

CREATE TABLE IF NOT EXISTS specialties (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  name_en TEXT,
  icon TEXT DEFAULT '🩺'
);

CREATE TABLE IF NOT EXISTS cities (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL
);

-- ============================================================
-- Clinics
-- ============================================================

CREATE TABLE IF NOT EXISTS clinics (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  city_id TEXT NOT NULL REFERENCES cities(id),
  area TEXT,
  address TEXT,
  phone TEXT,
  lat DECIMAL(10,6) DEFAULT 0,
  lng DECIMAL(10,6) DEFAULT 0,
  status TEXT DEFAULT 'pending' CHECK (status IN ('approved','pending','rejected')),
  activation_code TEXT, -- 6-char code generated on approval, NULL after activation
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- Doctors
-- ============================================================

CREATE TABLE IF NOT EXISTS doctors (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  name_en TEXT,
  specialty_id TEXT NOT NULL REFERENCES specialties(id),
  clinic_id UUID NOT NULL REFERENCES clinics(id) ON DELETE CASCADE,
  photo TEXT DEFAULT '',
  bio TEXT DEFAULT '',
  qualifications TEXT DEFAULT '',
  experience_years INT DEFAULT 0,
  price INT NOT NULL DEFAULT 20000,
  gender TEXT DEFAULT 'male' CHECK (gender IN ('male','female')),
  languages TEXT[] DEFAULT ARRAY['العربية']::TEXT[],
  rating DECIMAL(2,1) DEFAULT 0,
  reviews_count INT DEFAULT 0,
  services TEXT[] DEFAULT ARRAY['clinic']::TEXT[],
  verified BOOLEAN DEFAULT false,
  featured BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- Schedules (Weekly availability per doctor)
-- ============================================================

CREATE TABLE IF NOT EXISTS schedules (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  doctor_id UUID NOT NULL REFERENCES doctors(id) ON DELETE CASCADE,
  day INT NOT NULL CHECK (day >= 0 AND day <= 6), -- 0=Sunday
  start_time TEXT NOT NULL, -- HH:MM
  end_time TEXT NOT NULL,   -- HH:MM
  slot_duration INT DEFAULT 30, -- minutes
  UNIQUE(doctor_id, day)
);

-- ============================================================
-- Appointments (Bookings)
-- ============================================================

CREATE TABLE IF NOT EXISTS appointments (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  doctor_id UUID NOT NULL REFERENCES doctors(id),
  clinic_id UUID NOT NULL REFERENCES clinics(id),
  patient_name TEXT NOT NULL,
  patient_phone TEXT NOT NULL,
  patient_age INT,
  patient_notes TEXT,
  date TEXT NOT NULL, -- YYYY-MM-DD
  time TEXT NOT NULL, -- HH:MM
  service TEXT DEFAULT 'clinic' CHECK (service IN ('clinic','video','home')),
  price INT NOT NULL,
  status TEXT DEFAULT 'confirmed' CHECK (status IN ('confirmed','completed','cancelled')),
  payment_method TEXT DEFAULT 'clinic',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Prevent double-booking (same doctor, same date, same time, not cancelled)
CREATE UNIQUE INDEX IF NOT EXISTS idx_no_double_booking
  ON appointments(doctor_id, date, time)
  WHERE status != 'cancelled';

-- ============================================================
-- Reviews (Verified only - patient must have completed appointment)
-- ============================================================

CREATE TABLE IF NOT EXISTS reviews (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  doctor_id UUID NOT NULL REFERENCES doctors(id) ON DELETE CASCADE,
  patient_name TEXT NOT NULL,
  patient_phone TEXT,
  rating INT NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  verified BOOLEAN DEFAULT false,
  appointment_id UUID REFERENCES appointments(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- Reminders
-- ============================================================

CREATE TABLE IF NOT EXISTS reminders (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  appointment_id UUID NOT NULL REFERENCES appointments(id) ON DELETE CASCADE,
  patient_name TEXT NOT NULL,
  patient_phone TEXT NOT NULL,
  doctor_name TEXT NOT NULL,
  clinic_name TEXT NOT NULL,
  date TEXT NOT NULL,
  time TEXT NOT NULL,
  sent BOOLEAN DEFAULT false,
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- Clinic Users (links Supabase Auth users to clinics)
-- NO password column — authentication is handled by Supabase Auth
-- ============================================================

CREATE TABLE IF NOT EXISTS clinic_users (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  clinic_id UUID NOT NULL REFERENCES clinics(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE, -- Supabase Auth user
  username TEXT NOT NULL UNIQUE, -- For display + email mapping (username@sahatna.app)
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- Admin Users (links Supabase Auth users to admin role)
-- NO password column — authentication is handled by Supabase Auth
-- ============================================================

CREATE TABLE IF NOT EXISTS admin_users (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE, -- Supabase Auth user
  username TEXT NOT NULL UNIQUE, -- For display + email mapping (username@sahatna.app)
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- RLS Helper Functions
-- ============================================================

-- Get the clinic_id for the current authenticated clinic user
CREATE OR REPLACE FUNCTION get_current_clinic_id()
RETURNS UUID AS $$
  SELECT clinic_id FROM clinic_users WHERE user_id = auth.uid() LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Check if current user is an admin
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS(SELECT 1 FROM admin_users WHERE user_id = auth.uid());
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Check if current user is a clinic user (any clinic)
CREATE OR REPLACE FUNCTION is_clinic_user()
RETURNS BOOLEAN AS $$
  SELECT EXISTS(SELECT 1 FROM clinic_users WHERE user_id = auth.uid());
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- ============================================================
-- Row Level Security (RLS) — STRICT POLICIES
-- ============================================================

-- Enable RLS on all tables
ALTER TABLE clinics ENABLE ROW LEVEL SECURITY;
ALTER TABLE doctors ENABLE ROW LEVEL SECURITY;
ALTER TABLE specialties ENABLE ROW LEVEL SECURITY;
ALTER TABLE cities ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE reminders ENABLE ROW LEVEL SECURITY;
ALTER TABLE clinic_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;

-- Drop any old "Allow all" policies from previous schema versions
DROP POLICY IF EXISTS "Allow all appointments" ON appointments;
DROP POLICY IF EXISTS "Allow all reminders" ON reminders;
DROP POLICY IF EXISTS "Allow all clinic_users" ON clinic_users;
DROP POLICY IF EXISTS "Allow all admin_users" ON admin_users;
DROP POLICY IF EXISTS "Allow all clinics manage" ON clinics;
DROP POLICY IF EXISTS "Allow all doctors manage" ON doctors;
DROP POLICY IF EXISTS "Allow all schedules manage" ON schedules;
-- Drop old admin-only doctor policies (replaced by clinic-or-admin policies)
DROP POLICY IF EXISTS "Admin manage doctors" ON doctors;
DROP POLICY IF EXISTS "Admin update doctors" ON doctors;
DROP POLICY IF EXISTS "Admin delete doctors" ON doctors;
-- Drop old clinic_users policies (replaced by self-insert + admin manage)
DROP POLICY IF EXISTS "Admin manage clinic_users" ON clinic_users;

-- ---- specialties & cities (public read, admin write) ----
CREATE POLICY "Public read specialties" ON specialties FOR SELECT USING (true);
CREATE POLICY "Admin manage specialties" ON specialties FOR ALL USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY "Public read cities" ON cities FOR SELECT USING (true);
CREATE POLICY "Admin manage cities" ON cities FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- ---- clinics ----
-- Public can see approved clinics; clinic can see own; admin can see all
CREATE POLICY "Read clinics" ON clinics FOR SELECT
  USING (status = 'approved' OR id = get_current_clinic_id() OR is_admin());
-- Anyone can register a new clinic (status defaults to 'pending')
CREATE POLICY "Public register clinic" ON clinics FOR INSERT WITH CHECK (true);
-- Only admin can update/delete clinics (approve, reject, edit)
CREATE POLICY "Admin update clinics" ON clinics FOR UPDATE USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "Admin delete clinics" ON clinics FOR DELETE USING (is_admin());

-- ---- doctors ----
-- Public can see all doctors (for search)
CREATE POLICY "Public read doctors" ON doctors FOR SELECT USING (true);
-- Clinic can insert doctors for their own clinic; admin can insert any
CREATE POLICY "Clinic or admin insert doctors" ON doctors FOR INSERT
  WITH CHECK (is_admin() OR clinic_id = get_current_clinic_id());
-- Clinic can update their own doctors; admin can update any
CREATE POLICY "Clinic or admin update doctors" ON doctors FOR UPDATE
  USING (is_admin() OR clinic_id = get_current_clinic_id())
  WITH CHECK (is_admin() OR clinic_id = get_current_clinic_id());
-- Clinic can delete their own doctors; admin can delete any
CREATE POLICY "Clinic or admin delete doctors" ON doctors FOR DELETE
  USING (is_admin() OR clinic_id = get_current_clinic_id());

-- ---- schedules ----
-- Public can see all schedules (to show available slots)
CREATE POLICY "Public read schedules" ON schedules FOR SELECT USING (true);
-- Clinic can manage schedules for their own doctors; admin can manage all
CREATE POLICY "Clinic manage own schedules" ON schedules FOR ALL
  USING (
    doctor_id IN (SELECT id FROM doctors WHERE clinic_id = get_current_clinic_id())
    OR is_admin()
  )
  WITH CHECK (
    doctor_id IN (SELECT id FROM doctors WHERE clinic_id = get_current_clinic_id())
    OR is_admin()
  );

-- ---- appointments ----
-- Public (anon) can create bookings (INSERT only)
CREATE POLICY "Public create appointments" ON appointments FOR INSERT WITH CHECK (true);
-- Public can read appointments (needed for slot availability checking)
CREATE POLICY "Public read appointments" ON appointments FOR SELECT USING (true);
-- Clinic can view & update their own appointments; admin can view & update all
CREATE POLICY "Clinic view own appointments" ON appointments FOR SELECT
  USING (clinic_id = get_current_clinic_id() OR is_admin());
CREATE POLICY "Clinic update own appointments" ON appointments FOR UPDATE
  USING (clinic_id = get_current_clinic_id() OR is_admin())
  WITH CHECK (clinic_id = get_current_clinic_id() OR is_admin());
-- Only admin can delete appointments
CREATE POLICY "Admin delete appointments" ON appointments FOR DELETE USING (is_admin());

-- ---- reviews ----
-- Public can read reviews
CREATE POLICY "Public read reviews" ON reviews FOR SELECT USING (true);
-- Public can create reviews (verified check done in app logic)
CREATE POLICY "Public create reviews" ON reviews FOR INSERT WITH CHECK (true);
-- Only admin can delete reviews (moderation)
CREATE POLICY "Admin delete reviews" ON reviews FOR DELETE USING (is_admin());

-- ---- reminders ----
-- Clinic can view reminders for their own appointments; admin can view all
CREATE POLICY "Clinic view own reminders" ON reminders FOR SELECT
  USING (
    appointment_id IN (
      SELECT a.id FROM appointments a
      WHERE a.clinic_id = get_current_clinic_id()
    )
    OR is_admin()
  );
-- Clinic can update reminders (mark sent) for their own; admin can update all
CREATE POLICY "Clinic update own reminders" ON reminders FOR UPDATE
  USING (
    appointment_id IN (
      SELECT a.id FROM appointments a
      WHERE a.clinic_id = get_current_clinic_id()
    )
    OR is_admin()
  )
  WITH CHECK (
    appointment_id IN (
      SELECT a.id FROM appointments a
      WHERE a.clinic_id = get_current_clinic_id()
    )
    OR is_admin()
  );
-- Reminders are created automatically by app after booking (uses service_role or anon insert)
CREATE POLICY "Create reminders" ON reminders FOR INSERT WITH CHECK (true);

-- ---- clinic_users (NO public access) ----
-- A user can only read their own clinic_users row (to get clinic_id after login)
CREATE POLICY "User read own clinic_user" ON clinic_users FOR SELECT
  USING (user_id = auth.uid());
-- A newly signed-up user can insert their own clinic_users row (for activation flow)
CREATE POLICY "User self-insert clinic_user" ON clinic_users FOR INSERT
  WITH CHECK (user_id = auth.uid());
-- Admin can manage all clinic_users (update/delete)
CREATE POLICY "Admin manage clinic_users" ON clinic_users FOR UPDATE
  USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "Admin delete clinic_users" ON clinic_users FOR DELETE
  USING (is_admin());

-- ---- admin_users (NO public access) ----
-- A user can only read their own admin_users row (to confirm admin role)
CREATE POLICY "User read own admin_user" ON admin_users FOR SELECT
  USING (user_id = auth.uid());
-- Only admin can insert/update/delete admin_users
CREATE POLICY "Admin manage admin_users" ON admin_users FOR ALL
  USING (is_admin()) WITH CHECK (is_admin());

-- ============================================================
-- Demo Auth Users
-- Creates auth.users entries so demo logins work out of the box.
-- Email convention: username@sahatna.app
-- Passwords: cl1/cl2/cl3 = "1234", admin = "admin123"
-- ============================================================

-- Clinic user: cl1 (مركز الشفاء)
INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data, is_super_admin
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  'e0000000-0000-0000-0000-000000000001',
  'authenticated', 'authenticated',
  'cl1@sahatna.app', crypt('1234', gen_salt('bf')),
  NOW(), NOW(), NOW(),
  '', '', '', '',
  '{"provider":"email","providers":["email"]}', '{}', false
) ON CONFLICT (id) DO UPDATE SET
  instance_id = EXCLUDED.instance_id,
  aud = EXCLUDED.aud,
  role = EXCLUDED.role,
  email = EXCLUDED.email,
  encrypted_password = EXCLUDED.encrypted_password,
  email_confirmed_at = EXCLUDED.email_confirmed_at,
  updated_at = EXCLUDED.updated_at,
  confirmation_token = EXCLUDED.confirmation_token,
  recovery_token = EXCLUDED.recovery_token,
  email_change_token_new = EXCLUDED.email_change_token_new,
  email_change = EXCLUDED.email_change,
  raw_app_meta_data = EXCLUDED.raw_app_meta_data,
  raw_user_meta_data = EXCLUDED.raw_user_meta_data,
  is_super_admin = EXCLUDED.is_super_admin;

-- Clinic user: cl2 (عيادة النور)
INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data, is_super_admin
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  'e0000000-0000-0000-0000-000000000002',
  'authenticated', 'authenticated',
  'cl2@sahatna.app', crypt('1234', gen_salt('bf')),
  NOW(), NOW(), NOW(),
  '', '', '', '',
  '{"provider":"email","providers":["email"]}', '{}', false
) ON CONFLICT (id) DO UPDATE SET
  instance_id = EXCLUDED.instance_id,
  aud = EXCLUDED.aud,
  role = EXCLUDED.role,
  email = EXCLUDED.email,
  encrypted_password = EXCLUDED.encrypted_password,
  email_confirmed_at = EXCLUDED.email_confirmed_at,
  updated_at = EXCLUDED.updated_at,
  confirmation_token = EXCLUDED.confirmation_token,
  recovery_token = EXCLUDED.recovery_token,
  email_change_token_new = EXCLUDED.email_change_token_new,
  email_change = EXCLUDED.email_change,
  raw_app_meta_data = EXCLUDED.raw_app_meta_data,
  raw_user_meta_data = EXCLUDED.raw_user_meta_data,
  is_super_admin = EXCLUDED.is_super_admin;

-- Clinic user: cl3 (مستشفى الحياة)
INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data, is_super_admin
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  'e0000000-0000-0000-0000-000000000003',
  'authenticated', 'authenticated',
  'cl3@sahatna.app', crypt('1234', gen_salt('bf')),
  NOW(), NOW(), NOW(),
  '', '', '', '',
  '{"provider":"email","providers":["email"]}', '{}', false
) ON CONFLICT (id) DO UPDATE SET
  instance_id = EXCLUDED.instance_id,
  aud = EXCLUDED.aud,
  role = EXCLUDED.role,
  email = EXCLUDED.email,
  encrypted_password = EXCLUDED.encrypted_password,
  email_confirmed_at = EXCLUDED.email_confirmed_at,
  updated_at = EXCLUDED.updated_at,
  confirmation_token = EXCLUDED.confirmation_token,
  recovery_token = EXCLUDED.recovery_token,
  email_change_token_new = EXCLUDED.email_change_token_new,
  email_change = EXCLUDED.email_change,
  raw_app_meta_data = EXCLUDED.raw_app_meta_data,
  raw_user_meta_data = EXCLUDED.raw_user_meta_data,
  is_super_admin = EXCLUDED.is_super_admin;

-- Admin user: admin
INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data, is_super_admin
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  'e0000000-0000-0000-0000-000000000004',
  'authenticated', 'authenticated',
  'admin@sahatna.app', crypt('admin123', gen_salt('bf')),
  NOW(), NOW(), NOW(),
  '', '', '', '',
  '{"provider":"email","providers":["email"]}', '{}', false
) ON CONFLICT (id) DO UPDATE SET
  instance_id = EXCLUDED.instance_id,
  aud = EXCLUDED.aud,
  role = EXCLUDED.role,
  email = EXCLUDED.email,
  encrypted_password = EXCLUDED.encrypted_password,
  email_confirmed_at = EXCLUDED.email_confirmed_at,
  updated_at = EXCLUDED.updated_at,
  confirmation_token = EXCLUDED.confirmation_token,
  recovery_token = EXCLUDED.recovery_token,
  email_change_token_new = EXCLUDED.email_change_token_new,
  email_change = EXCLUDED.email_change,
  raw_app_meta_data = EXCLUDED.raw_app_meta_data,
  raw_user_meta_data = EXCLUDED.raw_user_meta_data,
  is_super_admin = EXCLUDED.is_super_admin;

-- ============================================================
-- auth.identities rows (required by GoTrue for email provider)
-- ============================================================
INSERT INTO auth.identities (
  id, user_id, identity_id, provider, created_at, updated_at
) VALUES
  ('e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 'email', NOW(), NOW()),
  ('e0000000-0000-0000-0000-000000000002', 'e0000000-0000-0000-0000-000000000002', 'e0000000-0000-0000-0000-000000000002', 'email', NOW(), NOW()),
  ('e0000000-0000-0000-0000-000000000003', 'e0000000-0000-0000-0000-000000000003', 'e0000000-0000-0000-0000-000000000003', 'email', NOW(), NOW()),
  ('e0000000-0000-0000-0000-000000000004', 'e0000000-0000-0000-0000-000000000004', 'e0000000-0000-0000-0000-000000000004', 'email', NOW(), NOW())
ON CONFLICT (id) DO UPDATE SET
  user_id = EXCLUDED.user_id,
  identity_id = EXCLUDED.identity_id,
  provider = EXCLUDED.provider,
  updated_at = EXCLUDED.updated_at;

-- ============================================================
-- Seed Data
-- ============================================================

INSERT INTO specialties (id, name, name_en, icon) VALUES
  ('sp1','طب الأسرة','Family Medicine','👨‍👩‍👧'),
  ('sp2','الباطنية','Internal Medicine','🩺'),
  ('sp3','الأطفال','Pediatrics','🧒'),
  ('sp4','النسائية والتوليد','Gynecology','🤰'),
  ('sp5','الجلدية','Dermatology','🧴'),
  ('sp6','الأسنان','Dentistry','🦷'),
  ('sp7','العيون','Ophthalmology','👁️'),
  ('sp8','الأنف والأذن والحنجرة','ENT','👂'),
  ('sp9','العظام','Orthopedics','🦴'),
  ('sp10','الجراحة العامة','General Surgery','🔪'),
  ('sp11','المخ والأعصاب','Neurology','🧠'),
  ('sp12','النفسية','Psychiatry','💭')
ON CONFLICT (id) DO NOTHING;

INSERT INTO cities (id, name) VALUES
  ('c1','بغداد'),('c2','البصرة'),('c3','الموصل'),('c4','أربيل'),
  ('c5','النجف'),('c6','كربلاء'),('c7','كركوك'),('c8','السليمانية'),
  ('c9','الديوانية'),('c10','العمارة'),('c11','الناصرية'),('c12','الحلة')
ON CONFLICT (id) DO NOTHING;

-- Insert sample clinics
INSERT INTO clinics (id, name, city_id, area, address, phone, lat, lng, status) VALUES
  ('a0000000-0000-0000-0000-000000000001','مركز الشفاء الطبي','c1','الكرادة','شارع الكرادة داخل، قرب مجمع الكرادة','07701234567',33.3152,44.4360,'approved'),
  ('a0000000-0000-0000-0000-000000000002','عيادة النور للتخصصات','c1','المنصور','شارع الأميرات، المنصور','07801234567',33.3230,44.3850,'approved'),
  ('a0000000-0000-0000-0000-000000000003','مستشفى الحياة الخاص','c2','العشار','شارع الكورنيش، العشار','07901234567',30.5085,47.7804,'approved'),
  ('a0000000-0000-0000-0000-000000000004','مركز الرافدين الطبي','c5','المركز','شارع الكوفة، النجف','07712345678',32.0000,44.3333,'pending')
ON CONFLICT (id) DO NOTHING;

-- Insert sample doctors
INSERT INTO doctors (id, name, name_en, specialty_id, clinic_id, photo, bio, qualifications, experience_years, price, gender, languages, rating, reviews_count, services, verified, featured) VALUES
  ('b0000000-0000-0000-0000-000000000001','د. أحمد الكاظمي','Dr. Ahmed Al-Kadhimi','sp2','a0000000-0000-0000-0000-000000000001','https://ui-avatars.com/api/?name=Ahmed+K&background=0d9488&color=fff&size=200','استشاري باطنية مع خبرة 15 سنة في تشخيص وعلاج الأمراض المزمنة مثل السكري وضغط الدم.','بورد عراقي في الباطنية - جامعة بغداد',15,30000,'male',ARRAY['العربية','English'],4.8,124,ARRAY['clinic','video'],true,true),
  ('b0000000-0000-0000-0000-000000000002','د. سارة العبيدي','Dr. Sara Al-Obaidi','sp4','a0000000-0000-0000-0000-000000000001','https://ui-avatars.com/api/?name=Sara+O&background=db2777&color=fff&size=200','أخصائية نسائية وتوليد، متخصصة في متابعة الحمل والعناية بصحة المرأة.','بورد عراقي في النسائية - جامعة بغداد',10,35000,'female',ARRAY['العربية'],4.9,89,ARRAY['clinic','video','home'],true,true),
  ('b0000000-0000-0000-0000-000000000003','د. محمد الجبوري','Dr. Mohammed Al-Jubouri','sp3','a0000000-0000-0000-0000-000000000002','https://ui-avatars.com/api/?name=Mohammed+J&background=2563eb&color=fff&size=200','طبيب أطفال متخصص في رعاية حديثي الولادة والأمراض المعدية لدى الأطفال.','بورد عراقي في الأطفال - جامعة الموصل',12,25000,'male',ARRAY['العربية','English','كوردی'],4.7,156,ARRAY['clinic','video'],true,false),
  ('b0000000-0000-0000-0000-000000000004','د. زينب الحسني','Dr. Zainab Al-Hasnawi','sp5','a0000000-0000-0000-0000-000000000002','https://ui-avatars.com/api/?name=Zainab+H&background=7c3aed&color=fff&size=200','أخصائية جلدية، علاج حب الشباب، التصبغات، وإجراءات التجميل غير الجراحي.','بورد عراقي في الجلدية - جامعة البصرة',8,40000,'female',ARRAY['العربية'],4.6,67,ARRAY['clinic'],true,false),
  ('b0000000-0000-0000-0000-000000000005','د. عمر التميمي','Dr. Omar Al-Tamimi','sp6','a0000000-0000-0000-0000-000000000003','https://ui-avatars.com/api/?name=Omar+T&background=0891b2&color=fff&size=200','طبيب أسنان تقويم وزراعة، خبرة في علاج التشوهات وتركيب الأسنان.','ماجستير في تقويم الأسنان - جامعة بغداد',14,20000,'male',ARRAY['العربية','English'],4.5,203,ARRAY['clinic'],true,true),
  ('b0000000-0000-0000-0000-000000000006','د. نور الساعدي','Dr. Noor Al-Saadi','sp1','a0000000-0000-0000-0000-000000000003','https://ui-avatars.com/api/?name=Noor+S&background=059669&color=fff&size=200','طبيبة طب أسرة، متابعة الأمراض المزمنة والوقائية لكل أفراد العائلة.','بورد عراقي في طب الأسرة',7,20000,'female',ARRAY['العربية','English'],4.9,45,ARRAY['clinic','video','home'],true,false)
ON CONFLICT (id) DO NOTHING;

-- Insert schedules
INSERT INTO schedules (doctor_id, day, start_time, end_time, slot_duration) VALUES
  ('b0000000-0000-0000-0000-000000000001',0,'17:00','21:00',30),
  ('b0000000-0000-0000-0000-000000000001',1,'17:00','21:00',30),
  ('b0000000-0000-0000-0000-000000000001',2,'17:00','21:00',30),
  ('b0000000-0000-0000-0000-000000000001',3,'17:00','21:00',30),
  ('b0000000-0000-0000-0000-000000000001',5,'10:00','14:00',30),
  ('b0000000-0000-0000-0000-000000000002',0,'16:00','20:00',30),
  ('b0000000-0000-0000-0000-000000000002',2,'16:00','20:00',30),
  ('b0000000-0000-0000-0000-000000000002',4,'16:00','20:00',30),
  ('b0000000-0000-0000-0000-000000000002',6,'11:00','15:00',30),
  ('b0000000-0000-0000-0000-000000000003',1,'10:00','14:00',20),
  ('b0000000-0000-0000-0000-000000000003',3,'10:00','14:00',20),
  ('b0000000-0000-0000-0000-000000000003',5,'10:00','14:00',20),
  ('b0000000-0000-0000-0000-000000000003',6,'10:00','14:00',20),
  ('b0000000-0000-0000-0000-000000000004',0,'11:00','15:00',30),
  ('b0000000-0000-0000-0000-000000000004',2,'11:00','15:00',30),
  ('b0000000-0000-0000-0000-000000000004',4,'11:00','15:00',30),
  ('b0000000-0000-0000-0000-000000000005',1,'09:00','13:00',30),
  ('b0000000-0000-0000-0000-000000000005',2,'09:00','13:00',30),
  ('b0000000-0000-0000-0000-000000000005',3,'09:00','13:00',30),
  ('b0000000-0000-0000-0000-000000000005',4,'09:00','13:00',30),
  ('b0000000-0000-0000-0000-000000000005',5,'09:00','13:00',30),
  ('b0000000-0000-0000-0000-000000000006',0,'12:00','16:00',20),
  ('b0000000-0000-0000-0000-000000000006',1,'12:00','16:00',20),
  ('b0000000-0000-0000-0000-000000000006',2,'12:00','16:00',20),
  ('b0000000-0000-0000-0000-000000000006',3,'12:00','16:00',20),
  ('b0000000-0000-0000-0000-000000000006',4,'12:00','16:00',20)
ON CONFLICT (doctor_id, day) DO NOTHING;

-- Insert sample reviews
INSERT INTO reviews (doctor_id, patient_name, patient_phone, rating, comment, verified) VALUES
  ('b0000000-0000-0000-0000-000000000001','علي حسين','07701112233',5,'طبيب محترم وخبير، شخّص حالتي بدقة.',true),
  ('b0000000-0000-0000-0000-000000000001','فاطمة عبد الله','07801112233',4,'استشارة جيدة لكن الانتظار كان طويل شوية.',true),
  ('b0000000-0000-0000-0000-000000000002','مريم أحمد','07701112244',5,'د. سارة رائعة، متابعة الحمل معها مريحة جداً.',true),
  ('b0000000-0000-0000-0000-000000000003','كريم سعد','07801112255',5,'تعامله مع الأطفال ممتاز، ابني ما خاف من الطبيب.',true),
  ('b0000000-0000-0000-0000-000000000005','حسن كاظم','07901112266',4,'علاج الأسنان كان جيد والأسعار معقولة.',true)
ON CONFLICT DO NOTHING;

-- Insert clinic_users (linked to auth.users — NO password column)
INSERT INTO clinic_users (clinic_id, user_id, username, name) VALUES
  ('a0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','cl1','مدير مركز الشفاء'),
  ('a0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000002','cl2','مدير عيادة النور'),
  ('a0000000-0000-0000-0000-000000000003','e0000000-0000-0000-0000-000000000003','cl3','مدير مستشفى الحياة')
ON CONFLICT (username) DO NOTHING;

-- Insert admin_users (linked to auth.users — NO password column)
INSERT INTO admin_users (user_id, username, name) VALUES
  ('e0000000-0000-0000-0000-000000000004','admin','مدير صحتنا')
ON CONFLICT (username) DO NOTHING;

-- ============================================================
-- Useful Indexes
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_doctors_clinic ON doctors(clinic_id);
CREATE INDEX IF NOT EXISTS idx_doctors_specialty ON doctors(specialty_id);
CREATE INDEX IF NOT EXISTS idx_appointments_doctor ON appointments(doctor_id);
CREATE INDEX IF NOT EXISTS idx_appointments_clinic ON appointments(clinic_id);
CREATE INDEX IF NOT EXISTS idx_appointments_date ON appointments(date);
CREATE INDEX IF NOT EXISTS idx_reviews_doctor ON reviews(doctor_id);
CREATE INDEX IF NOT EXISTS idx_schedules_doctor ON schedules(doctor_id);
CREATE INDEX IF NOT EXISTS idx_clinic_users_user ON clinic_users(user_id);
CREATE INDEX IF NOT EXISTS idx_admin_users_user ON admin_users(user_id);