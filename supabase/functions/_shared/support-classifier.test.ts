import {
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { classifySupport } from "./support-classifier.ts";

Deno.test("classifies a broken app as an important bug", () => {
  assertEquals(classifySupport("App geht nicht", "Die Umrechnung funktioniert nicht."), {
    category: "bug",
    priority: "yellow",
  });
});

Deno.test("flags account security incidents as urgent", () => {
  assertEquals(classifySupport("Mein Konto wurde gehackt", "Ich sehe fremde Anmeldungen."), {
    category: "account",
    priority: "red",
  });
});

Deno.test("classifies product suggestions as normal priority", () => {
  assertEquals(classifySupport("Wunsch", "Ich hätte gern eine neue Funktion."), {
    category: "feature",
    priority: "green",
  });
});

Deno.test("normalizes German characters before matching", () => {
  assertEquals(classifySupport("Zahlung", "Mir wurde der Betrag doppelt abgebucht."), {
    category: "payment",
    priority: "red",
  });
});
