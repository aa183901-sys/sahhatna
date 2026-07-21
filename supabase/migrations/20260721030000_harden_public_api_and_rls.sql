-- Harden public API views, RPC privileges, and common RLS hot paths.
-- Safe to run repeatedly.

BEGIN;

-- Store only a masked public display name so security-invoker views never
-- need permission to read the raw patient name.
ALTER TABLE public.reviews
  ADD COLUMN IF NOT EXISTS patient_name_public TEXT
  GENERATED ALWAYS AS (
    CASE
      WHEN patient_name IS NULL OR patient_name = '' THEN 'مستخدم'
      ELSE left(patient_name, 1) || '***'
    END
  ) STORED;

-- Anonymous callers may read only safe columns, and RLS still limits rows.
REVOKE SELECT ON public.clinics, public.reviews, public.appointments FROM anon;

GRANT SELECT (id, name, city_id, area, address, phone, lat, lng, status, created_at)
  ON public.clinics TO anon;
GRANT SELECT (id, doctor_id, patient_name_public, rating, comment, verified, created_at)
  ON public.reviews TO anon;
GRANT SELECT (doctor_id, date, time, status)
  ON public.appointments TO anon;

DROP POLICY IF EXISTS "Public read approved clinics" ON public.clinics;
CREATE POLICY "Public read approved clinics"
  ON public.clinics FOR SELECT TO anon
  USING (status = 'approved');

DROP POLICY IF EXISTS "Public read verified reviews" ON public.reviews;
CREATE POLICY "Public read verified reviews"
  ON public.reviews FOR SELECT TO anon
  USING (verified = true);

DROP POLICY IF EXISTS "Public read appointment slots" ON public.appointments;
CREATE POLICY "Public read appointment slots"
  ON public.appointments FOR SELECT TO anon
  USING (status NOT IN ('cancelled', 'no_show'));

CREATE OR REPLACE VIEW public.public_clinics
WITH (security_invoker = true, security_barrier = true) AS
SELECT id, name, city_id, area, address, phone, lat, lng, status, created_at
FROM public.clinics
WHERE status = 'approved';

CREATE OR REPLACE VIEW public.public_reviews
WITH (security_invoker = true, security_barrier = true) AS
SELECT id, doctor_id, patient_name_public AS patient_name,
       rating, comment, verified, created_at
FROM public.reviews
WHERE verified = true;

CREATE OR REPLACE VIEW public.public_appointment_slots
WITH (security_invoker = true, security_barrier = true) AS
SELECT doctor_id, date, time
FROM public.appointments
WHERE status NOT IN ('cancelled', 'no_show');

GRANT SELECT ON public.public_clinics, public.public_reviews,
  public.public_appointment_slots TO anon, authenticated;

-- Functions are executable by PUBLIC by default in Postgres. Start closed,
-- then grant only the RPC surface used by the application.
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_appointment(uuid, uuid, text, text, integer, text, text, text, text, integer, text)
  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_patient_booking(uuid, text)
  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_patient_booking(uuid, text)
  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_verified_review(uuid, text, integer, text)
  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_clinic(text, text, text, text, text, numeric, numeric)
  TO anon, authenticated;

GRANT EXECUTE ON FUNCTION public.activate_clinic_account(text, text, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_clinic_registration(uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_clinic_registration(uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_doctor(text, text, text, uuid, text, text, text, integer, integer, text, text[], text[])
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_doctor(uuid, jsonb)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_or_deactivate_doctor(uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.replace_doctor_schedule(uuid, jsonb, integer)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_clinic_appointments()
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_reminder_sent(uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_appointment_status(uuid, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_current_clinic_id()
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin()
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_clinic_user()
  TO authenticated;

-- Avoid evaluating auth.uid() once per row on common identity policies.
DROP POLICY IF EXISTS "User read own admin_user" ON public.admin_users;
CREATE POLICY "User read own admin_user"
  ON public.admin_users FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "User read own clinic_user" ON public.clinic_users;
CREATE POLICY "User read own clinic_user"
  ON public.clinic_users FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()) OR public.is_admin());

DROP POLICY IF EXISTS "User read own staff_role" ON public.staff_roles;
CREATE POLICY "User read own staff_role"
  ON public.staff_roles FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR clinic_id = public.get_current_clinic_id()
    OR public.is_admin()
  );

-- Cover foreign keys used by joins and cascades.
CREATE INDEX IF NOT EXISTS idx_clinic_users_clinic_id
  ON public.clinic_users(clinic_id);
CREATE INDEX IF NOT EXISTS idx_clinics_city_id
  ON public.clinics(city_id);
CREATE INDEX IF NOT EXISTS idx_reminders_appointment_id
  ON public.reminders(appointment_id);
CREATE INDEX IF NOT EXISTS idx_staff_roles_user_id
  ON public.staff_roles(user_id);

COMMIT;
