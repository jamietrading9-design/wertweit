interface PushMessage {
  title: string;
  body: string;
}

interface PushResult {
  sent: number;
  failed: number;
  configured: boolean;
}

function base64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function encodeJSON(value: unknown): string {
  return base64URL(new TextEncoder().encode(JSON.stringify(value)));
}

function decodePEM(value: string): ArrayBuffer {
  const body = value.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}

async function authorizationToken(teamID: string, keyID: string, privateKey: string): Promise<string> {
  const header = encodeJSON({ alg: "ES256", kid: keyID });
  const claims = encodeJSON({ iss: teamID, iat: Math.floor(Date.now() / 1000) });
  const unsigned = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    decodePEM(privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(unsigned),
  );
  return `${unsigned}.${base64URL(new Uint8Array(signature))}`;
}

export async function sendAPNS(
  deviceTokens: string[],
  message: PushMessage,
): Promise<PushResult> {
  const teamID = Deno.env.get("APPLE_TEAM_ID");
  const keyID = Deno.env.get("APPLE_APNS_KEY_ID");
  const privateKey = Deno.env.get("APPLE_APNS_PRIVATE_KEY");
  const topic = Deno.env.get("APPLE_APNS_TOPIC");
  const environment = Deno.env.get("APPLE_APNS_ENVIRONMENT");
  if (!teamID || !keyID || !privateKey || !topic || !environment) {
    return { sent: 0, failed: 0, configured: false };
  }
  if (environment !== "sandbox" && environment !== "production") {
    throw new Error("APPLE_APNS_ENVIRONMENT must be sandbox or production.");
  }
  if (deviceTokens.length === 0) return { sent: 0, failed: 0, configured: true };

  const token = await authorizationToken(teamID, keyID, privateKey);
  const host = environment === "sandbox"
    ? "https://api.sandbox.push.apple.com"
    : "https://api.push.apple.com";
  const results = await Promise.all(deviceTokens.map(async (deviceToken) => {
    try {
      const response = await fetch(`${host}/3/device/${deviceToken}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${token}`,
          "apns-topic": topic,
          "apns-push-type": "alert",
          "apns-priority": "10",
          "content-type": "application/json",
        },
        body: JSON.stringify({
          aps: { alert: message, sound: "default" },
        }),
      });
      if (response.ok) return true;
      console.error("APNs rejected a notification", response.status, await response.text());
      return false;
    } catch (error) {
      console.error("APNs request failed", error);
      return false;
    }
  }));
  return {
    sent: results.filter(Boolean).length,
    failed: results.filter((sent) => !sent).length,
    configured: true,
  };
}
