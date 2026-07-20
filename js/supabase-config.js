/**
 * صحتنا - Supabase Configuration
 *
 * Production values are supplied by js/runtime-config.js at deployment time.
 * Supabase never silently falls back to localStorage after being enabled.
 */

const runtimeConfig = window.SAHATNA_RUNTIME_CONFIG || {};
const SUPABASE_CONFIG = {
  url: runtimeConfig.supabaseUrl || '',
  anonKey: runtimeConfig.supabaseAnonKey || '',
  enabled: runtimeConfig.supabaseEnabled === true,
};

// Load Supabase JS SDK dynamically if enabled
let supabaseClient = null;

async function initSupabase() {
  if (!SUPABASE_CONFIG.enabled || supabaseClient) return supabaseClient;

  if (!SUPABASE_CONFIG.url || !SUPABASE_CONFIG.anonKey) {
    throw new Error('Supabase is enabled but runtime configuration is incomplete');
  }

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
