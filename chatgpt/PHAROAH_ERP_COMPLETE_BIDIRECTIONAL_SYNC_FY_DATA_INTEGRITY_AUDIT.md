# PHAROAH ERP – COMPLETE 6-MODULE BIDIRECTIONAL SYNC, STRESS, FY ISOLATION & LONG-TERM DATA INTEGRITY AUDIT

**Repository:** `new-ph-131/131-new-ph` (`main` branch, audited commit `3cd8dc9`)  
**Audit Scope:** App (`lib/pharoah_manager.dart`) ↔ Web (`lib/web_live_sync/pharoah_web_manager.dart`) ↔ Sync Core (`lib/sync_core/`, `lib/sync_bridge/`, `lib/realtime_signaling/`, `lib/web_live_sync/sync_protocol/`) ↔ Cloudflare D1 & Signaling (`functions/api/lab_signal.ts`) ↔ Google Apps Script & Google Drive (`google_backend/Code.js`)  
**Covered 6 Modules:**
1. **Sale Bill** (`INV-` / `W-`)
2. **Purchase Entry** (`PUR-` / `WPUR-`)
3. **Sale Challan** (`SCH-` / `WSCH-`)
4. **Purchase Challan** (`PCH-` / `WPCH-`)
5. **Credit Note / Sale Return** (`TXN-` / `CCN-` / `WCN-`)
6. **Debit Note / Purchase Return** (`DN-` / `WDN-`)

> **Important Audit Integrity Note:**  
> यह रिपोर्ट 100% वास्तविक source code inspection पर आधारित है। इस audit के दौरान **किसी भी source code file में कोई बदलाव नहीं किया गया है**, और live App/Web UI या Cloudflare/Drive runtime पर 50-record या 1-year simulation tests **अभी execute नहीं हुए हैं**। इसलिए जहाँ भी bug वास्तविक code flow में मिला है वहाँ उसे **`Code में Confirmed`** लिखा गया है, और जो runtime/stress tests अभी बाकी हैं उन्हें ईमानदारी से **`PROPOSED / NOT VERIFIED (Live Test Pending)`** mark किया गया है।

---

## 1. Executive Summary

Pharoah ERP एक dual-transport hybrid sync architecture पर चलता है:
- **Fast / Delta Path:** Cloudflare D1 (`functions/api/lab_signal.ts` — `sale_events`, `erp_master_sync`, `signal_events`, `batch_operations`) + `D1SalesLedgerService` + `SyncQueueManager` + `MasterSyncOrchestrator`.
- **Snapshot / Vault Path:** Google Drive `<TOKEN>.json` (via Google Apps Script `google_backend/Code.js`) + Multi-FY Vault (`lib/sync_core/multi_fy_cloud_vault.dart`) + App Disk JSON (`Documents/fy_<FY>/...`) / Web Memory + `SharedPreferences`.

### Overall Verdict (6 Modules Summary)

| Metric | Current Code Verdict | Main Reason (Code Proof) |
| :--- | :---: | :--- |
| **Production Data Safety (Concurrent App ↔ Web)** | **HIGH RISK (NOT SAFE)** | `google_backend/Code.js` snapshot merge sirf Challans/Config/Logs/Tombstones ke liye hai; **Sales, Purchases, Credit Notes, aur Debit Notes concurrent Drive push par overwrite ho sakte hain** (`BUG-001`). |
| **Offline / Crash / Browser Refresh Safety** | **CRITICAL RISK** | `SyncQueueManager._outboxBufferQueue` **sirf RAM में है** (`sync_queue_manager.dart` L16-20); disk/IndexedDB/SharedPreferences persistence नहीं है (`BUG-002`). |
| **Delete vs Zombie Resurrection Safety** | **HIGH RISK (Mixed)** | Sale/Purchase Challans strong हैं, par **Credit Note / Debit Note** में `MasterSyncOrchestrator` & `D1SalesLedgerService` merge से पहले **unconditionally `unmarkPermanentlyDeleted()`** चलाते हैं और Web में **unscoped `billNo` tombstones** हैं (`BUG-006`, `BUG-007`, `BUG-008`). |
| **FY 2026-27 ↔ FY 2027-28 Isolation** | **MEDIUM-HIGH RISK** | Challans का `originalFy` carry-forward & Delete-Bill→Revert-Challan मजबूत है, **पर Bill Cancel होने पर Challan revert नहीं होता**, Web Sale/Return tombstones में FY scoping missing है, और Return models में `originalFy` field नहीं है (`BUG-008`, `BUG-009`, `BUG-010`). |
| **Long-Term (1+ Year) Persistence** | **NOT GUARANTEED** | `D1` `sale_events` pull में 1,250-row cap/call, `signal_events` में 300-row trim, Browser cache clear par Web RAM/SharedPreferences loss, और Google Drive monolithic JSON + GAS 6-min limit (`BUG-005`). |

### Module-Wise Quick Health Rating

| # | Module | App ↔ Web Parity | Tombstone & Delete Safety | FY Isolation | Overall Risk |
| :---: | :--- | :--- | :--- | :--- | :---: |
| 1 | **Sale Bill** | Partial (Web UI me Cancel button missing) | Medium-High Risk (`MasterSyncOrchestrator` unmark-first + Web unscoped tombstone) | Medium Risk (`addSaleAndSync` missing `fy`, Cancel doesn't revert Challan) | **HIGH** |
| 2 | **Purchase Entry** | Medium (No Cancel in App or Web) | Medium-High Risk (`Code.js` overwrite + App `updatePurchase` unawaited sync) | Medium Risk (App `updatePurchase` omits `fy`, Challan link drift on edit) | **HIGH** |
| 3 | **Sale Challan** | Strong (Tail delete, HWM, Cancel distinct) | Low-Medium Risk (Strongest module, par RAM outbox & `Code.js` billNo fallback) | Low-Medium Risk (`originalFy` strong; Gap: Linked Bill **Cancel** doesn't revert) | **MEDIUM** |
| 4 | **Purchase Challan** | Strong (Tail delete, HWM, Cancel distinct) | Low-Medium Risk (Same architecture as Sale Challan) | Low-Medium Risk (`originalFy` strong; Gap: Linked Purchase Delete vs Partial Challan) | **MEDIUM** |
| 5 | **Credit Note** | Weak (Prefix/Delete/Cancel semantic mismatch) | **CRITICAL** (Delete sets `status="Cancelled"`, D1 labels as `"SALE"`, unscoped purge, zero sync tombstone guard) | **CRITICAL** (No `originalFy`, unscoped Web tombstone wipes other FY, `FYTransferEngine` ignores `partyId` & `paymentMode`) | **CRITICAL** |
| 6 | **Debit Note** | Weak (Prefix/Delete/Cancel semantic mismatch) | **CRITICAL** (Same critical flaws as Credit Note + D1 labels as `"PURCHASE"`/`"SALE"`) | **CRITICAL** (Same critical flaws as Credit Note) | **CRITICAL** |

---

## 2. Six Modules का अलग-अलग Audit

हर module के लिए Create, Modify, Delete, Cancel, Convert और Field Parity (Qty, Rate, GST, Discount, Amount, Party, Date) की वास्तविक code flow जांच नीचे दी गई है:

### 2.1 Module 1: Sale Bill (`SalesSyncModule` + `Sale`)

- **Number Series & Identity:**
  - App series: `INV-` (`pharoah_numbering_engine.dart`); Web series: `W-` (`web_pharoah_numbering_engine.dart`).
  - Dual-key identity: `id` (UUID) + `billNo` + `financialYear` (lekin legacy spots me `billNo` unscoped fallback मौजूद है).
  - Number allocation: Gap-filling (`getNextNumber` deleted gaps को reuse कर सकता है, इसलिए deleted billNo दुबारा आ सकता है -> tombstone collision का बड़ा कारण).
- **Allowed Business Operations (App vs Web Difference):**
  - **Create:** App (`saveBill`, `pharoah_manager.dart`) / Web (`addSaleAndSync`, `pharoah_web_manager.dart` L2995+).
    - *Code Defect:* Web `addSaleAndSync` (L3030-3036) `D1SalesLedgerService.onSaleSaved(...)` और `PharoahAutoSyncService.triggerAutoSync(...)` में **`fy: financialYear` pass नहीं करता**।
  - **Modify:** App (`updateBill` / save path) / Web (`updateSaleAndSync`, `pharoah_web_manager.dart` L3054+).
    - Modified fields (`qty`, `rate`, `gstRate`, `discount`, `totalAmount`, `partyName`, `partyId`, `date`, `items`) `SaleItem` के `toJson()` से serialize होते हैं और `version + 1` increment होता है।
  - **Delete vs Cancel (Critical Parity Gap):**
    - **Delete:** Bill remove होता है (`isDeleted = 1` + tombstone), linked Sale Challans `"Pending"` पर revert होते हैं (`deleteBill` App L3836; `deleteSale` Web L3217), और billNo नयी billing के लिए free हो जाता है।
    - **Cancel:** Bill list में रहता है (`status = "Cancelled"`, `isDeleted = 0`), stock wapas aata hai, billNo reserved रहता है।
    - **GAP #1 (Missing Web UI):** `pharoah_web_manager.dart` में `cancelSale` method (L3165) मौजूद है, लेकिन `lib/web_live_sync/sub_views/web_sales/web_sale_summary_view.dart` में **Cancel Sale का कोई UI button नहीं है** (सिर्फ Modify और Delete buttons हैं)!
    - **GAP #2 (Challan Orphan Bug):** न तो App `cancelBill` (`pharoah_manager.dart` L3778) और न ही Web `cancelSale` (`pharoah_web_manager.dart` L3165) linked Sale Challans को `"Pending"` पर revert करता है! Bill Cancel होने के बाद भी Challan `"Billed"` फंसा रहता है।
    - **GAP #3 (Unawaited D1 & Missing FY):** App `cancelBill` (L3794) `D1SalesLedgerService.onSaleCancelled` को `unawaited .then()` में चलाता है और `fy` pass नहीं करता।
  - **Convert:** Sale Challan → Sale Bill (`convertedToBillNo`, `linkedChallanIds`).
- **Sync & Field Parity Risks:**
  - `MasterSyncOrchestrator.dispatchEnvelope` (App L224, Web L1014) `isDelete == false` होने पर **tombstone check किए बिना `unmarkPermanentlyDeleted` call करता है**।
  - `SalesSyncModule.applySaleMutation` (`sales_sync_module.dart` L67-119) के अंदर **कोई tombstone guard नहीं है**।
  - `D1SalesLedgerService.applyEventsToLocalSales` (L1240-1248) में `if (version >= local.version || incomingSale.id != local.id || incomingSale.updatedAt >= local.updatedAt)` condition है — यानी **different UUID (`incomingSale.id != local.id`) या older `updatedAt` (अगर version tie हो) से भी local bill overwrite हो सकता है**।
  - `pharoah_web_manager.dart` `_parseDownloadedFiles` (L953-966) **unscoped** `localTombstoneRegistry[cleanBillNo]` check करता है और `masterSalesMap` (L983) pure `billNo` पर dedup करता है।

### 2.2 Module 2: Purchase Entry (`PurchaseSyncModule` + `Purchase`)

- **Number Series & Identity:**
  - App series: `PUR-`; Web series: `WPUR-` (`internalNo`), साथ में supplier का `billNo` और `partyId`.
  - Composite key: `PurchaseSyncModule.makeCompositeKey(partyId, supplierBillNo, internalNo)` (`purchase_sync_module.dart`).
- **Allowed Business Operations (App vs Web):**
  - **Create:** App (`savePurchase`) / Web (`addPurchaseAndSync`).
  - **Modify:** App (`updatePurchase`, `pharoah_manager.dart` L1276-1386) / Web (`updatePurchaseAndSync`, `pharoah_web_manager.dart` L3417+).
    - *Code Defect:* App `updatePurchase` (L1340) `PurchaseSyncModule.onPurchaseSaved` और `D1SalesLedgerService.onPurchaseSaved` को **unawaited `.then()`** में चलाता है और `unmarkPurchasePermanentlyDeleted`, `recordPurchaseKnownVersion`, `onPurchaseSaved`, `notifyAppMutation` में **`fy` omit करता है**। साथ ही edit के समय `linkedChallanIds` हटने/बदलने पर linked Purchase Challans का status reconcile नहीं होता।
  - **Delete:** App (`deletePurchase`) / Web (`deletePurchase`, L3501). Deleted purchase linked Purchase Challans को `"Pending"` पर revert करता है।
  - **Cancel:** **Purchase Entry में Cancel feature न App में है और न Web में है** (सिर्फ Modify और Delete)। *Test scripts को Purchase पर Cancel test apply नहीं करना चाहिए।*
  - **Convert:** Purchase Challan → Purchase Entry (`linkedChallanIds`).
- **Sync & Field Parity Risks:**
  - `D1SalesLedgerService.applyEventsToLocalPurchases` (`d1_sales_ledger_service.dart` L1774-1779) में `version >= local.version || incomingPur.updatedAt >= ...` है — पुराने server-side या stale edit से overwrite का खतरा।
  - `google_backend/Code.js` L796 `purc.json` को merge नहीं करता (`hasInSlice ? inSlice : exSlice`), जिससे concurrent App + Web Purchase create/modify पर **पूरा `purc.json` overwrite होकर दूसरे device का Purchase गायब हो सकता है** (`BUG-001`)।

### 2.3 Module 3: Sale Challan (`SaleChallanSyncModule` + `SaleChallan`)

- **Number Series & Identity:**
  - App series: `SCH-`; Web series: `WSCH-` (`ChallanHwmState`: separate `seq`, `gen`, `op`, `value` for App & Web!).
  - Composite identity: `id` + `challanNo` + `effectiveOriginalFy` (`originalFy ?? financialYear`).
- **Allowed Business Operations:**
  - **Create:** Pending Sale Challan बनाता है (`status = "Pending"`, HWM advance होता है)।
  - **Modify:** Challan items, qty, rate, GST, discount, party, remarks edit (`version + 1`).
  - **Delete vs Cancel (Strict Tail-Only Rule):**
    - `canDeleteSaleChallan`: **सिर्फ series का आख़िरी (tail) unbilled Challan (Pending या Cancelled) ही Delete हो सकता है** — और delete होने पर HWM (`ChallanHwmState`) rollback होता है ताकि वह number दुबारा इस्तेमाल हो सके।
    - **Middle Challan Delete Blocked:** बीच के किसी Challan को Delete करने की अनुमति नहीं है; user को उसे **Cancel** करना पड़ता है (`status = "Cancelled"`, `isDeleted = 0`, number permanently consumed रहता है)।
  - **Convert:** Sale Challan → Sale Bill (`status = "Billed"`, `convertedToBillNo`, `convertedFy`).
  - **Revert:** Linked Sale Bill **Delete** होने पर Sale Challan वापस `"Pending"` हो जाता है (`convertedToBillNo = ""`), भले ही Bill नए FY (`FY 2027-28`) में बना हो और Challan `FY 2026-27` का carry-forward हो (`revertLinkedChallansFromDeleteEvents` + `propagateChallanStatusAcrossVault` + `propagateChallanStatusAcrossDiskFolders`).
- **Remaining Risks Verified in Code:**
  1. Linked Sale Bill **Cancel** (`cancelBill` / `cancelSale`) होने पर Sale Challan `"Pending"` पर revert **नहीं** होता!
  2. Offline tail Delete करने के बाद अगर App crash हो या Browser refresh (`F5`) हो, तो `SyncQueueManager` (RAM-only) से `SALE_CHALLAN` delete + `hwmRollback` खो सकता है (अगर D1 call भी offline fail हो गई हो)।
  3. Browser cache clear (`SharedPreferences` clear) होने पर Web `challan_hwm_*` खो जाता है — recovery पूरी तरह Drive `config.json` (`challanHwm` / `challanHwmMeta`) या D1 `sale_events` के `hwmRollback` पर निर्भर करती है।

### 2.4 Module 4: Purchase Challan (`PurchaseChallanSyncModule` + `PurchaseChallan`)

- **Number Series & Identity:**
  - App series: `PCH-`; Web series: `WPCH-`. Separate `ChallanHwmState` tracking App vs Web sequences.
  - Identity: `id` + `challanNo` + `effectiveOriginalFy`.
- **Allowed Business Operations:**
  - **Create / Modify / Tail-Only Delete (with HWM rollback) / Middle-Only Cancel / Convert to Purchase Entry / Revert on Purchase Delete.**
- **Remaining Risks Verified in Code:**
  - Sale Challan की तरह ही strong cross-FY reconciliation (`reconcileCarryForwardPurchaseChallans`, `propagateChallanStatusAcrossVault`, `propagateChallanStatusAcrossDiskFolders`) मौजूद है।
  - *Gap:* Web/App `updatePurchase` में `linkedChallanIds` modify होने पर old linked challans का status `"Pending"` पर reset नहीं होता।
  - *Gap:* Offline tail Delete पर RAM-only `SyncQueueManager` और `D1` failure के कारण App & Web HWM divergence का risk।

### 2.5 Module 5: Credit Note / Sale Return (`CreditNoteSyncModule` + `SaleReturn`) — CRITICAL

- **Number Series & Identity:**
  - App: `TXN-` (commercial/document series `CCN-` in `credit_note_mechanism.dart` / `pharoah_manager.dart`); Web: `WCN-` (`web_pharoah_numbering_engine.dart`).
  - Model (`lib/models.dart` / `lib/web_live_sync/web_models.dart`): **`originalFy` field मौजूद नहीं है** (सिर्फ `financialYear` और `date` हैं)।
- **Critical Code Bugs Confirmed:**
  1. **Delete और Cancel एक दूसरे में मिक्स हैं (`CreditNoteSyncModule.onCreditNoteDeleted`, L30):** Delete करने पर sync payload `ret.status = "Cancelled"` और `ret.isDeleted = 1` दोनों set करता है, और `delta_merge_engine.dart` (L151) में जब `isDeleted` key miss हो तो `status == "Cancelled"` को `cloudIsDeleted = 1` मान लिया जाता है -> **एक device पर Cancel किया गया Credit Note दूसरे device पर Delete होकर गायब हो सकता है!**
  2. **Backend D1 Misclassification (`functions/api/lab_signal.ts` L295-315):** `sale_events` endpoint केवल `SALE_CHALLAN`, `PURCHASE_CHALLAN`, `PURCHASE` को अलग पहचानता है; बाकी सबको (जिसमें **`CREDIT_NOTE` / `SALE_RETURN` भी शामिल है**) **`"SALE"`** category में डाल देता है!
  3. **Zero Tombstone Guard & Unconditional Unmark:**
     - `CreditNoteSyncModule.applyCreditNoteMutation` (`credit_note_sync_module.dart` L61-83) में कोई tombstone check नहीं है, `billNo` match होने पर अलग UUID वाला local return भी overwrite हो जाता है, और version check `if (incoming.version <= local.version && incoming.updatedAt < local.updatedAt) return false` है (जिससे same timestamp par lower version या newer client clock par lower version जीत जाता है!).
     - `MasterSyncOrchestrator` (App L648-679, Web L1373-1392) merge से पहले unconditionally `unmarkPermanentlyDeleted` / `unmarkDeletedId` चलाता है, और Web `isDelete` में `D1SalesLedgerService.markPermanentlyDeleted` call ही नहीं करता।
     - `D1SalesLedgerService.applyEventsToLocalSaleReturns` (L2867-2918) भी merge से पहले `unmarkPermanentlyDeleted` call करता है और `inc.version >= local.version || inc.updatedAt >= local.updatedAt` से stale overwrites होने देता है।
  4. **Unawaited Delete & Missing FY in App/Web:**
     - `pharoah_manager.dart` (`finalizeSaleReturn` L2237-2238, `deleteSaleReturn`) व `pharoah_web_manager.dart` (`addSaleReturnAndSync` L4724-4780, `deleteSaleReturn`) `fy: financialYear` pass नहीं करते और `D1SalesLedgerService.onSaleReturnDeleted` को await नहीं करते।
  5. **Web Cross-FY Return Purge Leak (`pharoah_web_manager.dart` L306-311, L1488, L1525):**
     - `purgeDeletedIds` active list से `saleReturns` को **unscoped `bNo`** पर delete करता है (बिना FY या `unmarkedRecordIds` check के)!
     - `_parseDownloadedFiles` `localTombstoneRegistry[cleanBNo]` check करता है (unscoped) जबकि registry FY-scoped keys रखती है या cross-FY collision करती है।
  6. **FY Carry Forward Accounts Bug (`lib/fy_transfer_engine.dart` L105, L110):**
     - `dedupSr` में `sr.version >= dedupSr[k]!.version` है (no `updatedAt` tie-break) और party balance match **सिर्फ `_sameName(sr.partyName, pName)`** पर होता है (`partyId` और `paymentMode == 'CASH'` ignore होते हैं)।

### 2.6 Module 6: Debit Note / Purchase Return (`DebitNoteSyncModule` + `PurchaseReturn`) — CRITICAL

- **Number Series & Identity:**
  - App series: `DN-`; Web series: `WDN-`.
  - Model (`PurchaseReturn`): **`originalFy` field मौजूद नहीं है**।
- **Critical Code Bugs Confirmed:**
  - **Credit Note वाले लगभग सभी critical sync defects Debit Note में भी हूबहू मौजूद हैं:**
    1. `DebitNoteSyncModule.onDebitNoteDeleted` (L30) `status = "Cancelled"` और `isDeleted = 1` दोनों set करता है (`delta_merge_engine.dart` L151 के कारण Cancel और Delete आपस में corrupt हो सकते हैं)।
    2. `functions/api/lab_signal.ts` L295-315 में `DEBIT_NOTE` / `PURCHASE_RETURN` के लिए कोई separate `sale_events` category नहीं है — इसे `"PURCHASE"` या `"SALE"` bucket में गिना जाता है।
    3. `DebitNoteSyncModule.applyDebitNoteMutation` (L61-83) बिना tombstone check के overwrite करता है; `MasterSyncOrchestrator` (App L664-679, Web L1373-1392) पहले unmark करता है; `D1SalesLedgerService.applyEventsToLocalPurchaseReturns` (L3018-3069) पहले unmark करता है और `inc.version >= local.version || inc.updatedAt >= local.updatedAt` से stale timestamp overwrite allow करता है।
    4. `pharoah_web_manager.dart` (`purgeDeletedIds` L306-311, `_parseDownloadedFiles` L1546-1583, `addPurchaseReturnAndSync` L4785-4844) और `pharoah_manager.dart` (`finalizePurchaseReturn` L2334-2335) `fy` omit करते हैं और unscoped `bNo` tombstones use करते हैं।
    5. `lib/fy_transfer_engine.dart` L121, L126 `pr.version >= dedupPr[k]!.version` (no `updatedAt`) और सिर्फ `_sameName(pr.distributorName, pName)` (ignoring `partyId` and `paymentMode`) use करता है।

---

## 3. App ↔ Web Sync Test Matrix

नीचे दिया गया matrix दोनों दिशाओं (Test A: Web → App, Test B: App → Web) और edge/concurrency scenarios के लिए बनाया गया है।

| Test ID | Scenario | Transport / Mechanism Involved | Expected Result | Code Audit Risk & Status |
| :--- | :--- | :--- | :--- | :--- |
| **SYNC-01** | **Online Web → App (Create 50 Records)** | `D1SalesLedgerService` + `SyncQueueManager` (`erp_master_sync`) + `CloudSignalChannel` + `MasterSyncOrchestrator` | सभी 50 records App में exact Qty, Rate, GST, Discount, Amount, Party, Date के साथ दिखें। | **PROPOSED / NOT VERIFIED** (Risk: Credit/Debit Note `sale_events` misrouting & Drive `Code.js` overwrite) |
| **SYNC-02** | **Online App → Web (Create 50 Records)** | `AppRealtimeCoordinator` + `D1SalesLedgerService` + `SyncQueueManager` + Drive Push | सभी 50 records Web में बिना duplicate/drop के दिखें। | **PROPOSED / NOT VERIFIED** (Risk: App `add/update` missing `fy`, `"ERROR"` string check abort) |
| **SYNC-03** | **Bidirectional Modify (Same Record Sequentially)** | `version + 1`, `updatedAt`, `D1` `ON CONFLICT` | Latest version वाला edit दोनों devices पर जीते। | **CODE DEFECT (`BUG-003`, `BUG-007`)**: D1 clamps stale `updated_at` to `nowMs`; Returns version tie-break broken |
| **SYNC-04** | **Simultaneous Modify (App & Web Concurrent Push)** | `google_backend/Code.js` `PUSH_STORE_DATA` + D1 `erp_master_sync` | Both edits safely merge हों, कोई module slice गायब न हो। | **CONFIRMED FAIL IN CODE (`BUG-001`)**: `Code.js` overwrites `sales.json`, `purc.json`, `s_return.json`, `p_return.json`! |
| **SYNC-05** | **Delete vs Modify Race Condition** | Tombstone Registry + `MasterSyncOrchestrator` + `D1` | Deleted record दुबारा जिंदा (resurrect) नहीं होना चाहिए (या explicit conflict rule follow हो)। | **CONFIRMED FAIL IN CODE (`BUG-006`, `BUG-007`)**: `MasterSyncOrchestrator` & `D1SalesLedgerService` unmark tombstones BEFORE check |
| **SYNC-06** | **Offline App → Online Sync (With App Restart Mid-Offline)** | `SyncQueueManager` RAM queue + Local Disk JSON | Offline बनाए/delete किए गए records restart के बाद भी cloud पर sync हों। | **CONFIRMED FAIL IN CODE (`BUG-002`)**: `SyncQueueManager._outboxBufferQueue` RAM-only होने से restart par drop! |
| **SYNC-07** | **Web Offline → Browser Refresh (`F5`) → Online** | `SyncQueueManager` + `SharedPreferences` + Drive | Refresh के बाद pending Web edits sync हों। | **CONFIRMED FAIL IN CODE (`BUG-002`)**: Browser refresh Web memory & `SyncQueueManager` queue दोनों उड़ा देता है। |
| **SYNC-08** | **Network Retry / Duplicate Event Delivery** | `SyncQueueManager` (150ms loop) + `idempotency_key` | Duplicate events से duplicate bills या crash न हो। | **HIGH RISK (`BUG-002`)**: 150ms spin retry; duplicate UUID guard missing where `billNo` collides |
| **SYNC-09** | **App Logout/Login & Local Cache Wipe** | Drive Snapshot + Multi-FY Vault + `D1` full replay | Cloud से पूरा data, Challan HWM, और tombstones restore हों। | **HIGH RISK (`BUG-005`)**: D1 `sale_events` capped at 1,250/call; `signal_events` trimmed to 300 |
| **SYNC-10** | **Old Snapshot Restore (Zombie Check)** | `TombstoneEngine` + `snapshot_watcher.dart` | पहले Delete हो चुके records पुराने snapshot से वापस न आएं। | **HIGH RISK (`BUG-008`)**: Web `_parseDownloadedFiles` unscoped return/sale tombstones & `Code.js` merge gaps |
| **SYNC-11** | **FY Switch While Outbox Events Pending** | `MasterSyncOrchestrator` + `SyncEnvelope.fy` | FY 2026-27 का pending event गलती से FY 2027-28 data को pollute न करे। | **CONFIRMED RISK**: Web `addSaleAndSync`, `addSaleReturnAndSync`, `addPurchaseReturnAndSync`, App `updatePurchase` omit `fy`! |
| **SYNC-12** | **Text Contains `"ERROR"` (e.g., Party/Item/Remarks)** | `app_sync_engine.dart` L100/L501, `fast_pull_engine.dart` L99/L511 | Sync normal काम करना चाहिए। | **CONFIRMED FAIL IN CODE (`BUG-004`)**: `.contains("ERROR")` body check pull को abort कर देता है! |

---

## 4. 50-Record Stress Test Plan

हर module के लिए **50 अलग-अलग records** पर 3 चरणों में testing करनी है:
- **Test A (Web → App):** Web से 50 records बनाओ -> App में सभी 50 records + all fields (Qty, Rate, GST%, Discount%, Net/Total Amount, Party Name/ID, Date) verify करो -> Web से Modify -> App verify -> Web से Delete / Cancel / Convert -> App verify।
- **Test B (App → Web):** यही पूरी cycle App से शुरू कर के Web पर verify करो।
- **Test C (Repeated Stress Operations on the 50 Records):** Create (50) -> Modify (20) -> Delete (15) -> Re-create in freed gaps (10) -> Cancel (10, जहाँ लागू हो) -> Convert (Challan modules में 15)।

**Status of All 6 Stress Test Suites:** `PROPOSED / NOT VERIFIED (Live Test Pending)` — नीचे हर module के लिए exact operation breakdown और mandatory reconciliation checks दिए गए हैं:

### 4.1 Sale Bill — 50-Record Plan (`PROPOSED / NOT VERIFIED`)
- **Batch Mix (50 Records):** 15 GST 12% + Discount 5% (Credit), 15 GST 18% + Multi-item (Cash), 10 Zero-Discount / 5% GST, 10 Converted from Sale Challan (Web prefix `W-0001..W-0050` in Test A; App `INV-0001..INV-0050` in Test B).
- **Repeated Ops (Test C):**
  - Modify #1–#20 (change Qty, Rate, GST slab, Discount, Party, Date).
  - Delete #21–#35 (15 bills deleted -> freed `W-`/`INV-` slots check + linked Challan revert check).
  - Re-create 10 new bills (check if deleted numbers reuse cleanly without zombie resurrecting old deleted bill items!).
  - Cancel #36–#45 (**Expected UI blocker on Web:** Web Summary view में Cancel button missing होने से Test A Cancel phase Web UI से fail होगा unless called programmatically!).
- **Reconciliation Target:** Active Bills = 35 (25 active + 10 recreated), Cancelled = 10, Deleted = 15 (tombstoned, count = 0 in active list), Party Ledger & Stock exact match App ↔ Web।

### 4.2 Purchase Entry — 50-Record Plan (`PROPOSED / NOT VERIFIED`)
- **Batch Mix (50 Records):** 20 `WPUR-`/`PUR-` credit bills across 5 suppliers (with varying supplier `billNo`), 15 cash purchases, 15 converted from Purchase Challan.
- **Repeated Ops (Test C):**
  - Modify #1–#20 (Qty/Rate/GST/Discount/Supplier/SupplierBillNo/LinkedChallanIds).
  - Delete #21–#35 (verify linked Purchase Challan returns to `"Pending"`).
  - Re-create 10 purchases **same `(partyId, supplierBillNo)` से जो delete हुए थे** (composite key resurrection test!).
  - *Cancel:* **N/A** (Purchase Entry में Cancel operation मौजूद नहीं है — UI में button न होना verify करना है)।

### 4.3 Sale Challan — 50-Record Plan (`PROPOSED / NOT VERIFIED`)
- **Batch Mix (50 Records):** `WSCH-0001..0050` (Web) / `SCH-0001..0050` (App) — mixed Qty/Rate/GST/Discount/Party/Date.
- **Repeated Ops (Test C — Tail vs Middle Rule):**
  - Modify #1–#15 (Pending challans).
  - Attempt Delete on middle #20 -> **MUST BE BLOCKED** (`canDeleteSaleChallan == false`).
  - Cancel middle #16–#25 (10 Challans `status = "Cancelled"`, number preserved).
  - Delete ONLY tail #50 → #41 (one by one backwards from tail -> HWM `value`/`seq` must roll back `50 -> 40`).
  - Re-create 10 Challans -> must take `41..50` without duplicate `challanNo`.
  - Convert #1–#15 to Sale Bill -> verify Challan becomes `"Billed"`, फिर Linked Bill Delete -> `"Pending"`, फिर Test Linked Bill **Cancel** (expected bug confirmation: Challan stays `"Billed"`!).

### 4.4 Purchase Challan — 50-Record Plan (`PROPOSED / NOT VERIFIED`)
- **Batch Mix (50 Records):** `WPCH-0001..0050` / `PCH-0001..0050`.
- **Repeated Ops (Test C):** Exact Sale Challan जैसा Tail-Delete HWM rollback (#50 → #41), Middle-Cancel (#16–#25), Re-create 10 (`41..50`), Convert #1–#15 to Purchase Entry, Delete Purchase Entry -> verify Challan reverts to `"Pending"`.

### 4.5 Credit Note (Sale Return) — 50-Record Plan (`PROPOSED / NOT VERIFIED`)
- **Batch Mix (50 Records):** `WCN-0001..0050` / `TXN-0001..0050` (Credit & Cash returns, GST/Discount items, linked & standalone returns).
- **Repeated Ops (Test C):**
  - Modify #1–#20 -> verify Qty/Rate/GST/Amount/Party on opposite device.
  - **Cancel #21–#30** (`status = "Cancelled"`) -> verify opposite device पर यह **Delete न हो जाए** (`delta_merge_engine.dart` L151 risk!).
  - **Delete #31–#45** -> verify opposite device पर permanently गायब हो, Sale Bill या Purchase list pollute न करे (`lab_signal.ts` `"SALE"` misroute risk!).
  - Re-create 10 returns -> verify recreated returns same `billNo` पर old deleted tombstone से delete न हो जाएं या old data से overwrite न हों।

### 4.6 Debit Note (Purchase Return) — 50-Record Plan (`PROPOSED / NOT VERIFIED`)
- **Batch Mix (50 Records):** `WDN-0001..0050` / `DN-0001..0050` (Credit & Cash supplier returns, varying GST/Discount).
- **Repeated Ops (Test C):** Credit Note जैसी ही cycle — Modify (#1–#20), **Cancel (#21–#30)** vs **Delete (#31–#45)** separation test, Re-create 10, और cross-device Ledger/Stock match।

---

## 5. Data Loss और Duplicate Risk (10 Specific Code Checks)

User audit checklist के हर सवाल का सीधा code-verified उत्तर:

1. **क्या कोई Record दूसरे Device पर Sync होने के बाद गायब हो सकता है?**
   - **हाँ (CONFIRMED):**
     - `google_backend/Code.js` (L781-947) में `PUSH_STORE_DATA` सिर्फ Challans, Logs, Config और Tombstones को merge करता है; **`sales.json`, `purc.json`, `s_return.json`, `p_return.json` पर Last-Writer-Wins full slice overwrite (`hasInSlice ? inSlice : exSlice`, L796)** चलता है। Web और App कुछ सेकंड के अंतर से push करें तो एक device के नए/modified bills Drive पर मिट जाएंगे।
     - Web `pharoah_web_manager.dart` (`purgeDeletedIds` L306-311) `saleReturns`/`purchaseReturns` को बिना FY check के unscoped `bNo` से list से remove कर देता है।
     - Credit Note या Debit Note को **Cancel** करने पर अगर payload में `isDeleted` omitted हो, तो `delta_merge_engine.dart` L151 `status == "Cancelled"` को `isDeleted = 1` मानकर दूसरे device से record **गायब** कर देता है।

2. **क्या Deleted Record पुराने Snapshot से वापस आ सकता है (Zombie Resurrection)?**
   - **हाँ (CONFIRMED):**
     - `MasterSyncOrchestrator.dispatchEnvelope` में Sale (`App L224`, `Web L1014`), Credit Note (`App L648`, `Web L1373`), और Debit Note (`App L664`, `Web L1384`) **tombstone check से पहले ही `unmarkPermanentlyDeleted` call कर देते हैं**।
     - `D1SalesLedgerService` में `applyEventsToLocalSales` (L1240), `applyEventsToLocalSaleReturns` (L2867), `applyEventsToLocalPurchaseReturns` (L3018) भी incoming payload को पहले unmark करते हैं।
     - `SalesSyncModule`, `CreditNoteSyncModule`, `DebitNoteSyncModule` के `apply*Mutation` methods में कोई local tombstone check ही नहीं है।
     - `Code.js` L796 पर पुराने client का Drive push unmerged slice (`sales.json`, `purc.json`, `s_return.json`, `p_return.json`) को overwrite कर के deleted records वापस ला सकता है।

3. **क्या Duplicate Records बन सकते हैं?**
   - **हाँ (CONFIRMED RISK):**
     - **Dual-Path Version Skew:** `SalesSyncModule`, `CreditNoteSyncModule`, `DebitNoteSyncModule` `SyncQueueManager` को `exactVersion` बिना enqueue करते हैं (`version + 1` in `erp_master_sync` vs `version` in `D1` `sale_events`), जिससे same bill दो versions के साथ घूम सकता है।
     - **UUID vs `billNo` Mismatch:** `D1SalesLedgerService.applyEventsToLocalSales` L1244 (`incomingSale.id != local.id`) और Returns `applyEventsToLocal*Returns` (L2889, L3040) अलग UUID लेकिन same `billNo` होने पर overwrite या list में collision कर सकते हैं; अगर एक list match UUID पर हो और दूसरा `billNo` पर (e.g. gap-fill re-create), तो duplicate/mismatch बन सकता है।
     - **D1 Misclassification:** `lab_signal.ts` L295-315 में `CREDIT_NOTE` को `"SALE"` category में रखने से fast-pull routing cross-apply होने का खतरा रहता है।

4. **क्या एक Device का पुराना Data दूसरे Device के नए Data को Overwrite कर सकता है?**
   - **हाँ (CONFIRMED):**
     - `functions/api/lab_signal.ts` L590 (`Math.max(parseInt(op.updated_at || 0, 10), nowMs)`) offline client के पुराने timestamp को server के current `nowMs` में बदल देता है। अगर version बराबर (e.g. `v2`) हो, तो पुराना offline edit बाद में आकर नए online `v2` edit को `WHERE ?5 >= updated_at` (L610) से overwrite कर देगा!
     - `D1SalesLedgerService.applyEventsToLocalSales` / `Purchases` / `SaleReturns` / `PurchaseReturns` में `|| incoming.updatedAt >= local.updatedAt` OR condition होने से `version` कम होने पर भी (सिर्फ clock आगे होने पर) overwrite हो सकता है (`Sales` L1244, `Purchases` L1775, `SaleReturns` L2892, `PurchaseReturns` L3043).
     - `google_backend/Code.js` `baseSyncedAt` को completely ignore करता है, और `pharoah_web_manager.dart` L2759 में pre-push fetch `try { ... } catch (_) {}` में fail होने पर भी Web blind push कर देता है।

5. **क्या Tombstone सही काम करता है?**
   - **केवल आंशिक रूप से (Partial):**
     - **Challans (`SaleChallan` / `PurchaseChallan`):** Strong — FY-scoped keys, `tombstone_registry.json`, Drive merge in `Code.js`।
     - **Sale / Purchase / Credit Note / Debit Note:** Weak — `MasterSyncOrchestrator` & `D1SalesLedgerService` में unmark-first bugs, Web `_parseDownloadedFiles` में unscoped `cleanBillNo`/`cleanBNo` checks (`pharoah_web_manager.dart` L953, L1488, L1546), और Web Return delete में `D1SalesLedgerService.markPermanentlyDeleted` call missing होना।

6. **क्या UUID, Bill Number और FY के आधार पर Identity सुरक्षित है?**
   - **नहीं (Partially Broken):**
     - Sale Challan / Purchase Challan में `id` + `challanNo` + `effectiveOriginalFy` सुरक्षित है।
     - Credit Note (`SaleReturn`) और Debit Note (`PurchaseReturn`) models में `originalFy` है ही नहीं, Web `_parseDownloadedFiles` में `masterSalesMap` (L983) / Return maps pure `billNo` पर dedup होते हैं, और `D1SalesLedgerService` L1244 `incoming.id != local.id` होने पर भी overwrite होने देता है।

7. **क्या Outbox Events खो सकते हैं?**
   - **हाँ (100% CONFIRMED — `BUG-002`):** `SyncQueueManager._outboxBufferQueue` (`lib/sync_core/outbox/sync_queue_manager.dart` L16-20) केवल in-memory `static final List` है। App बंद, OS kill, या Browser reload (`F5`) होते ही सारे queued `erp_master_sync` events हमेशा के लिए खो जाते हैं।

8. **क्या Retry और Network Failure के दौरान Data सुरक्षित रहता है?**
   - **नहीं (CONFIRMED):**
     - `SyncQueueManager` fail होने पर `Future.delayed(Duration(milliseconds: 150))` से infinite tight-loop retry करता है (L146 — no exponential backoff, no persistence), और batch भेजते समय `batchPayload.first.storeToken` (L97) का उपयोग करता है।
     - `app_sync_engine.dart` (L100, L501) और `fast_pull_engine.dart` (L99, L511) में `.contains("ERROR")` string check अगर किसी party/item के नाम में `"ERROR"` अक्षर आ जाएं (जैसे `"TERROR"` या `"ERROR TEST"`), तो pull को fail मानकर abort कर देता है — और `app_sync_engine.dart` pull abort होने के बाद भी `PUSH_STORE_DATA` चला कर cloud data overwrite कर सकता है!
     - `pharoah_web_manager.dart` L2844 `response.statusCode == 200 || response.body.contains("SUCCESS")` मानता है — GAS HTTP 200 के साथ `{"status":"ERROR"}` लौटाए तब भी Web इसे success समझकर आगे बढ़ जाता है!

9. **क्या Modify और Delete के बीच Race Condition हो सकती है?**
   - **हाँ (CONFIRMED):**
     - Client A offline में `Modify (v2)` करता है, Client B online में `Delete` करता है। Client A जब online आता है:
       - `lab_signal.ts` L590 Client A का `updated_at` बढ़ाकर `nowMs` कर देता है;
       - `MasterSyncOrchestrator` Client A के `v2` envelope पर `unmarkPermanentlyDeleted()` पहले चलाकर Delete tombstone को मिटा देता है;
       - Client B का `Delete` हार जाता है और deleted record वापस जिंदा हो जाता है।

10. **क्या App और Web में अलग-अलग Delete Logic है?**
    - **हाँ (CONFIRMED):**
      - **Sale Bill:** App (`deleteBill` + `cancelBill` both in UI) vs Web (`deleteSale` in UI, **`cancelSale` UI में missing!**). Web `deleteSale` `tombstone_registry` को unscoped `cleanBillNo` में purge करता है।
      - **Credit/Debit Notes:** App `deleteSaleReturn`/`deletePurchaseReturn` अलग flow चलाते हैं जबकि Web `purgeDeletedIds` unscoped `bNo` wipe करता है और `MasterSyncOrchestrator` Web में `D1SalesLedgerService.markPermanentlyDeleted` call नहीं करता।
      - **Challans:** दोनों जगह Tail-Only delete + HWM rollback parity अच्छी है।

---

## 6. FY Isolation Audit (`FY 2026-27` vs `FY 2027-28`)

### 6.1 Sale Bill, Purchase Entry, Credit Note, Debit Note FY Rules
- **Multi-FY Storage Isolation:** App (`Documents/fy_<FY>/`) और Web Vault (`MultiFyCloudVault` / `snapshot.fy`) FY-wise isolated snapshots रखते हैं।
- **Sale Bill Gaps (`FY 2026-27` ↔ `FY 2027-28`):**
  - Web `addSaleAndSync` (`pharoah_web_manager.dart` L3030-3036) `D1SalesLedgerService.onSaleSaved` और `triggerAutoSync` में `fy` नहीं भेजता — यदि FY switch के आस-पास sync चले तो गलत active FY में event जा सकता है।
  - Web `_parseDownloadedFiles` (L953-966) `localTombstoneRegistry[cleanBillNo]` unscoped check करता है: FY 2026-27 में `W-0001` delete करने से unscoped registry FY 2027-28 के `W-0001` को प्रभावित कर सकती है।
- **Purchase Entry Gaps:**
  - App `updatePurchase` (`pharoah_manager.dart` L1340-1370) `fy` omit करता है। `MultiFyCloudVault` & `FYTransferEngine` में composite `(partyId, supplierBillNo, internalNo)` isolation मजबूत है (dedicated regression tests `multi_fy_purchase_regression_test.dart` मौजूद हैं)।
- **Credit Note & Debit Note Gaps (SEVERE):**
  - `SaleReturn` और `PurchaseReturn` models में **`originalFy` है ही नहीं**।
  - Web `purgeDeletedIds` (`pharoah_web_manager.dart` L306-311) **बिना FY check के `saleReturns`/`purchaseReturns` को delete करता है** -> FY 2026-27 का Return `WCN-0001` या `TXN-0001` delete होने पर **FY 2027-28 का `WCN-0001` / `TXN-0001` भी purge हो सकता है!**
  - App `finalizeSaleReturn` / `finalizePurchaseReturn` (L2237, L2334) और Web `addSaleReturnAndSync` / `addPurchaseReturnAndSync` (L4724-4844) `fy` omit करते हैं।
  - `FYTransferEngine` (`lib/fy_transfer_engine.dart` L105-128) carry-forward opening balance निकालते समय Returns को केवल `_sameName(partyName)` से जोड़ता है (`partyId` और `paymentMode == 'CASH'` को ignore करता है), जिससे Cash Returns या renamed parties का Opening Balance अगले FY में गलत carry-forward हो सकता है।

### 6.2 Sale Challan & Purchase Challan FY Isolation Audit

| FY Check Requirement | Code Implementation Status | Details & Remaining Gap |
| :--- | :---: | :--- |
| **1. पुराने FY (`2026-27`) के Records सुरक्षित रहें** | **STRONG (Code Verified)** | Vault + Disk folder `fy_2026-27` अलग रहते हैं; `originalFy` (`effectiveOriginalFy`) preserve होता है। |
| **2. नए FY (`2027-28`) में पुराने Bills गायब न हों** | **CONDITIONAL (Risk on `Code.js`)** | Single-FY switch पर Vault snapshot ठीक है, लेकिन `Code.js` में concurrent Drive push होने पर unmerged JSON slices से data risk रहता है। |
| **3. पुराने FY का Deletion नए FY को प्रभावित न करे** | **PASS (Challans) / FAIL (Web Returns)** | Challan tombstones FY-scoped हैं (`scopeSecondaryKey`), लेकिन Web Returns `purgeDeletedIds` L306 unscoped `bNo` पर चलता है! |
| **4. नए FY का Modify पुराने FY का Data न बदले** | **PASS (Challans)** | Non-carry-forward challans `effectiveOriginalFy` से isolated रहते हैं; सिर्फ carry-forward status propagate होता है। |
| **5. Pending Challan Carry Forward सही हो** | **STRONG (Code Verified)** | `FYTransferEngine.reconcileCarryForwardSaleChallans` & `PurchaseChallans` pending challans को `originalFy: '2026-27'` tag के साथ FY 2027-28 में लाते हैं। |
| **6. Converted Challan का व्यवहार सही हो** | **STRONG (Code Verified)** | FY 2027-28 में बिल बनने पर `status = "Billed"`, `convertedToBillNo`, `convertedFy = "2027-28"` दोनों FY snapshots में `propagateChallanStatusAcrossVault` + `DiskFolders` से update होता है। |
| **7. पुराने/नए FY में Converted Bill Delete होने पर Challan वापस Pending हो** | **STRONG (Delete) / FAIL (Cancel)** | Bill/Purchase **Delete** होने पर `revertLinkedChallansFromDeleteEvents` cross-FY `"Pending"` restore करता है। **BUG:** Linked Bill **Cancel** होने पर Challan `"Pending"` वापस नहीं होता! |
| **8. Challan Number Series & HWM सुरक्षित रहे** | **STRONG (Online) / RISK (Cache Clear + Offline)** | App (`SCH-`/`PCH-`) और Web (`WSCH-`/`WPCH-`) separate `ChallanHwmState` + tail-only delete rollback। Offline RAM outbox drop या Drive `config.json` overwrite से HWM drift का risk। |

### 6.3 Sale Challan vs Purchase Challan Separate FY Test Cases (`PROPOSED / NOT VERIFIED`)
- **Test Case SC-FY-01 (Sale Challan Cross-FY Revert):** FY 2026-27 में `SCH-0010` Pending बनाएं -> FY 2027-28 में Carry Forward करें -> Web से `W-0001` Sale Bill में Convert करें -> App पर verify `SCH-0010` Billed -> अब Web से `W-0001` **Delete** करें -> App (दोनों FY 2026-27 और FY 2027-28 views) में verify `SCH-0010` वापस `"Pending"` हुआ या नहीं -> फिर `W-0001` दुबारा बनाकर **Cancel** करें -> confirm करें कि Challan `"Billed"` फंसा रहता है (`BUG-010`).
- **Test Case PC-FY-01 (Purchase Challan Cross-FY Revert & Series Isolation):** FY 2026-27 में `PCH-0010` Pending बनाएं -> FY 2027-28 में Carry Forward करें -> App में `PUR-0001` में Convert करें -> FY 2027-28 में new `PCH-0001` अलग बनाएं -> FY 2026-27 के `PCH-0001` (यदि deleted हो) या `PUR-0001` को Delete करके verify करें कि FY 2027-28 का नया `PCH-0001` intact है और carried `PCH-0010 (originalFy: 2026-27)` `"Pending"` पर वापस आया है।

---

## 7. Long-Term Persistence Audit (1+ Year Readiness)

यदि user FY 2026-27 में App & Web पर काम करता है -> FY 2027-28 शुरू करता है -> **1 साल तक App/Web खोलता ही नहीं** -> browser cache clear कर देता है या नए phone में login करता है -> sync restart करता है:

### Code Audit Findings on 1+ Year Scenario:
1. **Cloudflare D1 `sale_events` Catch-up Limit (`d1_sales_ledger_service.dart` L1085):**
   - `fetchSaleDeltasWithCursor` एक बार में अधिकतम `5 pages * 250 = 1,250 events` fetch करता है। यदि 1 साल में या multi-FY में 1,250 से अधिक events हैं, तो single sync में पूरा history नहीं आएगा; multiple sync cycles चलानी होंगी।
2. **`signal_events` 300-Row Trim (`functions/api/lab_signal.ts` L229-238):**
   - Server `signal_events` को latest **300 rows per store** तक trim करता है, और `CloudSignalChannel.listenToSignals` (`cloud_signal_channel.dart` L182, L238-252) `_lastKnownSignalTime` को restart पर `now - 30s` से शुरू करता है। इसलिए 1 साल बाद realtime signal replay काम नहीं करेगा — app/web को पूरी तरह **Drive `<TOKEN>.json` Snapshot + `D1` Full Cursor Replay** पर निर्भर रहना होगा।
3. **Google Drive Monolithic `<TOKEN>.json` & GAS 6-Minute Execution Limit (`google_backend/Code.js`):**
   - पूरा ERP data (all modules + all FY Vault + logs + tombstones) एक ही `<TOKEN>.json` file में store होता है। साल भर का data (हजारों bills, items, audit logs) बढ़ने पर JSON parse/stringify में Google Apps Script की 6-minute execution limit, HTTP payload limits, या mobile timeout hit होने का गंभीर risk बढ़ता है।
4. **Web Browser Cache / Storage Clear:**
   - Web में App जैसी permanent local disk directory (`Documents/fy_<FY>`) नहीं है; Web memory + `SharedPreferences` (localStorage) browser cache clear करते ही **पूरी तरह साफ हो जाते हैं** (`challan_hwm_*`, local tombstones, local cursors सब गायब)। Re-login के बाद recovery 100% Drive `config.json` + D1 replay पर टिकी है। यदि cache clear से पहले Web का `SyncQueueManager` (RAM-only) कुछ unsent deletes/edits रखे हुए था, तो वह data **हमेशा के लिए खो जाएगा**।
5. **No False 1-Year Guarantee:**
   - वर्तमान codebase और बिना 1-year live/time-travel simulation run किए, **1 साल के बाद 100% lossless zero-manual-intervention recovery की गारंटी नहीं दी जा सकती** (`NOT VERIFIED / HIGH RISK`).

---

## 8. Live Reproduction Steps (Code-Confirmed Bugs)

हर bug नीचे दिए गए **8-Point Mandatory Template** में documented है:

---

### `BUG-001`: Concurrent App & Web Drive Push Overwrites Sales, Purchases, Credit Notes & Debit Notes
1. **Problem (आसान Hinglish में):** जब App और Web लगभग एक ही समय पर Google Drive पर data save (push) करते हैं, तो Google Apps Script सिर्फ Challans और Settings को merge करता है, लेकिन **Sales, Purchases, Credit Notes और Debit Notes में बाद वाले device की पूरी list पुराने device की list को overwrite कर देती है**, जिससे एक device के bills हमेशा के लिए गायब हो सकते हैं।
2. **Code Location:**
   - File: `google_backend/Code.js`
   - Method: `doPost` (`PUSH_STORE_DATA` handler), Lines `781–947` (विशेषकर Line `796`: `targetSlice = hasInSlice ? inSlice : exSlice;`, और Line `947`: `try { ... } catch(mergeErr) {}`).
   - Caller Side: `lib/web_live_sync/app_sync_engine.dart` (Line `540` `baseSyncedAt` भेजता है जिसे GAS ignore करता है) और `lib/web_live_sync/pharoah_web_manager.dart` `pushUpdatedDataToCloud` (Lines `2759–2797`, जहाँ pre-push fetch `catch (_) {}` में silently ignore होता है).
   - **Root Cause:** Server-side snapshot merge `s_challan.json`, `p_challan.json`, `logs.json`, `config.json`, `challan_hwm.json`, `tombstones.json`, `tombstone_registry.json` तक सीमित है; `sales.json`, `purc.json`, `s_return.json`, `p_return.json` के लिए कोई merge logic नहीं है।
3. **Live Testing Steps:**
   1. App (Device A) और Web (Device B) दोनों को एक ही Store Token से sync करके खोलें।
   2. दोनों devices पर इंटरनेट temporarily slow करें (या Drive snapshot sync pause कर के तुरंत एक के बाद एक दबाएं)।
   3. App से `INV-0051` बनाएं और Web से `W-0051` (या Credit Note `WCN-0051`) बनाएं, और 1–2 सेकंड के भीतर दोनों से Force Sync / Cloud Push trigger करें।
   4. Push complete होने के बाद दोनों devices पर Force Pull / Reload करें।
4. **Expected Result:** Drive की `sales.json` (और `s_return.json` / `purc.json`) में App का `INV-0051` और Web का `W-0051` दोनों सुरक्षित मौजूद होने चाहिए।
5. **Actual Buggy Result:** जो device बाद में Drive file (`setContent`) लिखता है, उसकी `sales.json` पहले device के bill को Drive snapshot से हटा देती है (और `catch(mergeErr) {}` के कारण कोई error भी नहीं दिखता)।
6. **Proof & Verification Target:** Google Drive `<TOKEN>.json` के अंदर `sales.json` और `s_return.json` inspect करें; एक device का record missing मिलेगा (जब तक D1 fast-sync ने दुबारा inject न किया हो)।
7. **Risk Level:** **CRITICAL**
8. **Reproduction Confidence:** **Code में Confirmed**

---

### `BUG-002`: RAM-Only Outbox Queue (`SyncQueueManager`) Causes Permanent Data Loss on Crash / Refresh
1. **Problem (आसान Hinglish में):** Offline रहते हुए या slow network पर आप जो भी Create, Modify, Delete या Cancel करते हैं, उसका sync queue सिर्फ **RAM (temporary memory)** में रहता है। अगर offline रहते हुए App बंद हो जाए या Web browser refresh (`F5`) हो जाए, तो सारा queued sync data उड़ जाता है।
2. **Code Location:**
   - File: `lib/sync_core/outbox/sync_queue_manager.dart`
   - Symbol/Lines: `_outboxBufferQueue` (Lines `16–20`), `batchPayload.first.storeToken` (Line `97`), retry loop `Future.delayed(const Duration(milliseconds: 150))` (Lines `143–146`).
   - **Root Cause:** Queue को disk (`SharedPreferences` / file storage / IndexedDB) में persist करने का कोई write/load mechanism नहीं है।
3. **Live Testing Steps:**
   1. Web browser (या Mobile App) में इंटरनेट बंद करें (Offline mode)।
   2. Web पर 2 Sale Bills (`W-0061`, `W-0062`) बनाएं और 1 Credit Note (`WCN-0005`) Delete करें।
   3. इंटरनेट ऑन करने से **पहले** Web browser को `F5` से hard refresh करें (या Mobile App को Recent Apps से swipe-kill करें)।
   4. अब इंटरनेट ऑन करके opposite device पर sync check करें।
4. **Expected Result:** Pending outbox queue disk से reload होकर D1 cloud पर push होना चाहिए और opposite device पर बदलाव दिखने चाहिए।
5. **Actual Buggy Result:** Outbox memory साफ हो चुकी है; Web के unsynced actions गायब हो जाते हैं और App/opposite device पर कभी sync नहीं होते।
6. **Proof & Verification Target:** Network inspector में restart के बाद `erp_master_sync` POST request न जाना और opposite device पर records missing मिलना।
7. **Risk Level:** **CRITICAL**
8. **Reproduction Confidence:** **Code में Confirmed**

---

### `BUG-003`: Cloudflare D1 Clamps Old Offline Client `updated_at` to `nowMs` (Stale Edit Overwrites Newer Edit)
1. **Problem (आसान Hinglish में):** अगर कोई device 2 दिन से offline था और पुराने version वाला bill edit करके बाद में online आता है, तो Cloudflare server उस पुराने edit का time आज का current time (`nowMs`) बना देता है — जिससे वह पुराना edit दूसरे device के नए (fresh) edit को overwrite कर सकता है।
2. **Code Location:**
   - File: `functions/api/lab_signal.ts`
   - Handler: `erp_master_sync` POST handler, Line `590`: `const uAt = Math.max(parseInt(op.updated_at || 0, 10), nowMs);` और Lines `601–614` (`ON CONFLICT(sync_id) ... WHERE ?5 >= updated_at`).
   - **Root Cause:** Server client के पुराने `updated_at` को clamp करके वर्तमान server time दे देता है।
3. **Live Testing Steps:**
   1. App (A) और Web (B) पर `INV-0010` (`v1`, Qty=5) sync करें।
   2. App (A) को offline करें और `INV-0010` को Qty=3 (`v2`, local time `T=10:00`) पर modify करें।
   3. Web (B) online रहते हुए `INV-0010` को Qty=8 (`v2`, server time `T=10:05`) पर modify करे।
   4. `T=10:15` पर App (A) को online लाएं।
4. **Expected Result:** `T=10:05` वाला newer edit (Qty=8) final state रहना चाहिए।
5. **Actual Buggy Result:** `lab_signal.ts` App (A) के edit को `uAt = 10:15` assign कर देता है, जो `10:05` से बड़ा होने के कारण D1 में Qty=8 को Qty=3 से overwrite कर देता है।
6. **Proof & Verification Target:** Cloudflare D1 `erp_master_sync` table की row inspect करें: `updated_at` `T=10:15` और payload Qty=3 दिखेगा।
7. **Risk Level:** **HIGH**
8. **Reproduction Confidence:** **Code में Confirmed**

---

### `BUG-004`: Any Record Containing `"ERROR"` Text Silently Aborts Sync & Corrupts Drive Snapshot
1. **Problem (आसान Hinglish में):** Sync engine JSON parse करने के बजाय पूरे server response text में `.contains("ERROR")` ढूंढता है। अगर किसी Party का नाम, Medicine का नाम, या Remarks में `"ERROR"` शब्द हो (जैसे `"ERROR PHARMA"`), तो App/Web sync को failed मानकर pull रोक देता है — और push वाले step में cloud का नया data overwrite कर सकता है!
2. **Code Location:**
   - `lib/web_live_sync/app_sync_engine.dart`: Lines `100` (`!pullRes.body.contains("ERROR")`) और `501` (`!response.body.contains("ERROR")`).
   - `lib/realtime_signaling/engines/fast_pull_engine.dart`: Lines `99` और `511`.
   - `lib/web_live_sync/pharoah_web_manager.dart`: Line `2844` (`response.statusCode == 200 || response.body.contains("SUCCESS")`).
   - **Root Cause:** Structured JSON `status == "ERROR"` check करने के बजाय raw substring `.contains("ERROR")` और HTTP 200 blind pass।
3. **Live Testing Steps:**
   1. Web पर एक Party बनाएं जिसका नाम `"ERROR MEDICAL STORE"` हो और एक Sale Bill `W-0070` बनाएं, sync करें।
   2. App पर Live Sync / Pull चलाएं।
   3. App से एक नया bill `INV-0071` बनाकर `AppSyncEngine` से push trigger करें।
4. **Expected Result:** `W-0070` App में safely pull होना चाहिए और `INV-0071` safely merge होना चाहिए।
5. **Actual Buggy Result:** Drive JSON में `"ERROR MEDICAL STORE"` होने के कारण `!pullRes.body.contains("ERROR")` `false` हो जाता है; pull abort हो जाता है और App को Web का data नहीं मिलता (और pre-push pull skip होने पर stale Drive push हो सकता है)।
6. **Proof & Verification Target:** Debug logs में pull abort बिना network failure के, जबकि JSON valid है।
7. **Risk Level:** **HIGH**
8. **Reproduction Confidence:** **Code में Confirmed**

---

### `BUG-005`: D1 1,250-Event Cursor Cap + `signal_events` 300-Row Trim + Dual-Path Version Skew
1. **Problem (आसान Hinglish में):** ज्यादा दिनों (या 1 साल) बाद sync चलाने पर D1 एक बार में सिर्फ 1,250 events तक ही लाता है और `signal_events` 300 rows पर trim हो जाता है; इसके अलावा `Sales`, `CreditNote`, और `DebitNote` के दोनों sync paths अलग-अलग `version` numbers भेजते हैं।
2. **Code Location:**
   - `lib/sync_core/d1_sales_ledger_service.dart` Line `1085` (max 5 pages × 250 = 1,250 events).
   - `functions/api/lab_signal.ts` Lines `229–238` (300-row trim on `signal_events`).
   - `lib/realtime_signaling/transport/cloud_signal_channel.dart` Lines `182`, `238–252` (`now - 30s` non-persistent cursor).
   - `lib/sync_core/modules/{sales,credit_note,debit_note}_sync_module.dart` (`SyncQueueManager` enqueued without `exactVersion: true`, while `D1SalesLedgerService` gets different version).
   - **Root Cause:** Unpersisted signal cursor, bounded delta pagination, और dual-path version desync।
3. **Live Testing Steps:**
   1. एक store में 1,500+ sale/return mutations generate करें (या 1 साल के workload जितना)।
   2. नया Web browser session / fresh cache clear App install खोलें और सिर्फ 1 बार sync trigger होने दें (बिना manual repeated reload के)।
4. **Expected Result:** एक ही cold-boot sync में सभी 1,500+ events reconcile होने चाहिए।
5. **Actual Buggy Result:** Initial `fetchSaleDeltasWithCursor` 1,250 events के बाद रुक जाता है; बचे हुए 250+ events के लिए next poll या Drive snapshot का इंतज़ार करना पड़ता है, और Sale/Return में version mismatch से stale events जीत सकते हैं।
6. **Proof & Verification Target:** D1 query response `page == 5` पर loop exit और missing trailing transactions on first sync cycle।
7. **Risk Level:** **MEDIUM-HIGH**
8. **Reproduction Confidence:** **Code में Confirmed (Dual-path version skew) / Test से Verify करना बाकी (1,500-event single-pass timing)**

---

### `BUG-006`: Deleted Sale Bill / Credit Note / Debit Note Resurrects Because Orchestrator Unmarks Tombstones BEFORE Merging
1. **Problem (आसान Hinglish में):** अगर किसी device पर Sale Bill, Credit Note या Debit Note Delete हो चुका है और दूसरे device से उसका कोई pending `CREATE`/`MODIFY` event आता है, तो `MasterSyncOrchestrator` और `D1SalesLedgerService` merge checks चलाने से **पहले ही** delete tombstone मिटा देते (`unmark`) हैं, जिससे deleted bill वापस जिंदा हो जाता है।
2. **Code Location:**
   - `lib/sync_core/orchestrator/master_sync_orchestrator.dart`: App Sale (Line `224`), Web Sale (Line `1014`), App Returns (Lines `648–679`), Web Returns (Lines `1373–1392`) — unconditional `unmarkPermanentlyDeleted` / `unmarkDeletedId`, और Web Return delete में `D1SalesLedgerService.markPermanentlyDeleted` missing!
   - `lib/sync_core/d1_sales_ledger_service.dart`: `applyEventsToLocalSales` (Line `1240`), `applyEventsToLocalSaleReturns` (Line `2867`), `applyEventsToLocalPurchaseReturns` (Line `3018`).
   - `lib/sync_core/modules/{sales,credit_note,debit_note}_sync_module.dart`: `apply*Mutation` methods में कोई local tombstone check नहीं।
   - **Root Cause:** Unconditional unmarking + sync module स्तर पर tombstone guard की अनुपस्थिति।
3. **Live Testing Steps:**
   1. App और Web पर `INV-0020` (या Credit Note `WCN-0020`) `v1` sync करें।
   2. Web को offline करके `WCN-0020` को `v1` पर minor modify करें (या queue रोक कर रखें)।
   3. App से `WCN-0020` को **Delete** करें (online sync complete होने दें)।
   4. अब Web को online लाएं।
4. **Expected Result:** Deleted `WCN-0020` हमेशा deleted रहना चाहिए (या explicit delete-wins policy लागू हो)।
5. **Actual Buggy Result:** Web से incoming event पर `MasterSyncOrchestrator` और `D1SalesLedgerService` पहले tombstone `unmark` करते हैं, जिससे deleted `WCN-0020` दुबारा active list में जिंदा हो जाता है।
6. **Proof & Verification Target:** Delete के बाद App/Web `SaleReturns`/`Sales` summary में `WCN-0020` दुबारा active दिखना।
7. **Risk Level:** **CRITICAL**
8. **Reproduction Confidence:** **Code में Confirmed**

---

### `BUG-007`: Credit Note & Debit Note Delete vs Cancel Conflation + D1 `"SALE"` Misclassification
1. **Problem (आसान Hinglish में):** Credit Note और Debit Note में **Delete** और **Cancel** दो अलग-अलग काम हैं, लेकिन sync module Delete होने पर भी `status = "Cancelled"` लिखता है और delta merge `status == "Cancelled"` होने पर record को Deleted मान लेता है! साथ ही Cloudflare server `lab_signal.ts` Credit Note और Debit Note के लिए अलग event category ही नहीं रखता।
2. **Code Location:**
   - `lib/sync_core/modules/credit_note_sync_module.dart`: Line `30` (`ret.status = "Cancelled"; ret.isDeleted = 1;`) और Lines `61–83` (`incoming.version <= local.version && incoming.updatedAt < local.updatedAt`).
   - `lib/sync_core/modules/debit_note_sync_module.dart`: Line `30` (`ret.status = "Cancelled"; ret.isDeleted = 1;`) और Lines `61–83`.
   - `lib/web_live_sync/sync_protocol/delta_merge_engine.dart`: Line `151` (`status == "Cancelled"` से `cloudIsDeleted = 1` मान लेना जब `isDeleted` omitted हो).
   - `functions/api/lab_signal.ts`: Lines `295–315` (sirf `SALE_CHALLAN`, `PURCHASE_CHALLAN`, `PURCHASE`, else `SALE`).
   - **Root Cause:** Semantic conflation (`Cancelled` vs `Deleted`) और D1 backend schema में Return event type routing की कमी।
3. **Live Testing Steps:**
   1. App से एक Credit Note `TXN-0005` बनाकर Web पर sync करें।
   2. App से `TXN-0005` को **Cancel** (Delete नहीं!) करें — ताकि audit के लिए Cancelled record दिखना चाहिए।
   3. Web पर delta/snapshot sync चलाएं।
4. **Expected Result:** Web पर `TXN-0005` `"Cancelled"` status के साथ list में दिखाई देना चाहिए (number reserved, amount 0 impact)।
5. **Actual Buggy Result:** `delta_merge_engine.dart` L151 पर `isDeleted` omitted होने पर `status == "Cancelled"` को `isDeleted = 1` मान लेने से record Web से **Delete होकर गायब** हो सकता है; साथ ही D1 `sale_events` इसे `"SALE"` category में store करता है।
6. **Proof & Verification Target:** D1 `sale_events` row में `entity_type = 'SALE'` और Web return list से Cancelled record का गायब होना।
7. **Risk Level:** **CRITICAL**
8. **Reproduction Confidence:** **Code में Confirmed**

---

### `BUG-008`: Web Unscoped `billNo` Tombstone Purge Deletes Returns/Sales Across Financial Years
1. **Problem (आसान Hinglish में):** Web में `FY 2026-27` का Credit Note `WCN-0001` या Sale Bill `W-0001` delete करने पर Web उसे सिर्फ bill number (`WCN-0001`) से purge/filter करता है (FY साथ नहीं मिलाता)। इससे `FY 2027-28` का नया `WCN-0001` या `W-0001` बिना किसी गलती के गायब या block हो सकता है!
2. **Code Location:**
   - `lib/web_live_sync/pharoah_web_manager.dart`:
     - `purgeDeletedIds` Lines `306–311` (`saleReturns` / `purchaseReturns` को unscoped `bNo` से remove करना, बिना FY check और बिना `unmarkedRecordIds` protection के)।
     - `_parseDownloadedFiles` Lines `953–966` (Sale unscoped `localTombstoneRegistry[cleanBillNo]`) और Lines `1488, 1525, 1546, 1583` (Return unscoped `localTombstoneRegistry[cleanBNo]`).
     - `addSaleAndSync` (Lines `3030–3036`), `addSaleReturnAndSync` (Lines `4724–4780`), `addPurchaseReturnAndSync` (Lines `4785–4844`) — `fy: financialYear` missing।
   - `lib/models.dart` & `lib/web_live_sync/web_models.dart`: `SaleReturn` और `PurchaseReturn` में **`originalFy` field missing**।
   - **Root Cause:** Challans की तरह FY-scoped `scopeSecondaryKey(billNo, fy)` का Sales/Returns purge व download parse में लागू न होना।
3. **Live Testing Steps:**
   1. Web में `FY 2026-27` में Credit Note `WCN-0001` बनाएं।
   2. `FY 2027-28` switch करके वहाँ भी `WCN-0001` बनाएं और sync करें।
   3. अब `FY 2026-27` में जाकर पुराने `WCN-0001` को Delete करें।
   4. वापस `FY 2027-28` में आएं और Cloud Pull / Reload करें।
4. **Expected Result:** `FY 2026-27` का `WCN-0001` delete होना चाहिए, लेकिन `FY 2027-28` का `WCN-0001` सुरक्षित रहना चाहिए।
5. **Actual Buggy Result:** `purgeDeletedIds` (L306-311) unscoped `WCN-0001` match करके active `FY 2027-28` के `WCN-0001` को भी purge कर देता है!
6. **Proof & Verification Target:** `FY 2027-28` Credit Note list में `WCN-0001` का गायब मिलना।
7. **Risk Level:** **CRITICAL**
8. **Reproduction Confidence:** **Code में Confirmed**

---

### `BUG-009`: Web Sale Summary View Has NO Cancel Sale UI Button (`cancelSale` Unreachable)
1. **Problem (आसान Hinglish में):** App में User Sale Bill को **Modify**, **Delete**, और **Cancel** तीनों कर सकता है। लेकिन Web के Sale Summary UI में सिर्फ Modify और Delete buttons हैं — **Cancel Sale का button ही नहीं है**, जबकि backend manager (`pharoah_web_manager.dart`) में `cancelSale()` method बना हुआ है।
2. **Code Location:**
   - Method exists: `lib/web_live_sync/pharoah_web_manager.dart` Line `3165` (`Future<void> cancelSale(...)`).
   - Missing UI call-site: `lib/web_live_sync/sub_views/web_sales/web_sale_summary_view.dart` (सिर्फ `deleteSale` call करता है; पूरे `lib/web_live_sync/` में `cancelSale` का कोई UI call नहीं)।
   - **Root Cause:** Web UI में `cancelSale` action button जोड़ना छूट गया है।
3. **Live Testing Steps:**
   1. Web ERP खोलें -> Sales Summary view में जाएं।
   2. किसी भी active `W-` या `INV-` Sale Bill के action buttons/menu खोलें।
4. **Expected Result:** App की तरह Modify, Cancel, और Delete तीनों विकल्प दिखने चाहिए।
5. **Actual Buggy Result:** सिर्फ Modify और Delete दिखते हैं; Cancel Sale उपलब्ध ही नहीं है।
6. **Proof & Verification Target:** `web_sale_summary_view.dart` का widget tree / rendered row actions inspect करना।
7. **Risk Level:** **MEDIUM-HIGH**
8. **Reproduction Confidence:** **Code में Confirmed**

---

### `BUG-010`: Cancelling a Converted Sale Bill Leaves Linked Sale Challan Stuck in `"Billed"` Status (Cross-FY Included)
1. **Problem (आसान Hinglish में):** जब किसी Sale Challan से Sale Bill बनता है तो Challan `"Billed"` हो जाता है। अगर बाद में वह Sale Bill **Delete** हो तो Challan वापस `"Pending"` हो जाता है, **लेकिन अगर Sale Bill को Cancel किया जाए, तो न App और न Web उस Challan को वापस `"Pending"` करता है** — Challan हमेशा के लिए `"Billed"` फंसा रहता है और दुबारा बिल नहीं बन सकता।
2. **Code Location:**
   - App: `lib/pharoah_manager.dart` `cancelBill` (Lines `3778–3810`) बनाम `deleteBill` (Lines `3836+`). `cancelBill` में Challan revert logic नहीं है, और `onSaleCancelled` भी unawaited `.then()` में बिना `fy` के चलता है।
   - Web: `lib/web_live_sync/pharoah_web_manager.dart` `cancelSale` (Line `3165`) बनाम `deleteSale` (Line `3217`).
   - **Root Cause:** Challan revert hook सिर्फ Delete path में जोड़ा गया, Cancel path में नहीं।
3. **Live Testing Steps:**
   1. `FY 2026-27` में `SCH-0010` बनाएं (Pending), `FY 2027-28` में Carry Forward करें और उसे `INV-0005` Sale Bill में Convert करें।
   2. Verify करें कि `SCH-0010` `"Billed"` दिख रहा है।
   3. अब App में `INV-0005` को **Cancel** करें (Delete नहीं)।
   4. `SCH-0010` का status दोनों FY (`2026-27` व `2027-28`) में और Web पर check करें।
4. **Expected Result:** Bill Cancel होने पर Business rule स्पष्ट होना चाहिए — यदि माल की billing रद्द हो गई है तो Challan वापस `"Pending"` होना चाहिए (या explicit lock rule UI में दिखना चाहिए)।
5. **Actual Buggy Result:** `SCH-0010` permanently `"Billed"` against a `"Cancelled"` `INV-0005` फंसा रहता है; इसे दुबारा bill नहीं किया जा सकता।
6. **Proof & Verification Target:** `SCH-0010.status == "Billed"` जबकि `INV-0005.status == "Cancelled"`.
7. **Risk Level:** **HIGH**
8. **Reproduction Confidence:** **Code में Confirmed**

---

### `BUG-011`: App `updatePurchase` Runs Unawaited Sync, Omits `fy`, & Does Not Reconcile Edited `linkedChallanIds`
1. **Problem (आसान Hinglish में):** App में Purchase Entry edit करने पर sync calls background में बिना `await` किए और बिना `fy` parameter के भेजी जाती हैं; साथ ही edit में linked Purchase Challan बदलने पर पुराना Challan `"Pending"` पर वापस नहीं आता।
2. **Code Location:**
   - File: `lib/pharoah_manager.dart`, Method `updatePurchase`, Lines `1276–1386` (विशेषकर Line `1340` unawaited `.then()` और missing `fy` arguments).
   - **Root Cause:** Legacy async `.then()` chain बिना `await` और बिना challan-diff reconciliation।
3. **Live Testing Steps:**
   1. App में एक Purchase Entry को `PCH-0003` से link करके save करें (`PCH-0003` becomes `Billed`).
   2. तुरंत `updatePurchase` से edit करके तुरंत App/Cloud sync देखें (या linked challan हटाएं)।
4. **Expected Result:** D1 save await होकर current FY में जाए और unlinked `PCH-0003` वापस `"Pending"` हो।
5. **Actual Buggy Result:** `updatePurchase` D1 push finish होने से पहले ही return कर जाता है, `fy` pass नहीं होता, और unlinked `PCH-0003` `"Billed"` रह जाता है।
6. **Proof & Verification Target:** `pharoah_manager.dart` L1340 sync trace और `PCH-0003.status` check।
7. **Risk Level:** **MEDIUM-HIGH**
8. **Reproduction Confidence:** **Code में Confirmed**

---

### `BUG-012`: `FYTransferEngine` Carry-Forward Return Balance Ignores `partyId`, `paymentMode`, and `updatedAt`
1. **Problem (आसान Hinglish में):** नया Financial Year शुरू (`FYTransferEngine`) करते समय Credit Note और Debit Note का party balance केवल **party के नाम** (`_sameName`) से जोड़ा जाता है (Party ID और Cash vs Credit mode नहीं देखा जाता) और version tie होने पर `updatedAt` check नहीं होता।
2. **Code Location:**
   - File: `lib/fy_transfer_engine.dart`, Lines `101–129` (`dedupSr` Line `105`, `_sameName(sr.partyName, pName)` Line `110`, `dedupPr` Line `121`, `_sameName(pr.distributorName, pName)` Line `126`).
   - Compare with: `lib/logic/app_accounts_calculator.dart` Lines `189–206` (जहाँ `partyId` और `mode == 'CREDIT'` दोनों check होते हैं!).
   - **Root Cause:** `FYTransferEngine` में returns calculation `AppAccountsCalculator` जैसा strict नहीं है।
3. **Live Testing Steps:**
   1. `FY 2026-27` में एक Party पर **Cash Credit Note** (₹1,000 Cash refund) बनाएं (या दो parties में एक नाम बदलें)।
   2. `FY 2026-27` का closing balance `AppAccountsCalculator` में देखें और फिर `FY 2027-28` carry-forward opening balance चलाएं।
4. **Expected Result:** Cash Credit Note party credit ledger balance नहीं घटाना चाहिए (क्योंकि पैसा पहले ही cash दे दिया गया), और opening balance live ledger से 100% match होना चाहिए।
5. **Actual Buggy Result:** `FYTransferEngine` Cash Credit Note को भी `runningBal -= sr.totalAmount` करके अगले साल के Opening Balance में गड़बड़ी ला सकता है।
6. **Proof & Verification Target:** `FY 2026-27` live party balance बनाम `FY 2027-28` carried `opBal` comparison।
7. **Risk Level:** **HIGH (Accounting Accuracy)**
8. **Reproduction Confidence:** **Code में Confirmed**

---

## 9. Code-Level Root Cause (Architecture Map)

पूरे 6-module sync pipeline की असली विफलता किसी एक line में नहीं, बल्कि **5 Architectural Gaps** में है:

1. **Asymmetric Snapshot Merge (`google_backend/Code.js` L781–947):**
   - `AppSyncEngine` व `WebSyncEngine` पूरा store snapshot (`sales.json`, `purc.json`, `s_return.json`, `p_return.json`, `s_challan.json`, `p_challan.json`, etc.) एक POST में भेजते हैं।
   - `Code.js` ने Challans (`s_challan.json`, `p_challan.json`) के लिए per-record version/updatedAt merge implement कर दिया, **लेकिन Sales, Purchases, Credit Notes, Debit Notes के लिए raw slice replacement (`hasInSlice ? inSlice : exSlice`) ही छोड़ दिया**।
2. **Volatile In-Memory Outbox (`SyncQueueManager` L16–20):**
   - D1 `erp_master_sync` पर जाने वाला queue disk-backed नहीं है। App kill या Browser `F5` से offline mutations permanently lost हो जाते हैं।
3. **Server-Side & Client-Side Clock / Version Flaws:**
   - `lab_signal.ts` L590 (`Math.max(op.updated_at, nowMs)`) stale edits को future timestamp दे देता है।
   - `D1SalesLedgerService` L1244, L1775, L2892, L3043 में `version >= local.version || updatedAt >= local.updatedAt` की OR logic से lower-version भी overwrite कर सकती है।
   - `SalesSyncModule` / `CreditNoteSyncModule` / `DebitNoteSyncModule` `exactVersion` pass नहीं करते जिससे dual-path (`sale_events` vs `erp_master_sync`) में version `v1` vs `v2` का skew बनता है।
4. **Tombstone & Semantic Bypass:**
   - `MasterSyncOrchestrator` (App L224/L648/L664, Web L1014/L1373/L1384) और `D1SalesLedgerService` merge से पहले ही `unmarkPermanentlyDeleted()` चलाकर tombstones साफ कर देते हैं।
   - Web `_parseDownloadedFiles` & `purgeDeletedIds` Sales/Returns पर **unscoped `billNo`** इस्तेमाल करते हैं, जबकि Challans properly `scopeSecondaryKey(no, fy)` इस्तेमाल करते हैं।
   - Credit/Debit Notes में `Delete` (`isDeleted=1`) और `Cancel` (`status="Cancelled"`) sync payloads में mixed हैं और D1 `lab_signal.ts` L295-315 में Return types का अपना event bucket नहीं है।
5. **Fragile Text Protocol Checks:**
   - `app_sync_engine.dart` (L100, L501) व `fast_pull_engine.dart` (L99, L511) में `.contains("ERROR")` और `pharoah_web_manager.dart` (L2844) में `statusCode == 200 || contains("SUCCESS")` data corruption का सीधा रास्ता खोलते हैं।

---

## 10. Storage और Recovery Analysis

| Storage Layer | Stored Data | Persistence Durability | Vulnerability / Recovery Risk |
| :--- | :--- | :--- | :--- |
| **App Local Disk (`Documents/fy_<FY>/`)** | Local FY JSON files (`sales.json`, `purc.json`, `s_challan.json`, `p_challan.json`, `s_return.json`, `p_return.json`, tombstones, HWM) | **High** (App uninstall/clear data तक सुरक्षित) | `SyncQueueManager` outbox disk पर नहीं जाता, सिर्फ saved state जाती है; unpushed delete/edit crash में cloud तक नहीं पहुँचता। |
| **Web Local Storage (`SharedPreferences` + RAM)** | Active `financialYear`, `challan_hwm_*`, local tombstone hints, in-memory lists | **Low** (Browser cache clear या Incognito में **0% durability**) | Cache clear या `F5` से `SyncQueueManager` (RAM) उड़ जाता है; recovery पूरी तरह Drive + D1 पर निर्भर। |
| **Cloudflare D1 (`sale_events`, `erp_master_sync`, `signal_events`, `batch_operations`)** | Delta mutations, idempotency, tombstones, signals | **High (Server SQLite)** | `signal_events` 300 rows पर trim; `sale_events` 1,250/call fetch cap; `CREDIT_NOTE`/`DEBIT_NOTE` `"SALE"`/`"PURCHASE"` में misclassified; `updated_at` clamped to `nowMs`. |
| **Google Drive (`<TOKEN>.json` via `Code.js`)** | Monolithic single JSON: active FY + Multi-FY Vault + config + HWM + tombstones | **High (Google Drive)** | `Code.js` concurrent push पर Sales/Purchases/Returns को overwrite करता है (`BUG-001`); 1+ साल बाद single JSON size बढ़ने पर GAS 6-min timeout risk। |
| **Recovery on Fresh Login / Cache Wipe** | Step 1: GAS `PULL_STORE_DATA` -> Step 2: `D1` deltas/events overlay | **Partial / Fragile** | अगर Drive `<TOKEN>.json` में `BUG-001` से कोई bill overwrite हो गया था और D1 `sale_events` 1,250 limit से पहले cycle में पूरा न आए (या `"ERROR"` text से pull abort हो जाए), तो recovery अधूरी रहेगी। |

---

## 11. Failed / Passed / Not Verified Tests

ईमानदारी और engineering accuracy के लिए test results को 3 साफ श्रेणियों में बांटा गया है:

### 11.1 Code-Audit Failed Checks (Static Verification Confirmed)
- **FAIL-01:** `google_backend/Code.js` concurrent push protection for Sales, Purchases, Credit Notes, Debit Notes (`BUG-001`).
- **FAIL-02:** `SyncQueueManager` crash/restart/`F5` outbox durability (`BUG-002`).
- **FAIL-03:** `lab_signal.ts` offline `updated_at` server-time preservation (`BUG-003`).
- **FAIL-04:** `app_sync_engine.dart` & `fast_pull_engine.dart` `"ERROR"` payload safety (`BUG-004`).
- **FAIL-05:** `MasterSyncOrchestrator` & `D1SalesLedgerService` tombstone protection against zombie resurrection in Sales & Returns (`BUG-006`).
- **FAIL-06:** Credit Note & Debit Note Delete vs Cancel separation + D1 `sale_events` entity classification (`BUG-007`).
- **FAIL-07:** Web FY-scoped tombstone isolation for Sales & Returns (`BUG-008`).
- **FAIL-08:** Web Sale Summary UI parity for Cancel Sale (`BUG-009`).
- **FAIL-09:** Converted Sale Challan revert on linked Sale Bill Cancel (`BUG-010`).
- **FAIL-10:** `FYTransferEngine` return partyId/paymentMode/updatedAt parity (`BUG-012`).

### 11.2 Existing Automated Unit/Regression Tests in Repository (`test/` — Code Present, Not Executed Here)
Repository में `16` Dart test files मौजूद हैं (जैसे `challan_fy_identity_numbering_cross_sync_test.dart`, `challan_fy_recovery_p0_test.dart`, `stitcher_cf_and_challan_revert_regression_test.dart`, `purchase_recreation_sync_regression_test.dart`, `multi_fy_purchase_regression_test.dart`, `return_history_engine_test.dart`, `e2e_sync_test.dart`)।  
*Audit Rule के अनुसार इस environment में कोई build/test run नहीं किया गया है — इसलिए इन्हें **Passed** mark नहीं किया जा रहा; इन्हें `Existing Regression Suites (Execution Pending)` माना जाए।*

### 11.3 Live Bidirectional, 50-Record Stress & Long-Term Tests (`PROPOSED / NOT VERIFIED`)
- **NOT VERIFIED (Pending Live Run):** Test A (Web → App 50 records × 6 modules = 300 creates + modifies/deletes/cancels/recreations)
- **NOT VERIFIED (Pending Live Run):** Test B (App → Web 50 records × 6 modules = 300 creates + modifies/deletes/cancels/recreations)
- **NOT VERIFIED (Pending Live Run):** Test C (Repeated stress cycles on live Cloudflare D1 + Google Drive GAS)
- **NOT VERIFIED (Pending Live Run):** 1-Year Zero-Usage Simulation, Browser Cache Clear + Fresh Login Cold-Boot Recovery on Multi-Thousand-Record `<TOKEN>.json`.

---

## 12. Overall Risk Assessment

| Priority Tier | Scope | Business Impact |
| :---: | :--- | :--- |
| **P0 — Critical Blockers (Immediate Data Loss / Corruption)** | `Code.js` snapshot overwrites (`BUG-001`), RAM-only `SyncQueueManager` (`BUG-002`), Return Delete=Cancel & D1 misrouting (`BUG-007`), Orchestrator/D1 unmark-first resurrection (`BUG-006`), Web unscoped Return/Sale FY purge (`BUG-008`) | **Multi-device काम करने पर बिना किसी error message के bills और returns गायब हो सकते हैं या दूसरे FY में मिट सकते हैं।** |
| **P1 — High Financial & Operational Risk** | D1 `updated_at` clamping (`BUG-003`), `"ERROR"` substring sync abort (`BUG-004`), Cancelled Bill leaving Challan `"Billed"` (`BUG-010`), `FYTransferEngine` return partyId/Cash mode bug (`BUG-012`), Web missing Cancel Sale UI (`BUG-009`) | **गलत Party Opening Balance, stuck Challans, और stale overwrites।** |
| **P2 — Medium Scalability & Robustness Risk** | D1 1,250-event cursor cap (`BUG-005`), Dual-path version skew, App `updatePurchase` unawaited sync & missing `fy` (`BUG-011`), Web `addSaleAndSync` / `addReturn` missing `fy` | **बड़े/पुराने stores (1+ year) और FY-switch boundary पर incomplete catch-up।** |

---

## 13. Recommended Fix Priority (Action Roadmap — Code Changes Not Applied Yet)

1. **P0-1 (`google_backend/Code.js`):** `sales.json`, `purc.json`, `s_return.json`, `p_return.json` के लिए भी `s_challan.json` जैसा per-ID/per-FY/per-version/tombstone-aware merge implement करें और silent `catch(mergeErr) {}` हटाकर proper error status लौटाएं।
2. **P0-2 (`SyncQueueManager`):** `_outboxBufferQueue` को `SharedPreferences` (Web/App) या SQLite/file disk queue में persist करें; per-item `storeToken` भेजें; 150ms loop की जगह exponential backoff लगाएं।
3. **P0-3 (`MasterSyncOrchestrator` + `D1SalesLedgerService` + `Sales/Credit/DebitNoteSyncModule`):** Merge से पहले `unmarkPermanentlyDeleted()` हटाएं; tombstone check पहले करें (और केवल explicit user re-create पर ही newer timestamp/version से unmark होने दें); `|| updatedAt >=` OR overwrite हटाकर strict `(version > local.version) || (version == local.version && updatedAt > local.updatedAt)` नियम लागू करें; `exactVersion` skew बंद करें।
4. **P0-4 (Credit Note & Debit Note Repair):**
   - `SaleReturn` और `PurchaseReturn` models में `originalFy` जोड़ें।
   - `CreditNoteSyncModule` व `DebitNoteSyncModule` में `Delete` (`isDeleted=1`, status unchanged/deleted) और `Cancel` (`status="Cancelled"`, `isDeleted=0`) को पूरी तरह अलग करें; `delta_merge_engine.dart` L151 से `"Cancelled"` को deleted मानना बंद करें।
   - `functions/api/lab_signal.ts` में `CREDIT_NOTE` (`SALE_RETURN`) और `DEBIT_NOTE` (`PURCHASE_RETURN`) के लिए dedicated D1 `sale_events` categories जोड़ें।
   - `pharoah_web_manager.dart` (`purgeDeletedIds`, `_parseDownloadedFiles`) में Sale व Return tombstones को Challans की तरह `scopeSecondaryKey(billNo, fy)` से scope करें।
5. **P1-1 (`functions/api/lab_signal.ts` L590):** `Math.max(op.updated_at, nowMs)` हटाकर client mutation `updated_at` preserve करें (या strict monotonic `version` को tie-breaker बनाएं)।
6. **P1-2 (`app_sync_engine.dart`, `fast_pull_engine.dart`, `pharoah_web_manager.dart`):** `.contains("ERROR")` की जगह proper JSON parse करके `json['status'] == 'ERROR'` check करें; pull fail होने पर Drive push रोकें (`abort push if pull failed`)।
7. **P1-3 (UI & Business Parity):** `web_sale_summary_view.dart` में `cancelSale` UI button जोड़ें; App `cancelBill` व Web `cancelSale` में linked Sale Challans के लिए clear revert/unblock rule लागू करें; `updatePurchase` में `await` + `fy` + `linkedChallanIds` diff reconciliation जोड़ें।
8. **P1-4 (`lib/fy_transfer_engine.dart`):** Carry-forward balance में `SaleReturn` / `PurchaseReturn` के लिए `partyId`, `paymentMode == 'CREDIT'`, और `updatedAt` tie-break वही रखें जो `AppAccountsCalculator` में है।
9. **P2-1 (Long-Term 1+ Year Hardening):** `D1SalesLedgerService.fetchSaleDeltasWithCursor` में 5-page limit हटाकर full cursor drain (with safe pagination) चलाएं और Google Drive `<TOKEN>.json` से archived FY data को separate per-FY Drive files में shard करने की योजना बनाएं।

---

## 14. Final Conclusion

Pharoah ERP में **Sale Challan** और **Purchase Challan** पर हालिया engineering work (FY-scoped keys, `originalFy`, `ChallanHwmState`, tail-only delete rollback, और cross-FY Converted Bill Delete → Pending Challan Revert) काफी मजबूत दिखता है।  
लेकिन **बाकी 4 Modules — खासकर Credit Note, Debit Note, Sale Bill, और Purchase Entry — तथा core Sync Infrastructure (`Code.js` unmerged Drive push, RAM-only `SyncQueueManager`, D1 `updated_at` clamping, Unscoped Web Tombstones, और Orchestrator unmark-first resurrection)** अभी concurrent App ↔ Web production stress या 1+ year cache-clear recovery के लिए **सुरक्षित नहीं हैं**।

**अंतिम सुझाव:** ऊपर दिए गए **P0 और P1 fixes** लागू किए बिना 50-record concurrent stress test या production multi-device rollout में **data loss, zombie bills, और cross-FY return deletion** लगभग निश्चित रूप से सामने आएंगे। Fix करने के तुरंत बाद Section 4 के सभी 6 × 50-record bidirectional tests और Section 6 के cross-FY tests को live App + Web पर run करके verify किया जाना चाहिए।
