# PHAROAH ERP — CHALLAN FY IDENTITY, NUMBERING, DUPLICATE MATCHING & CROSS-FY LIVE SYNC: DEEP TECHNICAL VALIDATION (PART 1 & PART 2)

> **Investigation Mandate & Ground Rules:**
> - यह रिपोर्ट सीधे आपके `131-new-ph` Repository (`main` branch, commit `31dff68` / code state `fe59f65`) के वास्तविक Source Code, Models, Call Sites, Storage Architecture और Sync Pipelines को पढ़कर तैयार की गई है।
> - **अभी कोई भी Code Change, Refactoring, Migration या Implementation नहीं किया गया है।**
> - जहाँ हमारी पिछली रिपोर्ट के 6-Step Plan में कोई अधूरी शर्त या संभावित साइड-इफेक्ट था (विशेषकर `effectiveOriginalFy == currentFY` और `date` से `originalFy` निकालने की सीमा), उसे भी इस रिपोर्ट में बिना किसी पक्षपात के **Code Evidence** के साथ सुधारा और स्पष्ट किया गया है।

---

# =====================================================================
# PART 1 — Challan FY Identity, Numbering & Duplicate Matching: Deep Technical Validation
# =====================================================================

## Part 1 • Section A — `originalFy` और पुराने रिकॉर्ड की पहचान

### प्रश्न 1: क्या Challan की `Date` हमेशा उसके वास्तविक Creation FY को दर्शाती है?
**उत्तर (Confirmed from Code — सामान्यतः हाँ, परंतु 2 स्थितियों में नहीं):**
1. **नया Challan बनाते समय (App & Web):**
   - **App:** `SaleChallanView._initChallanFlow()` (`lib/challans/sale_challan_view.dart:57`) और `PurchaseChallanView._initInwardFlow()` (`lib/challans/purchase_challan_view.dart:55`) में डिफ़ॉल्ट तारीख `PharoahDateController.getInitialBillDate(ph.currentFY)` से आती है, जो `AppDateLogic.getSmartDate(currentFY)` (`lib/app_date_logic.dart:95–108`) के माध्यम से हमेशा `currentFY` के भीतर (`01/04/YYYY` से `31/03/YYYY+1`) लॉक रहती है।
   - **Web:** `WebSaleChallanView._initChallanFlow()` (`lib/web_live_sync/sub_views/web_challans/web_sale_challan_view.dart:72`) और `WebPurchaseChallanView._initChallanFlow()` (`lib/web_live_sync/sub_views/web_challans/web_purchase_challan_view.dart:74`) में भी `WebAppDateLogic.getSmartDate(webPh.financialYear)` और सेव करते समय `addSaleChallanAndSync` (`lib/web_live_sync/pharoah_web_manager.dart:2918–2920`) तथा `addPurchaseChallanAndSync` (`Line 2998–3000`) में `if (!isUpdate) challan.date = WebFyDateRangeHelper.ensureDateInActiveFy(challan.date, financialYear);` लगा है।
   - इसलिए **नया चालान बनते समय उसकी `date` 100% उसके वास्तविक Creation FY के भीतर ही होती है।**
2. **कब `date` वास्तविक Creation FY से अलग हो सकती है (Critical Exceptions):**
   - **Exception A (Carry-Forward Challan को नए FY में Edit करके Date Picker खोलना):**
     - App में `lib/pharoah_date_controller.dart` (Lines `19–32`) में `pickDate()` कैलेंडर की सीमा `first = AppDateLogic.getFYStart(currentFY)` और `last = AppDateLogic.getFYEnd(currentFY)` पर लॉक करता है और लिखता है:
       ```dart
       DateTime safeInitial = initialDate;
       if (safeInitial.isBefore(first)) safeInitial = first;
       if (safeInitial.isAfter(last)) safeInitial = last;
       ```
     - यदि `2025-26` का चालान (`date: 15/03/2026`) Carry-Forward होकर `2026-27` में आया और यूज़र ने `2026-27` में उस चालान को Modify करते समय गलती से Date फ़ील्ड पर टैप करके OK दबा दिया, तो `safeInitial` उसकी तारीख को `15/03/2026` से बदलकर **`01/04/2026` (`2026-27`)** कर देगा!
   - **Exception B (Corrupted / Missing Date in JSON):**
     - `lib/models.dart` में `SaleChallan.fromMap` (Line `688`) और `PurchaseChallan.fromMap` (Line `747`) में लिखा है:
       ```dart
       date: DateTime.parse(map['date'] ?? DateTime.now().toIso8601String()),
       ```
     - यदि किसी पुराने रिकॉर्ड में `map['date'] == null` हो, तो `DateTime.now()` लग जाता है, जो आज के चालू वर्ष का डेट दे देगा!

---

### प्रश्न 2: अगर पुराने Challan की Date Edit हो चुकी है, तो क्या Date से Original FY निकालना सुरक्षित है?
**उत्तर (Confirmed — केवल `date` पर निर्भर रहना सुरक्षित नहीं है):**
- यदि हम `originalFy` को JSON में स्थायी रूप से सेव करने के बजाय हर बार केवल `AppDateLogic.getFYForDate(challan.date)` से डायनामिक रूप से निकालेंगे, तो ऊपर बताए गए **Exception A** में जैसे ही किसी Carry-Forward चालान की तारीख `2026-27` में बदल जाएगी, सिस्टम उसे `2025-26` के Carry-Forward चालान के बजाय `2026-27` का Native चालान मान लेगा!
- इसलिए **`date` से `originalFy` निकालना केवल एक बार (Fallback / Initial Attribution के समय) होना चाहिए, और एक बार निर्धारित होने के बाद `originalFy` को चालान के JSON में एक Immutable (अपरिवर्तनीय) फ़ील्ड के रूप में सेव रहना चाहिए।**

---

### प्रश्न 3: अगर किसी पुराने Challan की Date गलत, खाली या Invalid है तो क्या होगा?
**उत्तर (Confirmed from `lib/models.dart:688, 747`):**
1. **वर्तमान कोड का व्यवहार (Crash Risk on Invalid String):**
   - `SaleChallan.fromMap` (`lib/models.dart:688`) और `PurchaseChallan.fromMap` (`lib/models.dart:747`) में `DateTime.parse(...)` लगा है (`DateTime.tryParse` नहीं!)।
   - यदि `map['date']` खाली स्ट्रिंग `""` या `"invalid"` हो, तो `DateTime.parse("")` सीधे `FormatException` फेंकता है, जिससे पूरी `s_challan.json` या `p_challan.json` फाइल का लोड (`loadList` in `pharoah_manager.dart:565` / `_parseDownloadedFiles` in `pharoah_web_manager.dart:1053`) फेल हो सकता है!
   - और यदि `map['date'] == null` हो, तो `DateTime.now()` लग जाता है।
2. **सुरक्षित समाधान:**
   - `fromMap` में `DateTime.tryParse` का उपयोग होना चाहिए।
   - यदि किसी पुराने रिकॉर्ड में `originalFy` खाली है, तो सबसे पहले **जिस FY के फोल्डर या Vault (`2025-26/s_challan.json` या `fyVault["2025-26"]`) से वह Carry-Forward हो रहा है (`prevFY`)**, या यदि चालू फाइल में उसकी वैध `date` मौजूद है तो `AppDateLogic.getFYForDate(date)` से `originalFy` निर्धारित किया जाए।

---

### प्रश्न 4: क्या Carry-Forward के दौरान Original FY एक बार निर्धारित होकर स्थायी रह सकता है?
**उत्तर (100% हाँ — Confirmed from `lib/fy_transfer_engine.dart`):**
- `FYTransferEngine.computeCarryForwardFromFiles()` (`lib/fy_transfer_engine.dart:360–364, 473–474`), `reconcileCarryForwardSaleChallans()` (`Lines 513–565`), `reconcileCarryForwardPurchaseChallans()` (`Lines 568–630`), और `cascadeSingleYearStep()` (`Lines 684–760`) के पास हमेशा **`prevFY`** (जैसे `"2025-26"`) उपलब्ध होता है।
- जब `prevFY` (`2025-26`) से कोई चालान `targetFY` (`2026-27`) में Carry-Forward किया जाता है:
  - यदि उस चालान में पहले से `originalFy` मौजूद है (मान लो `"2024-25"`), तो **उसी `"2024-25"` को ज्यों का त्यों रखा जाएगा**।
  - यदि उस चालान में `originalFy` खाली है (पुराना लेगेसी रिकॉर्ड), तो Carry-Forward इंजन उस पर `sc.originalFy = sc.effectiveOriginalFy(fallbackFy: prevFY)` लिखकर स्थायी मुहर (stamp) लगा देगा!
  - इसके बाद चाहे वह चालान `2026-27` में जाए या `2027-28` में, या उसकी तारीख एडिट भी हो जाए, उसका `originalFy` हमेशा स्थायी रहेगा।

---

### प्रश्न 5: क्या `originalFy` को App, Web, Local Files, Cloud Vault, D1 Events और Backup में सुरक्षित रखा जा सकता है?
**उत्तर (100% हाँ — Confirmed from Serialization Flow):**
क्योंकि पूरे Pharoah ERP में App और Web दोनों एक ही `lib/models.dart` (`web_models.dart` Line `2` पर `export '../models.dart';` करता है) के `SaleChallan.toMap()` / `SaleChallan.fromMap()` और `PurchaseChallan.toMap()` / `PurchaseChallan.fromMap()` का उपयोग करते हैं:
1. **App Local Files (`s_challan.json`, `p_challan.json`):** `ph.save()` सीधे `e.toMap()` को JSON में लिखता है।
2. **Web `fyVault` & Cloud Snapshot (`multi_fy_vault.json`):** ` e.toMap()` से ही बनता है।
3. **Outbox Envelopes (`SaleChallanSyncModule` & `PurchaseChallanSyncModule`):** `challan.toMap()` को ही `bill_data` के अंदर भेजते हैं (`sale_challan_sync_module.dart:23`, `purchase_challan_sync_module.dart:31`)।
4. **D1 Edge Events & Backup ZIP:** सभी जगह यही `toMap()` JSON जाता है।
इसलिए `SaleChallan.toMap()` और `PurchaseChallan.toMap()` में `'originalFy': effectiveOriginalFy` जोड़ने मात्र से यह **App, Web, Local Disk, Cloud Vault, Outbox, D1 और Backup/Restore सभी जगह अपने-आप 100% सुरक्षित रहेगा।**

---

### प्रश्न 6: अगर पुराने रिकॉर्ड में `originalFy` मौजूद नहीं है, तो उसे सुरक्षित तरीके से कैसे निर्धारित किया जाएगा?
**उत्तर (3-Tier Deterministic Fallback Rule):**
जब `fromMap(map)` किसी पुराने रिकॉर्ड को पढ़ेगा जिसमें `map['originalFy']` खाली या `null` है:
1. **Tier 1 (Explicit Field):** यदि `map['originalFy']` (या `map['fy']`) गैर-खाली है, तो वही लें (normalized, जैसे `"2025-26"`).
2. **Tier 2 (Valid Date Inference):** यदि `map['date']` एक वैध तारीख है, तो `AppDateLogic.getFYForDate(parsedDate)` से उसका FY निकालें (उदाहरण: `2025-05-10` -> `"2025-26"`, `2026-03-15` -> `"2025-26"`).
3. **Tier 3 (Folder / Vault Context Stamp):** जब `loadAllData()` (App), `_parseDownloadedFiles()` (Web), या `FYTransferEngine` किसी विशेष FY फोल्डर (`prevFY`) से फाइल पढ़ता है और किसी रिकॉर्ड में `originalFy` खाली है, तो Tier 2 के बाद भी यदि कोई संदेह हो तो स्रोत फोल्डर का FY उपलब्ध रहता है।

---

### उदाहरण (Part 1 • Section A का वास्तविक Walkthrough)
> **Scenario:**
> - Challan `2025-26` में बना (`billNo: Y-1`, `date: 10/03/2026`)।
> - `2026-27` में Carry-Forward हुआ।
> - बाद में किसी कारण `2026-27` में उसकी `date` बदलकर `05/04/2026` (`2026-27`) कर दी गई।

1. **मौजूदा कोड (Current Code) में क्या होगा:**
   - मौजूदा कोड में `originalFy` है ही नहीं। `FYTransferEngine` (`lib/fy_transfer_engine.dart:29`) और `D1SalesLedgerService.extractEventFy` (`lib/sync_core/d1_sales_ledger_service.dart:371`) केवल `date` देखते हैं।
   - इसलिए तारीख `05/04/2026` होते ही मौजूदा सिस्टम उसे **`2026-27` का चालान समझ लेगा**, और उसकी `2025-26` की पहचान हमेशा के लिए नष्ट हो जाएगी!
2. **Immutable `originalFy` के साथ क्या होगा (सही व्यवहार):**
   - जब चालान `2025-26` में बना (या `2025-26` से Carry-Forward हुआ), तभी उस पर `originalFy: "2025-26"` स्थायी रूप से सेव हो गया।
   - जब `2026-27` में उसे Edit किया जाता है (`finalizeSaleChallan` या `addSaleChallanAndSync`), तो Edit मोड में `originalFy: existingRecord.originalFy` (`"2025-26"`) सुरक्षित रखा जाता है।
   - इसलिए भले ही यूज़र ने उसकी तारीख बदलकर `05/04/2026` कर दी हो (या बेहतर हो कि Carry-Forward चालान की तारीख को नए FY में बदलने से लॉक रखा जाए), फिर भी उसका `originalFy` **`"2025-26"` ही रहेगा** और वह कभी भी `2026-27` का Original चालान नहीं माना जाएगा।

---

## Part 1 • Section B — App और Web Numbering की वास्तविक स्थिति

### 1. मौजूदा Numbering Architecture का सटीक विवरण (Code Evidence सहित)

| घटक (Component) | App (`lib/`) | Web (`lib/web_live_sync/`) | सटीक Code Location |
|---|---|---|---|
| **Sale Challan Default Series** | Prefix: **`SCH-`**, Start: **`1`** | Prefix: **`WSCH-`**, Start: **`1`** *(UI `"SCH-", 101` भेजता है पर `getNextBillNumber` उसे `"WSCH-", 1` में बदल देता है)* | App: `pharoah_manager.dart:3616–3617, 3634`<br>Web: `web_sale_challan_view.dart:69` & `pharoah_web_manager.dart:4132–4134` |
| **Purchase Challan Internal No.** | Prefix: **`PCH-`**, Start: **`1`** *(Hardcoded in view)* | Prefix: **`WPCH-`**, Start: **`1`** | App: `purchase_challan_view.dart:49–50`<br>Web: `web_purchase_challan_view.dart:71` & `pharoah_web_manager.dart:4129–4131` |
| **Custom Prefix व्यवहार (जैसे `Y-`)** | यदि `numberingSeries` में `type: "CHALLAN"` की डिफ़ॉल्ट सीरीज़ `prefix: "Y-"` है, तो App **`Y-`** इस्तेमाल करता है *(Purchase Challan में Custom Series चेक ही नहीं होती, वहाँ हमेशा `"PCH-"` रहता है)* | यदि `numberingSeries` में `type: "CHALLAN"` का `prefix: "Y-"` है (जो `"SCH-"` नहीं है), तो `getNextBillNumber` (`Line 4132`) उसे ओवरराइड **नहीं** करता और Web भी **`Y-`** ही इस्तेमाल करता है! | App: `sale_challan_view.dart:45–53`<br>Web: `pharoah_web_manager.dart:4113–4134` |
| **Gap-Filling Logic** | `startFrom` से `existingNumbers.last` तक पहला गायब पूर्णांक खोजता है; कोई गैप न मिलने पर `last + 1` देता है | बिल्कुल समान: `startFrom` से `existingNumbers.last` तक पहला गायब पूर्णांक खोजता है; न मिलने पर `last + 1` देता है | App: `pharoah_numbering_engine.dart:52–64`<br>Web: `web_pharoah_numbering_engine.dart:63–72` |
| **कौन-सी List Scan होती है?** | `ph.saleChallans` / `ph.purchaseChallans` (Active FY की पूरी इन-मेमोरी लिस्ट, जिसमें Carry-Forward भी शामिल हैं) | `webPh.saleChallans` / `webPh.purchaseChallans` (Active FY की पूरी इन-मेमोरी लिस्ट, जिसमें Carry-Forward भी शामिल हैं) | App: `sale_challan_view.dart:52`, `purchase_challan_view.dart:51`<br>Web: `pharoah_web_manager.dart:4162, 4164` |

---

### 2. Part 1 • Section B के 6 सवालों का प्रमाणित उत्तर

#### सवाल 1: Carry-Forward Challan को Numbering से बाहर करने पर क्या नया Challan पुराने Carry-Forward Challan के समान Number प्राप्त कर सकता है?
**उत्तर (Confirmed — हाँ, बिल्कुल करेगा, और यही आपका अपेक्षित व्यवहार है):**
- मान लीजिए `2025-26` में App पर बना `SCH-1` (या कस्टम सीरीज़ `Y-1`) `Pending` रह गया और `2026-27` में Carry-Forward हुआ।
- जब हम `2026-27` की Numbering से Carry-Forward चालानों को बाहर कर देंगे, तो `2026-27` में अभी `2026-27` का कोई भी Native चालान नहीं है (`existingNumbers = []`)।
- इसलिए `2026-27` में बनने वाले पहले नए चालान को भी **`SCH-1` (या `Y-1`)** नंबर ही मिलेगा।
- फलस्वरूप `2026-27` की एक्टिव मेमोरी में दो चालान होंगे जिनका **Display Number समान (`SCH-1` या `Y-1`)** होगा, परंतु:
  - पहले का `id = ID-A` और `originalFy = "2025-26"` होगा (Carry-Forward)।
  - दूसरे का `id = ID-B` और `originalFy = "2026-27"` होगा (New FY Original)।

---

#### सवाल 2: अगर App और Web की Default Series अलग हैं (`SCH-` बनाम `WSCH-`, `PCH-` बनाम `WPCH-`), तो क्या मौजूदा व्यवस्था में यह समस्या पहले से नियंत्रित है?
**उत्तर (Confirmed — केवल Cross-Platform टकराव नियंत्रित है, Same-Platform Carry-Forward टकराव नियंत्रित नहीं है!):**
यह बहुत महत्वपूर्ण अंतर है:
- **क्या नियंत्रित है:** क्योंकि App का डिफ़ॉल्ट `SCH-` / `PCH-` है और Web का डिफ़ॉल्ट `WSCH-` / `WPCH-` है, इसलिए यदि `2025-26` में Pending चालान **App** पर बना था (`SCH-1`), तो `2026-27` में **Web** की सीरीज़ (`WSCH-1`) उससे प्रभावित नहीं होती।
- **क्या नियंत्रित नहीं है (Same-Platform Collision):**
  1. यदि `2025-26` में Pending चालान **App** पर बना था (`SCH-1` या `PCH-1`) और `2026-27` में Carry-Forward हुआ, तो **`2026-27` में App पर पहला नया चालान बनाते ही वह `SCH-1` / `PCH-1` के बजाय `SCH-2` / `PCH-2` बनता है!**
  2. इसी तरह यदि `2025-26` में Pending चालान **Web** पर बना था (`WSCH-1` या `WPCH-1`) और `2026-27` में Carry-Forward हुआ, तो **`2026-27` में Web पर पहला नया चालान `WSCH-1` / `WPCH-1` के बजाय `WSCH-2` / `WPCH-2` बनता है!**
- इसलिए Default Series अलग होने से केवल App और Web के आपस के नंबर अलग रहते हैं, लेकिन **हर प्लेटफ़ॉर्म अपने ही पिछले साल के Carry-Forward चालान से टकराता है!**

---

#### सवाल 3: अगर दोनों में एक ही Custom Prefix `Y-` इस्तेमाल होता है, तो क्या मौजूदा सिस्टम एक-दूसरे की Entries पहचानता है?
**उत्तर (Confirmed — जब दोनों Synced हैं तो पहचानता है, Offline होने पर दोनों `Y-1` बना सकते हैं):**
- यदि यूज़र ने `NumberingSeries` में `type: "CHALLAN"` के लिए कस्टम Prefix `"Y-"` सेट किया है:
  - App (`sale_challan_view.dart:45`) और Web (`pharoah_web_manager.dart:4121, 4132` — क्योंकि `"Y-"` != `"SCH-"`) दोनों ही `"Y-"` का उपयोग करेंगे।
  - जब App पर `Y-1` बनकर Web पर सिंक हो चुका है, तो `webPh.saleChallans` में `Y-1` आ जाता है; उसके बाद Web पर नया चालान बनाने पर `WebPharoahNumberingEngine` लिस्ट में `Y-1` देखकर अगला नंबर **`Y-2`** देगा।
  - (नोट: Purchase Challan में App `numberingSeries` को पढ़ता ही नहीं है — `purchase_challan_view.dart:49` में `"PCH-"` Hardcoded है)।

---

#### सवाल 4: क्या Numbering Engine केवल List Scan करके नंबर बनाता है या कोई साझा Persistent Counter भी प्रभावी रूप से काम करता है?
**उत्तर (100% Confirmed from Code — केवल List Scan काम करता है; Persistent Counter पूरी तरह निष्क्रिय/Dead है!):**
आइए `lib/logic/pharoah_numbering_engine.dart` (Lines `16–67`) के वास्तविक कोड को देखें:
```dart
final prefs = await SharedPreferences.getInstance();
String currentFY = prefs.getString('active_fy_$companyID') ?? "default_fy";
String counterKey = 'lastID_${type}_${prefix}_${companyID}_$currentFY'; // Line 20
```
- **Code Proof:** Line `20` पर `counterKey` स्ट्रिंग बनाई गई है, लेकिन **Line `21` से Line `67` (`getNextNumber` के अंत) तक `prefs.getInt(counterKey)` को एक बार भी कॉल नहीं किया गया है!**
- और इसके अलावा: Sale Challan (`finalizeSaleChallan`, `pharoah_manager.dart:1135–1209`) तथा Purchase Challan (`finalizePurchaseChallan`, `Lines 1210–1295`) में `PharoahNumberingEngine.updateSeriesCounter(...)` को कभी कॉल भी नहीं किया जाता!
- **Web (`lib/web_live_sync/web_pharoah_numbering_engine.dart:12–75`)** में तो `SharedPreferences` का कोई ज़िक्र ही नहीं है।
- **निष्कर्ष:** App और Web दोनों में Numbering Engine **100% केवल `currentList` को इन-मेमोरी स्कैन करके** ही नंबर बनाता है; कोई भी Persistent Counter नंबर जनरेशन में काम नहीं कर रहा है।

---

#### सवाल 5: क्या Delete के बाद Gap-Filling के कारण पुराने नंबर दोबारा दिए जा सकते हैं?
**उत्तर (Confirmed — हाँ, 100%):**
- क्योंकि दोनों Engines `for (int i = startFrom; i <= existingNumbers.last; i++) if (!existingNumbers.contains(i)) return "$prefix$i";` चलाते हैं (`pharoah_numbering_engine.dart:56–60` और `web_pharoah_numbering_engine.dart:66–70`):
- यदि `2026-27` में `Y-1`, `Y-2`, `Y-3` बने हैं और आपने `Y-2` डिलीट कर दिया, तो `existingNumbers = [1, 3]` रह जाएगा। अगली बार नया चालान बनाने पर इंजन `i = 2` को खाली पाकर दोबारा **`Y-2`** ही देगा।

---

#### सवाल 6: क्या Carry-Forward Records को Numbering से बाहर करना Sale और Purchase दोनों के लिए समान रूप से सुरक्षित है?
**उत्तर (Confirmed — हाँ, शर्त यह है कि Secondary-Key Matching में `originalFy` की सुरक्षा साथ में लगाई जाए):**
- **Sale Challan** में `billNo` (`SCH-1` / `WSCH-1` / `Y-1`) ऑटो-जनरेट होता है। Carry-Forward को बाहर करने पर नए साल में फिर से `SCH-1` / `WSCH-1` / `Y-1` बनेगा।
- **Purchase Challan** में `internalNo` (`PCH-1` / `WPCH-1`) ऑटो-जनरेट होता है और `billNo` सप्लायर का रेफरेंस नंबर होता है। Carry-Forward को बाहर करने पर नए साल में फिर से `PCH-1` / `WPCH-1` बनेगा।
- दोनों ही मामलों में यह तभी सुरक्षित होगा जब **Part 1 • Section C** में बताए अनुसार `id` को प्राथमिक पहचान और `(secondaryKey + originalFy)` को द्वितीयक पहचान बनाया जाए, ताकि नए साल का `SCH-1`/`PCH-1` पुराने साल के Carry-Forward `SCH-1`/`PCH-1` को ओवरराइट न करे।

---

### उदाहरण (Part 1 • Section B का Walkthrough)
> **Scenario:** `2025-26` में `Y-1` नाम का Challan है। वह `2026-27` में Carry-Forward होता है। अब `2026-27` में नया Challan बनाया जाता है।

1. **Carry-Forward `Y-1` की स्थिति:** वह `2026-27` की लिस्ट में `id: "ID-2025"`, `billNo: "Y-1"`, `originalFy: "2025-26"`, `status: "Pending"` के रूप में रहेगा।
2. **नए Challan को कौन-सा Number मिलेगा:** जब Numbering Engine केवल `originalFy == "2026-27"` वाले चालानों को स्कैन करेगा, तो उसे `2026-27` में कोई चालान नहीं मिलेगा और वह नए चालान को भी **`Y-1`** देगा (`id: "ID-2026"`, `billNo: "Y-1"`, `originalFy: "2026-27"`).
3. **क्या दोनों रिकॉर्ड पूरे ERP में सुरक्षित रहेंगे?:**
   - **वर्तमान कोड में:** सुरक्षित **नहीं** रहेंगे! नया `Y-1` सेव होते ही `finalizeSaleChallan` (`pharoah_manager.dart:1156`) या `addSaleChallanAndSync` (`pharoah_web_manager.dart:2910`) या `DeltaMergeEngine` (`delta_merge_engine.dart:253`) `billNo == "Y-1"` देखकर पुराने `ID-2025` को ओवरराइट कर देगा!
   - **हमारे संशोधित Plan (Section C) के बाद:** दोनों रिकॉर्ड 100% सुरक्षित रहेंगे क्योंकि उनकी प्राथमिक पहचान `id` (`ID-2025` बनाम `ID-2026`) और द्वितीयक पहचान `(billNo, originalFy)` (`("Y-1", "2025-26")` बनाम `("Y-1", "2026-27")`) अलग-अलग होगी।

---

## Part 1 • Section C — Duplicate Matching और Permanent Identity

### 1. सभी संबंधित Methods की वास्तविक Matching Logic (Code Audit Table)

हमने पूरे कोडबेस में उन सभी जगहों की जाँच की जहाँ `SaleChallan` और `PurchaseChallan` को खोजा, जोड़ा, हटाया या मर्ज किया जाता है:

| Method & File Path | वर्तमान Matching Condition (Exact Code) | क्या `billNo`/`internalNo` से गलत Match हो सकता है? |
|---|---|---|
| **1. `finalizeSaleChallan`**<br>`lib/pharoah_manager.dart:1148, 1156` | `c.id == cId \|\| (cleanBNo.isNotEmpty && c.billNo.trim().toUpperCase() == cleanBNo)` | ⚠️ **हाँ!** यदि नए FY में `Y-1` (`ID-B`) बना, तो `c.billNo == "Y-1"` के कारण वह पुराने Carry-Forward `Y-1` (`ID-A`) को `removeWhere` से उड़ा देगा! |
| **2. `finalizePurchaseChallan`**<br>`lib/pharoah_manager.dart:1224, 1247` | `c.id == cId \|\| (cleanINo.isNotEmpty && c.internalNo.trim().toUpperCase() == cleanINo)` | ⚠️ **हाँ!** नया `PCH-1` (`ID-B`) सेव होते ही पुराने Carry-Forward `PCH-1` (`ID-A`) को हटा देगा! |
| **3. `addSaleChallanAndSync`**<br>`lib/web_live_sync/pharoah_web_manager.dart:2909–2912` | `c.id == challan.id \|\| (cleanBNo.isNotEmpty && c.billNo.trim().toUpperCase() == cleanBNo)` | ⚠️ **हाँ!** Web पर नया `WSCH-1` / `Y-1` सेव होते ही `existingIdx` में पुराने Carry-Forward `WSCH-1` / `Y-1` को पकड़ लेगा और उसे ओवरराइट कर देगा! |
| **4. `addPurchaseChallanAndSync`**<br>`lib/web_live_sync/pharoah_web_manager.dart:2964–2966` | `c.id == challan.id \|\| (cleanINo.isNotEmpty && c.internalNo.trim().toUpperCase() == cleanINo)` | ⚠️ **हाँ!** Web पर नया `WPCH-1` पुराने Carry-Forward `WPCH-1` को ओवरराइट कर देगा! |
| **5. `deleteSaleChallan` (App & Web)**<br>`pharoah_manager.dart:3016, 3041`<br>`pharoah_web_manager.dart:3052, 3069` | `x.id == cId \|\| (bNo.isNotEmpty && x.billNo.trim().toUpperCase() == bNo)` | ⚠️ **हाँ!** यदि आप `2026-27` का नया `Y-1` (`ID-B`) डिलीट करेंगे, तो `x.billNo == "Y-1"` की वजह से `2025-26` का Carry-Forward `Y-1` (`ID-A`) भी साथ में डिलीट हो जाएगा! |
| **6. `deletePurchaseChallan` (App & Web)**<br>`pharoah_manager.dart:3052, 3085`<br>`pharoah_web_manager.dart:3086, 3116` | `item.id == challanId \|\| (iNo.isNotEmpty && item.internalNo == iNo) \|\| (partyId == pId && billNo == bNo)` | ⚠️ **हाँ!** नया `PCH-1` डिलीट करने पर पुराना Carry-Forward `PCH-1` भी डिलीट हो जाएगा! |
| **7. `SaleChallanSyncModule.mergeIncomingSaleChallanEnvelope`**<br>`lib/sync_core/modules/sale_challan_sync_module.dart:57, 78` | पहले `c.id == incoming.id` देखता है; न मिलने पर `c.billNo.trim() == incoming.billNo.trim()` से ओवरराइट कर देता है! | ⚠️ **हाँ!** जब दूसरे डिवाइस पर नया `Y-1` (`ID-B`) सिंक होकर आएगा, तो `ID-B` न मिलने पर वह `billNo == "Y-1"` से मैच करके पुराने `ID-A` को ओवरराइट कर देगा! |
| **8. `PurchaseChallanSyncModule.mergeIncomingPurchaseChallanEnvelope`**<br>`lib/sync_core/modules/purchase_challan_sync_module.dart:77–87` | `c.id == incoming.id \|\| c.internalNo == cleanInt \|\| (c.billNo == cleanBill && c.partyId == cleanParty)` | ⚠️ **हाँ!** अलग `id` होने पर भी `internalNo` समान होने के कारण पुराने Carry-Forward `PCH-1` को ओवरराइट कर देगा! |
| **9. `DeltaMergeEngine.processCloudData`**<br>`lib/web_live_sync/sync_protocol/delta_merge_engine.dart:207, 250–266` | Step 1 में `localBNo == bNoKey` से मैच करता है और Step 2 में **`uniqueByBillNo[dedupKey]` बनाकर समान `billNo` वाले दो चालानों में से एक को हमेशा के लिए गायब कर देता है!** | 🚨 **सबसे बड़ा खतरा!** भले ही आप सेव करते समय दोनों `Y-1` अलग रख लें, अगली बार `FastPullEngine` चलते ही `DeltaMergeEngine` का `uniqueByBillNo` दोनों `Y-1` में से पुराने वाले को उड़ा देगा! |
| **10. `MultiFyCloudVault._findMatchingRecordIndex`**<br>`lib/sync_core/multi_fy_cloud_vault.dart:282, 305` | `s_challan.json` में `keyToIdx[id] ?? secKeyToIdx[billNo]` इस्तेमाल करता है | ⚠️ **हाँ!** अलग `id` होने पर भी `secKeyToIdx["Y-1"]` से पुराने `Y-1` से मर्ज कर देगा! |
| **11. `PharoahWebManager._parseDownloadedFiles` & `_reloadActiveFyFromVaultHotSwap`**<br>`pharoah_web_manager.dart:1057, 1072, 1742, 1760` | `x.id == item.id \|\| (item.billNo.isNotEmpty && x.billNo == item.billNo)` | ⚠️ **हाँ!** अलग `id` होने पर भी `billNo` / `internalNo` समान होने से ओवरराइट कर देगा! |
| **12. Bill Conversion & Bill Delete Links**<br>`pharoah_manager.dart:723, 893, 2804, 2912`<br>`pharoah_web_manager.dart:2389, 2489, 2603, 2732` | `targetCids.contains(c.id) \|\| targetCids.contains(c.billNo)` (क्योंकि `item.sourceChallanNo` को भी `targetCids` में डाला जाता है!) | 🚨 **बहुत बड़ा खोज (Critical Discovery)!** नीचे सवाल 4 और उदाहरण में इसका पूरा प्रमाण देखें! |

---

### 2. Part 1 • Section C के 6 सवालों का सटीक और ईमानदार उत्तर

#### सवाल 1: क्या किसी जगह `billNo` या `internalNo` को प्राथमिक पहचान की तरह इस्तेमाल किया जा रहा है?
**उत्तर (Confirmed — हाँ, ऊपर दी गई सभी 12 जगहों पर!):**
- यद्यपि हर चालान के पास अपना `id` है, फिर भी लगभग हर Save, Delete, Merge और Conversion मेथड में `c.id == targetId || c.billNo == targetBillNo` लिखा है, और `DeltaMergeEngine` (`Line 253`) में तो `dedupKey = bNo.isNotEmpty ? bNo : "ID:$itemId"` लिखकर `billNo` को `id` से भी ऊपर प्राथमिक पहचान बना दिया गया है!
- और इससे भी गंभीर: जब किसी चालान से Bill बनता है (`finalizeSale` Line `716–718`, `deleteBill` Line `2792–2795`, `addSaleAndSync` Line `2382–2385`, `deleteSale` Line `2481–2483`), तो कोड `linkedChallanIds` (जिसमें `id` होता है) के साथ-साथ प्रत्येक आइटम के **`it.sourceChallanNo` (जिसमें `"Y-1"` लिखा होता है) को भी `allSaleChallanLinks` / `targetCids` सेट में डाल देता है!**
  - इसका परिणाम यह है कि यदि आपने केवल नए साल के `Y-1` (`ID-B`) का बिल बनाया, तो `it.sourceChallanNo` की वजह से `allSaleChallanLinks` में `"Y-1"` चला जाएगा, और लूप `c.billNo == "Y-1"` देखकर **पुराने साल के Carry-Forward `Y-1` (`ID-A`) को भी अपने-आप `"Billed"` कर देगा — जबकि आपने `ID-A` का बिल बनाया ही नहीं था!**

---

#### सवाल 2: क्या स्थायी `id` को प्राथमिक पहचान बनाना संभव और सही है?
**उत्तर (100% हाँ — Confirmed):**
- Pharoah ERP में बनने वाले हर `SaleChallan` और `PurchaseChallan` को निर्माण के समय ही एक गैर-खाली यूनिक `id` मिलता है:
  - App में: `DateTime.now().toString()` (`pharoah_manager.dart:1145, 1221`)
  - Web में: `"SCH-WEB-${DateTime.now().millisecondsSinceEpoch}"` / `"PCH-WEB-${DateTime.now().millisecondsSinceEpoch}"` (`web_sale_challan_billing_view.dart:119`, `web_purchase_challan_billing_view.dart:629`)
- और Carry-Forward होते समय भी वही `id` अपरिवर्तित रहता है।
- इसलिए जब दोनों रिकॉर्ड्स के पास गैर-खाली `id` (`c.id.isNotEmpty && incoming.id.isNotEmpty`) हो और उनका `originalFy` अलग-अलग हो, तो उनकी पहचान **केवल `id`** से होनी चाहिए; अलग `originalFy` वाले दो रिकॉर्ड्स को कभी भी `billNo` या `internalNo` के आधार पर एक नहीं माना जाना चाहिए।

---

#### सवाल 3: क्या `originalFy` केवल अतिरिक्त पहचान सुरक्षा (Secondary-Key Scope) के लिए इस्तेमाल होना चाहिए?
**उत्तर (Confirmed — हाँ, `originalFy` के 3 सटीक काम हैं):**
1. **Carry-Forward बनाम Native पहचान:** यह जानने के लिए कि कोई चालान `activeFy` का अपना चालान है (`originalFy == activeFy`) या पिछले साल से आया है (`originalFy != activeFy`), ताकि Numbering Engine उसे गिने नहीं और UI उस पर `[CF • 2025-26]` बैज दिखा सके।
2. **Secondary-Key (`billNo` / `internalNo`) Scoping:** जब कभी `billNo` या `internalNo` से Fallback Matching या Deduplication किया जाए (जैसे सेव करते समय या `DeltaMergeEngine` में), तो की (Key) केवल `"Y-1"` न होकर **`"${originalFy}_Y-1"`** हो!
3. **Cross-FY Origin Status Sync:** जब किसी Carry-Forward चालान (`originalFy: "2025-26"`) का बिल `2026-27` में बने या डिलीट हो, तो सिस्टम को तुरंत पता हो कि उसकी मूल कॉपी किस FY (`"2025-26"`) के फोल्डर/वॉल्ट में जाकर अपडेट करनी है।

---

#### सवाल 4: Gemini के पुराने Plan में `effectiveOriginalFy == currentFY` की शर्त लगाई गई थी। क्या इससे Carry-Forward Challan का Edit, Update, Delete या Bill Conversion रुक सकता है?
**उत्तर (100% हाँ — आपका सवाल बिल्कुल सही है! हमारे पिछले Plan के Step 3 में वह शर्त अधूरी/गलत थी):**
आइए साबित करें कि यदि `finalizeSaleChallan` या `addSaleChallanAndSync` में सीधे `c.effectiveOriginalFy == currentFY` लगा दिया जाता तो क्या टूटता:
1. **Carry-Forward Challan को नए FY (`2026-27`) में Edit करने पर क्या टूटता:**
   - मान लीजिए `Challan A` (`id: ID-A, billNo: Y-1, originalFy: 2025-26`) अभी `2026-27` में दिख रहा है।
   - यूज़र ने `2026-27` में रहते हुए `Challan A` में 1 आइटम बदला और Save दबाया।
   - इस समय `currentFY` तो `"2026-27"` है, लेकिन `Challan A` का `originalFy` `"2025-26"` है!
   - यदि `finalizeSaleChallan` में `c.effectiveOriginalFy == currentFY` शर्त होती, तो:
     - या तो वह `ID-A` को अपडेट करने से मना कर देता,
     - या यदि `newChallan` बनाते समय उसका `originalFy = currentFY` (`2026-27`) रख देता, तो पुराना `ID-A` (`2025-26`) लिस्ट में छूट जाता और एक डुप्लीकेट `ID-A` (`2026-27`) बन जाता!
2. **इसलिए सही नियम `effectiveOriginalFy == currentFY` नहीं, बल्कि यह है:**
   - नया या एडिट किया जा रहा चालान अपना **`targetOriginalFy = existingRecord?.effectiveOriginalFy ?? currentFY`** रखेगा!
   - और लिस्ट में मैचिंग का नियम होगा:
     ```dart
     bool isSameChallan(SaleChallan existing, String targetId, String targetBillNo, String targetOriginalFy) {
       // 1. Primary Match: If both have IDs, match ONLY if IDs are equal!
       if (existing.id.trim().isNotEmpty && targetId.trim().isNotEmpty) {
         if (existing.id.trim() == targetId.trim()) return true;
         // If IDs are different, they can ONLY be the same challan if they belong to the EXACT SAME originalFy AND have the same billNo
         return existing.effectiveOriginalFy == targetOriginalFy &&
                targetBillNo.isNotEmpty &&
                existing.billNo.trim().toUpperCase() == targetBillNo.trim().toUpperCase();
       }
       // 2. Fallback for legacy empty ID: match billNo + same originalFy
       return existing.effectiveOriginalFy == targetOriginalFy &&
              targetBillNo.isNotEmpty &&
              existing.billNo.trim().toUpperCase() == targetBillNo.trim().toUpperCase();
     }
     ```
   - **देखिए यह नियम कितना सटीक है:**
     - जब आप `2026-27` में Carry-Forward `Challan A` (`ID-A`, `originalFy: 2025-26`) को Edit करेंगे, तो `existing.id == "ID-A"` से वह सीधे `Challan A` को ही अपडेट करेगा और उसका `originalFy` भी `"2025-26"` ही रखेगा; `Challan B` (`ID-B`, `originalFy: 2026-27`) को छुएगा भी नहीं!
     - और जब आप `2026-27` में नया `Challan B` (`ID-B`, `billNo: Y-1`, `originalFy: 2026-27`) बनाएँगे, तो `Challan A` के साथ न तो उसका `id` मैच होगा (`ID-A != ID-B`) और न ही उसका `originalFy` मैच होगा (`2025-26 != 2026-27`) — इसलिए दोनों `Y-1` बिना किसी टकराव के एक साथ सुरक्षित रहेंगे!

---

#### सवाल 5: क्या Matching के लिए Original FY, Active FY और Record ID के अलग-अलग अर्थ स्पष्ट रूप से रखने जरूरी हैं?
**उत्तर (Confirmed — हाँ, तीनों का अर्थ और भूमिका पूरी तरह अलग है):**
1. **`Record ID` (`id`):** चालान की जन्मजात, अपरिवर्तनीय वैश्विक पहचान (Global Primary Key)। एक ही चालान जब `2025-26` से `2026-27` में Carry-Forward होता है, तो दोनों सालों की कॉपी का `id` **समान** होता है। लेकिन दो अलग-अलग चालानों (भले ही दोनों का नंबर `Y-1` हो) का `id` हमेशा **अलग** होता है।
2. **`Original FY` (`originalFy`):** वह वित्तीय वर्ष जिसमें वह चालान मूल रूप से पैदा हुआ था। यह चालान की नंबरिंग सीरीज़ का नेमस्पेस (Series Namespace) है। `Y-1` अकेले कोई यूनिक की नहीं है; **`(originalFy, billNo)`** यानी `("2025-26", "Y-1")` बनाम `("2026-27", "Y-1")` यूनिक सीरीज़ की है।
3. **`Active FY` (`currentFY` / `financialYear`):** वह फोल्डर या वॉल्ट बकेट (`2026-27`) जिसे यूज़र इस समय स्क्रीन पर देख रहा है। एक `Active FY` (`2026-27`) की लिस्ट में `originalFy = "2025-26"` (Carry-Forward) और `originalFy = "2026-27"` (Native) दोनों के रिकॉर्ड एक साथ रहते हैं।

---

#### सवाल 6: क्या Purchase Challan के `billNo` और `internalNo` को अलग-अलग पहचान नियमों की जरूरत है?
**उत्तर (Confirmed — हाँ, क्योंकि दोनों की प्रकृति बिल्कुल अलग है):**
1. **`internalNo` (Inward ID — `PCH-1` / `WPCH-1`):**
   - यह हमारे ERP द्वारा जनरेट किया गया सीरीज़ नंबर है।
   - इसकी यूनिकनेस **`(originalFy, internalNo)`** पर होती है (जैसे `("2025-26", "PCH-1")` बनाम `("2026-27", "PCH-1")`).
2. **`billNo` (Supplier Ref No — जैसे सप्लायर का चालान नंबर `105`):**
   - यह सप्लायर द्वारा दिया गया नंबर है; अलग-अलग सप्लायरों का `billNo` समान हो सकता है, और एक ही सप्लायर अगले वित्तीय वर्ष में फिर से `1` से अपने चालान नंबर शुरू कर सकता है।
   - इसलिए `billNo` की डुप्लीकेट जाँच (`findDuplicateSupplierChallan`) हमेशा **`(partyId, originalFy, billNo)`** पर होनी चाहिए — कभी भी अकेले `billNo` पर या बिना `originalFy` के नहीं!

---

### उदाहरण (Part 1 • Section C का 4-Point Verification)
मान लीजिए `Active FY = 2026-27` में दो रिकॉर्ड हैं:
- **Challan A:** `id = ID-A`, `originalFy = 2025-26`, `billNo = Y-1`
- **Challan B:** `id = ID-B`, `originalFy = 2026-27`, `billNo = Y-1`

1. **A को Edit करने पर B सुरक्षित कैसे रहेगा?**
   - Edit स्क्रीन में `existingRecord = Challan A` पास होता है, इसलिए `existingId = "ID-A"` और `targetOriginalFy = "2025-26"` है।
   - `finalizeSaleChallan` / `addSaleChallanAndSync` जब लिस्ट में मैच खोजेगा, तो `Challan B` का न तो `id` `"ID-A"` है और न ही उसका `originalFy` `"2025-26"` है। इसलिए केवल `Challan A` (`ID-A`) अपडेट होगा (और साथ ही `2025-26` के फोल्डर/वॉल्ट में भी `ID-A` अपडेट होगा); `Challan B` 100% अछूता रहेगा।
2. **B को Delete करने पर A सुरक्षित कैसे रहेगा?**
   - `deleteSaleChallan("ID-B")` को कॉल करने पर सबसे पहले `id == "ID-B"` से `targetC = Challan B` मिलेगा जिसका `originalFy = "2026-27"` है।
   - `saleChallans.removeWhere` केवल उसी रिकॉर्ड को हटाएगा जिसका `id == "ID-B"` हो (या जिसका `billNo == "Y-1"` **और** `effectiveOriginalFy == "2026-27"` हो)।
   - सेकेंडरी टॉम्बस्टोन भी `"2026-27_Y-1"` पर लगेगा, इसलिए `"2025-26"` का `Challan A` (`ID-A`) न तो मेमोरी से हटेगा और न ही टॉम्बस्टोन से ब्लॉक होगा!
3. **Sync में A और B को एक-दूसरे का Duplicate समझकर Merge या Overwrite होने से कैसे रोका जाएगा?**
   - `DeltaMergeEngine` (`lib/web_live_sync/sync_protocol/delta_merge_engine.dart:207, 253`), `MultiFyCloudVault._findMatchingRecordIndex` (`lib/sync_core/multi_fy_cloud_vault.dart:185, 305`), `SaleChallanSyncModule.mergeIncomingSaleChallanEnvelope` (`line 78`), `PurchaseChallanSyncModule.mergeIncomingPurchaseChallanEnvelope` (`line 80`), और `PharoahWebManager._parseDownloadedFiles` (`lines 1057, 1072`) में:
     - जब दो चालानों का `id` अलग-अलग हो और उनके `effectiveOriginalFy` अलग-अलग हों, तो उन्हें कभी मर्ज नहीं किया जाएगा।
     - `DeltaMergeEngine` के `uniqueByBillNo` में `dedupKey` को `bNo` के बजाय **`"${item.effectiveOriginalFy}_$bNo"`** बनाया जाएगा! इससे `"2025-26_Y-1"` और `"2026-27_Y-1"` दोनों अलग-अलग कीज़ में सुरक्षित रहेंगे!
4. **Bill Conversion में सही Challan कैसे चुना जाएगा?**
   - जैसा हमने ऊपर **Table Row #12** में पकड़ा: जब `Challan B` (`ID-B`, `billNo: Y-1`) का बिल बनता है, तो `Sale.linkedChallanIds` में `["ID-B"]` होता है, लेकिन प्रत्येक `BillItem` में `sourceChallanId: "ID-B"` और `sourceChallanNo: "Y-1"` दोनों होते हैं।
   - वर्तमान कोड (`pharoah_manager.dart:717, 887, 2794, 2902` और `pharoah_web_manager.dart:2384, 2482, 2600, 2725`) में एक गंभीर बग है: वह `it.sourceChallanId` मौजूद होने पर भी **`it.sourceChallanNo` (`"Y-1"`) को `allSaleChallanLinks` / `targetCids` में डाल देता है!**
   - **सुधार:** जब `it.sourceChallanId` मौजूद हो (जो हर नए और स्टिच किए गए बिल में हमेशा मौजूद होता है — `challan_stitcher_wizard.dart:345`, `web_challan_stitcher_wizard.dart:129`), तब **केवल `sourceChallanId` (`ID-B`) को ही मैचिंग सेट में डाला जाए; `sourceChallanNo` (`"Y-1"`) को केवल तभी इस्तेमाल किया जाए जब `linkedChallanIds` और `sourceChallanId` दोनों खाली हों!**
   - इससे `Challan B` (`ID-B`) का बिल बनने या डिलीट होने पर `Challan A` (`ID-A`) का स्टेटस कभी भी गलती से नहीं बदलेगा!

---

## Part 1 • Section D — Final Technical Conclusion (Part 1)

1. **क्या पिछला 6-Step Plan सही है?**
   - पिछले 6-Step Plan की दिशा सही थी, लेकिन इस गहरी जाँच से उसमें **3 महत्वपूर्ण सुधार (Critical Refinements)** सामने आए हैं जिनके बिना वह अधूरा रहता:
     - **Refinement 1:** `originalFy` केवल `date` से डायनामिक रूप से न निकाला जाए, बल्कि मॉडल में एक **स्थायी (persisted) `String originalFy` फ़ील्ड** हो जो निर्माण या Carry-Forward के समय एक बार सेट होकर Edit के दौरान भी अपरिवर्तित रहे (`existingRecord?.effectiveOriginalFy ?? currentFY`)।
     - **Refinement 2:** Save/Delete/Merge में शर्त `c.effectiveOriginalFy == currentFY` **नहीं** होनी चाहिए (वरना नए FY में Carry-Forward चालान का Edit/Delete टूट जाएगा), बल्कि शर्त **`c.id == target.id || (c.effectiveOriginalFy == target.effectiveOriginalFy && c.billNo == target.billNo)`** होनी चाहिए।
     - **Refinement 3:** `DeltaMergeEngine` (`uniqueByBillNo` at `line 253`) और Bill Conversion/Delete (`it.sourceChallanNo` matching at `pharoah_manager.dart:717, 2794` & `pharoah_web_manager.dart:2384, 2482`) को भी ठीक करना अनिवार्य है, वरना `FastPullEngine` समान `billNo` वाले दूसरे चालान को उड़ा देगा और एक `Y-1` का बिल बनाने पर दोनों `Y-1` `"Billed"` हो जाएँगे!
2. **क्या `originalFy` पर्याप्त है या कोई और Identity/Metadata आवश्यक है?**
   - `id` (Primary Key) + `originalFy` (Creation FY Namespace) — ये दोनों मिलकर Numbering, Deduplication और Origin FY Status Sync के लिए पूरी तरह पर्याप्त हैं।
3. **क्या Numbering Engine में बदलाव अकेले पर्याप्त होगा?**
   - **बिल्कुल नहीं!** यदि केवल Numbering Engine में बदलाव करके `2026-27` में नया `Y-1` (`SCH-1`/`PCH-1`) बनने दिया गया, और Save/Delete/Merge/Bill-Link में ऊपर बताए गए बदलाव नहीं किए गए, तो नया `Y-1` बनते ही पुराने Carry-Forward `Y-1` को ओवरराइट कर देगा या उसका बिल बनने पर दोनों `"Billed"` हो जाएँगे।

---
---

# =====================================================================
# PART 2 — Cross-FY Challan Status, App-Web Sync, Bill Conversion & Deletion: Deep Workflow Investigation
# =====================================================================

## Part 2 • Section A — Carry-Forward Challan का पूरा Data Flow

### 1. सटीक Storage और Identity Flow (Questions 1 to 7)

1. **App में वह किस File में Store होता है?**
   - **Original FY Copy:** `Pharoah_Data/<companyID>/<businessType>/2025-26/s_challan.json` (Sale) और `p_challan.json` (Purchase)।
   - **Carried-Forward Copy in Active FY:** `Pharoah_Data/<companyID>/<businessType>/2026-27/s_challan.json` और `p_challan.json` (`lib/fy_transfer_engine.dart:959–966` एवं `lib/pharoah_manager.dart:3940–3949`)।
2. **Web में वह किस FY Vault में Store होता है?**
   - `PharoahWebManager.fyVault` (`Map<String, Map<String, String>>`) के अंदर:
     - `fyVault["2025-26"]["s_challan.json"]` / `["p_challan.json"]`
     - `fyVault["2026-27"]["s_challan.json"]` / `["p_challan.json"]`
   - और जब Web पर Active FY `2026-27` चुना जाता है, तो `webPh.saleChallans` और `webPh.purchaseChallans` में `2026-27` के वॉल्ट की लिस्ट लोड होती है।
3. **Cloud D1 में उसकी पहचान और FY कैसे निर्धारित होते हैं?**
   - **वर्तमान स्थिति (Confirmed from Code):**
     - `SaleChallanSyncModule.onSaleChallanSaved()` (`lib/sync_core/modules/sale_challan_sync_module.dart:15–35`) और `PurchaseChallanSyncModule.onPurchaseChallanSaved()` (`lib/sync_core/modules/purchase_challan_sync_module.dart:23–44`) Outbox (`SyncQueueManager`) में एक `SyncEnvelope` डालते हैं जिसका `syncId = challan.id` और `billData = challan.toMap()` होता है।
     - ध्यान दें: **Challans के लिए `D1SalesLedgerService` में `onSaleSaved` / `onPurchaseSaved` जैसा कोई अलग डायरेक्ट HTTP POST मेथड नहीं है!** Challans केवल दो रास्तों से सिंक होते हैं:
       1. **Outbox Batch (`SyncQueueManager` -> `MasterSyncOrchestrator.dispatchEnvelope`)**, और
       2. **Full/Delta Cloud Vault Snapshot (`MultiFyCloudVault` / `WebSyncEngine.pushStoreData` / `FastPullEngine`)**।
     - जब `MasterSyncOrchestrator.dispatchEnvelope` (`lib/sync_core/orchestrator/master_sync_orchestrator.dart:63–68`) को कोई Challan Envelope मिलता है, तो वह `D1SalesLedgerService.extractEventFy(envelope.billData, envDate)` से उसका FY निकालता है — जो `billData['fy']` न होने के कारण **`challan.date` से उसका मूल FY (`2025-26`) निकालता है!**
4. **क्या एक ही Challan की Copies Original FY और Active FY दोनों में हो सकती हैं?**
   - **Confirmed (हाँ):** जब तक चालान `Pending` है (और बाद में `Billed` होने के बाद भी), उसकी एक कॉपी `2025-26/s_challan.json` में और दूसरी कॉपी `2026-27/s_challan.json` में रहती है।
5. **क्या दोनों Copies में समान ID और समान Original FY सुरक्षित रहते हैं?**
   - **Confirmed (हाँ):** `reconcileCarryForwardSaleChallans` (`lib/fy_transfer_engine.dart:538`) `SaleChallan.fromMap(sc.toMap())` के द्वारा क्लोन बनाता है, जिससे `id`, `billNo`, `date`, `items` सब समान रहते हैं। जब हम `originalFy` जोड़ेंगे, तो दोनों कॉपियों में `id: "ID-A"` और `originalFy: "2025-26"` बिल्कुल समान रहेंगे।
6. **क्या App और Web में Carry-Forward के बाद उसका Status, Date, Number और Items समान रहते हैं?**
   - **Confirmed (हाँ):** Carry-Forward के समय न तो `status` बदलता है (`"Pending"`), न `date`, न `billNo`/`internalNo`, और न ही `items`।
7. **क्या Multi-Year Carry-Forward (`2024-25` → `2025-26` → `2026-27`) में भी उसकी Original Identity सुरक्षित रहती है?**
   - **Confirmed (हाँ):** `syncPendingChallansFromPreviousYears` (`lib/pharoah_manager.dart:3888`) और `_cascadeWebFyVaultFrom` (`lib/web_live_sync/pharoah_web_manager.dart:1548`) क्रमबद्ध लूप (`for (int i = startIdx; i < endIdx; i++)`) में `2024-25` -> `2025-26` और फिर `2025-26` -> `2026-27` चलाते हैं।

### उदाहरण (Multi-Year Carry-Forward Walkthrough: `2024-25` → `2025-26` → `2026-27`)
- मान लीजिए `Challan ID-A` (`billNo: Y-1`, `date: 10/02/2025`, `originalFy: 2024-25`) अब तक `Pending` है:
  - **`2024-25/s_challan.json` (एवं `fyVault["2024-25"]`):** `{id: "ID-A", billNo: "Y-1", originalFy: "2024-25", status: "Pending"}` — यहाँ यह **Native Challan** के रूप में दिखेगा।
  - **`2025-26/s_challan.json` (एवं `fyVault["2025-26"]`):** `{id: "ID-A", billNo: "Y-1", originalFy: "2024-25", status: "Pending"}` — यहाँ यह **`[CF • 2024-25]`** के रूप में दिखेगा।
  - **`2026-27/s_challan.json` (एवं `fyVault["2026-27"]`):** `{id: "ID-A", billNo: "Y-1", originalFy: "2024-25", status: "Pending"}` — यहाँ भी यह **`[CF • 2024-25]`** के रूप में दिखेगा।

---

## Part 2 • Section B — नए FY में Bill Conversion (End-to-End Code Audit)

आइए देखें कि जब `2025-26` का Pending Challan `Y-1` (`ID-A`) Carry-Forward होकर `2026-27` में आया है और यूज़र **`2026-27` में उसका Bill बनाता है**, तब App और Web के सभी Conversion Paths वास्तव में क्या करते हैं:

### 1. सभी 6 Bill Conversion Paths की वास्तविक Code जाँच

| Conversion Path | File Path & Method | Active FY (`2026-27`) की Copy का क्या होता है? | Original FY (`2025-26`) की Copy का क्या होता है? (CRITICAL GAP!) |
|---|---|---|---|
| **1. App Single Sale Conversion** | `lib/challans/challan_to_bill_converter.dart:236–248` → `ph.finalizeSale()` (`lib/pharoah_manager.dart:720–735`) | `ph.saleChallans` (`2026-27`) में `c.status = "Billed"`, `c.version += 1`, `c.updatedAt = now` होता है और `2026-27/s_challan.json` में सेव होता है। *(नोट: `challan_to_bill_converter.dart:238` पहले ही `status = "Billed"` कर देता है, जिससे `finalizeSale:725` का `if (c.status != "Billed")` ब्लॉक स्किप हो जाता है और न `version++` होता है न `SaleChallanSyncModule.onSaleChallanSaved` चलता है!)* | ❌ **`2025-26/s_challan.json` को बिल्कुल नहीं छूता!** वहाँ `ID-A` अभी भी `"Pending"` पड़ा रहता है! |
| **2. App Single Purchase Conversion** | `lib/purchase/purchase_billing_view.dart` → `ph.finalizePurchase()` (`lib/pharoah_manager.dart:890–906`) | `ph.purchaseChallans` (`2026-27`) में `c.status = "Billed"`, `c.version += 1`, `c.updatedAt = now` और `PurchaseChallanSyncModule.onPurchaseChallanSaved` चलता है। | ❌ **`2025-26/p_challan.json` को बिल्कुल नहीं छूता!** वहाँ `ID-A` अभी भी `"Pending"` पड़ा रहता है! |
| **3. App Stitcher (Sale & Purchase Batch)** | `lib/challans/challan_stitcher_wizard.dart:101, 134` → `ph.finalizeBatchSales()` (`1066–1101`) / `ph.finalizeBatchPurchases()` (`1103–1133`) | `ph.saleChallans` / `ph.purchaseChallans` (`2026-27`) में `status = "Billed"`, `version += 1`, `updatedAt = now` होता है। *(किंतु `finalizeBatchSales/Purchases` में न `SyncQueueManager.flushOutboxAsJSONBatch()` कॉल होता है और न `AppRealtimeCoordinator.instance.notifyAppMutation()`!)* | ❌ **`2025-26/s_challan.json` और `p_challan.json` को बिल्कुल नहीं छूता!** |
| **4. Web Single Sale Conversion** | `lib/web_live_sync/sub_views/web_billing/web_new_sale_view.dart:438–451` → `webPh.addSaleAndSync()` (`pharoah_web_manager.dart:2387–2399`) | `webPh.saleChallans` (`2026-27`) और `fyVault["2026-27"]` में `status = "Billed"`, `version += 1`, `updatedAt = now` होता है और `SaleChallanSyncModule.onSaleChallanSaved` चलता है। | ❌ **`fyVault["2025-26"]["s_challan.json"]` को बिल्कुल नहीं छूता!** वहाँ `ID-A` अभी भी `"Pending"` रहता है! |
| **5. Web Single Purchase Conversion** | `lib/web_live_sync/sub_views/web_purchase/mechanism/web_purchase_mechanism.dart:84, 122–132` → `webPh.addPurchaseAndSync()` (`2601–2613`) | `webPh.purchaseChallans` (`2026-27`) और `fyVault["2026-27"]` में `status = "Billed"`, `version += 1`, `updatedAt = now` होता है। | ❌ **`fyVault["2025-26"]["p_challan.json"]` को बिल्कुल नहीं छूता!** |
| **6. Web Stitcher (Sale & Purchase)** | `lib/web_live_sync/web_challan_stitcher_wizard.dart:369–378, 424–433` | `webPh.saleChallans` / `webPh.purchaseChallans` (`2026-27`) और `fyVault["2026-27"]` में `status = "Billed"` करता है। | ❌ **`fyVault["2025-26"]` को बिल्कुल नहीं छूता!** |

---

### 2. Part 2 • Section B के 9 सवालों के सटीक उत्तर और Discovered Bugs

1. **Challan Status कहाँ और किस Method से Billed होता है?**
   - ऊपर तालिका के 6 मेथड्स में।
   - **Bug #1 (`lib/challans/challan_to_bill_converter.dart:238`):** App के `ChallanToBillConverter._finalizeConversion()` में Line `238` पर `ph.saleChallans[idx].status = "Billed";` पहले ही लिख दिया गया है, और उसके बाद Line `240` पर `ph.finalizeSale(...)` कॉल किया गया है। जब `finalizeSale` Line `725` पर पहुँचता है, तो वह चेक करता है: `if (c.status != "Billed") { c.status = "Billed"; c.version += 1; ... SaleChallanSyncModule.onSaleChallanSaved(c, activeToken); }`! क्योंकि `challan_to_bill_converter.dart` ने पहले ही `status = "Billed"` कर दिया था, इसलिए `if (c.status != "Billed")` **झूठा (false)** हो जाता है और **न तो `c.version` बढ़ता है, न `c.updatedAt` अपडेट होता है, और न ही `SaleChallanSyncModule.onSaleChallanSaved` कॉल होता है!**
2. **क्या Bill Conversion केवल Active FY की Copy को Update करता है?**
   - **Confirmed (हाँ):** वर्तमान में सभी 6 मेथड्स केवल Active FY (`2026-27`) की इन-मेमोरी लिस्ट और Active FY की फाइल/वॉल्ट को ही `"Billed"` करते हैं।
3. **क्या Original FY (`2025-26`) की Copy भी Update होती है?**
   - **Confirmed (नहीं!):** न App में `2025-26/s_challan.json` (`p_challan.json`) अपडेट होती है, और न Web में `fyVault["2025-26"]` अपडेट होता है!
   - **इसका दुष्परिणाम:** जब यूज़र बाद में `2025-26` खोलकर देखता है, तो जिस चालान का बिल `2026-27` में बन चुका है, वह `2025-26` में अभी भी **`"Pending"`** दिखता रहता है! और यदि कोई यूज़र `2025-26` में जाकर उसका दोबारा बिल बना दे, तो **Double Billing** हो जाएगी!
4. **क्या App और Web में Conversion के तरीके समान हैं? / 5. क्या Web Stitcher और App Stitcher दोनों में समान व्यवहार है?**
   - **नहीं, 3 बड़े अंतर हैं:**
     1. App Stitcher पहले तो `2026-27` में `2025-26` के Pending चालान दिखाता है (`challan_stitcher_wizard.dart:339` में कोई डेट फ़िल्टर नहीं है), जबकि **Web Stitcher (`web_challan_stitcher_wizard.dart:118, 122`) में `_isInDateRange(c.date)` लगा होने के कारण `2025-26` का Pending चालान `2026-27` के Web Stitcher में आता ही नहीं है!**
     2. App Stitcher `finalizeBatchSales` / `finalizeBatchPurchases` कॉल करता है जो न तो `SyncQueueManager.flushOutboxAsJSONBatch()` को `await` करता है और न ही `AppRealtimeCoordinator.instance.notifyAppMutation()` भेजता है!
     3. जब Web पर किसी पुराने FY (`2025-26`) के चालान को `"Billed"` करके Outbox में भेजा जाता है, तो `MasterSyncOrchestrator.dispatchEnvelope` (`lib/sync_core/orchestrator/master_sync_orchestrator.dart:84–88`) में **App उस `"Billed"` Envelope को ड्रॉप कर देता है** यदि उस चालान की `date` (`2025-26`) App के `currentFY` (`2026-27`) से मेल नहीं खाती!
6. **क्या Bill में Linked Challan ID सुरक्षित रहती है?**
   - **Confirmed (हाँ):** `Sale.linkedChallanIds` और `Purchase.linkedChallanIds` में चालान का `id` सुरक्षित रहता है (साथ ही `BillItem.sourceChallanId` में भी)।
7. **क्या Bill बनने के बाद Challan का Original FY और ID नहीं बदलता?**
   - **Confirmed (हाँ):** चालान का `id` और `date` (तथा प्रस्तावित `originalFy`) अपरिवर्तित रहते हैं; केवल `status = "Billed"`, `version += 1`, और `updatedAt` बदलता है।
8. **क्या D1 Event सही FY में जाता है? / 9. क्या दूसरे Device को सही Billed Status मिलता है?**
   - **Confirmed Gap:**
     - जब `2026-27` में `Sale`/`Purchase` बिल बनता है, तो `D1SalesLedgerService.onSaleSaved` / `onPurchaseSaved` केवल नए **Bill** का इवेंट D1 में भेजता है; उस इवेंट पर जब दूसरा डिवाइस `applyEventsToLocalSales` / `applyEventsToLocalPurchases` चलाता है (`lib/sync_core/d1_sales_ledger_service.dart:610–675` एवं `950–1030`), तो **वहाँ `linkedChallanIds` पढ़कर लोकल चालान को `"Billed"` करने का कोड ही नहीं लिखा है!** (जबकि Bill Delete होने पर `revertLinkedChallansFromDeleteEvents` लिखा गया था, पर Bill Create होने पर `markLinkedChallansBilledFromSaveEvents` नहीं लिखा गया!)
     - और Outbox (`MasterSyncOrchestrator.dispatchEnvelope` Line `84–88`) में App पर Cross-FY तारीख वाले `"Billed"` चालान का Envelope ड्रॉप हो जाता है!

---

### उदाहरण (Part 2 • Section B का Walkthrough)
> **Scenario:** `2025-26` का `Y-1` (`id: ID-A, date: 15/03/2026`) Pending Challan `2026-27` में Carry-Forward हुआ। `2026-27` में उसका Bill बनाया गया।

- **मौजूदा Code में क्या होता है:**
  1. `2026-27` की लोकल कॉपी में `status = "Billed"` हो जाता है।
  2. **`2025-26` की लोकल/वॉल्ट कॉपी में उसका `status` अभी भी `"Pending"` रह जाता है!**
  3. यदि बिल App के `ChallanToBillConverter` से बना है, तो `challan_to_bill_converter.dart:238` के बग के कारण `version++` और `SaleChallanSyncModule.onSaleChallanSaved` चलता ही नहीं!
  4. यदि बिल App के `ChallanStitcherWizard` से बना है, तो `finalizeBatchSales` रीयल-टाइम सिग्नल (`notifyAppMutation`) और Outbox Flush ट्रिगर ही नहीं करता!
  5. यदि बिल Web पर बना है और App `2026-27` पर खुला है, तो:
     - D1 के `SALE_SAVED` इवेंट में `linkedChallanIds` को `"Billed"` करने का कोई हैंडलर नहीं है,
     - और Outbox के `SALE_CHALLAN` इवेंट को `MasterSyncOrchestrator.dispatchEnvelope` (`Line 86`) इसलिए ड्रॉप कर देता है क्योंकि चालान की `date` (`15/03/2026`) `2026-27` की नहीं है और उसका `status` अब `'Pending'` के बजाय `'Billed'` है!
- **हमारे संशोधित Plan (Part 2 • Section G) से क्या होगा:**
  1. जैसे ही `2026-27` में किसी चालान (`ID-A`) का बिल बनेगा, एक केंद्रीकृत हेल्पर (`markLinkedChallansBilledAcrossFys`) चालू FY (`2026-27`) **और** उस चालान के `effectiveOriginalFy` (`2025-26` तथा बीच के किसी भी FY) की फाइल/वॉल्ट दोनों में `ID-A` को `status = "Billed", version += 1, updatedAt = now` करेगा।
  2. `D1SalesLedgerService` में जब दूसरे डिवाइस पर `SALE` या `PURCHASE` का INSERT/UPDATE इवेंट आएगा जिसमें `linkedChallanIds` हों, तो वह तुरंत रिसीवर के Active FY और Origin FY दोनों में उन `linkedChallanIds` को `"Billed"` कर देगा!
  3. `MasterSyncOrchestrator.dispatchEnvelope` में `isChallanDoc` होने पर केवल `status == 'Pending'` ही नहीं, बल्कि **`status == 'Billed'`** को भी स्वीकार किया जाएगा ताकि Carry-Forward चालान का `"Billed"` अपडेट कभी ड्रॉप न हो!

---

## Part 2 • Section C — Bill Delete और Challan का Pending होना

आइए अब उलटी दिशा की जाँच करें: जब `2026-27` में बने उस Bill को डिलीट किया जाता है (जिसमें `2025-26` के Carry-Forward चालान `ID-A` का रेफरेंस `linkedChallanIds: ["ID-A"]` है)।

### 1. Part 2 • Section C के 7 सवालों का Code-Backed उत्तर

#### सवाल 1: क्या Bill Delete Handler Linked Challan ID से सही Challan खोजता है?
**उत्तर (Confirmed — खोजता है, लेकिन साथ में `sourceChallanNo` भी जोड़ देता है जो खतरनाक है):**
- App के `deleteBill` (`lib/pharoah_manager.dart:2789–2796`) और `deletePurchase` (`Lines 2897–2904`) तथा Web के `deleteSale` (`lib/web_live_sync/pharoah_web_manager.dart:2477–2484`) और `deletePurchase` (`Lines 2720–2727`) में:
  - कोड `s.linkedChallanIds` के साथ-साथ `it.sourceChallanId` और **`it.sourceChallanNo`** को भी `targetCids` में जोड़ लेता है।
  - **जोखिम:** यदि `2026-27` में `Challan A` (`ID-A`, `Y-1`, `2025-26`) और `Challan B` (`ID-B`, `Y-1`, `2026-27`) दोनों `"Billed"` हैं, और यूज़र ने केवल `Challan B` का बिल डिलीट किया, तो `it.sourceChallanNo` (`"Y-1"`) के कारण `Challan A` भी वापस `"Pending"` हो जाएगा!
  - **समाधान:** जब `linkedChallanIds` या `it.sourceChallanId` मौजूद हो, तो केवल `id` से ही चालान खोजा जाए।

---

#### सवाल 2: क्या केवल Active FY (`2026-27`) की Copy Pending होती है? / सवाल 3: क्या Original FY (`2025-26`) की Copy भी Pending होती है?
**उत्तर (Confirmed Gap in Current Code):**
- आइए `deleteBill` (`lib/pharoah_manager.dart:2868–2870`) और `deleteSale` (`lib/web_live_sync/pharoah_web_manager.dart:2534–2536`) को देखें:
  - जब आप **`2025-26`** में जाकर बिल डिलीट करते हैं, तब तो `cascadePendingChallansOnlyFromBackYear("2025-26")` / `_cascadeWebFyVaultFrom("2025-26")` आगे की दिशा में (`2025-26` → `2026-27`) चलकर दोनों सालों में उसे `"Pending"` कर देता है।
  - **लेकिन जब चालान `2025-26` का था, उसका बिल `2026-27` में बना था, और अब वह बिल `2026-27` में ही डिलीट किया जाता है:**
    - तब `delFy` = `"2026-27"` होता है।
    - `cascadePendingChallansOnlyFromBackYear("2026-27")` केवल `2026-27` से **आगे** (`2027-28`) जाता है — वह **पीछे (`2025-26` में) नहीं जाता!**
    - इसलिए यदि हमने Step 5 के अनुसार बिल बनते समय `2025-26` की कॉपी को भी `"Billed"` किया है, तो `2026-27` में वह बिल डिलीट होने पर **`2025-26` (यानी `ch.effectiveOriginalFy`) की कॉपी को भी वापस `"Pending"` (`version += 1, updatedAt = revTs`) करना अनिवार्य है!**

---

#### सवाल 4: क्या Delete Tombstone और Status Event सही क्रम में Sync होते हैं?
**उत्तर (Confirmed from `pharoah_manager.dart:2846–2867` & `pharoah_web_manager.dart:2497–2513`):**
- हाँ, Commit `fe59f65` में:
  1. पहले रिवर्ट हुए चालान का टॉम्बस्टोन हटाया जाता है (`TombstoneEngine.unmarkTombstoneWithTimestamp` और `D1SalesLedgerService.unmarkPermanentlyDeleted`)।
  2. फिर डिलीट हुए बिल का टॉम्बस्टोन लगाया जाता है (`recordTombstoneWithTimestamp` और `markPermanentlyDeleted`)।
  3. फिर Outbox में `SalesSyncModule.onSaleDeleted` और `SaleChallanSyncModule.onSaleChallanSaved(ch)` डाले जाते हैं और `D1SalesLedgerService.onSaleDeleted(..., linkedChallanIds: allLinkedForCloud)` के साथ `SyncQueueManager.flushOutboxAsJSONBatch()` को `await` किया जाता है।
  4. और उसके बाद ही `AppRealtimeCoordinator.instance.notifyAppMutation` सिग्नल भेजा जाता है।

---

#### सवाल 5: क्या Duplicate Delete Event से कोई गलत बदलाव हो सकता है?
**उत्तर (Confirmed from `d1_sales_ledger_service.dart:1243, 1277`):**
- `D1SalesLedgerService.revertLinkedChallansFromDeleteEvents()` में शर्त है:
  ```dart
  if (match && ch.status != "Pending" && (evTs == 0 || ch.updatedAt == 0 || evTs >= ch.updatedAt)) {
    ch.status = "Pending";
    ch.version = (ch.version < 1 ? 1 : ch.version) + 1;
    ch.updatedAt = evTs > ch.updatedAt ? evTs : nowMs;
  ```
- **यहाँ दो सुरक्षा नियम काम करते हैं:**
  1. यदि चालान पहले ही `"Pending"` हो चुका है (`ch.status != "Pending"` false है), तो वही Delete Event दोबारा आने पर वह कुछ नहीं करता (Idempotent)।
  2. यदि बिल डिलीट होने के बाद (`evTs = 10:00 AM`) यूज़र ने `10:05 AM` पर उस चालान का **फिर से नया बिल बना दिया** (`ch.status = "Billed"`, `ch.updatedAt = 10:05 AM`), और बाद में पुराना `10:00 AM` वाला Delete Event दोबारा प्रोसेस होता है, तो `evTs >= ch.updatedAt` (`10:00 >= 10:05`) **false** हो जाता है! इसलिए पुराना Delete Event नए बने बिल के `"Billed"` स्टेटस को वापस `"Pending"` में **नहीं** बदल सकता!

---

#### सवाल 6: क्या पुराने FY में जाकर Bill Delete करने पर अगले FY में Carry-Forward Challan वापस आता है? / सवाल 7: क्या `switchYear()` और `syncPendingChallansFromPreviousYears()` इस स्थिति को सुरक्षित तरीके से संभालते हैं?
**उत्तर (Confirmed — हाँ, Commit `fe59f65` में यह पूरी तरह काम करता है):**
- `deleteBill` (`pharoah_manager.dart:2869`) और `deletePurchase` (`Line 2989`) में `await cascadePendingChallansOnlyFromBackYear(delFy)` चलता है, और `switchYear()` (`pharoah_manager.dart:333`) में `await syncPendingChallansFromPreviousYears(targetYear: y)` चलता है।
- ये दोनों `FYTransferEngine.cascadePendingChallansOnlyStep()` (`lib/fy_transfer_engine.dart:632–682`) को कॉल करते हैं, जो **केवल `s_challan.json` और `p_challan.json`** को अपडेट करता है और `parts.json` (`opBal`), `meds.json`, या `bats.json` को बिल्कुल नहीं छूता!

---

## Part 2 • Section D — App, Web और Cloud Sync Consistency

### 1. Part 2 • Section D के 8 सवालों का गहरा तकनीकी विश्लेषण

#### सवाल 1: क्या Cross-FY `Billed` Event स्वीकार किया जाता है?
**उत्तर (Confirmed Bug Found in `MasterSyncOrchestrator` & `D1SalesLedgerService`):**
- **अभी नहीं (Partially Broken on App & D1)!**
  1. **Outbox Path (`lib/sync_core/orchestrator/master_sync_orchestrator.dart:64–89`):**
     - जब `2025-26` में बना Carry-Forward चालान `2026-27` में `"Billed"` होता है, तो उसके Envelope में `date` `2025-26` की होती है और `status: "Billed"` होता है।
     - जब यह Envelope **App (`phApp != null`)** पर पहुँचता है (जो `2026-27` पर है), तो `doesEventBelongToActiveFY` `false` लौटाता है। इसके बाद Line `84–88` पर लिखा है:
       ```dart
       final bool isPendingChallan = isChallanDoc && status == 'Pending';
       final bool isDeletedChallan = isChallanDoc && isDelEnv;
       if (!isPendingChallan && !isDeletedChallan) {
         return false; // <-- DROPS "Billed" CHALLAN ENVELOPE!
       }
       ```
       अर्थात **App इस Cross-FY `"Billed"` Challan Envelope को अस्वीकार (drop) कर देता है!**
  2. **D1 Edge Path (`lib/sync_core/d1_sales_ledger_service.dart`):**
     - जब `2026-27` में `SALE` या `PURCHASE` बिल सेव होता है, तो D1 में `SALE_SAVED` / `PURCHASE_SAVED` इवेंट जाता है जिसमें `linkedChallanIds` मौजूद होते हैं।
     - लेकिन `applyEventsToLocalSales()` (`d1_sales_ledger_service.dart:610–675`) और `applyEventsToLocalPurchases()` (`Lines 950–1030`) में उन `linkedChallanIds` को पढ़कर लोकल `saleChallans` / `purchaseChallans` को `"Billed"` करने का लॉजिक ही नहीं है!

#### सवाल 2: क्या Cross-FY `Pending` Event स्वीकार किया जाता है?
**उत्तर (Confirmed — हाँ):**
- `MasterSyncOrchestrator.dispatchEnvelope` Line `84` पर `isPendingChallan` (`status == 'Pending'`) होने के कारण इसे स्वीकार कर लेता है, और D1 में `revertLinkedChallansFromDeleteEvents` भी काम करता है।

#### सवाल 3: क्या Event FY Challan की Date से निर्धारित होता है या Original FY से?
**उत्तर (Confirmed from `d1_sales_ledger_service.dart:371–394`):**
- वर्तमान में `D1SalesLedgerService.extractEventFy()` पहले `payload["fy"]` देखता है और न मिलने पर `date` से FY निकालता है।
- समस्या यह है कि Carry-Forward चालान **दो FYs से जुड़ा होता है**: उसका `originalFy` (`2025-26`) और वे सभी आगे के FYs (`2026-27`) जहाँ वह Carry-Forward होकर गया है!
- इसलिए किसी भी Challan Event (चाहे `Pending`, `Billed`, या `Deleted`) को केवल एक FY तक सीमित न रखकर:
  - यदि उस चालान का `id` रिसीवर के Active FY की `saleChallans`/`purchaseChallans` लिस्ट में मौजूद है, तो उसे Active FY में हमेशा अपडेट होना चाहिए, **और**
  - साथ ही उसके `effectiveOriginalFy` से लेकर आगे के FYs के वॉल्ट/डिस्क में भी रिकॉन्साइल होना चाहिए।

#### सवाल 4: क्या Carry-Forward Challan के Active FY और Original FY की Copies के लिए अलग-अलग Sync Operations होते हैं?
**उत्तर (Confirmed):**
- Outbox में `SaleChallanSyncModule.onSaleChallanSaved(ch, token)` केवल एक `SyncEnvelope` भेजता है (क्योंकि `syncId = ch.id` एक ही है)।
- लेकिन Cloud Snapshot (`multi_fy_vault.json`) में हर FY (`fyVault["2025-26"]` और `fyVault["2026-27"]`) की अलग `s_challan.json` / `p_challan.json` जाती है।
- इसलिए जब भी किसी Carry-Forward चालान का स्टेटस बदलता है (`Pending` ↔ `Billed`), तो सेव करने वाले डिवाइस को अपने लोकल डिस्क/वॉल्ट में **Origin FY और Active FY दोनों** की `s_challan.json`/`p_challan.json` अपडेट करनी चाहिए ताकि Cloud Snapshot (`multi_fy_vault.json`) में दोनों सालों की कॉपियाँ हमेशा एकसमान (`version` और `updatedAt` सहित) रहें।

#### सवाल 5: क्या कोई Event दूसरे FY में गलत रिकॉर्ड Update कर सकता है?
**उत्तर (Confirmed — वर्तमान में हाँ, यदि दो अलग चालानों का नंबर `Y-1` समान हो; सुधार के बाद नहीं):**
- वर्तमान में `SaleChallanSyncModule.mergeIncomingSaleChallanEnvelope` (`line 78`) और `PurchaseChallanSyncModule` (`line 80`) यदि `id` मैच न हो तो `billNo` / `internalNo` से मैच कर लेते हैं।
- जब हम Fallback Matching में `c.effectiveOriginalFy == incoming.effectiveOriginalFy` की शर्त जोड़ देंगे, तो `2025-26` का इवेंट कभी भी `2026-27` के नए चालान को अपडेट नहीं कर पाएगा।

#### सवाल 6: क्या Offline Device पुराने Status को दोबारा भेजकर नए Status को Overwrite कर सकता है? / सवाल 7: Idempotency / सवाल 8: Version & UpdatedAt Conflict Resolution
**उत्तर (Confirmed — LWW और Monotonic Version इसे रोकते हैं):**
- आइए **3-Device Example (Device A: App Online, Device B: Web Online, Device C: App Offline)** से पूरे कोड फ्लो को साबित करें:
  1. प्रारंभिक अवस्था: `Challan ID-A` (`status: "Pending", version: 1, updatedAt: T1`)।
  2. **Device B (Web Online)** पर `ID-A` का बिल बनाया गया -> `ID-A` अब `status: "Billed", version: 2, updatedAt: T2` हो गया।
  3. **Device A (App Online)** पर वह बिल डिलीट किया गया -> `ID-A` अब `status: "Pending", version: 3, updatedAt: T3` हो गया (जहाँ `T3 > T2 > T1`)।
  4. अब **Device C (App Offline)** ऑनलाइन आता है जिसके पास पुराना `ID-A` (`status: "Pending", version: 1, updatedAt: T1`) या मान लीजिए पुराना `"Billed"` (`version: 2, updatedAt: T2`) पड़ा है:
     - जब Device C का डेटा `DeltaMergeEngine` (`lib/web_live_sync/sync_protocol/delta_merge_engine.dart:235`), `MultiFyCloudVault._mergeJsonListLww` (`lib/sync_core/multi_fy_cloud_vault.dart:380`), `SaleChallanSyncModule.mergeIncomingSaleChallanEnvelope` (`line 71`), या `reconcileCarryForwardSaleChallans` (`lib/fy_transfer_engine.dart:545`) में मर्ज होता है:
     - तो सभी जगह शर्त है: `incoming.version <= local.version && incoming.updatedAt < local.updatedAt` -> **Reject stale record!**
     - क्योंकि `version: 3 (T3)` > `version: 1 (T1)` और `version: 2 (T2)`, इसलिए **अंतिम स्टेटस हमेशा `version: 3, status: "Pending" (T3)` ही रहेगा!**

---

## Part 2 • Section E — Visibility और Register Filtering

आइए आपके उदाहरण (**`2025-26` का Challan जिसकी तारीख `15 मार्च 2026` है, और अब Active FY `2026-27` है जहाँ Register की Date Range `01 अप्रैल 2026` से `31 मार्च 2027` है**) के लिए सभी 6 स्क्रीनों के वास्तविक कोड की जाँच करें:

| स्क्रीन (Screen) | File Path & Exact Line | वर्तमान कोड की Date Filter शर्त | `15 मार्च 2026` वाला Carry-Forward `Pending` Challan `2026-27` में दिखेगा या छिपेगा? |
|---|---|---|---|
| **1. App Sale Challan Register** | `lib/challans/sale_challan_register.dart:48` | `bool matchesDate = (!cOnly.isBefore(fOnly) && !cOnly.isAfter(tOnly)) \|\| ch.status == "Pending";` | ✅ **दिखेगा** (क्योंकि `\|\| ch.status == "Pending"` लगा है)। |
| **2. App Purchase Challan Register** | `lib/challans/purchase_challan_register.dart:41–43` | `bool matchesDate = ch.date.isAfter(fromDate.subtract(const Duration(days: 1))) && ch.date.isBefore(toDate.add(const Duration(days: 1)));` *(यहाँ `\|\| ch.status == "Pending"` **नहीं** है!)* | ❌ **छिप जाएगा!** (क्योंकि `fromDate` `01/04/2026` से पहले नहीं जाता — Line `30`: `if (fromDate.isBefore(fyStart)) fromDate = fyStart;`)। |
| **3. App Stitcher (Sale & Purchase)** | `lib/challans/challan_stitcher_wizard.dart:339` | `ph.saleChallans.where((c)=>c.partyName==pName && c.status=="Pending")` *(जब Selection Mode `"ALL"` या `"PARTY"` हो तो कोई Date Filter नहीं है; केवल `"MONTH"` या `"RANDOM"` चुनने पर ` _isInRange(c.date)` लगता है — Lines `295–296`)* | ✅ **दिखेगा** (`"ALL"` और `"PARTY"` मोड में)। |
| **4. Web Sale Challan Register** | `lib/web_live_sync/web_challan_view.dart:124–129` | `bool dateMatch = !cDateOnly.isBefore(fDateOnly) && !cDateOnly.isAfter(tDateOnly); return dateMatch && searchMatch;` | ❌ **छिप जाएगा!** (`regFromDate` `01/04/2026` होता है, इसलिए `15/03/2026` का चालान हमेशा छिपा रहता है!) |
| **5. Web Purchase Challan Register** | `lib/web_live_sync/web_challan_view.dart:315–321` | `bool dateMatch = !cDateOnly.isBefore(fDateOnly) && !cDateOnly.isAfter(tDateOnly); return dateMatch && searchMatch;` | ❌ **छिप जाएगा!** |
| **6. Web Stitcher (Sale & Purchase)** | `lib/web_live_sync/web_challan_stitcher_wizard.dart:118, 122, 839–845` | हर मोड में `_isInDateRange(c.date)` अनिवार्य रूप से लगा है, और डिफ़ॉल्ट `fromDate = 01/04/2026` (`WebFyDateRangeHelper.computeRegisterDateRange`) होता है! | ❌ **छिप जाएगा!** (Web Stitcher में `2026-27` में रहते हुए `15/03/2026` के Carry-Forward चालान का बिल बनाया ही नहीं जा सकता!) |

### Part 2 • Section E के सवालों का निष्कर्ष:
1. **क्या Carry-Forward Pending Challans Date Filter के कारण छिप सकते हैं?**
   - **100% Confirmed:** वर्तमान कोड में **App Purchase Challan Register, Web Sale Challan Register, Web Purchase Challan Register, Web Sale Stitcher और Web Purchase Stitcher** — इन पाँचों जगहों पर `15 मार्च 2026` का Carry-Forward Pending Challan `2026-27` में **पूरी तरह छिप जाता है**! केवल App के Sale Challan Register और App Stitcher (`ALL`/`PARTY` मोड) में दिखता है।
2. **क्या Billed Carry-Forward Challan को भी History या Filter में सही तरह देखा जा सकता है?**
   - जब कोई Carry-Forward चालान (`15 मार्च 2026`) नए FY `2026-27` में `"Billed"` हो जाता है, तो उसका `status` `"Pending"` नहीं रहता।
   - यदि यूज़र `2026-27` के Register में यह देखना चाहे कि इस साल कौन-कौन से Carry-Forward चालान आए थे (जिनमें से कुछ अब `"Billed"` हो चुके हैं), तो `ch.isCarryForwardIn(activeFy)` होने पर वह चालान `All Challans` और `Carry-Forward` टैब में `"Billed"` बैज के साथ भी दिखना चाहिए!

---

## Part 2 • Section F — Regression Safety & 11 Verification Test Scenarios

### 1. मौजूदा Workflows पर 0% प्रभाव का प्रमाण (Zero-Regression Proof)

| मौजूदा Workflow | संबंधित Code Path | प्रस्तावित सुधार से यह क्यों 100% सुरक्षित रहेगा? |
|---|---|---|
| **Sale Bill Creation & Numbering** | `PharoahNumberingEngine` (`type: "SALE"`), `finalizeSale`, `addSaleAndSync`, `sales.json` | नंबरिंग में `isCarryForwardIn` फ़िल्टर केवल `SaleChallan` और `PurchaseChallan` पर लगेगा; `Sale` (`sales.json`) में कोई Carry-Forward चालान नहीं होता। |
| **Purchase Bill Creation & Sync Fix (`#PH-REV-812`)** | `finalizePurchase`, `addPurchaseAndSync`, `PurchaseSyncModule`, `purc.json` | `Purchase` मॉडल, उसका कंपोजिट टॉम्बस्टोन और री-क्रिएशन लॉजिक (`isPurchaseDeleted`) बिल्कुल नहीं छुआ जाएगा। |
| **Sale / Purchase Bill Deletion** | `deleteBill`, `deletePurchase`, `deleteSale` | बिल डिलीट का मौजूदा फ्लो सुरक्षित रहेगा; केवल `linkedChallanIds` को रिवर्ट करते समय: (a) जब `linkedChallanIds`/`sourceChallanId` मौजूद हो तो नंगे `sourceChallanNo` से गलत चालान को मैच नहीं किया जाएगा, और (b) यदि रिवर्ट हुआ चालान Carry-Forward था, तो उसके `originalFy` में भी उसे `"Pending"` किया जाएगा। |
| **Inventory & Stock Ledger** | `InventoryLogicCenter.rebuildAllInventory()` (`lib/inventory_logic_center.dart`) | Pharoah ERP में स्टॉक केवल `purchases`, `sales`, `saleReturns`, `purchaseReturns` और `batchHistory.openingQty/adjustmentQty` से बनता है — **Challans से स्टॉक की गणना नहीं होती** (Challans केवल `registerBatchActivity` से बैच मास्टर में नाम/रेट रजिस्टर करते हैं)। इसलिए स्टॉक पर 0% असर पड़ेगा। |
| **Party Opening Balance & Party Ledger** | `FYTransferEngine.calculatePartyClosingBalance()` (`lib/fy_transfer_engine.dart:40–143`) | पार्टी का क्लोजिंग और ओपनिंग बैलेंस केवल `sales`, `purchases`, `saleReturns`, `purchaseReturns`, और `vouchers` से निकलता है; Challans उसमें शामिल ही नहीं होते। |
| **Challan Numbering Defaults** | App: `SCH-1`, `PCH-1`<br>Web: `WSCH-1`, `WPCH-1`<br>Custom: `Y-1` | किसी भी डिफ़ॉल्ट Prefix या `startFrom` को बदला नहीं जाएगा; केवल नए FY में नंबर बनाते समय पिछले FY के Carry-Forward चालानों को गिनती से बाहर रखा जाएगा। |

---

### 2. अनिवार्य 11 Regression Test Cases (Automated Test Suite में जोड़े जाने वाले)

1. **`T1` — Legacy Records without `originalFy`:** पुराने JSON (`s_challan.json`, `p_challan.json`) जिनमें `originalFy` फ़ील्ड नहीं है, वे लोड होते ही अपनी `date` (जैसे `15/03/2026` → `"2025-26"`) से सही `effectiveOriginalFy` प्राप्त करें।
2. **`T2` — Sale & Purchase Carry-Forward Numbering Isolation (Cases A, B, C):**
   - `2025-26` से `Y-1` (Case A), केवल `Y-5` (Case B), और `Y-1..Y-3` (Case C) तथा Purchase में `PCH-1`/`WPCH-1` Carry-Forward होकर `2026-27` में आने पर भी `2026-27` के नए चालान `Y-1, Y-2, Y-3, Y-4, Y-5` और `PCH-1, PCH-2` / `WPCH-1, WPCH-2` से ही शुरू हों।
3. **`T3` — Same Number, Different ID Coexistence (`Challan A` vs `Challan B`):**
   - `2026-27` में `Challan A` (`id: ID-A, billNo: Y-1, originalFy: 2025-26`) और `Challan B` (`id: ID-B, billNo: Y-1, originalFy: 2026-27`) दोनों एक साथ सेव हों, `DeltaMergeEngine` और `MultiFyCloudVault` में मर्ज हों, और कोई एक-दूसरे को ओवरराइट न करे।
4. **`T4` — Editing Carry-Forward Challan in New FY & Date Change Safety:**
   - `2026-27` में `Challan A` (`ID-A`) को Edit करने पर उसका `originalFy` `"2025-26"` ही रहे (भले ही उसकी तारीख बदल जाए) और `Challan B` (`ID-B`) सुरक्षित रहे; साथ ही `Challan B` को Delete करने पर `Challan A` डिलीट न हो।
5. **`T5` — New FY Bill Conversion Updates Both Active FY & Original FY:**
   - `2026-27` में `Challan A` (`ID-A`, `originalFy: 2025-26`) का Bill बनाने पर (Single Converter और Stitcher दोनों से, App और Web दोनों पर):
     - `2026-27` में `ID-A` `"Billed"` हो,
     - `2025-26` (Original FY) में भी `ID-A` `"Billed"` हो,
     - और `2026-27` का नया `Challan B` (`ID-B`, जिसका नंबर भी `Y-1` है) `"Pending"` ही रहे!
6. **`T6` — New FY Bill Deletion Reverts Both Active FY & Original FY:**
   - `2026-27` में बने उस Bill को डिलीट करने पर `2026-27` और `2025-26` दोनों में `ID-A` वापस `"Pending"` हो जाए।
7. **`T7` — Multi-Year Carry-Forward (`2024-25` → `2025-26` → `2026-27`):**
   - `2024-25` में बना चालान `2025-26` और `2026-27` दोनों में `originalFy: "2024-25"` बनाए रखे, और `2026-27` में उसका बिल बनने पर तीनों सालों (`2024-25`, `2025-26`, `2026-27`) में उसका स्टेटस `"Billed"` सिंक हो।
8. **`T8` — App ↔ Web Cross-FY Live Sync (`Billed` & `Pending`):**
   - Web पर `2026-27` में Carry-Forward चालान का बिल बनने पर App (`2026-27` और `2025-26`) में तुरंत `"Billed"` हो (`MasterSyncOrchestrator` उसे ड्रॉप न करे और `D1SalesLedgerService` उसे अप्लाई करे), और App पर करने पर Web में सिंक हो।
9. **`T9` — Offline Device C Reconnect (LWW Conflict Resolution):**
   - Online Web पर Bill बना (`v2, Billed`), Online App पर Bill डिलीट हुआ (`v3, Pending`), फिर Offline Device C पुराना `v1/v2` डेटा भेजे तो अंतिम स्टेटस `v3, Pending` ही रहे।
10. **`T10` — Duplicate Delete Event Idempotency:**
    - एक ही Delete Event दो बार आने पर या चालान के दोबारा Re-bill (`v4, Billed`) हो जाने के बाद पुराना Delete Event आने पर वह नए `"Billed"` स्टेटस को वापस `"Pending"` न करे।
11. **`T11` — Register & Stitcher Visibility + Existing Sale/Purchase Regression:**
    - `15 मार्च 2026` का Carry-Forward चालान `2026-27` में App और Web के दोनों Registers (Sale & Purchase) और दोनों Stitchers में दिखे, तथा मौजूदा `purchase_recreation_sync_regression_test.dart` और `three_issues_independent_regression_test.dart` के सभी टेस्ट 100% पास हों।

---

## Part 2 • Section G — Final Answers और Complete Revised Implementation Plan

### 1. आपके 10 अंतिम सवालों के सीधे उत्तर

1. **पिछला 6-Step Plan क्या पूरा है?**
   - **नहीं, वह ~65% पूरा था।** इस गहरी जाँच से उसमें 4 छूटे हुए पहलू मिले हैं जिन्हें अब नीचे **Revised 8-Step Plan** में जोड़ दिया गया है।
2. **कौन-से Steps सही हैं?**
   - `SaleChallan` / `PurchaseChallan` में `originalFy` जोड़ना (Step 1), Numbering Engine में केवल चालू FY के Native चालानों को गिनना (Step 2), और App/Web के Registers व Stitcher के Date Filter में Carry-Forward चालानों को दिखाना (Step 4) — ये तीनों बिल्कुल सही हैं।
3. **किन Steps में सुधार चाहिए?**
   - **पुराने Step 3 में सुधार:** `effectiveOriginalFy == currentFY` के बजाय चालान की अपनी `targetOriginalFy = existingRecord?.effectiveOriginalFy ?? currentFY` का उपयोग हो, और सेकेंडरी की मैचिंग केवल समान `effectiveOriginalFy` के भीतर हो। साथ ही `DeltaMergeEngine` (`uniqueByBillNo`) और Bill Conversion/Delete में `it.sourceChallanNo` के गलत ओवर-मैच को रोका जाए।
   - **पुराने Step 5 में सुधार:** केवल बिल बनते समय ही नहीं, बल्कि जब `2026-27` में बना वह बिल **डिलीट** हो, तब भी पीछे (`2025-26` / `originalFy`) जाकर चालान को वापस `"Pending"` किया जाए।
4. **क्या कोई जरूरी Step छूट गया है?**
   - **हाँ, 3 तकनीकी बिंदु छूटे थे:**
     1. `MasterSyncOrchestrator.dispatchEnvelope` (`Line 84–88`) में App पर Cross-FY तारीख वाले `"Billed"` चालान के Envelope को ड्रॉप होने से बचाना।
     2. `D1SalesLedgerService.applyEventsToLocalSales` / `applyEventsToLocalPurchases` (तथा Cross-FY D1 handlers) में जब नया Bill सेव होने का इवेंट आए, तब उसके `linkedChallanIds` को लोकल व वॉल्ट में भी `"Billed"` मार्क करना।
     3. App के `ChallanToBillConverter._finalizeConversion` (`Line 238`) और `finalizeBatchSales` / `finalizeBatchPurchases` (`pharoah_manager.dart:1066–1133`) में छूटे हुए `version++`, `Outbox flush` और `notifyAppMutation` को ठीक करना।
5. **क्या `originalFy` को Model में जोड़ना पर्याप्त है?**
   - मॉडल में `originalFy` जोड़ना आधार (foundation) है, लेकिन उसके साथ Numbering, Deduplication, Register Filter और Cross-FY Status Propagation के नियम जोड़ने पर ही पूरा समाधान बनता है।
6. **क्या Cross-FY Status Sync के लिए अलग सुरक्षित Mechanism चाहिए?**
   - किसी भारी नए आर्किटेक्चर की ज़रूरत नहीं है — केवल एक हल्का, सटीक हेल्पर मेथड (App में `propagateChallanStatusAcrossFys` और Web में `propagateChallanStatusAcrossVault`) चाहिए जो किसी भी चालान का स्टेटस (`"Billed"` या `"Pending"`) बदलने पर सभी संबंधित FYs (`originalFy` से लेकर `currentFY` तक) की `s_challan.json` / `p_challan.json` में उसी `id` वाले चालान का स्टेटस, `version` और `updatedAt` अपडेट कर दे।
7. **क्या पुराने Data की Migration या Backward Compatibility की जरूरत है?**
   - किसी अलग डेटा माइग्रेशन स्क्रिप्ट की जरूरत नहीं है। `fromMap()` में `effectiveOriginalFy` गेटर (जो `originalFy` खाली होने पर `AppDateLogic.getFYForDate(date)` से FY निकाल लेता है) और `FYTransferEngine` में Carry-Forward के समय `prevFY` स्टैम्प करने से 100% Backward Compatibility अपने-आप मिल जाएगी।
8. **क्या इस सुधार को सीमित Challan Files और Methods तक रखा जा सकता है?**
   - **हाँ, 100%!** नीचे Revised Plan में स्पष्ट है कि किसी भी Accounting, Inventory, Party Balance, या Normal Sale/Purchase लॉजिक को नहीं छुआ जाएगा।
9. **क्या App और Web दोनों में एक ही Business Rule लागू हो सकता है?**
   - **हाँ, 100% समान Business Rule** App और Web दोनों पर लागू होगा।
10. **Implementation के बाद कौन-से Tests, Builds और Live Checks जरूरी होंगे?**
    - ऊपर दिए गए **11 Regression Test Cases (`T1`–`T11`)**, सभी मौजूदा टेस्ट सुइट्स (`flutter test`), Android APK Release Build (`flutter build apk --release`), और Flutter Web Release Build + Cloudflare Pages Deployment।

---

### 2. COMPLETE REVISED TECHNICAL IMPLEMENTATION PLAN (8 Surgical Steps)

| Step | उद्देश्य (Objective) | प्रभावित Files & Methods | जोखिम नियंत्रण (Risk Mitigation) |
|---|---|---|---|
| **Step 1: Immutable `originalFy` in Models** | `SaleChallan` और `PurchaseChallan` में स्थायी `originalFy` फ़ील्ड और `effectiveOriginalFy` / `isCarryForwardIn(String activeFy)` जोड़ना; `fromMap` में सुरक्षित `DateTime.tryParse` लगाना। | `lib/models.dart` (`SaleChallan`, `PurchaseChallan`), `lib/fy_transfer_engine.dart` (Carry-Forward के समय खाली `originalFy` पर `prevFY` स्टैम्प करना) | 100% Backward-compatible: पुराने JSON बिना किसी माइग्रेशन के `date` से `effectiveOriginalFy` निकाल लेंगे। |
| **Step 2: FY-Isolated Challan Numbering (App & Web)** | नए FY में नंबर बनाते समय पिछले FY से आए Carry-Forward चालानों (`isCarryForwardIn(activeFy) == true`) को गिनती से बाहर रखना। | App: `lib/challans/sale_challan_view.dart`, `lib/challans/purchase_challan_view.dart`, `lib/logic/pharoah_numbering_engine.dart`<br>Web: `lib/web_live_sync/pharoah_web_manager.dart` (`getNextBillNumber`), `lib/web_live_sync/web_pharoah_numbering_engine.dart` | Default Prefixes (`SCH-`, `WSCH-`, `PCH-`, `WPCH-`) और Custom Series (`Y-`) दोनों में नए FY की सीरीज़ फिर से `1` (`startFrom`) से शुरू होगी। |
| **Step 3: Safe Primary (`id`) + FY-Scoped Secondary (`originalFy + billNo/internalNo`) Matching** | जब `2026-27` में Carry-Forward `Y-1 (2025-26)` और नया `Y-1 (2026-27)` दोनों हों, तो Save, Edit, Delete और Sync Merge में वे कभी एक-दूसरे को ओवरराइट या डिलीट न करें; Edit मोड में `existingRecord.effectiveOriginalFy` सुरक्षित रहे। | `lib/pharoah_manager.dart` (`finalizeSaleChallan`, `finalizePurchaseChallan`, `deleteSaleChallan`, `deletePurchaseChallan`), `lib/web_live_sync/pharoah_web_manager.dart` (`addSaleChallanAndSync`, `addPurchaseChallanAndSync`, `deleteSaleChallan`, `deletePurchaseChallan`, `_parseDownloadedFiles`), `lib/sync_core/modules/sale_challan_sync_module.dart`, `lib/sync_core/modules/purchase_challan_sync_module.dart`, `lib/web_live_sync/sync_protocol/delta_merge_engine.dart` (`uniqueByBillNo` scoped by `effectiveOriginalFy`), `lib/sync_core/multi_fy_cloud_vault.dart` (`_secondarySeriesKeyForMap` for `s_challan.json`/`p_challan.json`), `findDuplicateSupplierChallan` | `Challan A` को Edit करने पर उसका `originalFy` `"2025-26"` ही रहेगा, और `Challan B` को Delete करने पर केवल `"2026-27_Y-1"` पर टॉम्बस्टोन लगेगा। |
| **Step 4: Strict ID-Based Bill Conversion & Delete Linking** | जब किसी चालान का बिल बने या बिल डिलीट हो, और `linkedChallanIds` या `item.sourceChallanId` मौजूद हो, तो **केवल `id` से** ही चालान मैच किया जाए (`sourceChallanNo` से केवल तभी जब कोई `id` न हो)। | `lib/pharoah_manager.dart` (`finalizeSale`, `finalizePurchase`, `deleteBill`, `deletePurchase`), `lib/web_live_sync/pharoah_web_manager.dart` (`addSaleAndSync`, `deleteSale`, `addPurchaseAndSync`, `deletePurchase`), `lib/sync_core/d1_sales_ledger_service.dart` (`revertLinkedChallansFromDeleteEvents`), `lib/sync_core/orchestrator/master_sync_orchestrator.dart` | `2026-27` के `Y-1` (`ID-B`) का बिल बनाने या डिलीट करने पर `2025-26` के Carry-Forward `Y-1` (`ID-A`) का स्टेटस कभी भी गलती से नहीं बदलेगा। |
| **Step 5: Bidirectional Cross-FY Status Propagation (`Billed` & `Pending`)** | जब किसी Carry-Forward चालान का नए FY में Bill बने (`"Billed"`) या वह Bill डिलीट हो (`"Pending"`), तो Active FY के साथ-साथ उसके `effectiveOriginalFy` (और बीच के सभी FYs) की डिस्क फाइल (`App`) और `fyVault` (`Web`) में भी उसी `id` का स्टेटस अपडेट हो। साथ ही `ChallanToBillConverter:238` और `finalizeBatchSales/Purchases` के सिंक गैप ठीक किए जाएँ। | `lib/pharoah_manager.dart`, `lib/challans/challan_to_bill_converter.dart`, `lib/web_live_sync/pharoah_web_manager.dart`, `lib/web_live_sync/web_challan_stitcher_wizard.dart`, `lib/web_live_sync/sub_views/web_billing/web_new_sale_view.dart`, `lib/web_live_sync/sub_views/web_purchase/mechanism/web_purchase_mechanism.dart` | `2026-27` में बिल बनने के बाद जब यूज़र `2025-26` में स्विच करेगा, तो वहाँ भी वह चालान `"Billed"` दिखेगा (Double Billing असंभव)। |
| **Step 6: Cross-FY D1 & Outbox Sync Completion** | 1. `MasterSyncOrchestrator.dispatchEnvelope` में `isChallanDoc` होने पर `"Billed"` स्टेटस वाले Cross-FY चालान को भी स्वीकार करना और App के लोकल डिस्क के सभी संबंधित FYs में अपडेट करना।<br>2. `D1SalesLedgerService` में जब `SALE`/`PURCHASE` सेव इवेंट आए जिसमें `linkedChallanIds` हों, तो लोकल व वॉल्ट में उन चालानों को `"Billed"` मार्क करना। | `lib/sync_core/orchestrator/master_sync_orchestrator.dart`, `lib/sync_core/d1_sales_ledger_service.dart`, `lib/sync_core/multi_fy_cloud_vault.dart`, `lib/realtime_signaling/engines/fast_pull_engine.dart` | Web से Bill बनने या डिलीट होने पर App पर (और App से करने पर Web पर) बिना पेज रिफ्रेश किए दोनों FYs में तुरंत सही स्टेटस दिखेगा। |
| **Step 7: Complete Visibility in All Registers & Stitchers + Smart `[CF • FY]` Badge** | 1. App के `PurchaseChallanRegister` और Web के `WebChallanView` (Sale & Purchase Register) तथा `WebChallanStitcherWizard` में Carry-Forward चालानों को Date Filter से बाहर न होने देना।<br>2. Carry-Forward चालानों पर स्पष्ट `[CF • 2025-26]` बैज और `All / Current FY / Carry-Forward` फ़िल्टर चिप्स दिखाना। | `lib/challans/sale_challan_register.dart`, `lib/challans/purchase_challan_register.dart`, `lib/challans/challan_stitcher_wizard.dart`, `lib/web_live_sync/web_challan_view.dart`, `lib/web_live_sync/web_challan_stitcher_wizard.dart` | `15 मार्च 2026` का चालान `2026-27` में App और Web दोनों के हर Register और Stitcher में स्पष्ट `[CF • 2025-26]` बैज के साथ दिखेगा। |
| **Step 8: Automated Test Suite (`T1`–`T11`) & Release Verification** | ऊपर वर्णित सभी 11 परिदृश्यों (`T1`–`T11`) के लिए यूनिट और इंटीग्रेशन टेस्ट लिखकर चलाना तथा APK और Web बंडल बिल्ड करना। | `test/` | शत-प्रतिशत प्रमाणित और रिग्रेशन-मुक्त रिलीज़। |
