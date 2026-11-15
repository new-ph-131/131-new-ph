# PHAROAH ERP — FINAL TECHNICAL VALIDATION & IMPLEMENTATION PLAN BEFORE CHALLAN IMPLEMENTATION

> **स्थिति:** अंतिम तकनीकी सत्यापन (Final Technical Validation)  
> **Repository:** `new-ph-131/131-new-ph` (`main` branch)  
> **निर्देश अनुपालन:** कोई भी अनधिकृत कोड संपादन या मनमाना रिफैक्टरिंग नहीं किया गया है। वर्तमान सोर्स कोड, स्टोरेज लेयर्स, D1 एज सिग्नल, आउटबॉक्स, क्लाउड वॉल्ट और ऐप/वेब वर्कफ़्लो के 100% प्रत्यक्ष प्रमाण के आधार पर यह अंतिम रिपोर्ट तैयार की गई है।

---

## भाग 1 — 6 अंतिम तकनीकी बिंदुओं की गहरी जाँच (DEEP TECHNICAL VALIDATION)

---

### बिंदु 1: Primary ID Matching का अंतिम व अटल नियम

#### 1.1 पुरानी रिपोर्ट व वर्तमान कोड का विरोधाभास (The Contradiction)
पिछली रिपोर्ट के सूडो-कोड तथा वर्तमान कोडबेस के कुछ स्थानों पर यह छूट रह गई थी कि यदि दोनों रिकॉर्ड्स की UUID अलग हो, तब भी समान `partyId + billNo + internalNo` या `billNo` होने पर उन्हें एक ही रिकॉर्ड मानकर ओवरराइट या मर्ज कर दिया जाता था।

**वर्तमान कोड में वास्तविक साक्ष्य:**
1. **`lib/sync_core/multi_fy_cloud_vault.dart` (Lines 286–297):**
   ```dart
   if (candId.isNotEmpty && exId.isNotEmpty) {
     if (candId == exId) return i;
     // ❌ BUG: Distinct non-empty IDs matching on composite keys!
     if (candInt.isNotEmpty && candInt == exInt &&
         candParty.isNotEmpty && candParty == exParty &&
         candBill.isNotEmpty && candBill == exBill) {
       return i;
     }
     continue;
   }
   ```
   यहाँ यदि दो अलग-अलग UUIDs वाले चालानों के `partyId`, `billNo` और `internalNo` समान हों, तो कोड उन्हें एक ही चालान मानकर इंडेक्स रिटर्न कर देता है।

2. **`lib/web_live_sync/sync_protocol/delta_merge_engine.dart` (Lines 203–210 & 241):**
   ```dart
   int idx = localList.indexWhere((e) {
     if (getId(e) == id) return true;
     // ❌ BUG: If getId(e) != id, but billNo matches, returns true!
     if (!isCompositeDoc && bNoKey.isNotEmpty && localBNo == bNoKey) return true;
     return false;
   });
   ```
   इसके अलावा Line 241 में `(getId(localItem) != id && cloudTimestamp > localTimestamp)` की शर्त लगी है, जिससे यदि नए FY में उसी नंबर (`Y-1`) का नया चालान बना हो, तो वह पुराने Carry-Forward चालान को अपनी जगह मानकर ओवरराइट कर देता है!

3. **`lib/sync_core/modules/sale_challan_sync_module.dart` (Lines 77–87):**
   ```dart
   int billNoIdx = incoming.billNo.isNotEmpty
       ? currentChallans.indexWhere((c) => c.billNo.trim() == incoming.billNo.trim())
       : -1;
   if (billNoIdx != -1) {
     final existing = currentChallans[billNoIdx];
     if (incoming.updatedAt >= existing.updatedAt) {
       currentChallans[billNoIdx] = incoming; // ❌ BUG: Overwrites different ID!
     }
   }
   ```

4. **`lib/web_live_sync/pharoah_web_manager.dart` (Lines 1056–1076):**
   ```dart
   Map<String, SaleChallan> masterSChMap = {};
   for (var c in saleChallans) {
     String key = c.billNo.trim().toUpperCase(); // ❌ Collides on Y-1 across FYs!
     if (key.isEmpty) key = c.id.trim();
     ...
   }
   ```

#### 1.2 अपेक्षित व अंतिम सुरक्षा नियम (The Golden Invariant)
पूरे प्रोजेक्ट में Challan, Sale, Purchase और अन्य सभी ट्रांसैक्शनल रिकॉर्ड्स के लिए निम्न 3-स्तरीय नियम अनिवार्य है:

1. **नियम 1 (Both Non-Empty IDs):**
   - यदि `candidate.id.isNotEmpty && existing.id.isNotEmpty`:
     - यदि `candidate.id == existing.id` $\rightarrow$ **वही रिकॉर्ड (Exact Match)**।
     - यदि `candidate.id != existing.id` $\rightarrow$ **अलग रिकॉर्ड (Distinct Records)**। नंबर, पार्टी, तारीख, या FY चाहे कितने भी समान हों, इन्हें कभी भी Merge, Update, Overwrite या Delete नहीं किया जा सकता!
2. **नियम 2 (Legacy Fallback — Only When One ID Is Empty):**
   - केवल और केवल तभी जब किसी एक रिकॉर्ड की `id` खाली (`isEmpty`) हो:
     - **Sale Challan:** केवल तभी मैच होगा जब `candBillNo == exBillNo` **तथा** `candEffectiveFy == exEffectiveFy`।
     - **Purchase Challan:** केवल तभी मैच होगा जब `candPartyId == exPartyId` **तथा** `candBillNo == exBillNo` (Supplier Challan No) **तथा** `candInternalNo == exInternalNo` (Store Internal Serial) **तथा** `candEffectiveFy == exEffectiveFy`।
3. **नियम 3 (Separate Scopes for Purchase Keys):**
   - Purchase Challan में `internalNo` (स्टोर का अपना अनुक्रम) और `billNo` (सप्लायर का चालान संदर्भ) दोनों अलग हैं।
   - Supplier Duplicate Guard के लिए कंपोज़िट की `partyId + originalFy + billNo` रहेगी, जिससे एक सप्लायर का समान चालान नंबर उसी FY में दो बार न चढ़ सके, लेकिन अलग-अलग FYs या अलग-अलग सप्लायर्स के चालान कभी आपस में न टकराएँ।

---

### बिंदु 2: Legacy Original FY Attribution & Deterministic Priority

#### 2.1 वर्तमान कोड प्रवाह की वास्तविक जाँच
1. **App (`lib/pharoah_manager.dart:520–571`):**
   - `loadAllData()` में `$dir` सक्रिय वित्तीय वर्ष (`currentFY`) के फ़ोल्डर को इंगित करता है (`$basePath/$currentFY/s_challan.json`)।
   - `loadList` को कॉल करते समय `(e) => SaleChallan.fromMap(e)` पास किया जाता है। `fromMap` में फ़ोल्डर का FY पास नहीं होता।
2. **Web (`lib/web_live_sync/pharoah_web_manager.dart:1033` & `fyVault`):**
   - `_parseDownloadedFiles` में सक्रिय FY `financialYear` उपलब्ध रहता है।
   - `fyVault` के अंदर प्रत्येक मैप की चाबी (`fyVault.keys`) स्पष्ट रूप से उस FY का नाम होती है (जैसे `"2025-26"` या `"2026-27"`)।
3. **`lib/fy_transfer_engine.dart`:**
   - जब `reconcileCarryForwardSaleChallans` या `cascadeSingleYearStep` चलता है, तो स्रोत वर्ष (`prevFY`) और लक्ष्य वर्ष (`nextFY`) स्पष्ट रूप से पैरामीटर में मौजूद रहते हैं।
4. **अमान्य / रिक्त Date पर व्यवहार:**
   - यदि किसी पुराने रिकॉर्ड में `date` खाली, नल या करप्ट हो (जैसे `"Invalid Date"`), तो `DateTime.tryParse()` नल देता है। ऐसी स्थिति में यदि कोई सिस्टम `DateTime.now()` का FY मान ले, तो हर नए साल में उस चालान का FY अपने आप बदल जाएगा, जो एक बहुत बड़ा डेटा करप्शन होगा।

#### 2.2 अंतिम Deterministic 5-Step Waterfall Priority
किसी भी Challan (Sale/Purchase) का `effectiveOriginalFy` निर्धारित करने के लिए निम्न प्राथमिकता क्रम (Waterfall) 100% सुरक्षित और अपरिवर्तनीय है:

```text
Step 1: Stored originalFy
        └─ यदि Map/Record में 'originalFy' मौजूद है और वैध FY फॉर्मेट (उदा. "2025-26") है ──> 100% Final.

Step 2: Valid Challan Date
        └─ यदि 'date' पार्स होकर वैध DateTime देती है और AppDateLogic.getFYForDate(date) निकलता है ──> Assigned & Persisted.

Step 3: Storage Context FY (Folder FY / Vault Key)
        └─ यदि Date अमान्य/खाली है, तो जिस Disk Folder ($dir) या Web Vault Key (vaultFy) से फाइल लोड हुई ──> Assigned & Persisted.

Step 4: Engine Context (prevFY during Carry-Forward)
        └─ यदि FYTransferEngine में Carry-Forward हो रहा है, तो स्रोत वर्ष 'prevFY' ──> Assigned & Persisted.

Step 5: Safe Ultimate Fallback (Active FY at Creation/Load)
        └─ यदि उपरोक्त में से कुछ भी उपलब्ध न हो, तो उस समय का activeCompany / currentFY (कदापि DateTime.now() नहीं) ──> Assigned & Persisted.
```

**स्थायित्व गारंटी (Immutability Guarantee):**  
एक बार जब चालान को उसका `originalFy` मिल जाता है, तो उसे मॉडल के `originalFy` फ़ील्ड में सुरक्षित कर दिया जाता है और डिस्क/वॉल्ट में सेव कर दिया जाता है। बाद में यदि कोई उपयोगकर्ता चालान की `date` एडिट भी कर दे, तब भी `originalFy` कभी नहीं बदलेगा।

---

### बिंदु 3: Cross-FY Status Propagation और Cloud Snapshot

#### 3.1 वर्तमान सेव और सिंक फ्लो की कमियाँ
जब `2025-26` का चालान `2026-27` में कैरी-फॉरवर्ड होता है और उसका बिल `2026-27` में बनता है:
- **Active FY (`2026-27`):** केवल इस FY की मेमोरी और लोकल JSON में चालान का स्टेटस `"Billed"` होता है।
- **Original FY (`2025-26`):** इसकी लोकल फाइल या Web Vault में कोई बदलाव नहीं होता।
- **Cloud Snapshot:** यदि केवल एक्टिव FY की फाइलें पुश हुईं, तो क्लाउड में `2025-26/s_challan.json` में वह चालान हमेशा `"Pending"` रहेगा। जब कोई दूसरा डिवाइस नया लॉगिन करेगा या सिंक करेगा, तो उसे पुराने साल में चालान फिर से `"Pending"` दिखेगा।

#### 3.2 पूर्ण सुरक्षित Cross-FY Propagation & Snapshot Workflow

```text
[बिल बना या डिलीट हुआ (2026-27 में)]
               │
               ▼
┌─────────────────────────────────────────────────────────────┐
│ 1. Active FY Memory & Disk JSON Status Update                │
│    challan.status = "Billed" (या "Pending"), version++, updatedAt = nowMs │
└─────────────────────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. Cross-FY Local Storage Propagation (App & Web)           │
│    App:  $basePath/{originalFy}/s_challan.json पढ़ो,         │
│          समान ID वाले रिकॉर्ड का स्टेटस बदलो, version++,     │
│          updatedAt = nowMs, और डिस्क पर राइट करो।           │
│    Web:  fyVault[originalFy]['s_challan.json'] में समान ID   │
│          का स्टेटस बदलो, version++, updatedAt = nowMs।       │
│    Intermediate FYs: यदि बीच के किसी FY में वही ID है,       │
│          तो वहाँ भी स्टेटस अपडेट करो।                       │
└─────────────────────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. Atomic Outbox Mutation Dispatch (SyncQueueManager)       │
│    syncId: challan.id, docType: SALE_CHALLAN,               │
│    payload: { ...challan.toMap(), "originalFy": originalFy } │
└─────────────────────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. Unified Cloud Snapshot Push                              │
│    AppRealtimeCoordinator (App) / _uploadSnapshot (Web)     │
│    सक्रिय FY के साथ-साथ संशोधित 'fy_vault.json'             │
│    (जिसमें 2025-26 का s_challan.json अपडेटेड है) को         │
│    Google Drive Snapshot में एक साथ पुश करता है।             │
└─────────────────────────────────────────────────────────────┘
```

**Bill Delete होने पर रिवर्स फ्लो:**  
जब बिल डिलीट होता है, तो ठीक यही प्रक्रिया उल्टी दिशा में चलेगी:
- Active FY में चालान `"Pending"` होगा।
- Original FY (`2025-26`) और सभी Intermediate FYs में वही ID वाला चालान खोजकर उसका स्टेटस वापस `"Pending"` किया जाएगा, `version++` होगा और `updatedAt = nowMs` सेट होगा।
- Cloud Snapshot और Outbox दोनों FYs के अपडेटेड स्टेट को क्लाउड पर भेजेंगे।

---

### बिंदु 4: D1 Event Retrieval और दूसरे FY के Devices

#### 4.1 वर्तमान रिसीविंग फ्लो का वास्तविक ब्रेकडाउन
वर्तमान कोडबेस में D1 एज सिग्नल का रिसीविंग फ्लो इस प्रकार काम करता है:
1. **D1 API Endpoint (`/api/lab_signal`):**  
   जब कोई डिवाइस `fetchSaleDeltasWithCursor(storeToken)` कॉल करता है, तो D1 सर्वर पर क्वेरी चलती है:
   `SELECT * FROM mutations WHERE storeToken = ? AND seq > ? ORDER BY seq ASC`  
   **प्रमाण:** D1 सर्वर FY के आधार पर इवेंट्स को फ़िल्टर नहीं करता; वह उस स्टोर के सभी इवेंट्स अनुक्रमिक रूप से देता है।
2. **App `FastPullEngine.dart` की रुकावट (Lines 179–190):**
   ```dart
   final String evFy = (ev["fy"] ?? (rawPayload is Map ? rawPayload["fy"] : "") ?? "").toString().trim();
   if (evFy.isNotEmpty && evFy != targetFyAtStart) {
     continue; // ❌ App skips events belonging to other FYs!
   }
   ```
   यदि मोबाइल ऐप `2026-27` में खुला है, और वेब ने `2025-26` के किसी चालान का स्टेटस बदला या डिलीट किया, तो `FastPullEngine` उसे `continue;` करके छोड़ देता है! वह ऐप की `2025-26` वाली डिस्क फाइलों को अपडेट नहीं करता।
3. **Challan Event Handler की अनुपस्थिति:**  
   `FastPullEngine.dart` (Lines 140–171) में `applyEventsToLocalSales`, `applyEventsToLocalPurchases`, `applyEdgeEventsToLocalVouchers` आदि मौजूद हैं, लेकिन **`applyEventsToLocalSaleChallans` या `applyEventsToLocalPurchaseChallans` का कोई कॉल नहीं है!** चालान केवल स्नैपशॉट मर्ज के समय अपडेट होते थे।
4. **Bill Save पर Billed करने वाले लॉजिक का अभाव:**  
   `applyEventsToLocalSales` (Line 1090) में जब `INSERT_SALE` आता है, तो वह केवल `localSales` में बिल जोड़ता है। वह `rawSale['linkedChallanIds']` को पढ़कर चालान को `"Billed"` नहीं करता।

#### 4.2 सुरक्षित समाधान (Cross-FY Real-Time Delivery)
1. **`D1SalesLedgerService` में `billLinkedChallansFromSaveEvents` जोड़ना:**  
   जैसे बिल डिलीट पर `revertLinkedChallansFromDeleteEvents` चालान को वापस `"Pending"` करता है, वैसे ही `INSERT` और `UPDATE` इवेंट्स पर `billLinkedChallansFromSaveEvents` चलेगा, जो `linkedChallanIds` वाले चालानों को तुरंत `"Billed"` करेगा।
2. **App `FastPullEngine` में Inactive FY Disk Dispatcher:**  
   जब कोई D1 इवेंट किसी दूसरे FY (`evFy != targetFyAtStart`) का आए और वह चालान या लिंक्ड चालान से संबंधित हो, तो ऐप उसे ड्रॉप करने के बजाय सीधे डिस्क पर स्थित `$basePath/$evFy/s_challan.json` या `p_challan.json` में सुरक्षित रूप से अपडेट करेगा।
3. **Web `_applyEdgeEventsToFyVault` में पूर्णता:**  
   वेब के पास पहले से `fyVault` में सभी FYs हैं; वहाँ `billLinkedChallansFromSaveEvents` चलाकर संबंधित FY के वॉल्ट मैप में चालान को Billed कर दिया जाएगा।

---

### बिंदु 5: LWW, Version और Timestamp की वास्तविक सुरक्षा

#### 5.1 वर्तमान कोड में पाई गई गंभीर विसंगति (Audit of Existing Flaws)
वर्तमान `lib/sync_core/modules/sale_challan_sync_module.dart` (Line 71) और `purchase_challan_sync_module.dart` (Line 103) में निम्न कोड है:
```dart
if (incoming.version <= local.version && incoming.updatedAt < local.updatedAt) {
  return false;
}
currentChallans[idx] = incoming;
```
**गंभीर जोखिम:**  
यदि किसी डिवाइस की घड़ी 5 मिनट आगे है (`incoming.updatedAt > local.updatedAt`), लेकिन उसका वर्जन पुराना है (`incoming.version = 1` जबकि `local.version = 3`):
यहाँ `incoming.updatedAt < local.updatedAt` शर्त **FALSE** हो जाएगी। इसके कारण `return false;` नहीं चलेगा और **Line 74 पर पुराना Version 1 नए Version 3 को ओवरराइट कर देगा!**

#### 5.2 एकसमान व अटल Conflict Resolution Rule (Monotonic Version + LWW Tie-Breaker)
सभी मॉड्यूल (`SaleChallanSyncModule`, `PurchaseChallanSyncModule`, `DeltaMergeEngine`, `MultiFyCloudVault`, `D1SalesLedgerService`) के लिए नियम बिल्कुल स्पष्ट और सख्त होना चाहिए:

$$\text{Winner} = \begin{cases} 
\text{Incoming}, & \text{if } V_{\text{inc}} > V_{\text{loc}} \\
\text{Local}, & \text{if } V_{\text{inc}} < V_{\text{loc}} \\
\text{Incoming}, & \text{if } V_{\text{inc}} == V_{\text{loc}} \text{ and } T_{\text{inc}} > T_{\text{loc}} \\
\text{Local}, & \text{if } V_{\text{inc}} == V_{\text{loc}} \text{ and } T_{\text{inc}} < T_{\text{loc}} \\
\text{Incoming (Convergence)}, & \text{if } V_{\text{inc}} == V_{\text{loc}} \text{ and } T_{\text{inc}} == T_{\text{loc}}
\end{cases}$$

**कोड कार्यान्वयन:**
```dart
bool shouldIncomingWin({
  required int incVer,
  required int incTs,
  required int locVer,
  required int locTs,
}) {
  if (incVer > locVer) return true;
  if (incVer < locVer) return false;
  // Versions are equal: use timestamp as tie-breaker
  if (incTs > locTs) return true;
  if (incTs < locTs) return false;
  // Absolute tie: incoming wins to ensure deterministic cluster convergence
  return true;
}
```
**किनारों की परिस्थितियाँ (Edge Cases Verified):**
- **कम Version लेकिन अधिक Timestamp:** लोकल सुरक्षित रहेगा (इवेंट रिजेक्ट होगा)।
- **अधिक Version लेकिन कम Timestamp:** इनकमिंग जीतेगा (मोनोटोनिक वर्जन की सर्वोच्च प्राथमिकता)।
- **अलग डिवाइस घड़ियाँ (Clock Skew):** मोनोटोनिक वर्जन होने के कारण क्लॉक स्क्यू डेटा को दूषित नहीं कर सकता।
- **Re-Bill के बाद पुराना Delete Event आना:** जब बिल दोबारा बनता है, तो चालान का वर्जन बढ़ जाता है (`v3`). पुराने डिलीट इवेंट का वर्जन कम (`v2`) होने के कारण वह स्वतः रिजेक्ट हो जाएगा।

---

### बिंदु 6: Status Propagation केवल Existing Verified Copies पर

#### 6.1 सुरक्षा शर्तें (Safety Invariants)
Cross-FY स्टेटस प्रोपेगेशन हेल्पर (`propagateChallanStatusAcrossFys`) बनाते समय निम्न 5 नियमों का पालन अनिवार्य है:

1. **Zero New Record Creation (शून्य नई प्रविष्टि):**
   - यदि किसी FY (जैसे `2024-25` या `2025-26`) में उस विशिष्ट चालान की प्रति मौजूद नहीं है, तो केवल स्टेटस बदलने के नाम पर वहाँ कोई नया चालान इन्सर्ट नहीं किया जाएगा। केवल `indexWhere((c) => c.id == targetId) != -1` मिलने पर ही अपडेट होगा।
2. **Immutable ID Matching Only (केवल स्थायी ID मैच):**
   - स्टेटस प्रोपेगेशन में कभी भी `billNo` या `internalNo` के आधार पर खोज नहीं होगी। खोज केवल और केवल `c.id.trim() == targetId.trim()` से होगी।
3. **No Cross-Series Pollution (नंबर टकराव से सुरक्षा):**
   - यदि `2026-27` में एक नया चालान `Y-1` है (ID: `UUID-2026`) और `2025-26` में पुराना चालान `Y-1` है (ID: `UUID-2025`), तो `UUID-2026` का स्टेटस बदलने पर `UUID-2025` को कभी छुआ नहीं जाएगा।
4. **Anti-Resurrection Guard (टॉम्बस्टोन सुरक्षा):**
   - यदि किसी FY में वह रिकॉर्ड पहले से डिलीटेड है (`isDeleted == 1` या टॉम्बस्टोन रजिस्ट्री में दर्ज है), तो स्टेटस प्रोपेगेशन उसे कभी पुनर्जीवित (`un-delete`) नहीं करेगा।
5. **Multi-Year Carry-Forward Preservation (कैरी-फॉरवर्ड की स्वतंत्रता):**
   - `FYTransferEngine` का वार्षिक कैरी-फॉरवर्ड फ्लो केवल पेंडिंग चालानों को नए साल में कॉपी करने के लिए समर्पित रहेगा और इस स्टेटस सिंक से पूरी तरह स्वतंत्र रहेगा।

---

## भाग 2 — FINAL VERIFIED ROOT CAUSE (वास्तविक समस्याएँ)

वर्तमान कोड की गहन जाँच के बाद कुल 6 वास्तविक और प्रमाणित मूल कारण पाए गए हैं:

1. **Root Cause 1: Challan Models में Stored `originalFy` का अभाव**
   - `SaleChallan` और `PurchaseChallan` में `originalFy` फ़ील्ड केवल रनटाइम पर `date` से निकाला जाता था। जब नए FY में डेट पिकर खुलता है, तो वह तारीख को नए FY में क्लैंप कर देता है, जिससे पुराने चालान की वित्तीय पहचान बदल जाती है।
2. **Root Cause 2: DeltaMergeEngine & Web Parsing में Secondary Key Collision**
   - `DeltaMergeEngine.dart:253` में `uniqueByBillNo[bNo]` केवल `billNo` को चाबी बनाता है।
   - `pharoah_web_manager.dart:1069` में `masterSChMap` केवल `c.billNo` को चाबी बनाता है।
   - इसके कारण पुराने साल से आया `Y-1` और नए साल का अपना `Y-1` आपस में टकरा जाते हैं और एक दूसरे को मिटा देते हैं।
3. **Root Cause 3: Distinct Non-Empty IDs पर गलत मैचिंग**
   - `MultiFyCloudVault.dart:288` और `SaleChallanSyncModule.dart:80` में यदि दो रिकॉर्ड्स की UUID अलग-अलग हो, तब भी समान `billNo` मिलने पर पुराने रिकॉर्ड को नए से बदल दिया जाता है।
4. **Root Cause 4: Bill Conversion पर Original FY Copy का अन-अपडेटेड रहना**
   - सभी 6 बिल कन्वर्जन पाथ्स केवल सक्रिय FY के चालान को `"Billed"` करते हैं। डिस्क या वॉल्ट में रखे मूल FY के चालान का स्टेटस `"Pending"` ही रह जाता है।
5. **Root Cause 5: Real-Time Edge Signal में Challan Handler और Cross-FY Routing का अभाव**
   - `FastPullEngine.dart` में D1 एज इवेंट्स से चालान को प्रोसेस करने का कोई डायरेक्ट हैंडलर नहीं था, और दूसरे FY के इवेंट्स को सीधे `continue;` करके छोड़ दिया जाता था।
   - `D1SalesLedgerService` बिल सेव होने पर `linkedChallanIds` को `"Billed"` करने का हैंडलर नहीं चलाता था।
6. **Root Cause 6: Sync Modules में Flawed LWW Condition**
   - `SaleChallanSyncModule` और `PurchaseChallanSyncModule` में `incoming.version <= local.version && incoming.updatedAt < local.updatedAt` लिखा था, जिससे क्लॉक स्क्यू होने पर कम वर्जन वाला रिकॉर्ड अधिक वर्जन वाले रिकॉर्ड को ओवरराइट कर सकता था।

---

## भाग 3 — FINAL UNIFIED IMPLEMENTATION PLAN (कार्यान्वयन योजना)

कार्यान्वयन को 5 सुनियोजित और सुरक्षित चरणों में बाँटा गया है। प्रत्येक चरण में केवल वही फाइलें और मेथड्स बदले जाएँगे जो आवश्यक हैं:

```text
┌────────────────────────────────────────────────────────────────────────┐
│ Phase 1: Data Models & Immutability Foundation                         │
│ Files: lib/models.dart, lib/web_live_sync/web_models.dart              │
│ Task:  originalFy stored field, toMap/fromMap serialization            │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │
┌────────────────────────────────────▼───────────────────────────────────┐
│ Phase 2: Strict Primary ID Matching & Deduplication                    │
│ Files: lib/sync_core/multi_fy_cloud_vault.dart,                        │
│        lib/web_live_sync/sync_protocol/delta_merge_engine.dart,        │
│        lib/web_live_sync/pharoah_web_manager.dart                      │
│ Task:  Rule 1 enforcement, composite dedup key (effectiveFy::billNo)   │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │
┌────────────────────────────────────▼───────────────────────────────────┐
│ Phase 3: Monotonic Version & LWW Clock Auditing Fix                    │
│ Files: lib/sync_core/modules/sale_challan_sync_module.dart,            │
│        lib/sync_core/modules/purchase_challan_sync_module.dart         │
│ Task:  Strict Version > LocalVer, TS tie-breaker formula               │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │
┌────────────────────────────────────▼───────────────────────────────────┐
│ Phase 4: Cross-FY Status Propagation & 6 Conversion Paths              │
│ Files: lib/pharoah_manager.dart,                                       │
│        lib/web_live_sync/pharoah_web_manager.dart,                     │
│        lib/challans/challan_to_bill_converter.dart                     │
│ Task:  propagateChallanStatus across disk folders & fyVault,           │
│        fix version++ and SyncQueueManager enqueue in all 6 paths       │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │
┌────────────────────────────────────▼───────────────────────────────────┐
│ Phase 5: Real-Time Edge Signaling & Inactive FY Delivery               │
│ Files: lib/sync_core/d1_sales_ledger_service.dart,                     │
│        lib/realtime_signaling/engines/fast_pull_engine.dart            │
│ Task:  billLinkedChallansFromSaveEvents, cross-FY disk file update     │
└────────────────────────────────────────────────────────────────────────┘
```

---

### चरण 1: Data Models & Immutability Foundation

#### 1. `lib/models.dart` & `lib/web_live_sync/web_models.dart`
- **संशोधन:**
  - `SaleChallan` क्लास में `String originalFy;` फ़ील्ड जोड़ें (डिफ़ॉल्ट `""`)।
  - `PurchaseChallan` क्लास में `String originalFy;` फ़ील्ड जोड़ें (डिफ़ॉल्ट `""`)।
  - `effectiveOriginalFy` गैटर:
    ```dart
    String get effectiveOriginalFy {
      if (originalFy.trim().isNotEmpty) return originalFy.trim();
      if (date.trim().isNotEmpty) {
        final fy = AppDateLogic.getFYForDate(date);
        if (fy.isNotEmpty) return fy;
      }
      return "";
    }
    ```
  - `toMap()` में `'originalFy': effectiveOriginalFy` शामिल करें।
  - `fromMap()` में:
    ```dart
    originalFy: (map['originalFy'] ?? map['original_fy'] ?? '').toString().trim(),
    ```
    यदि `originalFy` खाली हो, तो `date` से निकालें।

---

### चरण 2: Strict Primary ID Matching & Deduplication

#### 1. `lib/sync_core/multi_fy_cloud_vault.dart`
- **Method:** `_findMatchingRecordIndex`
- **बदलाव:**
  - Lines 286–297 के दोषपूर्ण ब्लॉक को हटाकर सख्त नियम लागू करें:
    ```dart
    if (candId.isNotEmpty && exId.isNotEmpty) {
      if (candId == exId) return i;
      // IDs are distinct: NEVER match, continue searching!
      continue;
    }
    ```
  - जब किसी एक तरफ ID खाली हो (Legacy fallback), तो `originalFy` की तुलना अनिवार्य करें।

#### 2. `lib/web_live_sync/sync_protocol/delta_merge_engine.dart`
- **Method:** `mergeList<T>` (Lines 203–210 & 253–277)
- **बदलाव:**
  - `localList.indexWhere` में: यदि `getId(e).isNotEmpty && id.isNotEmpty`, तो केवल और केवल `getId(e) == id` पर ही मैच होगा।
  - `uniqueByBillNo` की डिडप्लीकेशन चाबी को FY-अवेयर बनाएँ:
    ```dart
    final String fyScope = (item is SaleChallan)
        ? item.effectiveOriginalFy
        : ((item is PurchaseChallan) ? item.effectiveOriginalFy : activeFy);
    String dedupKey = itemId.isNotEmpty
        ? "ID:$itemId"
        : (bNo.isNotEmpty ? "$fyScope::$bNo" : "");
    ```

#### 3. `lib/web_live_sync/pharoah_web_manager.dart`
- **Methods:** `_parseDownloadedFiles` (Lines 1056–1076 & 1120–1140)
- **बदलाव:**
  - `indexWhere` में अलग-अलग गैर-खाली ID होने पर मैचिंग ब्लॉक करें।
  - `masterSChMap` की चाबी:
    ```dart
    String key = c.id.trim().isNotEmpty
        ? c.id.trim()
        : "${c.effectiveOriginalFy}::${c.billNo.trim().toUpperCase()}";
    ```

---

### चरण 3: Monotonic Version & LWW Clock Auditing Fix

#### 1. `lib/sync_core/modules/sale_challan_sync_module.dart`
- **Method:** `applySaleChallanMutation`
- **बदलाव:**
  - Line 71 की दोषपूर्ण शर्त को बदलें:
    ```dart
    if (idx > -1) {
      final local = currentChallans[idx];
      // 🛡️ Strict Monotonic Versioning + LWW Tie-breaker
      if (incoming.version < local.version) return false;
      if (incoming.version == local.version && incoming.updatedAt < local.updatedAt) return false;
      currentChallans[idx] = incoming;
      return true;
    }
    ```
  - Lines 77–87 में: यदि `incoming.id.isNotEmpty`, तो किसी अलग ID वाले रिकॉर्ड को केवल `billNo` मिलने पर कभी ओवरराइट न करें।

#### 2. `lib/sync_core/modules/purchase_challan_sync_module.dart`
- **Method:** `applyPurchaseChallanMutation`
- **बदलाव:**
  - Line 103 में वही सख्त वर्जन और टाइमस्टैम्प फॉर्मूला लागू करें।

---

### चरण 4: Cross-FY Status Propagation & 6 Conversion Paths

#### 1. `lib/pharoah_manager.dart` (App Side)
- **New Method:** `Future<void> propagateChallanStatusAcrossDiskFolders({...})`
  ```dart
  Future<void> propagateChallanStatusAcrossDiskFolders({
    required String challanId,
    required String newStatus,
    required String originalFy,
    required bool isPurchase,
    int? customVersion,
    int? customUpdatedAt,
  }) async {
    if (activeCompany == null || challanId.trim().isEmpty) return;
    final root = await getApplicationDocumentsDirectory();
    final basePath = '${root.path}/Pharoah_Data/${activeCompany!.id}/${activeCompany!.businessType}';
    final fileName = isPurchase ? 'p_challan.json' : 's_challan.json';
    final nowMs = customUpdatedAt ?? DateTime.now().millisecondsSinceEpoch;

    for (final fy in activeCompany!.fYears) {
      if (fy == currentFY) continue; // Active FY is handled in-memory
      final file = File('$basePath/$fy/$fileName');
      if (!file.existsSync()) continue;
      try {
        final raw = jsonDecode(file.readAsStringSync());
        if (raw is! List) continue;
        bool modified = false;
        final updatedList = raw.map((item) {
          if (item is Map && (item['id'] ?? '').toString().trim() == challanId.trim()) {
            if ((item['isDeleted'] ?? 0) != 1) {
              item['status'] = newStatus;
              item['version'] = (item['version'] ?? 1) + 1;
              item['updatedAt'] = nowMs;
              modified = true;
            }
          }
          return item;
        }).toList();
        if (modified) {
          await file.writeAsString(jsonEncode(updatedList));
          debugPrint("✅ [App Cross-FY] Updated challan $challanId to $newStatus in $fy");
        }
      } catch (e) {
        debugPrint("⚠ [App Cross-FY Error] $fy: $e");
      }
    }
  }
  ```
- **Call Sites Integration:**
  - `finalizeSale`: जब लिंक्ड चालान Billed होता है, तो `propagateChallanStatusAcrossDiskFolders` को कॉल करें।
  - `deleteBill`: जब बिल डिलीट होता है, तो लिंक्ड चालानों को वापस `"Pending"` करने के लिए इसे कॉल करें।
  - `finalizePurchase` और `deletePurchase` में भी यही लागू करें।
  - `lib/challans/challan_to_bill_converter.dart:238`: `finalizeSale` से पहले चालान का स्टेटस प्री-मैच्योरली `"Billed"` करने वाली लाइन को हटाएँ ताकि `finalizeSale` के अंदर `version++` और `onSaleChallanSaved` सही ढंग से चल सकें।

#### 2. `lib/web_live_sync/pharoah_web_manager.dart` (Web Side)
- **New Method:** `void propagateChallanStatusAcrossVault({...})`
  - `fyVault` के सभी गैर-सक्रिय वित्तीय वर्षों में उसी `id` वाले चालान को खोजकर स्टेटस अपडेट करें।
- **Call Sites Integration:**
  - `addSaleAndSync`, `deleteSale`, `addPurchaseAndSync`, `deletePurchase`, और `WebChallanStitcherWizard` में इसे कॉल करें।

---

### चरण 5: Real-Time Edge Signaling & Inactive FY Delivery

#### 1. `lib/sync_core/d1_sales_ledger_service.dart`
- **New Method:** `billLinkedChallansFromSaveEvents`
  - यह मेथड इनकमिंग `INSERT_SALE` और `UPDATE_SALE` इवेंट्स से `linkedChallanIds` और `items.sourceChallanId` निकालकर सक्रिय व निष्क्रिय FY के चालानों को तुरंत `"Billed"` मार्क करेगा, `version++` करेगा और LWW टाइमस्टैम्प सेट करेगा।

#### 2. `lib/realtime_signaling/engines/fast_pull_engine.dart`
- **संशोधन:**
  - Lines 140–165 में `billLinkedChallansFromSaveEvents` को कॉल करें।
  - D1 इवेंट्स में यदि कोई चालान इवेंट किसी दूसरे FY (`evFy != targetFyAtStart`) का हो, तो उसे ड्रॉप करने के बजाय सीधे उस FY की डिस्क फाइल में सेव करें।

---

## भाग 4 — FINAL SAFETY & TEST MATRIX

### 1. अनिवार्य कंपाइलेशन व लिंटिंग सत्यापन
कार्यान्वयन के बाद दोनों प्लेटफ़ॉर्म्स पर शून्य त्रुटि (Zero Errors/Warnings) प्रमाणित की जाएगी:
- `compile_applet` & `lint_applet` $\rightarrow$ Clean build with 0 errors.
- Web TypeScript / Vite build $\rightarrow$ Clean pass.

### 2. रीग्रेशन टेस्ट परिदृश्य (Regression Test Scenarios)

| परिदृश्य संख्या | परीक्षण का नाम | क्रियान्वयन विवरण | अपेक्षित सफल परिणाम |
| :--- | :--- | :--- | :--- |
| **TEST-01** | **New FY Numbering Isolation** | FY 2025-26 में चालान `Y-1` (Pending) बनाएँ। FY 2026-27 में जाएँ। नया चालान बनाएँ। | 2026-27 के नए चालान का नंबर **`Y-1`** ही बनेगा। वह `Y-2` नहीं बनेगा। दोनों चालान लिस्ट में अलग-अलग UUID के साथ सुरक्षित दिखेंगे। |
| **TEST-02** | **App Bill Conversion $\rightarrow$ Web Live Sync** | App पर 2026-27 में पुराने चालान `Y-1` का बिल बनाएँ। Web पर लाइव देखें। | Web पर 2026-27 में चालान तुरंत **"Billed"** दिखेगा। Web पर 2025-26 में स्विच करने पर भी वह **"Billed"** दिखेगा। |
| **TEST-03** | **Web Stitcher Conversion $\rightarrow$ App Live Sync** | Web पर 2026-27 में चालानों का स्टिचर चलाकर बिल बनाएँ। App पर लाइव देखें। | App पर 2026-27 और 2025-26 दोनों वर्षों में चालान तुरंत **"Billed"** दिखेंगे (Pending नहीं रहेंगे)। |
| **TEST-04** | **Bill Deletion Reversion** | बने हुए बिल को डिलीट करें। | App और Web दोनों पर 2026-27 और 2025-26 दोनों वर्षों में चालान वापस **"Pending"** हो जाएँगे। कोई भी रिकॉर्ड डिलीट या करप्ट नहीं होगा। |
| **TEST-05** | **Carry-Forward Challan Date Edit** | 2026-27 में Carry-Forward चालान की डेट बदलें। | उसका `originalFy` अपरिवर्तित (`2025-26`) रहेगा। वह 2026-27 की नंबरिंग को प्रभावित नहीं करेगा। |
| **TEST-06** | **Out-of-Order / Skewed Clock Sync** | कम वर्जन लेकिन अधिक टाइमस्टैम्प वाला पुराना इवेंट भेजें। | मोनोटोनिक वर्जन सुरक्षा के कारण पुराना इवेंट रिजेक्ट हो जाएगा और नया डेटा सुरक्षित रहेगा। |
| **TEST-07** | **Zero Creation Safety** | किसी ऐसे FY में स्टेटस प्रोपेगेट करें जहाँ वह चालान कभी था ही नहीं। | उस FY में कोई नया अवांछित रिकॉर्ड नहीं बनेगा। |
| **TEST-08** | **Existing Business Workflows Safety** | Sale, Purchase, Inventory, Batch Expiry, Party Ledgers, Opening Balances चलाएँ। | किसी भी पूर्व-मौजूद अकाउंटिंग या इन्वेंट्री लॉजिक में कोई बदलाव या गिरावट नहीं होगी। |

---

## निष्कर्ष व अंतिम तैयारी
उपरोक्त सभी 6 बिंदुओं का स्वतंत्र, स्रोत-कोड-आधारित सत्यापन पूरा हो चुका है। प्रत्येक समस्या का मूल कारण स्पष्ट है, और समाधान का एक-एक चरण पूरी तरह से मैप किया जा चुका है।

**आपकी स्पष्ट अनुमति मिलते ही हम इस योजना के अनुसार बिना किसी अतिरिक्त प्रश्न के सीधा Implementation शुरू करेंगे।**
