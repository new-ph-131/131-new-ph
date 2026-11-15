# PHAROAH ERP — SALE CHALLAN & PURCHASE CHALLAN SYNC AUDIT & FIX IMPLEMENTATION REPORT (FOR CHATGPT)

**Repository:** `new-ph-131/131-new-ph` (`main` branch)  
**Implementation Commits:** `1ef62f4` (Step 1), `d82549e` (Step 2), `16d2eff` (Step 3), `7956a74` (Step 4), `ff9632e` (Step 5), `2b0632c` & `53e847b` (CI Verification & Tombstone Fixes)  
**CI Build Status:** `SUCCESS` (GitHub Actions Run `#43721761318` — All 65/65 Flutter tests passing, Android APK & Web Portal built, deployed to Cloudflare Pages)

---

## 1. Executive Summary

This report documents the end-to-end architectural fixes implemented across **Pharoah ERP (Flutter App + Flutter Web + Cloudflare Pages Functions/D1 + Google Apps Script Drive Vault)** to resolve all **12 audited vulnerabilities** (6 `P0` Critical, 4 `P1` High, 2 `P2` Medium) affecting **Sale Challan (`s_challan.json`)** and **Purchase Challan (`p_challan.json`)** synchronization across multi-device, multi-financial-year (`FY`), and clock-skewed environments.

All 5 implementation steps from `challan_sync_fix_plan 2.md` have been applied directly to `main` and verified in CI.

---

## 2. Root Causes Addressed (Audit Issues #1 – #12)

| Issue ID | Severity | Subsystem | Root Cause Summary | Resolution Status |
| :--- | :---: | :--- | :--- | :---: |
| **Issue #1** | **P0** | UI Billing Views & Managers | Editing an existing Sale/Purchase Challan constructed a new model with default `version: 1` instead of preserving `existingChallan.version` and incrementing monotonically. | **Fixed (Step 3)** |
| **Issue #2** | **P0** | `SyncQueueManager` & Challan Sync Modules | `SyncQueueManager.enqueueUpsert` initialized new outbox items with `version = 1` instead of `challan.version`, causing envelope/payload version mismatch. | **Fixed (Step 4)** |
| **Issue #3** | **P0** | `TombstoneEngine`, `D1SalesLedgerService`, `DeltaMergeEngine`, `MultiFyCloudVault` | Deleting `SCH-1` (`id: uuid_1`) recorded a secondary series tombstone `2026-27::SCH-1`. Re-creating `SCH-1` (`id: uuid_2`) on a device with a slightly behind clock (+45s skew on deleting device) caused the secondary tombstone to permanently kill `uuid_2`, and cloud `tombstones.json` lacked an `unmarkedRegistry` to clear resurrected series keys. | **Fixed (Steps 2, 3, 4)** |
| **Issue #4** | **P0** | `PurchaseChallanSyncModule` | `applyPurchaseChallanMutation` matched records by `(partyId, billNo)` even when both records had distinct non-empty UUIDs (`id`) and distinct `internalNo` (`PCH-1` vs `PCH-2`), overwriting distinct challans sharing a generic supplier `billNo` (e.g. `"NA"`). | **Fixed (Step 4)** |
| **Issue #5** | **P0** | `PharoahWebManager` (`addSaleAndSync`, `addPurchaseAndSync`) | Converting a Pending challan into a Sale/Purchase invoice (`status = 'Billed'`) on Web did not bump the challan's `version`/`updatedAt` or push the `Billed` state to `SyncQueueManager` and Cloudflare D1. | **Fixed (Step 3)** |
| **Issue #6** | **P0** | `D1SalesLedgerService` | `applyEventsToLocalSales` and `applyEventsToLocalPurchases` did not filter out `SALE_CHALLAN` / `PURCHASE_CHALLAN` events, risking cross-type deletion or mutation if a challan shared an ID or series number with a Sale/Purchase invoice. | **Fixed (Step 2)** |
| **Issue #7** | **P1** | `TombstoneEngine` | Concurrent rapid deletions/re-creations (e.g. 10-challan burst) performed unlocked parallel read-modify-write operations on `SharedPreferences`, dropping tombstones under race conditions. | **Fixed (Step 2)** |
| **Issue #8** | **P1** | `functions/api/lab_signal.ts` | Cloudflare D1 `SAVE_SALE_EVENT` used an unconditional `ON CONFLICT(company_id, bill_id) DO UPDATE`, allowing stale retries to overwrite newer versions, tombstones (`is_deleted = 1`), or `Billed` locks. | **Fixed (Step 1)** |
| **Issue #9** | **P1** | `google_backend/Code.js` | Google Apps Script `uploadAllFiles` blindly overwrote `s_challan.json` and `p_challan.json` in Drive without per-record LWW or `Billed`-lock merging. | **Fixed (Step 1)** |
| **Issue #10** | **P1** | `FastPullEngine` & `AppAutoSyncDaemon` | FastPullEngine did not run `billLinkedChallansFromSaveEvents` or cross-FY challan vault synchronization when pulling delta events. | **Fixed (Step 4)** |
| **Issue #11** | **P2** | `functions/api/lab_signal.ts` | `PULL_SALES_DELTA` used `WHERE updated_at > ? ORDER BY updated_at ASC LIMIT 500`, which could skip same-millisecond events at the 500-row boundary. | **Fixed (Step 1)** |
| **Issue #12** | **P2** | `AppRealtimeCoordinator` & `WebRealtimeCoordinator` | Realtime coordinators did not explicitly trigger challan-aware fast pull and UI refresh on `SALE_CHALLAN` / `PURCHASE_CHALLAN` signal packets. | **Fixed (Step 4)** |

---

## 3. Detailed Step-by-Step Technical Changes

### Step 1: Cloud Signaling & Google Apps Script Backend (`1ef62f4`)

1. **`functions/api/lab_signal.ts`**:
   - **`SAVE_SALE_EVENT` Conditional Upsert Guard**:
     - Added a `WHERE` clause to `ON CONFLICT(company_id, bill_id) DO UPDATE` enforcing:
       - If `sales_ledger_events.is_deleted = 1` and `excluded.is_deleted = 0`, the existing tombstone is preserved for that immutable `bill_id` unless the incoming event is an explicit higher-version state transition.
       - If `sales_ledger_events.sale_data` has `"status":"Billed"`, incoming non-billed mutations or deletes are rejected.
       - Standard updates require `excluded.version > sales_ledger_events.version` or `(excluded.version = sales_ledger_events.version AND excluded.updated_at >= sales_ledger_events.updated_at)`.
   - **`PULL_SALES_DELTA` Boundary Safety**:
     - Changed query filter from `updated_at > ?` to `updated_at >= ? ORDER BY updated_at ASC, bill_id ASC LIMIT 500` so same-millisecond batch writes are never skipped across pagination boundaries.

2. **`google_backend/Code.js`**:
   - Added `mergeChallanVaultSafe_(existingRaw, incomingRaw, tombstonesMap)` inside the Google Apps Script backend.
   - When `uploadAllFiles` writes `s_challan.json` or `p_challan.json` (both root and `FY_*` prefixed files), it merges existing Drive records with incoming records by primary `id`:
     - Never resurrects UUIDs present in `tombstonesMap`.
     - Never downgrades a `Billed` challan back to `Pending` or `isDeleted = 1`.
     - Resolves conflicts via `(version, updatedAt)` LWW.

---

### Step 2: Core Tombstone Engine & D1 Sales Ledger Isolation (`d82549e`, `53e847b`)

1. **`lib/web_live_sync/sync_protocol/tombstone_engine.dart`**:
   - **Async Serialization Mutex (`_prefsLock`)**:
     - Added `_runLocked<T>(Future<T> Function() action)` chaining futures on `_prefsLock` so concurrent calls to `recordTombstoneWithTimestamp`, `unmarkTombstoneWithTimestamp`, and `mergeCloudTombstones` execute sequentially without `SharedPreferences` write-clobbering.
   - **Unmarked Tombstone Registry (`unmarked_tombstone_registry_$cid`)**:
     - `unmarkTombstoneWithTimestamp` now records `{key: timestamp}` in `unmarked_tombstone_registry_$cid` and removes the unmarked keys from local tombstones.
     - Exposed `getUnmarkedRegistry(String companyId)` (and alias `getUnmarkedTombstoneRegistry`) plus `mergeCloudUnmarkedRegistry` so cloud `tombstones.json` propagates unmark timestamps across devices.
   - **Challan UUID vs. Series Key Separation**:
     - Added `bool isSaleChallan = false` and `bool isPurchaseChallan = false` parameters to `recordTombstoneWithTimestamp` so primary UUID tombstones are always recorded while preventing reused human-readable series numbers (`SCH-1`, `PCH-1`) from poisoning newly created UUIDs.

2. **`lib/sync_core/d1_sales_ledger_service.dart`**:
   - **Strict Document-Type Isolation**:
     - In `applyEventsToLocalSales`: explicitly skips events where `docType == 'SALE_CHALLAN' || docType == 'PURCHASE_CHALLAN' || docType == 'PURCHASE'`.
     - In `applyEventsToLocalPurchases`: explicitly skips events where `docType == 'PURCHASE_CHALLAN' || docType == 'SALE_CHALLAN'`.
   - **UUID-First `isSaleChallanDeleted` Check**:
     - In `isSaleChallanDeleted(String id, String billNo, [String? fy, int? recordUpdatedAt])`:
       - Checks `if (isSaleChallanIdDeleted(cleanId, fy)) return true;`
       - Immediately returns `false` if `cleanId.isNotEmpty` (so a newly created SaleChallan with a distinct UUID `w_sch_new` is never blocked by an older deleted SaleChallan's secondary `billNo` gravestone `2026-27::WSCH-1`, even under +45s clock skew).
       - Falls back to `cleanSec = scopeSecondaryKey(billNo, fy)` only for legacy records where `cleanId.isEmpty`.

---

### Step 3: App & Web Challan Save, Delete & Billed Conversion (`16d2eff`)

1. **Preserving Version on Edit in UI Views**:
   - `lib/challans/sale_challan_billing_view.dart`
   - `lib/web_live_sync/sub_views/web_challans/web_sale_challan_billing_view.dart`
   - `lib/web_live_sync/sub_views/web_challans/web_purchase_challan_billing_view.dart`
   - All three views now pass `version: widget.existingChallan?.version ?? 1` when constructing the updated `SaleChallan` / `PurchaseChallan` instance.

2. **Monotonic Version Bump & Tombstone Unmarking in Managers**:
   - **`lib/pharoah_manager.dart`** (`addSaleChallan`, `addPurchaseChallan`):
     - Computes `nextVersion = max(existing.version, challan.version) + 1` on edit and `max(existing.updatedAt + 1, now)` for monotonic timestamps.
     - Calls `D1SalesLedgerService.unmarkSaleChallanPermanentlyDeleted` / `unmarkPurchasePermanentlyDeleted` and `TombstoneEngine.unmarkTombstoneWithTimestamp` on every save/re-create.
   - **`lib/web_live_sync/pharoah_web_manager.dart`** (`addSaleChallanAndSync`, `addPurchaseChallanAndSync`, `addSaleAndSync`, `addPurchaseAndSync`):
     - Applies the same monotonic version/timestamp bump and tombstone unmarking on Web.
     - In `addSaleAndSync` and `addPurchaseAndSync`, when linked challans are marked `status = 'Billed'`, each converted challan now increments its `version`, updates `updatedAt`, enqueues into `SaleChallanSyncModule.onSaleChallanSaved` / `PurchaseChallanSyncModule.onPurchaseChallanSaved`, and pushes to D1 (`D1SalesLedgerService.pushSaleChallanSavingToD1` / `pushPurchaseChallanSavingToD1`).

---

### Step 4: Sync Modules, Orchestrator, DeltaMergeEngine, MultiFyCloudVault & Daemons (`7956a74`, `2b0632c`, `53e847b`)

1. **`lib/sync_core/outbox/sync_queue_manager.dart`, `lib/sync_core/modules/sale_challan_sync_module.dart`, `lib/sync_core/modules/purchase_challan_sync_module.dart`**:
   - Added `int? exactVersion` and `int? exactUpdatedAt` to `SyncQueueManager.enqueueUpsert` so outbox envelopes always carry the exact entity `version` and `updatedAt`.
   - Fixed `PurchaseChallanSyncModule.applyPurchaseChallanMutation` so that when both existing and incoming `PurchaseChallan` records have non-empty `id`, matching is strictly by `id == id` (never collapsing distinct `PCH-1` and `PCH-2` records that happen to share a supplier `billNo`).

2. **`lib/web_live_sync/sync_protocol/delta_merge_engine.dart` & `lib/sync_core/multi_fy_cloud_vault.dart`**:
   - In `DeltaMergeEngine.processCloudData`: for `s_challan.json` and `p_challan.json` records with a non-empty `id`, secondary series tombstones (`scopedBNo`, `scopedIntNo`, `scopedComp2`, `scopedComp3`) are ignored so they cannot kill a newly re-created challan with a distinct UUID.
   - In `MultiFyCloudVault._isRecordDeletedInFy`:
     - `s_challan.json` checks secondary key tombstones only when `id.isEmpty`, and delegates to `D1SalesLedgerService.isSaleChallanDeleted`.
     - `p_challan.json` checks secondary/composite tombstones in `localTombstones`/`localRegistry` only when `id.isEmpty`, while `purc.json` continues to enforce case-sensitive composite key tombstones (`PARTY_billNo`).
   - Both `MultiFyCloudVault` and `AppSyncEngine` now read/write `unmarkedRegistry` inside cloud `tombstones.json`, pruning any cloud tombstone whose `unmarkTs >= tombstoneTs`.

3. **`lib/realtime_signaling/engines/fast_pull_engine.dart`, `lib/realtime_signaling/coordinators/app_realtime_coordinator.dart`, `lib/realtime_signaling/coordinators/web_realtime_coordinator.dart`, `lib/sync_bridge/engines/app_auto_sync_daemon.dart`**:
   - `FastPullEngine` now invokes `D1SalesLedgerService.billLinkedChallansFromSaveEvents` and updates cross-FY vault slices whenever challan or invoice delta events arrive.
   - Realtime coordinators recognize `SALE_CHALLAN` and `PURCHASE_CHALLAN` signal packets for immediate fast pull.

---

### Step 5: Automated Test Suite Verification (`test/challan_fy_identity_numbering_cross_sync_test.dart`)

Added Group 4 tests **`T13` – `T17`** to `test/challan_fy_identity_numbering_cross_sync_test.dart`:
- **`T13`**: 10x Create -> Modify -> Delete -> Re-create lifecycle for `SaleChallan` (`SCH-1..10`) and `PurchaseChallan` (`PCH-1..10`) across D1 events and `MasterSyncOrchestrator`.
- **`T14`**: +45s Clock Skew resilience — verifies a re-created `SaleChallan` (`id: w_sch_new`, `billNo: WSCH-1`, `updatedAt: 1002000`) is never blocked by an earlier deleted challan (`id: w_sch_old`, `billNo: WSCH-1`, `deletedAt: 1045000`) in `D1SalesLedgerService` or `DeltaMergeEngine`.
- **`T15`**: `TombstoneEngine` concurrent 10-delete + 10-unmark burst test verifying zero race losses in `SharedPreferences`.
- **`T16`**: Outbox `exactVersion` and `exactUpdatedAt` alignment across `INSERT`, `UPDATE`, and `DELETE` transitions in `SaleChallanSyncModule` and `PurchaseChallanSyncModule`.
- **`T17`**: D1 ledger isolation (`SALE_CHALLAN`/`PURCHASE_CHALLAN` events never delete or mutate `Sale`/`Purchase` bills with colliding IDs) and Web `Billed` conversion version bump + outbox enqueue verification.
