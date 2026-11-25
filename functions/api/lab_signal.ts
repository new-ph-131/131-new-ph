// FILE: functions/api/lab_signal.ts
// Cloudflare Pages Function: High-Capacity D1 SQL Edge Signal & Tombstone Resolution Bus (<30ms)
// Features: Single-Row Store Sync Meta Gate, Indexed Trim, Zero Warm DDL, Sticky Delete Guards.
// Revision: #PH-REV-814 (D1-ROWS-READ-QUOTA-FIX)

interface SignalRecord {
  id: string;
  storeToken: string;
  source: string;
  action: string;
  entityType?: string;
  entityId: string;
  deviceId?: string;
  financialYear?: string;
  fy?: string;
  timestamp: number;
  serverReceivedAt: number;
  deletedIds?: string[];
  unmarkedIds?: string[];
  delta?: any;
  payload?: any;
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

// Cold-start isolate flag so DDL runs once per worker lifecycle instead of on every GET poll
let _schemaReady = false;
let _schemaPromise: Promise<void> | null = null;

function inferFyFromDateStr(dateStr: any): string {
  if (!dateStr || typeof dateStr !== "string") return "";
  const dt = new Date(dateStr.trim());
  if (isNaN(dt.getTime())) return "";
  const y = dt.getUTCFullYear();
  const m = dt.getUTCMonth() + 1;
  if (m >= 4) {
    return `${y}-${String(y + 1).slice(-2)}`;
  }
  return `${y - 1}-${String(y).slice(-2)}`;
}

async function ensureSignalTablesOnce(db: any): Promise<void> {
  if (_schemaReady) return;
  if (_schemaPromise) return _schemaPromise;
  _schemaPromise = (async () => {
    try {
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
          "CREATE INDEX IF NOT EXISTS idx_signal_tombstones_store_updated ON signal_tombstones (store_token, updated_at)"
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
        db.prepare("CREATE INDEX IF NOT EXISTS idx_signal_events_seq ON signal_events (store_token, seq)"),
        db.prepare(
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
        ),
        db.prepare("CREATE INDEX IF NOT EXISTS idx_sale_events_seq ON sale_events (store_token, seq)"),
        db.prepare("CREATE INDEX IF NOT EXISTS idx_sale_events_bill ON sale_events (store_token, bill_id)"),
        db.prepare(
          "CREATE TABLE IF NOT EXISTS erp_master_sync (" +
          "sync_id TEXT PRIMARY KEY, " +
          "store_token TEXT NOT NULL, " +
          "document_type TEXT NOT NULL, " +
          "version INTEGER NOT NULL, " +
          "updated_at INTEGER NOT NULL, " +
          "is_deleted INTEGER NOT NULL, " +
          "bill_data TEXT NOT NULL)"
        ),
        db.prepare("DROP INDEX IF EXISTS idx_doc_type_updated"),
        db.prepare("CREATE INDEX IF NOT EXISTS idx_erp_master_sync_store_updated ON erp_master_sync (store_token, updated_at)"),
        db.prepare(
          "CREATE TABLE IF NOT EXISTS store_sync_meta (" +
          "store_token TEXT PRIMARY KEY, " +
          "last_signal_ts INTEGER NOT NULL DEFAULT 0, " +
          "last_batch_ts INTEGER NOT NULL DEFAULT 0, " +
          "last_tomb_ts INTEGER NOT NULL DEFAULT 0, " +
          "latest_seq INTEGER NOT NULL DEFAULT 0)"
        ),
      ]);
      _schemaReady = true;
    } catch (_) {
      // Allow retry on next request if transient error
    } finally {
      _schemaPromise = null;
    }
  })();
  return _schemaPromise;
}

function buildMetaUpsertStmt(
  db: any,
  storeToken: string,
  signalTs: number,
  batchTs: number,
  tombTs: number,
  latestSeq: number
) {
  return db.prepare(
    "INSERT INTO store_sync_meta (store_token, last_signal_ts, last_batch_ts, last_tomb_ts, latest_seq) " +
    "VALUES (?, ?, ?, ?, ?) " +
    "ON CONFLICT(store_token) DO UPDATE SET " +
    "last_signal_ts = CASE WHEN excluded.last_signal_ts > store_sync_meta.last_signal_ts THEN excluded.last_signal_ts ELSE store_sync_meta.last_signal_ts END, " +
    "last_batch_ts = CASE WHEN excluded.last_batch_ts > store_sync_meta.last_batch_ts THEN excluded.last_batch_ts ELSE store_sync_meta.last_batch_ts END, " +
    "last_tomb_ts = CASE WHEN excluded.last_tomb_ts > store_sync_meta.last_tomb_ts THEN excluded.last_tomb_ts ELSE store_sync_meta.last_tomb_ts END, " +
    "latest_seq = CASE WHEN excluded.latest_seq > store_sync_meta.latest_seq THEN excluded.latest_seq ELSE store_sync_meta.latest_seq END"
  ).bind(storeToken, signalTs, batchTs, tombTs, latestSeq);
}

async function applyAtomicTombstonesAndEvent(
  db: any,
  storeToken: string,
  sigRecord: SignalRecord,
  deletedKeys: string[],
  unmarkedKeys: string[],
  fy: string,
  eventTs: number,
  extraBatchTs = 0,
  extraLatestSeq = 0
): Promise<number> {
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
        "fy = CASE WHEN excluded.fy != '' THEN excluded.fy ELSE signal_tombstones.fy END " +
        "WHERE excluded.updated_at > signal_tombstones.updated_at OR (excluded.fy != '' AND excluded.fy != signal_tombstones.fy)"
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

  // Update single-row sync meta atomically so idle GET polls only read 1 row
  const tombMetaTs = delSet.size > 0 ? eventTs : 0;
  stmts.push(buildMetaUpsertStmt(db, storeToken, sigRecord.timestamp, extraBatchTs, tombMetaTs, extraLatestSeq));

  await db.batch(stmts).catch(() => {});

  // Occasional indexed trim (~2% of writes) replaces expensive per-POST NOT IN full-store scan
  if (Math.random() < 0.02) {
    try {
      const cutoffRow: any = await db.prepare(
        "SELECT seq FROM signal_events WHERE store_token = ? ORDER BY seq DESC LIMIT 1 OFFSET 300"
      ).bind(storeToken).first().catch(() => null);
      if (cutoffRow && cutoffRow.seq) {
        await db.prepare(
          "DELETE FROM signal_events WHERE store_token = ? AND seq <= ?"
        ).bind(storeToken, cutoffRow.seq).run().catch(() => {});
      }
    } catch (_) {}
  }

  return delSet.size;
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
    const bodyDeviceId = (body.device_id || body.deviceId || "").toString().trim();

    if (context.env && context.env.SIGNAL_DB) {
      await ensureSignalTablesOnce(context.env.SIGNAL_DB);
    }

    // 🚀 SECTION 2: MARG-STYLE DETERMINISTIC SALE/PURCHASE EVENT LEDGER (D1 AUTO-INCREMENT SEQ)
    if (body.sale_event && typeof body.sale_event === "object") {
      try {
        if (context.env && context.env.SIGNAL_DB) {
          const db = context.env.SIGNAL_DB;

          const ev = body.sale_event;
          const billId = (ev.bill_id || ev.id || "").toString().trim();
          const billNo = (ev.bill_no || ev.billNo || "").toString().trim();
          const incomingVer = parseInt(ev.version || 1, 10);
          const evAction = (ev.action || "INSERT").toString().toUpperCase();
          const evStatus = (ev.status || (evAction === "CANCEL" ? "Cancelled" : (evAction === "DELETE" ? "Deleted" : "Active"))).toString();
          const clientSource = (ev.client_source || body.source || "UNKNOWN").toString();
          const evPayloadObj = typeof ev.payload === "string" ? JSON.parse(ev.payload || "{}") : (ev.payload || ev);
          const evFy = (
            reqFy ||
            (evPayloadObj && (evPayloadObj.fy || evPayloadObj.originalFy)) ||
            inferFyFromDateStr(evPayloadObj && evPayloadObj.date) ||
            ""
          ).toString().trim();
          const rawDocType = ((evPayloadObj && evPayloadObj.doc_type) || body.entityType || "").toString().trim().toUpperCase();
          const upperBodyAction = (body.action || "").toString().toUpperCase();
          const isSaleChallanEvt = rawDocType === "SALE_CHALLAN" || upperBodyAction.includes("SALE_CHALLAN");
          const isPurchaseChallanEvt = rawDocType === "PURCHASE_CHALLAN" || upperBodyAction.includes("PURCHASE_CHALLAN");
          const isPurchaseEvt = !isSaleChallanEvt && !isPurchaseChallanEvt && (
            rawDocType === "PURCHASE" ||
            upperBodyAction.includes("PURCHASE") ||
            (evPayloadObj && evPayloadObj.internalNo !== undefined)
          );
          const resolvedEntityType = isSaleChallanEvt
            ? "SALE_CHALLAN"
            : isPurchaseChallanEvt
              ? "PURCHASE_CHALLAN"
              : isPurchaseEvt
                ? "PURCHASE"
                : "SALE";
          const isPurchaseStyleDoc = isPurchaseEvt || isPurchaseChallanEvt;
          if (evPayloadObj && typeof evPayloadObj === "object") {
            if (evFy && !evPayloadObj.fy) evPayloadObj.fy = evFy;
            if (!evPayloadObj.doc_type) evPayloadObj.doc_type = resolvedEntityType;
          }
          const payload = JSON.stringify(evPayloadObj || {});

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

          const newSeq = Number(insertRes?.meta?.last_row_id || 0);

          const delIds: string[] = Array.isArray(body.deletedIds) ? body.deletedIds : [];
          const unmIds: string[] = Array.isArray(body.unmarkedIds) ? body.unmarkedIds : [];

          const atomicDelKeys: string[] = [];
          const atomicUnmKeys: string[] = [];
          if (evAction === "DELETE") {
            if (billId) atomicDelKeys.push(billId);
            if (billNo && !isPurchaseStyleDoc) {
              if (evFy) atomicDelKeys.push(`${evFy}::${billNo.toUpperCase()}`);
              else atomicDelKeys.push(billNo.toUpperCase());
            }
            if (isPurchaseStyleDoc && evPayloadObj && typeof evPayloadObj === "object") {
              const pParty = (evPayloadObj.partyId || "").toString().trim().toUpperCase();
              const pBill = (evPayloadObj.billNo || "").toString().trim();
              const pInt = (evPayloadObj.internalNo || "").toString().trim().toUpperCase();
              const effEvFy = evFy || inferFyFromDateStr(evPayloadObj.date);
              if (pInt) {
                if (effEvFy) atomicDelKeys.push(`${effEvFy}::${pInt}`);
                else atomicDelKeys.push(pInt);
              }
              if (pParty && pBill) {
                const c2 = `${pParty}_${pBill}`;
                if (effEvFy) atomicDelKeys.push(`${effEvFy}::${c2}`);
                else atomicDelKeys.push(c2);
                if (pInt) {
                  const c3 = `${pParty}_${pBill}_${pInt}`;
                  if (effEvFy) atomicDelKeys.push(`${effEvFy}::${c3}`);
                  else atomicDelKeys.push(c3);
                }
              }
            }
            for (const d of delIds) {
              if (d && typeof d === "string" && d.trim()) atomicDelKeys.push(d.trim());
            }
          } else {
            if (billId) atomicUnmKeys.push(billId);
            if (billNo && !isPurchaseStyleDoc) {
              atomicUnmKeys.push(billNo);
              atomicUnmKeys.push(billNo.toUpperCase());
              if (evFy) atomicUnmKeys.push(`${evFy}::${billNo.toUpperCase()}`);
            }
            if (isPurchaseStyleDoc && evPayloadObj && typeof evPayloadObj === "object") {
              const pParty = (evPayloadObj.partyId || "").toString().trim().toUpperCase();
              const pBill = (evPayloadObj.billNo || "").toString().trim();
              const pInt = (evPayloadObj.internalNo || "").toString().trim().toUpperCase();
              const effEvFy = evFy || inferFyFromDateStr(evPayloadObj.date);
              if (pInt) {
                atomicUnmKeys.push(pInt);
                if (effEvFy) atomicUnmKeys.push(`${effEvFy}::${pInt}`);
              }
              if (pParty && pBill) {
                const c2 = `${pParty}_${pBill}`;
                atomicUnmKeys.push(c2);
                if (effEvFy) atomicUnmKeys.push(`${effEvFy}::${c2}`);
                if (pInt) {
                  const c3 = `${pParty}_${pBill}_${pInt}`;
                  atomicUnmKeys.push(c3);
                  if (effEvFy) atomicUnmKeys.push(`${effEvFy}::${c3}`);
                }
              }
            }
            for (const u of unmIds) {
              if (u && typeof u === "string" && u.trim()) atomicUnmKeys.push(u.trim());
            }
          }

          const sigRecord: SignalRecord = {
            id: "evt_" + nowMs + "_" + Math.random().toString(36).substring(2, 7),
            storeToken,
            source: clientSource.toUpperCase().includes("WEB") ? "WEB" : (clientSource.toUpperCase().includes("APP") ? "APP" : clientSource.toUpperCase()),
            action: body.action || evAction,
            entityType: resolvedEntityType,
            entityId: billId,
            deviceId: bodyDeviceId || undefined,
            financialYear: evFy,
            fy: evFy,
            timestamp: nowMs,
            serverReceivedAt: nowMs,
            deletedIds: evAction === "DELETE" ? (atomicDelKeys.length > 0 ? atomicDelKeys : (billId ? [billId] : [])) : [],
            unmarkedIds: evAction !== "DELETE" ? atomicUnmKeys : [],
            payload: ev.payload || {},
          };

          await applyAtomicTombstonesAndEvent(
            db,
            storeToken,
            sigRecord,
            atomicDelKeys,
            atomicUnmKeys,
            evFy,
            nowMs,
            0,
            newSeq
          );

          return new Response(JSON.stringify({
            status: "SUCCESS",
            seq: newSeq || nowMs,
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

    const extractedBatchDeletedIds: string[] = [];
    const extractedBatchUnmarkedIds: string[] = [];

    if (body.operations && Array.isArray(body.operations)) {
      for (const op of body.operations) {
        const sId = (op.sync_id || "").toString().trim();
        const isActionDelete = (op.action || "").toString().toUpperCase() === "DELETE";
        const isDel = (op.is_deleted === 1 || isActionDelete) ? 1 : 0;
        const dType = (op.document_type || "SALE").toString().toUpperCase();
        const isPurchaseDoc = dType === "PURCHASE" || dType === "PURCHASE_CHALLAN";
        const rawPayload = op.bill_data || op.data || {};
        const rawBill = (rawPayload.billNo || "").toString().trim();
        const rawParty = (rawPayload.partyId || "").toString().trim();
        const rawInt = (rawPayload.internalNo || "").toString().trim().toUpperCase();
        const opFy = (op.fy || rawPayload.fy || reqFy || inferFyFromDateStr(rawPayload.date) || "").toString().trim();
        const compKey = (rawParty && rawBill) ? `${rawParty.toUpperCase()}_${rawBill}` : "";
        const compKey3 = (rawParty && rawBill && rawInt) ? `${rawParty.toUpperCase()}_${rawBill}_${rawInt}` : "";
        const scopedInt = (rawInt && opFy) ? `${opFy}::${rawInt}` : "";
        const scopedComp2 = (compKey && opFy) ? `${opFy}::${compKey}` : "";
        const scopedComp3 = (compKey3 && opFy) ? `${opFy}::${compKey3}` : "";
        const scopedBill = (rawBill && opFy) ? `${opFy}::${rawBill.toUpperCase()}` : "";

        if (isDel === 1) {
          if (sId) extractedBatchDeletedIds.push(sId);
          if (scopedInt) extractedBatchDeletedIds.push(scopedInt);
          else if (rawInt) extractedBatchDeletedIds.push(rawInt);
          if (scopedComp2) extractedBatchDeletedIds.push(scopedComp2);
          else if (compKey) extractedBatchDeletedIds.push(compKey);
          if (scopedComp3) extractedBatchDeletedIds.push(scopedComp3);
          else if (compKey3) extractedBatchDeletedIds.push(compKey3);
          if (rawBill && !isPurchaseDoc) {
            if (scopedBill) extractedBatchDeletedIds.push(scopedBill);
            else extractedBatchDeletedIds.push(rawBill.toUpperCase());
          }
        } else {
          if (sId) extractedBatchUnmarkedIds.push(sId);
          if (rawInt) extractedBatchUnmarkedIds.push(rawInt);
          if (scopedInt) extractedBatchUnmarkedIds.push(scopedInt);
          if (compKey) extractedBatchUnmarkedIds.push(compKey);
          if (scopedComp2) extractedBatchUnmarkedIds.push(scopedComp2);
          if (compKey3) extractedBatchUnmarkedIds.push(compKey3);
          if (scopedComp3) extractedBatchUnmarkedIds.push(scopedComp3);
          if (rawBill && !isPurchaseDoc) {
            extractedBatchUnmarkedIds.push(rawBill.toUpperCase());
            if (scopedBill) extractedBatchUnmarkedIds.push(scopedBill);
          }
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
    // Clamp absurd future client clocks (max +5s ahead of server) so meta timestamps stay sane
    const effectiveTs = normalizedTs > 0 ? Math.min(Math.max(normalizedTs, nowMs), nowMs + 5000) : nowMs;

    const record: SignalRecord = {
      id: body.id || ("evt_" + nowMs + "_" + Math.random().toString(36).substring(2, 7)),
      storeToken,
      source: (body.source || "UNKNOWN").toUpperCase(),
      action: body.action || "DELTA_MUTATION",
      entityType: body.entityType || "",
      entityId: (body.entityId || "").trim(),
      deviceId: bodyDeviceId || undefined,
      financialYear: reqFy,
      fy: reqFy,
      timestamp: effectiveTs,
      serverReceivedAt: nowMs,
      deletedIds: mergedDeletedIds,
      unmarkedIds: mergedUnmarkedIds,
      delta: body.delta || null,
      payload: body.payload || {},
    };

    let activeDeletesInPost = 0;

    if (context.env && context.env.SIGNAL_DB) {
      try {
        const db = context.env.SIGNAL_DB;

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

        // SECTION 1: CLOUDFLARE D1 BATCH ENGINE FOR ERP_MASTER_SYNC
        let maxBatchOpTs = 0;
        const sqlStatements: any[] = [];
        if (body.operations && Array.isArray(body.operations) && body.operations.length > 0) {
          for (const op of body.operations) {
            const sId = (op.sync_id || "").toString().trim();
            if (!sId) continue;
            const dType = (op.document_type || "SALE").toString().toUpperCase();
            const ver = parseInt(op.version || 1, 10);
            const uAt = Math.max(parseInt(op.updated_at || 0, 10), nowMs);
            if (uAt > maxBatchOpTs) maxBatchOpTs = uAt;
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
              "updated_at = CASE WHEN ?5 > updated_at THEN ?5 ELSE updated_at END " +
              "WHERE " +
                "(?6 = 1 AND (is_deleted != 1 OR ?4 > version OR (?7 != bill_data AND (?5 >= updated_at OR ?4 >= version)))) " +
                "OR (is_deleted = 1 AND ?6 = 0 AND ?4 > version AND ?5 > updated_at) " +
                "OR (is_deleted = 0 AND ?6 = 0 AND ((?4 > version) OR ((?5 >= updated_at OR ?4 > version) AND (?7 != bill_data OR store_token != ?2 OR document_type != ?3))))"
            ).bind(sId, storeToken, dType, ver, uAt, isDel, bData);
            sqlStatements.push(stmt);
          }
        }

        // Write erp_master_sync first if present, then atomic tombstones + signal event + meta
        if (sqlStatements.length > 0) {
          try {
            await db.batch(sqlStatements);
          } catch (batchErr) {
            console.error("D1 Master Sync Batch Exception:", batchErr);
          }
        }

        const isOutboxBatch = (body.source || "").toString().toUpperCase() === "OUTBOX_BATCH";
        if (!isOutboxBatch || sqlStatements.length > 0 || effectiveDeletes.length > 0 || effectiveUnmarks.length > 0) {
          activeDeletesInPost = await applyAtomicTombstonesAndEvent(
            db,
            storeToken,
            record,
            effectiveDeletes,
            effectiveUnmarks,
            reqFy,
            effectiveTs,
            maxBatchOpTs,
            0
          );
        }
      } catch (d1Err) {
        console.error("D1 Write Exception:", d1Err);
      }
    }

    return new Response(JSON.stringify({
      status: "SUCCESS",
      event: record,
      activeTombstonesCount: activeDeletesInPost,
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

async function backfillStoreSyncMeta(db: any, storeToken: string) {
  const [sigMax, batchMax, tombMax, seqMax]: any[] = await Promise.all([
    db.prepare("SELECT COALESCE(MAX(timestamp), 0) AS m FROM signal_events WHERE store_token = ?").bind(storeToken).first().catch(() => null),
    db.prepare("SELECT COALESCE(MAX(updated_at), 0) AS m FROM erp_master_sync WHERE store_token = ?").bind(storeToken).first().catch(() => null),
    db.prepare("SELECT COALESCE(MAX(updated_at), 0) AS m FROM signal_tombstones WHERE store_token = ?").bind(storeToken).first().catch(() => null),
    db.prepare("SELECT COALESCE(MAX(seq), 0) AS m FROM sale_events WHERE store_token = ?").bind(storeToken).first().catch(() => null),
  ]);
  const sTs = Number(sigMax?.m || 0);
  const bTs = Number(batchMax?.m || 0);
  const tTs = Number(tombMax?.m || 0);
  const lSeq = Number(seqMax?.m || 0);
  await buildMetaUpsertStmt(db, storeToken, sTs, bTs, tTs, lSeq).run().catch(() => {});
  return { last_signal_ts: sTs, last_batch_ts: bTs, last_tomb_ts: tTs, latest_seq: lSeq };
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

    if (!context.env || !context.env.SIGNAL_DB) {
      return new Response(JSON.stringify({ status: "SUCCESS", hasUpdate: false, event: null, mutations: [], events: [], tombstones: [], batch_operations: [], serverTime: Date.now() }), {
        status: 200,
        headers: NO_CACHE_HEADERS,
      });
    }

    const db = context.env.SIGNAL_DB;
    await ensureSignalTablesOnce(db);

    // 1-row gate check before touching any heavy table
    let metaRow: any = await db.prepare(
      "SELECT last_signal_ts, last_batch_ts, last_tomb_ts, latest_seq FROM store_sync_meta WHERE store_token = ?"
    ).bind(storeToken).first().catch(() => null);

    if (!metaRow) {
      metaRow = await backfillStoreSyncMeta(db, storeToken);
    }

    const metaSignalTs = Number(metaRow.last_signal_ts || 0);
    const metaBatchTs = Number(metaRow.last_batch_ts || 0);
    const metaTombTs = Number(metaRow.last_tomb_ts || 0);
    const metaLatestSeq = Number(metaRow.latest_seq || 0);

    // 🚀 SECTION 2: MARG-STYLE DETERMINISTIC SALE EVENT DELTAS
    if (sinceSeq >= 0) {
      try {
        if (metaLatestSeq <= sinceSeq) {
          return new Response(JSON.stringify({
            status: "SUCCESS",
            events: [],
            max_seq: sinceSeq,
            count: 0,
          }), {
            status: 200,
            headers: NO_CACHE_HEADERS,
          });
        }

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

    const needTombstones = metaTombTs > lastSeenTs;
    const needSignals = metaSignalTs > lastSeenTs;
    const needBatch = metaBatchTs > lastSeenTs;

    // Fast 1-row idle exit: nothing changed since lastSeenTs
    if (!needTombstones && !needSignals && !needBatch) {
      return new Response(JSON.stringify({
        status: "SUCCESS",
        hasUpdate: false,
        event: null,
        mutations: [],
        events: [],
        tombstones: [],
        batch_operations: [],
        serverTime: Date.now(),
      }), {
        status: 200,
        headers: NO_CACHE_HEADERS,
      });
    }

    let current: SignalRecord | null = null;
    const mutationMap = new Map<string, SignalRecord>();
    const tombSet = new Set<string>();
    let batchOperations: any[] = [];

    const [atomicTombRows, atomicEvtRows, deltaRows] = await Promise.all([
      needTombstones
        ? db.prepare(
            "SELECT tomb_key FROM signal_tombstones WHERE store_token = ? AND updated_at > ? ORDER BY updated_at ASC LIMIT 500"
          ).bind(storeToken, lastSeenTs).all().catch(() => null)
        : Promise.resolve(null),
      needSignals
        ? db.prepare(
            "SELECT event_json FROM signal_events WHERE store_token = ? AND timestamp > ? ORDER BY timestamp ASC, seq ASC LIMIT 200"
          ).bind(storeToken, lastSeenTs).all().catch(() => null)
        : Promise.resolve(null),
      needBatch
        ? db.prepare(
            "SELECT sync_id, document_type, version, updated_at, is_deleted, bill_data FROM erp_master_sync WHERE store_token = ? AND updated_at > ? ORDER BY updated_at ASC LIMIT 250"
          ).bind(storeToken, lastSeenTs).all().catch(() => null)
        : Promise.resolve(null),
    ]);

    if (atomicTombRows && Array.isArray(atomicTombRows.results)) {
      for (const r of atomicTombRows.results) {
        if (r.tomb_key) tombSet.add(r.tomb_key.toString());
      }
    }

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

    const mutations = Array.from(mutationMap.values()).sort((a, b) => (a.timestamp || 0) - (b.timestamp || 0));
    const tombstones = Array.from(tombSet);

    if (!current && batchOperations.length === 0 && mutations.length === 0 && tombstones.length === 0) {
      return new Response(JSON.stringify({
        status: "SUCCESS",
        hasUpdate: false,
        event: null,
        mutations: [],
        events: [],
        tombstones: [],
        batch_operations: [],
        serverTime: Date.now(),
      }), {
        status: 200,
        headers: NO_CACHE_HEADERS,
      });
    }

    const hasUpdate = (current !== null && current.timestamp > lastSeenTs) || mutations.length > 0 || batchOperations.length > 0;

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
