// FILE: functions/api/send_mail.ts
// Revision: #PH-REV-798 (ENTERPRISE-WEB-SMTP-EDGE-RELAY)
// Cloudflare Workers TCP Socket SMTP Relay for Gmail (smtp.gmail.com:465 / 587)
import { connect } from "cloudflare:sockets";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Content-Type": "application/json",
};

export async function onRequestOptions() {
  return new Response(null, { status: 204, headers: CORS_HEADERS });
}

function toBase64Utf8(str: string): string {
  const bytes = new TextEncoder().encode(str);
  let binary = "";
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

function chunkBase64(b64: string, lineLength = 76): string {
  const clean = b64.replace(/[\r\n\s]/g, "");
  const chunks: string[] = [];
  for (let i = 0; i < clean.length; i += lineLength) {
    chunks.push(clean.slice(i, i + lineLength));
  }
  return chunks.join("\r\n");
}

export async function onRequestPost(context: any) {
  try {
    const body = await context.request.json();
    const smtpHost = (body.smtpHost || "smtp.gmail.com").toString().trim();
    const smtpUser = (body.smtpMailID || "").toString().replace(/\s+/g, "").trim();
    const smtpPass = (body.smtpMailPass || "").toString().replace(/\s+/g, "").trim();
    const shopName = (body.shopName || "Pharoah ERP").toString().trim();
    const recipientEmail = (body.recipientEmail || "").toString().replace(/\s+/g, "").trim();
    const subject = (body.subject || "Document from " + shopName).toString();
    const textBody = (body.body || "").toString();
    const fileName = (body.fileName || "Document.pdf").toString();
    const attachmentBase64 = (body.attachmentBase64 || "").toString();
    const mimeType = fileName.toLowerCase().endsWith(".zip")
      ? "application/zip"
      : "application/pdf";

    if (!smtpUser || !smtpPass || !recipientEmail) {
      return new Response(
        JSON.stringify({ status: "ERROR", message: "Missing SMTP credentials or recipient email." }),
        { status: 400, headers: CORS_HEADERS }
      );
    }

    // Connect over implicit TLS (Port 465) for direct encrypted SMTP handshake
    const port = 465;
    const socket = connect({ hostname: smtpHost, port: port }, { secureTransport: "on" });
    const writer = socket.writable.getWriter();
    const reader = socket.readable.getReader();
    const decoder = new TextDecoder();
    const encoder = new TextEncoder();

    let buffer = "";
    async function readResponse(): Promise<string> {
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split("\r\n");
        // Check if last complete line is final SMTP response (3 digits followed by space)
        for (let i = 0; i < lines.length - 1; i++) {
          const line = lines[i];
          if (/^\d{3} /.test(line)) {
            const fullResp = lines.slice(0, i + 1).join("\r\n");
            buffer = lines.slice(i + 1).join("\r\n");
            return fullResp;
          }
        }
      }
      return buffer;
    }

    async function sendCommand(cmd: string, expectedPrefix: string): Promise<string> {
      await writer.write(encoder.encode(cmd + "\r\n"));
      const resp = await readResponse();
      if (!resp.startsWith(expectedPrefix)) {
        throw new Error(`SMTP error on '${cmd.split(" ")[0]}': ${resp}`);
      }
      return resp;
    }

    // 1. Read Server Greeting (220)
    const greeting = await readResponse();
    if (!greeting.startsWith("220")) {
      throw new Error("SMTP connection failed: " + greeting);
    }

    // 2. EHLO
    await sendCommand("EHLO pharoah-erp.pages.dev", "250");

    // 3. AUTH LOGIN
    await sendCommand("AUTH LOGIN", "334");
    await sendCommand(btoa(smtpUser), "334");
    await sendCommand(btoa(smtpPass), "235");

    // 4. MAIL FROM & RCPT TO
    await sendCommand(`MAIL FROM:<${smtpUser}>`, "250");
    await sendCommand(`RCPT TO:<${recipientEmail}>`, "250");

    // 5. DATA
    await sendCommand("DATA", "354");

    // 6. Construct MIME Multipart Message
    const boundary = "----=_PharoahErpPart_" + Date.now().toString(16);
    const safeShopName = shopName.replace(/["<>]/g, "");
    const encodedSubject = "=?UTF-8?B?" + toBase64Utf8(subject) + "?=";
    const encodedBody = chunkBase64(toBase64Utf8(textBody));
    const encodedAttachment = chunkBase64(attachmentBase64);

    const mimeLines = [
      `From: "${safeShopName}" <${smtpUser}>`,
      `To: <${recipientEmail}>`,
      `Subject: ${encodedSubject}`,
      `Date: ${new Date().toUTCString()}`,
      `MIME-Version: 1.0`,
      `Content-Type: multipart/mixed; boundary="${boundary}"`,
      ``,
      `--${boundary}`,
      `Content-Type: text/plain; charset="UTF-8"`,
      `Content-Transfer-Encoding: base64`,
      ``,
      encodedBody,
      ``,
      `--${boundary}`,
      `Content-Type: ${mimeType}; name="${fileName}"`,
      `Content-Disposition: attachment; filename="${fileName}"`,
      `Content-Transfer-Encoding: base64`,
      ``,
      encodedAttachment,
      ``,
      `--${boundary}--`,
      `.`,
    ];

    await sendCommand(mimeLines.join("\r\n"), "250");

    // 7. QUIT
    try {
      await writer.write(encoder.encode("QUIT\r\n"));
      await socket.close();
    } catch (_) {}

    return new Response(
      JSON.stringify({ status: "SUCCESS", recipient: recipientEmail }),
      { status: 200, headers: CORS_HEADERS }
    );
  } catch (err: any) {
    return new Response(
      JSON.stringify({ status: "ERROR", message: err?.message || String(err) }),
      { status: 500, headers: CORS_HEADERS }
    );
  }
}
