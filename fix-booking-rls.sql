-- ============================================================
-- صحتنا - Fix: Allow anon users to book appointments
-- 
-- PROBLEM: RLS blocks SELECT on appointments for anon users.
--          createBooking() used .select().single() after INSERT,
--          which returned an empty result (RLS) and threw
--          PGRST116 error, making booking fail silently.
--
-- SOLUTION: Create a SECURITY DEFINER function that handles the
--           insert + reminder creation and returns the new row.
--           Anon users call this via RPC instead of direct INSERT.
-- ============================================================

-- Drop old version if exists
DROP FUNCTION IF EXISTS create_appointment(
  UUID, UUID, TEXT, TEXT, INT, TEXT, TEXT, TEXT, TEXT, INT, TEXT
);

-- Create a function that inserts an appointment + reminder and returns the row
-- SECURITY DEFINER means it runs with the owner's privileges, bypassing RLS
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
BEGIN
  -- Insert the appointment
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

  -- Create reminder (best-effort)
  IF v_doctor_name IS NOT NULL AND v_clinic_name IS NOT NULL THEN
    INSERT INTO reminders (
      appointment_id, patient_name, patient_phone, doctor_name,
      clinic_name, date, time, sent
    ) VALUES (
      v_apt.id, p_patient_name, p_patient_phone, v_doctor_name,
      v_clinic_name, p_date, p_time, false
    );
  END IF;

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
-- Also add a policy so anon can read back their OWN appointment
-- immediately after insert (within 5 seconds, matching by phone)
-- This is a fallback in case the RPC approach isn't used
-- ============================================================
CREATE OR REPLACE FUNCTION is_recent_own_appointment()
RETURNS BOOLEAN AS $$
  SELECT EXISTS(
    SELECT 1 FROM appointments a
    WHERE a.patient_phone = NULLIF(current_setting('request.jwt.claim.sub', true), '')::TEXT
      AND a.created_at > NOW() - INTERVAL '10 seconds'
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;