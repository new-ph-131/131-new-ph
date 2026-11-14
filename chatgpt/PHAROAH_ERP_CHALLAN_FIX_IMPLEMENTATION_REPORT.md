# PHAROAH ERP — CHALLAN DEEP AUDIT FIX IMPLEMENTATION REPORT
## FY Transfer + Converted Bill Deletion + Pending Challan Recovery + Real-Time Dispatch Updates + Web Product Selection (`#PH-REV-813`)

- **Repository:** `new-ph-131/131-new-ph` (`main` branch)
- **Live Series Tag:** `#PH-REV-813 (FIX-CHALLAN-FY-RECOVERY-REALTIME-AND-PRODUCT-TAP)`
- **Verified Production Commit:** `fe59f65` (`fix(challan-ui): keep Row parent for Expanded _rateSegment items (#PH-REV-813)`)
- **GitHub Actions CI Status:**
  - **Workflow 1 (`Build Flutter Web Portal and Android APK` — Run `43619924589`):** `status=completed | conclusion=success`
    - `Run Flutter tests`: **48/48 Passed, 0 Failed** (including 9 new end-to-end tests in `test/challan_fy_recovery_p0_test.dart` covering T1–T7 + LWW/Tombstone/OpBal isolation)
    - `Build Android release APK`: **Success** (`build/app/outputs/flutter-apk/app-release.apk`, `110.7MB`)
    - `Build web portal`: **Success**
    - `Deploy production web to Cloudflare Pages`: **Success** (`https://b23c88ef.pharoah-erp.pages.dev` → live on `https://pharoah-erp.pages.dev`)
  - **Workflow 2 (`Build Android APK` — Run `43619924543`):** `status=completed | conclusion=success`

---

## 1. `PHAROAH_ERP_CHALLAN_DEEP_AUDIT_REPORT.md` की हर समस्या की वर्तमान स्थिति (Issue-by-Issue Status Summary)

| # | Audit Issue / Bug ID | विवरण (Description) | Phase | वर्तमान स्थिति (Current Status) |
|---|---|---|---|---|
| **1** | **P0-1 / Bug #1 (App `switchYear` Missing Challan Carry-Forward)** | `2025-26` में Converted Sale/Purchase Bill delete करने पर Challan `Pending` हो जाता था, लेकिन `switchYear("2026-27")` में Challan reconciliation न होने से `2026-27` में वह Challan कभी दिखाई नहीं देता था। | Phase 1 (P0) | **FIXED & VERIFIED (T1, T2-App)** |
| **2** | **P0-2 / Bug #2 (`FyTransferEngine` Stale `"Billed"` Overwrite & No Reconcile)** | `FyTransferEngine.cascadeSingleYearStep` केवल नए Challan append करता था या पहले से मौजूद `"Billed"` target Challan को skip कर देता था; source FY में `"Billed"` → `"Pending"` हुए Challan को LWW/Tombstone-safe तरीके से reconcile नहीं करता था। | Phase 1 (P0) | **FIXED & VERIFIED (T1, T2, T3, LWW Test)** |
| **3** | **P0-3 / Bug #3 (Web `_hotSwapActiveYearMastersFromVault` Missing Challans)** | Web पर `_cascadeWebFyVaultFrom()` Vault में Challan डाल देता था, लेकिन `_hotSwapActiveYearMastersFromVault()` केवल Parties, Batches और Invoices को memory में swap करता था — `saleChallans` और `purchaseChallans` को छोड़ देता था। | Phase 1 (P0) | **FIXED & VERIFIED (T2-Web)** |
| **4** | **P0-4 / Bug #4 (Cross-FY Remote Bill Delete Loses Linked Challan Recovery)** | जब Device A पर `2025-26` का Converted Bill delete होता था और Device B `2026-27` में होता था, तो `MultiFyCloudVault`, `D1SalesLedgerService`, `FastPullEngine`, `AppSyncEngine` और `MasterSyncOrchestrator` केवल Bill delete करते थे — `linkedChallanIds` / `sourceChallanId` से Challan को `"Pending"` revert और active FY में cascade नहीं करते थे। | Phase 1 (P0) | **FIXED & VERIFIED (T2-Web, T3, Same-FY Purchase Delete)** |
| **5** | **P0-5 / Bug #5 (Same-FY Web Purchase Delete Order-of-Operations Bug)** | `MasterSyncOrchestrator._applySingleEnvelope` में `PURCHASE` `DELETE` आने पर पहले `phWeb.purchases.removeWhere(...)` चल जाता था और उसके बाद `phWeb.purchases` में deleted purchase ढूँढकर `sourceChallanId` निकालने की कोशिश होती थी — जिससे Web पर Purchase Bill delete होने पर `PurchaseChallan` कभी `"Pending"` नहीं होता था। | Phase 1 (P0) | **FIXED & VERIFIED (Same-FY Purchase Delete Test)** |
| **6** | **P0-6 / Bug #6 (App `loadAllData` / `_reloadMemoryFromDisk` Missing Challan Tombstone Check & Tombstone Unmark on Recovery)** | App के `loadAllData()` और `_reloadMemoryFromDisk()` में `s_challans.json` / `p_challans.json` बिना `TombstoneEngine` फ़िल्टर के load हो जाते थे; और Converted Bill delete से Challan `"Pending"` होने पर उसका पुराना tombstone unmark नहीं होता था। | Phase 1 (P0) | **FIXED & VERIFIED (LWW & Tombstone Isolation Test)** |
| **7** | **P0-7 / Bug #7 (`D1SalesLedgerService` Document-Type Guard)** | `D1SalesLedgerService.applyEventsToLocalSales` / `applyEventsToLocalPurchases` में `"SALE_CHALLAN"`, `"PURCHASE_CHALLAN"`, `"CHALLAN"` को explicitly skip करने का guard नहीं था। | Phase 1 (P0) | **FIXED & VERIFIED (LWW & Tombstone Isolation Test)** |
| **8** | **P1-1 / Bug #8 (App Challan/Bill Mutation Signaling Before Outbox Enqueue & Missing `fy`)** | App में `finalizeSaleChallan`, `finalizePurchaseChallan`, `deleteSaleChallan`, `deletePurchaseChallan`, `finalizeSale`, `finalizePurchase` में `notifyAppMutation` तब कॉल हो जाता था जब `Future.microtask` ने Outbox में event लिखा ही नहीं होता था, और `fy: currentFY` भी पास नहीं होता था। | Phase 2 (P1) | **FIXED & VERIFIED** |
| **9** | **P1-2 / Bug #9 (Web Challan Create/Delete Missing `_snapshotActiveFyToVault()` & `fy: financialYear`)** | Web में `addSaleChallanAndSync`, `addPurchaseChallanAndSync`, `deleteSaleChallan`, `deletePurchaseChallan` में `_snapshotActiveFyToVault()` नहीं चलता था (जिससे अगले silent sync में Vault नए Challan को मिटा देता था) और `notifyWebMutation` में `fy: financialYear` नहीं जाता था। | Phase 2 (P1) | **FIXED & VERIFIED (T4)** |
| **10** | **P1-3 / Bug #10 (Single-Challan & Bulk Conversion Overwriting Unrelated Challans / Missing `sourceChallanId` Fallback)** | `addSaleAndSync`, `addPurchaseAndSync`, `web_new_sale_view.dart`, और `web_purchase_mechanism.dart` में पहले से `"Billed"` Challan की भी `updatedAt`/`version` दोबारा bump हो जाती थी, और single conversion में item-level `sourceChallanId`/`sourceChallanNo` का fallback अधूरा था। | Phase 2 (P1) | **FIXED & VERIFIED (T4)** |
| **11** | **P1-4 / Bug #11 (`RECENT STORE DISPATCHES` & `RECENT INWARD RECEIPTS` Sorted Only by Creation `date`)** | Web के `WebSaleChallanView` और `WebPurchaseChallanView` में Recent सूचियाँ केवल `b.date.compareTo(a.date)` से sort हो रही थीं — इसलिए पुराने या पिछले FY से recover/update हुए Challan ऊपर नहीं दिखते थे। | Phase 2 (P1) | **FIXED & VERIFIED (T5)** |
| **12** | **P1-5 / Bug #12 (App `PurchaseChallanRegister` Allowed Editing `"Billed"` Challans & Hid Status Badge)** | App के `PurchaseChallanRegister` में `"Billed"` Purchase Challan पर न कोई status badge था और न ही `Modify / Edit Items` पर lock था (जबकि Sale Challan में था)। | Phase 2 (P1) | **FIXED & VERIFIED** |
| **13** | **P1-6 / Bug #13 (Web Product Selection & Batch Dialog First-Click Failure on Desktop & Mobile)** | `WebSaleChallanBillingView` और `WebPurchaseChallanBillingView` पूरे `PharoahWebManager` को `Provider.of<PharoahWebManager>(context)` से listen कर रहे थे (हर 12s के silent background sync पर पूरा view और search list tap के बीच में ही rebuild हो जाता था), `ListView.builder` के `InkWell` के पास अपना `Material` ancestor नहीं था, और `_openItemEntry` से पहले `productSearchC.clear()` चलाया जा रहा था। | Phase 3 (P1) | **FIXED & VERIFIED (T6 & T7 — Desktop 1440×900 & Mobile 390×844)** |

---

## 2. वास्तविक Root Causes (Verified Against Source Code)

1. **FY Boundary पर Challan Carry-Forward और Opening Balance की Coupling:**
   - पहले Challan carry-forward केवल तब चलता था जब यूज़र `syncOpeningBalancesFromPreviousYear()` (Manual Sync Button) दबाता था।
   - `switchYear()` में जानबूझकर `syncOpeningBalancesFromPreviousYear()` नहीं चलाया जाता था ताकि बिना पूछे Party Opening Balance (`opBal`) या Closing Stock न बदल जाए।
   - परिणामस्वरूप, `2025-26` में Converted Bill delete होने से जो Challan `Pending` हुआ, वह `switchYear("2026-27")` करने पर `2025-26` की फाइल में ही पड़ा रह गया।
   - **समाधान:** हमने `FyTransferEngine.cascadePendingChallansOnlyStep` और `PharoahManager.syncPendingChallansFromPreviousYears()` बनाए जो **केवल `s_challans.json` और `p_challans.json`** को LWW और Tombstone नियमों के साथ reconcile करते हैं और `parts.json` (`opBal`), `meds.json` (Inventory), `bills.json`, या `pur_bills.json` को बिल्कुल नहीं छूते।

2. **Cross-FY और Same-FY Bill Deletion में Linked Challan Metadata का खो जाना:**
   - जब कोई Bill remote sync (`D1SalesLedgerService`, `FastPullEngine`, `AppSyncEngine`, `MultiFyCloudVault`, या `MasterSyncOrchestrator`) के ज़रिए delete होता था, तो sync इंजन Bill को सीधे list से हटा देते थे।
   - एक बार Bill memory या JSON से हट गया, तो उसके अंदर मौजूद `linkedChallanIds` और `items[].sourceChallanId` / `sourceChallanNo` हमेशा के लिए खो जाते थे।
   - विशेष रूप से `MasterSyncOrchestrator.dart` में `PURCHASE` `DELETE` के समय पहले `purgeDeletedIds` (जो `phWeb.purchases` से बिल हटा देता था) चलता था और उसके बाद `phWeb.purchases` में उस deleted ID को खोजा जा रहा था — जो हमेशा खाली मिलता था!
   - **समाधान:** अब **हर delete path में Bill को list से हटाने से पहले** (और remote event payload के `linkedChallanIds` / `items` दोनों से) linked Challan IDs/Numbers निकाले जाते हैं, केवल उन्हीं Challans को `"Pending"` किया जाता है जिनका `updatedAt <= deleteEventTs` हो (ताकि अगर Challan बाद में किसी नए बिल में लग चुका हो तो वह गलत तरीके से `"Pending"` न हो), और उनका tombstone तुरंत unmark करके Outbox व Active FY में sync किया जाता है।

3. **Web Challan Product Search में Tap Drop होने के 3 संयुक्त कारण:**
   - **पहला कारण (Background Rebuild Race):** `WebSaleChallanBillingView` और `WebPurchaseChallanBillingView` के `build()` में `final webPh = Provider.of<PharoahWebManager>(context);` लिखा था, और `PharoahWebManager.refreshStoreData(isSilent: true)` हर 12 सेकंड के background poll पर चाहे डेटा बदला हो या नहीं, पूरी cloud JSON दोबारा parse करके `rebuildInventory()` और `notifyListeners()` चला रहा था। इससे यूज़र के `pointerDown` और `pointerUp` के बीच में पूरा search results widget tree नष्ट होकर नया बन जाता था और gesture cancel हो जाता था।
   - **दूसरा कारण (Missing `Material` & Keyboard Viewport Shift):** `ListView.builder` सीधे `Container` के अंदर था (बिना `Material` ancestor के), और `Scaffold` पर `resizeToAvoidBottomInset: false` न होने से मोबाइल पर कीबोर्ड खुलते/बंद होते समय पोजीशन खिसक जाती थी।
   - **तीसरा कारण (State Mutation Order):** `onTap` के अंदर dialog खोलने से पहले `productSearchC.clear()` किया जा रहा था।
   - **समाधान:**
     1. `PharoahWebManager.refreshStoreData(isSilent: true)` में जब `syncedAtStr == _lastRemoteSyncedAt` हो, तब केवल lightweight `_harvestD1EdgeDeltas()` चलता है — अनावश्यक full JSON parse और `notifyListeners()` बंद कर दिया गया।
     2. दोनों Challan Billing Views में `Provider.of<PharoahWebManager>(context, listen: false)` + `context.select<PharoahWebManager, int>((m) => m.medicines.length)` लगाया गया ताकि background sync से कभी भी पूरा billing screen rebuild न हो।
     3. Search dropdown `ListView.builder` को `Material(color: Colors.transparent)` और हर item को स्थिर `ValueKey` दिया गया, और `onTap` में पहले `FocusScope.of(context).unfocus()` + `_openItemEntry(med)` / `_openPcItemDialog(webPh, med)` कॉल किया गया और उसके बाद `productSearchC.clear()` किया गया।

---

## 3. किन-किन Files में बदलाव किया गया और क्यों (Modified Files & Technical Rationale)

`git diff --stat 5124b92..fe59f65` के अनुसार कुल **19 files** (`2,634 insertions, 387 deletions`) में सटीक और सुरक्षित बदलाव किए गए हैं:

1. **`lib/fy_transfer_engine.dart`**
   - `reconcileCarryForwardSaleChallans` और `reconcileCarryForwardPurchaseChallans` जोड़े गए:
     - यदि source FY में Challan `"Pending"` है:
       - और target FY में पहले से मौजूद है: यदि target FY में वह delete हो चुका है (`isTargetDeleted`) तो resurrect नहीं करेगा; यदि target FY में `"Billed"` है तो केवल तभी `"Pending"` करेगा जब `source.updatedAt > target.updatedAt` (अर्थात् पुराना बिल बाद में delete हुआ हो, न कि नए साल में नया बिल बना हो)।
       - और target FY में नहीं है: यदि target FY में tombstoned नहीं है तो `"Pending"` के रूप में carry-forward करेगा।
     - यदि source FY में Challan `"Billed"` हो गया है और `source.updatedAt >= target.updatedAt`, तो target FY से stale `"Pending"` कॉपी हटा देगा।
   - `cascadePendingChallansOnlyStep(...)` जोड़ा गया जो **केवल** `s_challans.json` और `p_challans.json` को cascade करता है (Opening Balance या Inventory को छुए बिना)।

2. **`lib/sync_core/d1_sales_ledger_service.dart`**
   - `applyEventsToLocalSales` और `applyEventsToLocalPurchases` में `"SALE_CHALLAN"`, `"PURCHASE_CHALLAN"`, `"CHALLAN"` को तुरंत skip करने का explicit guard लगाया गया।
   - `revertLinkedChallansFromDeleteEvents(...)` जोड़ा गया जो remote `SALE` / `PURCHASE` `DELETE` events से (और delete होने से पहले local JSON में मौजूद बिलों से) `linkedChallanIds` तथा `items[].sourceChallanId` / `sourceChallanNo` निकालकर LWW-safe तरीके से (`ch.updatedAt <= deleteEventTs`) संबंधित Challans को `"Pending"` करता है।

3. **`lib/sync_core/multi_fy_cloud_vault.dart`**
   - `applyCrossFyEdgeEventsToLocalDisk` में `D1SalesLedgerService.revertLinkedChallansFromDeleteEvents` जोड़ा गया ताकि किसी पिछले FY (`2025-26`) का Bill remote से delete होने पर उसी FY की डिस्क में संबंधित Challan तुरंत `"Pending"` हो जाए, उसका tombstone unmark हो जाए, और active FY में cascade हो सके।

4. **`lib/realtime_signaling/engines/fast_pull_engine.dart` & `lib/web_live_sync/app_sync_engine.dart`**
   - `FastPullEngine._pullOnce` और `AppSyncEngine.pushStoreData` में remote `SALE` / `PURCHASE` `DELETE` लागू करने से पहले `revertLinkedChallansFromDeleteEvents` और `TombstoneEngine` unmarking जोड़ी गई।

5. **`lib/pharoah_manager.dart`**
   - `syncPendingChallansFromPreviousYears()` और `cascadePendingChallansOnlyFromBackYear(String editedFy)` जोड़े गए।
   - `switchYear(String newYear)` में केवल `await syncPendingChallansFromPreviousYears()` जोड़ा गया — जिससे `switchYear()` में Party Opening Balance (`opBal`) या Medicine Stock बिल्कुल नहीं बदलते, परंतु पिछले सालों के सभी `"Pending"` Challans (जिनमें Converted Bill delete होने से `"Pending"` हुए Challans भी शामिल हैं) तुरंत नए FY में आ जाते हैं।
   - `loadAllData()` और `_reloadMemoryFromDisk()` में `s_challans.json` और `p_challans.json` पर `TombstoneEngine.isSaleChallanDeleted` / `isPurchaseChallanDeleted` फ़िल्टर लगाया गया।
   - `deleteBill()` और `deletePurchase()` में:
     - `linkedChallanIds` और `items[].sourceChallanId` / `sourceChallanNo` से Challan को `"Pending"` करके `version++` व `updatedAt = nowMs` किया गया।
     - `TombstoneEngine.unmarkSaleChallanDeleted` / `unmarkPurchaseChallanDeleted` कॉल किया गया।
     - `SaleChallanSyncModule.enqueuePopupMutation` / `PurchaseChallanSyncModule.enqueuePopupMutation` को `await` किया गया।
     - यदि delete किसी पिछले FY में हुआ है, तो `await cascadePendingChallansOnlyFromBackYear(currentFY)` चलाकर आगे के सभी FYs के `s_challans.json` / `p_challans.json` और उनके Outbox को अपडेट किया गया, और उसके बाद `AppRealtimeCoordinator.instance.notifyAppMutation(..., fy: currentFY)` भेजा गया।
   - `finalizeSaleChallan`, `finalizePurchaseChallan`, `deleteSaleChallan`, `deletePurchaseChallan`, `finalizeSale`, और `finalizePurchase` में `Future.microtask` की जगह `await WebLiveToken.getOrCreateToken(...)` + synchronous Outbox enqueue करने के बाद ही `notifyAppMutation(..., fy: currentFY)` कॉल किया गया।

6. **`lib/web_live_sync/pharoah_web_manager.dart`**
   - `_hotSwapActiveYearMastersFromVault()` में **Section `3b. Sale Challans Hot-Swap`** और **Section `3c. Purchase Challans Hot-Swap`** जोड़े गए (LWW और Tombstone सुरक्षा के साथ)।
   - `_cascadeWebFyVaultFrom()` में `FyTransferEngine.reconcileCarryForwardSaleChallans` और `reconcileCarryForwardPurchaseChallans` जोड़े गए।
   - `deleteSale` और `deletePurchase` में converted challan reversion के समय `TombstoneEngine.unmark...` और Outbox enqueue के साथ `_snapshotActiveFyToVault()` और `fy: financialYear` सुनिश्चित किया गया।
   - `addSaleChallanAndSync`, `addPurchaseChallanAndSync`, `deleteSaleChallan`, `deletePurchaseChallan` में `_snapshotActiveFyToVault()` और `notifyWebMutation(..., fy: financialYear)` जोड़े गए।
   - `addSaleAndSync` और `addPurchaseAndSync` में item-level `sourceChallanId`/`sourceChallanNo` चेक और `if (ch.status != "Billed")` guard लगाया गया।
   - `applyCrossFyBatchEnvelopeToVault(SyncEnvelope env, String targetFy)` जोड़ा गया ताकि जब App किसी पिछले FY (`2025-26`) में Bill delete करे या Challan अपडेट करे और Web `2026-27` में खुला हो, तो Web अपने `fyVault['2025-26']` में Challan को `"Pending"` करके `_cascadeWebFyVaultFrom('2025-26')` और `_hotSwapActiveYearMastersFromVault()` के ज़रिए तुरंत `2026-27` की स्क्रीन पर बिना पेज रिफ्रेश किए वह Challan दिखा दे।
   - `refreshStoreData({bool isSilent = false})` में जब `isSilent && syncedAtStr == _lastRemoteSyncedAt` हो, तब अनावश्यक full cloud JSON parse, `rebuildInventory()`, और `notifyListeners()` को रोका गया (केवल `_harvestD1EdgeDeltas` चलता है)।

7. **`lib/sync_core/orchestrator/master_sync_orchestrator.dart`**
   - Cross-FY `SALE`, `PURCHASE`, `SALE_CHALLAN`, `PURCHASE_CHALLAN` envelopes को drop करने के बजाय `phWeb.applyCrossFyBatchEnvelopeToVault(env, envTargetFy)` पर रूट किया गया।
   - Same-FY Web `PURCHASE` `DELETE` में `purgeDeletedIds` से **पहले** `phWeb.purchases` से `linkedChallanIds` और `sourceChallanId` / `sourceChallanNo` निकाले गए ताकि deleted Purchase से जुड़ा `PurchaseChallan` हमेशा `"Pending"` में वापस आ जाए।
   - `PURCHASE_CHALLAN` पर supplier के `billNo` का original case सुरक्षित रखा गया।

8. **`lib/web_live_sync/sub_views/web_billing/web_new_sale_view.dart` & `lib/web_live_sync/sub_views/web_purchase/mechanism/web_purchase_mechanism.dart`**
   - Bulk/Single Challan conversion loops में `if (ch.status != "Billed")` guard लगाया गया ताकि पहले से `"Billed"` Challans दोबारा mutate या sync न हों, और केवल वास्तव में convert हुए Challans का `version++`, `updatedAt`, और `SaleChallanSyncModule` / `PurchaseChallanSyncModule` चले।

9. **`lib/web_live_sync/sub_views/web_challans/web_sale_challan_view.dart` & `web_purchase_challan_view.dart`**
   - `RECENT STORE DISPATCHES` और `RECENT INWARD RECEIPTS` की sorting को केवल `date` के बजाय `updatedAt > 0 ? updatedAt : date.millisecondsSinceEpoch` (tie-breaker: `date`) पर किया गया, ताकि नया, संपादित, या पुराने बिल के delete होने से `"Pending"` में लौटा Challan तुरंत सबसे ऊपर दिखाई दे।

10. **`lib/challans/purchase_challan_register.dart`**
    - App के Purchase Challan Register के कार्ड्स पर स्पष्ट `PENDING` / `BILLED` status badge लगाया गया और `ch.status == "Billed"` होने पर `Modify / Edit Items` को lock करके चेतावनी संदेश (`"Locked: Converted to Purchase Bill"`) दिखाया गया।

11. **`lib/web_live_sync/sub_views/web_challans/web_sale_challan_billing_view.dart` & `web_purchase_challan_billing_view.dart`**
    - `Provider.of<PharoahWebManager>(context)` को हटाकर `listen: false` + `context.select<PharoahWebManager, int>((m) => m.medicines.length)` किया गया।
    - `Scaffold(resizeToAvoidBottomInset: false)` जोड़ा गया।
    - Product search dropdown के `ListView.builder` को `Material(color: Colors.transparent)` में लपेटा गया, हर row को स्थिर `ValueKey` दिया गया, और `onTap` में पहले `_openItemEntry` / `_openPcItemDialog` कॉल करके बाद में `productSearchC.clear()` किया गया।
    - मोबाइल (`390×844`) और डेस्कटॉप (`1440×900`) दोनों स्क्रीन आकारों के लिए Header, Footer और Dialog summary rows को `LayoutBuilder` / `Wrap` के साथ पूरी तरह overflow-free बनाया गया।

12. **`lib/web_live_sync/components/web_top_bar.dart`, `lib/web_live_sync/components/web_recent_sidebar.dart`, `colab_runner_813.py` & `test/challan_fy_recovery_p0_test.dart`**
    - PH Live Series को `#PH-REV-813 (FIX-CHALLAN-FY-RECOVERY-REALTIME-AND-PRODUCT-TAP)` पर अपडेट किया गया और 9 व्यापक automated tests (`T1` से `T7` + LWW/Tombstone/OpBal isolation) जोड़े गए।

---

## 4. अन्य ERP Workflows पर प्रभाव का विश्लेषण (Impact & Non-Regression Analysis)

1. **Sale Bill & Purchase Bill Creation / Deletion:**
   - सामान्य Sale या Purchase Bill (जो किसी Challan से नहीं बने हैं) के बनने या delete होने के तर्क में कोई बदलाव नहीं है। केवल जिन बिलों में `linkedChallanIds` या `items[].sourceChallanId`/`sourceChallanNo` हैं, उनके delete होने पर संबंधित Challans को सुरक्षित रूप से `"Pending"` किया जाता है।
2. **Inventory / Batch Stock Deduction & Reversal:**
   - `rebuildInventory()` और Batch stock गणना पूरी तरह अपरिवर्तित हैं। जब Bill delete होता है और Challan `"Pending"` बनता है, तो stock एक ही बार Challan के माध्यम से hold रहता है (दोहरी कटौती नहीं होती)।
3. **Party Ledger & GST Calculations:**
   - Challan कभी भी वित्तीय Party Ledger या GST रिटर्न में नहीं जुड़ता; केवल `"Pending"` / `"Billed"` डिस्पैच/इनवर्ड स्थिति बदलती है।
4. **Opening Balance / Closing Stock Manual Sync (`syncOpeningBalancesFromPreviousYear`):**
   - `switchYear()` में केवल `syncPendingChallansFromPreviousYears()` चलता है, जो सिर्फ `s_challans.json` और `p_challans.json` को पढ़ता/लिखता है। `parts.json` (`opBal`) और `meds.json` (Closing/Opening Stock) को `switchYear()` बिल्कुल नहीं छूता — यह `T1` और `T2-App` (`expect(partyInNewFy.opBal, 5432.10)` / `9876.50`) द्वारा स्वचालित रूप से प्रमाणित है।
5. **Earlier Fix `#PH-REV-812` (App to Web Purchase Re-Creation Sync):**
   - `test/purchase_recreation_sync_test.dart` और `test/three_issues_independent_regression_test.dart` सहित सभी पूर्ववर्ती sync और tombstone tests 100% pass हुए हैं।

---

## 5. कौन-कौन से Tests चलाए गए और उनके परिणाम (Automated Test Results)

GitHub Actions CI (Run `43619924589`, Commit `fe59f65`) पर `flutter test` के अंतर्गत कुल **48 tests** चले और **48 के 48 PASS हुए (`0 failed`)**:

### नया Test Suite (`test/challan_fy_recovery_p0_test.dart` — 9 End-to-End Tests):
1. ✅ **`T1: App deleteBill in 2025-26 recovers SaleChallan to Pending and carries into 2026-27 on switchYear without altering opBal`**
2. ✅ **`T2-App: App deletePurchase in 2025-26 recovers PurchaseChallan to Pending and carries into 2026-27 on switchYear without altering opBal`**
3. ✅ **`T2 & Cross-FY Web Vault: Cross-FY PURCHASE DELETE in MasterSyncOrchestrator reverts PurchaseChallan in back FY Vault & hot-swaps 2026-27 Web memory`**
4. ✅ **`Same-FY Web PURCHASE DELETE in MasterSyncOrchestrator extracts sourceChallanId before purgeDeletedIds removes Purchase from memory`**
5. ✅ **`T3: MultiFyCloudVault.applyCrossFyEdgeEventsToLocalDisk reverts linked challans & cascades Pending forward to active FY without altering opBal`**
6. ✅ **`LWW & Tombstone Isolation: Newer 2026-27 Billed status not downgraded & deleted 2026-27 Challan not resurrected; D1 sales/purchase ignore Challan docs`**
7. ✅ **`T4 & Vault Snapshot: Web addSaleChallanAndSync, addPurchaseChallanAndSync, deleteSaleChallan, deletePurchaseChallan & single conversion update fyVault and outbox immediately`**
8. ✅ **`T5: RECENT STORE DISPATCHES & RECENT INWARD RECEIPTS sort by latest updatedAt (back-dated / recovered challan appears at top)`**
9. ✅ **`T6 & T7: Web Sale Challan & Purchase Challan Product Selection opens Batch/Config Dialog on 1st Click even when PharoahWebManager notifies listeners`**

### पूर्ववर्ती Regression Suites (सभी 39 Tests Passed):
- ✅ `test/purchase_recreation_sync_test.dart` (`#PH-REV-812` App to Web Purchase Re-Creation Sync)
- ✅ `test/three_issues_independent_regression_test.dart` (Multi-MRP NO BATCH Survival across FY, Mixed-Case Purchase Modify+Delete, Burst Coalescing)
- ✅ अन्य सभी यूनिट व सिंक टेस्ट (कुल **48/48 Passed**).

---

## 6. पहले के Intermediate CI Runs क्यों रुके थे और उन्हें कैसे ठीक किया गया

1. **Run `43615761470` (`a5c75e7`):** `pharoah_manager.dart` के `deleteBill()` में `bizType` लोकल वेरिएबल घोषित नहीं था और `fast_pull_engine.dart` व `app_sync_engine.dart` में `models.dart` का import छूट गया था → Commit `929c48b` में ठीक किया गया।
2. **Run `43617508502` (`0ba07d9`):** Python स्क्रिप्ट से पैच लगाते समय `"Billed"` और `"APP_MOBILE"` के कोट्स हट गए थे → Commit `69321e1` में ठीक किया गया।
3. **Run `43617960544` (`69321e1`) & Run `43618886251` (`51221f5`):** `T6 & T7` में जब `WebPurchaseChallanBillingView` को संकीर्ण मोबाइल स्क्रीन (`390×844`) पर चलाकर पहली बार में `_openPcItemDialog` खोला गया, तो Flutter के टेस्ट फ्रेमवर्क ने डायलॉग के अंदर और फुटर के बटनों में `Row` (`RenderFlex`) का `45px`–`156px` horizontal overflow पकड़ा।
4. **Run `43619574983` (`bfebe4f`) → Final Fix in `fe59f65`:** `bfebe4f` में सारे `RenderFlex` overflows समाप्त हो गए; `_rateSegment` (जो `Expanded` लौटाता है) के लिए `Row` parent को Commit `fe59f65` में वापस रखा गया, जिसके बाद **Run `43619924589` और Run `43619924543` दोनों 100% सफल (`conclusion=success`)** रहे।

---

## 7. Build Verification एवं PH Live Series Update

### PH Live Series Update:
- **`lib/web_live_sync/components/web_top_bar.dart`:**
  `const String phLiveVersion = "#PH-REV-813 (FIX-CHALLAN-FY-RECOVERY-REALTIME-AND-PRODUCT-TAP)";`
- **`lib/web_live_sync/components/web_recent_sidebar.dart`:**
  `const String phLiveVersion = "#PH-REV-813 (FIX-CHALLAN-FY-RECOVERY-REALTIME-AND-PRODUCT-TAP)";`
- **`colab_runner_813.py`:**
  `#PH-REV-813 (FIX-CHALLAN-FY-RECOVERY-REALTIME-AND-PRODUCT-TAP)` पर सिंक किया गया।

### Build Results (GitHub Actions Run `43619924589` & `43619924543` on Commit `fe59f65`):
- **`flutter pub get`:** `completed (success)`
- **`flutter test`:** `completed (success)` — `48 passed, 0 failed`
- **`flutter build apk --release`:** `completed (success)` — `✓ Built build/app/outputs/flutter-apk/app-release.apk (110.7MB)`
- **`flutter build web --release --no-tree-shake-icons`:** `completed (success)`

---

## 8. Cloudflare Pages Production Deployment Verification

- **GitHub Actions Workflow:** `Build Flutter Web Portal and Android APK`
- **Run ID:** `43619924589` (Job ID: `132523070033`, Commit: `fe59f65`)
- **Step 11 (`Deploy production web to Cloudflare Pages`):** `completed (success)`
- **Cloudflare Pages Project:** `pharoah-erp` (`branch: main`)
- **Verified CI Log Output:**
  ```text
  ✨ Success! Uploaded 2 files (29 already uploaded) (1.47 sec)
  ✨ Deployment complete! Take a peek over at https://b23c88ef.pharoah-erp.pages.dev
  ```
- **Production URL:** `https://pharoah-erp.pages.dev` (Preview Alias: `https://b23c88ef.pharoah-erp.pages.dev`)

---

## 9. ईमानदार सत्यापन सीमा (What Was Verified in Automated CI vs Live Multi-Device Runtime)

- **Automated CI एवं Widget/Integration Tests में पूर्णतः सत्यापित (100% Verified):**
  - `T1` से `T7` के सभी डेटा-फ्लो, डिस्क फ़ाइल (`s_challans.json`, `p_challans.json`, `parts.json`, `meds.json`) का पृथक्करण, `switchYear()` में `opBal` अपरिवर्तित रहना, Cross-FY और Same-FY `SALE`/`PURCHASE` `DELETE` पर Challan का `"Pending"` में लौटना, Tombstone unmarking, LWW सुरक्षा, `RECENT STORE DISPATCHES` / `RECENT INWARD RECEIPTS` की `updatedAt` आधारित क्रमबद्धता, और Desktop (`1440×900`) व Mobile (`390×844`) दोनों पर `PharoahWebManager.notifyListeners()` के बीच पहली ही बार के टैप पर प्रोडक्ट बैच डायलॉग खुलना।
  - Production Android Release APK (`app-release.apk`) और Production Flutter Web बंडल का निर्माण तथा `pharoah-erp.pages.dev` पर लाइव Cloudflare Pages डिप्लॉयमेंट।
- **Physical Android Phone + Live Browser पर अंतिम उपयोगकर्ता जाँच हेतु (Live Runtime Boundary):**
  - वास्तविक भौतिक Android फ़ोन पर नया APK इंस्टॉल करके लाइव नेटवर्क (Cloudflare Worker WebSocket / D1 पोलिंग) के माध्यम से दो अलग-अलग उपकरणों के बीच नेटवर्क लेटेंसी का अनुभव भौतिक उपकरणों पर ही देखा जा सकता है; इसके सभी कोड पथ, टोकन जनरेशन, Outbox फ्लश और Cross-FY Vault हैंडलर्स कोड व टेस्ट स्तर पर पूरी तरह सत्यापित और तैनात कर दिए गए हैं।

---

## 10. `git diff --stat` (`5124b92..fe59f65`)

```text
 colab_runner_813.py                                | 145 ++++
 lib/challans/purchase_challan_register.dart        |  29 +-
 lib/fy_transfer_engine.dart                        | 218 +++++-
 lib/pharoah_manager.dart                           | 525 +++++++++-----
 .../engines/fast_pull_engine.dart                  |  41 +-
 lib/sync_core/d1_sales_ledger_service.dart         | 174 ++++-
 lib/sync_core/multi_fy_cloud_vault.dart            |  55 +-
 .../orchestrator/master_sync_orchestrator.dart     |  80 ++-
 lib/web_live_sync/app_sync_engine.dart             |  13 +
 .../components/web_recent_sidebar.dart             |   2 +-
 lib/web_live_sync/components/web_top_bar.dart      |   2 +-
 lib/web_live_sync/pharoah_web_manager.dart         | 509 ++++++++++++--
 .../sub_views/web_billing/web_new_sale_view.dart   |  12 +-
 .../web_purchase_challan_billing_view.dart         | 175 +++--
 .../web_challans/web_purchase_challan_view.dart    |   7 +-
 .../web_sale_challan_billing_view.dart             | 254 ++++---
 .../web_challans/web_sale_challan_view.dart        |   7 +-
 .../mechanism/web_purchase_mechanism.dart          |  12 +-
 test/challan_fy_recovery_p0_test.dart              | 761 +++++++++++++++++++++
 19 files changed, 2634 insertions(+), 387 deletions(-)
```
