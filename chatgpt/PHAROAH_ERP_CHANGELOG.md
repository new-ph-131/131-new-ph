# Pharoah ERP Changelog — Revision #PH-REV-811

### 1. Inventory & Batch Management (`lib/inventory_logic_center.dart`, `lib/logic/batch_cascade_engine.dart`)
- **Unescaped Lot Keys**: Removed escaped literal `\$` in `makeLotKey` and `makeSyncKey` so blank-batch lots evaluate distinct keys by MRP and purchase rate (`__NOBATCH__||100.00|70.00` vs `__NOBATCH__||50.00|35.00`).
- **Batch Deletion Isolation**: Updated `BatchCascadeEngine.deleteBatchSafe` to take optional `exp`, `mrp`, and `purRate` and pass `exactEmptyBatchLot: true` to prevent deleting unrelated blank-batch lots.
- **Traceability Screens**: Updated `lib/batch_master_view.dart`, `lib/web_live_sync/web_batch_master.dart`, and traceability screens to supply `exp`, `mrp`, `purRate` to `deleteBatchSafe`.

### 2. Multi-FY Carry-Forward & Rebuild (`lib/fy_transfer_engine.dart`)
- Verified `FYTransferEngine.cascadeSingleYearStep` maintains separate `openingQty` and `qty` for each distinct blank-batch MRP lot into the new Financial Year.

### 3. Tombstone & Sync Protocol (`lib/web_live_sync/sync_protocol/tombstone_engine.dart`, `fast_pull_engine.dart`, `app_sync_engine.dart`)
- **Timestamped Unmark Registry**: Added `getUnmarkedRegistry` and `saveUnmarkedRegistry` (`unmarked_registry_$companyId`) in `TombstoneEngine`.
- **LWW Override**: Updated `sanitizeCloudTombstones` so cloud tombstones with newer timestamps (`cloudTs >= unmarkTs`) override local unmarks.
- **FastPull Persistence Guarantee**: Added post-merge `purgeDeletedRecords*` sweep and core record-count tracking in `FastPullEngine` and `AppSyncEngine` to guarantee `purc.json` is updated on disk whenever deletions occur.

### 4. Edge D1 Ledger & Worker (`functions/api/lab_signal.ts`, `lib/sync_core/d1_sales_ledger_service.dart`)
- **Relational Tables**: Provisioned `signal_tombstones` and `signal_events` tables for atomic row-level mutation.
- **Sticky 410 Guard**: Added HTTP `410 GONE` sticky guard on deleted bills to prevent stale `UPDATE` resurrection.
- **Multi-Page Cursor**: Added `fetchSaleDeltasWithCursor` and delayed `commitSaleDeltaSeq` in `D1SalesLedgerService`.
- **Composite Key Fallthrough**: Fixed `isPurchaseDeleted` to check `cleanInt`, `compKey2`, and `compKey3` when primary ID is missing or non-matching.

### 5. Outbox Coalescing (`lib/sync_core/outbox/sync_queue_manager.dart`)
- Added `_inFlightFlush` lock and `while (_outboxBufferQueue.isNotEmpty)` drain loop to prevent dropping mutation triggers during rapid bursts of 10–12 consecutive deletes.

### 6. UI & Versioning
- Bumped revision to `#PH-REV-811 (FIX-NOBATCH-MULTI-MRP-FY-AND-PURCHASE-DELETE-SYNC)` in `web_top_bar.dart` and `web_recent_sidebar.dart`.
- Added secret-free deployment runner `colab_runner_811.py`.
