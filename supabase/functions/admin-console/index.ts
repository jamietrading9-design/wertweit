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
  if (!supabaseURL || !serviceRoleKey) {
    console.error("Missing Supabase server configuration");
    return respond({ error: "Server configuration is incomplete" }, 500);
  }

  const accessToken = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
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

  if (authData.user.app_metadata?.role !== "admin") {
    return respond({ error: "Admin access required" }, 403);
  }

  let payload: Record<string, unknown>;
  try {
    payload = await request.json();
  } catch {
    return respond({ error: "Invalid JSON body" }, 400);
  }

  if (payload.action === "list-users") {
    const page = Number(payload.page ?? 1);
    const perPage = Number(payload.perPage ?? 50);
    if (!Number.isInteger(page) || page < 1 || !Number.isInteger(perPage) || perPage < 1 || perPage > 100) {
      return respond({ error: "Invalid pagination values" }, 400);
    }

    const { data, error } = await supabase.auth.admin.listUsers({ page, perPage });
    if (error) {
      console.error("Could not list accounts", error.message);
      return respond({ error: "Accounts could not be loaded" }, 502);
    }

    const userIds = data.users.map((user) => user.id);
    const { data: accessRows, error: accessError } = await supabase
      .from("app_user_access")
      .select("user_id, blocked, pro_until")
      .in("user_id", userIds);
    if (accessError) {
      console.error("Could not load account access", accessError.message);
      return respond({ error: "Account access could not be loaded" }, 502);
    }
    const accessByUser = new Map((accessRows ?? []).map((access) => [access.user_id, access]));

    return respond({
      users: data.users.map((user) => ({
        id: user.id,
        email: user.email ?? "",
        createdAt: user.created_at,
        lastSignInAt: user.last_sign_in_at,
        emailConfirmedAt: user.email_confirmed_at,
        blocked: accessByUser.get(user.id)?.blocked ?? false,
        proUntil: accessByUser.get(user.id)?.pro_until ?? null,
      })),
      page,
      perPage,
      total: data.total,
    });
  }

  if (payload.action === "create-user") {
    if (typeof payload.email !== "string" || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(payload.email.trim())) {
      return respond({ error: "A valid email address is required" }, 400);
    }
    if (payload.admin !== undefined && typeof payload.admin !== "boolean") {
      return respond({ error: "Invalid account role" }, 400);
    }
    const email = payload.email.trim();
    const { data, error } = await supabase.auth.admin.inviteUserByEmail(email, {
      redirectTo: "https://jamietrading9-design.github.io/wertweit/set-password.html",
    });
    if (error) {
      const alreadyRegistered = error.code === "email_exists" ||
        error.message.toLowerCase().includes("already registered") ||
        error.message.toLowerCase().includes("already been registered");
      if (alreadyRegistered && payload.admin !== true) {
        const { error: resendError } = await supabase.auth.resend({
          type: "signup",
          email,
          options: {
            emailRedirectTo: "https://jamietrading9-design.github.io/wertweit/set-password.html",
          },
        });
        if (!resendError) {
          return respond({ user: { email }, resent: true, emailType: "signup" });
        }

        const { error: recoveryError } = await supabase.auth.resetPasswordForEmail(email, {
          redirectTo: "https://jamietrading9-design.github.io/wertweit/set-password.html",
        });
        if (!recoveryError) {
          return respond({ user: { email }, resent: true, emailType: "recovery" });
        }

        console.error("Could not resend account confirmation or password setup email", {
          confirmationError: resendError.message,
          recoveryError: recoveryError.message,
        });
        return respond({
          error: "Für diese E-Mail besteht bereits ein Konto, aber Supabase konnte weder den Bestätigungs- noch den Passwort-Link versenden. Prüfe SMTP/E-Mail-Limits und die Redirect-URL in Supabase.",
        }, 409);
      }

      console.error("Could not invite account", error.message);
      if (alreadyRegistered) {
        return respond({
          error: "Diese E-Mail-Adresse hat bereits ein Konto. Aus Sicherheitsgründen wird einem bestehenden Konto über diese Einladung keine Admin-Rolle hinzugefügt.",
        }, 409);
      }
      return respond({
        error: `Einladung konnte nicht verschickt werden: ${error.message}. Prüfe Supabase Authentication > SMTP Settings und die E-Mail-Vorlage.`,
      }, 502);
    }
    if (payload.admin === true) {
      const { error: roleError } = await supabase.auth.admin.updateUserById(data.user.id, {
        app_metadata: { ...data.user.app_metadata, role: "admin" },
      });
      if (roleError) {
        console.error("Could not set invited admin role", roleError.message);
        await supabase.auth.admin.deleteUser(data.user.id);
        return respond({ error: "Admin invitation could not be completed" }, 502);
      }
    }
    return respond({ user: { id: data.user.id, email: data.user.email } }, 201);
  }

  if (payload.action === "set-pro-access") {
    if (typeof payload.userId !== "string" || !/^[0-9a-f-]{36}$/i.test(payload.userId)) {
      return respond({ error: "Invalid user ID" }, 400);
    }
    if (payload.userId === authData.user.id) {
      return respond({ error: "You cannot change your own admin Pro access here" }, 400);
    }
    if (typeof payload.proUntil !== "string") {
      return respond({ error: "A Pro expiration date is required" }, 400);
    }
    const proUntil = new Date(payload.proUntil);
    if (!Number.isFinite(proUntil.getTime()) || proUntil <= new Date() ||
        proUntil > new Date(Date.now() + 5 * 365 * 24 * 60 * 60 * 1000)) {
      return respond({ error: "The Pro expiration date must be in the future and within five years" }, 400);
    }
    const { data: currentAccess, error: currentAccessError } = await supabase
      .from("app_user_access")
      .select("blocked")
      .eq("user_id", payload.userId)
      .maybeSingle();
    if (currentAccessError) {
      console.error("Could not load account access", currentAccessError.message);
      return respond({ error: "Pro access could not be updated" }, 502);
    }
    const { error } = await supabase
      .from("app_user_access")
      .upsert({
        user_id: payload.userId,
        blocked: currentAccess?.blocked ?? false,
        pro_until: proUntil.toISOString(),
        updated_at: new Date().toISOString(),
        updated_by: authData.user.id,
      });
    if (error) {
      console.error("Could not update Pro access", error.message);
      return respond({ error: "Pro access could not be updated" }, 502);
    }
    return respond({ userId: payload.userId, proUntil: proUntil.toISOString() });
  }

  if (payload.action === "revoke-pro-access") {
    if (typeof payload.userId !== "string" || !/^[0-9a-f-]{36}$/i.test(payload.userId)) {
      return respond({ error: "Invalid user ID" }, 400);
    }
    const { data: currentAccess, error: currentAccessError } = await supabase
      .from("app_user_access")
      .select("blocked")
      .eq("user_id", payload.userId)
      .maybeSingle();
    if (currentAccessError) {
      console.error("Could not load account access", currentAccessError.message);
      return respond({ error: "Pro access could not be revoked" }, 502);
    }
    const { error } = await supabase
      .from("app_user_access")
      .upsert({
        user_id: payload.userId,
        blocked: currentAccess?.blocked ?? false,
        pro_until: null,
        updated_at: new Date().toISOString(),
        updated_by: authData.user.id,
      });
    if (error) {
      console.error("Could not revoke Pro access", error.message);
      return respond({ error: "Pro access could not be revoked" }, 502);
    }
    return respond({ userId: payload.userId, proUntil: null });
  }

  if (payload.action === "set-user-blocked") {
    if (typeof payload.userId !== "string" || !/^[0-9a-f-]{36}$/i.test(payload.userId) ||
        typeof payload.blocked !== "boolean") {
      return respond({ error: "Invalid account status" }, 400);
    }
    if (payload.userId === authData.user.id) {
      return respond({ error: "You cannot suspend your own admin account" }, 400);
    }
    const { data: target, error: targetError } = await supabase.auth.admin.getUserById(payload.userId);
    if (targetError || !target.user) {
      return respond({ error: "Account not found" }, 404);
    }
    if (target.user.app_metadata?.role === "admin") {
      return respond({ error: "Admin accounts cannot be suspended from this dashboard" }, 403);
    }
    const { data: currentAccess, error: currentAccessError } = await supabase
      .from("app_user_access")
      .select("pro_until")
      .eq("user_id", payload.userId)
      .maybeSingle();
    if (currentAccessError) {
      console.error("Could not load account access", currentAccessError.message);
      return respond({ error: "Account suspension could not be updated" }, 502);
    }
    const { error: banError } = await supabase.auth.admin.updateUserById(payload.userId, {
      ban_duration: payload.blocked ? "876000h" : "none",
    });
    if (banError) {
      console.error("Could not update auth suspension", banError.message);
      return respond({ error: "Account suspension could not be updated" }, 502);
    }
    const { error } = await supabase
      .from("app_user_access")
      .upsert({
        user_id: payload.userId,
        blocked: payload.blocked,
        pro_until: currentAccess?.pro_until ?? null,
        updated_at: new Date().toISOString(),
        updated_by: authData.user.id,
      });
    if (error) {
      console.error("Could not update account access", error.message);
      return respond({ error: "Account access could not be updated" }, 502);
    }
    return respond({ userId: payload.userId, blocked: payload.blocked });
  }

  if (payload.action === "list-support") {
    const { data: threads, error: threadsError } = await supabase
      .from("support_threads")
      .select("id, user_id, user_email, subject, status, created_at, updated_at")
      .order("updated_at", { ascending: false })
      .limit(100);
    if (threadsError) {
      console.error("Could not list support threads", threadsError.message);
      return respond({ error: "Support inbox could not be loaded" }, 502);
    }
    const threadIds = (threads ?? []).map((thread) => thread.id);
    if (threadIds.length === 0) return respond({ threads: [] });
    const { data: messages, error: messagesError } = await supabase.from("support_messages")
      .select("id, thread_id, sender_is_admin, body, created_at")
      .in("thread_id", threadIds)
      .order("created_at", { ascending: true });
    if (messagesError) {
      console.error("Could not load support inbox details", messagesError.message);
      return respond({ error: "Support inbox could not be loaded" }, 502);
    }
    return respond({
      threads: (threads ?? []).map((thread) => ({
        ...thread,
        email: thread.user_email || "Keine E-Mail",
        messages: (messages ?? []).filter((message) => message.thread_id === thread.id),
      })),
    });
  }

  if (payload.action === "reply-support") {
    if (typeof payload.threadId !== "string" || !/^[0-9a-f-]{36}$/i.test(payload.threadId) ||
        typeof payload.body !== "string") {
      return respond({ error: "A thread and message are required" }, 400);
    }
    const body = payload.body.trim();
    if (body.length < 1 || body.length > 5000) {
      return respond({ error: "The reply must be 1–5000 characters" }, 400);
    }
    const { data: thread, error: threadError } = await supabase
      .from("support_threads")
      .select("id")
      .eq("id", payload.threadId)
      .maybeSingle();
    if (threadError || !thread) return respond({ error: "Support conversation not found" }, 404);
    const { error: messageError } = await supabase
      .from("support_messages")
      .insert({
        thread_id: payload.threadId,
        sender_id: authData.user.id,
        sender_is_admin: true,
        body,
      });
    if (messageError) {
      console.error("Could not send support reply", messageError.message);
      return respond({ error: "Support reply could not be sent" }, 502);
    }
    const { error: updateError } = await supabase
      .from("support_threads")
      .update({ updated_at: new Date().toISOString(), status: "open" })
      .eq("id", payload.threadId);
    if (updateError) {
      console.error("Could not update support conversation", updateError.message);
      return respond({ error: "Support reply was sent but the conversation status could not be updated" }, 502);
    }
    return respond({ sent: true }, 201);
  }

  if (payload.action === "get-settings") {
    const { data, error } = await supabase
      .from("app_settings")
      .select("maintenance_enabled, maintenance_message, updated_at")
      .eq("id", 1)
      .single();

    if (error) {
      console.error("Could not load app settings", error.message);
      return respond({ error: "App settings could not be loaded" }, 502);
    }
    return respond({ settings: data });
  }

  if (payload.action === "update-maintenance") {
    if (typeof payload.enabled !== "boolean" || typeof payload.message !== "string") {
      return respond({ error: "Invalid maintenance settings" }, 400);
    }
    const message = payload.message.trim();
    if (message.length < 1 || message.length > 500) {
      return respond({ error: "The maintenance message must be 1–500 characters" }, 400);
    }

    const { data, error } = await supabase
      .from("app_settings")
      .update({
        maintenance_enabled: payload.enabled,
        maintenance_message: message,
        updated_at: new Date().toISOString(),
        updated_by: authData.user.id,
      })
      .eq("id", 1)
      .select("maintenance_enabled, maintenance_message, updated_at")
      .single();

    if (error) {
      console.error("Could not update maintenance settings", error.message);
      return respond({ error: "Maintenance settings could not be saved" }, 502);
    }
    return respond({ settings: data });
  }

  return respond({ error: "Unknown action" }, 400);
});
