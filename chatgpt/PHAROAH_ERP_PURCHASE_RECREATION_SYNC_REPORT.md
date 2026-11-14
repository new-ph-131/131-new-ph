# PHAROAH ERP — App to Web Purchase Re-Creation Sync Failure
## Autonomous Root-Cause Investigation, Minimal Fix & Regression Verification Report

**Repository:** `new-ph-131/131-new-ph` (Branch: `main`)  
**Scope:** App → Cloudflare D1 / Edge Worker → Google Drive Snapshot → Web Purchase Sync Pipeline

---

## 1. Problem Statement & Observed Live Behaviour

1. **First Create (Working):** Creating a Purchase Entry for **Party X** in the Android App successfully displays it in the App Purchase Register and syncs it to the Web Purchase Register.
2. **Delete (Working):** Deleting that Purchase Entry from the Android App removes it from both the App and Web Purchase Registers.
3. **Re-Create (Failing Before Fix):** Creating a new Purchase Entry for **Party X** in the Android App after deleting the first one displays the new entry on the App Purchase Register, **but it never appears in the Web Purchase Register**.
4. **Reference Workflow (Working & Preserved):** Sale's equivalent `Create -> Delete -> Re-create` workflow works on both App and Web and must remain intact.

---

## 2. Full End-to-End Purchase Lifecycle & Root Causes (Compared Against Working Sale Workflow)

### Step A — Why Re-Created Purchases Collide with Deleted Keys
In `PharoahNumberingEngine.getNextNumber` (`lib/logic/pharoah_numbering_engine.dart`), series numbers use **gap-filling** over active records (`currentList: ph.purchases`).
- Purchase #1 gets `id = id1`, `internalNo = "PUR-1"`, supplier `billNo = "100"`, `partyId = "P1"`.
- When Purchase #1 is deleted, `ph.purchases` no longer contains `"PUR-1"`, AND gravestones/tombstones are recorded on **both** immutable UUID (`id1`) and **secondary/composite keys** (`2026-27::PUR-1`, `2026-27::P1_100`, `2026-27::P1_100_PUR-1`).
- When Purchase #2 is created for Party X in `PharoahManager.finalizePurchase` (`lib/pharoah_manager.dart`), it receives a **brand-new UUID `id2 != id1`**, `version = 1`, `updatedAt = T_new`, and **reuses `internalNo = "PUR-1"`** (plus `P1_100` if the supplier bill number is also re-entered).

### Step B — Exact Differences Between Sale (Working) and Purchase (Broken)

1. **`WebRealtimeCoordinator.start` (`lib/realtime_signaling/coordinators/web_realtime_coordinator.dart`)**
   - `AppRealtimeCoordinator` unmarks `event.unmarkedIds` in **both** `TombstoneEngine` and `D1SalesLedgerService.unmarkPermanentlyDeleted`.
   - `WebRealtimeCoordinator` previously called `webManager.unmarkDeletedId(u)` **only**, never clearing `D1SalesLedgerService._permanentDeletedKeys`, `_knownBillVersions` (`999999`), or uppercase composite variants.

2. **`D1SalesLedgerService.applyEventsToLocalPurchases` (`lib/sync_core/d1_sales_ledger_service.dart`)**
   - `applyEventsToLocalSales` does **not** gate active events with `isBillDeleted` or `99999`; it unmarks `incomingSale` and merges it.
   - `applyEventsToLocalPurchases` previously executed `if (isPurchaseDeleted(incomingPur.id, incomingPur.partyId, incomingPur.billNo, incomingPur.internalNo, effFy)) continue;` **before** calling `unmarkPurchasePermanentlyDeleted`. Because `2026-27::PUR-1` (from deleted `id1`) was still in `_permanentDeletedKeys`, `id2` was skipped on both live delta sync and cold chronological replay (`DELETE id1` followed by `INSERT id2`).
   - Additionally, `unmarkPurchasePermanentlyDeleted` did not clear uppercase variants (`compKey2Upper` / `compKey3Upper`) even though `isPurchaseDeleted` checked them.

3. **`MasterSyncOrchestrator.dispatchBatchOperations` (`lib/sync_core/orchestrator/master_sync_orchestrator.dart`)**
   - For `SALE` (`isDeleted == 0`), both App and Web immediately unmark and call `SalesSyncModule.mergeIncomingSaleEnvelope`.
   - For `PURCHASE` (`isDeleted == 0`), both App and Web checked `D1SalesLedgerService.isPurchaseDeleted(envelope.syncId, pId, bNo, iNo, targetFy)` **before** `unmarkPurchasePermanentlyDeleted`, dropping `id2` whenever `id1`'s `PUR-1` or `PARTY_billNo` remained in `_permanentDeletedKeys`.

4. **`PurchaseSyncModule.applyPurchaseMutation` (`lib/sync_core/modules/purchase_sync_module.dart`)**
   - Previously blocked active `incoming` records (`id2 != id1`) using secondary-key `isPurchaseDeleted` / `getPurchaseKnownVersion` (`999999`) checks before unmarking.

5. **Snapshot & Fallback Merge Guards (`PharoahWebManager`, `DeltaMergeEngine`, `FastPullEngine`, `AppSyncEngine`, `MultiFyCloudVault`)**
   - `_parseDownloadedFiles` (`purc.json`), `_extractAndSyncFyVaultFromCloud`, `DeltaMergeEngine.processCloudData`, `FastPullEngine`, `AppSyncEngine`, and `MultiFyCloudVault` called timestamp-less `D1SalesLedgerService.isPurchaseDeleted(...)`. Even when `p.updatedAt > secDelTs` (and `_parseDownloadedFiles` explicitly intended to accept newer re-created records), `D1SalesLedgerService.isPurchaseDeleted` returned `true` and dropped `id2`, and `_parseDownloadedFiles` failed to remove stale keys from `localTombstoneRegistry`.

6. **Cloudflare Worker D1 Signal/Outbox Batch Handler (`functions/api/lab_signal.ts`) & `PharoahWebManager.purgeDeletedIds`**
   - In `JSON_BATCH_MUTATION`, `SyncQueueManager` sends `PURCHASE` payloads without top-level `fy`. `lab_signal.ts` extracted unscoped `PUR-1` and `PARTY_billNo` (omitting `${fy}::` scoping and `compKey3` `${fy}::PARTY_billNo_PUR-1`), leaving FY-scoped gravestones intact in D1 `signal_tombstones` / `signals.tombstones`.
   - When Web polled `onTombstonesReceived` every 2s, `PharoahWebManager.purgeDeletedIds` deleted any purchase matching `scopedINo` / `scopedComp` even when its freshly unmarked `id2` was **not** in `edgeTombstones`.

---

## 3. Implemented Minimal Fix (Summary by File)

| File | Change Summary |
| :--- | :--- |
| `lib/sync_core/d1_sales_ledger_service.dart` | Added `_permanentDeletedTimestamps` tracking (memory + `SharedPreferences`), `isPurchaseIdDeleted`, `getPurchaseSecondaryDeleteTimestamp`, `getPurchaseIdKnownVersion`, optional `recordUpdatedAt` parameter on `isPurchaseDeleted` (preserving strict `#PH-REV-811` behaviour when omitted or older, blocking deleted UUIDs forever, and allowing newer distinct UUIDs `recordUpdatedAt > delTs`), full uppercase key cleanup in `unmarkPurchasePermanentlyDeleted`, and UUID-scoped gating before unmark in `applyEventsToLocalPurchases`. |
| `lib/sync_core/orchestrator/master_sync_orchestrator.dart` | In both App and Web `PURCHASE` dispatch (`isDeleted == 0`), check `isPurchaseIdDeleted(envelope.syncId)` (never resurrecting deleted UUIDs) and secondary timestamp guard only for non-`INSERT` stale updates; allow fresh `INSERT` / newer re-creations to unmark secondary keys (`D1SalesLedgerService`, `TombstoneEngine`, `PharoahWebManager.unmarkDeletedId` with `fy` & uppercase variants) before `PurchaseSyncModule.mergeIncomingPurchaseEnvelope`. Pass `envelope.updatedAt` on `DELETE`. |
| `lib/sync_core/modules/purchase_sync_module.dart` | Use `isPurchaseIdDeleted` / `getPurchaseIdKnownVersion` + secondary delete timestamp comparison when `incoming.id` is non-empty (falling back to full `isPurchaseDeleted` for legacy empty-ID snapshots), and avoid poisoning `PUR-1` if an active newer distinct entity already holds it. |
| `lib/realtime_signaling/coordinators/web_realtime_coordinator.dart` | Mirror `AppRealtimeCoordinator`: on `event.unmarkedIds`, clear both `webManager.unmarkDeletedId(..., fy: targetFy)` and `D1SalesLedgerService.unmarkPermanentlyDeleted(..., targetFy)`. |
| `lib/web_live_sync/pharoah_web_manager.dart` | Add optional `{String? fy}` to `unmarkDeletedId`; protect freshly unmarked distinct `p.id` in `purgeDeletedIds` from stale secondary-key wipes (while still purging exact deleted IDs immediately); pass `p.updatedAt` to `isPurchaseDeleted` & clean `localTombstoneRegistry` / `D1SalesLedgerService` when newer re-created records arrive in `_parseDownloadedFiles`, `_extractAndSyncFyVaultFromCloud`, and `_harvestD1EdgeDeltas`. |
| `lib/web_live_sync/sync_protocol/delta_merge_engine.dart` | Pass `cloudTimestamp` to `isPurchaseDeleted`, unmark stale secondary keys when `cloudTimestamp > secDelTs` for active non-deleted records, and pass delete timestamp `delTs` when recording tombstones. |
| `lib/realtime_signaling/engines/fast_pull_engine.dart` | Check `isPurchaseIdDeleted` before unmarking `INSERT`/`UPDATE` events (`newUnmarkKeys`), and pass `updatedAt` + `getPurchaseIdKnownVersion` in `applyUniversalD1Shield`. |
| `lib/web_live_sync/app_sync_engine.dart` | Check `isPurchaseIdDeleted` (matching Sale's UUID-only check) and unmark secondary keys in `D1SalesLedgerService` alongside `localRegistry`/`localTombstones`. |
| `lib/sync_core/multi_fy_cloud_vault.dart` | Pass `recUpd` timestamp into `D1SalesLedgerService.isPurchaseDeleted`. |
| `lib/pharoah_manager.dart` | Use `getPurchaseIdKnownVersion(pId, currentFY)` and pass `fy: currentFY` on `onPurchaseSaved`, plus pass `p.updatedAt` on disk reload filters. |
| `functions/api/lab_signal.ts` | Added `inferFyFromDateStr` so `JSON_BATCH_MUTATION` and `sale_event` unmark/delete FY-scoped `internalNo`, `partyId_billNo`, and `partyId_billNo_internalNo` keys in D1 `signal_tombstones` and `signals.tombstones`. |
| `test/purchase_recreation_sync_regression_test.dart` | Added regression test suite covering Scenarios A–E (Create, Delete, Re-create with reused `PUR-1` + same/different `billNo`, D1 `sale_events` replay, `DeltaMergeEngine`, burst outbox/signal aggregation, and Sale `Create -> Delete -> Re-create` safety). |

---

## 4. Verification & Honest Execution Status

- **Container Pre-Checks:**
  - `esbuild functions/api/lab_signal.ts`: **PASSED** (valid TypeScript compilation, 0 syntax errors).
  - Static cross-file signature, caller, diff, and `#PH-REV-811` compatibility audit across all 11 modified files + new test file: **PASSED**.
- **GitHub Actions CI History & Resolution:**
  - Initial run `43605736279` (commit `0a02674`) failed only on 2 `DELETE` return-value expectations in `test/purchase_recreation_sync_regression_test.dart` (`dispatchEnvelope(..., phWeb: webPh)` returns `false` on `DELETE` because `MasterSyncOrchestrator` already removes the record via `phWeb.purgeDeletedIds` beforehand); all 37 pre-existing tests passed.
  - Updated those 2 assertions to verify `webPh.purchases` / `webPh.sales` are empty after `DELETE` dispatch and pushed commit `94717f1`.
- **Verified Passing GitHub Actions CI Runs (Commit `94717f1`):**
  - **`Build Flutter Web Portal and Android APK` (Run `43606117554`) — `SUCCESS`:**
    - `flutter test`: **39 tests passed** (0 failures; all pre-existing regression suites + Scenarios A–E of `test/purchase_recreation_sync_regression_test.dart` passed).
    - `flutter build apk --release`: **PASSED** (`build/app/outputs/flutter-apk/app-release.apk`, 110.4MB) + uploaded artifact.
    - `flutter build web`: **PASSED** + uploaded artifact.
    - `Deploy production web to Cloudflare Pages`: **PASSED** (`https://3f77faf1.pharoah-erp.pages.dev`).
  - **`Build Android APK` (Run `43606117161`) — `SUCCESS`:**
    - `flutter build apk --release` + APK artifact upload: **PASSED**.

---

## 5. Remaining Live Verification (Manual App ↔ Web Smoke Test)

Install the newly built Android release APK from GitHub Actions run `43606117554` / `43606117161` and verify against the deployed Cloudflare Pages Web Portal (`https://3f77faf1.pharoah-erp.pages.dev`):
1. Create Purchase for Party X (App) → verify visible on App & Web Purchase Registers.
2. Delete that Purchase (App) → verify removed on both App & Web.
3. Re-create Purchase for Party X (App) → verify visible on both App & Web Purchase Registers.
4. Repeat `Create -> Delete -> Re-create` with Sale to confirm no regressions.
