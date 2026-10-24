import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendAPNS } from "../_shared/apns.ts";
import { sendViaGmail } from "../_shared/gmail.ts";
import {
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

function invoiceText(value: unknown, maximumLength: number, required = true): string | null {
  if (typeof value !== "string") return null;
  const text = value.trim();
  if (text.length > maximumLength || (required && text.length === 0)) return null;
  return text;
}

function invoiceDate(value: unknown): string | null {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const date = new Date(`${value}T00:00:00.000Z`);
  return Number.isNaN(date.valueOf()) || date.toISOString().slice(0, 10) !== value ? null : value;
}

function invoiceAmountCents(value: unknown): number | null {
  if (typeof value !== "string") return null;
  const match = value.trim().match(/^(\d{1,9})(?:\.(\d{1,2}))?$/);
  if (!match) return null;
  const cents = Number(match[1]) * 100 + Number((match[2] ?? "").padEnd(2, "0"));
  return Number.isSafeInteger(cents) && cents <= 100_000_000 ? cents : null;
}

function invoiceQuantityMilli(value: unknown): { quantity: string; milli: number } | null {
  if (typeof value !== "string") return null;
  const match = value.trim().match(/^(\d{1,5})(?:\.(\d{1,3}))?$/);
  if (!match) return null;
  const milli = Number(match[1]) * 1000 + Number((match[2] ?? "").padEnd(3, "0"));
  if (!Number.isSafeInteger(milli) || milli < 1 || milli > 10_000_000) return null;
  return { quantity: value.trim(), milli };
}

function isValidIban(value: string): boolean {
  if (!/^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$/.test(value)) return false;
  const rearranged = value.slice(4) + value.slice(0, 4);
  let remainder = 0;
  for (const character of rearranged) {
    const digits = /[A-Z]/.test(character)
      ? String(character.charCodeAt(0) - 55)
      : character;
    for (const digit of digits) {
      remainder = (remainder * 10 + Number(digit)) % 97;
    }
  }
  return remainder === 1;
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

  async function recordAdminActivity(
    action: string,
    summary: string,
    targetId: string | null = null,
    targetLabel = "",
    metadata: Record<string, unknown> = {},
  ): Promise<string | null> {
    const { error } = await supabase.from("admin_activity_log").insert({
      actor_id: authData.user.id,
      actor_email: authData.user.email ?? "",
      action,
      summary,
      target_id: targetId,
      target_label: targetLabel,
      metadata,
    });
    if (!error) return null;
    console.error("Admin action completed but its activity record could not be saved", {
      action,
      actorId: authData.user.id,
      error: error.message,
    });
    return "Die Aktion wurde ausgeführt, aber der Aktivitätsverlauf konnte nicht gespeichert werden.";
  }

  if (payload.action === "record-admin-activity") {
    const activityLabels: Record<string, string> = {
      "send-email": "E-Mail versendet",
      "create-user": "App-Konto eingeladen oder angelegt",
      "set-pro-access": "Admin-Pro-Zugriff vergeben",
      "revoke-pro-access": "Admin-Pro-Zugriff entzogen",
      "set-user-blocked": "Kontozugriff geändert",
      "claim-support": "Support-Ticket übernommen",
      "release-support": "Support-Ticket freigegeben",
      "close-support": "Support-Ticket geschlossen",
      "reopen-support": "Support-Ticket wieder geöffnet",
      "reply-support": "Support-Antwort gesendet",
      "save-private-admin-note": "Interne Notiz erstellt oder geändert",
      "delete-private-admin-note": "Interne Notiz gelöscht",
      "update-maintenance": "Wartungseinstellung geändert",
      "update-site-maintenance": "Website-Wartungseinstellung geändert",
      "update-pro-offer": "Pro-Angebotstexte geändert",
      "update-app-announcement": "Broadcast-Hinweis geändert",
      "save-invoice-settings": "Rechnungsabsender geändert",
      "save-invoice-customer": "Rechnungskunde angelegt",
      "update-invoice-customer": "Rechnungskunde geändert",
      "save-invoice-product": "Rechnungsprodukt gespeichert",
      "set-invoice-product-active": "Rechnungsproduktstatus geändert",
      "create-invoice": "App-Rechnung erstellt",
      "set-invoice-paid": "Rechnungszahlungsstatus geändert",
      "save-private-sale-settings": "Angaben für Privatverkäufe geändert",
      "save-private-sale-customer": "Privatkunde angelegt",
      "create-private-sale-receipt": "Privater Verkaufsbeleg erstellt",
    };
    const sourceAction = typeof payload.sourceAction === "string" ? payload.sourceAction : "";
    const activityLabel = activityLabels[sourceAction];
    if (!activityLabel) return respond({ error: "This admin action cannot be recorded" }, 400);
    const targetId = typeof payload.targetId === "string" && /^[0-9a-f-]{36}$/i.test(payload.targetId)
      ? payload.targetId
      : null;
    const targetLabel = typeof payload.targetLabel === "string" ? payload.targetLabel.trim().slice(0, 254) : "";
    const warning = await recordAdminActivity(
      sourceAction,
      activityLabel,
      targetId,
      targetLabel,
    );
    return respond(warning ? { warning } : { recorded: true });
  }

  if (payload.action === "list-admin-activity") {
    const { data, error } = await supabase
      .from("admin_activity_log")
      .select("id, actor_email, action, summary, target_id, target_label, metadata, created_at")
      .order("created_at", { ascending: false })
      .limit(100);
    if (error) {
      console.error("Could not load admin activity history", error.message);
      return respond({ error: "Admin activity history could not be loaded" }, 502);
    }
    return respond({ activities: data ?? [] });
  }

  if (payload.action === "send-email") {
    if (payload.audience !== "selected" && payload.audience !== "newsletter") {
      return respond({ error: "Invalid email recipient group" }, 400);
    }
    if (payload.category !== "service" && payload.category !== "marketing") {
      return respond({ error: "Invalid email category" }, 400);
    }
    if (payload.category === "marketing" && payload.audience !== "newsletter") {
      return respond({ error: "Marketing emails may only be sent to subscribed newsletter recipients" }, 400);
    }
    if (payload.audience === "selected" && payload.servicePurposeConfirmed !== true) {
      return respond({ error: "Confirm that the message is a necessary account or service email before sending to selected accounts" }, 400);
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
    const search = typeof payload.search === "string" ? payload.search.trim().toLowerCase() : "";
    const accountFilter = typeof payload.accountFilter === "string" ? payload.accountFilter : "all";
    const sortBy = typeof payload.sortBy === "string" ? payload.sortBy : "standard";
    if (!Number.isInteger(page) || page < 1 || !Number.isInteger(perPage) || perPage < 1 ||
        perPage > 100 || search.length > 160 ||
        !["all", "active", "blocked", "unconfirmed", "pro", "admin"].includes(accountFilter) ||
        !["standard", "created-asc", "last-sign-in-desc", "email-asc"].includes(sortBy)) {
      return respond({ error: "Invalid pagination values" }, 400);
    }

    let users;
    let userTotal: number;
    let accessRows;
    if (search || accountFilter !== "all" || sortBy !== "standard") {
      const { data, error } = await supabase.auth.admin.listUsers({ page: 1, perPage: 1000 });
      if (error) {
        console.error("Could not load accounts for filtering", error.message);
        return respond({ error: "Accounts could not be searched or filtered" }, 502);
      }
      const allUsers = [...data.users];
      const totalPages = Math.ceil((data.total ?? data.users.length) / 1000);
      for (let searchPage = 2; searchPage <= totalPages; searchPage += 1) {
        const { data: nextPage, error: nextPageError } = await supabase.auth.admin.listUsers({
          page: searchPage,
          perPage: 1000,
        });
        if (nextPageError) {
          console.error("Could not search all account pages", nextPageError.message);
          return respond({ error: "Account search could not be completed" }, 502);
        }
        allUsers.push(...nextPage.users);
      }
      const accessResults = await Promise.all(
        Array.from({ length: Math.ceil(allUsers.length / 500) }, (_, index) =>
          supabase.from("app_user_access")
            .select("user_id, blocked, pro_until")
            .in("user_id", allUsers.slice(index * 500, (index + 1) * 500).map((user) => user.id))
        ),
      );
      const accessError = accessResults.find((result) => result.error)?.error;
      if (accessError) {
        console.error("Could not load account access for filtering", accessError.message);
        return respond({ error: "Account access could not be loaded for filtering" }, 502);
      }
      accessRows = accessResults.flatMap((result) => result.data ?? []);
      const accessByUser = new Map(accessRows.map((access) => [access.user_id, access]));
      const matchingUsers = allUsers.filter((user) => {
        const access = accessByUser.get(user.id);
        const matchesSearch = !search ||
          (user.email ?? "").toLowerCase().includes(search) ||
          (typeof user.user_metadata?.full_name === "string" && user.user_metadata.full_name.toLowerCase().includes(search)) ||
          (typeof user.user_metadata?.name === "string" && user.user_metadata.name.toLowerCase().includes(search));
        const matchesFilter = accountFilter === "all" ||
          (accountFilter === "active" && !(access?.blocked ?? false)) ||
          (accountFilter === "blocked" && (access?.blocked ?? false)) ||
          (accountFilter === "unconfirmed" && !user.email_confirmed_at) ||
          (accountFilter === "pro" && Boolean(access?.pro_until && Date.parse(access.pro_until) > Date.now())) ||
          (accountFilter === "admin" && user.app_metadata?.role === "admin");
        return matchesSearch && matchesFilter;
      });
      if (sortBy === "created-asc") {
        matchingUsers.sort((left, right) => Date.parse(left.created_at) - Date.parse(right.created_at));
      } else if (sortBy === "last-sign-in-desc") {
        matchingUsers.sort((left, right) => {
          const leftDate = left.last_sign_in_at ? Date.parse(left.last_sign_in_at) : Number.NEGATIVE_INFINITY;
          const rightDate = right.last_sign_in_at ? Date.parse(right.last_sign_in_at) : Number.NEGATIVE_INFINITY;
          return rightDate - leftDate;
        });
      } else if (sortBy === "email-asc") {
        matchingUsers.sort((left, right) => (left.email ?? "").localeCompare(right.email ?? "", "de"));
      }
      userTotal = matchingUsers.length;
      users = matchingUsers.slice((page - 1) * perPage, page * perPage);
    } else {
      const { data, error } = await supabase.auth.admin.listUsers({ page, perPage });
      if (error) {
        console.error("Could not list accounts", error.message);
        return respond({ error: "Accounts could not be loaded" }, 502);
      }
      users = data.users;
      userTotal = data.total ?? users.length;
    }

    if (!accessRows) {
      const userIds = users.map((user) => user.id);
      const { data, error: accessError } = await supabase
        .from("app_user_access")
        .select("user_id, blocked, pro_until")
        .in("user_id", userIds);
      if (accessError) {
        console.error("Could not load account access", accessError.message);
        return respond({ error: "Account access could not be loaded" }, 502);
      }
      accessRows = data ?? [];
    }
    const accessByUser = new Map(accessRows.map((access) => [access.user_id, access]));

    return respond({
      users: users.map((user) => ({
        id: user.id,
        email: user.email ?? "",
        name: typeof user.user_metadata?.full_name === "string"
          ? user.user_metadata.full_name.trim()
          : typeof user.user_metadata?.name === "string" ? user.user_metadata.name.trim() : "",
        createdAt: user.created_at,
        lastSignInAt: user.last_sign_in_at,
        emailConfirmedAt: user.email_confirmed_at,
        blocked: accessByUser.get(user.id)?.blocked ?? false,
        proUntil: accessByUser.get(user.id)?.pro_until ?? null,
      })),
      page,
      perPage,
      total: userTotal,
    });
  }

  if (payload.action === "get-user-profile") {
    if (typeof payload.userId !== "string" || !/^[0-9a-f-]{36}$/i.test(payload.userId)) {
      return respond({ error: "A valid account ID is required" }, 400);
    }
    const { data: account, error: accountError } = await supabase.auth.admin.getUserById(payload.userId);
    if (accountError) {
      console.error("Could not load account profile", accountError.message);
      return respond({ error: "Account profile could not be loaded" }, 502);
    }
    if (!account.user) return respond({ error: "Account not found" }, 404);
    const user = account.user;
    const [accessResult, demoAccessResult, opensResult, ticketsResult, notesResult, preferenceResult, invoiceCustomersResult] =
      await Promise.all([
        supabase.from("app_user_access").select("blocked, pro_until, updated_at").eq("user_id", user.id).maybeSingle(),
        supabase.from("demo_pro_entitlements")
          .select("activated_at, expires_at, confirmation_sent_at, confirmation_error")
          .eq("user_id", user.id).maybeSingle(),
        supabase.from("app_open_events").select("opened_at", { count: "exact" }).eq("user_id", user.id)
          .order("opened_at", { ascending: false }).limit(30),
        supabase.from("support_threads")
          .select("id, subject, support_category, support_priority, status, created_at, updated_at, claimed_by, claimed_at")
          .eq("user_id", user.id).order("updated_at", { ascending: false }).limit(100),
        supabase.from("admin_private_notes")
          .select("id, label, body, created_at, updated_at, created_by, updated_by")
          .eq("user_id", user.id).is("thread_id", null).order("created_at", { ascending: false }),
        supabase.from("email_update_preferences").select("subscribed, subscribed_at")
          .eq("user_id", user.id).maybeSingle(),
        user.email
          ? supabase.from("invoice_customers").select("id, name, email")
            .ilike("email", user.email.replace(/[\\%_]/g, "\\$&"))
          : Promise.resolve({ data: [], error: null }),
      ]);
    const queryErrors = [
      accessResult.error,
      demoAccessResult.error,
      opensResult.error,
      ticketsResult.error,
      notesResult.error,
      preferenceResult.error,
      invoiceCustomersResult.error,
    ].filter(Boolean);
    if (queryErrors.length) {
      console.error("Could not load all account profile details", queryErrors.map((error) => error?.message));
      return respond({ error: "Account details could not be loaded" }, 502);
    }

    const tickets = ticketsResult.data ?? [];
    const ticketIds = tickets.map((ticket) => ticket.id);
    let messages: {
      id: string;
      thread_id: string;
      sender_id: string | null;
      sender_is_admin: boolean;
      body: string;
      created_at: string;
    }[] = [];
    let ticketNotes = [];
    if (ticketIds.length) {
      const [messagesResult, ticketNotesResult] = await Promise.all([
        supabase.from("support_messages")
          .select("id, thread_id, sender_id, sender_is_admin, body, created_at")
          .in("thread_id", ticketIds).order("created_at", { ascending: true }),
        supabase.from("admin_private_notes").select("id, thread_id, label, body, created_at, updated_at, created_by, updated_by")
          .in("thread_id", ticketIds).is("user_id", null).order("created_at", { ascending: false }),
      ]);
      if (messagesResult.error || ticketNotesResult.error) {
        console.error("Could not load account support history", messagesResult.error?.message ?? ticketNotesResult.error?.message);
        return respond({ error: "Account support history could not be loaded" }, 502);
      }
      messages = messagesResult.data ?? [];
      ticketNotes = ticketNotesResult.data ?? [];
    }

    const invoiceCustomerIds = (invoiceCustomersResult.data ?? []).map((customer) => customer.id);
    let invoices = [];
    if (invoiceCustomerIds.length) {
      const { data, error } = await supabase.from("invoice_records")
        .select("id, invoice_number, invoice_date, total_cents, paid_at")
        .in("customer_id", invoiceCustomerIds).order("created_at", { ascending: false }).limit(100);
      if (error) {
        console.error("Could not load account invoices", error.message);
        return respond({ error: "Account invoices could not be loaded" }, 502);
      }
      invoices = data ?? [];
    }

    return respond({
      profile: {
        id: user.id,
        email: user.email ?? "",
        name: user.user_metadata?.full_name ?? user.user_metadata?.name ?? "",
        createdAt: user.created_at,
        lastSignInAt: user.last_sign_in_at,
        emailConfirmedAt: user.email_confirmed_at,
        isAdmin: user.app_metadata?.role === "admin",
        blocked: accessResult.data?.blocked ?? false,
        adminProUntil: accessResult.data?.pro_until ?? null,
        demoProActivatedAt: demoAccessResult.data?.activated_at ?? null,
        demoProUntil: demoAccessResult.data?.expires_at ?? null,
        demoProConfirmationSentAt: demoAccessResult.data?.confirmation_sent_at ?? null,
        demoProConfirmationError: demoAccessResult.data?.confirmation_error ?? null,
        accessUpdatedAt: accessResult.data?.updated_at ?? null,
        emailUpdatesSubscribed: preferenceResult.data?.subscribed ?? false,
        emailUpdatesSubscribedAt: preferenceResult.data?.subscribed_at ?? null,
        appOpenCount: opensResult.count ?? 0,
        recentAppOpens: opensResult.data ?? [],
        privateNotes: notesResult.data ?? [],
        tickets: tickets.map((ticket) => ({
          ...ticket,
          categoryLabel: supportCategoryLabel(ticket.support_category),
          priorityLabel: supportPriorityLabel(ticket.support_priority),
          messages: messages.filter((message) => message.thread_id === ticket.id),
          internalNotes: ticketNotes.filter((note) => note.thread_id === ticket.id),
        })),
        invoices,
        invoicesMatchedByEmail: Boolean(user.email && invoiceCustomersResult.data?.length),
      },
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
    const skipEmailConfirmation = payload.skipEmailConfirmation === true;
    const rawPassword = typeof payload.password === "string" ? payload.password.trim() : "";

    if (skipEmailConfirmation && rawPassword.length > 0 && (rawPassword.length < 8 || rawPassword.length > 128)) {
      return respond({ error: "Wenn du ein Initialpasswort setzt, muss es 8 bis 128 Zeichen lang sein." }, 400);
    }

    const generateRandomPassword = () => {
      const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%&*";
      const values = new Uint32Array(20);
      crypto.getRandomValues(values);
      return Array.from(values, (value) => alphabet[value % alphabet.length]).join("");
    };

    if (skipEmailConfirmation) {
      const password = rawPassword || generateRandomPassword();
      const { data: existingUsers, error: listError } = await supabase.auth.admin.listUsers({ page: 1, perPage: 1000 });
      if (listError) {
        console.error("Could not load accounts before direct user creation", listError.message);
        return respond({ error: "Die vorhandenen Konten konnten nicht geprüft werden." }, 502);
      }

      const existingUser = existingUsers.users.find((entry) => entry.email?.toLowerCase() === email.toLowerCase());

      if (existingUser) {
        const { error: updateError } = await supabase.auth.admin.updateUserById(existingUser.id, {
          password,
          app_metadata: {
            ...(existingUser.app_metadata ?? {}),
            ...(payload.admin === true ? { role: "admin" } : {}),
          },
        });
        if (updateError) {
          console.error("Could not update existing account without email confirmation", updateError.message);
          return respond({ error: "Ein vorhandenes Konto konnte nicht sofort aktiviert werden." }, 502);
        }
        return respond({
          user: { id: existingUser.id, email: existingUser.email },
          admin: payload.admin === true,
          password,
          directCreate: true,
        }, 200);
      }

      const { data, error } = await supabase.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { created_by_admin: true },
      });
      if (error) {
        console.error("Could not create account without email confirmation", error.message);
        return respond({ error: `Das Konto konnte ohne E-Mail-Bestätigung nicht angelegt werden: ${error.message}` }, 502);
      }

      if (payload.admin === true) {
        const { error: roleError } = await supabase.auth.admin.updateUserById(data.user.id, {
          app_metadata: { ...(data.user.app_metadata ?? {}), role: "admin" },
        });
        if (roleError) {
          console.error("Could not apply admin role on directly created account", roleError.message);
          await supabase.auth.admin.deleteUser(data.user.id);
          return respond({ error: "Admin-Konto konnte nicht erstellt werden." }, 502);
        }
      }

      return respond({
        user: { id: data.user.id, email: data.user.email },
        admin: payload.admin === true,
        password,
        directCreate: true,
      }, 201);
    }

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
    const priority = typeof payload.priority === "string" ? payload.priority : "all";
    const category = typeof payload.category === "string" ? payload.category : "all";
    const search = typeof payload.search === "string"
      ? payload.search.trim().replace(/[^\p{L}\p{N}@._+\- ]/gu, "").slice(0, 160)
      : "";
    if (!["open", "mine", "all", "closed"].includes(filter)) {
      return respond({ error: "Invalid support filter" }, 400);
    }
    if (!["all", "red", "yellow", "green"].includes(priority) ||
        !["all", "account", "payment", "bug", "feature", "other"].includes(category)) {
      return respond({ error: "Invalid support priority or category filter" }, 400);
    }
    let threadQuery = supabase
      .from("support_threads")
      .select("id, user_id, user_email, subject, support_category, support_priority, status, created_at, updated_at, claimed_by, claimed_at", { count: "exact" })
      .order("updated_at", { ascending: false })
      .limit(100);
    if (filter === "open") threadQuery = threadQuery.eq("status", "open");
    if (filter === "mine") threadQuery = threadQuery.eq("claimed_by", authData.user.id);
    if (filter === "closed") threadQuery = threadQuery.eq("status", "closed");
    if (priority !== "all") threadQuery = threadQuery.eq("support_priority", priority);
    if (category !== "all") threadQuery = threadQuery.eq("support_category", category);
    if (search) {
      const escapedSearch = search.replace(/[\\%_]/g, "\\$&");
      threadQuery = threadQuery.or(`subject.ilike.%${escapedSearch}%,user_email.ilike.%${escapedSearch}%`);
    }
    const { data: threads, error: threadsError, count: total } = await threadQuery;
    if (threadsError) {
      console.error("Could not list support threads", threadsError.message);
      return respond({ error: "Support inbox could not be loaded" }, 502);
    }
    const threadIds = (threads ?? []).map((thread) => thread.id);
    if (threadIds.length === 0) return respond({ threads: [], total: total ?? 0 });
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
    const { data: internalNotes, error: notesError } = await supabase
      .from("admin_private_notes")
      .select("id, thread_id, label, body, created_at, updated_at, created_by, updated_by")
      .in("thread_id", threadIds)
      .is("user_id", null)
      .order("created_at", { ascending: false });
    if (notesError) {
      console.error("Could not load internal support notes", notesError.message);
      return respond({ error: "Internal support notes could not be loaded" }, 502);
    }
    if (claimedUsers.some((user) => user.error)) {
      console.error("Could not load support ticket assignees", claimedUsers.filter((user) => user.error).map((user) => user.error));
      return respond({ error: "Support ticket assignees could not be loaded" }, 502);
    }
    const claimedEmailByUser = new Map(claimedUsers.map(({ id, email }) => [id, email]));
    return respond({
      total: total ?? 0,
      threads: (threads ?? []).map((thread) => ({
        ...thread,
        email: thread.user_email || "Keine E-Mail",
        claimedEmail: thread.claimed_by ? claimedEmailByUser.get(thread.claimed_by) ?? "Admin" : null,
        categoryLabel: supportCategoryLabel(thread.support_category),
        priorityLabel: supportPriorityLabel(thread.support_priority),
        priorityEmoji: supportPriorityEmoji(thread.support_priority),
        messages: (messages ?? []).filter((message) => message.thread_id === thread.id),
        internalNotes: (internalNotes ?? []).filter((note) => note.thread_id === thread.id),
      })),
    });
  }

  if ([
    "list-private-admin-notes",
    "save-private-admin-note",
    "delete-private-admin-note",
  ].includes(String(payload.action))) {
    const targetType = payload.targetType;
    const targetId = payload.targetId;
    if (!["user", "ticket"].includes(String(targetType)) ||
        typeof targetId !== "string" || !/^[0-9a-f-]{36}$/i.test(targetId)) {
      return respond({ error: "A valid person or ticket is required" }, 400);
    }
    const targetFilter = targetType === "user"
      ? { user_id: targetId, thread_id: null }
      : { user_id: null, thread_id: targetId };
    const targetColumn = targetType === "user" ? "user_id" : "thread_id";
    const otherColumn = targetType === "user" ? "thread_id" : "user_id";
    const noteSelection = "id, user_id, thread_id, label, body, created_at, updated_at, created_by, updated_by";

    if (payload.action === "list-private-admin-notes") {
      let query = supabase.from("admin_private_notes").select(noteSelection)
        .eq(targetColumn, targetId).order("created_at", { ascending: false });
      query = query.is(otherColumn, null);
      const { data, error } = await query;
      if (error) {
        console.error("Could not list internal notes", error.message);
        return respond({ error: "Internal notes could not be loaded" }, 502);
      }
      return respond({ notes: data ?? [] });
    }

    if (payload.action === "save-private-admin-note") {
      const label = invoiceText(payload.label ?? "Interne Notiz", 80);
      const body = typeof payload.body === "string" ? payload.body.trim() : "";
      if (!label || body.length < 1 || body.length > 4000) {
        return respond({ error: "Enter a note label and text (up to 4,000 characters)" }, 400);
      }
      const values = {
        ...targetFilter,
        label,
        body,
        updated_at: new Date().toISOString(),
        updated_by: authData.user.id,
      };
      const noteId = payload.noteId;
      if (noteId !== undefined &&
          (typeof noteId !== "string" || !/^[0-9a-f-]{36}$/i.test(noteId))) {
        return respond({ error: "Invalid internal note ID" }, 400);
      }
      const result = typeof noteId === "string"
        ? await supabase.from("admin_private_notes").update(values)
          .eq("id", noteId).eq(targetColumn, targetId).is(otherColumn, null)
          .select(noteSelection).maybeSingle()
        : await supabase.from("admin_private_notes").insert({
          ...values,
          created_by: authData.user.id,
        }).select(noteSelection).maybeSingle();
      if (result.error) {
        console.error("Could not save internal note", result.error.message);
        return respond({ error: "Internal note could not be saved" }, 502);
      }
      if (!result.data) return respond({ error: "Internal note or target could not be found" }, 404);
      return respond({ note: result.data }, typeof noteId === "string" ? 200 : 201);
    }

    if (typeof payload.noteId !== "string" || !/^[0-9a-f-]{36}$/i.test(payload.noteId)) {
      return respond({ error: "A valid internal note ID is required" }, 400);
    }
    const { data, error } = await supabase.from("admin_private_notes").delete()
      .eq("id", payload.noteId).eq(targetColumn, targetId).is(otherColumn, null)
      .select("id").maybeSingle();
    if (error) {
      console.error("Could not delete internal note", error.message);
      return respond({ error: "Internal note could not be deleted" }, 502);
    }
    if (!data) return respond({ error: "Internal note could not be found" }, 404);
    return respond({ deleted: true });
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

  if (payload.action === "invoice-settings") {
    const { data, error } = await supabase
      .from("invoice_settings")
      .select("*")
      .eq("id", 1)
      .single();
    if (error) {
      console.error("Could not load invoice settings", error.message);
      return respond({ error: "Invoice settings could not be loaded" }, 502);
    }
    return respond({ settings: data });
  }

  if (payload.action === "save-invoice-settings") {
    const sellerName = invoiceText(payload.sellerName, 160);
    const street = invoiceText(payload.street, 200);
    const postalCode = invoiceText(payload.postalCode, 24);
    const city = invoiceText(payload.city, 120);
    const country = invoiceText(payload.country, 80);
    const email = invoiceText(payload.email, 254);
    const taxIdentifier = invoiceText(payload.taxIdentifier, 80);
    const phone = invoiceText(payload.phone, 80, false);
    const bankAccountHolder = invoiceText(payload.bankAccountHolder ?? "", 160, false);
    const bankIban = invoiceText(payload.bankIban ?? "", 34, false);
    const bankBic = invoiceText(payload.bankBic ?? "", 11, false);
    const prefix = invoiceText(payload.invoicePrefix, 8);
    const logo = payload.invoiceLogoDataUrl ?? null;
    if (!sellerName || !street || !postalCode || !city || !country || !email ||
        !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !taxIdentifier ||
        phone === null || bankAccountHolder === null || bankIban === null || bankBic === null ||
        !prefix || !/^[A-Z0-9]{2,8}$/.test(prefix)) {
      return respond({ error: "Complete the seller details with a valid email and a 2–8 character invoice prefix" }, 400);
    }
    const normalizedIban = bankIban.replace(/\s/g, "").toUpperCase();
    const normalizedBic = bankBic.toUpperCase();
    if ((normalizedIban && !isValidIban(normalizedIban)) ||
        (normalizedBic && !/^[A-Z0-9]{8}(?:[A-Z0-9]{3})?$/.test(normalizedBic)) ||
        (!!normalizedBic && !normalizedIban)) {
      return respond({ error: "Check the IBAN and BIC. A BIC can only be saved together with a valid IBAN." }, 400);
    }
    if (logo !== null && (typeof logo !== "string" || logo.length > 700_000 ||
        !/^data:image\/(?:png|jpeg|webp);base64,[A-Za-z0-9+/]+={0,2}$/.test(logo))) {
      return respond({ error: "The invoice logo must be a PNG, JPG or WebP image under 512 KB" }, 400);
    }

    const { data, error } = await supabase
      .from("invoice_settings")
      .update({
        seller_name: sellerName,
        street,
        postal_code: postalCode,
        city,
        country,
        email,
        tax_identifier: taxIdentifier,
        phone,
        bank_account_holder: bankAccountHolder,
        bank_iban: normalizedIban,
        bank_bic: normalizedBic,
        invoice_prefix: prefix,
        invoice_logo_data_url: logo,
        updated_at: new Date().toISOString(),
        updated_by: authData.user.id,
      })
      .eq("id", 1)
      .select("*")
      .single();
    if (error) {
      console.error("Could not save invoice settings", error.message);
      return respond({ error: "Invoice settings could not be saved" }, 502);
    }
    return respond({ settings: data });
  }

  if (payload.action === "list-invoice-customers") {
    const page = Number(payload.page ?? 1);
    const perPage = Number(payload.perPage ?? 25);
    const search = invoiceText(payload.search ?? "", 160, false);
    const tier = payload.tier ?? "all";
    if (!Number.isInteger(page) || page < 1 || page > 1_000_000 ||
        !Number.isInteger(perPage) || perPage < 1 || perPage > 100 || search === null ||
        !["all", "pro", "standard"].includes(String(tier))) {
      return respond({ error: "Invalid customer search or pagination values" }, 400);
    }

    let customerQuery = supabase
      .from("invoice_customers")
      .select("id, name, email, street, postal_code, city, country, pro_customer, created_at", { count: "exact" })
      .order("name", { ascending: true })
      .range((page - 1) * perPage, page * perPage - 1);
    if (search) customerQuery = customerQuery.ilike("name", `%${search.replace(/[\\%_]/g, "\\$&")}%`);
    if (tier === "pro") customerQuery = customerQuery.eq("pro_customer", true);
    if (tier === "standard") customerQuery = customerQuery.eq("pro_customer", false);
    const { data, count, error } = await customerQuery;
    if (error) {
      console.error("Could not list invoice customers", error.message);
      return respond({ error: "Invoice customers could not be loaded" }, 502);
    }
    return respond({ customers: data ?? [], page, perPage, total: count ?? 0 });
  }

  if (payload.action === "list-invoice-customer-options") {
    const { data, error } = await supabase
      .from("invoice_customers")
      .select("id, name, email, street, postal_code, city, country, pro_customer")
      .order("name", { ascending: true })
      .limit(1000);
    if (error) {
      console.error("Could not list invoice customer options", error.message);
      return respond({ error: "Invoice customer options could not be loaded" }, 502);
    }
    return respond({ customers: data ?? [] });
  }

  if (payload.action === "save-invoice-customer" || payload.action === "update-invoice-customer") {
    const name = invoiceText(payload.name, 160);
    const email = invoiceText(payload.email, 254, false);
    const street = invoiceText(payload.street, 200);
    const postalCode = invoiceText(payload.postalCode, 24);
    const city = invoiceText(payload.city, 120);
    const country = invoiceText(payload.country, 80);
    const proCustomer = payload.proCustomer;
    if (!name || email === null || (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) ||
        !street || !postalCode || !city || !country || typeof proCustomer !== "boolean") {
      return respond({ error: "Enter a customer name, address and valid email address" }, 400);
    }

    const customerValues = {
      name,
      email,
      street,
      postal_code: postalCode,
      city,
      country,
      pro_customer: proCustomer,
      updated_at: new Date().toISOString(),
    };
    let customerId: string | null = null;
    if (payload.action === "update-invoice-customer") {
      if (typeof payload.customerId !== "string" || !/^[0-9a-f-]{36}$/i.test(payload.customerId)) {
        return respond({ error: "Invalid invoice customer" }, 400);
      }
      customerId = payload.customerId;
    }
    const result = customerId
      ? await supabase
        .from("invoice_customers")
        .update(customerValues)
        .eq("id", customerId)
        .select("id, name, email, street, postal_code, city, country, pro_customer, created_at")
        .maybeSingle()
      : await supabase
        .from("invoice_customers")
        .insert(customerValues)
        .select("id, name, email, street, postal_code, city, country, pro_customer, created_at")
        .maybeSingle();
    const { data, error } = result;
    if (error) {
      console.error("Could not save invoice customer", error.message);
      return respond({ error: "Invoice customer could not be saved" }, 502);
    }
    if (!data) return respond({ error: "Invoice customer could not be found" }, 404);
    return respond({ customer: data }, payload.action === "save-invoice-customer" ? 201 : 200);
  }

  if (payload.action === "list-private-sale-customers") {
    const { data, error } = await supabase
      .from("private_sale_customers")
      .select("id, name, email, created_at")
      .order("name", { ascending: true })
      .limit(500);
    if (error) {
      console.error("Could not list private-sale customers", error.message);
      return respond({ error: "Private-sale customers could not be loaded" }, 502);
    }
    return respond({ customers: data ?? [] });
  }

  if (payload.action === "private-sale-settings") {
    const { data, error } = await supabase
      .from("private_sale_settings")
      .select("seller_name, seller_email")
      .eq("id", 1)
      .single();
    if (error) {
      console.error("Could not load private-sale seller details", error.message);
      return respond({ error: "Private-sale seller details could not be loaded" }, 502);
    }
    return respond({ settings: data });
  }

  if (payload.action === "save-private-sale-settings") {
    const sellerName = invoiceText(payload.sellerName, 160);
    const sellerEmail = invoiceText(payload.sellerEmail ?? "", 254, false);
    if (!sellerName || sellerEmail === null ||
        (sellerEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(sellerEmail))) {
      return respond({ error: "Enter your name and, if provided, a valid email address" }, 400);
    }
    const { data, error } = await supabase
      .from("private_sale_settings")
      .update({
        seller_name: sellerName,
        seller_email: sellerEmail,
        updated_at: new Date().toISOString(),
        updated_by: authData.user.id,
      })
      .eq("id", 1)
      .select("seller_name, seller_email")
      .single();
    if (error) {
      console.error("Could not save private-sale seller details", error.message);
      return respond({ error: "Private-sale seller details could not be saved" }, 502);
    }
    return respond({ settings: data });
  }

  if (payload.action === "save-private-sale-customer") {
    const name = invoiceText(payload.name, 160);
    const email = invoiceText(payload.email ?? "", 254, false);
    if (!name || email === null || (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))) {
      return respond({ error: "Enter a customer name and a valid email address" }, 400);
    }
    const { data, error } = await supabase
      .from("private_sale_customers")
      .insert({ name, email })
      .select("id, name, email, created_at")
      .single();
    if (error) {
      console.error("Could not save private-sale customer", error.message);
      return respond({ error: "Private-sale customer could not be saved" }, 502);
    }
    return respond({ customer: data }, 201);
  }

  if (payload.action === "list-private-sale-receipts") {
    const { data, error } = await supabase
      .from("private_sale_receipts")
      .select("id, receipt_number, receipt_date, seller_snapshot, customer_snapshot, line_items, total_cents, note, created_at")
      .order("created_at", { ascending: false })
      .limit(200);
    if (error) {
      console.error("Could not list private-sale receipts", error.message);
      return respond({ error: "Private-sale receipts could not be loaded" }, 502);
    }
    return respond({ receipts: data ?? [] });
  }

  if (payload.action === "create-private-sale-receipt") {
    const customerId = payload.customerId;
    const date = invoiceDate(payload.receiptDate);
    const note = invoiceText(payload.note ?? "", 2000, false);
    if (typeof customerId !== "string" || !/^[0-9a-f-]{36}$/i.test(customerId) ||
        !date || note === null || !Array.isArray(payload.items) ||
        payload.items.length < 1 || payload.items.length > 50) {
      return respond({ error: "Check the customer, date and private-sale items" }, 400);
    }
    const { data: seller, error: sellerError } = await supabase
      .from("private_sale_settings")
      .select("seller_name, seller_email")
      .eq("id", 1)
      .single();
    if (sellerError || !seller?.seller_name) {
      if (sellerError) console.error("Could not load private-sale seller details", sellerError.message);
      return respond({ error: "Save your private-sale seller name before creating a receipt" }, 400);
    }
    const { data: customer, error: customerError } = await supabase
      .from("private_sale_customers")
      .select("id, name, email")
      .eq("id", customerId)
      .maybeSingle();
    if (customerError) {
      console.error("Could not load private-sale customer", customerError.message);
      return respond({ error: "Private-sale customer could not be loaded" }, 502);
    }
    if (!customer) return respond({ error: "Private-sale customer could not be found" }, 404);

    const lineItems: {
      description: string;
      quantity: string;
      unit_price_cents: number;
      line_total_cents: number;
    }[] = [];
    let totalCents = 0;
    for (const item of payload.items) {
      if (typeof item !== "object" || item === null) {
        return respond({ error: "Every private-sale item needs a description, quantity and price" }, 400);
      }
      const description = invoiceText(item.description, 200);
      const quantity = invoiceQuantityMilli(item.quantity);
      const unitPriceCents = invoiceAmountCents(item.unitPrice);
      if (!description || !quantity || unitPriceCents === null || unitPriceCents < 1) {
        return respond({ error: "Check each private-sale item's description, quantity and price" }, 400);
      }
      const lineTotalCents = Math.round(unitPriceCents * quantity.milli / 1000);
      totalCents += lineTotalCents;
      if (totalCents > 10_000_000_000) {
        return respond({ error: "The private-sale total exceeds the maximum supported amount" }, 400);
      }
      lineItems.push({
        description,
        quantity: quantity.quantity,
        unit_price_cents: unitPriceCents,
        line_total_cents: lineTotalCents,
      });
    }
    if (totalCents < 1) return respond({ error: "The private-sale total must be greater than zero" }, 400);

    const { data: receipt, error } = await supabase.rpc("admin_create_private_sale_receipt", {
      p_customer_id: customer.id,
      p_receipt_date: date,
      p_seller_snapshot: { name: seller.seller_name, email: seller.seller_email },
      p_customer_snapshot: { name: customer.name, email: customer.email },
      p_line_items: lineItems,
      p_total_cents: totalCents,
      p_note: note,
      p_created_by: authData.user.id,
    });
    if (error || !receipt) {
      console.error("Could not create private-sale receipt", error?.message ?? "No receipt returned");
      return respond({ error: "Private-sale receipt could not be created" }, 502);
    }
    return respond({ receipt }, 201);
  }

  if (payload.action === "list-invoice-products") {
    const { data, error } = await supabase
      .from("invoice_products")
      .select("id, name, unit_price_cents, active, created_at, updated_at")
      .order("name", { ascending: true })
      .limit(500);
    if (error) {
      console.error("Could not list invoice products", error.message);
      return respond({ error: "Invoice products could not be loaded" }, 502);
    }
    return respond({ products: data ?? [] });
  }

  if (payload.action === "save-invoice-product") {
    const name = invoiceText(payload.name, 200);
    const unitPriceCents = invoiceAmountCents(payload.unitPrice);
    if (!name || unitPriceCents === null || unitPriceCents < 1) {
      return respond({ error: "Enter a product name and a unit price greater than zero" }, 400);
    }

    const productValues = {
      name,
      unit_price_cents: unitPriceCents,
      active: true,
      updated_at: new Date().toISOString(),
    };
    const productId = payload.productId;
    if (productId !== undefined &&
        (typeof productId !== "string" || !/^[0-9a-f-]{36}$/i.test(productId))) {
      return respond({ error: "Invalid invoice product" }, 400);
    }
    const result = typeof productId === "string"
      ? await supabase
        .from("invoice_products")
        .update(productValues)
        .eq("id", productId)
        .select("id, name, unit_price_cents, active, created_at, updated_at")
        .maybeSingle()
      : await supabase
        .from("invoice_products")
        .insert(productValues)
        .select("id, name, unit_price_cents, active, created_at, updated_at")
        .maybeSingle();
    if (result.error) {
      console.error("Could not save invoice product", result.error.message);
      return respond({ error: "Invoice product could not be saved" }, 502);
    }
    if (!result.data) return respond({ error: "Invoice product could not be found" }, 404);
    return respond({ product: result.data }, typeof productId === "string" ? 200 : 201);
  }

  if (payload.action === "set-invoice-product-active") {
    if (typeof payload.productId !== "string" || !/^[0-9a-f-]{36}$/i.test(payload.productId) ||
        typeof payload.active !== "boolean") {
      return respond({ error: "Invalid invoice product status" }, 400);
    }
    const { data, error } = await supabase
      .from("invoice_products")
      .update({ active: payload.active, updated_at: new Date().toISOString() })
      .eq("id", payload.productId)
      .select("id, name, active")
      .maybeSingle();
    if (error) {
      console.error("Could not update invoice product status", error.message);
      return respond({ error: "Invoice product status could not be updated" }, 502);
    }
    if (!data) return respond({ error: "Invoice product could not be found" }, 404);
    return respond({ product: data });
  }

  if (payload.action === "list-invoices") {
    const page = Number(payload.page ?? 1);
    const perPage = Number(payload.perPage ?? 25);
    const search = invoiceText(payload.search ?? "", 160, false);
    const status = payload.status ?? "all";
    const from = payload.from ? invoiceDate(payload.from) : null;
    const to = payload.to ? invoiceDate(payload.to) : null;
    if (!Number.isInteger(page) || page < 1 || page > 1_000_000 ||
        !Number.isInteger(perPage) || perPage < 1 || perPage > 100 || search === null ||
        !["all", "open", "paid"].includes(String(status)) ||
        (payload.from && !from) || (payload.to && !to) || (from && to && from > to)) {
      return respond({ error: "Check the invoice search, status, date range and pagination values" }, 400);
    }
    const { data, error } = await supabase.rpc("admin_list_invoices", {
      p_search: search,
      p_status: status,
      p_from: from,
      p_to: to,
      p_page: page,
      p_per_page: perPage,
    });
    if (error) {
      console.error("Could not list invoices", error.message);
      return respond({ error: "Invoices could not be loaded" }, 502);
    }
    return respond({ ...data, page, perPage });
  }

  if (payload.action === "create-invoice") {
    const customerId = payload.customerId;
    const date = invoiceDate(payload.invoiceDate);
    const serviceDate = invoiceDate(payload.serviceDate);
    const dueDate = invoiceDate(payload.dueDate);
    const note = invoiceText(payload.note, 2000, false);
    if (typeof customerId !== "string" || !/^[0-9a-f-]{36}$/i.test(customerId) ||
        !date || !serviceDate || !dueDate || dueDate < date || note === null ||
        !Array.isArray(payload.items) || payload.items.length < 1 || payload.items.length > 50) {
      return respond({ error: "Check the customer, dates and invoice items. A due date cannot be before the invoice date." }, 400);
    }

    const { data: customer, error: customerError } = await supabase
      .from("invoice_customers")
      .select("id, name, email, street, postal_code, city, country")
      .eq("id", customerId)
      .single();
    if (customerError || !customer) {
      if (customerError) console.error("Could not load invoice customer", customerError.message);
      return respond({ error: "Invoice customer could not be found" }, 404);
    }
    const { data: settings, error: settingsError } = await supabase
      .from("invoice_settings")
      .select("*")
      .eq("id", 1)
      .single();
    if (settingsError || !settings) {
      if (settingsError) console.error("Could not load seller details for invoice", settingsError.message);
      return respond({ error: "Save the seller details before creating an invoice" }, 400);
    }
    if (!settings.seller_name || !settings.street || !settings.postal_code || !settings.city ||
        !settings.country || !settings.email || !settings.tax_identifier) {
      return respond({ error: "Complete and save all required seller details before creating an invoice" }, 400);
    }

    const lineItems: {
      description: string;
      quantity: string;
      unit_price_cents: number;
      line_total_cents: number;
    }[] = [];
    let totalCents = 0;
    for (const item of payload.items) {
      if (typeof item !== "object" || item === null) {
        return respond({ error: "Every invoice item needs a description, quantity and unit price" }, 400);
      }
      const description = invoiceText(item.description, 200);
      const quantity = invoiceQuantityMilli(item.quantity);
      const unitPriceCents = invoiceAmountCents(item.unitPrice);
      if (!description || !quantity || unitPriceCents === null) {
        return respond({ error: "Check each invoice item's description, quantity and unit price" }, 400);
      }
      const lineTotalCents = Math.round(unitPriceCents * quantity.milli / 1000);
      totalCents += lineTotalCents;
      if (totalCents > 10_000_000_000) {
        return respond({ error: "The invoice total exceeds the maximum supported amount" }, 400);
      }
      lineItems.push({
        description,
        quantity: quantity.quantity,
        unit_price_cents: unitPriceCents,
        line_total_cents: lineTotalCents,
      });
    }
    if (totalCents < 1) {
      return respond({ error: "The invoice total must be greater than zero" }, 400);
    }

    const sellerSnapshot = {
      name: settings.seller_name,
      street: settings.street,
      postalCode: settings.postal_code,
      city: settings.city,
      country: settings.country,
      email: settings.email,
      taxIdentifier: settings.tax_identifier,
      phone: settings.phone,
      bankAccountHolder: settings.bank_account_holder,
      bankIban: settings.bank_iban,
      bankBic: settings.bank_bic,
      logoDataUrl: settings.invoice_logo_data_url,
      taxNote: "Gemäß § 19 UStG wird keine Umsatzsteuer berechnet.",
    };
    const customerSnapshot = {
      name: customer.name,
      email: customer.email,
      street: customer.street,
      postalCode: customer.postal_code,
      city: customer.city,
      country: customer.country,
    };
    const { data: invoice, error } = await supabase.rpc("admin_create_invoice", {
      p_prefix: settings.invoice_prefix,
      p_customer_id: customer.id,
      p_invoice_date: date,
      p_service_date: serviceDate,
      p_due_date: dueDate,
      p_seller_snapshot: sellerSnapshot,
      p_customer_snapshot: customerSnapshot,
      p_line_items: lineItems,
      p_total_cents: totalCents,
      p_note: note,
      p_created_by: authData.user.id,
    });
    if (error || !invoice) {
      console.error("Could not create invoice", error?.message ?? "No invoice returned");
      return respond({ error: "Invoice could not be created" }, 502);
    }
    return respond({ invoice }, 201);
  }

  if (payload.action === "set-invoice-paid") {
    if (typeof payload.invoiceId !== "string" || !/^[0-9a-f-]{36}$/i.test(payload.invoiceId) ||
        typeof payload.paid !== "boolean") {
      return respond({ error: "Invalid invoice payment status" }, 400);
    }
    const { data, error } = await supabase
      .from("invoice_records")
      .update({ paid_at: payload.paid ? new Date().toISOString() : null })
      .eq("id", payload.invoiceId)
      .select("id, paid_at")
      .maybeSingle();
    if (error) {
      console.error("Could not update invoice payment status", error.message);
      return respond({ error: "Invoice payment status could not be updated" }, 502);
    }
    if (!data) return respond({ error: "Invoice could not be found" }, 404);
    return respond({ invoice: data });
  }

  if (payload.action === "get-settings") {
    const { data, error } = await supabase
      .from("app_settings")
      .select("maintenance_enabled, maintenance_message, announcement_enabled, announcement_title, announcement_message, website_maintenance_enabled, website_maintenance_message, website_announcement_enabled, website_announcement_title, website_announcement_message, pro_offer_title, pro_offer_message, pro_monthly_offer_message, pro_yearly_offer_message, updated_at")
      .eq("id", 1)
      .single();

    if (error) {
      console.error("Could not load app settings", error.message);
      return respond({ error: "App settings could not be loaded" }, 502);
    }
    return respond({ settings: data });
  }

  if (payload.action === "update-app-announcement") {
    const target = payload.target ?? "app";
    if (target !== "app" && target !== "website" && target !== "both") {
      return respond({ error: "Choose the app, the website, or both as the announcement target" }, 400);
    }
    if (typeof payload.enabled !== "boolean" ||
        typeof payload.title !== "string" || payload.title.trim().length > 80 ||
        typeof payload.message !== "string" || payload.message.trim().length > 500) {
      return respond({ error: "The announcement must fit within the title and message character limits" }, 400);
    }
    const title = payload.title.trim();
    const message = payload.message.trim();
    if (payload.enabled && (!title || !message)) {
      return respond({ error: "Enter both a title and a message before enabling the announcement" }, 400);
    }
    const update: Record<string, boolean | string> = {
      updated_at: new Date().toISOString(),
      updated_by: authData.user.id,
    };
    if (target === "app" || target === "both") {
      update.announcement_enabled = payload.enabled;
      update.announcement_title = title;
      update.announcement_message = message;
    }
    if (target === "website" || target === "both") {
      update.website_announcement_enabled = payload.enabled;
      update.website_announcement_title = title;
      update.website_announcement_message = message;
    }
    const { data, error } = await supabase
      .from("app_settings")
      .update(update)
      .eq("id", 1)
      .select("announcement_enabled, announcement_title, announcement_message, website_announcement_enabled, website_announcement_title, website_announcement_message, updated_at")
      .single();
    if (error) {
      console.error("Could not update announcement", error.message);
      return respond({ error: "Announcement could not be saved" }, 502);
    }
    return respond({ settings: data });
  }

  if (payload.action === "update-site-maintenance") {
    if (typeof payload.enabled !== "boolean" || typeof payload.message !== "string") {
      return respond({ error: "Invalid website maintenance settings" }, 400);
    }
    const message = payload.message.trim();
    if (message.length < 1 || message.length > 500) {
      return respond({ error: "The website maintenance message must be 1–500 characters" }, 400);
    }
    const { data, error } = await supabase
      .from("app_settings")
      .update({
        website_maintenance_enabled: payload.enabled,
        website_maintenance_message: message,
        updated_at: new Date().toISOString(),
        updated_by: authData.user.id,
      })
      .eq("id", 1)
      .select("website_maintenance_enabled, website_maintenance_message, updated_at")
      .single();
    if (error) {
      console.error("Could not update website maintenance settings", error.message);
      return respond({ error: "Website maintenance settings could not be saved" }, 502);
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

    const { data: currentSettings, error: currentSettingsError } = await supabase
      .from("app_settings")
      .select("maintenance_enabled")
      .eq("id", 1)
      .single();
    if (currentSettingsError) {
      console.error("Could not load previous maintenance settings", currentSettingsError.message);
      return respond({ error: "Maintenance settings could not be loaded" }, 502);
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

    let maintenanceEmail = {
      changed: currentSettings.maintenance_enabled !== data.maintenance_enabled,
      adminNotified: false,
      usersNotified: 0,
      usersSkipped: 0,
      error: "",
    };
    if (maintenanceEmail.changed) {
      try {
        const { count, error: countError } = await supabase
          .from("email_update_preferences")
          .select("user_id", { count: "exact", head: true })
          .eq("subscribed", true);
        if (countError) throw new Error(`Could not count email subscribers: ${countError.message}`);

        const { data: preferences, error: preferencesError } = await supabase
          .from("email_update_preferences")
          .select("user_id")
          .eq("subscribed", true)
          .order("user_id", { ascending: true })
          .limit(99);
        if (preferencesError) throw new Error(`Could not load email subscribers: ${preferencesError.message}`);

        const subscriberResults = await Promise.all(
          (preferences ?? []).map(({ user_id }) => supabase.auth.admin.getUserById(user_id)),
        );
        const failedLookup = subscriberResults.find(({ error: lookupError }) => lookupError);
        if (failedLookup?.error) {
          throw new Error(`Could not load a subscriber account: ${failedLookup.error.message}`);
        }
        const recipients = [...new Set(subscriberResults.flatMap(({ data: userData }) =>
          userData.user?.email_confirmed_at && userData.user.email
            ? [userData.user.email]
            : []
        ))].filter((email) => email.toLowerCase() !== "wertweitoffiziell@gmail.com");
        const maintenanceSubject = data.maintenance_enabled
          ? "Wertweit wird gewartet"
          : "Wertweit ist wieder verfügbar";
        const maintenanceBody = data.maintenance_enabled
          ? `Wertweit wird gerade gewartet. Bitte versuche es später erneut.\n\n${data.maintenance_message}`
          : `Die Wartung ist beendet. Wertweit ist wieder verfügbar.\n\n${data.maintenance_message}`;
        const deliveryRecipients = recipients.length > 0
          ? recipients
          : ["wertweitoffiziell@gmail.com"];
        const delivery = await sendViaGmail(deliveryRecipients, maintenanceSubject, maintenanceBody);
        maintenanceEmail = {
          changed: true,
          adminNotified: delivery.sent > 0 && delivery.failed.length === 0,
          usersNotified: delivery.failed.length === 0 ? Math.min(delivery.sent, recipients.length) : 0,
          usersSkipped: Math.max(0, (count ?? 0) - recipients.length),
          error: delivery.failed.length > 0
            ? delivery.failed.map((failure) => `${failure.email}: ${failure.error}`).join("; ")
            : (count ?? 0) > 99
            ? `Only 99 opted-in users can receive this free Gmail batch; ${count! - 99} were not emailed.`
            : "",
        };
      } catch (emailError) {
        maintenanceEmail = {
          ...maintenanceEmail,
          error: emailError instanceof Error ? emailError.message : "Maintenance email could not be sent.",
        };
        console.error("Maintenance setting saved but notification email failed", maintenanceEmail.error);
      }
    }
    return respond({ settings: data, maintenanceEmail });
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
