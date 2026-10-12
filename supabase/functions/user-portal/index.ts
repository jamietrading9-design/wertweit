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
  const { data: authData, error: authError } = await supabase.auth.getUser(accessToken);
  if (authError || !authData.user) {
    return respond({ error: "Invalid or expired session" }, 401);
  }

  const userId = authData.user.id;
  const { data: access, error: accessError } = await supabase
    .from("app_user_access")
    .select("blocked, pro_until")
    .eq("user_id", userId)
    .maybeSingle();
  if (accessError) {
    console.error("Could not load account access", accessError.message);
    return respond({ error: "Account access could not be loaded" }, 502);
  }
  if (access?.blocked) {
    return respond({ error: "This account is suspended" }, 403);
  }

  let payload: Record<string, unknown>;
  try {
    payload = await request.json();
  } catch {
    return respond({ error: "Invalid JSON body" }, 400);
  }

  if (payload.action === "get-access") {
    const proUntil = access?.pro_until ?? null;
    return respond({
      proUntil,
      hasAdminPro: proUntil !== null && Date.parse(proUntil) > Date.now(),
    });
  }

  if (payload.action === "list-support") {
    const { data: threads, error: threadsError } = await supabase
      .from("support_threads")
      .select("id, subject, status, created_at, updated_at")
      .eq("user_id", userId)
      .order("updated_at", { ascending: false })
      .limit(50);
    if (threadsError) {
      console.error("Could not list support threads", threadsError.message);
      return respond({ error: "Support messages could not be loaded" }, 502);
    }

    const threadIds = (threads ?? []).map((thread) => thread.id);
    if (threadIds.length === 0) return respond({ threads: [] });

    const { data: messages, error: messagesError } = await supabase
      .from("support_messages")
      .select("id, thread_id, sender_is_admin, body, created_at")
      .in("thread_id", threadIds)
      .order("created_at", { ascending: true });
    if (messagesError) {
      console.error("Could not load support messages", messagesError.message);
      return respond({ error: "Support messages could not be loaded" }, 502);
    }

    return respond({
      threads: (threads ?? []).map((thread) => ({
        ...thread,
        messages: (messages ?? []).filter((message) => message.thread_id === thread.id),
      })),
    });
  }

  if (payload.action === "create-support") {
    if (typeof payload.subject !== "string" || typeof payload.body !== "string") {
      return respond({ error: "A subject and message are required" }, 400);
    }
    const subject = payload.subject.trim();
    const body = payload.body.trim();
    if (subject.length < 1 || subject.length > 120 || body.length < 1 || body.length > 5000) {
      return respond({ error: "The subject or message has an invalid length" }, 400);
    }

    const { data: thread, error: threadError } = await supabase
      .from("support_threads")
      .insert({ user_id: userId, user_email: authData.user.email ?? "", subject })
      .select("id, subject, status, created_at, updated_at")
      .single();
    if (threadError) {
      console.error("Could not create support thread", threadError.message);
      return respond({ error: "Support request could not be sent" }, 502);
    }

    const { error: messageError } = await supabase
      .from("support_messages")
      .insert({ thread_id: thread.id, sender_id: userId, body });
    if (messageError) {
      console.error("Could not create support message", messageError.message);
      await supabase.from("support_threads").delete().eq("id", thread.id);
      return respond({ error: "Support request could not be sent" }, 502);
    }

    return respond({ thread }, 201);
  }

  return respond({ error: "Unknown action" }, 400);
});
