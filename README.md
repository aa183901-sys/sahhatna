# صحتنا (Sahatna) — منصة حجز المواعيد الطبية

> منصة رقمية تربط المرضى بالأطباء والعيادات في العراق، مشابهة لتطبيق Vezeeta ومكيّفة للسوق العراقي.

## 🌐 الروابط

- **الموقع المباشر:** https://aa183901-sys.github.io/sahhatna/
- **المستودع:** https://github.com/aa183901-sys/sahhatna

## 🚀 التشغيل السريع

افتح `index.html` مباشرة في المتصفح، أو شغّل خادم محلي:

```bash
python -m http.server 8000
# أو
npx serve .
```

## 📁 هيكل المشروع

```
sahhatna/
├── index.html              # تطبيق المريض
├── clinic.html             # لوحة تحكم العيادة
├── admin.html              # لوحة تحكم الإدارة
├── activate.html           # تفعيل حساب العيادة
├── my-bookings.html        # حجوزات المريض
├── manifest.json           # PWA manifest
├── sw.js                   # Service Worker (PWA offline)
├── supabase-schema.sql     # SQL schema الأساسية
├── supabase-security-hardening.sql  # تحصين RLS + جداول جديدة
├── supabase-field-encryption.sql    # تشفير الحقول الحساسة
├── supabase-vault-migration.sql     # استبدال المفتاح بـ Vault
├── supabase-migration-functions.sql # دوال SQL المطلوبة
├── supabase-rls-tests.sql           # اختبارات RLS v2
├── fix-booking-rls.sql              # إصلاح دالة الحجز
├── fix-auth-users.sql               # إصلاح مستخدمي المصادقة
├── SECURITY.md                      # توثيق الأمان
├── BACKUP-PLAN.md                   # خطة النسخ الاحتياطي
├── css/
│   └── styles.css          # الأنماط المخصصة
├── js/
│   ├── data.js             # طبقة البيانات (Supabase + localStorage)
│   ├── supabase-config.js  # إعدادات Supabase
│   ├── whatsapp.js         # تذكيرات واتساب
│   ├── app.js              # منطق تطبيق المريض
│   ├── clinic.js           # منطق لوحة العيادة
│   ├── admin.js            # منطق لوحة الإدارة
│   ├── activate.js         # منطق تفعيل العيادة
│   └── my-bookings.js      # منطق حجوزات المريض
└── supabase/functions/     # Edge Functions
    ├── rate-limit/         # تحديد المعدل
    └── webhook-verify/     # التحقق من توقيع webhooks
```

## 🗄️ إعداد قاعدة البيانات (Supabase)

المشروع يعمل بشكل افتراضي بـ localStorage (demo mode). لتفعيل قاعدة بيانات فعلية:

1. أنشئ مشروع على [supabase.com](https://supabase.com)
2. اذهب إلى **SQL Editor** وشغّل ملف `supabase-schema.sql`
3. اذهب إلى **Settings > API** وانسخ `URL` و `anon key`
4. عدّل `js/supabase-config.js`:
   ```js
   const SUPABASE_CONFIG = {
     url: 'https://YOUR_PROJECT.supabase.co',
     anonKey: 'YOUR_ANON_KEY',
     enabled: true,  // ← غيّر إلى true
   };
   ```

### الجداول (Tables)
| الجدول | الوصف |
|---|---|
| `specialties` | التخصصات الطبية |
| `cities` | المدن العراقية |
| `clinics` | العيادات والمستشفيات |
| `doctors` | الأطباء |
| `schedules` | أوقات الدوام الأسبوعية |
| `appointments` | الحجوزات (مع منع الحجز المزدوج) |
| `reviews` | التقييمات (موثّقة فقط) |
| `reminders` | تذكيرات المواعيد |
| `clinic_users` | حسابات دخول العيادات |
| `admin_users` | حسابات الإدارة |

## 👥 أنواع المستخدمين

### 1. المريض (`index.html`)
- بحث وفلترة متقدمة (تخصص، مدينة، سعر، تقييم، جنس، نوع خدمة)
- بروفايل طبيب كامل مع تقييمات موثّقة
- حجز موعد فوري مع تأكيد لحظي
- 3 أنواع خدمات: عيادة / فيديو / منزلية
- الدفع عند الحضور
- تذكير عبر واتساب قبل الموعد

### 2. العيادة (`clinic.html`)
| العيادة | المستخدم | كلمة المرور |
|---|---|---|
| مركز الشفاء | `cl1` | `1234` |
| عيادة النور | `cl2` | `1234` |
| مستشفى الحياة | `cl3` | `1234` |

- إدارة الحجوزات (تأكيد/إلغاء/إكمال)
- تقويم شهري تفاعلي
- إدارة أوقات دوام كل طبيب
- إرسال تذكيرات واتساب للمرضى
- إحصائيات وإيرادات

### 3. الإدارة (`admin.html`)
**الحساب:** `admin` / `admin123`

- الموافقة/رفض العيادات الجديدة
- عرض كل الأطباء والحجوزات
- تحليلات بيانية (أكثر التخصصات طلباً، الإيرادات)

## 📱 PWA (Progressive Web App)

الموقع يدعم التثبيت كتطبيق على الموبايل:
- **Android:** Chrome → Menu → "Install app"
- **iOS:** Safari → Share → "Add to Home Screen"
- يعمل بدون إنترنت (Service Worker يخزن الصفحات)
- `manifest.json` يحدد الأيقونة والألوان

## 📲 تذكيرات واتساب

بدلاً من SMS، يستخدم المشروع واتساب (أفعل في العراق):
- `js/whatsapp.js` يفتح واتساب برسالة جاهزة
- يحوّل أرقام العراق تلقائياً (07XX → 9647XX)
- للإرسال التلقائي: اربط مع WhatsApp Business API أو Twilio

## 🇮🇶 تكييف السوق العراقي

- 12 مدينة عراقية + 12 تخصص طبي
- الأسعار بالدينار العراقي (IQD)
- الدفع عند الحضور كخيار أساسي
- واجهة عربية كاملة RTL مع خط Cairo

## 🔄 الترقية للإنتاج

| الميزة | الحالي | الإنتاج |
|---|---|---|
| قاعدة البيانات | localStorage / Supabase | Supabase + Redis |
| المصادقة | كلمة مرور بسيطة | Supabase Auth + OTP |
| الإشعارات | واتساب يدوي | WhatsApp Business API |
| الدفع | عند العيادة | Zain Cash / FastPay / Qi Card |
| الفيديو | — | Agora.io / Twilio |
| التطبيق | PWA | Flutter / React Native |

## 📝 الترخيص

© 2025 صحتنا — صُنع للعراق 🇮🇶