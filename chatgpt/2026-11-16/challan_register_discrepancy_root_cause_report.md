# Root-Cause Report: Duplicate `SCH-1` (`₹1,731.00` aur `₹69.00`) aur App vs Web Challan Register Alag-Alag Kyon Dikha Rahe Hain

**Screenshot & System Details (Audit Basis):**
- **Company:** `MURLI` | **FY:** `2027-28` | **Filter:** `CURRENT FY` (`01/04/2027` - `31/03/2028`)
- **Party:** `ABC PHARMA DISTRIBUTORS`
- **Web Portal (`#PH-REV-814`) me dikh rahe 5 Outward Challans:**
  1. `WSCH-1` — `₹34.62` (`PENDING`, `WEB PORTAL`)
  2. `SCH-1` — `₹1731.00` (`PENDING`, App wala)
  3. `SCH-2` — `₹269.00` (`PENDING`, App wala)
  4. `WSCH-2` — `₹34.62` (`PENDING`, `WEB PORTAL`)
  5. `SCH-1` — `₹69.00` (`PENDING`, App wala)

---

## Short Summary (Seedhi Baat me Puri Kahani)

Yeh problem kisi ek button ya screen ke filter ki galti nahi hai — **7 real code bugs** ek saath milkar yeh gadbad kar rahe hain:

1. **App ka Numbering Engine "Gap-Filling" karta hai:** Agar App ki memory me `SCH-1` nahi dikh raha aur `SCH-2` maujood hai, to App naye challan ko wapas **`SCH-1`** number de deta hai — par ek **nayi UUID (`id`)** ke saath.
2. **Naya `SCH-1` save hote hi purane `SCH-1` ka number-tombstone mit jata hai:** Jaise hi naya `SCH-1 (₹69.00)` save hota hai, App, Web, D1 aur Google Drive sab jagah se `"2027-28::SCH-1"` ka delete-block hata diya jata hai.
3. **Sync engine me `billNo + FY` duplicate rokne ka check hi nahi hai:** Pura code sirf **UUID (`id`)** match karta hai. Isliye agar ek hi FY me 2 `SCH-1` alag-alag UUID se ban gaye, to na App aur na Web unko kabhi merge ya remove kar paate hain.
4. **Web apne purane RAM cache (`fyVault`) se App ka delete kiya hua challan zinda rakh leta hai:** Web refresh karte waqt `overwriteActiveYearInVault: false` lagata hai aur `deletedRecordIds` ko `fyVault` merge me check hi nahi karta — isliye App par delete hua `SCH-1 (₹1,731.00)` Web par bacha rehta hai ya wapas aa jata hai.
5. **D1 Gravestone loader dead code hai:** `D1SalesLedgerService.loadPersistedGravestones()` function likha to gaya hai par poore project me **kahin call hi nahi hota**. Page reload hote hi D1 ki delete memory zero ho jati hai.
6. **D1 ka `seq` cursor dusre device ke events skip kar deta hai:** Jab ek device save/delete karta hai to woh apna read-cursor aage badha leta hai, jisse beech me aaye dusre device ke D1 events hamesha ke liye miss ho jate hain.
7. **Google Drive Relay (`Code.js`) poori `s_challan.json` file overwrite kar deta hai (Last-Writer-Wins):** Jo device aakhri me push karta hai, woh dusre ke records/deletes ko Drive par overwrite kar deta hai. Saath hi Web ke `FINISH` button par double-tap guard nahi hai (isiliye `WSCH-1 ₹34.62` aur `WSCH-2 ₹34.62` bane).

---

## Hissa 1: Ek hi Company, FY aur Party me 2 `SCH-1` (`₹1,731.00` aur `₹69.00`) Kaise Ban Gaye?

### Step 1 — App ne dubara `SCH-1` number kaise de diya? (Gap-Filling Numbering Bug)

- **File:** `lib/logic/pharoah_numbering_engine.dart` (lines `11–91`) aur `lib/challans/sale_challan_view.dart` (lines `52–60`)
- App jab naya Outward Challan banata hai, to woh **sirf App ki current memory (`ph.saleChallans`)** ko scan karta hai — Google Drive, Web ya saved counter (`lastID_...`) ko check nahi karta.
- Code me **Gap-Filling loop** laga hai:
  ```dart
  // lib/logic/pharoah_numbering_engine.dart (lines 79-83)
  for (int i = startFrom; i <= existingNumbers.last; i++) {
    if (!existingNumbers.contains(i)) {
      return "$prefix$i"; // Jo pehla number missing milega, wahi de dega!
    }
  }
  ```

#### Example se samjho:
Maan lo aapke App par pehle yeh 2 challan bane the:
- `SCH-1` (`id = uuid_1`, Amount = `₹1,731.00`)
- `SCH-2` (`id = uuid_2`, Amount = `₹269.00`)

Ab do me se **koi bhi ek situation** hui:
- **Situation A (Sabse common):** Aapne App par `SCH-1 (₹1,731.00)` ko **Delete** kar diya. Ab App ki list me sirf `[SCH-2]` bacha (`existingNumbers = [2]`). Jab aapne agla naya challan (`₹69.00`) banaya, App ke numbering engine ne dekha `1` missing hai (kyonki `2` hai par `1` nahi hai), aur turant naye challan ko **`SCH-1`** number aur ek **nayi UUID (`id = uuid_3`)** de di (`lib/pharoah_manager.dart:1548`: `DateTime.now().toString()`).
- **Situation B (Multi-device / Sync lag):** Ek device par `SCH-1 (₹1,731)` aur `SCH-2 (₹269)` sync hone ke dauran ya offline hone par App ki memory me `SCH-1` missing tha aur sirf `SCH-2` tha, to App ne gap bharne ke liye dubara `SCH-1 (₹69.00)` bana diya.

*(Side Note — Web par `WSCH-1` aur `WSCH-2` dono `₹34.62` kyon hain?)*
- Web par `PharoahWebManager.getNextBillNumber` (`lib/web_live_sync/pharoah_web_manager.dart:4597-4599`) App ki `"SCH-"` series ko zabardasti `"WSCH-"` me badal deta hai.
- Aur Web ki billing screen (`lib/web_live_sync/sub_views/web_challans/web_sale_challan_billing_view.dart:112-172, 216-219`) me `isSaving` variable bana to hai par **`FINISH` button dabane par `if (isSaving) return;` check nahi laga hai**. Agar user `FINISH` par 2 baar click kar de to Web ek hi item/amount (`₹34.62`) ke **`WSCH-1` aur `WSCH-2`** do baar save kar deta hai (App me bhi commit `406c165` se pehle yahi issue tha).

---

### Step 2 — Naya `SCH-1 (₹69.00)` save hote hi purane `SCH-1` ki series protection kaise hat gayi?

Jaise hi App ne naya `SCH-1 (id = uuid_3, ₹69.00)` save kiya, code ne **charo jagah se `"2027-28::SCH-1"` ka tombstone clear kar diya**:

1. **App (`lib/pharoah_manager.dart:1568, 1618, 1647`):** `unmarkTombstoneWithTimestamp(..., secondaryKey: "SCH-1", fy: "2027-28")` aur `notifyAppMutation(..., unmarkedIds: [uuid_3, "SCH-1"])` chalata hai.
2. **D1 Push (`lib/sync_core/d1_sales_ledger_service.dart:1735-1739`):** Server ko bhejta hai `"unmarkedIds": [uuid_3, "2027-28::SCH-1", "SCH-1"]`.
3. **Cloudflare Server (`functions/api/lab_signal.ts:319-324, 381-385`):** D1 ke `signal_tombstones` table se `"2027-28::SCH-1"` aur `"SCH-1"` delete kar deta hai.
4. **Google Drive (`google_backend/Code.js:182-189, 236-261`):** `s_challan.json` me `SCH-1` active dekhkar `tombstones.json` se `"2027-28::SCH-1"` hata deta hai.
5. **Web (`lib/web_live_sync/pharoah_web_manager.dart:1112-1123`):** `SCH-1` aate hi `deletedRecordIds` se `"2027-28::SCH-1"` aur `"SCH-1"` remove kar deta hai.

Iske baad purane `SCH-1 (uuid_1, ₹1,731.00)` ko sirf **uski apni UUID `uuid_1` ka tombstone** hi rok sakta tha — aur wahi `uuid_1` ka delete Web tak pahuncha nahi ya Web ke cache ne use zinda rakh liya!

---

### Step 3 — Jab dono `SCH-1` aa gaye, to App ya Web ne unko merge/deduplicate kyon nahi kiya?

Kyonki poore project ke har sync module me **ek hi rule likha hai: "Agar dono records ke paas UUID (`id`) hai, to `billNo` aur `FY` bilkul mat dekho — sirf `id == id` check karo."**

| File / Engine | Line Number | Code kya karta hai |
|---|---|---|
| `SaleChallanSyncModule` | `lib/sync_core/modules/sale_challan_sync_module.dart:59-110` | Sirf `c.id == incoming.id` match karta hai. Line `96` par `incoming.id` non-empty ho to `billNoIdx = -1` kar deta hai aur seedhe `insert(0, incoming)` kar deta hai. |
| `DeltaMergeEngine` | `lib/web_live_sync/sync_protocol/delta_merge_engine.dart:224-242, 302-310` | Match check aur "Safe Deduplication Pass" dono me line `304` par key `"ID:$itemId"` banata hai. `uuid_1` aur `uuid_3` ki alag key banti hai, isliye **dono `SCH-1` zinda rehte hain**. |
| `D1SalesLedgerService` | `lib/sync_core/d1_sales_ledger_service.dart:2006-2033` | Line `2008` sirf `c.id == incoming.id` check karta hai; alag UUID wale `SCH-1` ko naya challan maankar add kar deta hai. |
| `PharoahWebManager` | `lib/web_live_sync/pharoah_web_manager.dart:1124-1148` | `masterSChMap` ki key `c.id.trim()` hai — matlab do alag UUID ke `SCH-1` ek saath list me rehte hain. |
| `MultiFyCloudVault` | `lib/sync_core/multi_fy_cloud_vault.dart:368-379` | Non-empty `id` match na ho to `null` return karta hai aur naya record add kar deta hai. |
| `PharoahManager.loadAllData` | `lib/pharoah_manager.dart:629-636` | Disk se load karte time `(FY, billNo)` uniqueness ka koi check nahi hai. |

---

## Hissa 2: Ek hi Company (`MURLI`) aur FY (`2027-28`) me App aur Web par Alag-Alag Data Kyon Dikh Raha Hai?

Iski **5 pakki code-level wajah** hain:

### Wajah 1 — Web ka `fyVault` refresh purane RAM cache ko Cloud ke upar chipka deta hai (`overwriteActiveYearInVault: false`)
- **File:** `lib/web_live_sync/pharoah_web_manager.dart` (lines `442-562`, `4684`, `4708-4713`)
- Har 12 second par jab Web `refreshStoreData()` chalata hai:
  ```dart
  // line 4684
  _extractAndSyncFyVaultFromCloud(files, cloudTopFy: cloudTopFy, overwriteActiveYearInVault: false);
  ```
- Yahan `overwriteActiveYearInVault` **`false`** hai! Jab Web ki RAM (`fyVault['2027-28']`) me pehle se data pada hota hai, to lines `467-562` **Cloud ke array aur Web ki apni RAM (`localArr`) dono ko merge karti hain**:
  ```dart
  // lines 548-550
  if (!mergedMap.containsKey(k)) {
    mergedMap[k] = item; // Cloud me nahi hai (App ne delete kar diya), phir bhi Web apni RAM se wapas daal deta hai!
  }
  ```
- Aur lines `530-534` (`isVaultItemDeleted`) me yeh **sirf `D1SalesLedgerService.isSaleChallanDeleted(...)` check karta hai — Web ka `deletedRecordIds` ya `localTombstoneRegistry` check hi nahi karta** (balki us waqt tak `files['tombstones.json']` parse bhi nahi hua hota!).
- **Example:** App par aapne `SCH-1 (₹1,731.00)` delete kiya -> Drive ke `s_challan.json` se woh hat gaya. Par Web par woh pehle se Web ki RAM `fyVault` me pada tha. Web ne refresh kiya, `overwriteActiveYearInVault: false` ki wajah se Web ne apni RAM se `SCH-1 (₹1,731.00)` wapas `mergedMap` me daal liya, aur agli push me use wapas Drive par upload kar diya!

---

### Wajah 2 — `D1SalesLedgerService.loadPersistedGravestones()` poore App/Web me kahin call hi nahi hota (Dead Code!)
- **File:** `lib/sync_core/d1_sales_ledger_service.dart` (line `82` aur line `825`)
- Jab koi challan delete hota hai to D1 service use `SharedPreferences` me `"d1_permanent_gravestones"` key ke andar save karti hai, aur check karte time RAM set `_permanentDeletedKeys` dekhti hai.
- Developer ne `loadPersistedGravestones()` function line `825` par banaya hai taki app/browser khulte hi purane deletes RAM me load ho jayein — **lekin poore `lib/` folder me yeh function ek baar bhi call nahi kiya gaya hai!**
- **Nateeja:** Jaise hi aap Web browser refresh/reopen karte ho ya Mobile App restart karte ho, `_permanentDeletedKeys` bilkul khali (`{}`) ho jata hai. Isliye Web ke `isVaultItemDeleted` aur `_parseDownloadedFiles` me D1 delete check fail ho jata hai!

---

### Wajah 3 — D1 ka `seq` Cursor Beech ke Events ko Hamesha ke Liye Skip Kar Deta Hai
Isme **do alag cursor bugs** hain:

1. **Save/Delete karne par Cursor aage jump kar jata hai (`lib/sync_core/d1_sales_ledger_service.dart:1761-1764, 1873-1875`):**
   - Jab bhi App ya Web koi Challan save ya delete karta hai, `onSaleChallanSaved` / `onSaleChallanDeleted` turant `_updateHighestLocalSeq(storeToken, newSeq)` chala deta hai.
   - **Example:**
     1. App ka D1 cursor abhi **`seq = 10`** par hai.
     2. Web ne ek challan create ya delete kiya -> D1 ne usko **`seq = 11`** diya (App ne abhi `11` pull nahi kiya hai).
     3. Isi beech App par aapne `SCH-1 (₹69.00)` save kiya -> D1 ne App ko response me **`seq = 12`** wapas bheja.
     4. App ne turant apna cursor **`10` se seedhe `12` par set kar diya** (`_updateHighestLocalSeq(token, 12)`).
     5. Agli baar App D1 se maangega: `WHERE seq > 12`. **`seq = 11` (Web wala change) App par kabhi aayega hi nahi!** (Aur yahi ulta Web ke saath bhi hota hai.)

2. **Web D1 `fetchSaleDeltas` abort check se PEHLE cursor commit kar deta hai (`lib/web_live_sync/pharoah_web_manager.dart:2059-2062`):**
   - App ka `FastPullEngine` pehle events apply karta hai aur last me `commitSaleDeltaSeq` chalata hai.
   - Lekin Web `D1SalesLedgerService.fetchSaleDeltas()` call karta hai (`d1_sales_ledger_service.dart:1104-1106`), jo data aate hi `maxSeq` save kar deta hai. Agar uske just baad line `2060` par `expectedGen != _fyParseGeneration` true ho jaye aur `_harvestD1EdgeDeltas` return kar de, to woh saare D1 events (jaise App ka `DELETE` ya `INSERT`) **bina apply hue hamesha ke liye skip ho jate hain**.

3. **App par `deleteSaleChallan` background me bina `await` ke chalta hai (`lib/pharoah_manager.dart:3533-3575`):**
   - App delete dabate hi screen se hata kar `save()` kar deta hai, par Tombstone + D1 Delete + Drive Push ko bina `await` kiye `Future<void>(() async { ... })` me chhod deta hai. Agar network slow ho, user App band kar de, ya `AppSyncEngine.pushStoreData` fail/abort ho jaye (`app_sync_engine.dart:89, 411`), to App ki local disk aur Web/Cloud me farq reh jata hai.

---

### Wajah 4 — Google Drive (`google_backend/Code.js`) Poori File Overwrite Karta Hai + Web `Pending` Guard Weak Hai
- **Google Drive Overwrite (`google_backend/Code.js:140-302`):**
  - `PUSH_STORE_DATA` me Apps Script sirf `tombstones.json` aur missing FY keys ko merge karta hai. Lekin **`s_challan.json` aur active FY ke `fy_vault.json` ko record-by-record merge nahi karta** — seedhe `fileObj.file.setContent(JSON.stringify(request))` (line `297`) se poori array overwrite kar deta hai.
  - Matlab agar Web aur App thode gap me push karein, to aakhri push wala client dusre ke naye ya delete kiye hue challans ko Drive par mita/badal sakta hai.
- **Web vs App Tombstone Filtering me Antari (`pharoah_web_manager.dart:1153-1163`):**
  - Web ke `_parseDownloadedFiles` me agar challan `Pending` hai, to woh `isSaleChallanDeleted` aur `secDelTs` skip karke sirf `isSaleChallanIdDeleted` + `deletedRecordIds` dekhta hai.
  - Jabki App par `FastPullEngine` aur `PharoahManager.loadAllData` phone ki local disk file (`Pharoah_Data/.../2027-28/s_challan.json`) aur phone ki apni `tombstones_$companyId` list use karte hain.
  - Is wajah se **App apne local phone data + local tombstones ke hisaab se alag list dikhata hai, aur Web apne `fyVault` + Drive/D1 ke hisaab se alag list dikhata hai**!

---

### Wajah 5 — UI Numbering Series aur Sorting ka Farq (Chhota Par Visible Difference)
- **Alag Series Prefix:** App banata hai `SCH-1, SCH-2...` (`getDefaultSeries("CHALLAN")`), jabki Web usi ko `WSCH-1, WSCH-2...` bana deta hai (`pharoah_web_manager.dart:4597`).
- **Sorting Order Alag:**
  - App (`lib/challans/sale_challan_register.dart:57`): `ph.saleChallans.reversed` (jis order me list me aaye uska ulta).
  - Web (`lib/web_live_sync/web_challan_view.dart:131-132`): `b.date.compareTo(a.date)` (date ke hisaab se sort).
- **App vs Web Build Timing:** Screenshot me Web `#PH-REV-814` par chal raha hai, jabki mobile me agar `406c165` se pehle ka APK install hai to usme slow `FINISH` / sync race ke purane bugs bhi saath chal rahe the.

---

## Live Example: Screenshot Wali Haalat (`MURLI`, `FY 2027-28`) Kaise Bani?

1. **Web Portal par:** Aapne/operator ne `ABC PHARMA DISTRIBUTORS` ke liye challan banaya aur `FINISH` par 2 baar click ho gaya (guard na hone se) -> **`WSCH-1` (`₹34.62`)** aur **`WSCH-2` (`₹34.62`)** ban gaye.
2. **Mobile App par:** App par `SCH-1` (`id: uuid_1`, `₹1,731.00`) aur `SCH-2` (`₹269.00`) bane aur Web par sync hue.
3. **App se `SCH-1 (₹1,731.00)` hata aur naya `SCH-1 (₹69.00)` bana:**
   - App par `SCH-1 (uuid_1)` delete hua (ya offline/dusre phone par sync nahi aaya tha) jabki `SCH-2 (₹269.00)` list me tha.
   - Agla challan banate hi `PharoahNumberingEngine` ne `[2]` me `1` ki gap dekhi aur `₹69.00` wale challan ko wapas **`SCH-1` (`id: uuid_3`)** de diya.
   - `uuid_3` save hote hi App, D1 aur Drive sab se `"2027-28::SCH-1"` ka block hat gaya.
4. **App aur Web alag ho gaye:**
   - App ki screen se `uuid_1 (₹1,731.00)` hat chuka tha (kyonki App ki local file + App tombstone ne use hata diya), lekin **Web ki RAM `fyVault` / Drive** me `uuid_1` zinda reh gaya (`overwriteActiveYearInVault: false` + dead `loadPersistedGravestones()` + D1 `seq` skip ki wajah se).
   - Phir jab naya `SCH-1 (uuid_3, ₹69.00)` Web par aaya, to UUID-only matching ki wajah se Web ne **`uuid_1` ko replace ya delete nahi kiya** — aur aapke screenshot ki tarah **ek hi table me `SCH-1 ₹1731.00` aur `SCH-1 ₹69.00` dono dikhne lage**, jabki App par alag records dikh rahe hain.

---

## Agar Fix Karna Ho to Kya Karna Hoga? (Exact Solution Plan)

1. **Numbering Engine me High-Water Mark Enforce karna:** Deleted bill number (`SCH-1`) ko gap-filling se dubara issue na kiya jaye jab persisted/highest counter usse bada ho.
2. **Same-FY `(originalFy, billNo)` Deduplication Guard:** `SaleChallanSyncModule`, `DeltaMergeEngine`, `D1SalesLedgerService` aur `PharoahWebManager` me check lagana ki ek hi FY me same `billNo` ke do alag-alag UUID zinda na rahein (latest version/timestamp jeete), aur `finalizeSaleChallan` / `addSaleChallanAndSync` me duplicate save block ho.
3. **`D1SalesLedgerService.loadPersistedGravestones()` Startup par Call karna** aur Web ke `_extractAndSyncFyVaultFromCloud` (`isVaultItemDeleted`) me `deletedRecordIds` + `localTombstoneRegistry` check lagana.
4. **D1 Cursor Bug Fix:** `onSaleChallanSaved` / `onSaleChallanDeleted` me `_updateHighestLocalSeq` hatana, aur Web par `fetchSaleDeltasWithCursor` + late `commitSaleDeltaSeq` lagana.
5. **Web `FINISH` Button Double-Tap Guard (`web_sale_challan_billing_view.dart`):** `if (isSaving) return;` lagana taki `WSCH-1` / `WSCH-2` duplicate na bane.
6. **Google Drive `Code.js` me Record-Level Merge:** `s_challan.json` ko overwrite karne ke bajaye server par UUID + version/timestamp + tombstones ke basis par merge karna.
