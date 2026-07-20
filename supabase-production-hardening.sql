-- ============================================================
-- صحتنا (Sahhatna) - Canonical production hardening migration
--
-- Apply on a STAGING project after supabase-schema.sql.
-- Do not run the legacy SQL files listed in SECURITY.md.
-- This migration is intentionally transactional and repeatable.
-- ============================================================

BEGIN;

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA extensions;
CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 1. Normalize columns and constraints
-- ============================================================

ALTER TABLE appointments ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE appointments ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'pending';
ALTER TABLE appointments ADD COLUMN IF NOT EXISTS patient_notes_encrypted BYTEA;
ALTER TABLE appointments ADD COLUMN IF NOT EXISTS national_id_encrypted BYTEA;
ALTER TABLE clinics ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE clinics ADD COLUMN IF NOT EXISTS license_number TEXT;
ALTER TABLE doctors ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE doctors ADD COLUMN IF NOT EXISTS active BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE appointments DROP CONSTRAINT IF EXISTS appointments_status_check;
ALTER TABLE appointments ADD CONSTRAINT appointments_status_check
  CHECK (status IN ('confirmed','completed','cancelled','no_show'));

ALTER TABLE appointments DROP CONSTRAINT IF EXISTS appointments_payment_status_check;
ALTER TABLE appointments ADD CONSTRAINT appointments_payment_status_check
  CHECK (payment_status IN ('pending','paid','refunded','clinic'));

ALTER TABLE appointments DROP CONSTRAINT IF EXISTS appointments_patient_name_check;
ALTER TABLE appointments ADD CONSTRAINT appointments_patient_name_check
  CHECK (length(trim(patient_name)) BETWEEN 2 AND 120);

ALTER TABLE appointments DROP CONSTRAINT IF EXISTS appointments_patient_phone_check;
ALTER TABLE appointments ADD CONSTRAINT appointments_patient_phone_check
  CHECK (patient_phone ~ '^07[0-9]{9}$');

ALTER TABLE appointments DROP CONSTRAINT IF EXISTS appointments_date_format_check;
ALTER TABLE appointments ADD CONSTRAINT appointments_date_format_check
  CHECK (date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$');

ALTER TABLE appointments DROP CONSTRAINT IF EXISTS appointments_time_format_check;
ALTER TABLE appointments ADD CONSTRAINT appointments_time_format_check
  CHECK (time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$');

ALTER TABLE appointments DROP CONSTRAINT IF EXISTS appointments_price_positive_check;
ALTER TABLE appointments ADD CONSTRAINT appointments_price_positive_check
  CHECK (price > 0);

DROP INDEX IF EXISTS idx_no_double_booking;
CREATE UNIQUE INDEX idx_no_double_booking
  ON appointments(doctor_id, date, time)
  WHERE status NOT IN ('cancelled', 'no_show');

-- ============================================================
-- 2. Stable authorization helpers
-- ============================================================

CREATE OR REPLACE FUNCTION get_current_clinic_id()
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
  SELECT clinic_id
  FROM public.clinic_users
  WHERE user_id = auth.uid()
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION is_clinic_user()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.clinic_users WHERE user_id = auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION get_current_clinic_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION is_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION is_clinic_user() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_current_clinic_id() TO authenticated;
GRANT EXECUTE ON FUNCTION is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION is_clinic_user() TO authenticated;

-- ============================================================
-- 3. Public-safe views (no activation codes or patient phones)
-- ============================================================

DROP VIEW IF EXISTS public_doctor_summary;
CREATE OR REPLACE VIEW public_clinics
WITH (security_barrier = true)
AS
SELECT id, name, city_id, area, address, phone, lat, lng, status, created_at
FROM clinics
WHERE status = 'approved';

REVOKE ALL ON public_clinics FROM PUBLIC;
GRANT SELECT ON public_clinics TO anon, authenticated;

CREATE OR REPLACE VIEW public_reviews
WITH (security_barrier = true)
AS
SELECT
  id,
  doctor_id,
  CASE
    WHEN patient_name IS NULL OR patient_name = '' THEN 'مستخدم'
    ELSE left(patient_name, 1) || '***'
  END AS patient_name,
  rating,
  comment,
  verified,
  created_at
FROM reviews
WHERE verified = true;

REVOKE ALL ON public_reviews FROM PUBLIC;
GRANT SELECT ON public_reviews TO anon, authenticated;

CREATE OR REPLACE VIEW public_appointment_slots
WITH (security_barrier = true)
AS
SELECT doctor_id, date, time
FROM appointments
WHERE status NOT IN ('cancelled', 'no_show');

REVOKE ALL ON public_appointment_slots FROM PUBLIC;
GRANT SELECT ON public_appointment_slots TO anon, authenticated;

DROP VIEW IF EXISTS clinic_appointment_details;

-- ============================================================
-- 4. Replace unsafe RLS policies
-- ============================================================

ALTER TABLE clinics ENABLE ROW LEVEL SECURITY;
ALTER TABLE doctors ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE reminders ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE clinic_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Read clinics" ON clinics;
DROP POLICY IF EXISTS "Public register clinic" ON clinics;
DROP POLICY IF EXISTS "Validated public register clinic" ON clinics;
DROP POLICY IF EXISTS "Authenticated read authorized clinics" ON clinics;
DROP POLICY IF EXISTS "Public register pending clinic" ON clinics;
DROP POLICY IF EXISTS "Admin update clinics" ON clinics;
DROP POLICY IF EXISTS "Admin delete clinics" ON clinics;

CREATE POLICY "Authenticated read authorized clinics" ON clinics FOR SELECT TO authenticated
  USING (id = get_current_clinic_id() OR is_admin());

CREATE POLICY "Public register pending clinic" ON clinics FOR INSERT TO anon, authenticated
  WITH CHECK (
    status = 'pending'
    AND activation_code IS NULL
    AND name IS NOT NULL AND length(trim(name)) >= 3
    AND city_id IN (SELECT id FROM cities)
    AND phone ~ '^07[0-9]{9}$'
  );

CREATE POLICY "Admin update clinics" ON clinics FOR UPDATE TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "Admin delete clinics" ON clinics FOR DELETE TO authenticated
  USING (is_admin());

REVOKE INSERT ON clinics FROM anon, authenticated;

DROP POLICY IF EXISTS "Public read doctors" ON doctors;
DROP POLICY IF EXISTS "Read doctors for approved clinics" ON doctors;
DROP POLICY IF EXISTS "Authorized read doctors" ON doctors;
CREATE POLICY "Read doctors for approved clinics" ON doctors FOR SELECT TO anon, authenticated
  USING (active = true AND clinic_id IN (SELECT id FROM public_clinics));
CREATE POLICY "Authorized read doctors" ON doctors FOR SELECT TO authenticated
  USING (clinic_id = get_current_clinic_id() OR is_admin());

REVOKE INSERT, UPDATE, DELETE ON doctors FROM authenticated;

DROP POLICY IF EXISTS "Public create appointments" ON appointments;
DROP POLICY IF EXISTS "Validated create appointments" ON appointments;
DROP POLICY IF EXISTS "Clinic view own appointments" ON appointments;
DROP POLICY IF EXISTS "Clinic update own appointments" ON appointments;
DROP POLICY IF EXISTS "Admin delete appointments" ON appointments;

CREATE POLICY "Clinic view own appointments" ON appointments FOR SELECT TO authenticated
  USING (clinic_id = get_current_clinic_id() OR is_admin());
CREATE POLICY "Clinic update own appointments" ON appointments FOR UPDATE TO authenticated
  USING (clinic_id = get_current_clinic_id() OR is_admin())
  WITH CHECK (clinic_id = get_current_clinic_id() OR is_admin());
CREATE POLICY "Admin delete appointments" ON appointments FOR DELETE TO authenticated
  USING (is_admin());

REVOKE INSERT ON appointments FROM anon, authenticated;
REVOKE SELECT ON appointments FROM anon;
REVOKE UPDATE ON appointments FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON schedules FROM authenticated;

DROP POLICY IF EXISTS "Create reminders" ON reminders;
DROP POLICY IF EXISTS "Validated create reminders" ON reminders;
REVOKE INSERT, UPDATE, DELETE ON reminders FROM anon, authenticated;

DROP POLICY IF EXISTS "Public read reviews" ON reviews;
DROP POLICY IF EXISTS "Public create reviews" ON reviews;
DROP POLICY IF EXISTS "Verified create reviews" ON reviews;
DROP POLICY IF EXISTS "Authorized read reviews" ON reviews;
DROP POLICY IF EXISTS "Admin delete reviews" ON reviews;
CREATE POLICY "Authorized read reviews" ON reviews FOR SELECT TO authenticated
  USING (is_admin() OR appointment_id IN (
    SELECT id FROM appointments WHERE clinic_id = get_current_clinic_id()
  ));
CREATE POLICY "Admin delete reviews" ON reviews FOR DELETE TO authenticated
  USING (is_admin());
REVOKE SELECT ON reviews FROM anon, authenticated;
REVOKE INSERT, UPDATE ON reviews FROM anon, authenticated;

DROP POLICY IF EXISTS "User self-insert clinic_user" ON clinic_users;
DROP POLICY IF EXISTS "User read own clinic_user" ON clinic_users;
DROP POLICY IF EXISTS "Admin manage clinic_users" ON clinic_users;
DROP POLICY IF EXISTS "Admin delete clinic_users" ON clinic_users;
CREATE POLICY "User read own clinic_user" ON clinic_users FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR is_admin());
CREATE POLICY "Admin manage clinic_users" ON clinic_users FOR ALL TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());
REVOKE INSERT, UPDATE, DELETE ON clinic_users FROM authenticated;

DROP POLICY IF EXISTS "User read own admin_user" ON admin_users;
DROP POLICY IF EXISTS "Admin manage admin_users" ON admin_users;
CREATE POLICY "User read own admin_user" ON admin_users FOR SELECT TO authenticated
  USING (user_id = auth.uid());
CREATE POLICY "Admin manage admin_users" ON admin_users FOR ALL TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());
REVOKE INSERT, UPDATE, DELETE ON admin_users FROM authenticated;

-- ============================================================
-- 5. Security tables
-- ============================================================

CREATE TABLE IF NOT EXISTS audit_log (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  action TEXT NOT NULL,
  target_table TEXT,
  target_id TEXT,
  details JSONB DEFAULT '{}'::JSONB,
  actor_type TEXT DEFAULT 'user',
  actor_id UUID,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admin read audit_log" ON audit_log;
DROP POLICY IF EXISTS "Admin manage audit_log" ON audit_log;
CREATE POLICY "Admin read audit_log" ON audit_log FOR SELECT TO authenticated
  USING (is_admin());

CREATE TABLE IF NOT EXISTS appointment_status_log (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  appointment_id UUID NOT NULL REFERENCES appointments(id) ON DELETE CASCADE,
  old_status TEXT,
  new_status TEXT NOT NULL CHECK (new_status IN ('confirmed','completed','cancelled','no_show')),
  changed_by UUID,
  changed_by_type TEXT NOT NULL DEFAULT 'system'
    CHECK (changed_by_type IN ('patient','clinic','admin','system')),
  reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE appointment_status_log
  DROP CONSTRAINT IF EXISTS appointment_status_log_new_status_check;
ALTER TABLE appointment_status_log
  ADD CONSTRAINT appointment_status_log_new_status_check
  CHECK (new_status IN ('confirmed','completed','cancelled','no_show'));
ALTER TABLE appointment_status_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Clinic view own status logs" ON appointment_status_log;
DROP POLICY IF EXISTS "Clinic insert own status logs" ON appointment_status_log;
CREATE POLICY "Clinic view own status logs" ON appointment_status_log FOR SELECT TO authenticated
  USING (appointment_id IN (
    SELECT id FROM appointments WHERE clinic_id = get_current_clinic_id()
  ) OR is_admin());

CREATE TABLE IF NOT EXISTS payments (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  appointment_id UUID NOT NULL REFERENCES appointments(id) ON DELETE CASCADE,
  gateway TEXT NOT NULL CHECK (gateway IN ('zaincash','asiahawala','clinic','manual')),
  amount INT NOT NULL CHECK (amount >= 0),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','completed','failed','refunded')),
  external_ref TEXT UNIQUE,
  gateway_response JSONB DEFAULT '{}'::JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Clinic view own payments" ON payments;
DROP POLICY IF EXISTS "Admin manage payments" ON payments;
CREATE POLICY "Clinic view own payments" ON payments FOR SELECT TO authenticated
  USING (appointment_id IN (
    SELECT id FROM appointments WHERE clinic_id = get_current_clinic_id()
  ) OR is_admin());
CREATE POLICY "Admin manage payments" ON payments FOR ALL TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());

CREATE TABLE IF NOT EXISTS rate_limit (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  identifier TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE rate_limit ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Deny all rate_limit" ON rate_limit;
CREATE POLICY "Deny all rate_limit" ON rate_limit FOR ALL
  USING (false) WITH CHECK (false);

CREATE OR REPLACE FUNCTION private.consume_rate_limit(
  p_identifier TEXT,
  p_endpoint TEXT,
  p_max_requests INT,
  p_window_minutes INT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_count INT;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext(p_endpoint || ':' || p_identifier));
  DELETE FROM public.rate_limit
  WHERE created_at < NOW() - INTERVAL '24 hours';

  SELECT COUNT(*) INTO v_count
  FROM public.rate_limit
  WHERE identifier = p_identifier
    AND endpoint = p_endpoint
    AND created_at > NOW() - make_interval(mins => p_window_minutes);

  IF v_count >= p_max_requests THEN
    RETURN false;
  END IF;
  INSERT INTO public.rate_limit(identifier, endpoint)
  VALUES (p_identifier, p_endpoint);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION private.consume_rate_limit(TEXT, TEXT, INT, INT)
  FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS notifications_log (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID,
  appointment_id UUID REFERENCES appointments(id) ON DELETE SET NULL,
  channel TEXT NOT NULL CHECK (channel IN ('whatsapp','sms','email','push')),
  template TEXT NOT NULL,
  recipient_phone TEXT,
  recipient_name TEXT,
  content TEXT,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','sent','delivered','failed','read')),
  provider_message_id TEXT,
  error_message TEXT,
  sent_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE notifications_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Clinic view own notifications" ON notifications_log;
DROP POLICY IF EXISTS "Admin manage notifications" ON notifications_log;
CREATE POLICY "Clinic view own notifications" ON notifications_log FOR SELECT TO authenticated
  USING (appointment_id IN (
    SELECT id FROM appointments WHERE clinic_id = get_current_clinic_id()
  ) OR is_admin());

CREATE TABLE IF NOT EXISTS staff_roles (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  clinic_id UUID NOT NULL REFERENCES clinics(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'secretary' CHECK (role IN ('secretary','doctor','manager')),
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(clinic_id, user_id)
);
ALTER TABLE staff_roles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "User read own staff_role" ON staff_roles;
DROP POLICY IF EXISTS "Clinic read own staff_roles" ON staff_roles;
DROP POLICY IF EXISTS "User self-insert staff_role" ON staff_roles;
DROP POLICY IF EXISTS "Clinic manage own staff_roles" ON staff_roles;
DROP POLICY IF EXISTS "Clinic delete own staff_roles" ON staff_roles;
CREATE POLICY "User read own staff_role" ON staff_roles FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR clinic_id = get_current_clinic_id() OR is_admin());
CREATE POLICY "Clinic manage own staff_roles" ON staff_roles FOR ALL TO authenticated
  USING (clinic_id = get_current_clinic_id() OR is_admin())
  WITH CHECK (clinic_id = get_current_clinic_id() OR is_admin());

CREATE OR REPLACE FUNCTION private.log_appointment_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor_type TEXT;
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    v_actor_type := NULLIF(current_setting('sahhatna.actor_type', true), '');
    IF v_actor_type IS NULL THEN
      v_actor_type := CASE
        WHEN public.is_admin() THEN 'admin'
        WHEN public.is_clinic_user() THEN 'clinic'
        ELSE 'system'
      END;
    END IF;

    INSERT INTO public.appointment_status_log (
      appointment_id, old_status, new_status, changed_by, changed_by_type
    ) VALUES (
      NEW.id, OLD.status, NEW.status, auth.uid(), v_actor_type
    );
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.log_appointment_status_change() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_log_appointment_status ON appointments;
CREATE TRIGGER trg_log_appointment_status
  AFTER UPDATE OF status ON appointments
  FOR EACH ROW EXECUTE FUNCTION private.log_appointment_status_change();

-- ============================================================
-- 6. Private encryption implementation
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM vault.decrypted_secrets WHERE name = 'sahatna_field_key'
  ) THEN
    PERFORM vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'sahatna_field_key',
      'Sahhatna field encryption key'
    );
  END IF;
END $$;

CREATE OR REPLACE FUNCTION private.get_encryption_key()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
DECLARE
  v_key TEXT;
BEGIN
  SELECT decrypted_secret INTO v_key
  FROM vault.decrypted_secrets
  WHERE name = 'sahatna_field_key'
  LIMIT 1;
  IF v_key IS NULL THEN
    RAISE EXCEPTION 'Sahhatna encryption key is missing';
  END IF;
  RETURN v_key;
END;
$$;

REVOKE ALL ON FUNCTION private.get_encryption_key() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.bootstrap_admin(
  p_user_id UUID,
  p_username TEXT,
  p_name TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'Supabase Auth user does not exist';
  END IF;
  IF p_username !~ '^[a-z0-9_]{3,40}$' THEN
    RAISE EXCEPTION 'Invalid admin username';
  END IF;
  INSERT INTO public.admin_users(user_id, username, name)
  VALUES (p_user_id, p_username, p_name)
  ON CONFLICT (username) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    name = EXCLUDED.name
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION private.bootstrap_admin(UUID, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;

-- Verify existing ciphertext with the current Vault key. A previous broken
-- migration encrypted the literal marker instead of the original note; stop
-- rather than silently accepting that data loss. Properly migrated rows make
-- this block and the following updates safe to rerun.
DO $$
BEGIN
  BEGIN
    PERFORM extensions.pgp_sym_decrypt(
      patient_notes_encrypted,
      private.get_encryption_key()
    )
    FROM appointments
    WHERE patient_notes_encrypted IS NOT NULL;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION
      'Existing encrypted notes cannot be decrypted with the current Vault key. Restore the correct key or backup before continuing.';
  END;

  IF EXISTS (
    SELECT 1
    FROM appointments
    WHERE patient_notes_encrypted IS NOT NULL
      AND extensions.pgp_sym_decrypt(
        patient_notes_encrypted,
        private.get_encryption_key()
      ) = '[محمي]'
  ) THEN
    RAISE EXCEPTION
      'A legacy migration encrypted the protection marker instead of the original note. Restore from backup before continuing.';
  END IF;
END $$;

UPDATE appointments
SET patient_notes_encrypted = extensions.pgp_sym_encrypt(
      patient_notes,
      private.get_encryption_key()
    )
WHERE patient_notes IS NOT NULL
  AND patient_notes <> ''
  AND patient_notes_encrypted IS NULL;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM appointments
    WHERE patient_notes_encrypted IS NOT NULL
      AND patient_notes IS NOT NULL
      AND patient_notes <> '[محمي]'
      AND extensions.pgp_sym_decrypt(
        patient_notes_encrypted,
        private.get_encryption_key()
      ) IS DISTINCT FROM patient_notes
  ) THEN
    RAISE EXCEPTION 'Patient note encryption verification failed';
  END IF;
END $$;

UPDATE appointments
SET patient_notes = '[محمي]'
WHERE patient_notes_encrypted IS NOT NULL
  AND patient_notes IS DISTINCT FROM '[محمي]';

CREATE OR REPLACE FUNCTION private.encrypt_appointment_notes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.patient_notes IS NULL OR NEW.patient_notes = '' OR NEW.patient_notes = '[محمي]' THEN
    RETURN NEW;
  END IF;
  NEW.patient_notes_encrypted := extensions.pgp_sym_encrypt(
    NEW.patient_notes,
    private.get_encryption_key()
  );
  NEW.patient_notes := '[محمي]';
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.encrypt_appointment_notes() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_encrypt_appointment_notes ON appointments;
CREATE TRIGGER trg_encrypt_appointment_notes
  BEFORE INSERT OR UPDATE OF patient_notes ON appointments
  FOR EACH ROW EXECUTE FUNCTION private.encrypt_appointment_notes();

-- Remove old client-callable key/decryption functions.
DROP FUNCTION IF EXISTS get_encryption_key();
DROP FUNCTION IF EXISTS encrypt_field(TEXT);
DROP FUNCTION IF EXISTS decrypt_field(BYTEA);
DROP FUNCTION IF EXISTS rotate_encryption_key(TEXT);

-- ============================================================
-- 7. Canonical RPC functions
-- ============================================================

DROP FUNCTION IF EXISTS log_audit_entry(TEXT, TEXT, UUID, JSONB, TEXT);
DROP FUNCTION IF EXISTS log_audit_entry(TEXT, TEXT, TEXT, JSONB, TEXT);
CREATE FUNCTION log_audit_entry(
  p_action TEXT,
  p_target_table TEXT,
  p_target_id TEXT DEFAULT NULL,
  p_details JSONB DEFAULT '{}'::JSONB,
  p_actor_type TEXT DEFAULT 'user'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin authentication required';
  END IF;
  INSERT INTO public.audit_log (
    actor_id, actor_type, action, target_table, target_id, details
  ) VALUES (
    auth.uid(), 'user', p_action, p_target_table, p_target_id,
    COALESCE(p_details, '{}'::JSONB)
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION log_audit_entry(TEXT, TEXT, TEXT, JSONB, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION log_audit_entry(TEXT, TEXT, TEXT, JSONB, TEXT) TO authenticated;

DROP FUNCTION IF EXISTS create_appointment(
  UUID, UUID, TEXT, TEXT, INT, TEXT, TEXT, TEXT, TEXT, INT, TEXT
);
CREATE FUNCTION create_appointment(
  p_doctor_id UUID,
  p_clinic_id UUID,
  p_patient_name TEXT,
  p_patient_phone TEXT,
  p_patient_age INT,
  p_patient_notes TEXT,
  p_date TEXT,
  p_time TEXT,
  p_service TEXT,
  p_price INT,
  p_payment_method TEXT DEFAULT 'clinic'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_appointment public.appointments%ROWTYPE;
  v_doctor public.doctors%ROWTYPE;
  v_clinic public.clinics%ROWTYPE;
  v_schedule public.schedules%ROWTYPE;
  v_date DATE;
  v_time TIME;
BEGIN
  IF p_patient_name IS NULL OR length(trim(p_patient_name)) NOT BETWEEN 2 AND 120 THEN
    RAISE EXCEPTION 'اسم المريض يجب أن يكون بين 2 و120 محرفاً';
  END IF;
  IF p_patient_phone IS NULL OR p_patient_phone !~ '^07[0-9]{9}$' THEN
    RAISE EXCEPTION 'رقم الهاتف يجب أن يكون بصيغة عراقية 07XXXXXXXXX';
  END IF;
  IF NOT private.consume_rate_limit(
    encode(extensions.digest(p_patient_phone, 'sha256'), 'hex'), 'booking', 5, 15
  ) THEN
    RAISE EXCEPTION 'محاولات حجز كثيرة. حاول لاحقاً';
  END IF;
  IF p_patient_age IS NOT NULL AND p_patient_age NOT BETWEEN 0 AND 120 THEN
    RAISE EXCEPTION 'عمر المريض غير صحيح';
  END IF;
  IF p_patient_notes IS NOT NULL AND length(p_patient_notes) > 2000 THEN
    RAISE EXCEPTION 'الملاحظات طويلة جداً';
  END IF;
  IF p_date IS NULL OR p_date !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
    RAISE EXCEPTION 'صيغة التاريخ غير صحيحة';
  END IF;
  IF p_time IS NULL OR p_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
    RAISE EXCEPTION 'صيغة الوقت غير صحيحة';
  END IF;

  BEGIN
    v_date := p_date::DATE;
    v_time := p_time::TIME;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'التاريخ أو الوقت غير صالح';
  END;

  IF v_date < (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Baghdad')::DATE
     OR (
       v_date = (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Baghdad')::DATE
       AND v_time <= (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Baghdad')::TIME
     ) THEN
    RAISE EXCEPTION 'لا يمكن الحجز بتاريخ سابق';
  END IF;
  IF p_service NOT IN ('clinic','video','home') THEN
    RAISE EXCEPTION 'نوع الخدمة غير صحيح';
  END IF;
  IF p_payment_method NOT IN ('clinic') THEN
    RAISE EXCEPTION 'طريقة الدفع غير مدعومة حالياً';
  END IF;

  SELECT * INTO v_doctor FROM public.doctors WHERE id = p_doctor_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'الطبيب غير موجود'; END IF;

  SELECT * INTO v_clinic FROM public.clinics WHERE id = p_clinic_id;
  IF NOT FOUND OR v_clinic.status <> 'approved' THEN
    RAISE EXCEPTION 'العيادة غير موجودة أو غير معتمدة';
  END IF;
  IF v_doctor.clinic_id <> p_clinic_id THEN
    RAISE EXCEPTION 'الطبيب لا يتبع هذه العيادة';
  END IF;
  IF NOT (
    p_service = ANY(COALESCE(v_doctor.services, ARRAY[]::TEXT[]))
  ) THEN
    RAISE EXCEPTION 'الخدمة غير متاحة لهذا الطبيب';
  END IF;
  IF p_price <> v_doctor.price THEN
    RAISE EXCEPTION 'السعر لا يطابق سعر الطبيب الحالي';
  END IF;

  SELECT * INTO v_schedule
  FROM public.schedules
  WHERE doctor_id = p_doctor_id
    AND day = EXTRACT(DOW FROM v_date)::INT;
  IF NOT FOUND
     OR v_time < v_schedule.start_time::TIME
     OR v_time + make_interval(mins => v_schedule.slot_duration) > v_schedule.end_time::TIME
     OR MOD(
       EXTRACT(EPOCH FROM (v_time - v_schedule.start_time::TIME))::INT / 60,
       v_schedule.slot_duration
     ) <> 0 THEN
    RAISE EXCEPTION 'الموعد خارج جدول الطبيب';
  END IF;

  BEGIN
    INSERT INTO public.appointments (
      doctor_id, clinic_id, patient_name, patient_phone, patient_age,
      patient_notes, date, time, service, price, status, payment_method
    ) VALUES (
      p_doctor_id, p_clinic_id, trim(p_patient_name), p_patient_phone,
      p_patient_age, NULLIF(trim(p_patient_notes), ''), p_date, p_time,
      p_service, v_doctor.price, 'confirmed', p_payment_method
    ) RETURNING * INTO v_appointment;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'هذا الموعد محجوز بالفعل';
  END;

  INSERT INTO public.reminders (
    appointment_id, patient_name, patient_phone, doctor_name,
    clinic_name, date, time
  ) VALUES (
    v_appointment.id, v_appointment.patient_name, v_appointment.patient_phone,
    v_doctor.name, v_clinic.name, v_appointment.date, v_appointment.time
  );

  INSERT INTO public.audit_log (
    action, target_table, target_id, details, actor_type
  ) VALUES (
    'appointment.create', 'appointments', v_appointment.id::TEXT,
    jsonb_build_object(
      'doctor_id', p_doctor_id,
      'clinic_id', p_clinic_id,
      'date', p_date,
      'time', p_time
    ),
    'anon'
  );

  RETURN json_build_object(
    'id', v_appointment.id,
    'doctor_id', v_appointment.doctor_id,
    'clinic_id', v_appointment.clinic_id,
    'patient_name', v_appointment.patient_name,
    'patient_phone', v_appointment.patient_phone,
    'patient_age', v_appointment.patient_age,
    'patient_notes', CASE WHEN v_appointment.patient_notes_encrypted IS NULL THEN NULL ELSE '[محمي]' END,
    'date', v_appointment.date,
    'time', v_appointment.time,
    'service', v_appointment.service,
    'price', v_appointment.price,
    'status', v_appointment.status,
    'payment_method', v_appointment.payment_method,
    'created_at', v_appointment.created_at
  );
END;
$$;
REVOKE ALL ON FUNCTION create_appointment(
  UUID, UUID, TEXT, TEXT, INT, TEXT, TEXT, TEXT, TEXT, INT, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_appointment(
  UUID, UUID, TEXT, TEXT, INT, TEXT, TEXT, TEXT, TEXT, INT, TEXT
) TO anon, authenticated;

DROP FUNCTION IF EXISTS get_patient_bookings(TEXT);

CREATE OR REPLACE FUNCTION get_patient_booking(
  p_booking_id UUID,
  p_phone TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_result JSON;
BEGIN
  IF p_phone !~ '^07[0-9]{9}$' THEN
    RAISE EXCEPTION 'رقم الهاتف غير صحيح';
  END IF;
  IF NOT private.consume_rate_limit(
    encode(extensions.digest(p_booking_id::TEXT || ':' || p_phone, 'sha256'), 'hex'),
    'patient_booking_lookup', 10, 15
  ) THEN
    RAISE EXCEPTION 'محاولات استرجاع كثيرة. حاول لاحقاً';
  END IF;
  SELECT json_build_object(
    'id', a.id,
    'doctor_id', a.doctor_id,
    'clinic_id', a.clinic_id,
    'patient_name', a.patient_name,
    'patient_phone', a.patient_phone,
    'patient_age', a.patient_age,
    'patient_notes', CASE
      WHEN a.patient_notes_encrypted IS NULL THEN NULL
      ELSE extensions.pgp_sym_decrypt(a.patient_notes_encrypted, private.get_encryption_key())
    END,
    'date', a.date,
    'time', a.time,
    'service', a.service,
    'price', a.price,
    'status', a.status,
    'payment_method', a.payment_method,
    'reviewed', EXISTS(
      SELECT 1 FROM public.reviews r WHERE r.appointment_id = a.id
    ),
    'created_at', a.created_at
  ) INTO v_result
  FROM public.appointments a
  WHERE a.id = p_booking_id AND a.patient_phone = p_phone;
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION get_patient_booking(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_patient_booking(UUID, TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION cancel_patient_booking(
  p_booking_id UUID,
  p_phone TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_appointment public.appointments%ROWTYPE;
BEGIN
  IF p_phone !~ '^07[0-9]{9}$' THEN
    RAISE EXCEPTION 'رقم الهاتف غير صحيح';
  END IF;
  IF NOT private.consume_rate_limit(
    encode(extensions.digest(p_booking_id::TEXT || ':' || p_phone, 'sha256'), 'hex'),
    'patient_booking_cancel', 5, 15
  ) THEN
    RAISE EXCEPTION 'محاولات إلغاء كثيرة. حاول لاحقاً';
  END IF;
  PERFORM set_config('sahhatna.actor_type', 'patient', true);
  UPDATE public.appointments
  SET status = 'cancelled', updated_at = NOW()
  WHERE id = p_booking_id
    AND patient_phone = p_phone
    AND status = 'confirmed'
    AND (date::DATE + time::TIME) > (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Baghdad')
  RETURNING * INTO v_appointment;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'الحجز غير موجود أو لا يمكن إلغاؤه';
  END IF;

  RETURN json_build_object(
    'id', v_appointment.id,
    'status', v_appointment.status,
    'date', v_appointment.date,
    'time', v_appointment.time
  );
END;
$$;
REVOKE ALL ON FUNCTION cancel_patient_booking(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION cancel_patient_booking(UUID, TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION get_clinic_appointments()
RETURNS TABLE (
  id UUID,
  doctor_id UUID,
  clinic_id UUID,
  patient_name TEXT,
  patient_phone TEXT,
  patient_age INT,
  patient_notes TEXT,
  date TEXT,
  "time" TEXT,
  service TEXT,
  price INT,
  status TEXT,
  payment_method TEXT,
  payment_status TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL OR (NOT public.is_admin() AND NOT public.is_clinic_user()) THEN
    RAISE EXCEPTION 'Clinic or admin authentication required';
  END IF;
  RETURN QUERY
  SELECT
    a.id, a.doctor_id, a.clinic_id, a.patient_name, a.patient_phone,
    a.patient_age,
    CASE
      WHEN a.patient_notes_encrypted IS NULL THEN NULL
      ELSE extensions.pgp_sym_decrypt(a.patient_notes_encrypted, private.get_encryption_key())
    END,
    a.date, a.time, a.service, a.price, a.status, a.payment_method,
    a.payment_status, a.created_at, a.updated_at
  FROM public.appointments a
  WHERE public.is_admin() OR a.clinic_id = public.get_current_clinic_id();
END;
$$;
REVOKE ALL ON FUNCTION get_clinic_appointments() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_clinic_appointments() TO authenticated;

CREATE OR REPLACE FUNCTION mark_reminder_sent(p_reminder_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_reminder public.reminders%ROWTYPE;
BEGIN
  UPDATE public.reminders r
  SET sent = true, sent_at = NOW()
  WHERE r.id = p_reminder_id
    AND (
      public.is_admin()
      OR r.appointment_id IN (
        SELECT a.id FROM public.appointments a
        WHERE a.clinic_id = public.get_current_clinic_id()
      )
    )
  RETURNING * INTO v_reminder;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'التذكير غير موجود أو غير مخول لتعديله';
  END IF;
  INSERT INTO public.audit_log(actor_id, actor_type, action, target_table, target_id, details)
  VALUES (
    auth.uid(), CASE WHEN public.is_admin() THEN 'admin' ELSE 'clinic' END,
    'reminder.mark_sent', 'reminders', v_reminder.id::TEXT,
    jsonb_build_object('appointment_id', v_reminder.appointment_id)
  );
  RETURN row_to_json(v_reminder);
END;
$$;
REVOKE ALL ON FUNCTION mark_reminder_sent(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mark_reminder_sent(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION update_appointment_status(
  p_booking_id UUID,
  p_status TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_appointment public.appointments%ROWTYPE;
BEGIN
  IF p_status NOT IN ('completed','cancelled','no_show') THEN
    RAISE EXCEPTION 'حالة الحجز غير صحيحة';
  END IF;

  SELECT * INTO v_appointment
  FROM public.appointments
  WHERE id = p_booking_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'الحجز غير موجود';
  END IF;
  IF NOT public.is_admin()
     AND v_appointment.clinic_id <> public.get_current_clinic_id() THEN
    RAISE EXCEPTION 'غير مخول لتحديث هذا الحجز';
  END IF;
  IF v_appointment.status <> 'confirmed' THEN
    RAISE EXCEPTION 'لا يمكن تغيير حالة هذا الحجز';
  END IF;

  UPDATE public.appointments
  SET status = p_status
  WHERE id = p_booking_id
  RETURNING * INTO v_appointment;

  RETURN json_build_object(
    'id', v_appointment.id,
    'doctor_id', v_appointment.doctor_id,
    'clinic_id', v_appointment.clinic_id,
    'patient_name', v_appointment.patient_name,
    'patient_phone', v_appointment.patient_phone,
    'patient_age', v_appointment.patient_age,
    'patient_notes', CASE
      WHEN v_appointment.patient_notes_encrypted IS NULL THEN NULL
      ELSE extensions.pgp_sym_decrypt(
        v_appointment.patient_notes_encrypted,
        private.get_encryption_key()
      )
    END,
    'date', v_appointment.date,
    'time', v_appointment.time,
    'service', v_appointment.service,
    'price', v_appointment.price,
    'status', v_appointment.status,
    'payment_method', v_appointment.payment_method,
    'payment_status', v_appointment.payment_status,
    'created_at', v_appointment.created_at,
    'updated_at', v_appointment.updated_at
  );
END;
$$;
REVOKE ALL ON FUNCTION update_appointment_status(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION update_appointment_status(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION replace_doctor_schedule(
  p_doctor_id UUID,
  p_slots JSONB,
  p_slot_duration INT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_clinic_id UUID;
  v_slot JSONB;
  v_day INT;
  v_start TEXT;
  v_end TEXT;
BEGIN
  IF p_slot_duration NOT BETWEEN 5 AND 240 THEN
    RAISE EXCEPTION 'مدة الموعد غير صحيحة';
  END IF;
  IF jsonb_typeof(p_slots) <> 'array' OR jsonb_array_length(p_slots) > 7 THEN
    RAISE EXCEPTION 'جدول الدوام غير صحيح';
  END IF;

  SELECT clinic_id INTO v_clinic_id
  FROM public.doctors WHERE id = p_doctor_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'الطبيب غير موجود'; END IF;
  IF NOT public.is_admin() AND v_clinic_id <> public.get_current_clinic_id() THEN
    RAISE EXCEPTION 'غير مخول لتعديل جدول هذا الطبيب';
  END IF;

  DELETE FROM public.schedules WHERE doctor_id = p_doctor_id;
  FOR v_slot IN SELECT value FROM jsonb_array_elements(p_slots)
  LOOP
    v_day := (v_slot->>'day')::INT;
    v_start := v_slot->>'start';
    v_end := v_slot->>'end';
    IF v_day NOT BETWEEN 0 AND 6
       OR v_start !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
       OR v_end !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
       OR v_start::TIME >= v_end::TIME THEN
      RAISE EXCEPTION 'وقت دوام غير صحيح';
    END IF;
    INSERT INTO public.schedules(
      doctor_id, day, start_time, end_time, slot_duration
    ) VALUES (p_doctor_id, v_day, v_start, v_end, p_slot_duration);
  END LOOP;
  INSERT INTO public.audit_log(actor_id, actor_type, action, target_table, target_id, details)
  VALUES (
    auth.uid(), CASE WHEN public.is_admin() THEN 'admin' ELSE 'clinic' END,
    'schedule.update', 'schedules', p_doctor_id::TEXT,
    jsonb_build_object('slots_count', jsonb_array_length(p_slots), 'slot_duration', p_slot_duration)
  );
END;
$$;
REVOKE ALL ON FUNCTION replace_doctor_schedule(UUID, JSONB, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION replace_doctor_schedule(UUID, JSONB, INT) TO authenticated;

CREATE OR REPLACE FUNCTION create_doctor(
  p_name TEXT,
  p_name_en TEXT,
  p_specialty_id TEXT,
  p_clinic_id UUID,
  p_photo TEXT,
  p_bio TEXT,
  p_qualifications TEXT,
  p_experience_years INT,
  p_price INT,
  p_gender TEXT,
  p_languages TEXT[],
  p_services TEXT[]
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_doctor public.doctors%ROWTYPE;
BEGIN
  IF NOT public.is_admin() AND p_clinic_id <> public.get_current_clinic_id() THEN
    RAISE EXCEPTION 'غير مخول لإضافة طبيب لهذه العيادة';
  END IF;
  IF length(trim(p_name)) < 3 OR p_price <= 0
     OR p_gender NOT IN ('male','female')
     OR p_experience_years NOT BETWEEN 0 AND 80
     OR NOT EXISTS (SELECT 1 FROM public.specialties WHERE id = p_specialty_id)
     OR NOT EXISTS (SELECT 1 FROM public.clinics WHERE id = p_clinic_id AND status = 'approved') THEN
    RAISE EXCEPTION 'بيانات الطبيب غير صحيحة';
  END IF;

  INSERT INTO public.doctors (
    name, name_en, specialty_id, clinic_id, photo, bio, qualifications,
    experience_years, price, gender, languages, services,
    rating, reviews_count, verified, featured
  ) VALUES (
    trim(p_name), NULLIF(trim(p_name_en), ''), p_specialty_id, p_clinic_id,
    COALESCE(p_photo, ''), COALESCE(p_bio, ''), COALESCE(p_qualifications, ''),
    p_experience_years, p_price, p_gender,
    COALESCE(p_languages, ARRAY['العربية']::TEXT[]),
    COALESCE(p_services, ARRAY['clinic']::TEXT[]),
    0, 0, false, false
  ) RETURNING * INTO v_doctor;
  INSERT INTO public.audit_log(actor_id, actor_type, action, target_table, target_id, details)
  VALUES (
    auth.uid(), CASE WHEN public.is_admin() THEN 'admin' ELSE 'clinic' END,
    'doctor.create', 'doctors', v_doctor.id::TEXT,
    jsonb_build_object('clinic_id', v_doctor.clinic_id, 'specialty_id', v_doctor.specialty_id)
  );
  RETURN row_to_json(v_doctor);
END;
$$;
REVOKE ALL ON FUNCTION create_doctor(
  TEXT, TEXT, TEXT, UUID, TEXT, TEXT, TEXT, INT, INT, TEXT, TEXT[], TEXT[]
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_doctor(
  TEXT, TEXT, TEXT, UUID, TEXT, TEXT, TEXT, INT, INT, TEXT, TEXT[], TEXT[]
) TO authenticated;

CREATE OR REPLACE FUNCTION update_doctor(
  p_doctor_id UUID,
  p_updates JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_doctor public.doctors%ROWTYPE;
  v_is_admin BOOLEAN;
BEGIN
  SELECT * INTO v_doctor FROM public.doctors WHERE id = p_doctor_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'الطبيب غير موجود'; END IF;
  v_is_admin := public.is_admin();
  IF NOT v_is_admin AND v_doctor.clinic_id <> public.get_current_clinic_id() THEN
    RAISE EXCEPTION 'غير مخول لتعديل هذا الطبيب';
  END IF;
  IF p_updates ?| ARRAY['id','clinic_id','rating','reviews_count','created_at'] THEN
    RAISE EXCEPTION 'محاولة تعديل حقول محمية';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_object_keys(p_updates) AS keys(key_name)
    WHERE key_name NOT IN (
      'name','name_en','specialty_id','photo','bio','qualifications',
      'experience_years','price','gender','languages','services',
      'verified','featured'
    )
  ) THEN
    RAISE EXCEPTION 'حقل تعديل غير معروف';
  END IF;
  IF NOT v_is_admin AND p_updates ?| ARRAY['verified','featured'] THEN
    RAISE EXCEPTION 'فقط الإدارة تعدّل حالة التوثيق والتمييز';
  END IF;

  UPDATE public.doctors SET
    name = CASE WHEN p_updates ? 'name' THEN trim(p_updates->>'name') ELSE name END,
    name_en = CASE WHEN p_updates ? 'name_en' THEN NULLIF(trim(p_updates->>'name_en'), '') ELSE name_en END,
    specialty_id = CASE WHEN p_updates ? 'specialty_id' THEN p_updates->>'specialty_id' ELSE specialty_id END,
    photo = CASE WHEN p_updates ? 'photo' THEN p_updates->>'photo' ELSE photo END,
    bio = CASE WHEN p_updates ? 'bio' THEN p_updates->>'bio' ELSE bio END,
    qualifications = CASE WHEN p_updates ? 'qualifications' THEN p_updates->>'qualifications' ELSE qualifications END,
    experience_years = CASE WHEN p_updates ? 'experience_years' THEN (p_updates->>'experience_years')::INT ELSE experience_years END,
    price = CASE WHEN p_updates ? 'price' THEN (p_updates->>'price')::INT ELSE price END,
    gender = CASE WHEN p_updates ? 'gender' THEN p_updates->>'gender' ELSE gender END,
    languages = CASE WHEN p_updates ? 'languages' THEN ARRAY(SELECT jsonb_array_elements_text(p_updates->'languages')) ELSE languages END,
    services = CASE WHEN p_updates ? 'services' THEN ARRAY(SELECT jsonb_array_elements_text(p_updates->'services')) ELSE services END,
    verified = CASE WHEN v_is_admin AND p_updates ? 'verified' THEN (p_updates->>'verified')::BOOLEAN ELSE verified END,
    featured = CASE WHEN v_is_admin AND p_updates ? 'featured' THEN (p_updates->>'featured')::BOOLEAN ELSE featured END
  WHERE id = p_doctor_id
  RETURNING * INTO v_doctor;

  IF length(trim(v_doctor.name)) < 3 OR v_doctor.price <= 0
     OR v_doctor.gender NOT IN ('male','female')
     OR v_doctor.experience_years NOT BETWEEN 0 AND 80
     OR NOT EXISTS (SELECT 1 FROM public.specialties WHERE id = v_doctor.specialty_id) THEN
    RAISE EXCEPTION 'بيانات الطبيب غير صحيحة';
  END IF;
  INSERT INTO public.audit_log(actor_id, actor_type, action, target_table, target_id, details)
  VALUES (
    auth.uid(), CASE WHEN v_is_admin THEN 'admin' ELSE 'clinic' END,
    'doctor.update', 'doctors', v_doctor.id::TEXT,
    jsonb_build_object('fields', ARRAY(SELECT jsonb_object_keys(p_updates)))
  );
  RETURN row_to_json(v_doctor);
END;
$$;
REVOKE ALL ON FUNCTION update_doctor(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION update_doctor(UUID, JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION delete_or_deactivate_doctor(p_doctor_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_clinic_id UUID;
BEGIN
  SELECT clinic_id INTO v_clinic_id
  FROM public.doctors WHERE id = p_doctor_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'الطبيب غير موجود'; END IF;
  IF NOT public.is_admin() AND v_clinic_id <> public.get_current_clinic_id() THEN
    RAISE EXCEPTION 'غير مخول لحذف هذا الطبيب';
  END IF;

  IF EXISTS (SELECT 1 FROM public.appointments WHERE doctor_id = p_doctor_id) THEN
    UPDATE public.doctors
    SET active = false, verified = false, featured = false
    WHERE id = p_doctor_id;
  ELSE
    DELETE FROM public.doctors WHERE id = p_doctor_id;
  END IF;
  INSERT INTO public.audit_log(actor_id, actor_type, action, target_table, target_id, details)
  VALUES (
    auth.uid(), CASE WHEN public.is_admin() THEN 'admin' ELSE 'clinic' END,
    'doctor.delete_or_deactivate', 'doctors', p_doctor_id::TEXT,
    jsonb_build_object('clinic_id', v_clinic_id)
  );
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION delete_or_deactivate_doctor(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION delete_or_deactivate_doctor(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION register_clinic(
  p_name TEXT,
  p_city_id TEXT,
  p_area TEXT,
  p_address TEXT,
  p_phone TEXT,
  p_lat DECIMAL DEFAULT 0,
  p_lng DECIMAL DEFAULT 0
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_clinic public.clinics%ROWTYPE;
BEGIN
  IF p_name IS NULL OR length(trim(p_name)) < 3 THEN
    RAISE EXCEPTION 'اسم العيادة قصير جداً';
  END IF;
  IF p_phone IS NULL OR p_phone !~ '^07[0-9]{9}$' THEN
    RAISE EXCEPTION 'رقم الهاتف غير صحيح';
  END IF;
  IF NOT private.consume_rate_limit(
    encode(extensions.digest(p_phone, 'sha256'), 'hex'), 'clinic_registration', 3, 1440
  ) THEN
    RAISE EXCEPTION 'تم تجاوز عدد محاولات تسجيل العيادة';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.cities WHERE id = p_city_id) THEN
    RAISE EXCEPTION 'المدينة غير موجودة';
  END IF;

  INSERT INTO public.clinics (
    name, city_id, area, address, phone, lat, lng, status, activation_code
  ) VALUES (
    trim(p_name), p_city_id, NULLIF(trim(p_area), ''),
    NULLIF(trim(p_address), ''), p_phone,
    COALESCE(p_lat, 0), COALESCE(p_lng, 0), 'pending', NULL
  ) RETURNING * INTO v_clinic;

  RETURN json_build_object(
    'id', v_clinic.id,
    'name', v_clinic.name,
    'city_id', v_clinic.city_id,
    'area', v_clinic.area,
    'address', v_clinic.address,
    'phone', v_clinic.phone,
    'lat', v_clinic.lat,
    'lng', v_clinic.lng,
    'status', v_clinic.status,
    'created_at', v_clinic.created_at
  );
END;
$$;
REVOKE ALL ON FUNCTION register_clinic(TEXT, TEXT, TEXT, TEXT, TEXT, DECIMAL, DECIMAL) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION register_clinic(TEXT, TEXT, TEXT, TEXT, TEXT, DECIMAL, DECIMAL)
  TO anon, authenticated;

CREATE OR REPLACE FUNCTION approve_clinic_registration(p_clinic_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_clinic public.clinics%ROWTYPE;
  v_code TEXT;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin authentication required';
  END IF;

  v_code := upper(substr(encode(extensions.gen_random_bytes(6), 'hex'), 1, 6));
  UPDATE public.clinics
  SET status = 'approved', activation_code = v_code
  WHERE id = p_clinic_id AND status = 'pending'
  RETURNING * INTO v_clinic;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'العيادة غير موجودة أو تمت معالجتها مسبقاً';
  END IF;

  INSERT INTO public.audit_log (
    actor_id, actor_type, action, target_table, target_id, details
  ) VALUES (
    auth.uid(), 'admin', 'clinic.approve', 'clinics', v_clinic.id::TEXT,
    jsonb_build_object('status', 'approved', 'activation_code_generated', true)
  );

  RETURN json_build_object(
    'id', v_clinic.id,
    'name', v_clinic.name,
    'city_id', v_clinic.city_id,
    'area', v_clinic.area,
    'address', v_clinic.address,
    'phone', v_clinic.phone,
    'lat', v_clinic.lat,
    'lng', v_clinic.lng,
    'status', v_clinic.status,
    'activation_code', v_code,
    'created_at', v_clinic.created_at
  );
END;
$$;
REVOKE ALL ON FUNCTION approve_clinic_registration(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION approve_clinic_registration(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION reject_clinic_registration(p_clinic_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_clinic public.clinics%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin authentication required';
  END IF;
  UPDATE public.clinics
  SET status = 'rejected', activation_code = NULL
  WHERE id = p_clinic_id
  RETURNING * INTO v_clinic;
  IF NOT FOUND THEN RAISE EXCEPTION 'العيادة غير موجودة'; END IF;
  INSERT INTO public.audit_log(actor_id, actor_type, action, target_table, target_id, details)
  VALUES (auth.uid(), 'admin', 'clinic.reject', 'clinics', v_clinic.id::TEXT, '{}'::JSONB);
  RETURN row_to_json(v_clinic);
END;
$$;
REVOKE ALL ON FUNCTION reject_clinic_registration(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION reject_clinic_registration(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION activate_clinic_account(
  p_clinic_name TEXT,
  p_activation_code TEXT,
  p_username TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_clinic public.clinics%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'سجّل الدخول بالحساب الجديد لإكمال التفعيل';
  END IF;
  IF NOT private.consume_rate_limit(auth.uid()::TEXT, 'clinic_activation', 5, 15) THEN
    RAISE EXCEPTION 'محاولات تفعيل كثيرة. حاول لاحقاً';
  END IF;
  IF p_username !~ '^[a-z0-9_]{3,40}$' THEN
    RAISE EXCEPTION 'اسم المستخدم غير صحيح';
  END IF;

  SELECT * INTO v_clinic
  FROM public.clinics
  WHERE name = p_clinic_name
    AND activation_code = upper(p_activation_code)
    AND status = 'approved'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'رمز التفعيل أو اسم العيادة غير صحيح';
  END IF;

  IF EXISTS (SELECT 1 FROM public.clinic_users WHERE username = p_username) THEN
    RAISE EXCEPTION 'اسم المستخدم مستخدم مسبقاً';
  END IF;
  IF EXISTS (SELECT 1 FROM public.clinic_users WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'هذا الحساب مرتبط بعيادة مسبقاً';
  END IF;

  INSERT INTO public.clinic_users (clinic_id, user_id, username, name)
  VALUES (v_clinic.id, auth.uid(), p_username, v_clinic.name || ' - مدير');

  UPDATE public.clinics SET activation_code = NULL WHERE id = v_clinic.id;

  INSERT INTO public.audit_log(actor_id, actor_type, action, target_table, target_id, details)
  VALUES (
    auth.uid(), 'clinic', 'clinic.activate', 'clinics', v_clinic.id::TEXT,
    jsonb_build_object('username', p_username)
  );

  RETURN json_build_object(
    'id', v_clinic.id,
    'name', v_clinic.name,
    'city_id', v_clinic.city_id,
    'area', v_clinic.area,
    'address', v_clinic.address,
    'phone', v_clinic.phone,
    'status', v_clinic.status
  );
END;
$$;
REVOKE ALL ON FUNCTION activate_clinic_account(TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION activate_clinic_account(TEXT, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION create_verified_review(
  p_booking_id UUID,
  p_phone TEXT,
  p_rating INT,
  p_comment TEXT DEFAULT ''
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_appointment public.appointments%ROWTYPE;
  v_review public.reviews%ROWTYPE;
BEGIN
  IF p_phone !~ '^07[0-9]{9}$' THEN
    RAISE EXCEPTION 'رقم الهاتف غير صحيح';
  END IF;
  IF NOT private.consume_rate_limit(
    encode(extensions.digest(p_booking_id::TEXT || ':' || p_phone, 'sha256'), 'hex'),
    'verified_review', 5, 60
  ) THEN
    RAISE EXCEPTION 'محاولات تقييم كثيرة. حاول لاحقاً';
  END IF;
  IF p_rating NOT BETWEEN 1 AND 5 THEN
    RAISE EXCEPTION 'التقييم يجب أن يكون بين 1 و5';
  END IF;
  IF length(COALESCE(p_comment, '')) > 2000 THEN
    RAISE EXCEPTION 'التعليق طويل جداً';
  END IF;

  SELECT * INTO v_appointment
  FROM public.appointments
  WHERE id = p_booking_id
    AND patient_phone = p_phone
    AND status = 'completed';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الحجز غير موجود أو غير مكتمل';
  END IF;

  INSERT INTO public.reviews (
    doctor_id, patient_name, patient_phone, rating,
    comment, verified, appointment_id
  ) VALUES (
    v_appointment.doctor_id, v_appointment.patient_name,
    v_appointment.patient_phone, p_rating, COALESCE(p_comment, ''),
    true, v_appointment.id
  ) RETURNING * INTO v_review;

  RETURN json_build_object(
    'id', v_review.id,
    'doctor_id', v_review.doctor_id,
    'patient_name', v_review.patient_name,
    'rating', v_review.rating,
    'comment', v_review.comment,
    'verified', v_review.verified,
    'appointment_id', v_review.appointment_id,
    'created_at', v_review.created_at
  );
END;
$$;
REVOKE ALL ON FUNCTION create_verified_review(UUID, TEXT, INT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_verified_review(UUID, TEXT, INT, TEXT) TO anon, authenticated;

-- ============================================================
-- 8. Triggers and indexes
-- ============================================================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_appointments_updated_at ON appointments;
CREATE TRIGGER trg_appointments_updated_at
  BEFORE UPDATE ON appointments
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
DROP TRIGGER IF EXISTS trg_clinics_updated_at ON clinics;
CREATE TRIGGER trg_clinics_updated_at
  BEFORE UPDATE ON clinics
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
DROP TRIGGER IF EXISTS trg_doctors_updated_at ON doctors;
CREATE TRIGGER trg_doctors_updated_at
  BEFORE UPDATE ON doctors
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
DROP TRIGGER IF EXISTS trg_payments_updated_at ON payments;
CREATE TRIGGER trg_payments_updated_at
  BEFORE UPDATE ON payments
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE UNIQUE INDEX IF NOT EXISTS reviews_appointment_unique
  ON reviews(appointment_id) WHERE appointment_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS clinic_users_user_unique
  ON clinic_users(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_log_created ON audit_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_status_log_appointment ON appointment_status_log(appointment_id);
CREATE INDEX IF NOT EXISTS idx_rate_limit_identifier
  ON rate_limit(identifier, endpoint, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_appointment ON notifications_log(appointment_id);
CREATE INDEX IF NOT EXISTS idx_payments_appointment ON payments(appointment_id);

-- Remove fixed demo identities from the production path. Demo mode remains
-- available through localStorage; production administrators are bootstrapped
-- separately through the Supabase dashboard.
DELETE FROM auth.users
WHERE id IN (
  'e0000000-0000-0000-0000-000000000001',
  'e0000000-0000-0000-0000-000000000002',
  'e0000000-0000-0000-0000-000000000003',
  'e0000000-0000-0000-0000-000000000004'
);

COMMIT;
