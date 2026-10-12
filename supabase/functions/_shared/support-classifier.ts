export type SupportCategory = "account" | "payment" | "bug" | "feature" | "other";
export type SupportPriority = "red" | "yellow" | "green";

export interface SupportClassification {
  category: SupportCategory;
  priority: SupportPriority;
}

const categoryLabels: Record<SupportCategory, string> = {
  account: "Konto & Anmeldung",
  payment: "Zahlung & Pro",
  bug: "App-Fehler",
  feature: "Wunsch & Vorschlag",
  other: "Sonstiges",
};

const priorityLabels: Record<SupportPriority, string> = {
  red: "Dringend",
  yellow: "Wichtig",
  green: "Normal",
};

const priorityEmoji: Record<SupportPriority, string> = {
  red: "🔴",
  yellow: "🟡",
  green: "🟢",
};

function normalize(text: string): string {
  return text.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase();
}

export function classifySupport(subject: string, body: string): SupportClassification {
  const text = normalize(`${subject}\n${body}`);
  let category: SupportCategory = "other";
  if (/\b(abo|apple|app store|abbuch\w*|zahlung\w*|bezahlt\w*|rechnung\w*|preis\w*|pro[- ]?abo|erstattung\w*|subscription\w*)\b/.test(text)) {
    category = "payment";
  } else if (/\b(anmeld\w*|login\w*|passwort\w*|kennwort\w*|bestatigungscode|bestatigung\w*|einlogg\w*|konto\w*|gesperrt\w*)\b/.test(text)) {
    category = "account";
  } else if (/\b(fehler\w*|bug\w*|absturz\w*|funktioniert\w*|geht nicht|lad\w*|start\w*|wechselt nicht|kurs\w*|anzeige\w*|crash\w*)\b/.test(text)) {
    category = "bug";
  } else if (/\b(vorschlag\w*|idee\w*|wunsch\w*|feature\w*|hinzufugen\w*|verbesser\w*|konnen sie|kannst du)\b/.test(text)) {
    category = "feature";
  }

  const urgent = /\b(gehackt|hacker|hacked|datenverlust|daten gestohlen|data loss|data stolen|sicherheitslucke|security hole|unbefugter zugriff|konto ubernommen|doppelt abgebucht|betrug|fraud|dringend|notfall|critical|urgent)\b/.test(text);
  const blocked = /\b(niemand|alle nutzer|komplett|vollstandig|everybody|everyone)\b/.test(text) &&
    /\b(ausfall|down|nicht erreichbar|geht nicht|funktioniert nicht|absturz|unavailable)\b/.test(text);
  const priority: SupportPriority = urgent || blocked
    ? "red"
    : category === "account" || category === "payment" || category === "bug"
    ? "yellow"
    : "green";

  return { category, priority };
}

export function supportCategoryLabel(category: SupportCategory): string {
  return categoryLabels[category] ?? categoryLabels.other;
}

export function supportPriorityLabel(priority: SupportPriority): string {
  return priorityLabels[priority] ?? priorityLabels.green;
}

export function supportPriorityEmoji(priority: SupportPriority): string {
  return priorityEmoji[priority] ?? priorityEmoji.green;
}
