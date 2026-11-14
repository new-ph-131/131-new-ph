# PHAROAH ERP — Three Issues Root-Cause Discovery & Complete Engineering Resolution

**Revision**: `#PH-REV-811 (FIX-NOBATCH-MULTI-MRP-FY-AND-PURCHASE-DELETE-SYNC)`  
**Base Commit**: `8beb64a`  
**Fix Commit**: `bbc3b2d`  

---

## 1. Executive Summary

This report provides the full forensic analysis and resolution of three critical issues in Pharoah ERP:
1. **Issue A**: Items with blank batch (`""`) and blank expiry (`""`) but different MRP values (e.g. Lot A: MRP 100, Lot B: MRP 50) disappeared or collapsed into a single lot upon transition to the next Financial Year.
2. **Issue B**: A Purchase created in the App, modified on the Web, and subsequently deleted on the Web remained visible in the App; also, rapid consecutive deletions (10–12 bills in 5s) dropped deletions or caused zombie resurrections.
3. **Issue C**: In the Web Sale item/batch selection dialog, only one blank-batch lot appeared when multiple blank-batch lots with different MRPs existed, whereas the App showed both.

---

## 2. Issue A & Issue C: Root Cause and Resolution

### Root Cause:
1. **Escaped Literal `\$` Interpolations (`lib/inventory_logic_center.dart`)**:
   In commit `8beb64a`, lines 57, 71, 73, 301, and 322 contained escaped dollar signs:
   `return "__NOBATCH__|\$normExp|\${mrp.toStringAsFixed(2)}|\${purRate.toStringAsFixed(2)}";`
   Because of `\$`, Dart treated this as a literal string rather than evaluating the variables!
   Consequently, every blank-batch lot produced the identical key:
   `"__NOBATCH__|$normExp|${mrp.toStringAsFixed(2)}|${purRate.toStringAsFixed(2)}"`
   When `WebBatchResolver.resolveBatchesForMedicine` stored them into a deduplicated map by `lotKey`, Lot B was discarded because Lot A already occupied that literal key (causing **Issue C**).
   Furthermore, `BatchSyncModule.getBatchSyncId` produced identical `syncId`s on D1, and `InventoryLogicCenter.rebuildAllInventory` merged them.
2. **Batch Deletion Matching Collateral Damage**:
   In `MasterSyncOrchestrator` and `BatchCascadeEngine.deleteBatchSafe`, deleting a blank-batch lot checked only `batch.trim().isEmpty`, wiping out ALL blank-batch lots for that medicine.

### Fix Implemented:
- Unescaped all literal `\$` in `makeLotKey`, `makeSyncKey`, and `rebuildAllInventory` in `lib/inventory_logic_center.dart`.
- Added `{String exp = '', double mrp = 0.0, double purRate = 0.0}` to `BatchCascadeEngine.deleteBatchSafe` and used `exactEmptyBatchLot: true`.
- In `MasterSyncOrchestrator`, isolated blank-batch delete envelopes using `exactEmptyBatchLot: true` and canonical `syncId`.
- In `FYTransferEngine.cascadeSingleYearStep`, preserved multi-MRP blank-batch lots with separate `openingQty` and `qty`.

---

## 3. Issue B: Purchase Deletion Synchronization & Burst Resilience

### Root Causes:
1. **Tombstone Unmark Poisoning**: Web modifying a purchase sent `DATA_SAVED` with `unmarkedIds: [id]`, saving `id` into `unmarked_tombstones_$companyId` without a timestamp. When Web subsequently deleted the purchase, App's `TombstoneEngine.sanitizeCloudTombstones` rejected the cloud tombstone because `id` was in `unmarked_tombstones`.
2. **FastPull Save-Gap**: When a bill was deleted from the cloud, `DeltaMergeEngine` returned `false` (no changes detected), so `FastPullEngine` never saved `purc.json` to disk, leaving the deleted bill intact in App local storage.
3. **Non-Atomic D1 Signals Table**: Rapidly deleting 10–12 bills in 5s caused concurrent read-modify-writes on the single-row JSON `signals` table in Cloudflare D1 worker (`functions/api/lab_signal.ts`), resulting in dropped events and truncation (`events.slice(-50)`).
4. **Stale UPDATE Auto-Rebasing**: D1 worker auto-rebased stale `UPDATE` events even after a bill had been deleted.

### Fix Implemented:
- Added timestamped `unmarked_registry_$companyId` in `TombstoneEngine` and implemented LWW comparison in `sanitizeCloudTombstones`: `if (cloudTs >= unmarkTs) sanitized.add(cleanK)`. Authoritative cloud deletions always override older unmarks.
- Added post-merge `purgeDeletedRecords*` sweep and record-count tracking in `FastPullEngine` so disk files are always saved and UI notified.
- Provisioned relational `signal_tombstones` and `signal_events` tables in Cloudflare D1 worker for atomic row-level inserts, and added sticky HTTP `410 GONE` guards to prevent resurrection.
- Added in-flight coalescing and queue drain loop in `SyncQueueManager`.

---

## 4. Verification & Testing

- **New Regression Test Suite**: `test/three_issues_independent_regression_test.dart` (9/9 passed).
- **All Existing Test Suites**: 25/25 passed.
- **Total**: 34/34 tests passed cleanly with zero regressions.
