-- ============================================================
-- صحتنا - إصلاح مستخدمي auth.users المعطوبين
-- شغّل هذا الملف في Supabase SQL Editor
-- يصلح الصفوف الموجودة ويضيف صفوف auth.identities
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
-- clinic_users and admin_users (if missing)
-- ============================================================
INSERT INTO clinic_users (clinic_id, user_id, username, name) VALUES
  ('a0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','cl1','مدير مركز الشفاء'),
  ('a0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000002','cl2','مدير عيادة النور'),
  ('a0000000-0000-0000-0000-000000000003','e0000000-0000-0000-0000-000000000003','cl3','مدير مستشفى الحياة')
ON CONFLICT (username) DO NOTHING;

INSERT INTO admin_users (user_id, username, name) VALUES
  ('e0000000-0000-0000-0000-000000000004','admin','مدير صحتنا')
ON CONFLICT (username) DO NOTHING;

-- ============================================================
-- Add missing RLS policy: Public read appointments
-- (needed for slot availability checking and clinic/admin views)
-- ============================================================
DROP POLICY IF EXISTS "Public read appointments" ON appointments;
CREATE POLICY "Public read appointments" ON appointments FOR SELECT USING (true);

-- ============================================================
-- Verify the fix
-- ============================================================
SELECT 'auth.users' as table_name, count(*) as count FROM auth.users WHERE email LIKE '%@sahatna.app'
UNION ALL
SELECT 'auth.identities', count(*) FROM auth.identities WHERE provider = 'email' AND user_id IN ('e0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000003','e0000000-0000-0000-0000-000000000004')
UNION ALL
SELECT 'clinic_users', count(*) FROM clinic_users
UNION ALL
SELECT 'admin_users', count(*) FROM admin_users;