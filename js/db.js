/**
 * صحتنا - DEPRECATED: This file is no longer used.
 *
 * All database logic has been consolidated into js/data.js (SahatnaDB).
 * This file is kept only for backwards compatibility — it is NOT loaded
 * by any HTML page (index.html, clinic.html, admin.html, activate.html).
 *
 * The old SahatnaAPI had security issues:
 *   - clinicLogin queried a non-existent 'password' column
 *   - createAppointment bypassed RLS validation
 *   - No audit logging
 *
 * If you need database access, use:
 *   <script src="js/data.js"></script>
 *   const data = await SahatnaDB.load();
 *
 * @deprecated Since v2.0 — use js/data.js (SahatnaDB) instead
 * @see js/data.js
 */

console.warn('⚠️ js/db.js is deprecated. Use js/data.js (SahatnaDB) instead.');