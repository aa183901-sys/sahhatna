/**
 * صحتنا - Rate Limiting Edge Function
 *
 * يستدعى قبل العمليات الحساسة (تسجيل دخول، حجز، تقييم)
 * للتحقق من عدم تجاوز الحد المسموح.
 *
 * Usage:
 *   POST /functions/v1/rate-limit
 *   Body: { "identifier": "ip_or_user_id", "action": "login", "maxAttempts": 5, "windowMinutes": 15 }
 *   Response: { "allowed": true } or { "allowed": false, "retryAfter": 300 }
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const { identifier, action, maxAttempts = 5, windowMinutes = 15 } = await req.json();

    if (!identifier || !action) {
      return new Response(
        JSON.stringify({ error: "identifier and action are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Call the database function check_rate_limit()
    const { data, error } = await supabase.rpc("check_rate_limit", {
      p_identifier: identifier,
      p_action: action,
      p_max_attempts: maxAttempts,
      p_window_minutes: windowMinutes,
    });

    if (error) {
      console.error("Rate limit check error:", error);
      return new Response(
        JSON.stringify({ allowed: true, error: "rate_limit_check_failed" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const allowed = data === true || data === "true" || data?.allowed === true;

    return new Response(
      JSON.stringify({
        allowed,
        retryAfter: allowed ? 0 : windowMinutes * 60,
      }),
      {
        status: allowed ? 200 : 429,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
          "Retry-After": allowed ? "0" : String(windowMinutes * 60),
        },
      }
    );
  } catch (err) {
    console.error("Edge function error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});