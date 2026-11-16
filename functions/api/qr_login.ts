// FILE: functions/api/qr_login.ts
// Cloudflare Pages Function: Secure Ephemeral QR Workstation Login Relay (D1 SIGNAL_DB)
// Stores ONLY opaque encrypted payload (sealed client-side with QR-embedded OTP key).
// Plaintext password never touches D1; rows are 120s TTL and single-use (deleted on claim).

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Requested-With",
  "Content-Type": "application/json",
};

const NO_CACHE_HEADERS: Record<string, string> = {
  ...CORS_HEADERS,
  "Cache-Control": "no-store, no-cache, must-revalidate",
};

const SESSION_TTL_MS = 120 * 1000;

let _qrTableReady = false;
async function ensureQrTable(db: any) {
  if (_qrTableReady) return;
  try {
    await db.batch([
      db.prepare(
        "CREATE TABLE IF NOT EXISTS qr_login_sessions (" +
        "sid TEXT PRIMARY KEY, " +
        "status TEXT NOT NULL, " +
        "sealed_payload TEXT DEFAULT '', " +
        "created_at INTEGER NOT NULL, " +
        "expires_at INTEGER NOT NULL)"
      ),
      db.prepare("CREATE INDEX IF NOT EXISTS idx_qr_login_exp ON qr_login_sessions (expires_at)"),
    ]);
    _qrTableReady = true;
  } catch (_) {}
}

function isValidSid(sid: string): boolean {
  return /^[A-Za-z0-9_-]{16,80}$/.test(sid);
}

export async function onRequestOptions() {
  return new Response(null, { status: 204, headers: CORS_HEADERS });
}

export async function onRequestPost(context: any) {
  try {
    if (!context.env || !context.env.SIGNAL_DB) {
      return new Response(JSON.stringify({ status: "ERROR", message: "D1 SIGNAL_DB binding unavailable" }), {
        status: 500,
        headers: NO_CACHE_HEADERS,
      });
    }
    const db = context.env.SIGNAL_DB;
    await ensureQrTable(db);

    const raw = await context.request.text();
    if (!raw || raw.trim().length === 0) {
      return new Response(JSON.stringify({ status: "ERROR", message: "Empty request body" }), {
        status: 400,
        headers: NO_CACHE_HEADERS,
      });
    }

    const body = JSON.parse(raw);
    const action = (body.action || "").toString().trim().toUpperCase();
    const sid = (body.sid || "").toString().trim();
    const now = Date.now();

    if (!isValidSid(sid)) {
      return new Response(JSON.stringify({ status: "ERROR", message: "Invalid session id" }), {
        status: 400,
        headers: NO_CACHE_HEADERS,
      });
    }

    // Opportunistic purge of expired sessions
    await db.prepare("DELETE FROM qr_login_sessions WHERE expires_at < ?").bind(now).run().catch(() => {});

    if (action === "INIT") {
      const expiresAt = now + SESSION_TTL_MS;
      await db.prepare(
        "INSERT INTO qr_login_sessions (sid, status, sealed_payload, created_at, expires_at) " +
        "VALUES (?, 'PENDING', '', ?, ?) " +
        "ON CONFLICT(sid) DO UPDATE SET status = 'PENDING', sealed_payload = '', created_at = excluded.created_at, expires_at = excluded.expires_at"
      ).bind(sid, now, expiresAt).run();

      return new Response(JSON.stringify({
        status: "SUCCESS",
        sid,
        expiresAt,
        expiresInSec: 120,
      }), {
        status: 200,
        headers: NO_CACHE_HEADERS,
      });
    }

    if (action === "APPROVE") {
      const sealedPayload = (body.sealedPayload || "").toString().trim();
      if (!sealedPayload || sealedPayload.length < 32 || sealedPayload.length > 8192) {
        return new Response(JSON.stringify({ status: "ERROR", message: "Invalid encrypted payload" }), {
          status: 400,
          headers: NO_CACHE_HEADERS,
        });
      }

      const existing: any = await db.prepare(
        "SELECT status, expires_at FROM qr_login_sessions WHERE sid = ?"
      ).bind(sid).first();

      if (!existing || Number(existing.expires_at) < now) {
        await db.prepare("DELETE FROM qr_login_sessions WHERE sid = ?").bind(sid).run().catch(() => {});
        return new Response(JSON.stringify({
          status: "EXPIRED",
          message: "QR code expired. Please refresh QR on Web Workstation.",
        }), {
          status: 410,
          headers: NO_CACHE_HEADERS,
        });
      }

      if (existing.status !== "PENDING") {
        return new Response(JSON.stringify({
          status: "CONSUMED",
          message: "This QR code has already been used.",
        }), {
          status: 409,
          headers: NO_CACHE_HEADERS,
        });
      }

      await db.prepare(
        "UPDATE qr_login_sessions SET status = 'APPROVED', sealed_payload = ? WHERE sid = ? AND status = 'PENDING'"
      ).bind(sealedPayload, sid).run();

      return new Response(JSON.stringify({
        status: "SUCCESS",
        message: "Web Workstation login approved!",
      }), {
        status: 200,
        headers: NO_CACHE_HEADERS,
      });
    }

    return new Response(JSON.stringify({ status: "ERROR", message: "Unknown action" }), {
      status: 400,
      headers: NO_CACHE_HEADERS,
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ status: "ERROR", message: err?.toString?.() || "Server error" }), {
      status: 500,
      headers: NO_CACHE_HEADERS,
    });
  }
}

export async function onRequestGet(context: any) {
  try {
    if (!context.env || !context.env.SIGNAL_DB) {
      return new Response(JSON.stringify({ status: "ERROR", message: "D1 SIGNAL_DB binding unavailable" }), {
        status: 500,
        headers: NO_CACHE_HEADERS,
      });
    }
    const db = context.env.SIGNAL_DB;
    await ensureQrTable(db);

    const url = new URL(context.request.url);
    const sid = (url.searchParams.get("sid") || "").trim();
    const now = Date.now();

    if (!isValidSid(sid)) {
      return new Response(JSON.stringify({ status: "ERROR", message: "Invalid session id" }), {
        status: 400,
        headers: NO_CACHE_HEADERS,
      });
    }

    const row: any = await db.prepare(
      "SELECT status, sealed_payload, expires_at FROM qr_login_sessions WHERE sid = ?"
    ).bind(sid).first();

    if (!row || Number(row.expires_at) < now) {
      if (row) {
        await db.prepare("DELETE FROM qr_login_sessions WHERE sid = ?").bind(sid).run().catch(() => {});
      }
      return new Response(JSON.stringify({ status: "EXPIRED" }), {
        status: 200,
        headers: NO_CACHE_HEADERS,
      });
    }

    if (row.status === "APPROVED" && row.sealed_payload) {
      // Single-use burn: delete immediately once claimed by polling Web browser
      await db.prepare("DELETE FROM qr_login_sessions WHERE sid = ?").bind(sid).run().catch(() => {});
      return new Response(JSON.stringify({
        status: "APPROVED",
        sealedPayload: row.sealed_payload,
      }), {
        status: 200,
        headers: NO_CACHE_HEADERS,
      });
    }

    return new Response(JSON.stringify({
      status: "PENDING",
      remainingSec: Math.max(0, Math.floor((Number(row.expires_at) - now) / 1000)),
    }), {
      status: 200,
      headers: NO_CACHE_HEADERS,
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ status: "ERROR", message: err?.toString?.() || "Server error" }), {
      status: 500,
      headers: NO_CACHE_HEADERS,
    });
  }
}
