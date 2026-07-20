/**
 * Deployment-specific configuration.
 *
 * Keep demo mode disabled in source control. A production deployment replaces
 * this file after the database migration and RLS tests have passed.
 */
window.SAHATNA_RUNTIME_CONFIG = Object.freeze({
  supabaseUrl: '',
  supabaseAnonKey: '',
  supabaseEnabled: false,
});
