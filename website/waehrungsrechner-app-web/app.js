import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const config = window.WERTWEIT_SUPABASE;
if (!config?.url || !config?.publishableKey || config.publishableKey.startsWith("REPLACE_")) {
  throw new Error("Wertweit Web benötigt website/supabase-config.js mit der öffentlichen Supabase-Konfiguration.");
}

const supabase = createClient(config.url, config.publishableKey);
const $ = (selector) => document.querySelector(selector);
const state = {
  page: "calculator",
  initialized: false,
  mode: "fees",
  currencies: {},
  rate: null,
  rateDate: "",
  isPro: false,
  notifications: [],
  supportThreads: [],
  historyDays: 7,
  phraseResult: "",
  maintenanceEnabled: false,
  maintenanceMessage: "",
  initializing: false,
  maintenanceTimer: null,
  appRefreshTimer: null,
};
const destinations = [
  { country: "Japan", flag: "🇯🇵", currency: "JPY", meal: 900, coffee: 500, transport: 1800, budget: "40–60 €", moderate: "80–130 €", comfort: "ab 150 €", tipping: "Trinkgeld ist in Japan normalerweise nicht üblich." },
  { country: "USA", flag: "🇺🇸", currency: "USD", meal: 16, coffee: 5, transport: 12, budget: "70–110 €", moderate: "140–230 €", comfort: "ab 280 €", tipping: "In Restaurants sind etwa 18–22 % üblich." },
  { country: "Vereinigtes Königreich", flag: "🇬🇧", currency: "GBP", meal: 13, coffee: 4, transport: 8, budget: "60–90 €", moderate: "120–190 €", comfort: "ab 240 €", tipping: "Service ist teils enthalten; sonst sind etwa 10–12,5 % üblich." },
  { country: "Schweiz", flag: "🇨🇭", currency: "CHF", meal: 24, coffee: 5, transport: 16, budget: "100–150 €", moderate: "190–300 €", comfort: "ab 380 €", tipping: "Trinkgeld ist freiwillig; Aufrunden ist verbreitet." },
  { country: "Polen", flag: "🇵🇱", currency: "PLN", meal: 38, coffee: 14, transport: 12, budget: "35–55 €", moderate: "70–115 €", comfort: "ab 145 €", tipping: "Bei gutem Service sind etwa 10 % üblich." },
  { country: "Thailand", flag: "🇹🇭", currency: "THB", meal: 90, coffee: 80, transport: 220, budget: "30–50 €", moderate: "65–110 €", comfort: "ab 140 €", tipping: "Trinkgeld ist nicht verpflichtend; kleine Beträge werden geschätzt." },
];

function setStatus(element, message, type = "") {
  element.textContent = message;
  element.className = `status ${type}`;
}

function authErrorMessage(error, operation) {
  const message = String(error?.message ?? "").toLowerCase();
  const code = String(error?.code ?? "").toLowerCase();
  if (/failed to fetch|network request failed|load failed/.test(message)) {
    return "Supabase ist gerade nicht erreichbar. Prüfe deine Internetverbindung und versuche es erneut.";
  }
  if (code.includes("email_not_confirmed") || message.includes("email not confirmed")) {
    return "Bitte bestätige zuerst deine E-Mail-Adresse mit dem zugesendeten Code.";
  }
  if (operation === "verify" &&
      (code.includes("otp_expired") || message.includes("expired") || message.includes("invalid token"))) {
    return "Der Code ist abgelaufen oder ungültig. Fordere einen neuen Bestätigungscode an.";
  }
  if (operation === "signin" &&
      (code.includes("invalid_credentials") || message.includes("invalid login credentials") || error?.status === 401)) {
    return "Anmeldung fehlgeschlagen. Prüfe E-Mail und Passwort und versuche es erneut.";
  }
  if (operation === "signup" &&
      (code.includes("user_already_exists") || message.includes("already registered"))) {
    return "Für diese E-Mail-Adresse besteht bereits ein Konto. Melde dich an oder setze dein Passwort zurück.";
  }
  if (error?.status === 429) {
    return "Zu viele Versuche. Warte kurz und versuche es danach erneut.";
  }
  return error?.message || "Die Anfrage ist fehlgeschlagen. Prüfe deine Eingaben und versuche es erneut.";
}

async function readMaintenanceSettings() {
  const { data, error } = await supabase
    .from("app_settings")
    .select("maintenance_enabled, maintenance_message")
    .eq("id", 1)
    .single();
  if (error || !data) {
    throw new Error(error?.message ?? "Der Wartungsstatus konnte nicht geladen werden.");
  }
  return data;
}

function showMaintenance(settings, unavailable = false) {
  state.maintenanceEnabled = true;
  state.maintenanceMessage = settings.maintenance_message ||
    (unavailable
      ? "Der Wartungsstatus konnte nicht geprüft werden. Bitte versuche es später erneut."
      : "Wertweit wird gerade gewartet. Bitte versuche es später erneut.");
  state.initialized = false;
  if (state.appRefreshTimer !== null) {
    clearInterval(state.appRefreshTimer);
    state.appRefreshTimer = null;
  }
  $("#auth-screen").hidden = true;
  $("#app-shell").hidden = true;
  $("#maintenance-screen").hidden = false;
  $("#maintenance-title").textContent = unavailable ? "Verbindung fehlgeschlagen" : "Kurz in Wartung";
  $("#maintenance-message").textContent = state.maintenanceMessage;
}

async function pollMaintenanceStatus() {
  try {
    const settings = await readMaintenanceSettings();
    if (settings.maintenance_enabled) {
      showMaintenance(settings);
      return;
    }
    if (!state.maintenanceEnabled) return;

    state.maintenanceEnabled = false;
    $("#maintenance-screen").hidden = true;
    const { data: { session } } = await supabase.auth.getSession();
    if (session?.user) {
      await initializeApp(session.user);
    } else {
      $("#auth-screen").hidden = false;
    }
  } catch (error) {
    if (!state.maintenanceEnabled) {
      showMaintenance({}, true);
    }
    console.error("Could not refresh maintenance status", error);
  }
}

function parseAmount(value) {
  const normalized = value.trim().replace(/\s/g, "");
  const parsed = normalized.includes(",")
    ? Number(normalized.replace(/\./g, "").replace(",", "."))
    : Number(normalized);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : null;
}

function money(value, currency) {
  return new Intl.NumberFormat("de-DE", { style: "currency", currency }).format(value);
}

function formatRate(value) {
  return new Intl.NumberFormat("de-DE", { maximumFractionDigits: 5 }).format(value);
}

function dateText(value) {
  if (!value) return "";
  return new Intl.DateTimeFormat("de-DE", { dateStyle: "long", timeZone: "UTC" }).format(new Date(`${value}T00:00:00Z`));
}

async function loadCurrentRate() {
  const from = $("#from-currency").value;
  const to = $("#to-currency").value;
  if (!from || !to) return;
  $("#rate-label").textContent = "Kurs wird geladen …";
  try {
    const response = await fetch(`https://api.frankfurter.app/latest?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`);
    if (!response.ok) throw new Error(`Kursdienst antwortet mit HTTP ${response.status}.`);
    const result = await response.json();
    const rate = result.rates?.[to];
    if (!Number.isFinite(rate)) throw new Error("Für dieses Währungspaar ist kein Referenzkurs verfügbar.");
    state.rate = rate;
    state.rateDate = result.date;
    $("#rate-label").textContent = `1 ${from} = ${formatRate(rate)} ${to}`;
    $("#rate-date").textContent = `EZB-Referenzkurs vom ${dateText(result.date)}`;
    renderConversion();
    renderTravel();
    renderExchange();
  } catch (error) {
    state.rate = null;
    $("#rate-label").textContent = error.message;
    $("#converted-value").textContent = "–";
    setStatus($("#app-status"), "Wechselkurse konnten nicht geladen werden. Bitte Verbindung prüfen und erneut versuchen.");
  }
}

function renderConversion() {
  const amount = parseAmount($("#amount").value);
  $("#converted-value").textContent = amount === null || state.rate === null
    ? "Betrag oder Kurs prüfen"
    : money(amount * state.rate, $("#to-currency").value);
}

function showPage(page) {
  state.page = page;
  document.querySelectorAll(".page").forEach((node) => node.classList.toggle("active", node.id === `page-${page}`));
  document.querySelectorAll(".nav-item[data-page]").forEach((node) => node.classList.toggle("active", node.dataset.page === page));
  if (page === "overview") renderHistory();
  if (page === "notifications") renderNotifications();
  if (page === "settings") loadEmailPreference();
}

async function portal(action, values = {}) {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) throw new Error("Bitte melde dich erneut an.");
  const { data, error } = await supabase.functions.invoke("user-portal", {
    body: { action, ...values },
    headers: { Authorization: `Bearer ${session.access_token}` },
  });
  if (error) throw new Error(error.message || "Die Anfrage konnte nicht abgeschlossen werden.");
  if (data?.error) throw new Error(data.error);
  return data;
}

async function loadAccess() {
  try {
    const access = await portal("get-access");
    state.isPro = access.hasAdminPro === true;
    $("#pro-status").textContent = state.isPro ? "Wertweit Pro aktiv" : "Kostenloses Konto";
    $("#pro-title").textContent = state.isPro ? "Wertweit Pro ist aktiv" : "Mehr Überblick auf Reisen.";
    $("#pro-description").textContent = state.isPro
      ? `Dein Web-Konto hat Pro-Zugriff bis ${dateText(access.proUntil?.slice(0, 10))}.`
      : "Der Rechner bleibt kostenlos. Pro bündelt die Reise- und Analysewerkzeuge. Webkäufe sind noch nicht verfügbar.";
    renderTravel();
    renderExchange();
    renderHistory();
  } catch (error) {
    setStatus($("#app-status"), error.message);
  }
}

function renderTravel() {
  const destination = destinations.find((item) => item.currency === $("#destination").value) ?? destinations[0];
  const amount = parseAmount($("#amount").value);
  const targetAmount = destination.currency === $("#from-currency").value
    ? amount
    : destination.currency === $("#to-currency").value && amount !== null && state.rate
    ? amount * state.rate
    : null;
  $("#travel-result").innerHTML = targetAmount === null
    ? `<strong>${destination.flag} ${destination.country}</strong><span>Wähle ${destination.currency} als Zielwährung im Rechner, um den Betrag zu übernehmen.</span>`
    : `<strong>${destination.flag} ${destination.country}</strong><strong>${money(targetAmount, destination.currency)}</strong>${
      state.isPro
        ? `<div class="row"><span>Essen (ca.)</span><strong>${Math.floor(targetAmount / destination.meal)}</strong></div><div class="row"><span>Kaffees (ca.)</span><strong>${Math.floor(targetAmount / destination.coffee)}</strong></div><div class="row"><span>Fahrten (ca.)</span><strong>${Math.floor(targetAmount / destination.transport)}</strong></div><div class="row"><span>Tagesbudget</span><strong>${destination.budget} · ${destination.moderate} · ${destination.comfort}</strong></div><p>${destination.tipping}</p>`
        : ""
    }`;
  $("#travel-pro").innerHTML = state.isPro
    ? `<p class="fine-print">Preisbeispiele, Budgets und Trinkgeld sind manuelle Schätzungen und keine aktuellen Marktdaten.</p>`
    : `<strong>Mehr Reiseinfos mit Pro</strong><p>Preisbeispiele, Tagesbudgets und Trinkgeldhinweise für ausgewählte Ziele. Dieses Konto hat aktuell keinen Web-Pro-Zugriff.</p>`;
}

function renderExchange() {
  const panel = $("#exchange-panel");
  const amount = parseAmount($("#amount").value);
  const percent = Number($("#fee-percent")?.value?.replace(",", ".") ?? 2);
  const offered = Number($("#offered-rate")?.value?.replace(",", ".") ?? 0);
  const desired = Number($("#desired-amount")?.value?.replace(",", ".") ?? 500);
  const source = $("#from-currency").value;
  const target = $("#to-currency").value;
  const rate = state.rate;

  if (!state.isPro) {
    const fee = Number.isFinite(percent) ? percent : 0;
    panel.innerHTML = `<h2>Gebühren-Simulator</h2><p class="muted">${source} → ${target}</p><label for="fee-percent">Gebühr in Prozent</label><input id="fee-percent" inputmode="decimal" value="${fee}"><div class="row"><span>Ausgangsbetrag</span><strong>${amount === null ? "Betrag prüfen" : money(amount, source)}</strong></div><div class="row"><span>Gebühr</span><strong>${amount === null ? "–" : money(amount * fee / 100, source)}</strong></div><div class="row"><span>Nach Gebühr</span><strong>${amount === null ? "–" : money(amount * (1 - fee / 100), source)}</strong></div><div class="row"><span>Voraussichtlicher Zielbetrag</span><strong>${amount === null || rate === null ? "Kein Kurs" : money(amount * (1 - fee / 100) * rate, target)}</strong></div><p class="fine-print">Ergebnisse sind eine Orientierung; Anbietergebühren können abweichen.</p>`;
    $("#fee-percent").addEventListener("input", renderExchange);
    return;
  }

  const availableModes = ["fees", "compare", "reverse", "phrase"];
  const mode = availableModes.includes(state.mode) ? state.mode : "fees";
  const feePanel = `<h2>Gebühren-Simulator</h2><label for="fee-percent">Gebühr in Prozent</label><input id="fee-percent" inputmode="decimal" value="${percent}"><div class="row"><span>Nach Gebühr</span><strong>${amount === null ? "Betrag prüfen" : money(amount * (1 - percent / 100), source)}</strong></div><div class="row"><span>Voraussichtlicher Zielbetrag</span><strong>${amount === null || rate === null ? "Kein Kurs" : money(amount * (1 - percent / 100) * rate, target)}</strong></div>`;
  const panels = {
    fees: feePanel,
    compare: `<h2>Kursangebot vergleichen</h2><p class="muted">Referenz: ${rate ? `1 ${source} = ${formatRate(rate)} ${target}` : "Kurs wird geladen"}</p><label for="offered-rate">Angebotener Kurs (${target})</label><input id="offered-rate" inputmode="decimal" value="${offered || ""}" placeholder="z. B. ${rate ? formatRate(rate) : "1,08"}"><div class="row"><span>Zum Referenzkurs</span><strong>${amount === null || rate === null ? "–" : money(amount * rate, target)}</strong></div><div class="row"><span>Zum angebotenen Kurs</span><strong>${amount === null || !offered ? "–" : money(amount * offered, target)}</strong></div><div class="row"><span>Unterschied</span><strong>${amount === null || !offered || rate === null ? "–" : money(Math.abs(amount * (rate - offered)), target)}</strong></div>`,
    reverse: `<h2>Zielbetrag rückwärts rechnen</h2><label for="desired-amount">Gewünschter Betrag (${target})</label><input id="desired-amount" inputmode="decimal" value="${desired}"><label for="fee-percent">Gebühr in Prozent</label><input id="fee-percent" inputmode="decimal" value="${percent}"><div class="row"><span>Ohne Gebühr</span><strong>${rate && desired ? money(desired / rate, source) : "–"}</strong></div><div class="row"><span>Mit Gebühr</span><strong>${rate && desired ? money(desired / rate / Math.max(.01, 1 - percent / 100), source) : "–"}</strong></div>`,
    phrase: `<h2>Natürlich fragen</h2><p class="muted">Beispiel: „250 Euro in Dollar“</p><label for="phrase">Deine Frage</label><input id="phrase" value="Wie viel sind 250 Euro in Dollar?"><button id="phrase-calculate" class="button primary" type="button">Berechnen</button><p id="phrase-result" class="status success">${state.phraseResult}</p>`,
  };
  panel.innerHTML = panels[mode] ?? feePanel;
  panel.querySelectorAll("input").forEach((input) => input.addEventListener("input", renderExchange));
  $("#phrase-calculate")?.addEventListener("click", parsePhrase);
}

function parsePhrase() {
  const text = $("#phrase")?.value?.toLowerCase() ?? "";
  const amountMatch = text.match(/\d+(?:[.,]\d{3})*(?:[.,]\d+)?/);
  const currencies = [
    ["euro", "EUR"], ["eur", "EUR"], ["€", "EUR"], ["dollar", "USD"], ["usd", "USD"],
    ["yen", "JPY"], ["jpy", "JPY"], ["pfund", "GBP"], ["gbp", "GBP"],
    ["franken", "CHF"], ["chf", "CHF"], ["zloty", "PLN"], ["pln", "PLN"], ["baht", "THB"], ["thb", "THB"],
  ];
  const found = currencies.filter(([name]) => text.includes(name)).map(([, code]) => code);
  if (!amountMatch || found.length < 2 || found[0] === found[1]) {
    state.phraseResult = "Bitte Betrag sowie zwei unterschiedliche Währungen nennen.";
  } else {
    const value = parseAmount(amountMatch[0]);
    if (found[0] === $("#from-currency").value && found[1] === $("#to-currency").value && state.rate) {
      state.phraseResult = `${money(value, found[0])} = ${money(value * state.rate, found[1])}`;
    } else {
      state.phraseResult = "Wähle die genannten Währungen zuerst im Rechner aus und lade den Kurs.";
    }
  }
  renderExchange();
}

function renderHistory() {
  const panel = $("#history-panel");
  const choices = state.isPro ? [[7, "7T"], [30, "30T"], [365, "1J"], [1825, "5J"]] : [[7, "7T"]];
  if (!choices.some(([days]) => days === state.historyDays)) state.historyDays = 7;
  panel.innerHTML = `<h2>Wechselkurs-Verlauf</h2><p class="muted">${$("#from-currency").value} → ${$("#to-currency").value}</p><div class="mode-switch">${choices.map(([days, title]) => `<button class="mode ${state.historyDays === days ? "active" : ""}" data-days="${days}">${title}</button>`).join("")}</div><div id="history-chart" class="muted">Verlauf wird geladen …</div>`;
  panel.querySelectorAll("[data-days]").forEach((button) => button.addEventListener("click", () => {
    state.historyDays = Number(button.dataset.days);
    renderHistory();
  }));
  loadHistoryData();
  const favoriteCodes = JSON.parse(localStorage.getItem("wertweit.web.favorites") || '["USD","GBP","JPY"]');
  $("#overview-pro").innerHTML = state.isPro
    ? `<div class="card"><h2>Mehrere Währungen</h2><div class="favorite-list">${favoriteCodes.map((code) => `<div class="favorite-row"><span>${code}</span><strong>${state.rate ? money((parseAmount($("#amount").value) ?? 0) * state.rate, $("#to-currency").value) : "–"}</strong><button data-remove-favorite="${code}" type="button">Entfernen</button></div>`).join("")}<div class="row"><label for="favorite-code">Währung hinzufügen</label><select id="favorite-code">${Object.keys(state.currencies).filter((code) => !favoriteCodes.includes(code)).map((code) => `<option value="${code}">${code} · ${state.currencies[code]}</option>`).join("")}</select><button id="add-favorite" class="quiet-button" type="button">Hinzufügen</button></div></div><p class="fine-print">Favoriten werden in diesem Browser gespeichert.</p></div><div class="card"><h2>Kursalarm</h2><p>Browseralarme funktionieren nur, solange die Web-App geöffnet ist. Auf iPhone/iPad nutze die App-Mitteilungen.</p><label for="alert-threshold">Zielkurs (${$("#to-currency").value})</label><input id="alert-threshold" inputmode="decimal" placeholder="z. B. ${state.rate ? formatRate(state.rate) : "1,08"}"><button id="add-alert" class="quiet-button" type="button">Kursalarm speichern</button><p id="alert-status" class="status"></p></div>`
    : `<div class="pro-locked"><strong>Mehr Überblick mit Pro</strong><p>Längere Kursverläufe, mehrere Währungen, Favoriten und Kursziele freischalten.</p></div>`;
  $("#add-favorite")?.addEventListener("click", () => {
    const value = $("#favorite-code").value;
    const updated = [...favoriteCodes, value];
    localStorage.setItem("wertweit.web.favorites", JSON.stringify(updated));
    renderHistory();
  });
  panel.querySelectorAll("[data-remove-favorite]").forEach((button) => button.addEventListener("click", () => {
    localStorage.setItem("wertweit.web.favorites", JSON.stringify(favoriteCodes.filter((code) => code !== button.dataset.removeFavorite)));
    renderHistory();
  }));
  $("#add-alert")?.addEventListener("click", addBrowserRateAlert);
}

async function loadHistoryData() {
  const chart = $("#history-chart");
  if (!chart) return;
  try {
    const today = new Date();
    const start = new Date(today);
    start.setUTCDate(today.getUTCDate() - state.historyDays);
    const startText = start.toISOString().slice(0, 10);
    const endText = today.toISOString().slice(0, 10);
    const from = encodeURIComponent($("#from-currency").value);
    const to = encodeURIComponent($("#to-currency").value);
    const response = await fetch(`https://api.frankfurter.app/${startText}..${endText}?from=${from}&to=${to}`);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const data = await response.json();
    const points = Object.entries(data.rates ?? {}).flatMap(([date, rates]) => Number.isFinite(rates[to]) ? [{ date, value: rates[to] }] : []);
    if (points.length < 2) {
      chart.textContent = "Für diesen Zeitraum sind noch nicht genügend Tageskurse verfügbar.";
      return;
    }
    const min = Math.min(...points.map((point) => point.value));
    const max = Math.max(...points.map((point) => point.value));
    const values = points.map((point, index) => `${(index / (points.length - 1)) * 100},${100 - ((point.value - min) / (max - min || 1)) * 85}`).join(" ");
    chart.innerHTML = `<svg class="chart" viewBox="0 0 100 100" preserveAspectRatio="none" role="img" aria-label="Wechselkursverlauf"><polyline points="${values}"></polyline></svg><div class="row"><span>Tief ${formatRate(min)}</span><strong>Hoch ${formatRate(max)}</strong></div><small class="muted">${points.length} Kurstage</small>`;
  } catch (error) {
    chart.textContent = `Kursverlauf konnte nicht geladen werden (${error.message}).`;
  }
}

async function addBrowserRateAlert() {
  const status = $("#alert-status");
  const threshold = Number($("#alert-threshold").value.replace(",", "."));
  if (!Number.isFinite(threshold) || threshold <= 0) {
    setStatus(status, "Bitte gib einen gültigen Zielkurs ein.");
    return;
  }
  if (!("Notification" in window)) {
    setStatus(status, "Dieser Browser unterstützt keine Benachrichtigungen.");
    return;
  }
  const permission = await Notification.requestPermission();
  if (permission !== "granted") {
    setStatus(status, "Erlaube Benachrichtigungen in deinem Browser.");
    return;
  }
  const key = "wertweit.web.alerts";
  const alerts = JSON.parse(localStorage.getItem(key) || "[]");
  alerts.push({ from: $("#from-currency").value, to: $("#to-currency").value, threshold, fired: false });
  localStorage.setItem(key, JSON.stringify(alerts));
  setStatus(status, "Kursalarm gespeichert. Der Browser prüft den Kurs nur, solange diese Web-App geöffnet ist.", "success");
}

function checkBrowserRateAlerts() {
  if (state.rate === null || !("Notification" in window) || Notification.permission !== "granted") return;
  const key = "wertweit.web.alerts";
  const alerts = JSON.parse(localStorage.getItem(key) || "[]");
  let changed = false;
  for (const alert of alerts) {
    if (!alert.fired && alert.from === $("#from-currency").value && alert.to === $("#to-currency").value && state.rate >= alert.threshold) {
      new Notification("Wertweit: Kursziel erreicht", { body: `1 ${alert.from} = ${formatRate(state.rate)} ${alert.to}` });
      alert.fired = true;
      changed = true;
    }
  }
  if (changed) localStorage.setItem(key, JSON.stringify(alerts));
}

function renderNotifications() {
  const list = $("#notification-list");
  list.innerHTML = state.notifications.length
    ? state.notifications.map((notification) => `<article class="notification-item ${notification.read_at ? "" : "unread"}"><strong>${escapeHTML(notification.title)}</strong><p>${escapeHTML(notification.body)}</p><small>${dateText(notification.created_at.slice(0, 10))}</small></article>`).join("")
    : `<div class="card muted">Du hast noch keine Benachrichtigungen.</div>`;
}

function escapeHTML(value) {
  return String(value).replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[character]);
}

async function loadNotifications() {
  try {
    const result = await portal("list-notifications");
    state.notifications = result.notifications ?? [];
    const unread = state.notifications.filter((notification) => !notification.read_at).length;
    $("#notification-count").hidden = unread === 0;
    renderNotifications();
  } catch (error) {
    setStatus($("#app-status"), error.message);
  }
}

async function loadSupportThreads() {
  try {
    const result = await portal("list-support");
    state.supportThreads = result.threads ?? [];
    $("#support-threads").innerHTML = state.supportThreads.length
      ? state.supportThreads.map((thread) => `<article class="thread-card"><strong>${escapeHTML(thread.subject)}</strong><small> · ${escapeHTML(thread.status)}</small>${thread.messages.map((message) => `<p class="thread-message ${message.sender_is_admin ? "admin" : ""}">${escapeHTML(message.body)}</p>`).join("")}</article>`).join("")
      : `<div class="card muted">Du hast noch keine Support-Nachrichten.</div>`;
  } catch (error) {
    setStatus($("#support-status"), error.message);
  }
}

async function loadEmailPreference() {
  try {
    const result = await portal("get-email-updates");
    $("#email-updates").checked = result.subscribed;
  } catch (error) {
    setStatus($("#settings-status"), error.message);
  }
}

function populateDestination() {
  $("#destination").innerHTML = destinations.map((item) => `<option value="${item.currency}">${item.flag} ${item.country}</option>`).join("");
}

function fillCurrencySelectors() {
  const options = Object.entries(state.currencies)
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([code, name]) => `<option value="${code}">${code} · ${escapeHTML(name)}</option>`)
    .join("");
  $("#from-currency").innerHTML = options;
  $("#to-currency").innerHTML = options;
  $("#from-currency").value = localStorage.getItem("wertweit.web.from") || "EUR";
  $("#to-currency").value = localStorage.getItem("wertweit.web.to") || "USD";
}

async function initializeApp(user) {
  if (state.initialized || state.initializing) return;
  state.initializing = true;
  try {
    let settings;
    try {
      settings = await readMaintenanceSettings();
    } catch (error) {
      showMaintenance({}, true);
      console.error("Could not load maintenance settings", error);
      return;
    }
    state.maintenanceEnabled = settings.maintenance_enabled === true;
    if (state.maintenanceEnabled) {
      showMaintenance(settings);
      return;
    }
    $("#maintenance-screen").hidden = true;
    state.initialized = true;
    $("#auth-screen").hidden = true;
    $("#app-shell").hidden = false;
    $("#account-email").textContent = user.email ?? "";
    await Promise.all([loadAccess(), loadNotifications(), loadEmailPreference()]);
    try {
      const response = await fetch("https://api.frankfurter.app/currencies");
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      state.currencies = await response.json();
      fillCurrencySelectors();
      populateDestination();
      await loadCurrentRate();
      renderHistory();
      state.appRefreshTimer = setInterval(() => {
        if (document.visibilityState === "visible") {
          loadCurrentRate();
          loadNotifications();
        }
      }, 5 * 60 * 1000);
    } catch (error) {
      setStatus($("#app-status"), `Die Währungsliste konnte nicht geladen werden: ${error.message}`);
    }
  } finally {
    state.initializing = false;
  }
}

document.querySelectorAll(".nav-item[data-page]").forEach((button) => button.addEventListener("click", () => showPage(button.dataset.page)));
$("#amount").addEventListener("input", () => {
  renderConversion();
  renderTravel();
  renderExchange();
});
$("#from-currency").addEventListener("change", () => {
  localStorage.setItem("wertweit.web.from", $("#from-currency").value);
  loadCurrentRate();
  if (state.page === "overview") renderHistory();
});
$("#to-currency").addEventListener("change", () => {
  localStorage.setItem("wertweit.web.to", $("#to-currency").value);
  loadCurrentRate();
  if (state.page === "overview") renderHistory();
});
$("#swap-currencies").addEventListener("click", () => {
  const oldFrom = $("#from-currency").value;
  $("#from-currency").value = $("#to-currency").value;
  $("#to-currency").value = oldFrom;
  $("#from-currency").dispatchEvent(new Event("change"));
  $("#to-currency").dispatchEvent(new Event("change"));
});
$("#refresh-rate").addEventListener("click", loadCurrentRate);
$("#destination").addEventListener("change", renderTravel);
$("#exchange-modes").addEventListener("click", (event) => {
  const button = event.target.closest("[data-mode]");
  if (!button) return;
  if (!state.isPro && button.dataset.mode !== "fees") {
    showPage("pro");
    return;
  }
  state.mode = button.dataset.mode;
  document.querySelectorAll(".mode").forEach((node) => node.classList.toggle("active", node.dataset.mode === state.mode));
  renderExchange();
});
$("#notification-button").addEventListener("click", async () => {
  await loadNotifications();
  showPage("notifications");
  const unread = state.notifications.filter((notification) => !notification.read_at).map((notification) => notification.id);
  if (unread.length) {
    try {
      await portal("mark-notifications-read", { ids: unread });
      await loadNotifications();
    } catch (error) {
      setStatus($("#app-status"), error.message);
    }
  }
});
$("#settings-button").addEventListener("click", () => showPage("settings"));
$("#settings-refresh").addEventListener("click", loadEmailPreference);
$("#support-open").addEventListener("click", () => {
  showPage("support");
  loadSupportThreads();
});
$("#support-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const button = event.currentTarget.querySelector("button[type=submit]");
  button.disabled = true;
  try {
    await portal("create-support", {
      subject: $("#support-subject").value,
      body: $("#support-body").value,
    });
    event.currentTarget.reset();
    setStatus($("#support-status"), "Nachricht an den Wertweit-Support gesendet.", "success");
    await loadSupportThreads();
  } catch (error) {
    setStatus($("#support-status"), error.message);
  } finally {
    button.disabled = false;
  }
});
$("#delete-account").addEventListener("click", async () => {
  if (!confirm("Wertweit-Konto und Kontodaten endgültig löschen? Ein App-Store-Abo musst du separat bei Apple kündigen.")) return;
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return;
  const { data, error } = await supabase.functions.invoke("account-delete", {
    body: {},
    headers: { Authorization: `Bearer ${session.access_token}` },
  });
  if (error || data?.error) {
    setStatus($("#settings-status"), error?.message ?? data.error);
    return;
  }
  await supabase.auth.signOut();
  location.reload();
});
$("#email-updates").addEventListener("change", async (event) => {
  try {
    const result = await portal("set-email-updates", { subscribed: event.target.checked });
    event.target.checked = result.subscribed;
    setStatus($("#settings-status"), result.subscribed ? "Produktneuigkeiten sind eingeschaltet." : "Produktneuigkeiten sind ausgeschaltet.", "success");
  } catch (error) {
    event.target.checked = !event.target.checked;
    setStatus($("#settings-status"), error.message);
  }
});
$("#sign-out").addEventListener("click", async () => {
  const { error } = await supabase.auth.signOut();
  if (error) {
    setStatus($("#app-status"), error.message);
    return;
  }
  location.reload();
});
$("#maintenance-refresh").addEventListener("click", async (event) => {
  const button = event.currentTarget;
  button.disabled = true;
  try {
    await pollMaintenanceStatus();
  } finally {
    button.disabled = false;
  }
});

let authMode = "signin";
let awaitingOTP = false;
let pendingConfirmationEmail = "";

function updateAuthMode() {
  $("#auth-title").textContent = authMode === "signin" ? "Willkommen zurück" : "Konto erstellen";
  $("#auth-description").textContent = "Melde dich mit deinem Wertweit-Konto an, um die App zu nutzen.";
  $("#auth-submit").textContent = authMode === "signin" ? "Anmelden" : "Konto erstellen";
  $("#auth-mode").textContent = authMode === "signin" ? "Neues Konto erstellen" : "Ich habe schon ein Konto";
  $("#reset-password").hidden = authMode !== "signin";
  $("#auth-password").autocomplete = authMode === "signin" ? "current-password" : "new-password";
}

function showConfirmation(email) {
  awaitingOTP = true;
  pendingConfirmationEmail = email;
  $("#auth-title").textContent = "E-Mail bestätigen";
  $("#auth-description").textContent = `Gib den Bestätigungscode ein, den wir an ${email} gesendet haben.`;
  $("#auth-credentials").hidden = true;
  $("#auth-email").required = false;
  $("#auth-password").required = false;
  $("#auth-otp-fields").hidden = false;
  $("#auth-otp").required = true;
  $("#auth-actions").hidden = true;
  $("#auth-submit").textContent = "E-Mail bestätigen";
  $("#auth-message").textContent = "";
  $("#auth-otp").focus();
}

function showCredentials() {
  awaitingOTP = false;
  pendingConfirmationEmail = "";
  $("#auth-title").textContent = "Willkommen zurück";
  $("#auth-description").textContent = "Melde dich mit deinem Wertweit-Konto an, um die App zu nutzen.";
  $("#auth-credentials").hidden = false;
  $("#auth-email").required = true;
  $("#auth-password").required = true;
  $("#auth-otp-fields").hidden = true;
  $("#auth-otp").required = false;
  $("#auth-otp").value = "";
  $("#auth-actions").hidden = false;
  authMode = "signin";
  updateAuthMode();
}

$("#auth-mode").addEventListener("click", () => {
  authMode = authMode === "signin" ? "signup" : "signin";
  updateAuthMode();
});
$("#reset-password").addEventListener("click", async () => {
  const email = $("#auth-email").value.trim();
  if (!email) {
    setStatus($("#auth-message"), "Gib zuerst deine E-Mail-Adresse ein.");
    return;
  }
  const { error } = await supabase.auth.resetPasswordForEmail(email, { redirectTo: location.href });
  setStatus($("#auth-message"), error?.message ?? "Falls das Konto existiert, wurde ein Link zum Zurücksetzen angefordert.", error ? "" : "success");
});
$("#auth-otp").addEventListener("input", (event) => {
  event.target.value = event.target.value.replace(/\D/g, "").slice(0, 8);
});
$("#auth-resend").addEventListener("click", async (event) => {
  const button = event.currentTarget;
  button.disabled = true;
  try {
    const { error } = await supabase.auth.resend({
      type: "signup",
      email: pendingConfirmationEmail,
    });
    if (error) throw error;
    setStatus($("#auth-message"), "Wenn die Adresse noch nicht bestätigt ist, wurde ein neuer Code gesendet.", "success");
  } catch (error) {
    setStatus($("#auth-message"), authErrorMessage(error, "resend"));
  } finally {
    button.disabled = false;
  }
});
$("#auth-cancel").addEventListener("click", () => {
  showCredentials();
  setStatus($("#auth-message"), "");
});
$("#auth-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const email = $("#auth-email").value.trim();
  const password = $("#auth-password").value;
  const button = $("#auth-submit");
  button.disabled = true;
  setStatus($("#auth-message"), "");
  let authOperation = awaitingOTP ? "verify" : authMode;
  try {
    if (awaitingOTP) {
      const { data, error } = await supabase.auth.verifyOtp({
        email: pendingConfirmationEmail,
        token: $("#auth-otp").value.trim(),
        type: "signup",
      });
      if (error) throw error;
      if (!data.user) throw new Error("Die E-Mail konnte nicht bestätigt werden. Fordere einen neuen Code an.");
      awaitingOTP = false;
      pendingConfirmationEmail = "";
      await initializeApp(data.user);
      return;
    }
    if (authMode === "signup" && password.length < 8) {
      throw new Error("Das Passwort muss mindestens 8 Zeichen lang sein.");
    }
    if (authMode === "signup") {
      authOperation = "signup";
      const { data, error } = await supabase.auth.signUp({ email, password });
      if (error) throw error;
      if (data.session && data.user) {
        await initializeApp(data.user);
        return;
      }
      showConfirmation(email);
      setStatus($("#auth-message"), "Wir haben einen Bestätigungscode an deine E-Mail-Adresse gesendet.", "success");
      return;
    }
    authOperation = "signin";
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) {
      if (error.code === "email_not_confirmed" || /email not confirmed/i.test(error.message)) {
        showConfirmation(email);
        setStatus($("#auth-message"), "Bitte bestätige zuerst deine E-Mail-Adresse mit dem zugesendeten Code.");
        return;
      }
      throw error;
    }
    await initializeApp(data.user);
  } catch (error) {
    setStatus($("#auth-message"), authErrorMessage(error, authOperation));
  } finally {
    button.disabled = false;
  }
});

supabase.auth.onAuthStateChange((_event, session) => {
  if (session?.user && $("#app-shell").hidden && !state.maintenanceEnabled) {
    void initializeApp(session.user).catch((error) => {
      setStatus($("#auth-message"), error.message || "Die Anmeldung konnte nicht abgeschlossen werden.");
    });
  }
});
try {
  const settings = await readMaintenanceSettings();
  state.maintenanceEnabled = settings.maintenance_enabled === true;
  if (state.maintenanceEnabled) {
    showMaintenance(settings);
  } else {
    const { data: { session } } = await supabase.auth.getSession();
    if (session?.user) await initializeApp(session.user);
    else $("#auth-screen").hidden = false;
  }
} catch (error) {
  showMaintenance({}, true);
  console.error("Could not load initial maintenance settings", error);
}
state.maintenanceTimer = setInterval(() => void pollMaintenanceStatus(), 60 * 1000);

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("./sw.js").catch((error) => {
    console.error("Die Web-App konnte nicht für die Installation vorbereitet werden.", error);
  });
}
