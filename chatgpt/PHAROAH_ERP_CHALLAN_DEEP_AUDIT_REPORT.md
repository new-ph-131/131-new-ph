# PHAROAH ERP — DEEP CHALLAN WORKFLOW AUDIT REPORT
**Repository:** `new-ph-131/131-new-ph` (`main` @ `69919cf`)  
**Audit Mode:** Read-Only Deep Investigation (कोई भी Production Code या Business Logic बदला नहीं गया है)  
**भाषा:** हिन्दी (Devanagari) + सटीक English Technical Terms / File Paths / Symbol Names  

---

## Executive Summary (संक्षिप्त निष्कर्ष)

इस गहन audit में पूरे **Sale Challan**, **Purchase Challan**, **Challan-to-Bill Conversion**, **Converted Bill Edit/Delete**, **Financial Year (FY) Carry-Forward & Cascade**, **App ↔ Web 9-Layer Real-Time Sync (`RECENT STORE DISPATCHES`)**, और **Web Challan Product Selection Bug** का source-code स्तर पर पूरा विश्लेषण किया गया है।

मुख्य रूप से तीन बड़े क्षेत्रों में वास्तविक, verifiable code-level defects पाए गए हैं:
1. **FY Transfer + Converted Bill Delete Pending Recovery Failure (FY `2025-26` → `2026-27`):** जब पिछली FY (`2025-26`) का कोई converted Bill delete होता है, तो जुड़ा हुआ Challan केवल `2025-26` में `Pending` होता है। वह `2026-27` में **7 अलग-अलग broken links** की वजह से नहीं आता:
   - App `deleteBill` / `deletePurchase` और Web `deleteSale` / `deletePurchase` delete के बाद FY cascade नहीं चलाते।
   - App `switchYear` FY बदलने पर भी `syncOpeningBalancesFromPreviousYear` नहीं चलाता।
   - Web `_hotSwapActiveYearMastersFromVault()` `s_challan.json` और `p_challan.json` को hot-swap ही **नहीं** करता!
   - `D1SalesLedgerService` और cross-FY edge delta pipelines (`_applyEdgeEventsToFyVault`, `applyCrossFyEdgeEventsToLocalDisk`) में Challans और linked-challan revert का कोई handler ही नहीं है (`deleteBill` में `fy: currentFY` भी missing है)।
   - `MasterSyncOrchestrator.dispatchEnvelope` cross-FY `DELETE` envelopes को line 73 पर drop कर देता है और Web Purchase Delete handler `purgeDeletedIds` पहले चलाकर `linkedChallanIds` पढ़ने का मौका ही खत्म कर देता है।
   - `FYTransferEngine.cascadeSingleYearStep` यदि target FY में challan ID पहले से मौजूद हो तो उसे skip कर देता है।
   - `AppRealtimeCoordinator` Signal #1 पहले भेजता है और full multi-FY Drive vault upload बाद में करता है — जिससे receiver पुराना snapshot पढ़ लेता है।
2. **Real-Time Dispatch & `RECENT STORE DISPATCHES` Updates:** Web `RECENT STORE DISPATCHES` `date` से sort करता है (`updatedAt` से नहीं), Web की चारों challan mutation methods `_snapshotActiveFyToVault()` नहीं चलातीं, `WebNewSaleView` single-bill conversion में `SaleChallanSyncModule` / `version` / `updatedAt` update नहीं करता, और `FastPullEngine` में `sale_events` के अंदर challan fast-path नहीं है।
3. **Web Challan Product Selection (10–12 taps bug):** `WebSaleChallanBillingView` और `WebPurchaseChallanBillingView` में product search dropdown `Container` के अंदर बिना `Material` wrapper और बिना item `Key` के `ListView.builder(shrinkWrap: true)` में है, जबकि दोनों full pushed `Scaffold` में `Provider.of<PharoahWebManager>(context)` (`listen: true`) से हर 12s के unconditional `refreshStoreData` (`rebuildInventory()` + `notifyListeners()`) पर rebuild होते हैं, और `onTap` से HTML `<input>` focus loss / `viewInsets` collapse व `productSearchC.clear()` synchronously उसी frame में dropdown unmount कर देते हैं।

---

# PART 1 — CHALLAN BUSINESS LOGIC (सभी 14 Workflows का पूरा मानचित्र)

| # | Workflow | Model / Identity Keys | मुख्य Files और Functions | Status & Storage Lifecycle (Local / DB / Cloud / Sync) |
|---|---|---|---|---|
| 1 | **Sale Challan Model & Identity** | `SaleChallan` (`id`, `billNo` e.g. `CH-1` / `SCH-WEB-<ts>`, `partyId`, `date`, `items: List<BillItem>`, `status`: `"Pending"` / `"Billed"` / `"Cancelled"`, `updatedAt`, `version`, `isDeleted`). Identity: `id` या uppercase `billNo`. | `lib/models/bill.dart` (या challan model definitions), `lib/pharoah_manager.dart`, `lib/web_live_sync/pharoah_web_manager.dart` | Local disk JSON: `s_challan.json` (per FY folder). D1 Outbox: `SaleChallanSyncModule` (`lib/sync_core/modules/sale_challan_sync_module.dart`), Drive vault JSON `s_challan.json`. |
| 2 | **Purchase Challan Model & Identity** | `PurchaseChallan` (`id`, `internalNo` e.g. `PCH-1` / `PCH-WEB-1`, `billNo` = Supplier Ref No, `partyId`, `date`, `items: List<PurchaseItem>`, `status`: `"Pending"` / `"Billed"`, `updatedAt`, `version`, `isDeleted`). Identity: `id`, `internalNo`, व case-sensitive composite `partyId_billNo` / `partyId_billNo_internalNo`. | `lib/pharoah_manager.dart`, `lib/web_live_sync/pharoah_web_manager.dart` (`_parseDownloadedFiles:1093-1200`), `lib/sync_core/modules/purchase_challan_sync_module.dart` | Local disk JSON: `p_challan.json` (per FY folder). **गंभीर नोट:** `deletePurchaseChallan` App (`2973`) व Web (`2710`) में `D1SalesLedgerService.markPurchasePermanentlyDeleted(...)` को call करता है — यानी Purchase Challan और Purchase Bill एक ही tombstone registry share करते हैं! |
| 3 | **Challan Create** | App Sale: `CH-<n>` (`billNo`); Web Sale: `SCH-WEB-<ts>`. App Purchase: `PCH-<n>`; Web Purchase: `PCH-WEB-<n>`. Initial `status = "Pending"`. | **App:** `lib/challans/sale_challan_view.dart`, `sale_challan_billing_view.dart`, `purchase_challan_view.dart`, `purchase_challan_billing_view.dart`, `PharoahManager.finalizeSaleChallan` (`1111-1184`), `finalizePurchaseChallan` (`1186-1265`).<br>**Web:** `web_sale_challan_billing_view.dart`, `web_purchase_challan_billing_view.dart`, `PharoahWebManager.addSaleChallanAndSync` (`2504-2571`), `addPurchaseChallanAndSync` (`2573-2664`). | App: memory update -> `saveToDisk` -> `SaleChallanSyncModule`/`PurchaseChallanSyncModule` enqueue -> `notifyAppMutation` (`CHALLAN_SYNC` / `PURCHASE_CHALLAN_SYNC`).<br>**Gap:** App `finalize*` में `.then((t) => SyncQueueManager.enqueue(...))` बिना `await` के चलता है, और Web `addSaleChallanAndSync` / `addPurchaseChallanAndSync` में `_snapshotActiveFyToVault()` call ही **नहीं** होता! |
| 4 | **Challan Edit** | Same `id` और `billNo`/`internalNo` retain होता है। | **App:** `SaleChallanRegister` (`lib/challans/sale_challan_register.dart:315` पर `Billed` guard है) -> `SaleChallanBillingView`; `PurchaseChallanRegister` (`lib/challans/purchase_challan_register.dart:259` — यहाँ **`Billed` guard missing** है!) -> `PurchaseChallanBillingView`.<br>**Web:** `WebChallanView` (`web_challan_view.dart:232, 423` दोनों पर `Billed` guard है) -> `WebSaleChallanBillingView` / `WebPurchaseChallanBillingView`. | Edit पर `status` normally `"Pending"` रहता है (`existingRecord?.status ?? "Pending"`).<br>**Gap:** App `PurchaseChallanRegister` पर `Billed` Challan को edit से नहीं रोका जाता और card पर Pending/Billed badge भी नहीं दिखता। |
| 5 | **Challan Delete** | Tombstone / Soft-delete + cloud D1 delete. | **App:** `PharoahManager.deleteSaleChallan` (`2929-2957`), `deletePurchaseChallan` (`2958-2999`).<br>**Web:** `PharoahWebManager.deleteSaleChallan` (`2666-2693`), `deletePurchaseChallan` (`2695-2744`). | App & Web दोनों list से हटाते हैं (`s_challan.json`/`p_challan.json` save), outbox delete भेजते हैं (`SaleChallanSyncModule.onSaleChallanDeleted` / `PurchaseChallanSyncModule.onPurchaseChallanDeleted`), और Purchase Challan में `markPurchasePermanentlyDeleted` + `deletedPurchaseTombstones` record करते हैं। Web में `_snapshotActiveFyToVault()` missing है। |
| 6 | **Pending / Active / Billed Status** | Active / Unconverted = `"Pending"`; Converted = `"Billed"`; (कुछ जगह `"Cancelled"` check भी है)। | `PharoahManager`, `PharoahWebManager`, `ChallanStitcherWizard`, `WebChallanStitcherWizard`, `FYTransferEngine` (`lib/fy_transfer_engine.dart`). | Single source of truth JSON field `status` में है। Stock impact को ध्यान में रखें: केवल `Billed` होने या direct bill बनने पर ही ledger/bill settlement होती है (Sale Challan stock deduct करता है या dispatch hold करता है — convert होने पर double-deduction से बचने के लिए `linkedChallanIds` / `sourceChallanId` का इस्तेमाल होता है)। |
| 7 | **Challan → Sale Bill Conversion** | `Bill.linkedChallanIds` (`List<String>`) + item `sourceChallanId` / `sourceChallanNo`. Single Challan या Multi-Challan Stitch दोनों supported हैं। | **App:** `lib/challans/challan_to_bill_converter.dart`, `challan_stitcher_wizard.dart`, `PharoahManager.addSale` (`690-745`).<br>**Web:** `lib/web_live_sync/web_challan_stitcher_wizard.dart`, `sub_views/web_billing/web_new_sale_view.dart` (`440-446`), `PharoahWebManager`. | `PharoahManager.addSale` व `WebChallanStitcherWizard` converted challans को `"Billed"` mark कर `version++`, `updatedAt` और `SaleChallanSyncModule.onSaleChallanSaved` चलाते हैं।<br>**Critical Bug in Web Single Conversion (`web_new_sale_view.dart:440-446`):** `WebNewSaleView._saveInvoice` केवल `status = "Billed"` set करता है — **न `version++`, न `updatedAt`, न `SaleChallanSyncModule.onSaleChallanSaved`!** यानी cloud D1 में challan `"Pending"` ही रह जाता है। |
| 8 | **Challan → Purchase Bill Conversion** | `Purchase.linkedChallanIds` + item `sourceChallanId` / `sourceChallanNo`. | **App:** `challan_to_bill_converter.dart`, `challan_stitcher_wizard.dart`, `PharoahManager.addPurchase` (`850-900`).<br>**Web:** `web_challan_stitcher_wizard.dart`, `sub_views/web_purchase/ui/web_purchase_billing_screen.dart`, `PharoahWebManager`. | `PharoahManager.addPurchase` व Web Stitcher matching `PurchaseChallan` का `status = "Billed"` करते हैं और `PurchaseChallanSyncModule.onPurchaseChallanSaved` से sync करते हैं। |
| 9 | **Converted Bill Edit** | Saved `Bill.linkedChallanIds` और item links Edit flow में आगे carry होना ज़रूरी है। | **App:** `sale_bill_modify_view.dart` → `sale_entry_view.dart` (`218, 237`) → `billing_view.dart` (`23, 278`); `purchase_modify_view.dart` → `purchase_entry_view.dart` (`238`) → `purchase_billing_view.dart` (`24, 317, 328`).<br>**Web:** `web_new_sale_view.dart`, `web_purchase_entry_view.dart` (`67`), `web_purchase_billing_screen.dart` (`217`). | Verified: App और Web दोनों के Modify workflows `linkedChallanIds` को preserve करते हैं ताकि बाद में Bill delete करने पर भी challan link न टूटे। |
| 10 | **Converted Bill Delete** | Bill की `linkedChallanIds` + हर item के `sourceChallanId`/`sourceChallanNo` से matching challan खोजकर `"Pending"` किया जाता है। | **App:** `PharoahManager.deleteBill` (`2756-2832`), `deletePurchase` (`2833-2928`).<br>**Web:** `PharoahWebManager.deleteSale` (`2120-2185`), `deletePurchase` (`2325-2420`).<br>**Remote Envelope:** `MasterSyncOrchestrator.dispatchEnvelope` (`lib/sync_core/orchestrator/master_sync_orchestrator.dart`). | **बड़ा अंतर & Bug:** Active FY में local revert होता है, पर **न तो cross-FY cascade चलता है** और न ही D1/Outbox delete handlers back-FY में मौजूद challan को revert करते हैं। Web `MasterSyncOrchestrator` line `631` पर `purgeDeletedIds` पहले कर देता है और line `641` पर deleted purchase को `phWeb.purchases` में ढूँढता है! |
| 11 | **Pending Challan Recovery Logic** | Deleted bill से जुड़े सभी IDs (`linkedChallanIds`, `sourceChallanId`, `sourceChallanNo`) को collect कर challan `status = "Pending"`, `version++`, `updatedAt = now` किया जाता है। | App & Web delete methods + `MasterSyncOrchestrator`. | Active FY में काम करता है। **Failure Case:** यदि user FY `2026-27` में है और Bill FY `2025-26` का है (या `2025-26` में delete करके `2026-27` में देखा जाए), तो recovered `"Pending"` challan `2026-27` में **नहीं** पहुँचता (Part 2 में पूरा trace)। |
| 12 | **FY Transition & Carry Forward** | Rule: `computeCarryForwardFromFiles` (`lib/fy_transfer_engine.dart:360-364, 473-474`) केवल `c.isDeleted != 1 && c.status == "Pending"` challans को अगले FY में carry-forward करता है। | `FYTransferEngine` (`computeCarryForwardFromFiles`, `cascadeSingleYearStep:821-837`), `PharoahManager.startNewFinancialYear` (`3358-3430`), `syncOpeningBalancesFromPreviousYear` (`3679-3757`), `silentAutoCascadeFromBackYear` (`3762-3774`), `PharoahWebManager.startNewFinancialYearOnWeb` (`3918-3960`), `silentAutoCascadeMultiYear` (`1654-1662`). | Initial FY transition में `"Billed"` challans next FY में copy **नहीं** होते। बाद में back FY में बिल delete होने पर challan वापस `"Pending"` बनता है — लेकिन automatic multi-year recovery broken है। |
| 13 | **App ↔ Web Challan Sync** | दो main pipelines: (a) Full/Vault JSON Sync (`pushUpdatedDataToCloud` / Drive vault + `s_challan.json`, `p_challan.json`), (b) Incremental D1 Outbox `erp_master_sync` (`SaleChallanSyncModule`, `PurchaseChallanSyncModule`), (c) Instant signal (`CloudSignalChannel` / `/api/lab_signal`). | `lib/sync_core/modules/sale_challan_sync_module.dart`, `purchase_challan_sync_module.dart`, `lib/sync_core/outbox/sync_queue_manager.dart`, `lib/sync_core/orchestrator/master_sync_orchestrator.dart`, `lib/sync_core/d1_sales_ledger_service.dart`, `lib/realtime_signaling/...`. | Note: `D1SalesLedgerService` (`sale_events` fast delta path) व `FastPullEngine` केवल Sales/Purchases/Returns संभालते हैं — Challans के लिए `D1SalesLedgerService` handler मौजूद **नहीं** है! |
| 14 | **Store Dispatch / Recent Store Dispatches** | Web Sale Challan dashboard पर top 5 recent dispatches; Purchase Challan dashboard पर `RECENT INWARD RECEIPTS`. | `lib/web_live_sync/sub_views/web_challans/web_sale_challan_view.dart` (`_buildStoreRecentChallansCard`, lines `1528-1679`), `web_purchase_challan_view.dart` (`1669+`). | `webPh.saleChallans` को `b.date.compareTo(a.date)` से sort कर top 5 दिखाता है (`updatedAt` से नहीं)। बैकग्राउंड `_safetyHeartbeatTimer` हर 12s पर `refreshStoreData` चलाता है (Part 3 देखें)। |

---

# PART 2 — FY TRANSFER और CONVERTED BILL DELETE की समस्या (FY `2025-26` → `2026-27`)

## वास्तविक User Flow क्यों टूटता है? (Step-by-Step Root Cause Trace)

**Scenario:**
1. FY `2025-26` में एक **Challan C1** (`Pending`) बना और उसी FY `2025-26` में **Bill B1** में convert हो गया → C1 का status `"Billed"` हो गया।
2. अब **FY `2026-27`** शुरू हुई (`startNewFinancialYear` / `startNewFinancialYearOnWeb`)।
   - `FYTransferEngine.computeCarryForwardFromFiles` (`lib/fy_transfer_engine.dart:360-364, 473-474`) ने केवल `c.isDeleted != 1 && c.status == "Pending"` challans को `2026-27` में भेजा। चूँकि C1 उस समय `"Billed"` था, **C1 को `2026-27` में नहीं लाया गया** (यहाँ तक rule सही था)।
3. अब user या तो App या Web से FY `2025-26` में जाकर **Converted Bill B1 Delete** करता है।
   - `2025-26` में C1 वापस `"Pending"` हो जाता है।
   - **लेकिन FY `2026-27` में C1 दिखाई नहीं देता!**

इस failure के पीछे **7 verified root causes** हैं (जो App और Web दोनों, तथा Sale और Purchase Challan दोनों को प्रभावित करते हैं):

### Root Cause 1 — Bill Delete के बाद App और Web दोनों FY Cascade नहीं चलाते
- **App (`lib/pharoah_manager.dart`):**
  - `deleteBill` (`2756-2832`) व `deletePurchase` (`2833-2928`) active `currentFY` (`2025-26`) में linked challan का `status = "Pending"` करके केवल current FY के `s_challan.json`/`p_challan.json` save करते हैं।
  - ये **कभी भी** `silentAutoCascadeFromBackYear(currentFY)` या `syncOpeningBalancesFromPreviousYear(...)` call नहीं करते — इसलिए App के local disk पर मौजूद `2026-27/s_challan.json` और `2026-27/p_challan.json` कभी update नहीं होते!
- **Web (`lib/web_live_sync/pharoah_web_manager.dart`):**
  - `deleteSale` (`2120-2185`) और `deletePurchase` (`2325-2420`) `_snapshotActiveFyToVault()` तो चलाते हैं (जिससे `2025-26` vault में C1 `"Pending"` हो जाता है), लेकिन delete के बाद `_cascadeWebFyVaultFrom(financialYear)` **नहीं** चलाते।
  - हाँ, Web में `switchWebFinancialYear` (`line 3884`) `_cascadeWebFyVaultFrom` call करता है और `pushUpdatedDataToCloud` (`line 1938`) push के समय cascade करता है — **परंतु App में `switchYear` पर भी कोई cascade नहीं है!**

### Root Cause 2 — App `switchYear()` Carry-Forward / Cascade Trigger ही नहीं करता
- `PharoahManager.switchYear(String year)` (`lib/pharoah_manager.dart:305-326`) में सिर्फ `currentFY = year` होता है और `loadAllData()` run होता है।
- यदि आपने App पर `2025-26` में B1 delete किया और तुरंत App को `2026-27` में switch किया, तो App पुरानी `2026-27/s_challan.json` ही load करेगा — C1 वहाँ बिल्कुल नहीं मिलेगा!
- इसके अलावा `PharoahManager.loadAllData` (`569`) और `_reloadMemoryFromDisk` (`3651`) में भी Purchase Challans पर inconsistency है: `loadAllData:569` `isPurchaseDeleted(..., currentFY)` को बिना `c.updatedAt` call करता है, और `_reloadMemoryFromDisk:3651` `isPurchaseDeleted(c.id, c.partyId, c.billNo, c.internalNo)` को बिना `currentFY` और बिना `c.updatedAt` call करता है (यदि कभी same ref re-create या stale tombstone हो तो silently filter हो सकता है)।

### Root Cause 3 — Web `_hotSwapActiveYearMastersFromVault()` Challans (`s_challan.json` / `p_challan.json`) को Hot-Swap ही नहीं करता!
- यह Web पर सबसे बड़ा silent blocker है (`lib/web_live_sync/pharoah_web_manager.dart:1556-1648`)।
- मान लीजिए Web `2026-27` पर खुला है। जब पीछे से cascade या App sync `2025-26` से `2026-27` vault (`_fyVaultCache["2026-27"]`) में `Pending` challan C1 डालता है, तब `silentAutoCascadeMultiYear` (`1654-1662`) `_cascadeWebFyVaultFrom` के बाद `_hotSwapActiveYearMastersFromVault()` call करता है।
- लेकिन `_hotSwapActiveYearMastersFromVault()` केवल `parties`, `carriedPendingInvoices`, `batchHistory`, `banks` और `rebuildInventory()` reload करता है — **`s_challan.json` और `p_challan.json` को बिल्कुल पढ़ता ही नहीं!**
- नतीजा: Web की memory में `webPh.saleChallans` और `webPh.purchaseChallans` पुराने ही रहते हैं और UI पर C1 कभी नहीं दिखता!

### Root Cause 4 — Cross-FY `D1SalesLedgerService` (`sale_events`) और Edge Delta Pipelines Challans के लिए Blind हैं
- जब App `2025-26` में B1 delete करता है और Web `2026-27` पर खुला है (या vice versa):
  1. `D1SalesLedgerService` (`lib/sync_core/d1_sales_ledger_service.dart`) में केवल `applyEventsToLocalSales`, `Purchases`, `SaleReturns`, `PurchaseReturns` हैं — **Challans और Linked Challan Revert के लिए कोई function ही नहीं है**।
  2. `PharoahManager.deleteBill` (`2802`) `D1SalesLedgerService.onSaleDeleted(...)` में **`fy: currentFY` pass ही नहीं करता** (जबकि `deletePurchase` या बाकी calls में `fy` जरूरी है)।
  3. `PharoahWebManager._applyEdgeEventsToFyVault` (`1726-1880`) और `MultiFyCloudVault.applyCrossFyEdgeEventsToLocalDisk` (`lib/sync_core/multi_fy_cloud_vault.dart:681-831`) जब `2025-26` के लिए `DELETE` event पाते हैं, तो वे केवल `sales.json` / `purchase.json` से bill हटाते हैं — **वे उस bill से जुड़े `s_challan.json` / `p_challan.json` के challans को `"Pending"` में revert नहीं करते** और न ही `SALE_CHALLAN` / `PURCHASE_CHALLAN` deltas संभालते हैं!

### Root Cause 5 — Cross-FY `MasterSyncOrchestrator.dispatchEnvelope` Deletes को Drop करता है (+ Web Purchase Bug)
- `lib/sync_core/orchestrator/master_sync_orchestrator.dart`:
  - **Line 66–75:** `MasterSyncOrchestrator.dispatchEnvelope` में `_fyScopedTransactionTypes` पर `doesEventBelongToActiveFY` check लगता है। केवल `CHALLAN` / `SALE_CHALLAN` / `PURCHASE_CHALLAN` (`status == 'Pending'`) को cross-FY allow किया जाता है। **FY `2025-26` का `SALE` DELETE या `PURCHASE` DELETE envelope यदि receiver `2026-27` पर है तो line 73 पर `return false;` होकर drop हो जाता है!** इसी तरह `Billed` challan के updates भी cross-FY में skip होते हैं।
  - **Line 631–649 (Web Purchase Delete Bug):** जब Web `2025-26` पर भी `PURCHASE` `DELETE` envelope पाता है, तो line `631` पहले ही `phWeb.purgeDeletedIds(delList)` चलाकर `phWeb.purchases` से item उड़ा देती है, और उसके **बाद** line `641` पर `phWeb.purchases.firstWhere(...)` करके `linkedChallanIds` / `sourceChallanId` निकालने की कोशिश करती है! यानी यदि envelope के `billData` में `linkedChallanIds` न हो (सिर्फ delete payload हो), तो `try/catch` हमेशा fail होता है और Purchase Challan `"Billed"` ही फँसा रहता है।

### Root Cause 6 — `FYTransferEngine.cascadeSingleYearStep` केवल Absent IDs जोड़ता है (`821-837`)
- `lib/fy_transfer_engine.dart:824-837`:
  ```dart
  // यदि targetScIds में sc.id नहीं है तभी जोड़ता है
  ```
- यदि किसी पिछले FY transfer में C1 किसी रूप में target FY (`2026-27`) में पहले से मौजूद था (जैसे पहले `Pending` transfer हुआ था, फिर `2025-26` में edit/delete/revert चक्र चला, या `version` अपडेट हुआ), तो `cascadeSingleYearStep` मौजूद ID वाले challan का latest status (`Pending`) और items refresh नहीं करता!

### Root Cause 7 — `AppRealtimeCoordinator` / `WebRealtimeCoordinator` Signal vs Cloud Vault Upload Race Condition
- जब App `2025-26` में `deleteBill` / `deletePurchase` चलाकर `AppRealtimeCoordinator` के ज़रिए `DELETE_SALE` / `DELETE_PURCHASE` signal भेजता है, तब **Signal #1 पहले fire होता है और Multi-FY full Drive vault upload बाद में होता है**।
- Web side (`web_realtime_coordinator.dart:73-79`) Signal #1 मिलते ही तुरंत `silentAutoCascadeMultiYear(eventFy)` और `refreshStoreData` चलाता है — उस पल cloud पर `2025-26` का पुराना vault पड़ा होता है जिसमें B1 अभी भी जीवित है और C1 अभी भी `"Billed"` है!
- और चूँकि `SaleChallanSyncModule` / `PurchaseChallanSyncModule` केवल `erp_master_sync` (`SyncQueueManager`) में जाते हैं और cross-FY cascade पर `_applyEdgeEventsToFyVault` challans को touch नहीं करता, Web का `2026-27` empty ही रह जाता है।

> **सारांश (Part 2):** App ↔ App, Web ↔ Web, App → Web और Web → App — इन सभी दिशाओं में जब `2025-26` का converted Bill delete होता है, तो `2026-27` में Pending Challan पहुँचने का chain उपरोक्त 7 बिंदुओं में से कहीं न कहीं टूट जाता है।

---

# PART 3 — REAL-TIME UPDATES & `RECENT STORE DISPATCHES` AUDIT (सभी 9 Architectural Layers)

| Layer | Component / File | वास्तविक स्थिति (Verified Audit Finding) | Impact |
|---|---|---|---|
| **1. UI Presentation (`RECENT STORE DISPATCHES`)** | `web_sale_challan_view.dart:1528-1679` (`_buildStoreRecentChallansCard`), `web_purchase_challan_view.dart:1669+` (`RECENT INWARD RECEIPTS`) | `webPh.saleChallans` को `b.date.compareTo(a.date)` से sort करता है। **Bug:** यदि कोई backdated challan हो या किसी पुराने Pending challan को edit किया जाए / delete करके वापस Pending बनाया जाए, तो वह `updatedAt` के हिसाब से top 5 में ऊपर नहीं आता। साथ ही dashboard state `Provider.of<PharoahWebManager>` पर depend करती है जो `_hotSwapActiveYearMastersFromVault` से update नहीं होता। | Recent list stale या wrong order दिखा सकती है। |
| **2. Local State & Manager Mutation** | `PharoahWebManager` (`addSaleChallanAndSync:2504`, `addPurchaseChallanAndSync:2573`, `deleteSaleChallan:2666`, `deletePurchaseChallan:2695`), `WebNewSaleView._saveInvoice:440-446` | (a) Web के चारों challan mutation methods `_snapshotActiveFyToVault()` को call ही नहीं करते (जबकि Sale/Purchase/Return methods करते हैं) — इसलिए FY switch या cloud push में Web challans का vault snapshot अधूरा रह सकता है।<br>(b) `WebNewSaleView._saveInvoice` single challan convert करते वक्त `version`, `updatedAt` और `SaleChallanSyncModule.onSaleChallanSaved` miss करता है। | Challan status cloud पर `"Pending"` अटका रहता है और Multi-FY vault में challan missing हो सकता है। |
| **3. Local Persistence & Disk Vault** | `PharoahManager._saveDataToDisk`, `MultiFyCloudVault` (`681-831`), `PharoahWebManager._fyVaultCache` | App पर `finalizeSaleChallan` / `finalizePurchaseChallan` disk पर write तो करते हैं, पर `deletePurchase` / `deleteBill` के बाद multi-FY local disk पर `2026-27` update नहीं होता। `PharoahManager.loadAllData` (`569`) और `_reloadMemoryFromDisk` (`3651`) Purchase Challans के लिए inconsistent `isPurchaseDeleted` args (`currentFY` / `updatedAt` omitted) भेजते हैं। | Reload या FY switch पर stale या erroneously hidden Purchase Challans की संभावना। |
| **4. FY Cascade Engine** | `lib/fy_transfer_engine.dart:360-364, 473-474, 821-837`, `PharoahManager.switchYear:305-326`, `PharoahWebManager._hotSwapActiveYearMastersFromVault:1556-1648` | `cascadeSingleYearStep` केवल missing IDs add करता है; App `switchYear` cascade नहीं करता; Web `_hotSwapActiveYearMastersFromVault()` `s_challan.json` व `p_challan.json` load ही नहीं करता। | Cross-FY Pending challan propagation broken। |
| **5. Outbox Queue (`SyncQueueManager`)** | `lib/sync_core/outbox/sync_queue_manager.dart`, `SaleChallanSyncModule`, `PurchaseChallanSyncModule`, `PharoahManager.finalizeSaleChallan`/`finalizePurchaseChallan` | App `finalizeSaleChallan` (`1111-1184`) व `finalizePurchaseChallan` (`1186-1265`) तथा `deleteBill`/`deletePurchase` में `.then((t) => SyncQueueManager.enqueue(...))` बिना `await` किए fire-and-forget होते हैं। यदि तुरंत `flushOutboxAsJSONBatch` या `notifyAppMutation` चल जाए, तो outbox row enqueue होने से पहले batch खाली या पुराना निकल सकता है। | Fast real-time sync में race condition। |
| **6. D1 Fast Delta (`D1SalesLedgerService` & `FastPullEngine`)** | `lib/sync_core/d1_sales_ledger_service.dart`, `lib/realtime_signaling/engines/fast_pull_engine.dart:139-149` | `FastPullEngine` और `D1SalesLedgerService` केवल Sales, Purchases, SaleReturns, PurchaseReturns के delta events apply करते हैं। **Challans के लिए `applyEventsToLocalSaleChallans` / `PurchaseChallans` या `linkedChallanIds` revert logic मौजूद ही नहीं है।** | Real-time fast pull challan creation, edit, या deleted bill → Pending revert को ignore कर देता है। |
| **7. Orchestrator Envelope Dispatch** | `lib/sync_core/orchestrator/master_sync_orchestrator.dart` | Line `66-75`: cross-FY `DELETE` envelopes (`SALE`, `PURCHASE`) व `"Billed"` challan envelopes drop हो जाते हैं। Line `631-649`: Web Purchase delete में `purgeDeletedIds` पहले चलने से `linkedChallanIds` lookup टूट जाता है। | Live outbox sync पर Web/App का Challan status `"Billed"` से `"Pending"` नहीं लौटता। |
| **8. Realtime Signaling Transport** | `lib/realtime_signaling/coordinators/app_realtime_coordinator.dart`, `web_realtime_coordinator.dart`, `cloud_signal_channel.dart`, `functions/api/lab_signal.ts` | Cloudflare Worker `lab_signal.ts` व `CloudSignalChannel` हर 2s पर fast pulse देते हैं। पर App mutation के बाद Signal #1 vault upload पूरा होने से पहले fire होने पर Web stale cloud vault pull करता है। | Transient या permanent stale state जब तक user manual refresh न करे। |
| **9. Periodic Heartbeat & Cloud Vault Sync** | `WebRealtimeCoordinator._safetyHeartbeatTimer` (`web_realtime_coordinator.dart:85`, हर 12s), `PharoahWebManager.refreshStoreData` (`3781-3874`) | `refreshStoreData` हर 12s में बिना यह जाँचे कि data बदला है या नहीं, unconditionally `rebuildInventory()` (`3859`) और `notifyListeners()` (`3873`) fire करता है। इससे UI widgets बार-बार अनावश्यक rebuild होते हैं (Part 4 bug को trigger करता है) जबकि cross-FY challan hot-swap फिर भी miss होता है। | UI tap disruption + CPU overhead, फिर भी stale cross-FY challans। |

---

# PART 4 — WEB CHALLAN PRODUCT SELECTION BUG (10–12 Taps पर Dialog न खुलने का Root Cause)

मैंने प्रभावित दोनों Web Challan files और तुलना के लिए normal Billing views का गहन कोड विश्लेषण किया है:
- **Sale Challan:** `lib/web_live_sync/sub_views/web_challans/web_sale_challan_billing_view.dart` (`lines 65-96, 161-365`) → `WebItemEntryCard` (`ITEM BILLING & BATCH CONFIG`)
- **Purchase Challan:** `lib/web_live_sync/sub_views/web_challans/web_purchase_challan_billing_view.dart` (`lines 104-210, 671-870`) → `_openPcItemDialog` (`INWARD STOCK CONFIGURATION`)
- **Comparison Views:** `sub_views/web_billing/web_new_sale_view.dart`, `sub_views/web_purchase/ui/web_purchase_billing_screen.dart`

### Source Code में Verified Concrete Defects

1. **12-Second Unconditional Background Rebuild (`Provider` `listen: true` + `refreshStoreData`):**
   - दोनों Challan Billing Views के `build()` की शुरुआत में `final webPh = Provider.of<PharoahWebManager>(context);` (`listen: true`) लगा है।
   - `WebRealtimeCoordinator` का `_safetyHeartbeatTimer` हर **12 सेकंड** में `refreshStoreData(isSilent: true)` चलाता है (`web_realtime_coordinator.dart:85`), और `CloudSignalChannel` हर 2s में poll करता है।
   - `PharoahWebManager.refreshStoreData` (`lines 3859, 3873`) चाहे cloud पर **शून्य बदलाव** हुआ हो, हर बार unconditionally `rebuildInventory()` और `notifyListeners()` call करता है!
   - पूरा `Scaffold` व product search `ListView.builder` बिना किसी item `Key` (`ValueKey(med.systemId)`) के rebuild होते हैं। यदि user के tap/click या slow pointer touch के बीच `notifyListeners()` चला, तो row rebuild होकर gesture break कर सकती है।

2. **Opaque `Container` के अंदर `Material` Wrapper न होना + Scrollable `ListView` Gesture Arena:**
   - `WebSaleChallanBillingView` (`lines 325-361`) और `WebPurchaseChallanBillingView` (`lines 833-866`) में `ListView.builder(shrinkWrap: true)` सीधे `Container(constraints: BoxConstraints(maxHeight: 180), decoration: BoxDecoration(color: Color(0xFF0F172A)))` के अंदर है — **बीच में कोई `Material(color: Colors.transparent)` नहीं है**।
   - नतीजा: `ListTile` का ripple/ink feedback opaque container के पीछे `Scaffold` पर चला जाता है (user को बिल्कुल पता नहीं चलता कि tap register हुआ या cancelled हुआ)।
   - साथ ही `ListView.builder` scrollable होने के कारण Flutter Gesture Arena में vertical drag detector attach होता है — ज़रा-सा finger movement (`> kTouchSlop`) या focus shift होने पर `onTapCancel` होकर tap silently fail हो जाता है।

3. **HTML `<input>` Focus Loss / Virtual Keyboard Collapse / Layout Shift (`Scaffold` + `Expanded`):**
   - दोनों Challan Billing Views full pushed `Scaffold` हैं (`resizeToAvoidBottomInset: true` default) जिनमें ऊपर `TextField(controller: productSearchC)` है और ठीक नीचे dropdown `ListView` + `Expanded(child: _buildCartTable(webPh))` है (`web_sale_challan_billing_view.dart:247-254`)। (इसके विपरीत `WebNewSaleView` `SingleChildScrollView` के अंदर है जहाँ नीचे `Expanded` viewport collapse नहीं करता।)
   - Mobile/Tablet Chrome Web पर जब user search result को tap करता है:
     - `PointerDown` पर browser `<input>` (`TextField`) से focus हटता है → virtual keyboard बंद होने या HTML input blur होने पर viewport/height (`viewInsets`) `PointerUp` से **पहले** shift हो सकती है → `ListTile` ऊपर/नीचे खिसक जाता है और hit-test miss होकर tap ignore हो जाता है!

4. **Synchronous `productSearchC.clear()` + Unbounded `Text` Row + Sync Rate Scan:**
   - दोनों views में `onTap` के अंदर:
     ```dart
     setState(() => productSearchC.clear());
     _openItemEntry(med); // या _openPcItemDialog(webPh, med);
     ```
     `setState(() => productSearchC.clear())` उसी tap handler में dropdown को synchronously unmount करने की schedule करता है; यदि focus/pointer event दो बार या blur-reentrant तरीके से fire हो या frame drop हो, तो state conflict/jank बनता है।
   - `WebSaleChallanBillingView:343` में `Row` के अंदर `Text(med.name)` बिना `Expanded`/`Flexible` के है — लंबे medicine names `RenderFlex overflow` दे सकते हैं जो hit/layout pass को गड़बड़ करते हैं।
   - `WebPurchaseChallanBillingView:846` **हर matching item build पर** `_findLatestPurchaseRate(webPh, med)` चलाता है (पूरे `purchases` व `batches` पर linear scan — maximum 5 items × हर keystroke/rebuild, और `onTap` पर dialog खुलने से पहले दोबारा `109` पर यही scan चलता है)।

### Honest Engineering Disclosure (Static Audit vs Live Browser Runtime)
> **ध्यान दें:** यह जाँच source code के static analysis पर आधारित है; इस shell environment में live compiled Flutter Web app को mobile/desktop Chrome DevTools pointer trace के साथ run नहीं किया गया है। इसलिए **10–12 taps के बाद ही dialog खुलने की exact frequency** runtime में browser focus-blur timing और `12s` heartbeat / `viewInsets` collapse के आपसी टकराव से उत्पन्न होने वाला *strongly corroborated runtime behavior* है, जिसे ऊपर दिए गए सभी verified widget-tree defects ठीक करके समाप्त किया जा सकता है।

---

# PART 5 — SALE CHALLAN vs PURCHASE CHALLAN (Comparative Matrix)

| आयाम (Dimension) | Sale Challan (`SaleChallan`) | Purchase Challan (`PurchaseChallan`) | मुख्य अंतर / Risk |
|---|---|---|---|
| **Storage File** | `s_challan.json` | `p_challan.json` | दोनों per-FY folders व `_fyVaultCache` में store होते हैं। |
| **Numbering & Keys** | `id`, `billNo` (`CH-1` / `SCH-WEB-<ts>`), case-insensitive uppercase match | `id`, `internalNo` (`PCH-1` / `PCH-WEB-1`), `billNo` (Supplier Ref, **case-sensitive** in composite keys!) | Purchase Challan में 2 separate numbers (`internalNo` + supplier `billNo`) होने से mismatch का risk ज्यादा है। |
| **App Edit `Billed` Guard** | `SaleChallanRegister:315` पर `"Billed"` edit blocked है | **`PurchaseChallanRegister:259` पर `"Billed"` guard MISSING है!** (+ status badge missing) | App पर user Billed Purchase Challan को edit कर सकता है, जिससे mismatch हो सकता है। |
| **Delete Tombstone Registry** | अलग Sale Challan delete list/outbox (`SaleChallanSyncModule`) | **Shared with Purchase Bills!** `D1SalesLedgerService.markPurchasePermanentlyDeleted(...)` + `deletedPurchaseTombstones` | Purchase Challan delete करने का key यदि किसी Purchase से collide करे या `isPurchaseDeleted` बिना `updatedAt`/`FY` चले (`pharoah_manager.dart:569, 3651`), तो re-created Purchase Challan गायब हो सकता है! |
| **Converted Bill Single Save** | Web `WebNewSaleView._saveInvoice:440-446` **broken** (`version`, `updatedAt`, `SaleChallanSyncModule` missing!) | Web `WebPurchaseBillingScreen` व Stitcher sync call करते हैं | Single Sale Challan → Sale Bill conversion Web से cloud D1 पर `"Pending"` ही अटका रहता है। |
| **Web Delete MasterSync** | `MasterSyncOrchestrator:600+` `phWeb.sales` से `linkedChallanIds` पढ़ सकता है | **`MasterSyncOrchestrator:631-649` पहले `purgeDeletedIds` कर देता है, फिर `phWeb.purchases` में खोजता है!** | Remote Purchase Delete envelope Web पर Purchase Challan revert fail कर सकता है। |
| **Deleted Converted Bill → Next FY** | `2025-26` से `2026-27` में Pending recovery **Broken** | `2025-26` से `2026-27` में Pending recovery **Broken** | दोनों में Part 2 के Root Causes 1–7 लागू होते हैं। |
| **Web Product Tap Bug** | `WebSaleChallanBillingView:325-361` → `WebItemEntryCard` | `WebPurchaseChallanBillingView:833-866` → `_openPcItemDialog` | दोनों में Part 4 की समान architecture + UI tap समस्या है। |

---

# PART 6 — GIT HISTORY & DUPLICATE / DEAD CODE PATHS

### हाल के Relevant Commits (`git log`)
- `69919cf` / `bbc3b2d` / `0a02674` (`#PH-REV-812`): `Purchase` delete के बाद same Party/Ref re-creation पर cross-FY tombstone collision fix (`updatedAt`-aware comparison व `fy` isolation `D1SalesLedgerService` में) — **परंतु** `PharoahManager.loadAllData:569` व `_reloadMemoryFromDisk:3651` में Purchase Challans पर पुराना non-`updatedAt` `isPurchaseDeleted` call अभी भी बाकी रह गया!
- `476dffb` (`#PH-REV-811`): Post-build verification & Web purchase sync hardening।
- `6dcc627` / `eb223de` (`#PH-REV-809`, `#PH-REV-808`): Bill deletion पर Challan revert (`linkedChallanIds` + `sourceChallanId` + App `sale_entry_view` / `purchase_entry_view` modify preservation), पर केवल active FY तक सीमित रहा; cross-FY cascade व `_hotSwapActiveYearMastersFromVault` छूट गए।
- `#PH-REV-721` – `#PH-REV-729`: Web Challan Portal, Stitcher Wizard (`WebChallanStitcherWizard`), `D1SalesLedgerService` व `MultiFyCloudVault` की नींव रखी गई थी — उसी दौरान `_hotSwapActiveYearMastersFromVault` में केवल master + `carriedPendingInvoices` जोड़े गए और challans (`s_challan.json`, `p_challan.json`) छूट गए।

### Duplicate / Divergent Code Paths (एक ही काम के अलग रास्ते)
1. **Single Conversion vs Stitcher Conversion (Web):** `WebChallanStitcherWizard` पूरी sync fields (`version++`, `updatedAt`, `SaleChallanSyncModule.onSaleChallanSaved`) चलाता है, जबकि `WebNewSaleView._saveInvoice:440-446` एक अधूरा inline loop चलाता है।
2. **Legacy `challan_sync_module.dart` vs `sale_challan_sync_module.dart` / `purchase_challan_sync_module.dart`:** `lib/sync_core/modules/` में दो तरह के sync modules मौजूद हैं; सभी callers को dedicated typed modules (`SaleChallanSyncModule` & `PurchaseChallanSyncModule`) के ज़रिए consistent रहना चाहिए।
3. **App `loadAllData` vs `_reloadMemoryFromDisk`:** `PurchaseChallan` tombstone filtering दोनों जगह अलग signatures से call होती है (`pharoah_manager.dart:569` vs `3651`)।

---

# PART 7 — SAFE MINIMAL FIX PLAN (Approval के बाद लागू करने हेतु)

**सिद्धांत:** मौजूदा working Sale और Purchase workflows को बिल्कुल नहीं छेड़ना; केवल न्यूनतम, surgical और reversible बदलाव करना।

### Priority P0 — Cross-FY Pending Challan Recovery (Part 2 + Part 3 Critical)
1. **`lib/web_live_sync/pharoah_web_manager.dart`:**
   - `_hotSwapActiveYearMastersFromVault()` (`1556-1648`) में सक्रिय FY के vault से `s_challan.json` और `p_challan.json` को भी merge/reload करें (Pending challans जो back FY से cascade हुए हैं, वे तुरंत `saleChallans` और `purchaseChallans` में दिखें)।
   - `deleteSale` (`2120+`) और `deletePurchase` (`2325+`) के अंत में `_cascadeWebFyVaultFrom(financialYear)` trigger करें ताकि same-session FY switch या cloud push पर अगला FY तुरंत sync हो।
   - `addSaleChallanAndSync`, `addPurchaseChallanAndSync`, `deleteSaleChallan`, `deletePurchaseChallan` (`2504-2744`) में `_snapshotActiveFyToVault()` जोड़ें ताकि `RECENT STORE DISPATCHES` और vault हमेशा consistent रहें।
   - `_applyEdgeEventsToFyVault` (`1726-1880`) में back-FY `SALE`/`PURCHASE` `DELETE` delta मिलने पर उस vault की `s_challan.json`/`p_challan.json` में linked challans को `"Pending"` revert कर तुरंत `_cascadeWebFyVaultFrom(eventFy)` चलाएँ, और `SALE_CHALLAN`/`PURCHASE_CHALLAN` deltas भी handle करें।
2. **`lib/pharoah_manager.dart` & `lib/fy_transfer_engine.dart` & `lib/sync_core/multi_fy_cloud_vault.dart`:**
   - `deleteBill` (`2756+`) व `deletePurchase` (`2833+`) के बाद `silentAutoCascadeFromBackYear(currentFY)` trigger करें (और `D1SalesLedgerService.onSaleDeleted` line `2802` में `fy: currentFY` pass करें)।
   - `switchYear(year)` (`305-326`) में `loadAllData()` से पहले/साथ `syncOpeningBalancesFromPreviousYear(...)` या safe previous-FY Pending challan merge चलाएँ।
   - `finalizeSaleChallan` / `finalizePurchaseChallan` / `deleteBill` / `deletePurchase` में outbox enqueue (`SyncQueueManager.enqueue`) को `notifyAppMutation` / `flushOutboxAsJSONBatch` से पहले `await` करें।
   - `FYTransferEngine.cascadeSingleYearStep` (`824-837`) में यदि `sc.id`/`pc.id` target FY में पहले से हो और `prevFY` का `version`/`updatedAt` नया हो (या `Pending` revert हुआ हो), तो target FY का challan भी update करें।
   - `MultiFyCloudVault.applyCrossFyEdgeEventsToLocalDisk` (`681-831`) में back-FY `SALE`/`PURCHASE` `DELETE` पर disk `s_challan.json`/`p_challan.json` revert + cascade जोड़ें।
   - `loadAllData:569` और `_reloadMemoryFromDisk:3651` में `PurchaseChallan` deletion check को consistent `fy` व `updatedAt` के साथ align करें।
3. **`lib/sync_core/orchestrator/master_sync_orchestrator.dart`:**
   - `dispatchEnvelope` में `SALE`/`PURCHASE` `DELETE` को cross-FY होने पर silently `return false` करने के बजाय back-FY vault/disk में bill delete + challan revert + cascade के लिए route करें (ya `D1SalesLedgerService` में `applyEventsToLocalSaleChallans` / `PurchaseChallans` जोड़कर `FastPullEngine` से link करें)।
   - Web Purchase delete (`lines 631-649`) में `phWeb.purchases` से `linkedChallanIds` **पहले** extract करें, उसके बाद `purgeDeletedIds(delList)` चलाएँ।
4. **`lib/web_live_sync/sub_views/web_billing/web_new_sale_view.dart` (`lines 440-446`):**
   - Single challan conversion पर `version += 1`, `updatedAt = now`, और `SaleChallanSyncModule.onSaleChallanSaved(ch, fy: webPh.financialYear)` add करें।
5. **`lib/realtime_signaling/coordinators/app_realtime_coordinator.dart` & `web_realtime_coordinator.dart`:**
   - Delete + challan revert जैसी multi-FY mutations के बाद full cloud vault sync complete होने पर confirmation/secondary pull हो ताकि receiver stale `2025-26` vault से गलत cascade न करे।

### Priority P1 — Real-Time `RECENT STORE DISPATCHES` & UI Stability
6. **`web_sale_challan_view.dart` (`1528+`) & `web_purchase_challan_view.dart` (`1669+`):**
   - `RECENT STORE DISPATCHES` sort में `date` के साथ `updatedAt` tie-breaker / recent mutation priority दें (business rule अनुसार date primary या updatedAt recent clear रखें), और `PharoahWebManager.refreshStoreData` में `notifyListeners()` / `rebuildInventory()` तभी call करें जब वाकई कोई state delta आया हो (no-op 12s heartbeat rebuilds बंद करें)।
7. **`lib/challans/purchase_challan_register.dart:259`:**
   - `"Billed"` Purchase Challan पर Edit block + Status badge add करें (Sale Challan और Web Challan के समान)।

### Priority P1 — Web Challan Product Selection Tap Bug (Part 4)
8. **`web_sale_challan_billing_view.dart` & `web_purchase_challan_billing_view.dart`:**
   - Search result `ListView.builder` को explicit `Material(color: Color(0xFF0F172A), borderRadius: ...)` के अंदर रखें ताकि ink/hit-testing container की surface पर काम करे।
   - प्रत्येक search result item पर stable `Key: ValueKey('med_${med.systemId}')` दें और `Provider.of<PharoahWebManager>(context, listen: false)` (या `Selector` सिर्फ `medicines.length` पर) इस्तेमाल करें ताकि हर 12s के background heartbeat पर input/dropdown rebuild न हो।
   - `Scaffold(resizeToAvoidBottomInset: false)` रखें और `onTap` में `WidgetsBinding.instance.addPostFrameCallback` या `FocusScope.of(context).unfocus()` के साथ **पहले dialog open / capture `med` करें और फिर सुरक्षित रूप से search clear करें** (tap race से बचने के लिए `InkWell` / `GestureDetector(behavior: HitTestBehavior.opaque)` का उपयोग करें)।
   - `WebSaleChallanBillingView:343` में `Expanded(child: Text(med.name, overflow: TextOverflow.ellipsis))` लगाएँ और `WebPurchaseChallanBillingView:846` का heavy `_findLatestPurchaseRate` प्रति-row build loop में बार-बार चलाने के बजाय cached/tap-time पर compute करें।

---

# PART 8 — TEST MATRIX & FINAL OBJECTIVE ANSWERS

## Verification Matrix (Fix लागू करने के बाद चलाए जाने वाले Tests)
| Test Case | Flow | Expected Verified Result |
|---|---|---|
| **T1** | FY `2025-26`: Create Sale Challan → Convert to Bill → Start FY `2026-27` → Delete Bill in `2025-26` (App) → Switch App to `2026-27` | Reverted `Pending` Sale Challan `2026-27` में तुरंत दिखना चाहिए; Web `2026-27` में भी real-time sync होकर दिखना चाहिए। |
| **T2** | Same as T1 for **Purchase Challan → Purchase Bill** (App Delete → App & Web `2026-27` + Web Delete → App & Web `2026-27`) | Reverted `Pending` Purchase Challan दोनों FY और दोनों platforms पर दिखना चाहिए; `D1` delete registry इसे गलत block न करे। |
| **T3** | Web open on `2026-27` while App deletes Bill in `2025-26` (zero manual reload) | Web की `SaleChallan` / `PurchaseChallan` list में auto-cascade होकर `Pending` challan दिखना चाहिए। |
| **T4** | Web single Sale Challan → Sale Bill (`WebNewSaleView`) | Cloud D1 और App पर Challan `"Billed"` होना चाहिए (`version++`, `updatedAt`, outbox sync सहित)। |
| **T5** | App/Web create, edit, delete Challan → Check Web `RECENT STORE DISPATCHES` & `RECENT INWARD RECEIPTS` | 2–5 सेकंड में real-time update बिना manual F5 के। |
| **T6** | Web Sale Challan & Purchase Challan Product Search tap test (Desktop + Mobile Chrome touch + focus active) | **1st tap** पर ही 100% `WebItemEntryCard` (`ITEM BILLING & BATCH CONFIG`) और `_openPcItemDialog` (`INWARD STOCK CONFIGURATION`) खुलना चाहिए। |
| **T7** | Regression Check: Normal Sale Create/Modify/Delete + Normal Purchase Create/Modify/Delete + Party Re-creation (`#PH-REV-812`) | 100% existing working behavior सुरक्षित रहना चाहिए। |

---

## Final Objective — 6 प्रश्नों के सटीक उत्तर

1. **FY `2025-26` का Converted Bill delete करने के बाद वापस `Pending` हुआ Challan FY `2026-27` में क्यों नहीं आता?**
   - Initial FY transfer में `"Billed"` challan `2026-27` में नहीं जाता (`FYTransferEngine:360-364, 473-474`)। बाद में Bill delete करने पर: (a) App `deleteBill`/`deletePurchase` व Web `deleteSale`/`deletePurchase` FY cascade नहीं चलाते, (b) App `switchYear()` carry-forward नहीं चलाता, (c) Web `_hotSwapActiveYearMastersFromVault()` `s_challan.json`/`p_challan.json` reload ही नहीं करता, (d) `D1SalesLedgerService` और cross-FY edge delta pipelines में Challans/revert का कोई handler नहीं है (`deleteBill:2802` में `fy` भी missing है), (e) `MasterSyncOrchestrator` cross-FY `DELETE` को drop करता है और Web Purchase delete `purgeDeletedIds` पहले कर देता है, (f) `cascadeSingleYearStep` existing IDs को update नहीं करता, और (g) Signal #1 cloud vault upload से पहले race कर जाता है।

2. **यह समस्या Sale Challan और Purchase Challan दोनों में है या अलग-अलग?**
   - **दोनों में है** — दोनों ही FY cascade omission, `_hotSwapActiveYearMastersFromVault` omission, और missing D1 edge Challan handlers से टूटे हुए हैं। इसके अतिरिक्त **Purchase Challan में 3 extra जोखिम हैं**: `D1SalesLedgerService` delete tombstone registry Purchase Bills के साथ shared है, `pharoah_manager.dart:569, 3651` पर `isPurchaseDeleted` में `updatedAt`/`FY` अधूरा है, App `PurchaseChallanRegister:259` पर `Billed` guard missing है, और Web `MasterSyncOrchestrator:631` पर `purgeDeletedIds` `linkedChallanIds` पढ़ने से पहले list साफ कर देता है।

3. **Real-time `RECENT STORE DISPATCHES` और Challan status update किस layer में fail हो रहा है?**
   - **Multiple layers में:** (a) Web `WebNewSaleView._saveInvoice:440-446` single conversion पर `SaleChallanSyncModule` / `version` / `updatedAt` नहीं भेजता, (b) Web challan CRUD methods `_snapshotActiveFyToVault()` नहीं चलाते, (c) `FastPullEngine` / `D1SalesLedgerService` में Challan fast delta support नहीं है, (d) `PharoahManager.finalize*` में outbox enqueue `await` नहीं होता, (e) `_safetyHeartbeatTimer` (12s) व `_hotSwapActiveYearMastersFromVault()` challans reload नहीं करते, और (f) `_buildStoreRecentChallansCard` `date` से sort करता है (`updatedAt` से नहीं)।

4. **Web Sale Challan और Purchase Challan में Product search result पर 10–12 बार click करने के बाद ही Item dialog क्यों खुलता है?**
   - दोनों `WebSaleChallanBillingView` (`325-361`) और `WebPurchaseChallanBillingView` (`833-866`) में `Container(color: 0xFF0F172A)` के अंदर बिना `Material` wrapper और बिना item `Key` के `ListView.builder(shrinkWrap: true)` है, जबकि पूरा pushed `Scaffold` `Provider.of<PharoahWebManager>(context)` (`listen: true`) के कारण हर 12s के unconditional `refreshStoreData` (`rebuildInventory()` + `notifyListeners()`) पर rebuild होता है। साथ ही tap पर HTML `<input>` blur / `viewInsets` layout shift और synchronous `setState(() => productSearchC.clear())` मिलकर `PointerDown`–`PointerUp` के बीच hit-test/gesture arena cancel कर देते हैं।

5. **क्या Existing Sale/Purchase सही logic को छेड़े बिना safe fix संभव है?**
   - **हाँ, 100% संभव है।** Part 7 में दिया गया fix plan केवल Challan vault hot-swap, Challan-specific cascade triggers, Web Purchase delete lookup order fix (`purgeDeletedIds` को line 649 के बाद move करना), `WebNewSaleView` challan sync metadata जोड़ने, और Web Challan product search widget/Provider isolation पर केंद्रित है — यह working Sale/Purchase billing, ledger और `#PH-REV-812` tombstone behavior को सुरक्षित रखता है।

6. **सही और स्थायी Fix Plan क्या है?**
   - Part 7 के **8 P0/P1 surgical steps** (Cross-FY vault hot-swap + delete-triggered cascade + `D1SalesLedgerService`/outbox cross-FY Challan & revert routing + `MasterSyncOrchestrator` ordering fix + `WebNewSaleView` sync fix + Web Challan `Material`/`Key`/focus-safe `onTap` + unconditional 12s `notifyListeners` suppression)।

---
**अगला कदम:** कृपया इस audit report की समीक्षा करें। आपकी अनुमति मिलने पर मैं Part 7 के सुरक्षित fixes step-by-step लागू कर दूँगा और उसके बाद `Part 8` के अनुसार verification रिपोर्ट दूंगा।
