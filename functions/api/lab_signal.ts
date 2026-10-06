// FILE: functions/api/lab_signal.ts
// Cloudflare Pages Function: High-Capacity D1 SQL Edge Signal Bus (<30ms)
// Equipped with 100,000 writes/day & 5,000,000 reads/day quota.

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

interface ChannelData {
  latest: SignalRecord | null;
  events: SignalRecord[];
  tombstones: string[];
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
      id: body.id || ("evt_" + Date.now() + "_" + Math.random().toString(36).substring(2, 7)),
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

    let channelData: ChannelData = {
      latest: null,
      events: [],
      tombstones: [],
    };

    // 1. PRIMARY ENGINE: CLOUDFLARE D1 (100,000 Writes/Day Quota)
    if (context.env && context.env.SIGNAL_DB) {
      try {
        const db = context.env.SIGNAL_DB;
        // Self-healing table creation
        await db.prepare(
          "CREATE TABLE IF NOT EXISTS signals (storeToken TEXT PRIMARY KEY, data TEXT, timestamp INTEGER)"
        ).run().catch(() => {});

        const row: any = await db.prepare("SELECT data FROM signals WHERE storeToken = ?").bind(storeToken).first();
        if (row && row.data) {
          try {
            channelData = JSON.parse(row.data);
          } catch (_) {}
        }

        channelData.latest = record;
        if (!channelData.events) channelData.events = [];
        channelData.events.push(record);
        if (channelData.events.length > 40) {
          channelData.events = channelData.events.slice(channelData.events.length - 40);
        }

        if (!channelData.tombstones) channelData.tombstones = [];
        const tSet = new Set(channelData.tombstones);
        if (record.deletedIds && record.deletedIds.length > 0) {
          for (const d of record.deletedIds) {
            if (d && typeof d === "string" && d.trim().length > 0) {
              tSet.add(d.trim());
            }
          }
        }
        if (record.entityId && record.action.includes("DELETE")) {
          tSet.add(record.entityId.trim());
        }
        channelData.tombstones = Array.from(tSet);

        // Atomic Upsert to D1
        await db.prepare(
          "INSERT INTO signals (storeToken, data, timestamp) VALUES (?, ?, ?) ON CONFLICT(storeToken) DO UPDATE SET data = excluded.data, timestamp = excluded.timestamp"
        ).bind(storeToken, JSON.stringify(channelData), Date.now()).run();
      } catch (d1Err) {
        console.error("D1 Write Exception:", d1Err);
      }
    }

    // 2. SECONDARY / TRANSITIONAL FALLBACK: KV (Silent catch if KV quota exhausted)
    if (context.env && context.env.SIGNAL_KV) {
      try {
        const kv = context.env.SIGNAL_KV;
        const chanKey = "chan_" + storeToken;
        await kv.put(chanKey, JSON.stringify(channelData), { expirationTtl: 604800 }).catch(() => {});
      } catch (_) {}
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
    let foundInD1 = false;

    // 1. PRIMARY ENGINE: CLOUDFLARE D1 (5,000,000 Reads/Day Quota)
    if (context.env && context.env.SIGNAL_DB) {
      try {
        const db = context.env.SIGNAL_DB;
        const row: any = await db.prepare("SELECT data, timestamp FROM signals WHERE storeToken = ?").bind(storeToken).first();
        if (row && row.data) {
          const chanData: ChannelData = JSON.parse(row.data);
          current = chanData.latest;
          if (Array.isArray(chanData.events)) {
            mutations = chanData.events.filter((e) => e.timestamp > lastSeenTs);
          }
          if (Array.isArray(chanData.tombstones)) {
            tombstones = chanData.tombstones;
          }
          foundInD1 = true;
        }
      } catch (d1Err) {
        console.error("D1 Read Exception:", d1Err);
      }
    }

    // 2. SECONDARY FALLBACK: KV (Only if not found in D1)
    if (!foundInD1 && context.env && context.env.SIGNAL_KV) {
      try {
        const kv = context.env.SIGNAL_KV;
        const chanKey = "chan_" + storeToken;
        const rawChan = await kv.get(chanKey);
        if (rawChan) {
          const chanData: ChannelData = JSON.parse(rawChan);
          current = chanData.latest;
          if (Array.isArray(chanData.events)) {
            mutations = chanData.events.filter((e) => e.timestamp > lastSeenTs);
          }
          if (Array.isArray(chanData.tombstones)) {
            tombstones = chanData.tombstones;
          }
        }
      } catch (_) {}
    }

    if (!current) {
      return new Response(JSON.stringify({ status: "SUCCESS", hasUpdate: false, event: null, mutations: [], tombstones: [] }), {
        status: 200,
        headers: {
          ...CORS_HEADERS,
          "Cache-Control": "public, max-age=1, stale-while-revalidate=2",
        },
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
      headers: {
        ...CORS_HEADERS,
        "Cache-Control": "public, max-age=1, stale-while-revalidate=2",
      },
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ status: "ERROR", message: err.toString() }), {
      status: 500,
      headers: CORS_HEADERS,
    });
  }
}
