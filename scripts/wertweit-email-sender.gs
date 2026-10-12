function jsonResponse(value) {
  return ContentService
    .createTextOutput(JSON.stringify(value))
    .setMimeType(ContentService.MimeType.JSON);
}

function doPost(event) {
  const expectedToken = PropertiesService.getScriptProperties().getProperty("WERTWEIT_MAIL_SECRET");
  let payload;
  try {
    payload = JSON.parse(event.postData.contents);
  } catch (_error) {
    return jsonResponse({ error: "Invalid JSON body" });
  }

  if (!expectedToken || typeof payload.token !== "string" || payload.token !== expectedToken) {
    return jsonResponse({ error: "Unauthorized" });
  }
  if (!Array.isArray(payload.recipients) || payload.recipients.length < 1 || payload.recipients.length > 99 ||
      payload.recipients.some((email) => typeof email !== "string" ||
        !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))) {
    return jsonResponse({ error: "Invalid recipient list" });
  }
  if (typeof payload.subject !== "string" || payload.subject.trim().length < 1 ||
      payload.subject.length > 150 || /[\r\n]/.test(payload.subject) ||
      typeof payload.body !== "string" || payload.body.trim().length < 1 || payload.body.length > 10000) {
    return jsonResponse({ error: "Invalid email content" });
  }

  const recipients = payload.recipients.filter((email) =>
    email.toLowerCase() !== "wertweitoffiziell@gmail.com"
  );
  const quota = MailApp.getRemainingDailyQuota();
  const requiredQuota = recipients.length + 1;
  if (quota < requiredQuota) {
    return jsonResponse({
      sent: 0,
      failed: payload.recipients.map((email) => ({
        email,
        error: `Gmail-Tageslimit erreicht; dieser Versand benötigt ${requiredQuota} Empfängerplätze, noch ${quota} verfügbar.`,
      })),
    });
  }

  try {
    const message = {
      to: "wertweitoffiziell@gmail.com",
      subject: payload.subject.trim(),
      body: payload.body.trim(),
      name: "Wertweit",
    };
    if (recipients.length > 0) message.bcc = recipients.join(",");
    MailApp.sendEmail(message);
    return jsonResponse({ sent: payload.recipients.length, failed: [] });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Gmail konnte die E-Mail nicht senden.";
    return jsonResponse({
      sent: 0,
      failed: payload.recipients.map((email) => ({ email, error: message })),
    });
  }
}
