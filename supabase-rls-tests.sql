-- ============================================================
-- صحتنا - Production RLS and RPC test suite
-- Run after:
--   1. supabase-schema.sql
--   2. supabase-production-hardening.sql
--
-- The entire suite runs inside a transaction and always rolls back.
-- ============================================================

BEGIN;

CREATE TEMP TABLE test_results (
  test_name TEXT PRIMARY KEY,
  passed BOOLEAN NOT NULL,
  details TEXT NOT NULL DEFAULT ''
);

CREATE OR REPLACE FUNCTION pg_temp.record_test(
  p_name TEXT,
  p_passed BOOLEAN,
  p_details TEXT DEFAULT ''
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_temp
AS $$
BEGIN
  INSERT INTO pg_temp.test_results(test_name, passed, details)
  VALUES (p_name, p_passed, COALESCE(p_details, ''));
  IF p_passed THEN
    RAISE NOTICE '✅ PASS: %', p_name;
  ELSE
    RAISE WARNING '❌ FAIL: % — %', p_name, p_details;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.set_test_user(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_user_id::TEXT, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.aud', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.clear_test_user()
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'anon', true);
  PERFORM set_config('request.jwt.claim.aud', 'anon', true);
END;
$$;

-- ============================================================
-- 1. Static privilege and schema assertions
-- ============================================================

DO $$
DECLARE
  v_exists BOOLEAN;
  v_count INT;
BEGIN
  PERFORM pg_temp.record_test(
    'anon cannot select raw appointments',
    NOT has_table_privilege('anon', 'public.appointments', 'SELECT')
  );

  PERFORM pg_temp.record_test(
    'anon cannot insert raw appointments',
    NOT has_table_privilege('anon', 'public.appointments', 'INSERT')
  );

  PERFORM pg_temp.record_test(
    'anon can select public appointment slots',
    has_table_privilege('anon', 'public.public_appointment_slots', 'SELECT')
  );

  PERFORM pg_temp.record_test(
    'authenticated cannot mutate raw appointments',
    NOT has_table_privilege('authenticated', 'public.appointments', 'INSERT')
    AND NOT has_table_privilege('authenticated', 'public.appointments', 'UPDATE')
  );

  PERFORM pg_temp.record_test(
    'authenticated cannot mutate raw doctors',
    NOT has_table_privilege('authenticated', 'public.doctors', 'INSERT')
    AND NOT has_table_privilege('authenticated', 'public.doctors', 'UPDATE')
    AND NOT has_table_privilege('authenticated', 'public.doctors', 'DELETE')
  );

  PERFORM pg_temp.record_test(
    'authenticated cannot mutate raw schedules or reminders',
    NOT has_table_privilege('authenticated', 'public.schedules', 'INSERT')
    AND NOT has_table_privilege('authenticated', 'public.schedules', 'UPDATE')
    AND NOT has_table_privilege('authenticated', 'public.schedules', 'DELETE')
    AND NOT has_table_privilege('authenticated', 'public.reminders', 'INSERT')
    AND NOT has_table_privilege('authenticated', 'public.reminders', 'UPDATE')
    AND NOT has_table_privilege('authenticated', 'public.reminders', 'DELETE')
  );

  PERFORM pg_temp.record_test(
    'clients cannot create raw reviews or clinic mappings',
    NOT has_table_privilege('anon', 'public.reviews', 'INSERT')
    AND NOT has_table_privilege('authenticated', 'public.reviews', 'INSERT')
    AND NOT has_table_privilege('authenticated', 'public.clinic_users', 'INSERT')
  );

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'public_clinics'
      AND column_name = 'activation_code'
  ) INTO v_exists;
  PERFORM pg_temp.record_test(
    'public clinics does not expose activation codes',
    NOT v_exists
  );

  SELECT COUNT(*) INTO v_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'get_patient_bookings';
  PERFORM pg_temp.record_test(
    'unsafe phone-only booking RPC is absent',
    v_count = 0,
    'count=' || v_count
  );

  SELECT COUNT(*) INTO v_count
  FROM information_schema.views
  WHERE table_schema = 'public'
    AND table_name = 'clinic_appointment_details';
  PERFORM pg_temp.record_test(
    'unsafe clinic appointment view is absent',
    v_count = 0,
    'count=' || v_count
  );

  PERFORM pg_temp.record_test(
    'authenticated cannot read encryption key',
    NOT has_function_privilege(
      'authenticated',
      'private.get_encryption_key()',
      'EXECUTE'
    )
  );

  PERFORM pg_temp.record_test(
    'anon cannot read encryption key',
    NOT has_function_privilege(
      'anon',
      'private.get_encryption_key()',
      'EXECUTE'
    )
  );
END $$;

-- ============================================================
-- 2. Public registration is forced to pending
-- ============================================================

DO $$
DECLARE
  v_result JSON;
  v_status TEXT;
  v_code TEXT;
BEGIN
  PERFORM pg_temp.clear_test_user();
  SET LOCAL ROLE anon;

  SELECT public.register_clinic(
    'عيادة اختبار أمان', 'c1', 'الكرادة', 'عنوان تجريبي',
    '07709990001', 0, 0
  ) INTO v_result;

  RESET ROLE;
  SELECT status, activation_code INTO v_status, v_code
  FROM public.clinics
  WHERE id = (v_result->>'id')::UUID;

  PERFORM pg_temp.record_test(
    'public clinic registration is pending with no activation code',
    v_status = 'pending' AND v_code IS NULL,
    'status=' || COALESCE(v_status, 'NULL')
  );
END $$;

-- ============================================================
-- 3. Booking validation, encryption, privacy, and cancellation
-- ============================================================

DO $$
DECLARE
  v_date DATE;
  v_day INT;
  v_time TEXT;
  v_booking JSON;
  v_booking_id UUID;
  v_result JSON;
  v_success BOOLEAN;
  v_plain TEXT;
  v_cipher BYTEA;
BEGIN
  -- Find the next scheduled day for the first seeded doctor.
  SELECT gs::DATE, s.day, s.start_time
  INTO v_date, v_day, v_time
  FROM generate_series(CURRENT_DATE + 1, CURRENT_DATE + 14, INTERVAL '1 day') gs
  JOIN public.schedules s
    ON s.doctor_id = 'b0000000-0000-0000-0000-000000000001'
   AND s.day = EXTRACT(DOW FROM gs)::INT
  ORDER BY gs
  LIMIT 1;

  IF v_date IS NULL THEN
    RAISE EXCEPTION 'Seeded doctor has no future schedule for booking tests';
  END IF;

  PERFORM pg_temp.clear_test_user();
  SET LOCAL ROLE anon;

  BEGIN
    SELECT public.create_appointment(
      'b0000000-0000-0000-0000-000000000001',
      'a0000000-0000-0000-0000-000000000001',
      'مريض اختبار', '07709990002', 30, 'ملاحظة طبية سرية',
      v_date::TEXT, '29:30', 'clinic', 30000, 'clinic'
    ) INTO v_result;
    v_success := true;
  EXCEPTION WHEN OTHERS THEN
    v_success := false;
  END;
  RESET ROLE;
  PERFORM pg_temp.record_test('booking rejects invalid time', NOT v_success);

  PERFORM pg_temp.clear_test_user();
  SET LOCAL ROLE anon;
  BEGIN
    SELECT public.create_appointment(
      'b0000000-0000-0000-0000-000000000001',
      'a0000000-0000-0000-0000-000000000001',
      'مريض اختبار', '07709990002', 30, 'ملاحظة طبية سرية',
      v_date::TEXT, v_time, 'clinic', 1, 'clinic'
    ) INTO v_result;
    v_success := true;
  EXCEPTION WHEN OTHERS THEN
    v_success := false;
  END;
  RESET ROLE;
  PERFORM pg_temp.record_test('booking rejects client price tampering', NOT v_success);

  PERFORM pg_temp.clear_test_user();
  SET LOCAL ROLE anon;
  SELECT public.create_appointment(
    'b0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000001',
    'مريض اختبار', '07709990002', 30, 'ملاحظة طبية سرية',
    v_date::TEXT, v_time, 'clinic', 30000, 'clinic'
  ) INTO v_booking;
  RESET ROLE;

  v_booking_id := (v_booking->>'id')::UUID;
  SELECT patient_notes, patient_notes_encrypted
  INTO v_plain, v_cipher
  FROM public.appointments WHERE id = v_booking_id;

  PERFORM pg_temp.record_test(
    'medical note is encrypted and plaintext is cleared',
    v_plain = '[محمي]' AND v_cipher IS NOT NULL
  );

  PERFORM pg_temp.clear_test_user();
  SET LOCAL ROLE anon;
  SELECT public.get_patient_booking(v_booking_id, '07709990003') INTO v_result;
  RESET ROLE;
  PERFORM pg_temp.record_test(
    'wrong phone cannot retrieve booking',
    v_result IS NULL
  );

  PERFORM pg_temp.clear_test_user();
  SET LOCAL ROLE anon;
  SELECT public.get_patient_booking(v_booking_id, '07709990002') INTO v_result;
  RESET ROLE;
  PERFORM pg_temp.record_test(
    'booking ID plus phone retrieves and decrypts own note',
    v_result->>'patient_notes' = 'ملاحظة طبية سرية'
  );

  PERFORM pg_temp.clear_test_user();
  SET LOCAL ROLE anon;
  BEGIN
    SELECT public.cancel_patient_booking(v_booking_id, '07709990003') INTO v_result;
    v_success := true;
  EXCEPTION WHEN OTHERS THEN
    v_success := false;
  END;
  RESET ROLE;
  PERFORM pg_temp.record_test('wrong phone cannot cancel booking', NOT v_success);

  PERFORM pg_temp.clear_test_user();
  SET LOCAL ROLE anon;
  SELECT public.cancel_patient_booking(v_booking_id, '07709990002') INTO v_result;
  RESET ROLE;
  PERFORM pg_temp.record_test(
    'booking ID plus phone can cancel own future booking',
    v_result->>'status' = 'cancelled'
  );
END $$;

-- ============================================================
-- 4. Clinic isolation
-- ============================================================

DO $$
DECLARE
  v_visible INT;
  v_wrong_clinic INT;
  v_reminder_id UUID;
  v_result JSON;
  v_success BOOLEAN;
BEGIN
  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    raw_app_meta_data, raw_user_meta_data, is_super_admin
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    'f0000000-0000-0000-0000-000000000001',
    'authenticated', 'authenticated',
    'rls-clinic-test@sahatna.invalid',
    extensions.crypt('temporary-test-only', extensions.gen_salt('bf')),
    NOW(), NOW(), NOW(), '', '', '', '',
    '{"provider":"email","providers":["email"]}', '{}', false
  ) ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.clinic_users (clinic_id, user_id, username, name)
  VALUES (
    'a0000000-0000-0000-0000-000000000001',
    'f0000000-0000-0000-0000-000000000001',
    'rls_clinic_test', 'RLS Clinic Test'
  ) ON CONFLICT (username) DO NOTHING;

  PERFORM pg_temp.set_test_user('f0000000-0000-0000-0000-000000000001');
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*), COUNT(*) FILTER (
    WHERE clinic_id <> 'a0000000-0000-0000-0000-000000000001'
  )
  INTO v_visible, v_wrong_clinic
  FROM public.get_clinic_appointments();

  SELECT r.id INTO v_reminder_id
  FROM public.reminders r
  JOIN public.appointments a ON a.id = r.appointment_id
  WHERE a.clinic_id = 'a0000000-0000-0000-0000-000000000001'
  ORDER BY r.created_at DESC
  LIMIT 1;

  SELECT public.mark_reminder_sent(v_reminder_id) INTO v_result;

  BEGIN
    PERFORM public.log_audit_entry(
      'forged.action', 'appointments', NULL, '{}'::JSONB, 'clinic'
    );
    v_success := true;
  EXCEPTION WHEN OTHERS THEN
    v_success := false;
  END;

  RESET ROLE;
  PERFORM pg_temp.record_test(
    'clinic RPC never returns another clinic appointments',
    v_wrong_clinic = 0,
    'visible=' || v_visible || ', wrong_clinic=' || v_wrong_clinic
  );
  PERFORM pg_temp.record_test(
    'clinic can mark only an owned reminder through RPC',
    v_result->>'id' = v_reminder_id::TEXT AND (v_result->>'sent')::BOOLEAN
  );
  PERFORM pg_temp.record_test(
    'clinic cannot forge audit log entries',
    NOT v_success
  );
END $$;

-- ============================================================
-- 5. Summary and hard failure on any failed assertion
-- ============================================================

DO $$
DECLARE
  v_total INT;
  v_passed INT;
  v_failed INT;
  v_failed_names TEXT;
BEGIN
  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE passed),
    COUNT(*) FILTER (WHERE NOT passed),
    string_agg(test_name, ' | ') FILTER (WHERE NOT passed)
  INTO v_total, v_passed, v_failed, v_failed_names
  FROM pg_temp.test_results;

  RAISE NOTICE '============================================================';
  RAISE NOTICE 'RLS tests: total=%, passed=%, failed=%', v_total, v_passed, v_failed;
  RAISE NOTICE '============================================================';

  IF v_failed > 0 THEN
    RAISE EXCEPTION 'RLS TESTS FAILED: %', v_failed_names;
  END IF;
END $$;

ROLLBACK;
