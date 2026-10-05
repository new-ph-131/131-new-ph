// FILE: functions/api/lab_signal.ts
// Cloudflare Pages Function: High-Speed Edge Signal Bus for Event-Driven 2-Way Sync

interface SignalRecord {
  id: string;
  storeToken: string;
  source: string;
  action: string;
  entityId: string;
  timestamp: number;
  serverReceivedAt: number;
  payload?: any;
}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Requested-With",
  "Content-Type": "application/json",
};

export async function onRequestOptions() {
  return new Response(null, { status: 204, headers: CORS_HEADERS });
}

export async function onRequestPost(context: any) {
  try {
    const raw = await context.request.text();
    if (!raw || raw.trim().length === 0) {
      return new Response(JSON.stringify({ status: "ERROR", message: "Empty body" }), {
        status: 400,
        headers: CORS_HEADERS,
      });
    }

    const body = JSON.parse(raw);
    const storeToken = (body.storeToken || "").trim().toUpperCase();

    if (!storeToken) {
      return new Response(JSON.stringify({ status: "ERROR", message: "storeToken required" }), {
        status: 400,
        headers: CORS_HEADERS,
      });
    }

    const record: SignalRecord = {
      id: body.id || `evt_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
      storeToken,
      source: (body.source || "UNKNOWN").toUpperCase(),
      action: body.action || "DELTA_MUTATION",
      entityId: body.entityId || "",
      timestamp: body.timestamp || Date.now(),
      serverReceivedAt: Date.now(),
      payload: body.payload || {},
    };

    // Store in Cloudflare KV (instant global replication across all edge datacenters)
    if (context.env && context.env.SIGNAL_KV) {
      await context.env.SIGNAL_KV.put(`sig_${storeToken}`, JSON.stringify(record), {
        expirationTtl: 3600,
      });
    }

    return new Response(JSON.stringify({ status: "SUCCESS", event: record }), {
      status: 200,
      headers: CORS_HEADERS,
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ status: "ERROR", message: err.toString() }), {
      status: 500,
      headers: CORS_HEADERS,
    });
  }
}

export async function onRequestGet(context: any) {
  try {
    const url = new URL(context.request.url);
    const storeToken = (url.searchParams.get("storeToken") || "").trim().toUpperCase();
    const lastSeenTs = parseInt(url.searchParams.get("lastSeenTs") || "0", 10);

    if (!storeToken) {
      return new Response(JSON.stringify({ status: "ERROR", message: "storeToken query param required" }), {
        status: 400,
        headers: CORS_HEADERS,
      });
    }

    let current: SignalRecord | null = null;
    if (context.env && context.env.SIGNAL_KV) {
      const raw = await context.env.SIGNAL_KV.get(`sig_${storeToken}`);
      if (raw) {
        try {
          current = JSON.parse(raw);
        } catch (_) {}
      }
    }

    if (!current) {
      return new Response(JSON.stringify({ status: "SUCCESS", hasUpdate: false, event: null }), {
        status: 200,
        headers: CORS_HEADERS,
      });
    }

    const hasUpdate = current.timestamp > lastSeenTs;

    return new Response(JSON.stringify({ status: "SUCCESS", hasUpdate, event: hasUpdate ? current : null }), {
      status: 200,
      headers: CORS_HEADERS,
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ status: "ERROR", message: err.toString() }), {
      status: 500,
      headers: CORS_HEADERS,
    });
  }
}
