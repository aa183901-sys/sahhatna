-- ============================================================
-- صحّتنا - Single-statement production RLS and RPC smoke test
-- Run after supabase-schema.sql and supabase-production-hardening.sql.
-- This is one atomic DO statement so Supabase SQL Editor runs it whole.
-- Test data is deleted on success and rolled back automatically on failure.
-- ============================================================

DO $test$
DECLARE
  v_names TEXT[] := ARRAY[]::TEXT[];
  v_checks BOOLEAN[] := ARRAY[]::BOOLEAN[];
  v_total INT;
  v_passed INT := 0;
  v_failed INT := 0;
  v_failed_names TEXT := '';
  v_i INT;
  v_count INT;
  v_exists BOOLEAN;
  v_date DATE;
  v_time TEXT;
  v_result JSON;
  v_booking JSON;
  v_booking_id UUID;
  v_clinic JSON;
  v_clinic_id UUID;
  v_plain TEXT;
  v_cipher BYTEA;
  v_success BOOLEAN;
BEGIN
  -- Static privilege, RLS, and schema checks.
  v_names := array_append(v_names, 'anon cannot select raw appointments');
  v_checks := array_append(v_checks,
    NOT has_table_privilege('anon', 'public.appointments', 'SELECT'));

  v_names := array_append(v_names, 'anon cannot insert raw appointments');
  v_checks := array_append(v_checks,
    NOT has_table_privilege('anon', 'public.appointments', 'INSERT'));

  v_names := array_append(v_names, 'anon can select public appointment slots');
  v_checks := array_append(v_checks,
    has_table_privilege('anon', 'public.public_appointment_slots', 'SELECT'));

  v_names := array_append(v_names, 'authenticated cannot mutate raw doctors');
  v_checks := array_append(v_checks,
    NOT has_table_privilege('authenticated', 'public.doctors', 'INSERT')
    AND NOT has_table_privilege('authenticated', 'public.doctors', 'UPDATE')
    AND NOT has_table_privilege('authenticated', 'public.doctors', 'DELETE'));

  v_names := array_append(v_names, 'authenticated cannot mutate schedules or reminders');
  v_checks := array_append(v_checks,
    NOT has_table_privilege('authenticated', 'public.schedules', 'INSERT')
    AND NOT has_table_privilege('authenticated', 'public.schedules', 'UPDATE')
    AND NOT has_table_privilege('authenticated', 'public.reminders', 'INSERT'));

  SELECT COUNT(*) = 0 INTO v_exists
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'public_clinics'
    AND column_name = 'activation_code';
  v_names := array_append(v_names, 'public clinics hides activation codes');
  v_checks := array_append(v_checks, v_exists);

  SELECT COUNT(*) = 0 INTO v_exists
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'get_patient_bookings';
  v_names := array_append(v_names, 'unsafe phone-only booking RPC is absent');
  v_checks := array_append(v_checks, v_exists);

  SELECT COUNT(*) = 0 INTO v_exists
  FROM information_schema.views
  WHERE table_schema = 'public' AND table_name = 'clinic_appointment_details';
  v_names := array_append(v_names, 'unsafe clinic appointment view is absent');
  v_checks := array_append(v_checks, v_exists);

  v_names := array_append(v_names, 'clients cannot execute encryption key function');
  v_checks := array_append(v_checks,
    NOT has_function_privilege('anon', 'private.get_encryption_key()', 'EXECUTE')
    AND NOT has_function_privilege('authenticated', 'private.get_encryption_key()', 'EXECUTE'));

  SELECT COUNT(*) = 7 INTO v_exists
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname IN (
      'clinics', 'doctors', 'appointments', 'reminders',
      'reviews', 'clinic_users', 'admin_users'
    )
    AND c.relrowsecurity;
  v_names := array_append(v_names, 'RLS is enabled on core tables');
  v_checks := array_append(v_checks, v_exists);

  -- Public clinic registration must always create a pending clinic without a code.
  SET LOCAL ROLE anon;
  SELECT public.register_clinic(
    'عيادة اختبار أمان', 'c1', 'الكرادة', 'عنوان تجريبي',
    '07709990001', 0, 0
  ) INTO v_clinic;
  RESET ROLE;
  v_clinic_id := (v_clinic->>'id')::UUID;

  SELECT COUNT(*) = 1 INTO v_exists
  FROM public.clinics
  WHERE id = v_clinic_id AND status = 'pending' AND activation_code IS NULL;
  v_names := array_append(v_names, 'public clinic registration is forced pending');
  v_checks := array_append(v_checks, v_exists);

  -- Find a future seeded slot for booking tests.
  SELECT gs::DATE, s.start_time
  INTO v_date, v_time
  FROM generate_series(CURRENT_DATE + 1, CURRENT_DATE + 14, INTERVAL '1 day') gs
  JOIN public.schedules s
    ON s.doctor_id = 'b0000000-0000-0000-0000-000000000001'
   AND s.day = EXTRACT(DOW FROM gs)::INT
  ORDER BY gs
  LIMIT 1;
  IF v_date IS NULL THEN
    RAISE EXCEPTION 'Seeded doctor has no future schedule for booking tests';
  END IF;

  -- Invalid time must fail.
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
  v_names := array_append(v_names, 'booking rejects invalid time');
  v_checks := array_append(v_checks, NOT v_success);

  -- Client price tampering must fail.
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
  v_names := array_append(v_names, 'booking rejects client price tampering');
  v_checks := array_append(v_checks, NOT v_success);

  -- Create one valid booking.
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
  v_names := array_append(v_names, 'medical note is encrypted and plaintext cleared');
  v_checks := array_append(v_checks, v_plain = '[محمي]' AND v_cipher IS NOT NULL);

  SET LOCAL ROLE anon;
  SELECT public.get_patient_booking(v_booking_id, '07709990003') INTO v_result;
  RESET ROLE;
  v_names := array_append(v_names, 'wrong phone cannot retrieve booking');
  v_checks := array_append(v_checks, v_result IS NULL);

  SET LOCAL ROLE anon;
  SELECT public.get_patient_booking(v_booking_id, '07709990002') INTO v_result;
  RESET ROLE;
  v_names := array_append(v_names, 'booking ID plus phone retrieves own note');
  v_checks := array_append(v_checks,
    v_result->>'patient_notes' = 'ملاحظة طبية سرية');

  SET LOCAL ROLE anon;
  BEGIN
    SELECT public.cancel_patient_booking(v_booking_id, '07709990003') INTO v_result;
    v_success := true;
  EXCEPTION WHEN OTHERS THEN
    v_success := false;
  END;
  RESET ROLE;
  v_names := array_append(v_names, 'wrong phone cannot cancel booking');
  v_checks := array_append(v_checks, NOT v_success);

  SET LOCAL ROLE anon;
  SELECT public.cancel_patient_booking(v_booking_id, '07709990002') INTO v_result;
  RESET ROLE;
  v_names := array_append(v_names, 'booking ID plus phone can cancel own booking');
  v_checks := array_append(v_checks, v_result->>'status' = 'cancelled');

  -- Summarize all checks.
  v_total := COALESCE(array_length(v_names, 1), 0);
  FOR v_i IN 1..v_total LOOP
    IF COALESCE(v_checks[v_i], false) THEN
      v_passed := v_passed + 1;
      RAISE NOTICE '✅ PASS: %', v_names[v_i];
    ELSE
      v_failed := v_failed + 1;
      v_failed_names := concat_ws(' | ', NULLIF(v_failed_names, ''), v_names[v_i]);
      RAISE WARNING '❌ FAIL: %', v_names[v_i];
    END IF;
  END LOOP;

  -- Remove the exact test records before reporting success.
  DELETE FROM public.appointments WHERE id = v_booking_id;
  DELETE FROM public.clinics WHERE id = v_clinic_id;
  DELETE FROM public.rate_limit
  WHERE (endpoint = 'clinic_registration'
      AND identifier = encode(extensions.digest('07709990001', 'sha256'), 'hex'))
     OR (endpoint IN ('booking', 'patient_lookup', 'patient_cancel')
      AND identifier IN (
        encode(extensions.digest('07709990002', 'sha256'), 'hex'),
        encode(extensions.digest(v_booking_id::TEXT || ':07709990002', 'sha256'), 'hex'),
        encode(extensions.digest(v_booking_id::TEXT || ':07709990003', 'sha256'), 'hex')
      ));

  RAISE NOTICE '============================================================';
  RAISE NOTICE 'RLS tests: total=%, passed=%, failed=%', v_total, v_passed, v_failed;
  RAISE NOTICE '============================================================';

  IF v_failed > 0 THEN
    RAISE EXCEPTION 'RLS TESTS FAILED: %', v_failed_names;
  END IF;
END
$test$;
