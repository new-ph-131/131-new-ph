// FILE: functions/api/lab_signal.ts
// Cloudflare Pages Function: High-Capacity D1 SQL Edge Signal & Tombstone Resolution Bus (<30ms)
// Features: Server-Authoritative Tombstone Sanitization, 100,000 Writes/Day, 5,000,000 Reads/Day.

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

    const action = (body.action || "DELTA_MUTATION").toUpperCase();
    const isDeleteAction = action.includes("DELETE") || action.includes("REMOVE");

    const record: SignalRecord = {
      id: body.id || ("evt_" + Date.now() + "_" + Math.random().toString(36).substring(2, 7)),
      storeToken,
      source: (body.source || "UNKNOWN").toUpperCase(),
      action: body.action || "DELTA_MUTATION",
      entityType: body.entityType || "",
      entityId: (body.entityId || "").trim(),
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

        if (isDeleteAction) {
          // 🛑 DELETION OPERATION: Add to tombstones
          if (record.deletedIds && record.deletedIds.length > 0) {
            for (const d of record.deletedIds) {
              if (d && typeof d === "string" && d.trim().length > 0) {
                tSet.add(d.trim());
              }
            }
          }
          if (record.entityId && record.entityId.length > 0) {
            tSet.add(record.entityId);
          }
        } else {
          // 🛡️ RE-IMPORT / SAVE / UPDATE OPERATION: Server-side Tombstone Purification!
          // If a record is being saved or imported, it is ALIVE. It must be evicted from tombstones!
          if (record.entityId && record.entityId.length > 0) {
            tSet.delete(record.entityId);
          }
          if (record.payload && typeof record.payload === "object") {
            if (record.payload.billNo) tSet.delete(record.payload.billNo.toString().trim());
            if (record.payload.internalNo) tSet.delete(record.payload.internalNo.toString().trim());
            if (record.payload.id) tSet.delete(record.payload.id.toString().trim());
          }
          // Also if explicit unmark list provided in body
          if (Array.isArray(body.unmarkedIds)) {
            for (const u of body.unmarkedIds) {
              if (u && typeof u === "string") tSet.delete(u.trim());
            }
          }
        }

        channelData.tombstones = Array.from(tSet);

        // Atomic Upsert to D1
        await db.prepare(
          "INSERT INTO signals (storeToken, data, timestamp) VALUES (?, ?, ?) ON CONFLICT(storeToken) DO UPDATE SET data = excluded.data, timestamp = excluded.timestamp"
        ).bind(storeToken, JSON.stringify(channelData), Date.now()).run();

        // 🚀 SECTION 1: CLOUDFLARE D1 BATCH ENGINE FOR ERP_MASTER_SYNC
        if (body.operations && Array.isArray(body.operations) && body.operations.length > 0) {
          try {
            await db.prepare(
              "CREATE TABLE IF NOT EXISTS erp_master_sync (sync_id TEXT PRIMARY KEY, store_token TEXT NOT NULL, document_type TEXT NOT NULL, version INTEGER NOT NULL, updated_at INTEGER NOT NULL, is_deleted INTEGER NOT NULL, bill_data TEXT NOT NULL)"
            ).run().catch(() => {});
            await db.prepare(
              "CREATE INDEX IF NOT EXISTS idx_doc_type_updated ON erp_master_sync (store_token, document_type, updated_at)"
            ).run().catch(() => {});

            const sqlStatements = [];
            for (const op of body.operations) {
              const sId = (op.sync_id || "").toString().trim();
              if (!sId) continue;
              const dType = (op.document_type || "SALE").toString().toUpperCase();
              const ver = parseInt(op.version || 1, 10);
              const uAt = parseInt(op.updated_at || Date.now(), 10);
              const isActionDelete = (op.action || "").toString().toUpperCase() === "DELETE";
              const isDel = (op.is_deleted === 1 || isActionDelete) ? 1 : 0;
              const rawData = op.data !== undefined ? op.data : op.bill_data;
              const bData = typeof rawData === "string" ? rawData : JSON.stringify(rawData || {});

              const stmt = db.prepare(
                "INSERT INTO erp_master_sync (sync_id, store_token, document_type, version, updated_at, is_deleted, bill_data) " +
                "VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7) " +
                "ON CONFLICT(sync_id) DO UPDATE SET " +
                "bill_data = CASE WHEN ?5 > updated_at AND ?4 >= version THEN ?7 ELSE bill_data END, " +
                "is_deleted = CASE WHEN ?5 > updated_at AND ?4 >= version THEN ?6 ELSE is_deleted END, " +
                "version = CASE WHEN ?4 > version THEN ?4 ELSE version END, " +
                "updated_at = CASE WHEN ?5 > updated_at THEN ?5 ELSE updated_at END"
              ).bind(sId, storeToken, dType, ver, uAt, isDel, bData);
              sqlStatements.push(stmt);
            }

            if (sqlStatements.length > 0) {
              await db.batch(sqlStatements);
            }
          } catch (batchErr) {
            console.error("D1 Master Sync Batch Exception:", batchErr);
          }
        }
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

    return new Response(JSON.stringify({
      status: "SUCCESS",
      event: record,
      activeTombstonesCount: channelData.tombstones.length,
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

    // Query D1 Master Sync for Delta Batch Operations
    let batchOperations: any[] = [];
    if (context.env && context.env.SIGNAL_DB) {
      try {
        const db = context.env.SIGNAL_DB;
        const deltaRows: any = await db.prepare(
          "SELECT sync_id, document_type, version, updated_at, is_deleted, bill_data FROM erp_master_sync WHERE store_token = ? AND updated_at > ? ORDER BY updated_at ASC LIMIT 150"
        ).bind(storeToken, lastSeenTs).all().catch(() => null);
        if (deltaRows && Array.isArray(deltaRows.results) && deltaRows.results.length > 0) {
          batchOperations = deltaRows.results.map((r: any) => ({
            sync_id: r.sync_id,
            document_type: r.document_type,
            version: r.version,
            updated_at: r.updated_at,
            is_deleted: r.is_deleted,
            action: r.is_deleted === 1 ? 'DELETE' : 'UPDATE',
            data: typeof r.bill_data === 'string' ? JSON.parse(r.bill_data) : (r.bill_data || {}),
            bill_data: r.bill_data,
          }));
        }
      } catch (err) {
        console.error("D1 Delta Read Exception:", err);
      }
    }

    if (!current && batchOperations.length === 0) {
      return new Response(JSON.stringify({ status: "SUCCESS", hasUpdate: false, event: null, mutations: [], tombstones: [], batch_operations: [] }), {
        status: 200,
        headers: {
          ...CORS_HEADERS,
          "Cache-Control": "public, max-age=1, stale-while-revalidate=2",
        },
      });
    }

    const hasUpdate = (current && current.timestamp > lastSeenTs) || mutations.length > 0 || batchOperations.length > 0;
    return new Response(JSON.stringify({
      status: "SUCCESS",
      hasUpdate,
      event: (current && current.timestamp > lastSeenTs) ? current : null,
      mutations,
      tombstones,
      batch_operations: batchOperations,
      serverTime: Date.now(),
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
