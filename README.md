# صحتنا (Sahatna)

منصة عربية لحجز المواعيد الطبية في العراق، تشمل واجهة للمريض ولوحة للعيادة ولوحة للإدارة.

## التشغيل المحلي

```bash
python -m http.server 8000
```

ثم افتح `http://localhost:8000`. يبقى التطبيق في الوضع التجريبي المحلي ما دام إعداد Supabase غير مفعّل.

## إعداد Supabase للإنتاج

> لا تفتح الموقع للجمهور بين الخطوتين 2 و3. ملف التحصين جزء إلزامي من إنشاء القاعدة وليس ترقية اختيارية.

1. أنشئ مشروع Supabase جديداً.
2. شغّل `supabase-schema.sql` مرة واحدة من SQL Editor.
3. شغّل `supabase-production-hardening.sql` مباشرة بعده.
4. شغّل `supabase-rls-tests.sql`. الملف عبارة عن أمر ذري واحد مناسب لـ SQL Editor؛ يحذف بيانات الاختبار عند النجاح ويتراجع عنها تلقائياً عند الفشل.
5. أنشئ مستخدم الإدارة الحقيقي من **Authentication > Users** ثم اربطه مرة واحدة من SQL Editor:

```sql
SELECT private.bootstrap_admin(
  'AUTH-USER-UUID'::uuid,
  'admin',
  'اسم المدير'
);
```

6. اضبط `js/runtime-config.js` وقت النشر فقط:

```js
window.SAHATNA_RUNTIME_CONFIG = Object.freeze({
  supabaseUrl: 'https://YOUR_PROJECT.supabase.co',
  supabaseAnonKey: 'YOUR_PUBLIC_ANON_KEY',
  supabaseEnabled: true,
});
```

لا تضع `service_role key` أو أي سر داخل ملفات الواجهة. عند تفعيل Supabase بإعداد ناقص يتوقف التطبيق برسالة واضحة بدلاً من الرجوع بصمت إلى `localStorage`.

## ملفات SQL القديمة

الملفات التالية محفوظة للتاريخ فقط، وتوقفت عمداً برسالة خطأ لمنع تشغيلها على بيئة حقيقية:

- `supabase-security-hardening.sql`
- `supabase-field-encryption.sql`
- `supabase-vault-migration.sql`
- `supabase-migration-functions.sql`
- `fix-booking-rls.sql`
- `fix-auth-users.sql`

المسار المعتمد الوحيد هو `supabase-schema.sql` ثم `supabase-production-hardening.sql`.

## الواجهات

- `index.html`: البحث والحجز.
- `my-bookings.html`: استرجاع الحجز برقم الحجز UUID ورقم الهاتف، مع إمكانية الإلغاء.
- `clinic.html`: إدارة حجوزات العيادة والأطباء والدوام بعد تسجيل الدخول عبر Supabase Auth.
- `admin.html`: الموافقات والإدارة بعد تسجيل الدخول بحساب الإدارة الحقيقي.
- `activate.html`: ربط مستخدم Auth بطلب عيادة موافق عليه باستخدام كود تفعيل لمرة واحدة.

## فحوصات الأمان

راجع [SECURITY.md](SECURITY.md) لتفاصيل نموذج الصلاحيات، التشفير، الاختبارات، وخطوات ما قبل النشر.

## الروابط

- الموقع: https://aa183901-sys.github.io/sahhatna/
- المستودع: https://github.com/aa183901-sys/sahhatna

## الترخيص

© 2025 صحتنا — صُنع للعراق 🇮🇶
