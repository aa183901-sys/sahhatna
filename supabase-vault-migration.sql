DO $$ BEGIN
  RAISE EXCEPTION 'ملف Vault قديم ومعطّل لتجنب فقدان المفتاح. استخدم supabase-production-hardening.sql.';
END $$;

-- ============================================================
-- صحتنا (Sahatna) - Supabase Vault Migration
-- استبدال مفتاح التشفير الثابت بـ Supabase Vault
--
-- شغّل هذا الملف في Supabase SQL Editor AFTER:
--   1. supabase-schema.sql
--   2. supabase-security-hardening.sql
--   3. supabase-field-encryption.sql
--
-- الغرض: نقل مفتاح التشفير من كود SQL مكشوف إلى Vault آمن
-- ============================================================

-- ============================================================
-- 1. تفعيل إضافة pgsodium (مطلوبة لـ Vault)
-- ============================================================
-- ملاحظة: Vault متاح افتراضياً في مشاريع Supabase السحابية
-- إذا لم يكن متاحاً، شغّل:
-- CREATE EXTENSION IF NOT EXISTS pgsodium;

-- ============================================================
-- 2. إنشاء سر التشفير في Vault
-- المفتاح يُخزّن مشفّراً ولا يظهر في تعريف الدالة
-- ============================================================

-- حذف السر القديم إذا موجود (لإعادة التشغيل الآمن)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM vault.secrets WHERE name = 'sahatna_field_key'
  ) THEN
    DELETE FROM vault.secrets WHERE name = 'sahatna_field_key';
    RAISE NOTICE '✅ Deleted old vault secret';
  END IF;
END $$;

-- إنشاء سر جديد بقيمة عشوائية قوية (256-bit)
-- ⚠️ احفظ هذه القيمة في مكان آمن خارج قاعدة البيانات (نسخ احتياطي)
DO $$
DECLARE
  v_key TEXT;
BEGIN
  -- توليد مفتاح عشوائي قوي 64 محرف (256-bit hex)
  v_key := encode(gen_random_bytes(32), 'hex');
  
  INSERT INTO vault.secrets (name, description, secret)
  VALUES (
    'sahatna_field_key',
    'مفتاح تشفير الحقول الحساسة (patient_notes, national_id) - صحتنا',
    v_key
  );
  
  RAISE NOTICE '✅ Created new vault secret: sahatna_field_key';
  RAISE NOTICE '⚠️ احفظ المفتاح في مكان آمن كنسخة احتياطية';
END $$;

-- ============================================================
-- 3. تحديث دالة get_encryption_key() لقراءة المفتاح من Vault
-- بدلاً من القيمة الثابتة المكشوفة
-- ============================================================

CREATE OR REPLACE FUNCTION get_encryption_key()
RETURNS TEXT AS $$
DECLARE
  v_key TEXT;
BEGIN
  -- قراءة المفتاح من Vault (مشفّر أثناء التخزين)
  SELECT decrypted_secret INTO v_key
  FROM vault.decrypted_secrets
  WHERE name = 'sahatna_field_key'
  LIMIT 1;
  
  IF v_key IS NULL THEN
    RAISE EXCEPTION 'مفتاح التشفير غير موجود في Vault. شغّل supabase-vault-migration.sql أولاً';
  END IF;
  
  RETURN v_key;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- إعادة صلاحيات التنفيذ
REVOKE ALL ON FUNCTION get_encryption_key() FROM PUBLIC;
REVOKE ALL ON FUNCTION get_encryption_key() FROM anon;
GRANT EXECUTE ON FUNCTION get_encryption_key() TO authenticated;

-- ============================================================
-- 4. إعادة تشفير البيانات الموجودة بالمفتاح الجديد
-- (البيانات مشفّرة بالمفتاح القديم، نحتاج إعادة تشفيرها)
-- ============================================================

DO $$
DECLARE
  v_old_key TEXT;
  v_count INT := 0;
BEGIN
  -- المفتاح القديم (من النسخة السابقة - للترحيل فقط)
  v_old_key := 'sahatna_prod_encryption_key_change_me_in_production_2025';
  
  -- إعادة تشفير patient_notes_encrypted
  UPDATE appointments
  SET patient_notes_encrypted = pgp_sym_encrypt(
    pgp_sym_decrypt(patient_notes_encrypted, v_old_key),
    get_encryption_key()
  )
  WHERE patient_notes_encrypted IS NOT NULL;
  
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE '✅ Re-encrypted % rows in patient_notes_encrypted', v_count;
  
  -- إعادة تشفير national_id_encrypted
  UPDATE appointments
  SET national_id_encrypted = pgp_sym_encrypt(
    pgp_sym_decrypt(national_id_encrypted, v_old_key),
    get_encryption_key()
  )
  WHERE national_id_encrypted IS NOT NULL;
  
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE '✅ Re-encrypted % rows in national_id_encrypted', v_count;
END $$;

-- ============================================================
-- 5. دالة تدوير المفتاح (Key Rotation)
-- تستخدم لتغيير المفتاح دورياً بأمان
-- ============================================================

CREATE OR REPLACE FUNCTION rotate_encryption_key(p_new_key TEXT DEFAULT NULL)
RETURNS VOID AS $$
DECLARE
  v_old_key TEXT;
  v_new_key TEXT;
  v_count INT := 0;
BEGIN
  -- قراءة المفتاح القديم من Vault
  SELECT decrypted_secret INTO v_old_key
  FROM vault.decrypted_secrets
  WHERE name = 'sahatna_field_key'
  LIMIT 1;
  
  IF v_old_key IS NULL THEN
    RAISE EXCEPTION 'لا يوجد مفتاح حالي في Vault';
  END IF;
  
  -- توليد مفتاح جديد إذا لم يُمرر
  v_new_key := COALESCE(p_new_key, encode(gen_random_bytes(32), 'hex'));
  
  -- إعادة تشفير كل البيانات بالمفتاح الجديد
  UPDATE appointments
  SET patient_notes_encrypted = pgp_sym_encrypt(
    pgp_sym_decrypt(patient_notes_encrypted, v_old_key),
    v_new_key
  )
  WHERE patient_notes_encrypted IS NOT NULL;
  
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE '✅ Re-encrypted % rows with new key', v_count;
  
  UPDATE appointments
  SET national_id_encrypted = pgp_sym_encrypt(
    pgp_sym_decrypt(national_id_encrypted, v_old_key),
    v_new_key
  )
  WHERE national_id_encrypted IS NOT NULL;
  
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE '✅ Re-encrypted % national_id rows with new key', v_count;
  
  -- تحديث السر في Vault
  DELETE FROM vault.secrets WHERE name = 'sahatna_field_key';
  INSERT INTO vault.secrets (name, description, secret)
  VALUES (
    'sahatna_field_key',
    'مفتاح تشفير الحقول الحساسة - مدوّر ' || NOW()::TEXT,
    v_new_key
  );
  
  RAISE NOTICE '✅ Key rotation complete. احفظ المفتاح الجديد في مكان آمن';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- فقط الأدمن يمكنه تدوير المفتاح
REVOKE ALL ON FUNCTION rotate_encryption_key() FROM PUBLIC;
REVOKE ALL ON FUNCTION rotate_encryption_key() FROM anon, authenticated;

-- ============================================================
-- 6. ملخص التغييرات
-- ============================================================
-- ✅ مفتاح التشفير لم يعد مكشوفاً في كود SQL
-- ✅ المفتاح مخزّن في Vault (مشفّر أثناء التخزين)
-- ✅ البيانات الموجودة أُعيد تشفيرها بالمفتاح الجديد
-- ✅ دالة rotate_encryption_key() للتدوير الدوري الآمن
-- ✅ صلاحيات محددة: فقط authenticated يقرأ المفتاح
--
-- ⚠️ خطوات ما بعد التطبيق:
--   [ ] احفظ المفتاح في مكان آمن خارج قاعدة البيانات
--   [ ] جدول تدوير المفتاح كل 90 يوماً
--   [ ] راجع من يستدعي decrypt_field() دورياً
