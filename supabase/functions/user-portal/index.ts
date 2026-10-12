import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendViaGmail } from "../_shared/gmail.ts";
import {
  classifySupport,
  supportCategoryLabel,
  supportPriorityEmoji,
  supportPriorityLabel,
} from "../_shared/support-classifier.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-supabase-api-version",
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
  let payload: Record<string, unknown>;
  try {
    payload = await request.json();
  } catch {
    return respond({ error: "Invalid JSON body" }, 400);
  }

  if (access?.blocked &&
      payload.action !== "get-email-updates" &&
      payload.action !== "set-email-updates") {
    return respond({ error: "This account is suspended" }, 403);
  }

  if (payload.action === "get-access") {
    const proUntil = access?.pro_until ?? null;
    return respond({
      proUntil,
      hasAdminPro: proUntil !== null && Date.parse(proUntil) > Date.now(),
    });
  }

  if (payload.action === "list-notifications") {
    const { data: notifications, error } = await supabase
      .from("app_notifications")
      .select("id, title, body, kind, created_at, read_at")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(50);
    if (error) {
      console.error("Could not load app notifications", error.message);
      return respond({ error: "App notifications could not be loaded" }, 502);
    }
    return respond({ notifications: notifications ?? [] });
  }

  if (payload.action === "mark-notifications-read") {
    if (!Array.isArray(payload.ids) || payload.ids.length > 50 ||
        payload.ids.some((id) => typeof id !== "string" || !/^[0-9a-f-]{36}$/i.test(id))) {
      return respond({ error: "Invalid notification identifiers" }, 400);
    }
    if (payload.ids.length === 0) return respond({ updated: 0 });
    const { data, error } = await supabase
      .from("app_notifications")
      .update({ read_at: new Date().toISOString() })
      .eq("user_id", userId)
      .in("id", payload.ids)
      .is("read_at", null)
      .select("id");
    if (error) {
      console.error("Could not mark app notifications read", error.message);
      return respond({ error: "App notifications could not be updated" }, 502);
    }
    return respond({ updated: data?.length ?? 0 });
  }

  if (payload.action === "register-push-token") {
    if (typeof payload.token !== "string" || !/^[0-9a-f]{64}$/i.test(payload.token)) {
      return respond({ error: "Invalid push token" }, 400);
    }
    const { error } = await supabase
      .from("device_push_tokens")
      .upsert({
        user_id: userId,
        device_token: payload.token.toLowerCase(),
        enabled: true,
        updated_at: new Date().toISOString(),
      });
    if (error) {
      console.error("Could not register device push token", error.message);
      return respond({ error: "Push notifications could not be enabled" }, 502);
    }
    return respond({ registered: true });
  }

  if (payload.action === "unregister-push-token") {
    if (typeof payload.token !== "string" || !/^[0-9a-f]{64}$/i.test(payload.token)) {
      return respond({ error: "Invalid push token" }, 400);
    }
    const { error } = await supabase
      .from("device_push_tokens")
      .delete()
      .eq("user_id", userId)
      .eq("device_token", payload.token.toLowerCase());
    if (error) {
      console.error("Could not unregister device push token", error.message);
      return respond({ error: "Push notifications could not be disabled" }, 502);
    }
    return respond({ unregistered: true });
  }

  if (payload.action === "get-email-updates") {
    const { data: preference, error } = await supabase
      .from("email_update_preferences")
      .select("subscribed")
      .eq("user_id", userId)
      .maybeSingle();
    if (error) {
      console.error("Could not load email update preference", error.message);
      return respond({ error: "Email preferences could not be loaded" }, 502);
    }
    return respond({ subscribed: preference?.subscribed ?? false });
  }

  if (payload.action === "set-email-updates") {
    if (typeof payload.subscribed !== "boolean") {
      return respond({ error: "A valid email preference is required" }, 400);
    }
    const subscribed = payload.subscribed;
    const { error } = await supabase
      .from("email_update_preferences")
      .upsert({
        user_id: userId,
        subscribed,
        subscribed_at: subscribed ? new Date().toISOString() : null,
        updated_at: new Date().toISOString(),
      });
    if (error) {
      console.error("Could not update email update preference", error.message);
      return respond({ error: "Email preferences could not be saved" }, 502);
    }
    return respond({ subscribed });
  }

  if (payload.action === "record-app-open") {
    const { data, error } = await supabase.rpc("record_app_open", { p_user_id: userId });
    if (error) {
      console.error("Could not record app session", error.message);
      return respond({ error: "App session could not be recorded" }, 502);
    }
    return respond({ recorded: data === true });
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
    const classification = classifySupport(subject, body);

    const { data: thread, error: threadError } = await supabase
      .from("support_threads")
      .insert({
        user_id: userId,
        user_email: authData.user.email ?? "",
        subject,
        support_category: classification.category,
        support_priority: classification.priority,
      })
      .select("id, subject, support_category, support_priority, status, created_at, updated_at")
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

    let adminNotified = false;
    try {
      const notification = await sendViaGmail(
        ["wertweitoffiziell@gmail.com"],
        `${supportPriorityEmoji(classification.priority)} ${supportPriorityLabel(classification.priority)} · ${supportCategoryLabel(classification.category)} · ${subject.replace(/[\r\n]/g, " ").slice(0, 80)}`,
        `Neue Support-Anfrage von ${authData.user.email ?? "unbekannter E-Mail-Adresse"}:\n\nPriorität: ${supportPriorityLabel(classification.priority)}\nKategorie: ${supportCategoryLabel(classification.category)}\nBetreff: ${subject}\n\n${body}`,
      );
      adminNotified = notification.sent === 1 && notification.failed.length === 0;
      if (!adminNotified) {
        console.error("Support ticket was created but its admin notification failed", notification.failed);
      }
    } catch (error) {
      console.error("Support ticket was created but its admin notification could not be sent", error);
    }
    return respond({ thread, adminNotified }, 201);
  }

  return respond({ error: "Unknown action" }, 400);
});
