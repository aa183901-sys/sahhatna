DO $$ BEGIN
  RAISE EXCEPTION 'ملف legacy خطير ومعطّل لأنه يعيد سياسات RLS الضعيفة.';
END $$;

-- ============================================================
-- صحتنا - Migration: إضافة الدوال المفقودة
-- شغّل هذا الملف في Supabase SQL Editor لإضافة الدوال المطلوبة
-- ============================================================

-- 1. جدول سجل التدقيق
CREATE TABLE IF NOT EXISTS audit_log (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  action TEXT NOT NULL,
  target_table TEXT,
  target_id TEXT,
  details JSONB DEFAULT '{}',
  actor_type TEXT DEFAULT 'user',
  actor_id UUID,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. تحديث CHECK constraint لدعم no_show
ALTER TABLE appointments DROP CONSTRAINT IF EXISTS appointments_status_check;
ALTER TABLE appointments ADD CONSTRAINT appointments_status_check 
  CHECK (status IN ('confirmed','completed','cancelled','no_show'));

-- 3. تحديث index لاستبعاد no_show
DROP INDEX IF EXISTS idx_no_double_booking;
CREATE UNIQUE INDEX idx_no_double_booking
  ON appointments(doctor_id, date, time)
  WHERE status NOT IN ('cancelled', 'no_show');

-- 4. تحديث public_appointment_slots view
CREATE OR REPLACE VIEW public_appointment_slots AS
SELECT doctor_id, date, time, status
FROM appointments
WHERE status NOT IN ('cancelled', 'no_show');

GRANT SELECT ON public_appointment_slots TO anon;

-- 5. دالة create_appointment
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
  v_id UUID;
  v_doctor_name TEXT;
  v_clinic_name TEXT;
  v_result JSON;
BEGIN
  SELECT name INTO v_doctor_name FROM doctors WHERE id = p_doctor_id;
  IF v_doctor_name IS NULL THEN
    RAISE EXCEPTION 'الطبيب غير موجود';
  END IF;

  SELECT name INTO v_clinic_name FROM clinics WHERE id = p_clinic_id;
  IF v_clinic_name IS NULL THEN
    RAISE EXCEPTION 'العيادة غير موجودة';
  END IF;

  IF EXISTS (
    SELECT 1 FROM appointments
    WHERE doctor_id = p_doctor_id
      AND date = p_date
      AND time = p_time
      AND status NOT IN ('cancelled', 'no_show')
  ) THEN
    RAISE EXCEPTION 'هذا الموعد محجوز بالفعل';
  END IF;

  INSERT INTO appointments (
    doctor_id, clinic_id, patient_name, patient_phone,
    patient_age, patient_notes, date, time, service, price,
    status, payment_method
  ) VALUES (
    p_doctor_id, p_clinic_id, p_patient_name, p_patient_phone,
    p_patient_age, p_patient_notes, p_date, p_time, p_service, p_price,
    'confirmed', p_payment_method
  ) RETURNING id INTO v_id;

  INSERT INTO reminders (appointment_id, patient_name, patient_phone, doctor_name, clinic_name, date, time)
  VALUES (v_id, p_patient_name, p_patient_phone, v_doctor_name, v_clinic_name, p_date, p_time);

  INSERT INTO audit_log (action, target_table, target_id, details, actor_type)
  VALUES ('appointment.create', 'appointments', v_id::TEXT,
    jsonb_build_object('doctor_id', p_doctor_id, 'clinic_id', p_clinic_id, 'date', p_date, 'time', p_time),
    'anon');

  SELECT json_build_object(
    'id', a.id, 'doctor_id', a.doctor_id, 'clinic_id', a.clinic_id,
    'patient_name', a.patient_name, 'patient_phone', a.patient_phone,
    'patient_age', a.patient_age, 'patient_notes', a.patient_notes,
    'date', a.date, 'time', a.time, 'service', a.service, 'price', a.price,
    'status', a.status, 'payment_method', a.payment_method, 'created_at', a.created_at
  ) INTO v_result
  FROM appointments a WHERE a.id = v_id;

  RETURN v_result;
END;
$$;

-- 6. View: clinic_appointment_details
CREATE OR REPLACE VIEW clinic_appointment_details AS
SELECT * FROM appointments;

GRANT SELECT ON clinic_appointment_details TO authenticated;

-- 7. دالة log_audit_entry
CREATE OR REPLACE FUNCTION log_audit_entry(
  p_action TEXT,
  p_target_table TEXT,
  p_target_id TEXT,
  p_details JSONB DEFAULT '{}',
  p_actor_type TEXT DEFAULT 'user'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO audit_log (action, target_table, target_id, details, actor_type, actor_id)
  VALUES (p_action, p_target_table, p_target_id, p_details, p_actor_type, auth.uid());
END;
$$;

-- 8. دالة get_patient_bookings
CREATE OR REPLACE FUNCTION get_patient_bookings(p_phone TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSON;
BEGIN
  SELECT COALESCE(json_agg(json_build_object(
    'id', a.id, 'doctor_id', a.doctor_id, 'clinic_id', a.clinic_id,
    'patient_name', a.patient_name, 'patient_phone', a.patient_phone,
    'patient_age', a.patient_age, 'patient_notes', a.patient_notes,
    'date', a.date, 'time', a.time, 'service', a.service, 'price', a.price,
    'status', a.status, 'payment_method', a.payment_method, 'created_at', a.created_at
  ) ORDER BY a.date DESC, a.time DESC), '[]'::json) INTO v_result
  FROM appointments a
  WHERE a.patient_phone = p_phone;

  RETURN v_result;
END;
$$;

-- 9. صلاحيات التنفيذ
GRANT EXECUTE ON FUNCTION create_appointment TO anon, authenticated;
GRANT EXECUTE ON FUNCTION log_audit_entry TO authenticated;
GRANT EXECUTE ON FUNCTION get_patient_bookings TO anon, authenticated;

-- 10. RLS على audit_log
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin read audit_log" ON audit_log FOR SELECT USING (is_admin());
CREATE POLICY "Admin manage audit_log" ON audit_log FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- 11. تأكد من وجود GRANT لـ anon و authenticated
GRANT ALL ON appointments TO anon, authenticated;
GRANT SELECT ON appointments TO anon, authenticated;
GRANT INSERT ON appointments TO anon, authenticated;
GRANT UPDATE ON appointments TO authenticated;
GRANT SELECT ON doctors TO anon, authenticated;
GRANT SELECT ON clinics TO anon, authenticated;
GRANT SELECT ON specialties TO anon, authenticated;
GRANT SELECT ON cities TO anon, authenticated;
GRANT SELECT ON schedules TO anon, authenticated;
GRANT SELECT ON reviews TO anon, authenticated;
GRANT ALL ON reminders TO anon, authenticated;
GRANT SELECT ON reminders TO authenticated;
GRANT INSERT ON reminders TO anon, authenticated;

-- 12. تأكد من وجود سياسات RLS للـ INSERT
DROP POLICY IF EXISTS "Public create appointments" ON appointments;
CREATE POLICY "Public create appointments" ON appointments FOR INSERT WITH CHECK (true);

-- 13. تأكد من وجود سياسات RLS للـ INSERT على reminders
DROP POLICY IF EXISTS "Create reminders" ON reminders;
CREATE POLICY "Create reminders" ON reminders FOR INSERT WITH CHECK (true);
