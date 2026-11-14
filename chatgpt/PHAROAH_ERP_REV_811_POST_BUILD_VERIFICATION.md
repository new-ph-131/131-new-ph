# 🏛️ PHAROAH ERP — REVISION #PH-REV-811 POST-BUILD INDEPENDENT VERIFICATION REPORT

**Repository**: `https://github.com/new-ph-131/131-new-ph.git`  
**Inspected Commits**:  
- **Code Fixes**: `bbc3b2da3a4f008a5c64b2c166867b2ad7ff9c46` (`#PH-REV-811`)  
- **Documentation**: `c4c2ece66234fc13f15b84510fdb0f349e3e42f9`  
**Base Commit**: `8beb64a`  
**Verification Mode**: Independent Read-Only Forensic Audit & Real Test Execution (Zero Code Changes, Zero Commits)  
**Date**: November 14, 2026  

---

## 1. Executive Summary (कार्यकारी सारांश)

Pharoah ERP ke Revision `#PH-REV-811` me pichle agent dwara commit kiye gaye fixes aur reports ki swatantra (independent) jaanch ki gayi hai. Is audit me kisi bhi source code, accounting logic, schema ya workflow me badlaav nahi kiya gaya hai. 

### Mukhya Parinaam (Key Findings):
1. **Teeno Core Issues Verified in Source Code & Tests**:
   - **Issue A (Multi-MRP No-Batch FY Collapse)**: `InventoryLogicCenter.makeLotKey` aur `makeSyncKey` me escaped `\$` interpolations ko hatana aur `exactEmptyBatchLot: true` ke sath batch isolation implement karna source code aur tests dono se fully verified hai.
   - **Issue B (Purchase Modify/Delete Sync & 10–12 Rapid Bursts)**: `TombstoneEngine` me timestamped unmark registry (`cloudTs >= unmarkTs`), `D1SalesLedgerService` me composite key bug fix, `FastPullEngine` me post-purge disk sync sweep, aur `SyncQueueManager` me burst coalescing verified hai.
   - **Issue C (Web Sale Batch Dialog Incomplete Lots)**: `WebBatchResolver` ab multi-MRP blank-batch lots ko collapse nahi karta, dono distinct lots dialogue me aate hain.
2. **Real Test Execution Results**:
   - Naya regression test suite (`test/three_issues_independent_regression_test.dart`): **9/9 Tests PASSED**.
   - Puraane sabhi test suites: **25/25 Tests PASSED**.
   - **Kul milakar 34/34 Tests across 8 suites PASSED (100% Success Rate)**.
3. **Forensic Discovery on Audit Reports in `chatgpt/`**:
   - Pichle agent ke commit `c4c2ece` me `chatgpt/*.md` files me filenames, function names, test names aur commands **khali (blank)** the. 
   - Iska exact technical root-cause yeh tha ki bash command me double quotes ke andar Python code me markdown backticks (`` `...` ``) use kiye gaye the, jisse bash ne unhe shell commands samajhkar execute karne ki koshish ki aur empty strings se replace kar diya.
4. **Machine-Specific Changes in `.flutter-plugins`**:
   - Commit `bbc3b2d` me `.flutter-plugins` file me path `/home/codespace/.pub-cache/...` se badalkar `/root/.pub-cache/...` ho gaya tha. Yeh pure local environment artifact hai aur iska production source code se koi taalluk nahi hai; ise `.gitignore` me hona chahiye.

---

## 2. Teeno Samasyaon Ki Deep Verification (A, B, C)

### 📌 ISSUE A: FY Transition Me Alag-Alag MRP Wale NO BATCH Lots Ki Quantity Aur Identity

#### 1. Code Level Verification:
- **Flaw in Commit `8beb64a`**: `lib/inventory_logic_center.dart` me lines 57, 71, 73, 301, 322 par string interpolation me `\$` (escaped dollar) laga tha:
  ```dart
  // Pehle:
  return "__NOBATCH__|\$normExp|\${mrp.toStringAsFixed(2)}|\${purRate.toStringAsFixed(2)}";
  ```
  Is escaped backslash ki vajah se Dart ne ise literal `$` string treat kiya. Parinaamsvaroop sabhi NO BATCH lots (chahe MRP 100 ho ya 50) ka key exact identical string ban gaya:
  `"__NOBATCH__|$normExp|${mrp.toStringAsFixed(2)}|${purRate.toStringAsFixed(2)}"`
- **Fix in `bbc3b2d`**:
  Saare `\$` ko unescape karke `$normExp`, `${mrp.toStringAsFixed(2)}`, `${purRate.toStringAsFixed(2)}` kar diya gaya hai.
  Ab evaluate hone par:
  - Lot A (MRP 100, PurRate 70): `"__NOBATCH__||100.00|70.00"`
  - Lot B (MRP 50, PurRate 35): `"__NOBATCH__||50.00|35.00"`
  Dono keys mathematically alag hain.
- **Carry-Forward Preservation (`lib/fy_transfer_engine.dart`)**:
  `FYTransferEngine.cascadeSingleYearStep` (lines 707–737) target batch history me match karne ke liye `InventoryLogicCenter.findMatchingBatchIndex(..., exactEmptyBatchLot: true)` call karta hai.
  Jab `exactEmptyBatchLot: true` hota hai:
  `(b.mrp - mrp).abs() < 0.01 && (bPur - purRate).abs() < 0.01` match hona zaroori hai.
  Isliye FY1 se FY2 me carry forward karte waqt Lot A aur Lot B dono distinct copy hokar apne alag-alag `openingQty` aur `qty` ke sath naye FY me jaate hain.
- **Deletion Isolation (`lib/logic/batch_cascade_engine.dart` & `MasterSyncOrchestrator`)**:
  `deleteBatchSafe` me `{String exp = '', double mrp = 0.0, double purRate = 0.0}` add kiya gaya hai aur `MasterSyncOrchestrator` me blank-batch delete envelope canonical `syncId` aur `exactEmptyBatchLot: true` se match hota hai. Agar ek blank-batch lot delete kiya jaye toh doosra lot delete nahi hota.

#### 2. Test Level Verification:
- `test/three_issues_independent_regression_test.dart`:
  - `makeLotKey & makeSyncKey produce distinct evaluated keys for different MRPs when batch & expiry are blank`: **PASSED** (0ms)
  - `Issue A: Two NO BATCH MRP lots (100 & 50, qty 10 each) survive FY1 -> FY2 carry-forward, rebuild, and WebBatchResolver`: **PASSED** (2ms)
  - `Issue A: Deleting ONE blank-batch MRP lot via MasterSyncOrchestrator or BatchCascadeEngine preserves the OTHER MRP lot`: **PASSED** (3ms)

---

### 📌 ISSUE B: App ↔ Web Purchase Modify/Delete Sync & Rapid 10–12 Deletes

#### 1. Code Level Verification:
- **Unmark Poisoning Problem**:
  Jab Web par Purchase modify hota tha (`DATA_SAVED`), Web `unmarkedIds: [id]` bhejta tha. App `TombstoneEngine.unmarkTombstone` me us ID ko `unmarked_tombstones_$companyId` me bina timestamp ke daal deta tha. Jab Web par baad me wahi purchase delete kiya jata tha, toh App ka `sanitizeCloudTombstones` check karta tha:
  `if (unmarked.contains(cleanK)) continue;`
  Isse naya delete tombstone permanently censor ho jata tha aur App use discard kar deta tha.
- **Fix in `bbc3b2d`**:
  `TombstoneEngine` me `unmarked_registry_$companyId` introduce kiya gaya hai jisme unmark hone ka timestamp store hota hai. `sanitizeCloudTombstones` me LWW logic implement kiya gaya hai:
  `if (cloudTs > 0 && cloudTs >= unmarkTs) { sanitized.add(cleanK); }`
  Isse newer authoritative cloud delete hamesha older unmark ko override kar deta hai.
- **`FastPullEngine` Save-Gap Fix**:
  Pehle `FastPullEngine` tabhi disk par `purc.json` save karta tha jab `DeltaMergeEngine` return `true` kare. Agar koi bill cloud se delete ho gaya ho, toh cloud data me wo bill missing hota tha, jisse `DeltaMergeEngine` koi update detect nahi karta tha aur return `false` kar deta tha. Parinaam: App ke disk se delete hua bill kabhi nahi hat-ta tha.
  Fix me post-merge `TombstoneEngine.purgeDeletedRecords*` sweep aur record count tracking lagayi gayi hai, jisse purges disk par persist hote hain aur UI notify hoti hai.
- **Composite Key & Mixed-Case Fix**:
  `D1SalesLedgerService.isPurchaseDeleted` me pehle `cleanId.isNotEmpty` match na hone par direct `false` return ho raha tha; ab wo fallthrough karke composite keys (`cleanInt`, `compKey2`, `compKey3`) check karta hai.
- **10–12 Rapid Deletes Resilience**:
  - `functions/api/lab_signal.ts`: Single-row JSON table ki jagah D1 me relational `signal_tombstones` aur `signal_events` tables banayi gayi hain jahan atomic `INSERT OR REPLACE` hota hai, jisse rapid deletes me concurrency clash nahi hota.
  - Sticky HTTP `410`: Deleted purchase par koi stale UPDATE aaye toh worker `410 GONE` return karta hai, jisse zombie resurrection impossible ho jati hai.
  - `SyncQueueManager`: In-flight flush coalescing aur queue drain loop se rapid bursts me koi event drop nahi hota.

#### 2. Test Level Verification:
- `test/three_issues_independent_regression_test.dart`:
  - `App Purchase (mixed-case billNo) -> Web Modify -> Web Delete cannot resurrect via stale UPDATE or Cloud JSON merge`: **PASSED**
  - `isPurchaseDeleted checks composite keys even when UUID is non-empty and differs from tombstoned UUID`: **PASSED**
  - `CloudSignalChannel.aggregateRemoteSignals sorts out-of-order modify+delete chronologically so delete wins`: **PASSED**
  - `SyncQueueManager retains all 12 rapid Purchase delete operations in frame buffer without dropping any`: **PASSED**
  - `Sale edit -> delete workflow remains intact via MasterSyncOrchestrator and D1SalesLedgerService`: **PASSED**

---

### 📌 ISSUE C: Web Sale Batch Dialog Me Alag-Alag MRP Wale NO BATCH Lots Ka Display

#### 1. Code Level Verification:
- `WebItemEntryCard` (`lib/web_live_sync/sub_views/web_billing/web_item_entry_card.dart:161`) calls `webPh.getBatchesForMedicine(med)`, jo `WebBatchResolver.resolveBatchesForMedicine(med, batchHistory)` call karta hai.
- `WebBatchResolver` me loop chalte waqt har batch ka lotKey banaya jata tha:
  `final String lotKey = InventoryLogicCenter.makeLotKey(b.batch, exp: b.exp, mrp: b.mrp, purRate: bPur);`
  Kyuki `makeLotKey` me `\$` ki vajah se dono lots ka key identical `"__NOBATCH__|$normExp|${mrp.toStringAsFixed(2)}|${purRate.toStringAsFixed(2)}"` tha, `deduplicatedBatches[lotKey]` me sirf pehla lot rehta tha aur doosra lot drop ho jata tha.
- `makeLotKey` theek hone ke baad `WebBatchResolver` dono lots ko alag-alag keys par preserve karta hai aur `WebBatchLookupDialog` dono lots ko alag rows me display karta hai (MRP 100 @ 10 Qty aur MRP 50 @ 10 Qty).

#### 2. Test Level Verification:
- `test/three_issues_independent_regression_test.dart`:
  - `Issue C: WebBatchResolver returns BOTH distinct NO BATCH MRP lots without collapse (normal + post-FY zero purRate)`: **PASSED**

---

## 3. Real Test Suite Execution Matrix (Vaastavik Test Parinaam)

Sandbox me Flutter 3.27.4 runtime par sabhi test suites run karke verify kiye gaye:

| Test Suite File | Test Cases Count | Status | Notes |
|---|---|---|---|
| `test/three_issues_independent_regression_test.dart` | 9 Tests | **PASSED (100%)** | Issue A, B, C ke liye naya focused regression suite |
| `test/four_issues_comprehensive_regression_test.dart` | 4 Tests | **PASSED (100%)** | Inventory configurations, multi-FY party cascade, batch sync |
| `test/multi_fy_purchase_regression_test.dart` | 3 Tests | **PASSED (100%)** | Multi-FY E2E sequence, remote new-FY records, LWW conflict |
| `test/decimal_fy_duplicate_regression_test.dart` | 5 Tests | **PASSED (100%)** | Decimal quantity formatting, exact-case duplicates, 0.5 closing stock |
| `test/stock_ledger_regression_test.dart` | 6 Tests | **PASSED (100%)** | StockFlowEngine, App/Web ledger parity, Cash/UPI zero debt |
| `test/e2e_sync_test.dart` | 5 Tests | **PASSED (100%)** | Edit invoice, delete voucher, reborn bill, purchase lifecycle |
| `test/sync_bridge_test.dart` | 1 Test | **PASSED (100%)** | 2-Way Sync Engine: ID lock, tombstone & in-place merge |
| `test/widget_test.dart` | 1 Test | **PASSED (100%)** | ERP root app boot test with manager providers |
| **Total** | **34 Tests** | **34 Passed (100%)** | **Zero Failures, Zero Regressions** |

---

## 4. Forensic Audit: `chatgpt/` Folder Ki Adhoori Reports Ka Vishleshan

Pichle agent ne documentation commit `c4c2ece` me `chatgpt/` folder me 5 markdown files push ki thi. Un files ka forensic analysis karne par yeh paya gaya:

### Konsi Filenames/Function Names Khali The:
1. **`chatgpt/PHAROAH_ERP_CHANGELOG.md`**:
   - Line: `Unescaped all literal  interpolations in  and .`  
     *(Khali the: `\$`, `InventoryLogicCenter.makeLotKey`, `makeSyncKey`)*
   - Line: `Hardened  and  to isolate blank-batch deletion...`  
     *(Khali the: `BatchCascadeEngine.deleteBatchSafe`, `MasterSyncOrchestrator`)*
   - Line: `Added timestamped  and robust  LWW comparison...`  
     *(Khali the: `unmarked_registry`, `sanitizeCloudTombstones`)*
   - Line: `Provisioned relational  and  tables in Cloudflare D1 worker () and added HTTP  deleted sticky guards.`  
     *(Khali the: `signal_tombstones`, `signal_events`, `functions/api/lab_signal.ts`, `410`)*
   - Line: `Added  coalescing queue drain...`  
     *(Khali the: `SyncQueueManager`)*
   - Line: `Updated UI headers and sidebars to .`  
     *(Khali the: `#PH-REV-811 (FIX-NOBATCH-MULTI-MRP-FY-AND-PURCHASE-DELETE-SYNC)`)*
2. **`chatgpt/PHAROAH_ERP_TEST_RESULTS.md`**:
   - `Test Suite`: Khali (missing `test/three_issues_independent_regression_test.dart`).
   - `Execution Command`: Khali (missing `flutter test ...`).
   - Test Names 1 to 9: Sabhi 9 test names gayab the (sirf `1. : **PASSED**`, `2. : **PASSED**` likha tha).
3. **`chatgpt/PHAROAH_ERP_EVIDENCE.md`**:
   - Commit hash, test artifact path, patch diff path, worker script path, runner path sab khali the.
4. **`chatgpt/PHAROAH_ERP_THREE_ISSUES_ROOT_CAUSE_AND_FIX_REPORT.md`**:
   - Code explanation ke sabhi identifiers aur function names khali the.

### Root Cause of Missing Text:
Pichle agent ne bash me Python script ko double quotes `python3 -c "with open(...) as f: f.write('''... `func_name` ...''')"` me wrap kiya tha. Bash shell ne double quotes ke andar aane wale sabhi backticks (`` `...` ``) ko command substitution samajhkar execute kar diya. Kyuki wo system commands nahi the, bash ne error output phenk kar unki jagah empty string substitute kar di.

---

## 5. Machine-Specific Diff: `.flutter-plugins` Ka Vishleshan

Commit `bbc3b2d` me `.flutter-plugins` file me 33 entries ka absolute path badla hua dikhta hai:
- **Pehle**: `/home/codespace/.pub-cache/hosted/pub.dev/...`
- **Baad me**: `/root/.pub-cache/hosted/pub.dev/...`

### Evaluation:
- `.flutter-plugins` Flutter tool ka ek auto-generated caching index hota hai jo `flutter pub get` chalaate waqt generate hota hai.
- Yeh machine-specific (developer-machine-dependent) hota hai aur project ke actual source code ya execution ka hissa nahi hota.
- **Recommendation**: Ise git tracking se bahar (`.gitignore` me) hona chahiye taaki alag-alag dev environments ke beech dirty diff create na ho.

---

## 6. What Is Verified vs What Requires Physical Device / Manual Testing

| Area / Feature | Status | Verification Detail |
|---|---|---|
| **Multi-MRP Blank Batch FY Carry Forward** | **VERIFIED** | Code trace + `computeCarryForwardFromFiles` test verified |
| **Web Batch Selection Dialog Isolation** | **VERIFIED** | Code trace + `WebBatchResolver` test verified |
| **Blank-Batch Deletion Non-Interference** | **VERIFIED** | `BatchCascadeEngine` + `MasterSyncOrchestrator` test verified |
| **Tombstone Unmark Overcome (LWW)** | **VERIFIED** | `sanitizeCloudTombstones` + `TombstoneEngine` test verified |
| **Outbox Rapid Burst Coalescing** | **VERIFIED** | 12 consecutive Purchase delete operations buffer test verified |
| **Live Cloudflare D1 Edge Execution** | **MANUAL PENDING** | Automated test isolated environment me tha; real Cloudflare Pages worker deployment verification pending |
| **Physical Android App ↔ Web Live Relay** | **MANUAL PENDING** | Real physical device network connectivity par sync latency test manual verification mangti hai |
| **Multi-Tab Web Concurrency Stress Test** | **MANUAL PENDING** | 2-3 alag browser tabs me simultaneously 10 bill delete karne ka manual user flow |

---

## 7. Production Deployment Status

- **Git HEAD**: `origin/main` at `c4c2ece` (docs) and `bbc3b2d` (code).
- **GitHub Actions Workflows**:
  - `deploy-web.yml`: Configured for automated deployment on `push: main`.
  - Condition: Agar repo secrets me `CLOUDFLARE_API_TOKEN` set hai, toh GitHub Actions automatically production web bundle build aur deploy kar deta hai.
- **Colab Standalone Runner**:
  - `colab_runner_811.py`: Secret-free deployment script committed in repo root. Agar local ya sandbox environment me tokens na ho, toh Google Colab ya developer terminal se `CLOUDFLARE_API_TOKEN` pass karke 1-click deploy kiya ja sakta hai.
- **Regressions**:
  - Sabhi 8 regression suites (34 tests) pass hain. Existing Sale workflows, Purchase challans, multi-FY cascading, vouchers, aur ledger balance parity me **zero regression** hai.
