export interface GmailDeliveryFailure {
  email: string;
  error: string;
}

export interface GmailDeliveryResult {
  sent: number;
  failed: GmailDeliveryFailure[];
}

export async function sendViaGmail(
  recipients: string[],
  subject: string,
  body: string,
): Promise<GmailDeliveryResult> {
  const scriptURL = Deno.env.get("GOOGLE_APPS_SCRIPT_URL");
  const scriptToken = Deno.env.get("GOOGLE_APPS_SCRIPT_TOKEN");
  if (!scriptURL || !scriptToken) {
    throw new Error("Gmail delivery is not configured. Set GOOGLE_APPS_SCRIPT_URL and GOOGLE_APPS_SCRIPT_TOKEN.");
  }

  let response: Response;
  try {
    response = await fetch(scriptURL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token: scriptToken, recipients, subject, body }),
    });
  } catch (error) {
    console.error("Could not reach the Gmail delivery script", error);
    throw new Error("Gmail delivery could not be reached. Check the Apps Script deployment.");
  }

  if (!response.ok) {
    console.error("Gmail delivery script returned an HTTP error", response.status);
    throw new Error(`Gmail delivery returned HTTP ${response.status}. Check the Apps Script deployment.`);
  }
  try {
    const result: unknown = await response.json();
    if (typeof result !== "object" || result === null || !("sent" in result) || !("failed" in result) ||
        typeof result.sent !== "number" || !Number.isInteger(result.sent) || !Array.isArray(result.failed)) {
      throw new Error("Unexpected Gmail delivery response");
    }
    const failed = result.failed.flatMap((failure) => {
      if (typeof failure !== "object" || failure === null || !("email" in failure) || !("error" in failure) ||
          typeof failure.email !== "string" || typeof failure.error !== "string") {
        return [];
      }
      return [{ email: failure.email, error: failure.error }];
    });
    if (failed.length !== result.failed.length) throw new Error("Invalid Gmail delivery failures");
    return { sent: result.sent, failed };
  } catch (error) {
    console.error("Could not verify the Gmail delivery response", error);
    throw new Error("Gmail delivery response could not be verified. Check sent mail before retrying.");
  }
}
