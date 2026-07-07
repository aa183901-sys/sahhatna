/**
 * صحتنا - Supabase Configuration
 *
 * 1. أنشئ مشروع على https://supabase.com
 * 2. انسخ URL و anon key من Settings > API
 * 3. استبدل القيم أدناه
 * 4. شغّل supabase-schema.sql في SQL Editor
 *
 * ملاحظة: Supabase مفعّل (enabled = true) — البيانات تُخزن في PostgreSQL.
 * الحسابات التجريبية (cl1/1234, cl2/1234, cl3/1234, admin/admin123) تعمل
 * عبر Supabase Auth الحقيقي. تأكد من تشغيل supabase-schema.sql في SQL Editor.
 */

const SUPABASE_CONFIG = {
  url: 'https://cjlykvcrzzlnjannjlgq.supabase.co',
  anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNqbHlrdmNyenpsbmphbm5qbGdxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzMzY1MzEsImV4cCI6MjA5ODkxMjUzMX0.FyQJBRwTyBbjt2RCUQInV3kicFGZfAosMaig70lfGkA',
  // ضع true بعد إعداد Supabase لتفعيل قاعدة البيانات الفعلية
  enabled: true,
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