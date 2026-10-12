function jsonResponse(value) {
  return ContentService
    .createTextOutput(JSON.stringify(value))
    .setMimeType(ContentService.MimeType.JSON);
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[character]);
}

function brandedHtmlBody(subject, body) {
  const lines = body.trim().replace(/\r\n?/g, "\n").split("\n");
  const details = [];
  const content = [];
  lines.forEach((line) => {
    const detail = line.match(/^(Priorität|Kategorie|Betreff):\s*(.+)$/);
    if (detail) {
      details.push(`<tr>
        <td style="padding:7px 12px;color:#69746d;font-size:12px;font-weight:bold;">${escapeHtml(detail[1])}</td>
        <td style="padding:7px 12px;color:#14241f;font-size:13px;">${escapeHtml(detail[2])}</td>
      </tr>`);
    } else {
      content.push(line);
    }
  });

  const paragraphs = content.join("\n").trim().split(/\n{2,}/).filter(Boolean).map((paragraph) =>
    `<p style="margin:0 0 16px;">${escapeHtml(paragraph).replace(/\n/g, "<br>")}</p>`
  ).join("");
  const detailsTable = details.length
    ? `<table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;margin:0 0 22px;border:1px solid #e1e5dd;border-radius:8px;background:#f8f9f5;">${details.join("")}</table>`
    : "";
  const title = escapeHtml(subject.trim());
  const preview = escapeHtml(content.find((line) => line.trim())?.trim() ?? subject.trim());

  return `<!doctype html>
<html lang="de">
  <body style="margin:0;padding:0;background:#f1f3ec;color:#14241f;font-family:Arial,Helvetica,sans-serif;">
    <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">${preview}</div>
    <table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;background:#f1f3ec;">
      <tr><td align="center" style="padding:34px 14px;">
        <table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;max-width:600px;border:1px solid #e1e5dd;background:#ffffff;">
          <tr><td style="padding:25px 30px;background:#0b2b24;">
            <img src="https://jamietrading9-design.github.io/wertweit/assets/wertweit-logo.png" width="44" height="44" alt="Wertweit" style="display:inline-block;vertical-align:middle;border:0;border-radius:11px;">
            <span style="display:inline-block;margin-left:11px;color:#ffffff;font-size:20px;font-weight:bold;line-height:44px;vertical-align:middle;">Wertweit</span>
            <span style="float:right;color:#d8f06b;font-size:10px;font-weight:bold;letter-spacing:1.5px;line-height:44px;text-transform:uppercase;">Unterwegs gut informiert</span>
          </td></tr>
          <tr><td style="height:4px;background:#d8f06b;font-size:0;line-height:0;">&nbsp;</td></tr>
          <tr><td style="padding:32px 30px 16px;">
            <h1 style="margin:0;color:#123c31;font-family:Georgia,'Times New Roman',serif;font-size:27px;font-weight:normal;line-height:1.3;">${title}</h1>
          </td></tr>
          <tr><td style="padding:8px 30px 30px;color:#34433d;font-size:15px;line-height:1.75;">
            ${detailsTable}${paragraphs}
          </td></tr>
          <tr><td style="padding:20px 30px;border-top:1px solid #e1e5dd;background:#fafbf8;color:#69746d;font-size:12px;line-height:1.7;">
            Viele Grüße,<br><strong style="color:#123c31;">Dein Wertweit-Team</strong><br>
            <a href="https://jamietrading9-design.github.io/wertweit/" style="color:#1c6a4f;text-decoration:underline;">Wertweit im Web öffnen</a>
          </td></tr>
        </table>
        <p style="margin:15px 0 0;color:#879089;font-size:11px;line-height:1.5;">Wertweit · Währungsrechner für unterwegs</p>
      </td></tr>
    </table>
  </body>
</html>`;
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
  if (payload.replyTo !== undefined && (typeof payload.replyTo !== "string" ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(payload.replyTo))) {
    return jsonResponse({ error: "Invalid reply address" });
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
      htmlBody: brandedHtmlBody(payload.subject, payload.body),
      name: "Wertweit",
    };
    if (payload.replyTo) message.replyTo = payload.replyTo;
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
