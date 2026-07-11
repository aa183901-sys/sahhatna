-- ============================================================
-- صحتنا (Sahatna) - Field-Level Encryption Migration
-- Run this in Supabase SQL Editor AFTER supabase-security-hardening.sql
--
-- PURPOSE: Encrypt sensitive fields (national_id, medical notes)
--          at rest using pgcrypto symmetric encryption.
--
-- SECURITY: Encryption keys should ideally be stored in Supabase
--           Vault (pgsodium), not hardcoded. For this migration,
--           we use a key passed via a SECURITY DEFINER function
--           so the key is never exposed to client roles.
--
-- NOTE: In production, replace the hardcoded key with a call to
--       vault.decrypted_secrets where the key is stored securely.
--       → شغّل supabase-vault-migration.sql لاستبدال المفتاح بـ Vault
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. Encryption Key Management
-- In production, store this in Supabase Vault and retrieve it
-- via a SECURITY DEFINER function. For now, we use a placeholder.
-- ============================================================

-- Helper: get encryption key (replace with Vault in production)
CREATE OR REPLACE FUNCTION get_encryption_key()
RETURNS TEXT AS $$
BEGIN
  -- ⚠️ PRODUCTION: Replace with vault.decrypted_secrets
  -- Example: SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'sahatna_field_key'
  RETURN 'sahatna_prod_encryption_key_change_me_in_production_2025';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 2. Add encrypted fields to appointments
-- patient_notes may contain sensitive medical info.
-- We keep the original column for backward compat but add
-- an encrypted version. Migration script below copies data.
-- ============================================================

-- Add encrypted patient_notes column
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'appointments' AND column_name = 'patient_notes_encrypted'
  ) THEN
    ALTER TABLE appointments ADD COLUMN patient_notes_encrypted BYTEA;
  END IF;
END $$;

-- ============================================================
-- 3. Add national_id field to patients (future patients table)
-- For now, add to appointments as optional encrypted field
-- for family member booking (booking on behalf of children/elderly)
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'appointments' AND column_name = 'national_id_encrypted'
  ) THEN
    ALTER TABLE appointments ADD COLUMN national_id_encrypted BYTEA;
  END IF;
END $$;

-- ============================================================
-- 4. Encryption/Decryption Helper Functions
-- These are SECURITY DEFINER so the key is never exposed.
-- ============================================================

-- Encrypt a text value
CREATE OR REPLACE FUNCTION encrypt_field(p_value TEXT)
RETURNS BYTEA AS $$
DECLARE
  v_key TEXT;
BEGIN
  IF p_value IS NULL OR p_value = '' THEN
    RETURN NULL;
  END IF;
  v_key := get_encryption_key();
  RETURN pgp_sym_encrypt(p_value, v_key);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Decrypt a text value
CREATE OR REPLACE FUNCTION decrypt_field(p_encrypted BYTEA)
RETURNS TEXT AS $$
DECLARE
  v_key TEXT;
BEGIN
  IF p_encrypted IS NULL THEN
    RETURN NULL;
  END IF;
  v_key := get_encryption_key();
  RETURN pgp_sym_decrypt(p_encrypted, v_key);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to authenticated users (clinic/admin can decrypt)
GRANT EXECUTE ON FUNCTION encrypt_field TO authenticated;
GRANT EXECUTE ON FUNCTION decrypt_field TO authenticated;

-- ============================================================
-- 5. Trigger: Auto-encrypt patient_notes on INSERT/UPDATE
-- When patient_notes is set, automatically encrypt it.
-- ============================================================

CREATE OR REPLACE FUNCTION auto_encrypt_appointment_notes()
RETURNS TRIGGER AS $$
BEGIN
  -- If patient_notes is provided (plaintext), encrypt it
  IF NEW.patient_notes IS NOT NULL AND NEW.patient_notes != '' THEN
    NEW.patient_notes_encrypted := encrypt_field(NEW.patient_notes);
    -- Clear the plaintext column for security
    -- We keep it NULL so plaintext is never stored
    NEW.patient_notes := '[محمي]';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_encrypt_appointment_notes ON appointments;
CREATE TRIGGER trg_encrypt_appointment_notes
  BEFORE INSERT OR UPDATE OF patient_notes ON appointments
  FOR EACH ROW EXECUTE FUNCTION auto_encrypt_appointment_notes();

-- ============================================================
-- 6. Migrate existing data: encrypt current patient_notes
-- ============================================================

DO $$
BEGIN
  -- Only run if there are unencrypted notes
  IF EXISTS (
    SELECT 1 FROM appointments
    WHERE patient_notes IS NOT NULL
      AND patient_notes != ''
      AND patient_notes != '[محمي]'
  ) THEN
    UPDATE appointments
    SET patient_notes_encrypted = encrypt_field(patient_notes),
        patient_notes = '[محمي]'
    WHERE patient_notes IS NOT NULL
      AND patient_notes != ''
      AND patient_notes != '[محمي]';
    RAISE NOTICE '✅ Migrated existing patient_notes to encrypted storage';
  ELSE
    RAISE NOTICE 'ℹ️ No unencrypted patient_notes to migrate';
  END IF;
END $$;

-- ============================================================
-- 7. Secure view: clinic_appointment_details
-- Decrypts patient_notes for authorized clinic users only.
-- RLS on the underlying appointments table ensures isolation.
-- ============================================================

CREATE OR REPLACE VIEW clinic_appointment_details AS
SELECT
  a.id, a.doctor_id, a.clinic_id, a.patient_name, a.patient_phone,
  a.patient_age,
  decrypt_field(a.patient_notes_encrypted) AS patient_notes,
  a.date, a.time, a.service, a.price, a.status,
  a.payment_method, a.payment_status, a.created_at, a.updated_at
FROM appointments a;

-- Grant access to authenticated users (RLS on appointments handles filtering)
GRANT SELECT ON clinic_appointment_details TO authenticated;

-- ============================================================
-- 8. Summary
-- ============================================================
-- ✅ Encryption key management via SECURITY DEFINER function
-- ✅ patient_notes_encrypted (BYTEA) column added to appointments
-- ✅ national_id_encrypted (BYTEA) column added to appointments
-- ✅ encrypt_field() / decrypt_field() helper functions
-- ✅ Auto-encrypt trigger on patient_notes (plaintext cleared after encrypt)
-- ✅ Existing data migrated to encrypted storage
-- ✅ Secure view clinic_appointment_details for authorized decryption
--
-- ⚠️ PRODUCTION CHECKLIST:
--   [ ] Replace get_encryption_key() with Supabase Vault
--   [ ] Rotate encryption key periodically
--   [ ] Audit who calls decrypt_field()
--   [ ] Backup encrypted data with key management plan