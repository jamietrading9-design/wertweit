import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendAPNS } from "../_shared/apns.ts";
import { sendViaGmail } from "../_shared/gmail.ts";

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

  if (payload.action === "send-email") {
    if (payload.audience !== "selected" && payload.audience !== "newsletter") {
      return respond({ error: "Invalid email recipient group" }, 400);
    }
    if (typeof payload.subject !== "string" || payload.subject.trim().length < 1 ||
        payload.subject.trim().length > 150 || /[\r\n]/.test(payload.subject) || typeof payload.body !== "string" ||
        payload.body.trim().length < 1 || payload.body.trim().length > 10000) {
      return respond({ error: "The subject and message are required and must fit within their character limits" }, 400);
    }

    let userIds: string[];
    if (payload.audience === "selected") {
      if (!Array.isArray(payload.userIds) || payload.userIds.length < 1 ||
          payload.userIds.length > 99 ||
          payload.userIds.some((id) => typeof id !== "string" || !/^[0-9a-f-]{36}$/i.test(id)) ||
          new Set(payload.userIds).size !== payload.userIds.length) {
        return respond({ error: "Select between 1 and 99 valid, distinct user accounts" }, 400);
      }
      userIds = payload.userIds;
    } else {
      const { data: preferences, error: preferencesError } = await supabase
        .from("email_update_preferences")
        .select("user_id")
        .eq("subscribed", true)
        .limit(100);
      if (preferencesError) {
        console.error("Could not load email subscribers", preferencesError.message);
        return respond({ error: "Email subscribers could not be loaded" }, 502);
      }
      if ((preferences ?? []).length > 99) {
        return respond({ error: "More than 99 users are subscribed. Narrow the recipient group before sending." }, 400);
      }
      userIds = (preferences ?? []).map((preference) => preference.user_id);
    }

    if (userIds.length === 0) {
      return respond({ error: "No users are available in this recipient group" }, 400);
    }

    const recipientResults = await Promise.all(userIds.map((id) => supabase.auth.admin.getUserById(id)));
    const failedRecipient = recipientResults.find(({ error, data }) => error || !data.user);
    if (failedRecipient) {
      console.error("Could not resolve an email recipient", failedRecipient.error?.message ?? "User not found");
      return respond({ error: "One or more recipient accounts could not be loaded. Refresh the user list and try again." }, 502);
    }
    const users = recipientResults.flatMap(({ data }) => data.user ? [data.user] : []);
    if (payload.audience === "selected" && users.some((user) => !user.email_confirmed_at || !user.email)) {
      return respond({ error: "Every selected account must have a confirmed email address before it can receive an email." }, 400);
    }
    const recipients = users.flatMap((user) =>
      user.email_confirmed_at && user.email ? [user.email] : []
    );
    if (recipients.length === 0) {
      return respond({ error: "There are no confirmed email addresses in this recipient group" }, 400);
    }

    const subject = payload.subject.trim();
    const message = payload.body.trim();
    const unsubscribeText = payload.audience === "newsletter"
      ? "\n\nDu erhältst diese Nachricht, weil du Produktneuigkeiten in Wertweit eingeschaltet hast. Du kannst sie jederzeit im App-Menü ausschalten."
      : "";
    try {
      const result = await sendViaGmail(recipients, subject, `${message}${unsubscribeText}`);
      const failedEmails = new Set(result.failed.map((failure) => failure.email.toLowerCase()));
      const successfulUsers = users.filter((user) =>
        user.email_confirmed_at && user.email && !failedEmails.has(user.email.toLowerCase())
      );
      const notifications = successfulUsers.map((user) => ({
        user_id: user.id,
        title: subject,
        body: message.slice(0, 500),
        kind: "admin_email",
      }));
      let notificationStatus = {
        created: 0,
        pushSent: 0,
        pushFailed: 0,
        pushConfigured: false,
      };
      if (notifications.length > 0) {
        const { data: inserted, error: notificationError } = await supabase
          .from("app_notifications")
          .insert(notifications)
          .select("id, user_id");
        if (notificationError) {
          console.error("Email delivered but in-app notifications could not be saved", notificationError.message);
        } else {
          notificationStatus.created = inserted?.length ?? 0;
          const userIdsWithNotifications = [...new Set((inserted ?? []).map((item) => item.user_id))];
          if (userIdsWithNotifications.length > 0) {
            const { data: tokens, error: tokenError } = await supabase
              .from("device_push_tokens")
              .select("device_token")
              .in("user_id", userIdsWithNotifications)
              .eq("enabled", true);
            if (tokenError) {
              console.error("In-app notifications saved but device tokens could not be loaded", tokenError.message);
            } else {
              try {
                const push = await sendAPNS(
                  [...new Set((tokens ?? []).map((item) => item.device_token))],
                  { title: subject, body: message.slice(0, 500) },
                );
                notificationStatus.pushSent = push.sent;
                notificationStatus.pushFailed = push.failed;
                notificationStatus.pushConfigured = push.configured;
              } catch (error) {
                console.error("In-app notifications saved but APNs delivery failed", error);
                notificationStatus.pushConfigured = true;
                notificationStatus.pushFailed = (tokens ?? []).length;
              }
            }
          }
        }
      }
      return respond({ ...result, appNotifications: notificationStatus });
    } catch (error) {
      console.error("Could not send admin email", error);
      return respond({ error: error instanceof Error ? error.message : "Email could not be sent" }, 502);
    }
  }

  if (payload.action === "dashboard-metrics") {
    const [{ data: metrics, error: metricsError }, { data: users, error: usersError }] = await Promise.all([
      supabase.rpc("admin_dashboard_metrics"),
      supabase.auth.admin.listUsers({ page: 1, perPage: 1 }),
    ]);
    if (metricsError) {
      console.error("Could not load dashboard metrics", metricsError.message);
      return respond({ error: "Dashboard statistics could not be loaded" }, 502);
    }
    if (usersError) {
      console.error("Could not count user accounts", usersError.message);
      return respond({ error: "Account statistics could not be loaded" }, 502);
    }
    return respond({ metrics: { ...metrics, total_accounts: users.total ?? 0 } });
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
    const filter = typeof payload.filter === "string" ? payload.filter : "open";
    if (!["open", "mine", "all", "closed"].includes(filter)) {
      return respond({ error: "Invalid support filter" }, 400);
    }
    let threadQuery = supabase
      .from("support_threads")
      .select("id, user_id, user_email, subject, status, created_at, updated_at, claimed_by, claimed_at")
      .order("updated_at", { ascending: false })
      .limit(100);
    if (filter === "open") threadQuery = threadQuery.eq("status", "open");
    if (filter === "mine") threadQuery = threadQuery.eq("claimed_by", authData.user.id);
    if (filter === "closed") threadQuery = threadQuery.eq("status", "closed");
    const { data: threads, error: threadsError } = await threadQuery;
    if (threadsError) {
      console.error("Could not list support threads", threadsError.message);
      return respond({ error: "Support inbox could not be loaded" }, 502);
    }
    const threadIds = (threads ?? []).map((thread) => thread.id);
    if (threadIds.length === 0) return respond({ threads: [] });
    const [messagesResult, claimedUsers] = await Promise.all([
      supabase.from("support_messages")
      .select("id, thread_id, sender_is_admin, body, created_at")
      .in("thread_id", threadIds)
      .order("created_at", { ascending: true }),
      Promise.all([...new Set((threads ?? []).map((thread) => thread.claimed_by).filter((id): id is string => Boolean(id)))]
          .map(async (id) => {
            const { data, error } = await supabase.auth.admin.getUserById(id);
            return { id, email: data.user?.email ?? "Admin", error: error?.message };
          })),
    ]);
    const { data: messages, error: messagesError } = messagesResult;
    if (messagesError) {
      console.error("Could not load support inbox details", messagesError.message);
      return respond({ error: "Support inbox could not be loaded" }, 502);
    }
    if (claimedUsers.some((user) => user.error)) {
      console.error("Could not load support ticket assignees", claimedUsers.filter((user) => user.error).map((user) => user.error));
      return respond({ error: "Support ticket assignees could not be loaded" }, 502);
    }
    const claimedEmailByUser = new Map(claimedUsers.map(({ id, email }) => [id, email]));
    return respond({
      threads: (threads ?? []).map((thread) => ({
        ...thread,
        email: thread.user_email || "Keine E-Mail",
        claimedEmail: thread.claimed_by ? claimedEmailByUser.get(thread.claimed_by) ?? "Admin" : null,
        messages: (messages ?? []).filter((message) => message.thread_id === thread.id),
      })),
    });
  }

  if (payload.action === "claim-support") {
    if (typeof payload.threadId !== "string" || !/^[0-9a-f-]{36}$/i.test(payload.threadId)) {
      return respond({ error: "A valid support ticket is required" }, 400);
    }
    const { data: ticket, error: ticketError } = await supabase
      .from("support_threads")
      .select("id, status, claimed_by")
      .eq("id", payload.threadId)
      .maybeSingle();
    if (ticketError) {
      console.error("Could not load support ticket before claiming", ticketError.message);
      return respond({ error: "Support ticket could not be claimed" }, 502);
    }
    if (!ticket) return respond({ error: "Support ticket not found" }, 404);
    if (ticket.status === "closed") return respond({ error: "This ticket is closed. Reopen it before claiming." }, 409);
    if (ticket.claimed_by === authData.user.id) return respond({ claimed: true });
    if (ticket.claimed_by) {
      const { data: assignee } = await supabase.auth.admin.getUserById(ticket.claimed_by);
      return respond({ error: `This ticket is being handled by ${assignee.user?.email ?? "another admin"}.` }, 409);
    }

    const { data: claimed, error: claimError } = await supabase
      .from("support_threads")
      .update({
        claimed_by: authData.user.id,
        claimed_at: new Date().toISOString(),
        status: "in_progress",
        updated_at: new Date().toISOString(),
      })
      .eq("id", ticket.id)
      .eq("status", "open")
      .is("claimed_by", null)
      .select("id")
      .maybeSingle();
    if (claimError) {
      console.error("Could not claim support ticket", claimError.message);
      return respond({ error: "Support ticket could not be claimed" }, 502);
    }
    if (!claimed) return respond({ error: "Another admin claimed this ticket just now. Refresh the inbox." }, 409);
    return respond({ claimed: true });
  }

  if (payload.action === "release-support") {
    if (typeof payload.threadId !== "string" || !/^[0-9a-f-]{36}$/i.test(payload.threadId)) {
      return respond({ error: "A valid support ticket is required" }, 400);
    }
    const { data, error } = await supabase
      .from("support_threads")
      .update({
        claimed_by: null,
        claimed_at: null,
        status: "open",
        updated_at: new Date().toISOString(),
      })
      .eq("id", payload.threadId)
      .eq("claimed_by", authData.user.id)
      .eq("status", "in_progress")
      .select("id")
      .maybeSingle();
    if (error) {
      console.error("Could not release support ticket", error.message);
      return respond({ error: "Support ticket could not be released" }, 502);
    }
    if (!data) return respond({ error: "This ticket is no longer assigned to you." }, 409);
    return respond({ released: true });
  }

  if (payload.action === "close-support") {
    if (typeof payload.threadId !== "string" || !/^[0-9a-f-]{36}$/i.test(payload.threadId)) {
      return respond({ error: "A valid support ticket is required" }, 400);
    }
    const { data, error } = await supabase
      .from("support_threads")
      .update({
        status: "closed",
        claimed_by: null,
        claimed_at: null,
        updated_at: new Date().toISOString(),
      })
      .eq("id", payload.threadId)
      .eq("claimed_by", authData.user.id)
      .eq("status", "in_progress")
      .select("id")
      .maybeSingle();
    if (error) {
      console.error("Could not close support ticket", error.message);
      return respond({ error: "Support ticket could not be closed" }, 502);
    }
    if (!data) return respond({ error: "Claim this ticket before closing it." }, 409);
    return respond({ closed: true });
  }

  if (payload.action === "reopen-support") {
    if (typeof payload.threadId !== "string" || !/^[0-9a-f-]{36}$/i.test(payload.threadId)) {
      return respond({ error: "A valid support ticket is required" }, 400);
    }
    const { data, error } = await supabase
      .from("support_threads")
      .update({ status: "open", updated_at: new Date().toISOString() })
      .eq("id", payload.threadId)
      .eq("status", "closed")
      .select("id")
      .maybeSingle();
    if (error) {
      console.error("Could not reopen support ticket", error.message);
      return respond({ error: "Support ticket could not be reopened" }, 502);
    }
    if (!data) return respond({ error: "This ticket is no longer closed." }, 409);
    return respond({ reopened: true });
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
    const { data: reply, error: replyError } = await supabase.rpc("admin_reply_support", {
      p_thread_id: payload.threadId,
      p_sender_id: authData.user.id,
      p_body: body,
    });
    if (replyError || !reply?.[0]) {
      if (replyError?.code === "P0001") {
        return respond({ error: "Claim this ticket before replying. Tickets assigned to another admin are locked." }, 409);
      }
      if (replyError?.code === "P0002") return respond({ error: "Support conversation not found" }, 404);
      console.error("Could not save support reply", replyError?.message ?? "No reply record returned");
      return respond({ error: "Support reply could not be saved" }, 502);
    }
    const thread = reply[0];
    let emailSent = false;
    let emailError: string | null = null;
    let recipientEmail = thread.user_email;
    if (!recipientEmail) {
      const { data: user, error: userError } = await supabase.auth.admin.getUserById(thread.user_id);
      if (userError) {
        console.error("Could not load support email recipient", userError.message);
      }
      recipientEmail = user.user?.email ?? "";
    }
    if (recipientEmail) {
      try {
        const emailResult = await sendViaGmail(
          [recipientEmail],
          `Antwort zu deiner Support-Anfrage: ${thread.subject.replace(/[\r\n]/g, " ").slice(0, 100)}`,
          `Hallo,\n\nDer Wertweit-Support hat auf dein Ticket geantwortet:\n\n${body}\n\nDu kannst den vollständigen Verlauf in der Wertweit-App unter Support ansehen.`,
        );
        emailSent = emailResult.sent === 1 && emailResult.failed.length === 0;
        if (!emailSent) emailError = emailResult.failed[0]?.error ?? "Die E-Mail konnte nicht bestätigt werden.";
      } catch (error) {
        emailError = error instanceof Error ? error.message : "E-Mail konnte nicht gesendet werden.";
      }
    } else {
      emailError = "Für dieses Konto ist keine E-Mail-Adresse gespeichert.";
    }
    if (!emailSent) console.error("Support reply saved but email notification failed", emailError);
    return respond({ sent: true, emailSent, emailError }, 201);
  }

  if (payload.action === "get-settings") {
    const { data, error } = await supabase
      .from("app_settings")
      .select("maintenance_enabled, maintenance_message, pro_offer_title, pro_offer_message, pro_monthly_offer_message, pro_yearly_offer_message, updated_at")
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

  if (payload.action === "update-pro-offer") {
    const { title, message, monthlyMessage, yearlyMessage } = payload;
    if (typeof title !== "string" || title.trim().length < 1 || title.trim().length > 80 ||
        typeof message !== "string" || message.trim().length < 1 || message.trim().length > 500 ||
        typeof monthlyMessage !== "string" || monthlyMessage.trim().length < 1 || monthlyMessage.trim().length > 160 ||
        typeof yearlyMessage !== "string" || yearlyMessage.trim().length < 1 || yearlyMessage.trim().length > 160) {
      return respond({ error: "Offer text is required and must fit within the displayed character limits" }, 400);
    }
    const { data, error } = await supabase
      .from("app_settings")
      .update({
        pro_offer_title: title.trim(),
        pro_offer_message: message.trim(),
        pro_monthly_offer_message: monthlyMessage.trim(),
        pro_yearly_offer_message: yearlyMessage.trim(),
        updated_at: new Date().toISOString(),
        updated_by: authData.user.id,
      })
      .eq("id", 1)
      .select("pro_offer_title, pro_offer_message, pro_monthly_offer_message, pro_yearly_offer_message, updated_at")
      .single();
    if (error) {
      console.error("Could not update Pro offer copy", error.message);
      return respond({ error: "Pro offer text could not be saved" }, 502);
    }
    return respond({ settings: data });
  }

  return respond({ error: "Unknown action" }, 400);
});
