-- ============================================================
-- صحتنا - Fix: Secure appointment creation for anon users
--
-- PROBLEM: The original create_appointment() was SECURITY DEFINER
--          and bypassed RLS validation entirely. It allowed:
--          - Past dates
--          - Non-existent doctors
--          - Non-approved clinics
--          - Doctors not belonging to the specified clinic
--          - Double bookings
--
-- SOLUTION: Add full validation INSIDE the function so even though
--          it runs with owner privileges, it enforces the same
--          rules as the RLS "Validated create appointments" policy.
--          Also removed the broken is_recent_own_appointment() helper.
--
-- RUN: Execute this in Supabase SQL Editor AFTER:
--      1. supabase-schema.sql
--      2. supabase-security-hardening.sql
-- ============================================================

-- Drop old versions
DROP FUNCTION IF EXISTS create_appointment(
  UUID, UUID, TEXT, TEXT, INT, TEXT, TEXT, TEXT, TEXT, INT, TEXT
);

DROP FUNCTION IF EXISTS is_recent_own_appointment();

-- ============================================================
-- Secure create_appointment function
-- Validates all inputs before inserting, then creates reminder.
-- Returns the new appointment as JSON.
-- ============================================================
CREATE OR REPLACE FUNCTION create_appointment(
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
AS $$
DECLARE
  v_apt RECORD;
  v_doctor_name TEXT;
  v_clinic_name TEXT;
  v_clinic_status TEXT;
  v_doctor_clinic_id UUID;
  v_existing_count INT;
BEGIN
  -- ============================================================
  -- VALIDATION (mirrors RLS "Validated create appointments" policy)
  -- ============================================================

  -- 1. Patient name must not be empty
  IF p_patient_name IS NULL OR length(trim(p_patient_name)) < 2 THEN
    RAISE EXCEPTION 'INVALID: patient name must be at least 2 characters';
  END IF;

  -- 2. Patient phone must be valid Iraqi format (07XXXXXXXXX)
  IF p_patient_phone IS NULL OR p_patient_phone !~ '^07[0-9]{9}$' THEN
    RAISE EXCEPTION 'INVALID: patient phone must be Iraqi format 07XXXXXXXXX';
  END IF;

  -- 3. Date must not be in the past
  IF p_date IS NULL OR p_date < to_char(NOW(), 'YYYY-MM-DD') THEN
    RAISE EXCEPTION 'INVALID: appointment date cannot be in the past';
  END IF;

  -- 4. Time must not be empty
  IF p_time IS NULL OR p_time !~ '^[0-2][0-9]:[0-5][0-9]$' THEN
    RAISE EXCEPTION 'INVALID: appointment time must be HH:MM format';
  END IF;

  -- 5. Service must be valid
  IF p_service IS NULL OR p_service NOT IN ('clinic', 'video', 'home') THEN
    RAISE EXCEPTION 'INVALID: service must be clinic, video, or home';
  END IF;

  -- 6. Price must be positive
  IF p_price IS NULL OR p_price <= 0 THEN
    RAISE EXCEPTION 'INVALID: price must be a positive number';
  END IF;

  -- 7. Doctor must exist
  SELECT clinic_id INTO v_doctor_clinic_id FROM doctors WHERE id = p_doctor_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID: doctor does not exist';
  END IF;

  -- 8. Clinic must be approved
  SELECT status INTO v_clinic_status FROM clinics WHERE id = p_clinic_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID: clinic does not exist';
  END IF;
  IF v_clinic_status != 'approved' THEN
    RAISE EXCEPTION 'INVALID: clinic is not approved (status: %)', v_clinic_status;
  END IF;

  -- 9. Doctor must belong to the specified clinic
  IF v_doctor_clinic_id != p_clinic_id THEN
    RAISE EXCEPTION 'INVALID: doctor does not belong to this clinic';
  END IF;

  -- 10. Prevent double booking (same doctor, same date, same time, not cancelled)
  SELECT COUNT(*) INTO v_existing_count
  FROM appointments
  WHERE doctor_id = p_doctor_id
    AND date = p_date
    AND time = p_time
    AND status != 'cancelled';
  IF v_existing_count > 0 THEN
    RAISE EXCEPTION 'INVALID: this slot is already booked (double booking prevented)';
  END IF;

  -- ============================================================
  -- INSERT (validation passed)
  -- ============================================================
  INSERT INTO appointments (
    doctor_id, clinic_id, patient_name, patient_phone, patient_age,
    patient_notes, date, time, service, price, status, payment_method
  ) VALUES (
    p_doctor_id, p_clinic_id, p_patient_name, p_patient_phone, p_patient_age,
    p_patient_notes, p_date, p_time, p_service, p_price, 'confirmed', p_payment_method
  )
  RETURNING * INTO v_apt;

  -- Get doctor and clinic names for the reminder
  SELECT name INTO v_doctor_name FROM doctors WHERE id = p_doctor_id;
  SELECT name INTO v_clinic_name FROM clinics WHERE id = p_clinic_id;

  -- Create reminder (best-effort, won't fail the booking if it errors)
  BEGIN
    IF v_doctor_name IS NOT NULL AND v_clinic_name IS NOT NULL THEN
      INSERT INTO reminders (
        appointment_id, patient_name, patient_phone, doctor_name,
        clinic_name, date, time, sent
      ) VALUES (
        v_apt.id, p_patient_name, p_patient_phone, v_doctor_name,
        v_clinic_name, p_date, p_time, false
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Reminder creation is non-critical; log and continue
    RAISE NOTICE 'WARNING: reminder creation failed for appointment %', v_apt.id;
  END;

  -- Log audit entry (best-effort)
  BEGIN
    INSERT INTO audit_log (actor_type, action, target_table, target_id, details)
    VALUES (
      'anon',
      'appointment.create',
      'appointments',
      v_apt.id,
      json_build_object(
        'doctor_id', p_doctor_id,
        'clinic_id', p_clinic_id,
        'date', p_date,
        'time', p_time,
        'service', p_service
      )
    );
  EXCEPTION WHEN OTHERS THEN
    -- Audit logging is non-critical
    NULL;
  END;

  -- Return the appointment as JSON
  RETURN json_build_object(
    'id', v_apt.id,
    'doctor_id', v_apt.doctor_id,
    'clinic_id', v_apt.clinic_id,
    'patient_name', v_apt.patient_name,
    'patient_phone', v_apt.patient_phone,
    'patient_age', v_apt.patient_age,
    'patient_notes', v_apt.patient_notes,
    'date', v_apt.date,
    'time', v_apt.time,
    'service', v_apt.service,
    'price', v_apt.price,
    'status', v_apt.status,
    'payment_method', v_apt.payment_method,
    'created_at', v_apt.created_at
  );
END;
$$;

-- Grant execute to anon (unauthenticated patients) and authenticated users
GRANT EXECUTE ON FUNCTION create_appointment(
  UUID, UUID, TEXT, TEXT, INT, TEXT, TEXT, TEXT, TEXT, INT, TEXT
) TO anon, authenticated;

-- ============================================================
-- Summary of changes
-- ============================================================
-- ✅ create_appointment() now validates ALL inputs before insert:
--    - patient name ≥ 2 chars
--    - patient phone = 07XXXXXXXXX (Iraqi format)
--    - date not in past
--    - time = HH:MM format
--    - service in (clinic, video, home)
--    - price > 0
--    - doctor exists
--    - clinic exists and is approved
--    - doctor belongs to specified clinic
--    - no double booking (same doctor/date/time, not cancelled)
-- ✅ Audit log entry created for each booking (actor_type = 'anon')
-- ✅ Reminder creation is best-effort (won't fail booking)
-- ✅ Removed broken is_recent_own_appointment() function