/**
 * صحتنا - Supabase Configuration
 *
 * 1. أنشئ مشروع على https://supabase.com
 * 2. انسخ URL و anon key من Settings > API
 * 3. استبدل القيم أدناه
 * 4. شغّل ملفات SQL بالترتيب في SQL Editor:
 *    a. supabase-schema.sql
 *    b. supabase-security-hardening.sql
 *    c. fix-auth-users.sql  ← مهم جداً لحسابات الدخول
 *    d. fix-booking-rls.sql
 *    e. supabase-field-encryption.sql
 *    f. supabase-vault-migration.sql
 * 5. بعد التأكد من نجاح كل الملفات، غيّر enabled إلى true
 *
 * ⚠️ حالياً enabled = false (وضع التجربة) — البيانات تُخزن في المتصفح فقط.
 *    هذا يضمن عمل جميع الوظائف (حجز، دخول عيادة، دخول إدارة) فوراً.
 *    لتفعيل قاعدة البيانات الفعلية، شغّل ملفات SQL أعلاه ثم ضع enabled = true.
 */

const SUPABASE_CONFIG = {
  url: 'https://cjlykvcrzzlnjannjlgq.supabase.co',
  anonKey: 'sb_publishable_21PkKAquV9ZtlZZumU3AeQ_NMY8Ffpc',
  // ⚠️ ضع true فقط بعد تشغيل كل ملفات SQL في Supabase SQL Editor
  enabled: false,
};

// Load Supabase JS SDK dynamically if enabled
let supabaseClient = null;

async function initSupabase() {
  if (!SUPABASE_CONFIG.enabled || supabaseClient) return supabaseClient;

  try {
    // Load Supabase SDK from CDN
    if (!window.supabase) {
      await loadScript('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2');
    }
    supabaseClient = window.supabase.createClient(
      SUPABASE_CONFIG.url,
      SUPABASE_CONFIG.anonKey
    );
    console.log('✅ Supabase connected');
    return supabaseClient;
  } catch (e) {
    console.error('❌ Supabase init failed, falling back to localStorage:', e);
    return null;
  }
}

function loadScript(src) {
  return new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = src;
    script.onload = resolve;
    script.onerror = reject;
    document.head.appendChild(script);
  });
}