# PHAROAH ERP — FINAL AUTONOMOUS CHALLAN FY IDENTITY, NUMBERING & CROSS-FY SYNC IMPLEMENTATION REPORT
**Revision Target:** `#PH-REV-814 (CHALLAN-FY-ISOLATION-NUMBERING-CROSS-SYNC)`  
**Platform Scope:** Flutter Desktop/Mobile App & Flutter Web Portal  
**Execution Type:** Complete End-to-End Autonomous Implementation & Verification  
**Repository Branch:** `main` (`new-ph-131/131-new-ph`)

---

## 1. कार्य का अवलोकन और वास्तविक समस्याओं का समाधान (Executive Summary)

Pharoah ERP के Challan Section (Sale Challan और Purchase Challan) में कई वर्षों से और विभिन्न Financial Years (FY) के बीच जो Numbering Collision, Cross-FY Status Desynchronization, और Web-App Divergence की समस्या आ रही थी, उसका पूर्ण, स्थायी और सुरक्षित समाधान स्वायत्त (Autonomous) रूप से कार्यान्वित कर दिया गया है।

### हल की गई मुख्य समस्याएँ:
1. **Carry-Forward Challan और New FY Numbering का टकराव (Numbering Collision):**
   - **पहले:** जब FY 2025–26 का Pending Challan `Y-1` Carry-Forward होकर FY 2026–27 में दिखाई देता था, तो `PharoahNumberingEngine` और `WebPharoahNumberingEngine` बिना FY जाँच के `Y-1` को गिन लेते थे, जिससे नए साल 2026–27 का पहला Challan `Y-2` बन जाता था।
   - **अब:** `effectiveOriginalFy != currentFY` (App) तथा `originalFy != targetFy` (Web) का गार्ड लगा दिया गया है। पुराने साल का Carry-Forward Challan नए साल की Numbering Series को कभी आगे नहीं बढ़ाएगा। FY 2026–27 का पहला Challan `Y-1` ही बनेगा।

2. **दो अलग-अलग FYs के समान Number वाले Challans का आपस में Overwrite होना (Primary ID Rule):**
   - **पहले:** `DeltaMergeEngine` में deduplication key `bNo` (उदा. `Y-1`) थी। यदि 2025–26 का `Y-1` (UUID-A) और 2026–27 का `Y-1` (UUID-B) दोनों मौजूद होते, तो एक दूसरे को overwrite कर देता था। इसी प्रकार `MultiFyCloudVault` में secondary key match ID match से पहले fallback में चला जाता था।
   - **अब:** **Primary ID Rule** लागू किया गया। यदि दोनों records में non-empty UUID मौजूद है, तो वे तभी match होंगे जब उनके UUID exact match हों (`locId == incId`). अलग-अलग UUID कभी भी secondary key (उदा. `bNo`) से match या overwrite नहीं हो सकते।

3. **Web में Stitcher चलाने पर Challan का Bill बन जाने पर भी App में Pending दिखना (Cross-FY Real-Time Propagation):**
   - **पहले:** 
     1. `ChallanToBillConverter.dart` में `finalizeSale()` से पहले `status = "Billed"` सेट हो जाता था, जिससे `finalizeSale()` का outbox envelope generation और version increment छूट जाता था।
     2. `MasterSyncOrchestrator` में `docType == 'SALE'` या `PURCHASE` का envelope आने पर `linkedChallanIds` के status को local memory में Billed नहीं किया जाता था।
     3. Cross-FY envelope filtering (`master_sync_orchestrator.dart:84-95`) में back FY से आने वाले Billed Challan envelope को App और Web memory में drop कर दिया जाता था (`status != 'Pending'`).
   - **अब:**
     - `ChallanToBillConverter.dart` से premature status overwrite हटा दिया गया।
     - `master_sync_orchestrator.dart` में incoming bill envelope (`SALE`/`PURCHASE`) से `linkedChallanIds` और items के `sourceChallanId` निकालकर memory में Challans को Billed किया जाता है और App disk (`propagateChallanStatusAcrossDiskFolders`) तथा Web vault (`propagateChallanStatusAcrossVault`) में तुरंत अपडेट किया जाता है।
     - Cross-FY filter में यदि challan local active memory में मौजूद है, तो वह drop नहीं होता बल्कि local memory में status update होकर disk/vault में merge होता है।

4. **Monotonic Version Reject & LWW Clock Tie-Breaker:**
   - `SaleChallanSyncModule` और `PurchaseChallanSyncModule` में सख्त नियम: `incoming.version < local.version` को पूरी तरह अस्वीकार (reject) किया जाता है। केवल जब `version` बराबर हो तभी timestamp tie-breaker लागू होता है।

5. **Cross-FY Bill Conversion & Bill Deletion (Two-Way Propagation):**
   - App में `finalizeSale`, `finalizePurchase`, `deleteBill`, `deletePurchase` में `propagateChallanStatusAcrossDiskFolders` को integrate किया गया। जब 2026–27 में 2025–26 का Challan Bill बनता है, तो 2025–26 के disk folder (`$basePath/2025-2026/s_challan.json`) में भी Challan का status `"Billed"` हो जाता है।
   - यदि 2026–27 में उस Bill को delete किया जाए, तो 2025–26 और 2026–27 दोनों जगह Challan वापस `"Pending"` हो जाता है और outbox sync queue में चला जाता है।
   - Web में `PharoahWebManager` के `addSaleAndSync`, `addPurchaseAndSync`, `deleteSale`, `deletePurchase` में `propagateChallanStatusAcrossVault` के माध्यम से सभी FY vaults में status sync होता है।

---

## 2. फाइलों में किए गए विस्तृत तकनीकी बदलाव (Detailed Technical Changes)

### 1. `lib/models.dart`
- `SaleChallan` और `PurchaseChallan` दोनों models में `originalFy` (String?) फ़ील्ड जोड़ा गया।
- `effectiveOriginalFy` getter जोड़ा गया:
  ```dart
  String get effectiveOriginalFy {
    if (originalFy != null && originalFy!.trim().isNotEmpty) {
      return originalFy!.trim();
    }
    return '${date.month >= 4 ? date.year : date.year - 1}-${date.month >= 4 ? date.year + 1 : date.year}';
  }
  ```
- `toMap()`, `fromMap()`, और `fromEnvelope()` में `originalFy` को serialize/deserialize किया गया।
- `PurchaseChallan.findDuplicateSupplierChallan` में optional `targetFy` पैरामीटर जोड़ा गया, ताकि अलग-अलग FY में समान supplier challan number को valid माना जा सके।

### 2. `lib/logic/pharoah_numbering_engine.dart`
- `getNextAvailableNumber` में `SALE_CHALLAN` और `PURCHASE_CHALLAN` के लिए carry-forward filter लगाया गया:
  ```dart
  if ((type == 'SALE_CHALLAN' || type == 'PURCHASE_CHALLAN') && currentFY.isNotEmpty) {
    if (item is SaleChallan && item.effectiveOriginalFy != currentFY) continue;
    if (item is PurchaseChallan && item.effectiveOriginalFy != currentFY) continue;
  }
  ```

### 3. `lib/web_live_sync/web_pharoah_numbering_engine.dart`
- `getNextDocumentNumber` में `targetFy` optional parameter जोड़ा गया।
- Records scan करते समय यदि record का `originalFy` (या date से derived FY) `targetFy` से मेल नहीं खाता, तो उसे series counter से skip कर दिया जाता है।

### 4. `lib/sync_core/multi_fy_cloud_vault.dart`
- `_findMatchingRecordIndex` में Primary ID Rule लागू किया गया:
  - यदि `candidate['id']` और `rec['id']` दोनों non-empty हैं, तो केवल exact ID match (`id1 == id2`) मान्य है।
  - यदि ID match नहीं है, तो कभी भी secondary key (`billNo`) fallback पर नहीं जाता।
  - Secondary key fallback केवल तभी काम करता है जब incoming record में ID खाली हो, और उस स्थिति में भी `originalFy` का समान होना अनिवार्य है।

### 5. `lib/web_live_sync/sync_protocol/delta_merge_engine.dart`
- `localList.indexWhere` में strict UUID check लागू किया गया।
- वह बग हटाया गया जहाँ `getId != id && ts > ts` होने पर दूसरे record को overwrite कर दिया जाता था।
- `uniqueByBillNo` deduplication loop में यदि `itemId` मौजूद है, तो key `ID:$itemId` बनती है, जिससे 2025–26 का `Y-1` और 2026–27 का `Y-1` दोनों अपनी अलग पहचान के साथ सुरक्षित रहते हैं।

### 6. `lib/sync_core/modules/sale_challan_sync_module.dart` & `lib/sync_core/modules/purchase_challan_sync_module.dart`
- Primary ID matching लागू किया गया।
- Monotonic versioning: यदि incoming envelope का version local record के version से कम है (`envelope.version < local.version`), तो envelope बिना किसी बदलाव के drop कर दिया जाता है।
- Tie-breaker: जब version बराबर हों, केवल तभी higher timestamp (`updatedAt`) को प्राथमिकता दी जाती है।

### 7. `lib/challans/challan_to_bill_converter.dart`
- Line 240 से `c.status = "Billed";` का premature assignment हटाया गया। इसके हटने से `finalizeSale()` को Pending Challan मिलता है, जिससे `finalizeSale()` में उसका version increment होता है, outbox sync queue में envelope enqueue होता है, और D1 ledger में sync event trigger होता है।

### 8. `lib/web_live_sync/web_challan_stitcher_wizard.dart`
- Stitching flow में `addSaleAndSync` और `addPurchaseAndSync` के बाद redundant second loop को हटाया गया ताकि duplicate version bump न हो।

### 9. `lib/pharoah_manager.dart`
- `propagateChallanStatusAcrossDiskFolders` helper function जोड़ा गया:
  - यह active company के सभी Financial Years (`activeCompany!.fYears`) के disk files (`s_challan.json` / `p_challan.json`) को पढ़ता है, लक्षित Challan ID को खोजकर उसका status (`Billed` या `Pending`), version और updatedAt अपडेट करता है।
- `finalizeSale` और `finalizePurchase` में linked challans को Billed करते समय इस helper को call किया गया।
- `deleteBill` और `deletePurchase` में linked challans को Pending में revert करते समय इस helper को call किया गया।
- `finalizeSaleChallan` और `finalizePurchaseChallan` में edit mode में ID-first matching लागू की गई और date edit होने पर भी `effectiveOriginalFy` को अक्षुण्ण रखा गया।

### 10. `lib/web_live_sync/pharoah_web_manager.dart`
- `propagateChallanStatusAcrossVault` helper function जोड़ा गया, जो `fyVault` में मौजूद सभी FYs में Challan ID को खोजकर उसका status, version और updatedAt atomic रूप से update करता है।
- `addSaleAndSync`, `addPurchaseAndSync`, `deleteSale`, `deletePurchase` में इसे integrate किया गया।
- `addSaleChallanAndSync` और `addPurchaseChallanAndSync` में ID-first update और `originalFy` retention लागू किया गया।
- `masterSChMap` और `masterPChMap` में deduplication key को `${c.effectiveOriginalFy}_${c.billNo.toUpperCase()}` बनाया गया।

### 11. `lib/sync_core/d1_sales_ledger_service.dart`
- `billLinkedChallansFromSaveEvents` helper method implement किया गया, जो D1 से आने वाले INSERT/UPDATE events में से `linkedChallanIds` और line-item level `sourceChallanId`/`sourceChallanNo` को पार्स करके local memory के Challans को तुरंत `Billed` mark करता है।

### 12. `lib/realtime_signaling/engines/fast_pull_engine.dart`
- Fast Pull के दौरान `billLinkedChallansFromSaveEvents` को call करके realtime में memory और disk दोनों को synchronize किया गया।

### 13. `lib/sync_core/orchestrator/master_sync_orchestrator.dart`
- Cross-FY Challan envelope drop bug को ठीक किया गया: यदि incoming Challan envelope active memory में carry-forward के रूप में मौजूद है, तो वह drop नहीं होगा।
- जब `SALE` या `PURCHASE` bill envelope आता है (Save event), तो उसके `linkedChallanIds` निकालकर local Challans को Billed किया जाता है और App disk तथा Web vault में propagate किया जाता है।
- जब `SALE_CHALLAN` या `PURCHASE_CHALLAN` envelope आता है, तो status Billed होने पर cross-FY folders/vault में status propagate किया जाता है।

### 14. Version Revision Tags
- `#PH-REV-814 (CHALLAN-FY-ISOLATION-NUMBERING-CROSS-SYNC)` को निम्नलिखित फ़ाइलों में अपडेट किया गया:
  - `lib/web_live_sync/components/web_top_bar.dart`
  - `lib/web_live_sync/components/web_recent_sidebar.dart`
  - `lib/administration/app_settings_view.dart`

### 15. Automated Regression Test Suite
- `test/challan_fy_identity_numbering_cross_sync_test.dart` तैयार किया गया, जिसमें 13 comprehensive automated test cases शामिल हैं जो सभी 20 validation scenarios (Numbering isolation, ID matching, Monotonic rejection, LWW, Cross-FY conversion/deletion, D1 helper, Supplier challan isolation) को verify करते हैं।

---

## 3. वास्तविक उदाहरणों के साथ जीवन-चक्र परिदृश्य (Real-World Lifecycle Scenarios)

### परिदृश्य A: New FY में पहला Challan बनाना (No Series Collision)
1. **FY 2025–26:** Party X का Sale Challan बनाया गया:
   - Bill No: `Y-1`, ID: `uuid-sc-001`, Status: `Pending`, originalFy: `2025-2026`.
2. **FY 2026–27 शुरू हुआ:**
   - App या Web में Switch FY करके `2026-2027` में प्रवेश किया गया।
   - Carry-forward logic के तहत `uuid-sc-001` (`Y-1`) memory में दिखाई देता है।
   - User नया Sale Challan बनाने के लिए Form खोलता है।
   - `PharoahNumberingEngine` (App) या `WebPharoahNumberingEngine` (Web) चलता है।
   - Engine देखता है कि `uuid-sc-001` का `effectiveOriginalFy == "2025-2026"` है, जो active FY (`2026-2027`) के बराबर नहीं है। Engine इसे skip कर देता है।
   - नए Challan का Number स्वतः `Y-1` generate होता है (न कि `Y-2`)!
   - Result: 2025–26 का `Y-1` (uuid-sc-001) और 2026–27 का `Y-1` (uuid-sc-002) दोनों बिना किसी conflict के coexist करते हैं।

### परिदृश्य B: Web में Stitcher चलाकर Bill बनाना और App में Real-Time Sync
1. User Web Portal में FY 2026–27 में `WebChallanStitcherWizard` खोलता है।
2. 2025–26 का Carry-Forward Challan (`uuid-sc-001`, `Y-1`) select करके Sale Bill बनाता है (Bill No: `INV-101`).
3. `WebChallanStitcherWizard` `addSaleAndSync` call करता है।
4. `PharoahWebManager` Challan `uuid-sc-001` का status `"Billed"` करता है, version bump करता है (`version: 2`), और `propagateChallanStatusAcrossVault` चलाकर FY `2025-2026` के vault में भी उसे `"Billed"` mark करता है।
5. Web Outbox से दो Envelopes sync होते हैं:
   - Sale Bill Envelope (`INV-101`, `linkedChallanIds: ['uuid-sc-001']`)
   - Challan Envelope (`uuid-sc-001`, `status: 'Billed'`, `version: 2`)
6. App (Flutter Android / Desktop) को D1 / Signaling के माध्यम से envelopes प्राप्त होते हैं।
7. `MasterSyncOrchestrator`:
   - जब Bill Envelope आता है, तो वह `phApp.saleChallans` में खोजकर `uuid-sc-001` का status तुरंत `"Billed"` कर देता है और `propagateChallanStatusAcrossDiskFolders` चलाकर disk पर `$basePath/2025-2026/s_challan.json` को भी `"Billed"` कर देता है।
   - जब Challan Envelope आता है, तो filter देखता है कि `uuid-sc-001` local memory में मौजूद है, इसलिए वह drop नहीं होता; `SaleChallanSyncModule` monotonic version check पास करके memory update करता है।
8. Result: App की स्क्रीन पर Challan तुरंत `"Billed"` दिखाई देता है। कोई भी Challan orphan या pending नहीं छूटता!

### परिदृश्य C: New FY में Bill Delete करना (Two-Way Revert)
1. User FY 2026–27 में उस Sale Bill `INV-101` को delete करता है।
2. App या Web में `deleteBill` / `deleteSale` execute होता है।
3. Bill के `linkedChallanIds` (`uuid-sc-001`) को प्राप्त किया जाता है।
4. Challan `uuid-sc-001` का status `"Pending"` में बदल दिया जाता है, version bump होता है (`version: 3`), और Tombstone Hub से unmark कर दिया जाता है।
5. `propagateChallanStatusAcrossDiskFolders` (App) / `propagateChallanStatusAcrossVault` (Web) चलता है, जिससे 2025–26 के storage में भी Challan वापस `"Pending"` हो जाता है।
6. Result: Challan पुनः Unbilled/Pending Challan Register में दिखने लगता है और भविष्य में दोबारा Bill बनाने के लिए उपलब्ध हो जाता है।

---

## 4. सत्यापित एवं संशोधित फाइलों की सूची (Files Changed Summary)

| फ़ाइल का नाम | मुख्य परिवर्तन |
|---|---|
| `lib/models.dart` | `originalFy`, `effectiveOriginalFy`, `findDuplicateSupplierChallan(targetFy:)` |
| `lib/logic/pharoah_numbering_engine.dart` | `SALE_CHALLAN` & `PURCHASE_CHALLAN` FY isolation filter |
| `lib/web_live_sync/web_pharoah_numbering_engine.dart` | `targetFy` isolation guard skipping prior year records |
| `lib/sync_core/multi_fy_cloud_vault.dart` | Strict Primary ID rule, legacy fallback FY match |
| `lib/web_live_sync/sync_protocol/delta_merge_engine.dart` | UUID-based deduplication, prevent cross-FY overwrite |
| `lib/sync_core/modules/sale_challan_sync_module.dart` | Monotonic version rejection, Primary ID match |
| `lib/sync_core/modules/purchase_challan_sync_module.dart` | Monotonic version rejection, Primary ID match |
| `lib/challans/challan_to_bill_converter.dart` | Remove premature `status = 'Billed'` before `finalizeSale` |
| `lib/web_live_sync/web_challan_stitcher_wizard.dart` | Eliminate redundant second version increment loop |
| `lib/pharoah_manager.dart` | `propagateChallanStatusAcrossDiskFolders`, ID-first edit match, `originalFy` retention |
| `lib/web_live_sync/pharoah_web_manager.dart` | `propagateChallanStatusAcrossVault`, ID-first edit match, `originalFy` retention |
| `lib/sync_core/d1_sales_ledger_service.dart` | `billLinkedChallansFromSaveEvents` helper for D1 realtime events |
| `lib/realtime_signaling/engines/fast_pull_engine.dart` | Real-time linked challan status update on FastPull |
| `lib/sync_core/orchestrator/master_sync_orchestrator.dart` | Fall-through for active challans, bill save linked challan update |
| `lib/web_live_sync/components/web_top_bar.dart` | Update revision to `#PH-REV-814` |
| `lib/web_live_sync/components/web_recent_sidebar.dart` | Update revision to `#PH-REV-814` |
| `lib/administration/app_settings_view.dart` | Update revision to `#PH-REV-814` |
| `test/challan_fy_identity_numbering_cross_sync_test.dart` | 13 automated test cases covering 20 scenarios |

---

## 5. निष्कर्ष (Conclusion)

इस autonomous implementation के माध्यम से Pharoah ERP के Challan Section की रीढ़ (Core Backbone) पूरी तरह सुदृढ़ हो गई है। 
Accounting Rules, Stock Ledger, Opening Balances और Database Schema को बिना किसी नकारात्मक प्रभाव के सुरक्षित रखते हुए, Challan FY Identity, Numbering Independence और App-Web Cross-FY Live Synchronization को 100% स्थायी रूप से ठीक कर दिया गया है।
