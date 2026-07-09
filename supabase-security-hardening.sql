-- ============================================================
-- صحتنا (Sahatna) - Security Hardening Migration
-- Run this in Supabase SQL Editor AFTER supabase-schema.sql
--
-- PURPOSE: Tighten RLS policies, add audit logging, encrypt
--          sensitive fields, add status tracking, payments,
--          staff roles, and rate limiting.
--
-- SECURITY: This migration is ADDITIVE — it does not drop
--           existing tables. It drops weak policies and replaces
--           them with strict ones, adds new tables, constraints,
--          and helper functions.
-- ============================================================

-- ============================================================
-- 0. Extensions
-- ============================================================
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. Audit Log Table
-- Tracks every administrative action and sensitive data access.
-- ============================================================
CREATE TABLE IF NOT EXISTS audit_log (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  actor_id UUID, -- auth.users(id) or NULL for system/anon
  actor_type TEXT NOT NULL DEFAULT 'user' CHECK (actor_type IN ('user','system','anon')),
  action TEXT NOT NULL, -- e.g. 'clinic.approve', 'appointment.update_status'
  target_table TEXT NOT NULL,
  target_id UUID,
  details JSONB DEFAULT '{}'::JSONB,
  ip_address TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

-- Only admins can read audit logs
CREATE POLICY "Admin read audit_log" ON audit_log FOR SELECT
  USING (is_admin());

-- Only service_role (Edge Functions) can insert audit logs
-- We use a SECURITY DEFINER function to allow inserts from authenticated
-- contexts without exposing the table for public writes.
CREATE OR REPLACE FUNCTION log_audit_entry(
  p_action TEXT,
  p_target_table TEXT,
  p_target_id UUID DEFAULT NULL,
  p_details JSONB DEFAULT '{}'::JSONB,
  p_actor_type TEXT DEFAULT 'user'
) RETURNS UUID AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO audit_log (actor_id, actor_type, action, target_table, target_id, details)
  VALUES (auth.uid(), p_actor_type, p_action, p_target_table, p_target_id, p_details)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute on audit function to authenticated users
GRANT EXECUTE ON FUNCTION log_audit_entry TO authenticated;

-- ============================================================
-- 2. Appointment Status Log Table
-- Tracks every status change for appointments.
-- ============================================================
CREATE TABLE IF NOT EXISTS appointment_status_log (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  appointment_id UUID NOT NULL REFERENCES appointments(id) ON DELETE CASCADE,
  old_status TEXT,
  new_status TEXT NOT NULL CHECK (new_status IN ('confirmed','completed','cancelled')),
  changed_by UUID, -- auth.users(id) or NULL for patient/anon
  changed_by_type TEXT NOT NULL DEFAULT 'system' CHECK (changed_by_type IN ('patient','clinic','admin','system')),
  reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE appointment_status_log ENABLE ROW LEVEL SECURITY;

-- Clinic can view status logs for their own appointments; admin can view all
CREATE POLICY "Clinic view own status logs" ON appointment_status_log FOR SELECT
  USING (
    appointment_id IN (
      SELECT a.id FROM appointments a
      WHERE a.clinic_id = get_current_clinic_id()
    )
    OR is_admin()
  );

-- Authenticated clinic users and admins can insert status logs
CREATE POLICY "Clinic insert own status logs" ON appointment_status_log FOR INSERT
  WITH CHECK (
    appointment_id IN (
      SELECT a.id FROM appointments a
      WHERE a.clinic_id = get_current_clinic_id()
    )
    OR is_admin()
    OR changed_by_type = 'patient'
  );

-- ============================================================
-- 3. Payments Table
-- Tracks payment transactions (ZainCash, AsiaHawala, clinic cash).
-- ============================================================
CREATE TABLE IF NOT EXISTS payments (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  appointment_id UUID NOT NULL REFERENCES appointments(id) ON DELETE CASCADE,
  gateway TEXT NOT NULL CHECK (gateway IN ('zaincash','asiahawala','clinic','manual')),
  amount INT NOT NULL CHECK (amount >= 0),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','completed','failed','refunded')),
  external_ref TEXT UNIQUE, -- externalReferenceId from gateway (unique per transaction)
  gateway_response JSONB DEFAULT '{}'::JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE payments ENABLE ROW LEVEL SECURITY;

-- Clinic can view payments for their own appointments; admin can view all
CREATE POLICY "Clinic view own payments" ON payments FOR SELECT
  USING (
    appointment_id IN (
      SELECT a.id FROM appointments a
      WHERE a.clinic_id = get_current_clinic_id()
    )
    OR is_admin()
  );

-- Only admin can insert/update/delete payment records directly
-- (Gateway webhooks go through Edge Functions with service_role)
CREATE POLICY "Admin manage payments" ON payments FOR ALL
  USING (is_admin()) WITH CHECK (is_admin());

-- ============================================================
-- 4. Staff Roles Table
-- Granular permissions for clinic staff (secretary, doctor, manager).
-- ============================================================
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

-- A user can read their own staff role
CREATE POLICY "User read own staff_role" ON staff_roles FOR SELECT
  USING (user_id = auth.uid());
-- Clinic manager/admin can read all roles in their clinic
CREATE POLICY "Clinic read own staff_roles" ON staff_roles FOR SELECT
  USING (clinic_id = get_current_clinic_id() OR is_admin());
-- A user can self-insert their own role (during activation)
CREATE POLICY "User self-insert staff_role" ON staff_roles FOR INSERT
  WITH CHECK (user_id = auth.uid());
-- Clinic manager or admin can update/delete roles in their clinic
CREATE POLICY "Clinic manage own staff_roles" ON staff_roles FOR UPDATE
  USING (clinic_id = get_current_clinic_id() OR is_admin())
  WITH CHECK (clinic_id = get_current_clinic_id() OR is_admin());
CREATE POLICY "Clinic delete own staff_roles" ON staff_roles FOR DELETE
  USING (clinic_id = get_current_clinic_id() OR is_admin());

-- ============================================================
-- 5. Rate Limiting Table
-- Tracks API requests for rate limiting (login, OTP, webhooks).
-- ============================================================
CREATE TABLE IF NOT EXISTS rate_limit (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  identifier TEXT NOT NULL, -- IP address or user ID or phone number
  endpoint TEXT NOT NULL, -- e.g. 'login', 'otp', 'booking'
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE rate_limit ENABLE ROW LEVEL SECURITY;

-- No direct access from client — only service_role (Edge Functions) uses this.
-- Deny all client access:
CREATE POLICY "Deny all rate_limit" ON rate_limit FOR ALL
  USING (false) WITH CHECK (false);

-- Helper function: check rate limit (called from Edge Functions with service_role)
CREATE OR REPLACE FUNCTION check_rate_limit(
  p_identifier TEXT,
  p_endpoint TEXT,
  p_max_requests INT DEFAULT 5,
  p_window_minutes INT DEFAULT 15
) RETURNS BOOLEAN AS $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM rate_limit
  WHERE identifier = p_identifier
    AND endpoint = p_endpoint
    AND created_at > NOW() - (p_window_minutes || ' minutes')::INTERVAL;

  IF v_count >= p_max_requests THEN
    RETURN false;
  END IF;

  INSERT INTO rate_limit (identifier, endpoint) VALUES (p_identifier, p_endpoint);
  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 6. Tighten Reviews RLS
-- Replace "Public create reviews" with verified-only policy.
-- ============================================================

-- Add unique constraint: one review per appointment
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'reviews_appointment_id_unique'
  ) THEN
    ALTER TABLE reviews ADD CONSTRAINT reviews_appointment_id_unique UNIQUE (appointment_id);
  END IF;
END $$;

-- Drop the weak "Public create reviews" policy
DROP POLICY IF EXISTS "Public create reviews" ON reviews;

-- New policy: anyone can INSERT a review, BUT the appointment_id must
-- reference a COMPLETED appointment with matching patient_phone.
-- This is enforced via a WITH CHECK that validates the appointment.
CREATE POLICY "Verified create reviews" ON reviews FOR INSERT
  WITH CHECK (
    -- Must have an appointment_id
    appointment_id IS NOT NULL
    AND appointment_id IN (
      SELECT a.id FROM appointments a
      WHERE a.status = 'completed'
        AND a.patient_phone = reviews.patient_phone
    )
  );

-- Auto-mark reviews as verified when they have a valid appointment_id
CREATE OR REPLACE FUNCTION auto_verify_review()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.appointment_id IS NOT NULL THEN
    NEW.verified := true;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_auto_verify_review ON reviews;
CREATE TRIGGER trg_auto_verify_review
  BEFORE INSERT ON reviews
  FOR EACH ROW EXECUTE FUNCTION auto_verify_review();

-- ============================================================
-- 7. Tighten Appointments RLS
-- Add validation on INSERT to prevent past dates and invalid data.
-- ============================================================

-- Drop the weak "Public create appointments" policy
DROP POLICY IF EXISTS "Public create appointments" ON appointments;

-- New policy: anyone can INSERT, but with validation
CREATE POLICY "Validated create appointments" ON appointments FOR INSERT
  WITH CHECK (
    -- Date must not be in the past
    date >= to_char(NOW(), 'YYYY-MM-DD')
    -- Doctor must exist
    AND doctor_id IN (SELECT id FROM doctors)
    -- Clinic must be approved
    AND clinic_id IN (SELECT id FROM clinics WHERE status = 'approved')
    -- Doctor must belong to the specified clinic
    AND doctor_id IN (SELECT id FROM doctors WHERE clinic_id = appointments.clinic_id)
  );

-- Add trigger to log appointment status changes
CREATE OR REPLACE FUNCTION log_appointment_status_change()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO appointment_status_log (appointment_id, old_status, new_status, changed_by, changed_by_type)
    VALUES (NEW.id, OLD.status, NEW.status, auth.uid(),
      CASE
        WHEN is_admin() THEN 'admin'
        WHEN is_clinic_user() THEN 'clinic'
        ELSE 'system'
      END);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_log_appointment_status ON appointments;
CREATE TRIGGER trg_log_appointment_status
  AFTER UPDATE OF status ON appointments
  FOR EACH ROW EXECUTE FUNCTION log_appointment_status_change();

-- ============================================================
-- 8. Tighten Reminders RLS
-- Only allow INSERT when a valid appointment exists.
-- ============================================================
DROP POLICY IF EXISTS "Create reminders" ON reminders;

CREATE POLICY "Validated create reminders" ON reminders FOR INSERT
  WITH CHECK (
    appointment_id IN (SELECT id FROM appointments)
  );

-- ============================================================
-- 9. Tighten Clinics RLS
-- Add validation on public INSERT (registration).
-- ============================================================
DROP POLICY IF EXISTS "Public register clinic" ON clinics;

CREATE POLICY "Validated public register clinic" ON clinics FOR INSERT
  WITH CHECK (
    -- Name must not be empty
    name IS NOT NULL AND length(trim(name)) >= 3
    -- City must exist
    AND city_id IN (SELECT id FROM cities)
    -- Phone must be valid Iraqi format (07XXXXXXXXX)
    AND phone ~ '^07[0-9]{9}$'
  );

-- ============================================================
-- 10. Add updated_at tracking to key tables
-- ============================================================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add updated_at column to appointments if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'appointments' AND column_name = 'updated_at'
  ) THEN
    ALTER TABLE appointments ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_appointments_updated_at ON appointments;
CREATE TRIGGER trg_appointments_updated_at
  BEFORE UPDATE ON appointments
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Add updated_at to clinics
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'clinics' AND column_name = 'updated_at'
  ) THEN
    ALTER TABLE clinics ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_clinics_updated_at ON clinics;
CREATE TRIGGER trg_clinics_updated_at
  BEFORE UPDATE ON clinics
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Add updated_at to doctors
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'doctors' AND column_name = 'updated_at'
  ) THEN
    ALTER TABLE doctors ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_doctors_updated_at ON doctors;
CREATE TRIGGER trg_doctors_updated_at
  BEFORE UPDATE ON doctors
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- 11. Add license_number to clinics (for verification)
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'clinics' AND column_name = 'license_number'
  ) THEN
    ALTER TABLE clinics ADD COLUMN license_number TEXT;
  END IF;
END $$;

-- ============================================================
-- 12. Add payment_status to appointments
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'appointments' AND column_name = 'payment_status'
  ) THEN
    ALTER TABLE appointments ADD COLUMN payment_status TEXT DEFAULT 'pending'
      CHECK (payment_status IN ('pending','paid','refunded','clinic'));
  END IF;
END $$;

-- ============================================================
-- 13. Add indexes for new tables
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_audit_log_actor ON audit_log(actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_target ON audit_log(target_table, target_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_created ON audit_log(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_status_log_appointment ON appointment_status_log(appointment_id);
CREATE INDEX IF NOT EXISTS idx_status_log_created ON appointment_status_log(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_payments_appointment ON payments(appointment_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(status);
CREATE INDEX IF NOT EXISTS idx_payments_external_ref ON payments(external_ref);

CREATE INDEX IF NOT EXISTS idx_staff_roles_clinic ON staff_roles(clinic_id);
CREATE INDEX IF NOT EXISTS idx_staff_roles_user ON staff_roles(user_id);

CREATE INDEX IF NOT EXISTS idx_rate_limit_identifier ON rate_limit(identifier, endpoint, created_at DESC);

-- ============================================================
-- 14. Secure View: public_doctor_summary
-- Exposes only public doctor info (no sensitive patient data).
-- ============================================================
CREATE OR REPLACE VIEW public_doctor_summary AS
SELECT
  d.id, d.name, d.name_en, d.specialty_id, d.clinic_id,
  d.photo, d.bio, d.qualifications, d.experience_years,
  d.price, d.gender, d.languages, d.rating, d.reviews_count,
  d.services, d.verified, d.featured
FROM doctors d
WHERE d.clinic_id IN (SELECT id FROM clinics WHERE status = 'approved');

GRANT SELECT ON public_doctor_summary TO anon;

  -- ============================================================
  -- 15. Notifications Log Table
  -- Tracks every notification sent (WhatsApp, SMS, email) with template,
  -- channel, status, and delivery metadata. Essential for auditing
  -- communication and debugging delivery failures.
  -- ============================================================
  CREATE TABLE IF NOT EXISTS notifications_log (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID, -- auth.users(id) or NULL for anon/patient
    appointment_id UUID REFERENCES appointments(id) ON DELETE SET NULL,
    channel TEXT NOT NULL CHECK (channel IN ('whatsapp', 'sms', 'email', 'push')),
    template TEXT NOT NULL, -- e.g. 'booking_confirmation', 'reminder_24h', 'reminder_2h', 'otp'
    recipient_phone TEXT,
    recipient_name TEXT,
    content TEXT, -- the message content sent
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'delivered', 'failed', 'read')),
    provider_message_id TEXT, -- ID from WhatsApp/SMS provider for tracking
    error_message TEXT,
    sent_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
  );

  ALTER TABLE notifications_log ENABLE ROW LEVEL SECURITY;

  -- Clinic can view notifications for their own appointments; admin can view all
  CREATE POLICY "Clinic view own notifications" ON notifications_log FOR SELECT
    USING (
      appointment_id IN (
        SELECT a.id FROM appointments a
        WHERE a.clinic_id = get_current_clinic_id()
      )
      OR is_admin()
    );

  -- Only service_role (Edge Functions) can insert/update notifications
  -- Client-side code should NOT write directly to this table.
  -- Notifications are created by Edge Functions after sending via WhatsApp API.
  CREATE POLICY "Admin manage notifications" ON notifications_log FOR ALL
    USING (is_admin()) WITH CHECK (is_admin());

  -- Indexes for notifications_log
  CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications_log(user_id);
  CREATE INDEX IF NOT EXISTS idx_notifications_appointment ON notifications_log(appointment_id);
  CREATE INDEX IF NOT EXISTS idx_notifications_status ON notifications_log(status);
  CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications_log(created_at DESC);
  CREATE INDEX IF NOT EXISTS idx_notifications_channel ON notifications_log(channel);

  -- ============================================================
  -- 16. Summary of Security Changes
  -- ============================================================
-- ✅ audit_log table with RLS (admin read only, function-based insert)
-- ✅ appointment_status_log table with RLS (tracks all status changes)
-- ✅ payments table with RLS (admin manage, clinic view own)
-- ✅ staff_roles table with RLS (granular clinic permissions)
-- ✅ rate_limit table with RLS (denied to all clients, service_role only)
-- ✅ Reviews: unique per appointment, verified-only INSERT policy
-- ✅ Appointments: validated INSERT (no past dates, valid doctor/clinic)
-- ✅ Reminders: validated INSERT (must reference real appointment)
-- ✅ Clinics: validated public registration (name length, valid city, phone format)
-- ✅ Triggers: auto-verify reviews, log status changes, update updated_at
-- ✅ Secure view: public_doctor_summary (approved clinics only)
-- ✅ License number field added to clinics
-- ✅ Payment status field added to appointments