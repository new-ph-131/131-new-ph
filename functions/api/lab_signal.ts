// FILE: functions/api/lab_signal.ts
// Cloudflare Pages Function: High-Capacity D1 SQL Edge Signal & Tombstone Resolution Bus (<30ms)
// Features: Atomic Row-Level Signal/Tombstone Tables, Sticky Delete Guards, 100k Writes/Day.
// Revision: #PH-REV-811 (FIX-NOBATCH-MULTI-MRP-FY-AND-PURCHASE-DELETE-SYNC)

interface SignalRecord {
  id: string;
  storeToken: string;
  source: string;
  action: string;
  entityType?: string;
  entityId: string;
  financialYear?: string;
  fy?: string;
  timestamp: number;
  serverReceivedAt: number;
  deletedIds?: string[];
  unmarkedIds?: string[];
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

const NO_CACHE_HEADERS = {
  ...CORS_HEADERS,
  "Cache-Control": "no-store, no-cache, must-revalidate",
};

async function ensureSignalTables(db: any) {
  await db.batch([
    db.prepare("CREATE TABLE IF NOT EXISTS signals (storeToken TEXT PRIMARY KEY, data TEXT, timestamp INTEGER)"),
    db.prepare(
      "CREATE TABLE IF NOT EXISTS signal_tombstones (" +
      "store_token TEXT NOT NULL, " +
      "tomb_key TEXT NOT NULL, " +
      "fy TEXT DEFAULT '', " +
      "updated_at INTEGER NOT NULL, " +
      "PRIMARY KEY (store_token, tomb_key))"
    ),
    db.prepare(
      "CREATE TABLE IF NOT EXISTS signal_events (" +
      "seq INTEGER PRIMARY KEY AUTOINCREMENT, " +
      "store_token TEXT NOT NULL, " +
      "event_id TEXT NOT NULL, " +
      "source TEXT NOT NULL, " +
      "action TEXT NOT NULL, " +
      "entity_type TEXT DEFAULT '', " +
      "entity_id TEXT DEFAULT '', " +
      "fy TEXT DEFAULT '', " +
      "timestamp INTEGER NOT NULL, " +
      "deleted_ids TEXT DEFAULT '[]', " +
      "unmarked_ids TEXT DEFAULT '[]', " +
      "event_json TEXT NOT NULL)"
    ),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_signal_events_ts ON signal_events (store_token, timestamp, seq)"),
  ]).catch(() => {});
}

async function applyAtomicTombstonesAndEvent(
  db: any,
  storeToken: string,
  sigRecord: SignalRecord,
  deletedKeys: string[],
  unmarkedKeys: string[],
  fy: string,
  eventTs: number
) {
  const stmts: any[] = [];
  const delSet = new Set<string>();
  const unmSet = new Set<string>();

  for (const rawD of deletedKeys) {
    if (typeof rawD !== "string") continue;
    const dk = rawD.trim();
    if (!dk) continue;
    delSet.add(dk);
    if (!dk.includes("_")) delSet.add(dk.toUpperCase());
  }

  for (const rawU of unmarkedKeys) {
    if (typeof rawU !== "string") continue;
    const uk = rawU.trim();
    if (!uk || delSet.has(uk)) continue;
    unmSet.add(uk);
    if (!uk.includes("_")) unmSet.add(uk.toUpperCase());
  }

  for (const dk of delSet) {
    stmts.push(
      db.prepare(
        "INSERT INTO signal_tombstones (store_token, tomb_key, fy, updated_at) VALUES (?, ?, ?, ?) " +
        "ON CONFLICT(store_token, tomb_key) DO UPDATE SET " +
        "updated_at = CASE WHEN excluded.updated_at > signal_tombstones.updated_at THEN excluded.updated_at ELSE signal_tombstones.updated_at END, " +
        "fy = CASE WHEN excluded.fy != '' THEN excluded.fy ELSE signal_tombstones.fy END"
      ).bind(storeToken, dk, fy, eventTs)
    );
  }

  for (const uk of unmSet) {
    stmts.push(
      db.prepare(
        "DELETE FROM signal_tombstones WHERE store_token = ? AND tomb_key = ? AND updated_at <= ?"
      ).bind(storeToken, uk, eventTs)
    );
  }

  stmts.push(
    db.prepare(
      "INSERT INTO signal_events (store_token, event_id, source, action, entity_type, entity_id, fy, timestamp, deleted_ids, unmarked_ids, event_json) " +
      "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    ).bind(
      storeToken,
      sigRecord.id,
      sigRecord.source,
      sigRecord.action,
      sigRecord.entityType || "",
      sigRecord.entityId || "",
      fy,
      sigRecord.timestamp,
      JSON.stringify(Array.from(delSet)),
      JSON.stringify(Array.from(unmSet)),
      JSON.stringify(sigRecord)
    )
  );

  // Keep event buffer trimmed per store (keep last 300 atomic events)
  stmts.push(
    db.prepare(
      "DELETE FROM signal_events WHERE store_token = ? AND seq NOT IN (SELECT seq FROM signal_events WHERE store_token = ? ORDER BY seq DESC LIMIT 300)"
    ).bind(storeToken, storeToken)
  );

  await db.batch(stmts).catch(() => {});
}

export async function onRequestOptions() {
  return new Response(null, { status: 204, headers: CORS_HEADERS });
}

export async function onRequestPost(context: any) {
  try {
    const raw = await context.request.text();
    if (!raw || raw.trim().length === 0) {
      return new Response(JSON.stringify({ status: "ERROR", message: "Empty body" }), {
        status: 400,
        headers: NO_CACHE_HEADERS,
      });
    }

    const body = JSON.parse(raw);
    const storeToken = (body.storeToken || "").trim().toUpperCase();
    if (!storeToken) {
      return new Response(JSON.stringify({ status: "ERROR", message: "storeToken required" }), {
        status: 400,
        headers: NO_CACHE_HEADERS,
      });
    }

    const reqFy = (body.fy || body.financialYear || "").toString().trim();

    // 🚀 SECTION 2: MARG-STYLE DETERMINISTIC SALE/PURCHASE EVENT LEDGER (D1 AUTO-INCREMENT SEQ)
    if (body.sale_event && typeof body.sale_event === "object") {
      try {
        if (context.env && context.env.SIGNAL_DB) {
          const db = context.env.SIGNAL_DB;
          await ensureSignalTables(db);
          await db.prepare(
            "CREATE TABLE IF NOT EXISTS sale_events (" +
            "seq INTEGER PRIMARY KEY AUTOINCREMENT, " +
            "store_token TEXT NOT NULL, " +
            "bill_id TEXT NOT NULL, " +
            "bill_no TEXT NOT NULL, " +
            "version INTEGER NOT NULL, " +
            "action TEXT NOT NULL, " +
            "status TEXT NOT NULL, " +
            "client_source TEXT NOT NULL, " +
            "payload TEXT NOT NULL, " +
            "created_at INTEGER NOT NULL)"
          ).run().catch(() => {});
          await db.prepare(
            "CREATE INDEX IF NOT EXISTS idx_sale_events_seq ON sale_events (store_token, seq)"
          ).run().catch(() => {});
          await db.prepare(
            "CREATE INDEX IF NOT EXISTS idx_sale_events_bill ON sale_events (store_token, bill_id)"
          ).run().catch(() => {});

          const ev = body.sale_event;
          const billId = (ev.bill_id || ev.id || "").toString().trim();
          const billNo = (ev.bill_no || ev.billNo || "").toString().trim();
          const incomingVer = parseInt(ev.version || 1, 10);
          const evAction = (ev.action || "INSERT").toString().toUpperCase();
          const evStatus = (ev.status || (evAction === "CANCEL" ? "Cancelled" : (evAction === "DELETE" ? "Deleted" : "Active"))).toString();
          const clientSource = (ev.client_source || body.source || "UNKNOWN").toString();
          const evPayloadObj = typeof ev.payload === "string" ? JSON.parse(ev.payload || "{}") : (ev.payload || ev);
          const evFy = (reqFy || (evPayloadObj && evPayloadObj.fy) || "").toString().trim();
          if (evPayloadObj && typeof evPayloadObj === "object" && evFy && !evPayloadObj.fy) {
            evPayloadObj.fy = evFy;
          }
          const payload = typeof ev.payload === "string" ? ev.payload : JSON.stringify(evPayloadObj || {});

          // Sticky DELETE + Optimistic Concurrency Control (OCC) Check
          if (evAction !== "DELETE" && billId) {
            const latestRow: any = await db.prepare(
              "SELECT version, action, status FROM sale_events WHERE store_token = ? AND bill_id = ? ORDER BY seq DESC LIMIT 1"
            ).bind(storeToken, billId).first().catch(() => null);

            if (latestRow) {
              const latestAct = (latestRow.action || "").toString().toUpperCase();
              const latestSt = (latestRow.status || "").toString().toUpperCase();
              if (latestAct === "DELETE" || latestSt === "DELETED") {
                return new Response(JSON.stringify({
                  status: "DELETED",
                  message: "Bill was permanently deleted and cannot be overwritten by a stale update",
                  current_version: latestRow.version || 999999,
                  bill_id: billId,
                }), { status: 410, headers: NO_CACHE_HEADERS });
              }
              if ((evAction === "UPDATE" || evAction === "CANCEL") && latestRow.version && latestRow.version >= incomingVer) {
                return new Response(JSON.stringify({
                  status: "CONFLICT",
                  message: `Bill has already been modified (Server v${latestRow.version} vs Client v${incomingVer})`,
                  current_version: latestRow.version,
                  bill_id: billId,
                }), { status: 409, headers: NO_CACHE_HEADERS });
              }
            }
          }

          const nowMs = Date.now();
          const insertRes: any = await db.prepare(
            "INSERT INTO sale_events (store_token, bill_id, bill_no, version, action, status, client_source, payload, created_at) " +
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
          ).bind(storeToken, billId, billNo, incomingVer, evAction, evStatus, clientSource, payload, nowMs).run();

          const newSeq = insertRes?.meta?.last_row_id || nowMs;

          const delIds: string[] = Array.isArray(body.deletedIds) ? body.deletedIds : [];
          const unmIds: string[] = Array.isArray(body.unmarkedIds) ? body.unmarkedIds : [];
          const isPurchaseEvt = (body.action || "").toString().toUpperCase().includes("PURCHASE") ||
            (evPayloadObj && (evPayloadObj.doc_type === "PURCHASE" || evPayloadObj.internalNo !== undefined));

          const atomicDelKeys: string[] = [];
          const atomicUnmKeys: string[] = [];
          if (evAction === "DELETE") {
            if (billId) atomicDelKeys.push(billId);
            for (const d of delIds) {
              if (d && typeof d === "string" && d.trim()) atomicDelKeys.push(d.trim());
            }
          } else {
            if (billId) atomicUnmKeys.push(billId);
            if (billNo && !isPurchaseEvt) atomicUnmKeys.push(billNo);
            for (const u of unmIds) {
              if (u && typeof u === "string" && u.trim()) atomicUnmKeys.push(u.trim());
            }
          }

          const sigRecord: SignalRecord = {
            id: "evt_" + nowMs + "_" + Math.random().toString(36).substring(2, 7),
            storeToken,
            source: clientSource.toUpperCase().includes("WEB") ? "WEB" : (clientSource.toUpperCase().includes("APP") ? "APP" : clientSource.toUpperCase()),
            action: body.action || evAction,
            entityType: isPurchaseEvt ? "PURCHASE" : "SALE",
            entityId: billId,
            financialYear: evFy,
            fy: evFy,
            timestamp: nowMs,
            serverReceivedAt: nowMs,
            deletedIds: evAction === "DELETE" ? (atomicDelKeys.length > 0 ? atomicDelKeys : (billId ? [billId] : [])) : [],
            unmarkedIds: evAction !== "DELETE" ? atomicUnmKeys : [],
            payload: ev.payload || {},
          };

          await applyAtomicTombstonesAndEvent(db, storeToken, sigRecord, atomicDelKeys, atomicUnmKeys, evFy, nowMs);

          // Backward-compatible signals blob best-effort sync
          try {
            const row: any = await db.prepare("SELECT data FROM signals WHERE storeToken = ?").bind(storeToken).first();
            let chanData: ChannelData = row && row.data ? JSON.parse(row.data) : { latest: null, events: [], tombstones: [] };
            if (!chanData.tombstones) chanData.tombstones = [];
            if (!chanData.events) chanData.events = [];
            const tSet = new Set(chanData.tombstones);
            if (evAction === "DELETE") {
              for (const dk of atomicDelKeys) {
                tSet.add(dk);
                if (!dk.includes("_")) tSet.add(dk.toUpperCase());
              }
            } else {
              for (const uk of atomicUnmKeys) {
                tSet.delete(uk);
                if (!uk.includes("_")) tSet.delete(uk.toUpperCase());
              }
            }
            chanData.tombstones = Array.from(tSet);
            chanData.latest = sigRecord;
            chanData.events.push(sigRecord);
            if (chanData.events.length > 200) {
              chanData.events = chanData.events.slice(chanData.events.length - 200);
            }
            await db.prepare(
              "INSERT INTO signals (storeToken, data, timestamp) VALUES (?, ?, ?) ON CONFLICT(storeToken) DO UPDATE SET data = excluded.data, timestamp = excluded.timestamp"
            ).bind(storeToken, JSON.stringify(chanData), nowMs).run();
          } catch (_) {}

          return new Response(JSON.stringify({
            status: "SUCCESS",
            seq: newSeq,
            version: incomingVer,
            bill_id: billId,
            bill_no: billNo,
            action: evAction,
          }), { status: 200, headers: NO_CACHE_HEADERS });
        }
      } catch (evtErr: any) {
        console.error("D1 Sale Event Exception:", evtErr);
      }
    }

    const action = (body.action || "DELTA_MUTATION").toUpperCase();
    const isDeleteAction = action.includes("DELETE") || action.includes("REMOVE");
    const isOutboxBatch = action === "JSON_BATCH_MUTATION" || (body.source || "").toUpperCase() === "OUTBOX_BATCH";

    const extractedBatchDeletedIds: string[] = [];
    const extractedBatchUnmarkedIds: string[] = [];

    if (body.operations && Array.isArray(body.operations)) {
      for (const op of body.operations) {
        const sId = (op.sync_id || "").toString().trim();
        const isActionDelete = (op.action || "").toString().toUpperCase() === "DELETE";
        const isDel = (op.is_deleted === 1 || isActionDelete) ? 1 : 0;
        const dType = (op.document_type || "SALE").toString().toUpperCase();
        const isPurchaseDoc = dType === "PURCHASE" || dType === "PURCHASE_CHALLAN";
        const rawBill = ((op.bill_data && op.bill_data.billNo) || (op.data && op.data.billNo) || "").toString().trim();
        const rawParty = ((op.bill_data && op.bill_data.partyId) || (op.data && op.data.partyId) || "").toString().trim();
        const rawInt = ((op.bill_data && op.bill_data.internalNo) || (op.data && op.data.internalNo) || "").toString().trim();
        const compKey = (rawParty && rawBill) ? `${rawParty.toUpperCase()}_${rawBill}` : "";

        if (isDel === 1) {
          if (sId) extractedBatchDeletedIds.push(sId);
          if (rawInt) extractedBatchDeletedIds.push(rawInt.toUpperCase());
          if (compKey) extractedBatchDeletedIds.push(compKey);
        } else {
          if (sId) extractedBatchUnmarkedIds.push(sId);
          if (rawInt) extractedBatchUnmarkedIds.push(rawInt.toUpperCase());
          if (compKey) extractedBatchUnmarkedIds.push(compKey);
          if (rawBill && !isPurchaseDoc) extractedBatchUnmarkedIds.push(rawBill.toUpperCase());
        }
      }
    }

    const mergedDeletedIds = Array.from(new Set([
      ...(Array.isArray(body.deletedIds) ? body.deletedIds : []),
      ...extractedBatchDeletedIds,
    ]));
    const deletedSetForFilter = new Set(mergedDeletedIds.map((e: any) => (e || "").toString().trim()));
    const mergedUnmarkedIds = Array.from(new Set([
      ...(Array.isArray(body.unmarkedIds) ? body.unmarkedIds : []),
      ...extractedBatchUnmarkedIds,
    ])).filter((u: any) => !deletedSetForFilter.has((u || "").toString().trim()));

    const nowMs = Date.now();
    const rawTs = body.timestamp ? parseInt(body.timestamp, 10) : 0;
    const normalizedTs = rawTs > 100000000000000 ? Math.floor(rawTs / 1000) : rawTs;
    const effectiveTs = Math.max(normalizedTs || 0, nowMs);

    const record: SignalRecord = {
      id: body.id || ("evt_" + nowMs + "_" + Math.random().toString(36).substring(2, 7)),
      storeToken,
      source: (body.source || "UNKNOWN").toUpperCase(),
      action: body.action || "DELTA_MUTATION",
      entityType: body.entityType || "",
      entityId: (body.entityId || "").trim(),
      financialYear: reqFy,
      fy: reqFy,
      timestamp: effectiveTs,
      serverReceivedAt: nowMs,
      deletedIds: mergedDeletedIds,
      unmarkedIds: mergedUnmarkedIds,
      delta: body.delta || null,
      payload: body.payload || {},
    };

    let channelData: ChannelData = {
      latest: null,
      events: [],
      tombstones: [],
    };

    if (context.env && context.env.SIGNAL_DB) {
      try {
        const db = context.env.SIGNAL_DB;
        await ensureSignalTables(db);

        const isPurchaseSignal = (record.entityType || "").toUpperCase().includes("PURCHASE") ||
          action.includes("PURCHASE");

        const effectiveDeletes: string[] = [...mergedDeletedIds];
        const effectiveUnmarks: string[] = [...mergedUnmarkedIds];
        if (isDeleteAction && record.entityId) {
          effectiveDeletes.push(record.entityId);
        } else if (!isDeleteAction) {
          if (record.entityId) effectiveUnmarks.push(record.entityId);
          if (record.payload && typeof record.payload === "object") {
            if (record.payload.billNo && !isPurchaseSignal) {
              effectiveUnmarks.push(record.payload.billNo.toString().trim());
            }
            if (record.payload.internalNo) {
              effectiveUnmarks.push(record.payload.internalNo.toString().trim());
            }
            if (record.payload.id) {
              effectiveUnmarks.push(record.payload.id.toString().trim());
            }
            if (record.payload.partyId && record.payload.billNo) {
              effectiveUnmarks.push(`${record.payload.partyId.toString().trim().toUpperCase()}_${record.payload.billNo.toString().trim()}`);
            }
          }
        }

        // Write atomically to relational signal_tombstones & signal_events first
        await applyAtomicTombstonesAndEvent(
          db,
          storeToken,
          record,
          effectiveDeletes,
          effectiveUnmarks,
          reqFy,
          effectiveTs
        );

        // Maintain signals compatibility blob as best-effort secondary store
        const row: any = await db.prepare("SELECT data FROM signals WHERE storeToken = ?").bind(storeToken).first();
        if (row && row.data) {
          try {
            channelData = JSON.parse(row.data);
          } catch (_) {}
        }

        if (!isOutboxBatch || !channelData.latest) {
          channelData.latest = record;
        } else {
          channelData.latest = {
            ...channelData.latest,
            timestamp: Math.max(channelData.latest.timestamp || 0, record.timestamp),
            serverReceivedAt: nowMs,
            deletedIds: Array.from(new Set([...(channelData.latest.deletedIds || []), ...mergedDeletedIds])),
            unmarkedIds: Array.from(new Set([...(channelData.latest.unmarkedIds || []), ...mergedUnmarkedIds])),
          };
        }

        if (!channelData.events) channelData.events = [];
        channelData.events.push(record);
        if (channelData.events.length > 200) {
          channelData.events = channelData.events.slice(channelData.events.length - 200);
        }

        if (!channelData.tombstones) channelData.tombstones = [];
        const tSet = new Set(channelData.tombstones);
        for (const u of effectiveUnmarks) {
          if (u && u.trim()) {
            const uk = u.trim();
            tSet.delete(uk);
            if (!uk.includes("_")) tSet.delete(uk.toUpperCase());
          }
        }
        for (const d of effectiveDeletes) {
          if (d && d.trim()) {
            const dk = d.trim();
            tSet.add(dk);
            if (!dk.includes("_")) tSet.add(dk.toUpperCase());
          }
        }
        channelData.tombstones = Array.from(tSet);

        await db.prepare(
          "INSERT INTO signals (storeToken, data, timestamp) VALUES (?, ?, ?) ON CONFLICT(storeToken) DO UPDATE SET data = excluded.data, timestamp = excluded.timestamp"
        ).bind(storeToken, JSON.stringify(channelData), nowMs).run();

        // SECTION 1: CLOUDFLARE D1 BATCH ENGINE FOR ERP_MASTER_SYNC
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
              const uAt = Math.max(parseInt(op.updated_at || 0, 10), nowMs);
              const isActionDelete = (op.action || "").toString().toUpperCase() === "DELETE";
              const isDel = (op.is_deleted === 1 || isActionDelete) ? 1 : 0;
              const rawData = op.data !== undefined ? op.data : op.bill_data;
              const bData = typeof rawData === "string" ? rawData : JSON.stringify(rawData || {});

              const stmt = db.prepare(
                "INSERT INTO erp_master_sync (sync_id, store_token, document_type, version, updated_at, is_deleted, bill_data) " +
                "VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7) " +
                "ON CONFLICT(sync_id) DO UPDATE SET " +
                "bill_data = CASE " +
                  "WHEN ?6 = 1 THEN CASE WHEN (?5 >= updated_at OR ?4 >= version) THEN ?7 ELSE bill_data END " +
                  "WHEN is_deleted = 1 THEN CASE WHEN (?4 > version AND ?5 > updated_at) THEN ?7 ELSE bill_data END " +
                  "WHEN (?5 >= updated_at OR ?4 > version) THEN ?7 ELSE bill_data END, " +
                "is_deleted = CASE " +
                  "WHEN ?6 = 1 THEN 1 " +
                  "WHEN is_deleted = 1 THEN CASE WHEN (?4 > version AND ?5 > updated_at) THEN 0 ELSE 1 END " +
                  "WHEN (?5 >= updated_at OR ?4 > version) THEN ?6 ELSE is_deleted END, " +
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

    return new Response(JSON.stringify({
      status: "SUCCESS",
      event: record,
      activeTombstonesCount: channelData.tombstones.length,
    }), {
      status: 200,
      headers: NO_CACHE_HEADERS,
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ status: "ERROR", message: err.toString() }), {
      status: 500,
      headers: NO_CACHE_HEADERS,
    });
  }
}

export async function onRequestGet(context: any) {
  try {
    const url = new URL(context.request.url);
    const storeToken = (url.searchParams.get("storeToken") || "").trim().toUpperCase();
    let lastSeenTs = parseInt(url.searchParams.get("lastSeenTs") || url.searchParams.get("since") || "0", 10);
    if (lastSeenTs > 100000000000000) lastSeenTs = Math.floor(lastSeenTs / 1000);
    const sinceSeq = parseInt(url.searchParams.get("since_seq") || "-1", 10);

    if (!storeToken) {
      return new Response(JSON.stringify({ status: "ERROR", message: "storeToken query param required" }), {
        status: 400,
        headers: NO_CACHE_HEADERS,
      });
    }

    // 🚀 SECTION 2: MARG-STYLE DETERMINISTIC SALE EVENT DELTAS
    if (sinceSeq >= 0 && context.env && context.env.SIGNAL_DB) {
      try {
        const db = context.env.SIGNAL_DB;
        await db.prepare(
          "CREATE TABLE IF NOT EXISTS sale_events (" +
          "seq INTEGER PRIMARY KEY AUTOINCREMENT, " +
          "store_token TEXT NOT NULL, " +
          "bill_id TEXT NOT NULL, " +
          "bill_no TEXT NOT NULL, " +
          "version INTEGER NOT NULL, " +
          "action TEXT NOT NULL, " +
          "status TEXT NOT NULL, " +
          "client_source TEXT NOT NULL, " +
          "payload TEXT NOT NULL, " +
          "created_at INTEGER NOT NULL)"
        ).run().catch(() => {});

        const deltaRows: any = await db.prepare(
          "SELECT seq, bill_id, bill_no, version, action, status, client_source, payload, created_at FROM sale_events " +
          "WHERE store_token = ? AND seq > ? ORDER BY seq ASC LIMIT 250"
        ).bind(storeToken, sinceSeq).all().catch(() => null);

        if (deltaRows && Array.isArray(deltaRows.results)) {
          const events = deltaRows.results.map((r: any) => ({
            seq: r.seq,
            bill_id: r.bill_id,
            bill_no: r.bill_no,
            version: r.version,
            action: r.action,
            status: r.status,
            client_source: r.client_source,
            created_at: r.created_at,
            sale_data: typeof r.payload === "string" ? JSON.parse(r.payload) : r.payload,
          }));
          const maxSeq = events.length > 0 ? events[events.length - 1].seq : sinceSeq;

          return new Response(JSON.stringify({
            status: "SUCCESS",
            events,
            max_seq: maxSeq,
            count: events.length,
          }), {
            status: 200,
            headers: NO_CACHE_HEADERS,
          });
        }
      } catch (err) {
        console.error("D1 Sale Deltas Read Exception:", err);
      }
    }

    let current: SignalRecord | null = null;
    const mutationMap = new Map<string, SignalRecord>();
    const tombSet = new Set<string>();

    // 1. PRIMARY ENGINE: CLOUDFLARE D1 (Atomic signal_tombstones + signal_events + signals blob)
    if (context.env && context.env.SIGNAL_DB) {
      try {
        const db = context.env.SIGNAL_DB;
        await ensureSignalTables(db);

        const atomicTombRows: any = await db.prepare(
          "SELECT tomb_key FROM signal_tombstones WHERE store_token = ?"
        ).bind(storeToken).all().catch(() => null);
        if (atomicTombRows && Array.isArray(atomicTombRows.results)) {
          for (const r of atomicTombRows.results) {
            if (r.tomb_key) tombSet.add(r.tomb_key.toString());
          }
        }

        const atomicEvtRows: any = await db.prepare(
          "SELECT event_json FROM signal_events WHERE store_token = ? AND timestamp > ? ORDER BY seq ASC LIMIT 200"
        ).bind(storeToken, lastSeenTs).all().catch(() => null);
        if (atomicEvtRows && Array.isArray(atomicEvtRows.results)) {
          for (const r of atomicEvtRows.results) {
            try {
              const ev: SignalRecord = typeof r.event_json === "string" ? JSON.parse(r.event_json) : r.event_json;
              if (ev && ev.id) {
                mutationMap.set(ev.id, ev);
                current = ev;
              }
            } catch (_) {}
          }
        }

        const row: any = await db.prepare("SELECT data, timestamp FROM signals WHERE storeToken = ?").bind(storeToken).first();
        if (row && row.data) {
          const chanData: ChannelData = JSON.parse(row.data);
          if (!current || (chanData.latest && chanData.latest.timestamp > current.timestamp)) {
            current = chanData.latest;
          }
          if (Array.isArray(chanData.events)) {
            for (const e of chanData.events) {
              if (e && e.timestamp > lastSeenTs && e.id && !mutationMap.has(e.id)) {
                mutationMap.set(e.id, e);
              }
            }
          }
          if (Array.isArray(chanData.tombstones)) {
            for (const t of chanData.tombstones) {
              if (t) tombSet.add(t);
            }
          }
        }
      } catch (d1Err) {
        console.error("D1 Read Exception:", d1Err);
      }
    }

    const mutations = Array.from(mutationMap.values()).sort((a, b) => (a.timestamp || 0) - (b.timestamp || 0));
    const tombstones = Array.from(tombSet);

    // Query D1 Master Sync for Delta Batch Operations
    let batchOperations: any[] = [];
    if (context.env && context.env.SIGNAL_DB) {
      try {
        const db = context.env.SIGNAL_DB;
        const deltaRows: any = await db.prepare(
          "SELECT sync_id, document_type, version, updated_at, is_deleted, bill_data FROM erp_master_sync WHERE store_token = ? AND updated_at > ? ORDER BY updated_at ASC LIMIT 250"
        ).bind(storeToken, lastSeenTs).all().catch(() => null);

        if (deltaRows && Array.isArray(deltaRows.results) && deltaRows.results.length > 0) {
          batchOperations = deltaRows.results.map((r: any) => ({
            sync_id: r.sync_id,
            document_type: r.document_type,
            version: r.version,
            updated_at: r.updated_at,
            is_deleted: r.is_deleted,
            action: r.is_deleted === 1 ? "DELETE" : "UPDATE",
            data: typeof r.bill_data === "string" ? JSON.parse(r.bill_data) : (r.bill_data || {}),
            bill_data: r.bill_data,
          }));
        }
      } catch (err) {
        console.error("D1 Delta Read Exception:", err);
      }
    }

    if (!current && batchOperations.length === 0 && mutations.length === 0 && tombstones.length === 0) {
      return new Response(JSON.stringify({ status: "SUCCESS", hasUpdate: false, event: null, mutations: [], events: [], tombstones: [], batch_operations: [] }), {
        status: 200,
        headers: NO_CACHE_HEADERS,
      });
    }

    const hasUpdate = (current && current.timestamp > lastSeenTs) || mutations.length > 0 || batchOperations.length > 0;

    return new Response(JSON.stringify({
      status: "SUCCESS",
      hasUpdate,
      event: (current && current.timestamp > lastSeenTs) ? current : (mutations.length > 0 ? mutations[mutations.length - 1] : null),
      mutations,
      events: mutations,
      tombstones,
      batch_operations: batchOperations,
      serverTime: Date.now(),
    }), {
      status: 200,
      headers: NO_CACHE_HEADERS,
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ status: "ERROR", message: err.toString() }), {
      status: 500,
      headers: NO_CACHE_HEADERS,
    });
  }
}
