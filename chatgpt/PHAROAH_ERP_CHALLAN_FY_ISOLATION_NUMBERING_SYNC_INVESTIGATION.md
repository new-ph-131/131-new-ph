# PHAROAH ERP — COMPLETE CHALLAN FY ISOLATION, NUMBERING & CROSS-FY LIVE SYNC INVESTIGATION

> **Investigation Scope & Ground Rules:**
> - यह रिपोर्ट सीधे `131-new-ph` (Branch: `main`, Current HEAD: `fe59f65`, Compared against Commit: `0a02674`) के वास्तविक **App (`lib/`)** और **Web (`lib/web_live_sync/`)** Source Code को पढ़कर तैयार की गई है।
> - आपके निर्देशानुसार **कोई भी Code Change, Refactoring, Migration या नया Implementation नहीं किया गया है** — यह 100% Evidence-Based Investigation, Verification और Architectural Explanation है।
> - इसमें **Sale Challan** और **Purchase Challan** दोनों का App तथा Web पर अलग-अलग Call Flow, Numbering Engine, Storage Format, Sync Pipeline और Edge Cases शामिल हैं।

---

## Section A — Carry-Forward Challan और New FY Numbering Investigation (Part 1)

### 1. मुख्य निष्कर्ष (Executive Verdict — Confirmed from Code)
**हाँ (100% Confirmed):** वर्तमान Code में जब पुराने FY (जैसे `2025-26`) का कोई `Pending` Challan नए FY (`2026-27`) में Carry-Forward होकर आता है, तो **वह नए FY की Challan Numbering Series को सीधे प्रभावित (pollute/collide) करता है** — बशर्ते उसका Prefix नए FY में इस्तेमाल होने वाले Prefix से मेल खाता हो।

इसका मूल कारण यह है कि:
1. **Carry-Forward Engine (`FYTransferEngine.computeCarryForwardFromFiles`)** पुराने FY के `Pending` Challans को नए FY की `s_challan.json` और `p_challan.json` फाइल में **उसी मुख्य लिस्ट का सामान्य सदस्य बनाकर** कॉपी कर देता है।
2. **App का `PharoahNumberingEngine.getNextNumber()`** और **Web का `WebPharoahNumberingEngine.getNextNumber()`** — दोनों ही नंबर बनाते समय `currentList` (`ph.saleChallans` / `ph.purchaseChallans` या `webPh.saleChallans` / `webPh.purchaseChallans`) के **प्रत्येक तत्व (every item)** को स्कैन करते हैं।
3. **दोनों में से कोई भी Numbering Engine न तो `item.date` देखता है, न `creationFY` / `originalFy` देखता है, और न ही यह जाँचता है कि वह Challan पुराने FY से Carry-Forward होकर आया है या चालू FY में नया बना है।** वे केवल `prefix` मैच करके नंबर निकालते हैं और Gap-Filling + `last + 1` चला देते हैं।

---

### 2. आपके 9 प्रश्नों का App और Web के अलग-अलग Source Code से प्रमाणित उत्तर

#### प्रश्न 1: Sale Challan Number Generate करने का वास्तविक Logic कहाँ है?
- **App (Mobile/Desktop):**
  - **Call Site:** `lib/challans/sale_challan_view.dart` → `_SaleChallanViewState._initChallanFlow()` (Lines `44–54`):
    ```dart
    var series = ph.getDefaultSeries("CHALLAN");
    String nextNo = await PharoahNumberingEngine.getNextNumber(
      type: "CHALLAN",
      companyID: ph.activeCompany!.id,
      prefix: series.prefix,
      startFrom: series.startNumber,
      currentList: ph.saleChallans,
    );
    ```
  - **Default Series Definition:** `lib/pharoah_manager.dart` → `getDefaultSeries("CHALLAN")` (Lines `3569–3636`): यदि `series.json` में कोई कस्टम `"CHALLAN"` सीरीज़ नहीं है, तो यह fallback में `prefix: "SCH-"`, `startNumber: 1` (Line `3616–3617`, `3634`) लौटाता है।
  - **Engine Implementation:** `lib/logic/pharoah_numbering_engine.dart` → `PharoahNumberingEngine.getNextNumber()` (Lines `8–67`)।

- **Web (`web_live_sync`):**
  - **Active UI Call Site:** `lib/web_live_sync/sub_views/web_challans/web_sale_challan_view.dart` → `_WebSaleChallanViewState._initChallanFlow()` (Line `69`):
    ```dart
    String nextNo = webPh.getNextBillNumber("CHALLAN", "SCH-", 101);
    ```
    *(नोट: `lib/web_live_sync/sub_views/web_challans/sale_challan/logic/sale_challan_controller.dart` Line `39` में भी `webPh.getNextBillNumber("CHALLAN", "WSCH-", 1)` है, परंतु `WebChallanHub` Line `43` पर `"SALE_CHALLAN_ENTRY"` सीधे `WebSaleChallanView` को खोलता है।)*
  - **Manager Wrapper:** `lib/web_live_sync/pharoah_web_manager.dart` → `getNextBillNumber()` (Lines `4110–4177`):
    - यह पहले `numberingSeries` में `"CHALLAN"` खोजता है। यदि न मिले तो `defaultPrefix = "SCH-"` और `defaultStart = 101` लेता है।
    - **किंतु तुरंत बाद (Lines `4132–4134`)** इसमें एक Hardcoded Override लगा है:
      ```dart
      } else if ((type == "CHALLAN" || type == "SALE_CHALLAN") && prefix.trim().toUpperCase() == "SCH-") {
        prefix = "WSCH-";
        start = 1;
      }
      ```
      अर्थात यदि Prefix `"SCH-"` है, तो Web उसे जबरन बदलकर **`prefix = "WSCH-"`** और **`start = 1`** कर देता है! फिर `targetList = saleChallans` (Line `4162`) लेकर `WebPharoahNumberingEngine.getNextNumber()` (Line `4172`) को कॉल करता है।
  - **Engine Implementation:** `lib/web_live_sync/web_pharoah_numbering_engine.dart` → `WebPharoahNumberingEngine.getNextNumber()` (Lines `12–75`)।

---

#### प्रश्न 2: Purchase Challan Number Generate करने का वास्तविक Logic कहाँ है?
Purchase Challan में दो नंबर होते हैं:
1. **`internalNo` (Inward ID):** सिस्टम द्वारा ऑटो-जनरेटेड (`PCH-1` या `WPCH-1`)।
2. **`billNo` (Supplier Ref No):** सप्लायर के कागज़ पर लिखा चालान नंबर (यूज़र द्वारा मैन्युअली टाइप किया जाता है)।

`internalNo` जनरेट करने का वास्तविक Logic:
- **App (Mobile/Desktop):**
  - **Call Site:** `lib/challans/purchase_challan_view.dart` → `_PurchaseChallanViewState._initInwardFlow()` (Lines `46–52`):
    ```dart
    String nextNo = await PharoahNumberingEngine.getNextNumber(
      type: "CHALLAN_PUR",
      companyID: ph.activeCompany!.id,
      prefix: "PCH-",
      startFrom: 1,
      currentList: ph.purchaseChallans,
    );
    ```
    *(यहाँ `getDefaultSeries` भी कॉल नहीं होता; सीधे `"PCH-"` और `startFrom: 1` Hardcoded पास किया गया है।)*
  - **Engine Implementation:** `lib/logic/pharoah_numbering_engine.dart` → `PharoahNumberingEngine.getNextNumber()` (Lines `28–29`: `if (type == "PURCHASE" || type == "CHALLAN_PUR") idToParse = item.internalNo;`)।

- **Web (`web_live_sync`):**
  - **Call Site:** `lib/web_live_sync/sub_views/web_challans/web_purchase_challan_view.dart` → `_WebPurchaseChallanViewState._initChallanFlow()` (Line `71`):
    ```dart
    String nextNo = webPh.getNextBillNumber("PURCHASE_CHALLAN", "WPCH-", 1);
    ```
  - **Manager Wrapper:** `lib/web_live_sync/pharoah_web_manager.dart` → `getNextBillNumber()` (Lines `4129–4131`, `4163–4164`):
    - यदि कोई सीरीज़ `"PCH-"` लौटाए तो भी यह उसे बदलकर **`prefix = "WPCH-"`** और **`start = 1`** कर देता है, और `targetList = purchaseChallans` को `WebPharoahNumberingEngine.getNextNumber()` में भेजता है।
  - **Engine Implementation:** `lib/web_live_sync/web_pharoah_numbering_engine.dart` → `WebPharoahNumberingEngine.getNextNumber()` (Lines `29–30`: `else if (item is PurchaseChallan) { idToParse = item.internalNo; }`)।

---

#### प्रश्न 3: क्या App और Web एक ही Numbering Engine इस्तेमाल करते हैं या अलग-अलग?
**Confirmed:** App और Web **दो अलग-अलग फाइलों/क्लासों** का उपयोग करते हैं, लेकिन दोनों का **Core Algorithm (Prefix Match + Sequential Gap-Filling + `last + 1`) समान** है, जबकि **Default Prefixes अलग-अलग** हैं:

| पहलू | App (`PharoahNumberingEngine`) | Web (`WebPharoahNumberingEngine` + `getNextBillNumber`) |
|---|---|---|
| **File Path** | `lib/logic/pharoah_numbering_engine.dart` | `lib/web_live_sync/web_pharoah_numbering_engine.dart` |
| **Method Signature** | `Future<String> getNextNumber(...)` (Async) | `String getNextNumber(...)` (Sync) |
| **Sale Challan Default Prefix** | `SCH-` (`startFrom: 1`) (या Custom Series जैसे `Y-`) | `WSCH-` (`startFrom: 1`) — यदि Custom Series का Prefix `SCH-` नहीं है (जैसे `Y-`), तो दोनों पर `Y-` रहता है |
| **Purchase Challan Default Prefix** | `PCH-` (`startFrom: 1`) (Hardcoded) | `WPCH-` (`startFrom: 1`) |
| **SharedPreferences Pointer** | `counterKey = 'lastID_${type}_${prefix}_${companyID}_$currentFY'` बनाता तो है (Line `20`), **लेकिन `getNextNumber()` के अंदर इस `counterKey` को कभी पढ़ता (read) ही नहीं है!** (Dead variable in `getNextNumber`) | कोई `SharedPreferences` counter इस्तेमाल नहीं करता; केवल in-memory `currentList` स्कैन करता है। |

---

#### प्रश्न 4: Number Generate करते समय क्या Current FY की पूरी Challan List Scan होती है?
**Confirmed (हाँ):**
- **App में:** `PharoahNumberingEngine.getNextNumber()` को `currentList: ph.saleChallans` (Sale Challan के लिए) और `currentList: ph.purchaseChallans` (Purchase Challan के लिए) पास किया जाता है। Line `24` (`for (var item in currentList)`) इस पूरी लिस्ट को शुरू से अंत तक स्कैन करता है।
- **Web में:** `WebPharoahNumberingEngine.getNextNumber()` को `currentList: webPh.saleChallans` और `currentList: webPh.purchaseChallans` पास किया जाता है। Line `20` (`for (var item in currentList)`) इस पूरी लिस्ट को स्कैन करता है।

---

#### प्रश्न 5: क्या Carry-Forward Challans भी उस List में शामिल होकर अगला Number निर्धारित करते हैं?
**Confirmed (हाँ, 100%):**
आइए पूरे डेटा फ्लो से इसे साबित करें:
1. जब नया FY (`2026-27`) शुरू होता है या Carry-Forward सिंक चलता है, तो `lib/fy_transfer_engine.dart` → `computeCarryForwardFromFiles()` (Lines `360–364` एवं `473–474`) पुराने FY (`2025-26`) की `s_challan.json` और `p_challan.json` से सभी `status == "Pending" && isDeleted != 1` वाले चालान निकालता है:
   ```dart
   List<SaleChallan> pendingSaleChallans = oldSaleChallans
       .where((c) => c.status == "Pending" && c.isDeleted != 1)
       .toList();
   ```
2. फिर `reconcileCarryForwardSaleChallans()` / `reconcileCarryForwardPurchaseChallans()` (Lines `20–106`) या `transferData()` (Lines `959–966`) उन्हें **सीधे नए FY (`2026-27`) की `s_challan.json` और `p_challan.json` फाइल में सेव कर देता है**।
3. जब App (`loadAllData`, `lib/pharoah_manager.dart` Lines `565–571`) या Web (`_parseDownloadedFiles`, `lib/web_live_sync/pharoah_web_manager.dart` Lines `1053–1083`) नए FY (`2026-27`) को लोड करता है, तो `saleChallans` और `purchaseChallans` लिस्ट में **पुराने FY के Carry-Forward Challans भी लोड हो जाते हैं**।
4. जब यूज़र नए FY (`2026-27`) में नया Challan बनाने के लिए स्क्रीन खोलता है, तो `PharoahNumberingEngine.getNextNumber()` और `WebPharoahNumberingEngine.getNextNumber()` उसी `saleChallans` / `purchaseChallans` लिस्ट को स्कैन करते हैं।
5. क्योंकि Carry-Forward Challan उसी लिस्ट में मौजूद है और उसका `billNo` / `internalNo` (जैसे `SCH-1`, `Y-1`, `WSCH-1`, `PCH-1`, `WPCH-1`) उसी `prefix` से शुरू होता है, इसलिए Line `45–48` (App) और Line `54–59` (Web) उसका नंबर `existingNumbers` लिस्ट में जोड़ लेते हैं!

---

#### प्रश्न 6: क्या Numbering Engine Challan की Creation FY, Original FY, Date, Status या किसी दूसरे आधार पर पहचान करता है?
**Confirmed (बिल्कुल नहीं):**
- `lib/logic/pharoah_numbering_engine.dart` (Lines `24–50`) और `lib/web_live_sync/web_pharoah_numbering_engine.dart` (Lines `20–61`) दोनों का कोड देखने पर स्पष्ट है कि:
  - **न `item.date` चेक होता है** (यह नहीं देखा जाता कि चालान की तारीख `2025-26` की है या `2026-27` की)।
  - **न `item.status` चेक होता है** (`Pending` और `Billed` दोनों गिने जाते हैं)।
  - **न कोई `originalFy` / `createdFy` / `isCarryForward` चेक होता है।**
  - केवल एक ही शर्त चेक होती है: `if (upperId.startsWith(upperPrefix))` -> उसके आगे का पूर्णांक (`int.tryParse(numPart)`) निकालो और `existingNumbers` में डाल दो।

---

#### प्रश्न 7: क्या पुराने FY से आए Challan और नए FY में बनाए गए Original Challan के बीच Code में कोई स्पष्ट अंतर रखा गया है?
**Confirmed (कोई अलग फ़ील्ड या फ्लैग नहीं है):**
- `lib/models.dart` में `SaleChallan` (Lines `661–719`) और `PurchaseChallan` (Lines `721–755`) के मॉडल में केवल ये फ़ील्ड्स हैं:
  - `SaleChallan`: `id`, `billNo`, `partyId`, `date`, `partyName`, `partyGstin`, `partyState`, `items`, `totalAmount`, `status`, `salesmanName`, `remarks`, `sigHistory`, `isSigned`, `updatedAt`, `version`, `isDeleted`
  - `PurchaseChallan`: `id`, `internalNo`, `billNo`, `partyId`, `date`, `distributorName`, `items`, `totalAmount`, `status`, `remarks`, `updatedAt`, `version`, `isDeleted`
- **न तो मॉडल में `originalFy` / `sourceFy` है, न `carriedForward: true` फ्लैग है, और न ही `currentFY` है।**
- पूरे कोडबेस में पुराने FY के चालान को पहचानने का एकमात्र अप्रत्यक्ष (indirect) तरीका उसकी `date` है (`ch.date.isBefore(fyStart)` — जिसका उपयोग `FYTransferEngine.reconcileCarryForwardSaleChallans` Line `29` में करता है: `!c.date.isBefore(targetFyStart)` से वह पहचानता है कि कौन-सा चालान नए FY का native है और कौन-सा पुराने FY से आया है)। लेकिन Numbering Engine इस `date` चेक का उपयोग **नहीं** करता!

---

#### प्रश्न 8: क्या Delete, Modify, Re-create या Bill Conversion के बाद Numbering फिर से प्रभावित हो सकती है?
**Confirmed (हाँ, क्योंकि दोनों Engines "Gap-Filling" पर काम करते हैं):**
Numbering Engine किसी स्थायी बढ़ते हुए काउंटर (monotonic counter) का उपयोग नहीं करता, बल्कि हर बार मौजूदा लिस्ट में **सबसे छोटा खाली नंबर (First Available Gap from `startFrom`)** खोजता है (`for (int i = startFrom; i <= existingNumbers.last; i++) if (!existingNumbers.contains(i)) return "$prefix$i";`):
1. **Delete करने पर:** यदि नए FY में `Y-1`, `Y-2`, `Y-3` मौजूद हैं और आपने `Y-1` (चाहे वह Carry-Forward हो या नया) डिलीट कर दिया, तो अगली नई एंट्री सीधे `Y-4` नहीं बनेगी, बल्कि खाली जगह भरने के लिए **`Y-1`** बनेगी!
2. **Bill Conversion के बाद (अगले और तीसरे FY में प्रभाव):**
   - मान लीजिए `2025-26` का Pending Challan `Y-1` Carry-Forward होकर `2026-27` में आया।
   - `2026-27` में आपने `Y-1` का Bill बना दिया। अब `2026-27` की `s_challan.json` में `Y-1` का `status = "Billed"` हो गया, लेकिन **वह `2026-27` की `saleChallans` लिस्ट में अभी भी मौजूद है**। इसलिए पूरे `2026-27` के दौरान Numbering Engine `Y-1` को occupied मानता रहेगा।
   - जब अगला साल `2027-28` शुरू होगा, तब `Y-1` क्योंकि अब `"Billed"` हो चुका है, वह `2027-28` में Carry-Forward नहीं होगा।
3. **Purane FY का Bill Delete होकर Challan वापस Pending होने पर (Cross-FY Re-entry):**
   - मान लीजिए `2025-26` में `Y-2` पहले `"Billed"` था, इसलिए `2026-27` शुरू होते समय `2026-27` में नहीं आया।
   - `2026-27` में आपने नया Challan बनाया तो उसे `Y-1` (या `Y-2`) मिल गया।
   - अब यदि आप `2025-26` में जाकर पुराना Bill डिलीट करते हैं, तो `Y-2` वापस `"Pending"` होकर `2026-27` में Cascade होकर आ जाता है!
   - इस स्थिति में:
     - `2026-27` में **एक ही Challan Number (`Y-2`) के दो अलग-अलग Challans** (एक `2025-26` वाला जिसका `id` पुराना है, और एक `2026-27` में बना नया जिसका `id` अलग है) एक साथ लिस्ट में आ सकते हैं!
     - और इससे भी गंभीर: यदि आप `2026-27` में किसी चालान को सेव करते हैं (`finalizeSaleChallan`, `lib/pharoah_manager.dart` Line `1148`, `1156` या `addSaleChallanAndSync`, `lib/web_live_sync/pharoah_web_manager.dart` Line `2902`), तो वहाँ यह कोड लिखा है:
       ```dart
       saleChallans.removeWhere((c) => c.id == cId || (cleanBNo.isNotEmpty && c.billNo.trim().toUpperCase() == cleanBNo));
       ```
       **अर्थात `billNo` समान होने के कारण नए FY का चालान सेव करते समय वह पुराने FY से Carry-Forward होकर आए उसी `billNo` वाले चालान को मेमोरी और फाइल से मिटा (overwrite) सकता है!** (यही खतरा `PurchaseChallan` में `internalNo` पर Line `1247` और Web Line `3013` पर भी है!)

---

#### प्रश्न 9: क्या Sale और Purchase दोनों में यही समस्या है या दोनों का व्यवहार अलग है?
**Confirmed:**
- **दोनों में बिल्कुल यही समस्या है**, लेकिन दोनों में जिस फ़ील्ड पर टकराव होता है और जो Prefix इस्तेमाल होता है, उसमें यह सूक्ष्म अंतर है:
  1. **Sale Challan:**
     - नंबर फ़ील्ड `billNo` है।
     - App डिफ़ॉल्ट `SCH-` (`startFrom: 1`) इस्तेमाल करता है (या `numberingSeries` में सेट किया गया कस्टम Prefix, जैसे `Y-`)।
     - Web में यदि Prefix `SCH-` हो तो `getNextBillNumber` उसे `WSCH-` (`startFrom: 1`) में बदल देता है, लेकिन यदि आपने कस्टम Series (जैसे `Y-`) बनाई है, तो App और Web दोनों `Y-` इस्तेमाल करते हैं।
  2. **Purchase Challan:**
     - ऑटो-जनरेटेड नंबर फ़ील्ड **`internalNo` (Inward ID)** है, जबकि `billNo` सप्लायर का मैन्युअल रेफरेंस नंबर है।
     - App में `internalNo` का Prefix हमेशा Hardcoded **`PCH-`** (`startFrom: 1`) है (`lib/challans/purchase_challan_view.dart` Line `49`)।
     - Web में `internalNo` का Prefix हमेशा **`WPCH-`** (`startFrom: 1`) है (`lib/web_live_sync/sub_views/web_challans/web_purchase_challan_view.dart` Line `71`)।
     - इसके अलावा Purchase Challan में एक **अतिरिक्त टकराव (`findDuplicateSupplierChallan`)** भी है: जब पुराने FY का कोई Pending Purchase Challan नए FY में Carry-Forward होकर आता है और सप्लायर नए साल में फिर से अपने चालान नंबर `1` या `101` से माल भेजता है, तो `findDuplicateSupplierChallan` (`ph.purchaseChallans` में समान `partyId` + समान `billNo` खोजने वाला फंक्शन) पुराने साल के Carry-Forward चालान से टकराकर `"Ye challan #... already purchase challan me entry ho chuka hai!"` की त्रुटि दे सकता है यदि सप्लायर ने नए साल में अपना चालान नंबर फिर से `1` से शुरू किया हो!

---

## Section B — App और Web की Numbering का Case-by-Case Comparison (Part 2)

यहाँ हम दोनों स्थितियों (1. जब आपकी कस्टम Series `Y-` है, और 2. जब सिस्टम का Default Prefix `SCH-`/`WSCH-` या `PCH-`/`WPCH-` है) के लिए आपके तीनों Cases (`Case A`, `Case B`, `Case C`) का सटीक व्यवहार कोड के अनुसार दिखा रहे हैं:

### Case A — पुराना `Pending` Challan `Y-1` (`2025-26`) Carry-Forward हुआ, और `2026-27` में पहली नई Entry बनाई गई

#### 1. यदि कस्टम Series Prefix `Y-` (`startNumber: 1`) है (या समान Prefix वाले Carry-Forward Challans हैं):
- `2026-27` की `saleChallans` लिस्ट में अभी: `[Y-1 (date: 2025-26, status: Pending)]` है।
- **App में `2026-27` का पहला नया Challan बनाते समय:**
  - `PharoahNumberingEngine.getNextNumber` `ph.saleChallans` को स्कैन करेगा।
  - उसे `Y-1` मिल जाएगा (`existingNumbers = [1]`)।
  - `startFrom = 1` से लूप चलेगा: `1` पहले से मौजूद है, इसलिए वह `existingNumbers.last + 1` यानी **`Y-2`** देगा!
- **Web में `2026-27` का पहला नया Challan बनाते समय:**
  - `WebPharoahNumberingEngine.getNextNumber` `webPh.saleChallans` को स्कैन करेगा।
  - उसे भी `Y-1` मिल जाएगा (`existingNumbers = [1]`)।
  - इसलिए Web भी पहली नई एंट्री को **`Y-2`** देगा!

#### 2. यदि सिस्टम के Default Prefixes (`App = SCH- / PCH-`, `Web = WSCH- / WPCH-`) इस्तेमाल हो रहे हैं:
- मान लीजिए `2025-26` का Pending Challan **App** पर बना था, तो उसका नंबर `SCH-1` (या Purchase में `PCH-1`) है।
  - अब `2026-27` में **App** पर पहली नई एंट्री बनाएँगे -> `ph.saleChallans` में `SCH-1` मौजूद है -> App **`SCH-2`** (Purchase में **`PCH-2`**) देगा! (गलत — `SCH-1` से शुरू नहीं होगा)।
  - `2026-27` में **Web** पर पहली नई एंट्री बनाएँगे -> Web `WSCH-` खोजता है -> लिस्ट में `SCH-1` है पर `WSCH-1` नहीं है -> Web **`WSCH-1`** देगा।
- इसके विपरीत, यदि `2025-26` का Pending Challan **Web** पर बना था (`WSCH-1` / `WPCH-1`), तो `2026-27` में Carry-Forward होने के बाद **Web** पर पहली नई एंट्री **`WSCH-2`** / **`WPCH-2`** बनेगी!

---

### Case B — पुराना Pending Challan `Y-5` है (जबकि `Y-1` से `Y-4` पुराने साल में ही Billed हो चुके थे)

यह सबसे चौंकाने वाला Case है क्योंकि दोनों Engines **Gap-Filling Algorithm** (`lib/logic/pharoah_numbering_engine.dart` Lines `55–63` और `lib/web_live_sync/web_pharoah_numbering_engine.dart` Lines `66–71`) चलाते हैं:
```dart
for (int i = startFrom; i <= existingNumbers.last; i++) {
  if (!existingNumbers.contains(i)) {
    return "$prefix$i"; // Found a missing number
  }
}
return "$prefix${existingNumbers.last + 1}";
```
**`2026-27` में क्या होगा (App और Web दोनों पर):**
- `2025-26` में `Y-1`, `Y-2`, `Y-3`, `Y-4` `"Billed"` हो चुके थे, इसलिए वे `2026-27` में Carry-Forward **नहीं** हुए। केवल `Y-5` (`Pending`) `2026-27` की `saleChallans` लिस्ट में आया।
- अब `2026-27` में `existingNumbers = [5]` है।
- **1st New Entry in `2026-27`:** Engine `i = 1` चेक करेगा -> `1` लिस्ट में नहीं है -> **`Y-1`** देगा।
- **2nd New Entry in `2026-27`:** `existingNumbers = [1, 5]` -> `i = 2` खाली है -> **`Y-2`** देगा।
- **3rd New Entry in `2026-27`:** `existingNumbers = [1, 2, 5]` -> **`Y-3`** देगा।
- **4th New Entry in `2026-27`:** `existingNumbers = [1, 2, 3, 5]` -> **`Y-4`** देगा।
- **5th New Entry in `2026-27`:** अब `existingNumbers = [1, 2, 3, 4, 5]` है! जब आप `2026-27` का **5वाँ नया चालान** बनाएँगे, तो Engine देखेगा कि `5` तो पहले से लिस्ट में है (क्योंकि पुराना `2025-26` वाला `Y-5` बैठा है)! इसलिए वह **`Y-5` को Skip करके सीधे `Y-6` दे देगा!**
- **परिणाम:** `2026-27` में कभी भी `2026-27` का अपना नया `Y-5` बन ही नहीं पाएगा (जब तक पुराना `Y-5` डिलीट न हो), और यदि यूज़र ने मैन्युअली नंबर बदलकर `Y-5` टाइप कर दिया, तो `finalizeSaleChallan` / `addSaleChallanAndSync` का `removeWhere(... || c.billNo == cleanBNo)` **पुराने साल के Pending `Y-5` को ही उड़ाकर उसकी जगह नया `Y-5` लिख देगा!**

---

### Case C — पुराने साल में `Y-1`, `Y-2`, `Y-3` सभी `Pending` रह गए और `2026-27` में Carry-Forward हो गए

- `2026-27` शुरू होते ही `saleChallans` लिस्ट में `[Y-1, Y-2, Y-3]` (तीनों `2025-26` के) मौजूद हैं।
- `existingNumbers = [1, 2, 3]`।
- जब आप `2026-27` में **पहला नया Challan** बनाएँगे:
  - लूप `i = 1` से `3` तक देखेगा कि `1, 2, 3` तीनों मौजूद हैं।
  - इसलिए **नए साल (`2026-27`) की सबसे पहली नई एंट्री `Y-1` के बजाय सीधे `Y-4` से शुरू होगी!**

---

### Summary Table — Part 2 (Expected vs Current Code on App & Web)

| Scenario | Expected Ideal Behavior in `2026-27` | Current App Code (`PharoahNumberingEngine`) | Current Web Code (`WebPharoahNumberingEngine`) |
|---|---|---|---|
| **Case A:** Old `Y-1` (`SCH-1`/`WSCH-1`) carried forward to `2026-27` | Carry-forward remains `Y-1` (2025-26); 1st new entry in `2026-27` = **`Y-1`**; 2nd = **`Y-2`** | 1st new entry becomes **`Y-2`** (`SCH-2` / `PCH-2`) because `1` is in `currentList` | 1st new entry becomes **`Y-2`** (`WSCH-2` / `WPCH-2`) because `1` is in `currentList` |
| **Case B:** Only Old `Y-5` carried forward (`Y-1..Y-4` were Billed in `2025-26`) | 1st..5th new entries in `2026-27` = **`Y-1, Y-2, Y-3, Y-4, Y-5`** | Gives `Y-1, Y-2, Y-3, Y-4`, then **skips `Y-5` and jumps to `Y-6`!** | Gives `Y-1, Y-2, Y-3, Y-4`, then **skips `Y-5` and jumps to `Y-6`!** |
| **Case C:** Old `Y-1, Y-2, Y-3` all carried forward to `2026-27` | 1st new entry in `2026-27` = **`Y-1`** | 1st new entry starts at **`Y-4`!** | 1st new entry starts at **`Y-4`!** |
| **Manual Override Collision Risk** | New `Y-1` (2026-27) and Carry-Forward `Y-1` (2025-26) must both coexist safely | **`finalizeSaleChallan` (Line `1156`) & `finalizePurchaseChallan` (Line `1247`) overwrite/delete old `Y-1` because they match by `billNo`/`internalNo`!** | **`addSaleChallanAndSync` (Line `2902`) & `addPurchaseChallanAndSync` (Line `3013`) overwrite/delete old `Y-1` because they match by `billNo`/`internalNo`!** |

---

## Section C — FY-Wise Challan Storage और Identity Architecture (Part 3)

यहाँ App, Web, Cloud Snapshot और D1 Edge Ledger के चारों स्तरों पर वर्तमान Storage और Identity Architecture का पूरा सच है:

### 1. App (`lib/pharoah_manager.dart` + `lib/fy_transfer_engine.dart`)
- **Disk Storage Path:**
  - `Pharoah_Data/<companyID>/<businessType>/<currentFY>/s_challan.json` (Sale Challans)
  - `Pharoah_Data/<companyID>/<businessType>/<currentFY>/p_challan.json` (Purchase Challans)
- **In-Memory Lists:**
  - `ph.saleChallans` और `ph.purchaseChallans` (केवल `currentFY` की लोड की गई लिस्ट)।
- **Carry-Forward Storage Behavior:**
  - जब `2025-26` से `2026-27` बनता है, तो `2025-26` का Pending चालान `2025-26/s_challan.json` में भी रहता है और **उसकी हूबहू कॉपी `2026-27/s_challan.json` में भी लिख दी जाती है**।
  - कोई अलग `carried_pending_challans.json` फाइल **नहीं** है (जबकि Pending Credit Invoices के लिए `pending_invoices.json` अलग फाइल रखी गई है!)।

### 2. Web (`lib/web_live_sync/pharoah_web_manager.dart`)
- **In-Memory Multi-FY Vault:**
  - `fyVault` (`Map<String, Map<String, dynamic>>`): इसमें हर FY का अलग बकेट होता है:
    - `fyVault["2025-2026"]["s_challan.json"]` / `fyVault["2025-2026"]["p_challan.json"]`
    - `fyVault["2026-2027"]["s_challan.json"]` / `fyVault["2026-2027"]["p_challan.json"]`
- **Active Working Lists:**
  - `webPh.saleChallans` और `webPh.purchaseChallans` (जो `financialYear` एक्टिव है, उसकी लिस्ट)।
- **Carry-Forward Storage Behavior:**
  - Web में भी Carry-Forward Challans सीधे नए FY के `fyVault["2026-2027"]["s_challan.json"]` और `webPh.saleChallans` के अंदर सामान्य चालान की तरह ही रखे जाते हैं।

### 3. Cloud Vault (`MultiFyCloudVault` / `store_data` JSON Blob)
- **Structure:** Cloud पर `multi_fy_vault.json` के अंदर हर FY (`2025-2026`, `2026-2027`) का अलग JSON map सेव होता है।
- **Identity Limitation:** प्रत्येक FY के अंदर `s_challan.json` में वही `SaleChallan.toMap()` ऑब्जेक्ट रहता है जिसका `id` (जैसे `"1741234567890"` या `"SCH-WEB-..."`) दोनों सालों की फाइल में **समान (identical)** होता है।

### 4. D1 Edge Ledger (`lib/sync_core/d1_sales_ledger_service.dart` + Outbox Sync Modules)
- **Outbox Modules:**
  - `SaleChallanSyncModule` (`lib/sync_core/modules/sale_challan_sync_module.dart`) और `PurchaseChallanSyncModule` (`lib/sync_core/modules/purchase_challan_sync_module.dart`) चालान सेव होने पर `c.toMap()` को Outbox में भेजते हैं।
- **FY Resolution in D1 (`extractEventFy` & `doesEventBelongToActiveFY`):**
  - क्योंकि `SaleChallan.toMap()` और `PurchaseChallan.toMap()` में कोई स्पष्ट `fy` फ़ील्ड **नहीं** होता, इसलिए `D1SalesLedgerService.extractEventFy()` (Lines `371–394`) चालान की **`date`** पढ़कर उसका FY निकालता है (`2025-05-10` -> `"2025-2026"`)!
  - इसका अर्थ है कि यदि `2026-27` में किसी पुराने Carry-Forward चालान (जिसकी `date` `2025-26` की है) का स्टेटस `"Billed"` किया जाता है, तो D1 Edge Event में उसकी `date` अभी भी `2025-26` की होती है। (Commit `fe59f65` में `_applyEdgeEventsToFyVault` और `FastPullEngine` में `targetFy` के साथ-साथ आगे के FYs में भी cascade/status propagate करने का पैच जोड़ा गया है ताकि दोनों FYs अपडेट हो सकें)।

### 5. Identity Fields Matrix (क्या मौजूद है और क्या गायब है?)

| Identity Attribute | SaleChallan Model | PurchaseChallan Model | वास्तविक स्थिति (Confirmed) |
|---|---|---|---|
| **Unique Record ID** | `id` (`sync_id`) | `id` (`sync_id`) | मौजूद है, लेकिन Carry-Forward होने पर पुराने और नए दोनों FY में **एक ही `id`** रहता है |
| **Challan Display No.** | `billNo` | `internalNo` (Inward ID) + `billNo` (Supplier Ref) | मौजूद है, लेकिन `finalize*` और `add*AndSync` में `billNo`/`internalNo` को भी overwrite/dedup key की तरह इस्तेमाल किया गया है |
| **Challan Date** | `date` | `date` | मौजूद है (Carry-Forward होने पर भी मूल तारीख ही रहती है) |
| **`createdFy` / `originalFy`** | ❌ **Missing** | ❌ **Missing** | मॉडल या JSON में कहीं भी सेव नहीं होता (केवल `date` से अनुमान लगाया जाता है) |
| **`currentFy` / `activeFy`** | ❌ **Missing** | ❌ **Missing** | केवल जिस फोल्डर/वॉल्ट में फाइल रखी है, उससे पता चलता है |
| **`isCarryForward` Flag** | ❌ **Missing** | ❌ **Missing** | मॉडल में कोई बूलियन या टैग नहीं है |
| **`billedInFy` / `linkedBillId`** | ❌ **Missing** | ❌ **Missing** | चालान पर यह नहीं लिखा होता कि वह किस FY के किस Bill नंबर से `"Billed"` हुआ है (केवल `Sale`/`Purchase` बिल के `linkedChallanIds` में चालान का `id` होता है) |

---

## Section D — Root Cause Analysis (Numbering Collision & Deduplication Flaws)

कोड के आधार पर Carry-Forward और New FY Numbering के बीच टकराव के **4 सटीक Root Causes** हैं:

### Root Cause 1: Single Unfiltered List Passed to Numbering Engine
- **App:** `SaleChallanView` (`lib/challans/sale_challan_view.dart:52`) सीधे `currentList: ph.saleChallans` और `PurchaseChallanView` (`lib/challans/purchase_challan_view.dart:51`) सीधे `currentList: ph.purchaseChallans` पास करता है।
- **Web:** `PharoahWebManager.getNextBillNumber` (`lib/web_live_sync/pharoah_web_manager.dart:4162, 4164`) सीधे `targetList = saleChallans` और `targetList = purchaseChallans` पास करता है।
- इन दोनों लिस्टों में चालू FY के चालान और पिछले FY से Carry-Forward होकर आए चालान **एक साथ मिले हुए** हैं।

### Root Cause 2: Numbering Engine Blindly Scans All Items Without FY/Date Check
- `PharoahNumberingEngine.getNextNumber()` (`lib/logic/pharoah_numbering_engine.dart:24–50`) और `WebPharoahNumberingEngine.getNextNumber()` (`lib/web_live_sync/web_pharoah_numbering_engine.dart:20–61`) में कोई FY या Date फ़िल्टर नहीं है।
- इसलिए पिछले FY का `Y-1` (`SCH-1` / `WSCH-1` / `PCH-1` / `WPCH-1`) चालू FY का नंबर मान लिया जाता है।

### Root Cause 3: Secondary-Key (`billNo` / `internalNo`) Deduplication without FY Scope in Save & Sync Methods
यदि हम केवल Numbering Engine को ठीक कर दें ताकि नए FY (`2026-27`) में फिर से `Y-1` (`SCH-1` / `PCH-1`) जनरेट हो सके, तो **तुरंत अगला बग (Data Overwrite Bug)** सामने आएगा! क्यों?
क्योंकि वर्तमान कोड में कई जगह `id` के साथ-साथ **`billNo` या `internalNo` के बराबर होने पर भी रिकॉर्ड को एक ही मानकर मिटा (replace) दिया जाता है**:
1. **App `finalizeSaleChallan` (`lib/pharoah_manager.dart:1148, 1156`):**
   ```dart
   final int existingIdx = saleChallans.indexWhere((c) => c.id == cId || (cleanBNo.isNotEmpty && c.billNo.trim().toUpperCase() == cleanBNo));
   ...
   saleChallans.removeWhere((c) => c.id == cId || (cleanBNo.isNotEmpty && c.billNo.trim().toUpperCase() == cleanBNo));
   ```
   **खतरा:** यदि `2026-27` में `2025-26` का Carry-Forward चालान `Y-1` मौजूद है, और `2026-27` में नया चालान भी `Y-1` नंबर से सेव किया गया, तो `c.billNo == cleanBNo` सत्य हो जाएगा और **पुराने साल का Carry-Forward चालान `Y-1` डिलीट/ओवरराइट हो जाएगा!**
2. **App `finalizePurchaseChallan` (`lib/pharoah_manager.dart:1224, 1247`):**
   ```dart
   purchaseChallans.removeWhere((c) => c.id == cId || (cleanINo.isNotEmpty && c.internalNo.trim().toUpperCase() == cleanINo));
   ```
   **खतरा:** नए साल का `PCH-1` सेव होते ही पुराने साल के Carry-Forward `PCH-1` को लिस्ट से हटा देगा!
3. **Web `addSaleChallanAndSync` (`lib/web_live_sync/pharoah_web_manager.dart:2902`) और `addPurchaseChallanAndSync` (`Line 3013`):**
   - यहाँ भी `c.billNo.trim().toUpperCase() == cleanBNo` और `c.internalNo.trim().toUpperCase() == cleanINo` से `existingIdx` खोजकर उसी इंडेक्स पर ओवरराइट (`saleChallans[existingIdx] = challan`) किया जाता है!
4. **Cloud / Vault Merge (`_parseDownloadedFiles` in `pharoah_web_manager.dart:1057, 1072` & `FastPullEngine` & `MasterSyncOrchestrator`):**
   - वहाँ भी `x.id == item.id || x.billNo == item.billNo` (और Purchase Challan में `x.internalNo == item.internalNo`) से मैचिंग होती है। यदि एक ही FY की लिस्ट में `2025-26` का `Y-1` और `2026-27` का `Y-1` दोनों रखे गए और उनकी मैचिंग बिना FY/Origin चेक किए केवल `billNo`/`internalNo` से हुई, तो वे एक-दूसरे को कुचल (overwrite) देंगे!

### Root Cause 4: Register और Stitcher में Date Filter की असंगति (Web vs App)
- **Web में:** `WebChallanView` (`lib/web_live_sync/web_challan_view.dart:115, 283`) और `WebChallanStitcherWizard` (`lib/web_live_sync/web_challan_stitcher_wizard.dart:111, 883`) सक्रिय FY की तारीख सीमा (`01/04/2026` से `31/03/2027`) लगाते हैं, जिससे `2025-26` की तारीख वाले Carry-Forward Pending Challans मेमोरी (`webPh.saleChallans` / `webPh.purchaseChallans`) में होते हुए भी Web के Register और Stitcher में **दिखाई ही नहीं देते**!
- **App में:** `SaleChallanRegister` (`lib/challans/sale_challan_register.dart:46`) में `if (matchesDate || ch.status == "Pending")` लिखा है (इसलिए वहाँ दिखते हैं), लेकिन **`PurchaseChallanRegister` (`lib/challans/purchase_challan_register.dart:41–43`) में `|| ch.status == "Pending"` नहीं लिखा है**, इसलिए App के Purchase Challan Register में भी 30 दिन/FY start से पुराने Carry-Forward Pending Purchase Challans छुप जाते हैं!

---

## Section E — Carry-Forward Challan को New FY Series से अलग रखने का सही Architecture (Part 4)

आपकी अपेक्षा बिल्कुल स्पष्ट और व्यावसायिक रूप से 100% सही है:
> - **FY `2025-26` का Pending Challan `Y-1`** नए FY `2026-27` में दिखना भी चाहिए और उसका Bill भी बनना चाहिए।
> - लेकिन **FY `2026-27` की अपनी नई Challan Series फिर से `Y-1`, `Y-2`, `Y-3` से स्वतंत्र रूप से शुरू होनी चाहिए।**
> - दोनों में कभी कोई Numbering Collision या Overwrite नहीं होना चाहिए।

इसे हासिल करने के लिए **सबसे सुरक्षित, Backward-Compatible और Zero-Regression Architecture** नीचे दिया गया है:

### 1. Challan Identity & Origin FY Attribution (`originalFy` + `isCarryForwardFor(activeFy)`)
- **Model Enhancement (`SaleChallan` एवं `PurchaseChallan` दोनों में):**
  - मॉडल में एक स्पष्ट फ़ील्ड जोड़ी जाए:
    ```dart
    String originalFy; // e.g., "2025-2026"
    ```
  - **Backward Compatibility Fallback:** यदि पुराने डेटा में `originalFy` खाली है, तो एक हेल्पर गेटर `effectiveOriginalFy` अपने-आप `date` से उसका वास्तविक निर्माण वित्तीय वर्ष (Creation FY, जैसे `10/05/2025` -> `"2025-2026"`) निकाल लेगा (`FYTransferEngine` या `AppDateLogic` के अनुसार: यदि महीना अप्रैल (4) या उसके बाद है तो `year - (year+1)`, अन्यथा `(year-1) - year`)।
  - **Helper Method on `SaleChallan` & `PurchaseChallan`:**
    ```dart
    bool isCarryForwardIn(String activeFy) {
      return effectiveOriginalFy != activeFy.trim();
    }
    ```
  - इससे बिना किसी डेटा माइग्रेशन के हर पुराने और नए चालान के बारे में 100% सटीक पता रहेगा कि:
    - उसका **Original Creation FY (`effectiveOriginalFy`)** कौन-सा है।
    - और क्या वह चालू FY (`activeFy`) का **Native (Original) Challan** है या **Carry-Forward Challan**।

### 2. Numbering Engine Isolation Rule (App और Web दोनों में)
- **नियम:** किसी भी FY (`activeFy`) में नया Challan Number जनरेट करते समय Numbering Engine केवल **उसी `activeFy` के Native Challans (`!ch.isCarryForwardIn(activeFy)`)** को गिनेगा!
- **App में (`PharoahNumberingEngine` / Call Sites):**
  - `SaleChallanView` और `PurchaseChallanView` (या सीधे `PharoahNumberingEngine.getNextNumber`) में `currentList` को फ़िल्टर किया जाए ताकि केवल चालू FY में बने चालान (`effectiveOriginalFy == ph.currentFY`) ही `existingNumbers` में गिने जाएँ।
- **Web में (`PharoahWebManager.getNextBillNumber` / `WebPharoahNumberingEngine`):**
  - `targetList` पास करते समय `saleChallans.where((c) => !c.isCarryForwardIn(financialYear)).toList()` और `purchaseChallans.where((c) => !c.isCarryForwardIn(financialYear)).toList()` पास किया जाए।
- **परिणाम:**
  - यदि `2025-26` से `Y-1`, `Y-5` या `Y-1, Y-2, Y-3` Carry-Forward होकर `2026-27` में आए हैं, तो `2026-27` का Numbering Engine उन्हें पूरी तरह अनदेखा (ignore) करेगा।
  - `2026-27` की पहली नई एंट्री हमेशा **`Y-1`** (`SCH-1` / `WSCH-1` / `PCH-1` / `WPCH-1`) बनेगी, दूसरी **`Y-2`**, तीसरी **`Y-3`**!

### 3. Same-Number Coexistence Protection (सबसे महत्वपूर्ण सुरक्षा!)
जब `2026-27` में:
- एक Carry-Forward Challan है: `billNo: "Y-1"`, `effectiveOriginalFy: "2025-2026"`, `id: "id_old_2025"`
- और एक नया Native Challan बनता है: `billNo: "Y-1"`, `effectiveOriginalFy: "2026-2027"`, `id: "id_new_2026"`

तब वे दोनों एक-दूसरे को कभी Overwrite न करें, इसके लिए **Deduplication Key में `effectiveOriginalFy` को शामिल करना अनिवार्य है**:
1. **App `finalizeSaleChallan` (`lib/pharoah_manager.dart:1148, 1156`) & `finalizePurchaseChallan` (`1224, 1247`):**
   - `c.billNo == cleanBNo` या `c.internalNo == cleanINo` से मैच करते समय यह शर्त अनिवार्य रूप से जोड़ी जाए:
     ```dart
     c.effectiveOriginalFy == newChallanOriginalFy
     ```
   - इससे `2026-27` का नया `Y-1` (`originalFy: 2026-27`) कभी भी `2025-26` के Carry-Forward `Y-1` (`originalFy: 2025-26`) से टकराएगा नहीं!
2. **Web `addSaleChallanAndSync` (`pharoah_web_manager.dart:2902`) & `addPurchaseChallanAndSync` (`3013`):**
   - यहाँ भी secondary key (`billNo` / `internalNo`) से मैच करते समय `c.effectiveOriginalFy == challan.effectiveOriginalFy` चेक हो।
3. **Purchase Challan Supplier Duplicate Check (`findDuplicateSupplierChallan`):**
   - यह चेक भी केवल समान `effectiveOriginalFy` वाले चालानों के बीच (या चालू FY के चालानों पर) चले, ताकि अगर किसी सप्लायर का पिछले साल का `Bill No: 1` Pending पड़ा है और नए साल में उस सप्लायर ने नए साल का `Bill No: 1` भेजा, तो सिस्टम उसे ब्लॉक न करे।
4. **Tombstone & Delete Keys (`deleteSaleChallan` / `deletePurchaseChallan`):**
   - सेकेंडरी डिलीट की (`scopedBNo` / `internalNo`) को `c.effectiveOriginalFy` से स्कोप किया जाए, ताकि `2026-27` का नया `Y-1` डिलीट करने पर `2025-26` का Carry-Forward `Y-1` डिलीट न हो।

### 4. Lifecycle Matrix (Convert to Bill, Bill Delete, Edit, Delete Challan)
| Action in `2026-27` | Carry-Forward Challan (`Y-1` from `2025-26`) | Native Challan (`Y-1` of `2026-27`) |
|---|---|---|
| **Stitcher / Single Bill Conversion in `2026-27`** | `id` (`id_old_2025`) के आधार पर `"Billed"` होगा और यह `"Billed"` स्टेटस `2026-27` तथा `2025-26` दोनों में सिंक होगा। `2026-27` के नए `Y-1` (`id_new_2026`) पर कोई असर नहीं पड़ेगा। | केवल `2026-27` में `"Billed"` होगा। |
| **Converted Bill Deleted Later** | `linkedChallanIds` में `id_old_2025` होने से केवल वही पुराना `Y-1` वापस `"Pending"` होगा; `2026-27` की नई नंबरिंग सीरीज़ पर कोई असर नहीं पड़ेगा। | `id_new_2026` वापस `"Pending"` होगा। |
| **Delete Challan** | यदि `id_old_2025` डिलीट किया जाए, तो `2026-27` के नंबरिंग इंजन पर 0% असर पड़ेगा। | यदि `id_new_2026` डिलीट किया जाए, तो `2026-27` में `Y-1` का स्लॉट खाली होगा (Gap-filling केवल `2026-27` के native चालानों पर काम करेगा)। |

---

## Section F — Smart Challan Screen और UX Improvement Plan (Part 5)

जब नए FY (`2026-27`) में Carry-Forward `Y-1 (2025-26)` और नया `Y-1 (2026-27)` दोनों मौजूद हों, तो यूज़र और अकाउंटेंट को एक नज़र में बिना किसी भ्रम के सब कुछ स्पष्ट दिखना चाहिए। इसके लिए **App और Web दोनों पर** यह Smart Design होना चाहिए:

### 1. Visual Badge & Origin FY Tagging (हर Challan Card और Table Row पर)
- जिस चालान का `isCarryForwardIn(activeFy) == true` हो, उसके नंबर के बगल में एक स्पष्ट Amber/Indigo बैज दिखे:
  - **Badge:** `[CF • FY 2025-26]` या `[CARRY FORWARD • 2025-26]`
  - **Display Format:** `Y-1` के नीचे या बगल में छोटा सब-लेबल: `Orig. Date: 14/03/2026 (FY 2025-26)`
- चालू FY (`2026-27`) के चालानों पर सामान्य रूप से `Y-1` दिखे।

### 2. Challan Register & Stitcher में Smart Filter Tabs (App + Web)
- **Web (`WebChallanView` & `WebChallanStitcherWizard`) और App (`SaleChallanRegister` & `PurchaseChallanRegister`) में:**
  - सबसे पहले: Date Range Filter में Carry-Forward Pending Challans को छुपाने वाला बग ठीक हो — यानी **सभी `Pending` Carry-Forward Challans डिफ़ॉल्ट रूप से चालू FY के Register और Stitcher दोनों में दिखें** (चाहे उनकी तारीख पिछले साल की हो)।
  - ऊपर 3 Quick Filter Chips / Segmented Tabs हों:
    1. **`All Challans (14)`** — चालू FY के सभी + पिछले FY के Carry-Forward Pending चालान।
    2. **`Current FY 2026-27 (11)`** — केवल इस साल बने नए चालान।
    3. **`Carry-Forward Pending (3)`** — केवल पिछले FY से आए बिना बिल वाले Pending चालान।

### 3. Stitcher (Convert to GST Bill) में स्पष्ट समूहीकरण (Grouping)
- जब किसी पार्टी (Party X) के पास पिछले साल का `Y-1 (FY 2025-26)` और नए साल का `Y-1 (FY 2026-27)` दोनों `Pending` हों, तो Stitcher की चेकलिस्ट में दोनों के आगे स्पष्ट रूप से `[FY 2025-26]` और `[FY 2026-27]` तथा उनकी तारीख लिखी हो।
- जब दोनों को मिलाकर या अलग-अलग Bill बनाया जाए, तो Bill Item के `sourceChallanNo` में Carry-Forward चालान के लिए `"Y-1 (25-26)"` लिखा जाए ताकि प्रिंट होने वाले GST Invoice पर भी पार्टी को साफ पता चले कि कौन-सा आइटम पिछले साल के `Y-1` का है और कौन-सा नए साल के `Y-1` का।

---

## Section G — Old Working Commit `0a02674` से Comparison (Part 6)

हमने `git diff 0a02674..HEAD` (`fe59f65`) का पूरा निरीक्षण किया है। इसके निष्कर्ष नीचे हैं:

### 1. Commit `0a02674` के बाद किन-किन फाइलों में बदलाव हुआ?
`0a02674` से `fe59f65` के बीच कुल 19 कोड/टेस्ट फाइलों में बदलाव हुआ:
- `lib/fy_transfer_engine.dart`
- `lib/pharoah_manager.dart`
- `lib/web_live_sync/pharoah_web_manager.dart`
- `lib/sync_core/d1_sales_ledger_service.dart`
- `lib/sync_core/multi_fy_cloud_vault.dart`
- `lib/sync_core/orchestrator/master_sync_orchestrator.dart`
- `lib/realtime_signaling/engines/fast_pull_engine.dart`
- `lib/web_live_sync/app_sync_engine.dart`
- `lib/challans/purchase_challan_register.dart`
- `lib/web_live_sync/sub_views/web_billing/web_new_sale_view.dart`
- `lib/web_live_sync/sub_views/web_challans/web_sale_challan_view.dart`
- `lib/web_live_sync/sub_views/web_challans/web_sale_challan_billing_view.dart`
- `lib/web_live_sync/sub_views/web_challans/web_purchase_challan_view.dart`
- `lib/web_live_sync/sub_views/web_challans/web_purchase_challan_billing_view.dart`
- `lib/web_live_sync/sub_views/web_purchases/mechanism/web_purchase_mechanism.dart`

### 2. क्या `0a02674` के बाद Challan Numbering Engine में कोई बदलाव हुआ था?
- **Confirmed:** `lib/logic/pharoah_numbering_engine.dart` और `lib/web_live_sync/web_pharoah_numbering_engine.dart` में `0a02674` और `fe59f65` के बीच **एक भी लाइन का बदलाव नहीं हुआ है (`0 lines changed`)**।
- अर्थात **Part 1 और Part 2 वाली Carry-Forward Numbering Collision की समस्या Commit `0a02674` में भी पहले से मौजूद थी** (यह कोई नया रिग्रेशन नहीं है, बल्कि शुरुआती डिज़ाइन से ही Numbering Engine बिना FY फ़िल्टर के पूरी लिस्ट स्कैन करता आ रहा है)।

### 3. `0a02674` के बाद जो बदलाव हुए (`#PH-REV-813`), उन्होंने क्या ठीक किया और क्या अभी भी बाकी है?
- **जो `fe59f65` (`#PH-REV-813`) में ठीक किया गया:**
  1. पुराने FY में Converted Sale/Purchase Bill डिलीट करने पर वापस `"Pending"` हुए Challan को अगले FY में अकेले Cascade करना (`cascadePendingChallansOnlyStep` — बिना `opBal` या `meds.json` को छेड़े)।
  2. App में `switchYear()` करते समय पिछले FY से `"Pending"` हुए चालानों को ऑटो-रिकॉन्साइल करना (`syncPendingChallansFromPreviousYears`)।
  3. Web के `_reloadActiveFyFromVaultHotSwap` में `s_challan.json` और `p_challan.json` को हॉट-स्वैप में शामिल करना।
  4. `D1SalesLedgerService` और `FastPullEngine` में `SALE_CHALLAN` और `PURCHASE_CHALLAN` के लिए डेल्टा सिंक और LWW मर्ज जोड़ना।
  5. Web के `WebSaleChallanBillingView` और `WebPurchaseChallanBillingView` में प्रोडक्ट सर्च पर पहले क्लिक में डायलॉग न खुलने की समस्या को ठीक करना।

- **जो `fe59f65` में अभी भी अधूरा/बाकी है (Confirmed Gaps Still Present in `fe59f65`):**
  1. **Gap #1 (Numbering Collision):** Carry-Forward Challans अभी भी नए FY की Numbering Series (`PharoahNumberingEngine` और `WebPharoahNumberingEngine`) में गिने जा रहे हैं (Part 1 & Part 2)।
  2. **Gap #2 (Same-Number Overwrite Risk):** `finalizeSaleChallan`, `finalizePurchaseChallan`, `addSaleChallanAndSync`, `addPurchaseChallanAndSync` अभी भी बिना `originalFy` चेक किए `billNo`/`internalNo` से मैच करके पुराने Carry-Forward चालान को ओवरराइट कर सकते हैं।
  3. **Gap #3 (Web Register & Web Stitcher Date Filter Hiding Carry-Forward Challans):** `lib/web_live_sync/web_challan_view.dart` (Lines `115, 283`) और `lib/web_live_sync/web_challan_stitcher_wizard.dart` (Lines `111, 883`) तथा App का `lib/challans/purchase_challan_register.dart` (Line `41–43`) अभी भी तारीख के आधार पर पिछले FY के Carry-Forward Pending Challans को UI में फ़िल्टर कर देते हैं!
  4. **Gap #4 (Reverse Status Sync when Carry-Forward Challan is Billed in New FY):** जब `2025-26` का Pending Challan `2026-27` में Carry-Forward होकर आता है और यूज़र **`2026-27` में उसका Bill बनाता है**, तो `2026-27` की लिस्ट में तो वह `"Billed"` हो जाता है, लेकिन `2025-26` की लोकल फाइल (`Pharoah_Data/.../2025-2026/s_challan.json` या `p_challan.json`) और `fyVault["2025-2026"]` में पीछे जाकर उसका स्टेटस `"Billed"` अपडेट करने वाला बैकवर्ड सिंक (`updateOriginFyChallanStatus`) हर पाथ (जैसे App के `ChallanStitcherWizard`, `ChallanToBillConverter`, `SaleEntryView` आदि) में नहीं चलता! इस वजह से अगर बाद में `switchYear` या `syncPendingChallansFromPreviousYears` चलता है, तो `2025-26` में पड़ी पुरानी `"Pending"` कॉपी देखकर सिस्टम भ्रमित हो सकता है (हालाँकि `reconcileCarryForwardSaleChallans` में यदि `2026-27` में पहले से वह `id` `"Billed"` है तो वह उसे वापस `"Pending"` नहीं करता, लेकिन `2025-26` में स्विच करके देखने पर वह वहाँ `"Pending"` ही दिखता रहेगा!)।

---

## Section H — Edge Cases और Regression Risks

हमारी जाँच में निम्नलिखित **7 महत्वपूर्ण Edge Cases** सामने आए हैं जिनका समाधान करते समय विशेष ध्यान रखना होगा:

1. **Edge Case 1 — Carry-Forward Challan को नए FY में Bill बनाने पर Origin FY (`2025-26`) का स्टेटस अपडेट होना:**
   - यदि `2025-26` का चालान `Y-1` नए साल `2026-27` में Stitcher से Bill में बदला जाता है, तो वह केवल `2026-27` में ही नहीं, बल्कि `2025-26` के रिकॉर्ड में भी `"Billed"` (या `"Billed in 2026-27"`) दिखना चाहिए ताकि `2025-26` खोलने पर वह दुबारा Pending न दिखे।
2. **Edge Case 2 — `2026-27` में बने Bill को डिलीट करने पर Carry-Forward Challan का वापस `Pending` होना:**
   - यदि `2025-26` के Carry-Forward चालान का बिल `2026-27` में बना था, और बाद में `2026-27` में वह बिल डिलीट कर दिया गया, तो `2026-27` और `2025-26` दोनों में वह चालान वापस `"Pending"` हो जाना चाहिए।
3. **Edge Case 3 — एक ही पार्टी के पास `2025-26` का `Y-1` और `2026-27` का `Y-1` दोनों `Pending` होना:**
   - दोनों का `id` अलग है (`id_2025` बनाम `id_2026`), लेकिन `billNo` समान (`"Y-1"`) है।
   - इसलिए किसी भी Save, Edit, Delete, Bill Conversion या Cloud Sync में **कभी भी केवल `billNo` या `internalNo` से बिना `originalFy` के मैचिंग नहीं होनी चाहिए**।
4. **Edge Case 4 — App और Web के Default Prefix (`SCH-` बनाम `WSCH-` और `PCH-` बनाम `WPCH-`):**
   - वर्तमान में App `SCH-1` / `PCH-1` बनाता है और Web `WSCH-1` / `WPCH-1` बनाता है (ताकि ऑफलाइन/ऑनलाइन एक साथ एंट्री करने पर नंबर न टकराएँ), लेकिन यदि कस्टम सीरीज़ (`Y-`) बनाई जाए तो दोनों `Y-` बनाते हैं। FY Isolation दोनों ही स्थितियों (`SCH-`, `WSCH-`, `PCH-`, `WPCH-`, और कस्टम `Y-`) पर समान रूप से काम करना चाहिए।
5. **Edge Case 5 — सप्लायर का नया साल शुरू होने पर `Supplier Ref No` (`billNo`) फिर से `1` से आना (Purchase Challan):**
   - `findDuplicateSupplierChallan()` केवल उसी `effectiveOriginalFy` के चालानों में डुप्लीकेट चेक करे, ताकि पिछले साल के सप्लायर चालान नंबर `101` की वजह से नए साल का सप्लायर चालान नंबर `101` ब्लॉक न हो।
6. **Edge Case 6 — Multi-Year Hop (`2024-25` -> `2025-26` -> `2026-27`):**
   - यदि कोई चालान `2024-25` में बना था (`date: 2024-25`), तो `2025-26` और `2026-27` दोनों में उसका `effectiveOriginalFy` `"2024-2025"` ही रहेगा और वह दोनों ही सालों की नई नंबरिंग सीरीज़ को प्रभावित नहीं करेगा।
7. **Edge Case 7 — Existing Sale Bill / Purchase Bill / Party Opening Balance पर Zero Regression:**
   - Challan Numbering और Carry-Forward Isolation में किया जाने वाला कोई भी बदलाव `Sale` (`sales.json`), `Purchase` (`purs.json`), `Party.opBal` (`parts.json`), या `Medicine` (`meds.json`) के मौजूदा लॉजिक को बिल्कुल नहीं छुएगा।

---

## Section I — Step-by-Step Safe Implementation Plan (केवल आपके अनुमोदन हेतु — अभी लागू नहीं किया गया है)

जब आप अनुमति देंगे, तब निम्नलिखित **6 सुरक्षित और सर्जिकल स्टेप्स** में इसे लागू किया जा सकता है:

### Step 1: `SaleChallan` और `PurchaseChallan` में `originalFy` व `isCarryForwardIn(String activeFy)` जोड़ना (`lib/models.dart`)
- `SaleChallan` और `PurchaseChallan` में `String originalFy` फ़ील्ड जोड़ें।
- यदि `originalFy` खाली हो (पुराने रिकॉर्ड्स के लिए), तो `effectiveOriginalFy` गेटर स्वचालित रूप से `date` से उसका FY (`"YYYY-YYYY"`) निकाले।
- `bool isCarryForwardIn(String activeFy)` हेल्पर जोड़ें जो जाँचे कि `effectiveOriginalFy != activeFy.trim()`।

### Step 2: App और Web के Numbering Engines में Carry-Forward Challans को Exclude करना
- **App (`lib/challans/sale_challan_view.dart`, `lib/challans/purchase_challan_view.dart`, एवं `lib/logic/pharoah_numbering_engine.dart`):**
  - `PharoahNumberingEngine.getNextNumber()` में `SaleChallan` / `PurchaseChallan` को स्कैन करते समय केवल उन्हीं चालानों को गिनें जिनका `effectiveOriginalFy == currentFY` हो (अर्थात Carry-Forward चालानों को नंबर जनरेशन से बाहर रखें)।
- **Web (`lib/web_live_sync/pharoah_web_manager.dart` -> `getNextBillNumber` एवं `lib/web_live_sync/web_pharoah_numbering_engine.dart`):**
  - `CHALLAN` / `SALE_CHALLAN` और `PURCHASE_CHALLAN` / `CHALLAN_PUR` के लिए `targetList` में से केवल चालू `financialYear` के native चालान (`!c.isCarryForwardIn(financialYear)`) ही `WebPharoahNumberingEngine.getNextNumber()` को भेजें।

### Step 3: Secondary-Key (`billNo` / `internalNo`) Deduplication को `effectiveOriginalFy` से सुरक्षित करना
- **App (`lib/pharoah_manager.dart`):**
  - `finalizeSaleChallan` (Lines `1148, 1156`) और `finalizePurchaseChallan` (Lines `1224, 1247`) में `billNo` / `internalNo` से मैच करते समय `c.effectiveOriginalFy == currentFY` की शर्त जोड़ें, ताकि नए साल का `Y-1` कभी भी पिछले साल के Carry-Forward `Y-1` को ओवरराइट या डिलीट न करे।
  - `deleteSaleChallan` और `deletePurchaseChallan` में भी सेकेंडरी की मैचिंग में `c.effectiveOriginalFy == target.effectiveOriginalFy` रखें।
- **Web (`lib/web_live_sync/pharoah_web_manager.dart`, `MasterSyncOrchestrator`, `FastPullEngine`):**
  - `addSaleChallanAndSync` (Line `2902`), `addPurchaseChallanAndSync` (Line `3013`), `_parseDownloadedFiles` (Lines `1057, 1072`) और सिंक मर्ज में जब `id` अलग हो और केवल `billNo` / `internalNo` से मैच किया जा रहा हो, तब `x.effectiveOriginalFy == incoming.effectiveOriginalFy` अनिवार्य रूप से चेक करें।
- **Supplier Duplicate Check (`findDuplicateSupplierChallan`):**
  - केवल समान `effectiveOriginalFy` वाले Purchase Challans के बीच डुप्लीकेट चेक करें।

### Step 4: Web और App के Challan Registers व Stitcher में Carry-Forward Pending Challans की 100% Visibility
- **Web (`lib/web_live_sync/web_challan_view.dart` Lines `115, 283` एवं `lib/web_live_sync/web_challan_stitcher_wizard.dart` Lines `111, 883`):**
  -App के `SaleChallanRegister` की तरह Web के Sale/Purchase Challan Register और Stitcher में भी `matchesDate || (ch.status == "Pending" && ch.isCarryForwardIn(webPh.financialYear))` लागू करें, ताकि Carry-Forward Pending Challans नए FY में Web पर भी हमेशा दिखें और उनका बिल बन सके।
- **App (`lib/challans/purchase_challan_register.dart` Line `43`):**
  - यहाँ भी `matchesDate || ch.status == "Pending"` लागू करें ताकि App के Purchase Challan Register में भी पुराने Pending चालान छुपें नहीं।

### Step 5: Carry-Forward Challan का नए FY में Bill बनने पर Origin FY में भी `"Billed"` स्टेटस सिंक करना
- जब किसी Carry-Forward Challan (`c.isCarryForwardIn(activeFy) == true`) को नए FY में `"Billed"` किया जाए (चाहे App पर या Web पर), तो `c.effectiveOriginalFy` के लोकल डिस्क/वॉल्ट (`s_challan.json` / `p_challan.json`) में भी उस `c.id` का स्टेटस `"Billed"` अपडेट कर दिया जाए।

### Step 6: UI में Carry-Forward Badge (`[CF • 2025-26]`) और Filter Chips जोड़ना
- App और Web दोनों के Sale/Purchase Challan Register और Stitcher में Carry-Forward चालानों पर स्पष्ट `[CF • 2025-26]` बैज और `All / Current FY / Carry-Forward` फ़िल्टर चिप्स जोड़ें।

---

## Section J — Final Summary & Verification Status Classification

### 1. Classification of Findings (Confirmed vs Likely vs Unverified)

- **100% Confirmed from Source Code:**
  1. **Carry-Forward Numbering Collision (Part 1 & Part 2):** App (`PharoahNumberingEngine.getNextNumber` in `lib/logic/pharoah_numbering_engine.dart:8-67`) और Web (`WebPharoahNumberingEngine.getNextNumber` in `lib/web_live_sync/web_pharoah_numbering_engine.dart:12-75`) दोनों `currentList` के सभी तत्वों को बिना किसी Date या FY फ़िल्टर के स्कैन करते हैं। इसलिए पुराने FY से Carry-Forward होकर आया `Y-1` (`SCH-1`/`WSCH-1`/`PCH-1`/`WPCH-1`) नए FY की नंबरिंग को `Y-2` पर धकेल देता है (Case A), `Y-5` होने पर `Y-1..Y-4` देकर `Y-5` को स्किप कर `Y-6` पर कूद जाता है (Case B), और `Y-1..Y-3` होने पर पहली एंट्री `Y-4` से शुरू करता है (Case C)।
  2. **Dead Counter Key in App Numbering Engine:** `PharoahNumberingEngine.getNextNumber` (Line `20`) में `String counterKey = 'lastID_${type}_${prefix}_${companyID}_$currentFY';` वेरिएबल बनाया गया है, लेकिन पूरे मेथड में उसे कहीं पढ़ा (read) ही नहीं गया है।
  3. **Same-Number Overwrite Vulnerability:** `finalizeSaleChallan` (`lib/pharoah_manager.dart:1156`), `finalizePurchaseChallan` (`1247`), `addSaleChallanAndSync` (`lib/web_live_sync/pharoah_web_manager.dart:2902`), और `addPurchaseChallanAndSync` (`3013`) में `billNo` / `internalNo` के आधार पर बिना FY चेक किए रिकॉर्ड ओवरराइट/डिलीट होता है।
  4. **Web Register & Stitcher Date Filter Bug:** `web_challan_view.dart` (Lines `115, 283`), `web_challan_stitcher_wizard.dart` (Lines `111, 883`), और App के `purchase_challan_register.dart` (Line `43`) में तारीख के कड़े फ़िल्टर के कारण पिछले FY के Carry-Forward Pending Challans छुप जाते हैं।
  5. **Commit `0a02674` Comparison:** Numbering Engine की फाइलों में `0a02674` के बाद कोई बदलाव नहीं हुआ था; यह व्यवहार शुरू से ही ऐसा था।

- **Likely (Code Flow से अत्यधिक संभावित):**
  - यदि किसी पार्टी/सप्लायर का पिछले FY का Purchase Challan (जैसे `Supplier Ref: 101`) Pending होकर नए FY में आता है और नए FY में वही सप्लायर फिर से `101` नंबर का चालान भेजता है, तो `findDuplicateSupplierChallan` उसे डुप्लीकेट मानकर रोक देगा क्योंकि वह `effectiveOriginalFy` चेक नहीं करता।

- **Unverified (Live Multi-Device Network Timing):**
  - यह पूरी जाँच स्थैतिक सोर्स कोड (Static Source Code) और गिट इतिहास के प्रत्यक्ष निरीक्षण पर आधारित है; आपके निर्देशानुसार अभी कोई कोड बदलाव या नया रनटाइम निष्पादन नहीं किया गया है।
