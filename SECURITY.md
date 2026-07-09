# 🔐 صحتنا - توثيق تحصين الأمان (Security Hardening)

## نظرة عامة

هذا التوثيق يشرح جميع التغييرات الأمنية المطبقة على منصة صحتنا، بترتيب التنفيذ المطلوب.

## 📋 ترتيب تطبيق ملفات SQL

يجب تطبيق ملفات SQL بالترتيب التالي في Supabase SQL Editor:

1. `supabase-schema.sql` — السكيما الأساسية (موجودة مسبقاً)
2. `supabase-security-hardening.sql` — تحصين RLS + جداول جديدة
3. `supabase-field-encryption.sql` — تشفير الحقول الحساسة
4. `supabase-rls-tests.sql` — اختبارات RLS (للتحقق فقط)

## 🔧 التغييرات المنفذة

### 1. سجل التدقيق (Audit Log)

**الملف:** `supabase-security-hardening.sql` (القسم 1)

- جدول `audit_log` جديد لتتبع كل عملية إدارية
- سياسة RLS: الأدمن فقط يقرأ، الإدراج عبر دالة `log_audit_entry()`
- الدالة `SECURITY DEFINER` لمنع الوصول المباشر للجدول

```sql
-- مثال استخدام
SELECT log_audit_entry('clinic.approve', 'clinics', 'clinic-uuid-here', '{"code":"ABC123"}'::JSONB);
```

### 2. سجل حالة المواعيد (Appointment Status Log)

**الملف:** `supabase-security-hardening.sql` (القسم 2)

- جدول `appointment_status_log` لتتبع كل تغيير حالة
- Trigger تلقائي `trg_log_appointment_status` يسجل التغييرات
- يميز نوع المغير: `patient` / `clinic` / `admin` / `system`

### 3. جدول المدفوعات (Payments)

**الملف:** `supabase-security-hardening.sql` (القسم 3)

- جدول `payments` لمعاملات ZainCash / AsiaHawala / كاش
- حقل `external_ref` فريد لكل معاملة (منع التكرار)
- RLS: العيادة ترى مدفوعاتها، الأدمن يرى الكل
- الإدارة المباشرة للأدمن فقط (webhooks عبر Edge Functions)

### 4. صلاحيات الموظفين (Staff Roles)

**الملف:** `supabase-security-hardening.sql` (القسم 4)

- جدول `staff_roles` لصلاحيات متدرجة
- الأدوار: `secretary` / `doctor` / `manager`
- المستخدم يرى دوره فقط، مدير العيادة يرى كل أدوار عيادته

### 5. تحديد المعدل (Rate Limiting)

**الملف:** `supabase-security-hardening.sql` (القسم 5)

- جدول `rate_limit` لتتبع الطلبات
- **مرفوض تماماً** للوصول المباشر من العميل (`USING (false)`)
- دالة `check_rate_limit()` للاستخدام من Edge Functions

```sql
-- مثال: 5 محاولات تسجيل دخول كل 15 دقيقة
SELECT check_rate_limit('192.168.1.1', 'login', 5, 15);
-- يعيد true إذا مسموح، false إذا تجاوز الحد
```

### 6. تشديد التقييمات (Reviews)

**الملف:** `supabase-security-hardening.sql` (القسم 6)

- **قيد فريد:** تقييم واحد لكل موعد (`reviews_appointment_id_unique`)
- **سياسة INSERT صارمة:** يجب وجود `appointment_id` لموعد **مكتمل** بنفس `patient_phone`
- Trigger تلقائي يضع `verified = true` عند وجود `appointment_id`
- **منع التقييمات الوهمية تماماً**

### 7. تشديد المواعيد (Appointments)

**الملف:** `supabase-security-hardening.sql` (القسم 7)

- **لا يمكن حجز موعد بتاريخ ماضي**
- يجب أن يكون الطبيب موجوداً
- يجب أن تكون العيادة موافق عليها (`status = 'approved'`)
- يجب أن ينتمي الطبيب للعيادة المحددة

### 8. تشديد التذكيرات (Reminders)

**الملف:** `supabase-security-hardening.sql` (القسم 8)

- لا يمكن إدراج تذكير بدون `appointment_id` صحيح

### 9. تشديد تسجيل العيادات

**الملف:** `supabase-security-hardening.sql` (القسم 9)

- اسم العيادة ≥ 3 محارف
- المدينة يجب أن تكون موجودة في `cities`
- رقم الهاتف بصيغة عراقية صحيحة: `07XXXXXXXXX`

### 10. تتبع `updated_at`

**الملف:** `supabase-security-hardening.sql` (القسم 10)

- أعمدة `updated_at` مضافة لـ `appointments`, `clinics`, `doctors`
- Triggers تحدّث القيمة تلقائياً عند التعديل

### 11. رقم ترخيص العيادة

**الملف:** `supabase-security-hardening.sql` (القسم 11)

- حقل `license_number` مضاف لـ `clinics` للتحقق الرسمي

### 12. حالة الدفع للموعد

**الملف:** `supabase-security-hardening.sql` (القسم 12)

- حقل `payment_status` مضاف لـ `appointments`
- القيم: `pending` / `paid` / `refunded` / `clinic`

### 13. العروض الآمنة (Secure Views)

**الملف:** `supabase-security-hardening.sql` (القسم 14)

- `public_doctor_summary` — معلومات الأطباء للعيادات الموافق عليها فقط
- `public_appointment_slots` — مواعيد متاحة بدون بيانات المرضى (موجود مسبقاً)

### 14. تشفير الحقول الحساسة

**الملف:** `supabase-field-encryption.sql`

- `patient_notes_encrypted` (BYTEA) — ملاحظات طبية مشفرة
- `national_id_encrypted` (BYTEA) — رقم الهوية المشفر
- دوال `encrypt_field()` و `decrypt_field()` بـ `SECURITY DEFINER`
- Trigger تلقائي يشفر `patient_notes` عند الإدراج/التحديث
- عرض `clinic_appointment_details` يفك التشفير للمستخدمين المخولين
- **⚠️ الإنتاج:** استبدل `get_encryption_key()` بـ Supabase Vault

## 🧪 اختبارات RLS

**الملف:** `supabase-rls-tests.sql`

يختبر 4 أدوار:
- `anon` (زائر / مريض غير مسجل)
- `authenticated` (مستخدم مسجل)
- `clinic` (عيادة)
- `admin` / `service_role`

### الاختبارات المغطاة:

| # | الاختبار | النتيجة المتوقعة |
|---|---------|-----------------|
| 1.1-1.6 | anon يقرأ البيانات العامة | ✅ مسموح |
| 1.7-1.13 | anon يقرأ الجداول الحساسة | ❌ ممنوع (0 صفوف) |
| 2.1 | حجز موعد بتاريخ ماضي | ❌ ممنوع |
| 2.2 | تقييم بدون موعد | ❌ ممنوع |
| 2.3 | تسجيل عيادة بهاتف خاطئ | ❌ ممنوع |
| 2.4 | تسجيل عيادة باسم قصير | ❌ ممنوع |
| 2.5 | تذكير بدون موعد صحيح | ❌ ممنوع |
| 5.1 | دالة تحديد المعدل | ✅ تعمل |
| 6.1 | دالة سجل التدقيق | ✅ تعمل |
| 7.1-7.3 | العروض الآمنة | ✅ تعمل |
| 8.1 | منع الحجز المزدوج | ✅ ممنوع |
| 9.1 | تقييمين لنفس الموعد | ❌ ممنوع |

## 🔄 تغييرات كود الواجهة

### `js/data.js`

1. **`mapBooking()`**: أضيف حقل `paymentStatus`
2. **`loadFromSupabase()`**: يستخدم `clinic_appointment_details` لفك تشفير الملاحظات
   - fallback إلى `appointments` إذا العرض غير متوفر

## ⚠️ قائمة التحقق للإنتاج

- [ ] استبدال مفتاح التشفير بـ Supabase Vault
- [ ] تدوير مفتاح التشفير دورياً
- [ ] مراجعة من يستدعي `decrypt_field()`
- [ ] خطة نسخ احتياطي مع إدارة المفاتيح
- [ ] تفعيل Rate limiting على Edge Functions
- [ ] التحقق من توقيع webhooks (ZainCash / واتساب) بـ HS256
- [ ] اختبار RLS قبل كل نشر جديد
- [ ] عدم كشف `service_role key` في كود العميل أبداً

## 📊 ملخص الجداول الجديدة

| الجدول | الغرض | RLS |
|--------|------|-----|
| `audit_log` | سجل تدقيق | أدمن يقرأ فقط |
| `appointment_status_log` | تتبع حالة المواعيد | عيادة ترى مواعيدها |
| `payments` | معاملات الدفع | عيادة ترى مدفوعاتها |
| `staff_roles` | صلاحيات الموظفين | مستخدم يرى دوره |
| `rate_limit` | تحديد المعدل | مرفوض للعميل تماماً |

## 🛡️ ملخص السياسات المُشدّدة

| الجدول | السياسة القديمة | السياسة الجديدة |
|--------|----------------|----------------|
| `appointments` | `WITH CHECK (true)` | تحقق من التاريخ/الطبيب/العيادة |
| `reviews` | `WITH CHECK (true)` | موعد مكتمل + هاتف مطابق |
| `reminders` | `WITH CHECK (true)` | موعد صحيح موجود |
| `clinics` | `WITH CHECK (true)` | اسم ≥ 3 + مدينة + هاتف صحيح |