/**
 * صحتنا - Supabase Configuration
 *
 * 1. أنشئ مشروع على https://supabase.com
 * 2. انسخ URL و anon key من Settings > API
 * 3. استبدل القيم أدناه
 * 4. شغّل supabase-schema.sql في SQL Editor
 */

const SUPABASE_CONFIG = {
  url: 'https://YOUR_PROJECT_ID.supabase.co',
  anonKey: 'YOUR_ANON_KEY',
  // ضع true بعد إعداد Supabase لتفعيل قاعدة البيانات الفعلية
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