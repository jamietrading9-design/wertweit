import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function respond(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return respond({ error: "Method not allowed" }, 405);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const accessToken = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!supabaseURL || !serviceRoleKey) {
    console.error("Missing Supabase server configuration");
    return respond({ error: "Server configuration is incomplete" }, 500);
  }
  if (!accessToken) {
    return respond({ error: "Authentication required" }, 401);
  }

  const supabase = createClient(supabaseURL, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data, error: authError } = await supabase.auth.getUser(accessToken);
  if (authError || !data.user) {
    return respond({ error: "Invalid or expired session" }, 401);
  }

  const { error } = await supabase.auth.admin.deleteUser(data.user.id);
  if (error) {
    console.error("Could not delete account", error.message);
    return respond({ error: "Account could not be deleted" }, 502);
  }
  return respond({ deleted: true });
});
