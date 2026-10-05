// FILE: functions/api/lab_signal.ts
// Cloudflare Pages Function: High-Speed Edge Signal & Delta Mutation Bus (<30ms)

interface SignalRecord {
  id: string;
  storeToken: string;
  source: string;
  action: string;
  entityType?: string;
  entityId: string;
  timestamp: number;
  serverReceivedAt: number;
  deletedIds?: string[];
  delta?: any;
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
      entityType: body.entityType || "",
      entityId: body.entityId || "",
      timestamp: body.timestamp || Date.now(),
      serverReceivedAt: Date.now(),
      deletedIds: Array.isArray(body.deletedIds) ? body.deletedIds : [],
      delta: body.delta || null,
      payload: body.payload || {},
    };

    if (context.env && context.env.SIGNAL_KV) {
      const kv = context.env.SIGNAL_KV;

      // 1. Store latest signal
      await kv.put(`sig_${storeToken}`, JSON.stringify(record), { expirationTtl: 86400 });

      // 2. Manage circular mutation log (last 50 mutations)
      let events: SignalRecord[] = [];
      const rawEvents = await kv.get(`events_${storeToken}`);
      if (rawEvents) {
        try { events = JSON.parse(rawEvents); } catch (_) {}
      }
      events.push(record);
      if (events.length > 50) {
        events = events.slice(events.length - 50);
      }
      await kv.put(`events_${storeToken}`, JSON.stringify(events), { expirationTtl: 86400 });

      // 3. Update persistent edge tombstone registry
      if (record.deletedIds && record.deletedIds.length > 0) {
        let tombstones: string[] = [];
        const rawT = await kv.get(`tomb_${storeToken}`);
        if (rawT) {
          try { tombstones = JSON.parse(rawT); } catch (_) {}
        }
        const tSet = new Set(tombstones);
        for (const d of record.deletedIds) {
          if (d && typeof d === 'string' && d.trim().length > 0) {
            tSet.add(d.trim());
          }
        }
        if (record.entityId && record.action.includes('DELETE')) {
          tSet.add(record.entityId.trim());
        }
        await kv.put(`tomb_${storeToken}`, JSON.stringify(Array.from(tSet)), { expirationTtl: 604800 }); // 7 days
      }
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
    let mutations: SignalRecord[] = [];
    let tombstones: string[] = [];

    if (context.env && context.env.SIGNAL_KV) {
      const kv = context.env.SIGNAL_KV;

      const [rawSig, rawEvents, rawTomb] = await Promise.all([
        kv.get(`sig_${storeToken}`),
        kv.get(`events_${storeToken}`),
        kv.get(`tomb_${storeToken}`),
      ]);

      if (rawSig) {
        try { current = JSON.parse(rawSig); } catch (_) {}
      }
      if (rawEvents) {
        try {
          const allEvts: SignalRecord[] = JSON.parse(rawEvents);
          mutations = allEvts.filter((e) => e.timestamp > lastSeenTs);
        } catch (_) {}
      }
      if (rawTomb) {
        try { tombstones = JSON.parse(rawTomb); } catch (_) {}
      }
    }

    if (!current) {
      return new Response(JSON.stringify({ status: "SUCCESS", hasUpdate: false, event: null, mutations: [], tombstones: [] }), {
        status: 200,
        headers: CORS_HEADERS,
      });
    }

    const hasUpdate = current.timestamp > lastSeenTs || mutations.length > 0;

    return new Response(JSON.stringify({
      status: "SUCCESS",
      hasUpdate,
      event: hasUpdate ? current : null,
      mutations,
      tombstones,
    }), {
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
