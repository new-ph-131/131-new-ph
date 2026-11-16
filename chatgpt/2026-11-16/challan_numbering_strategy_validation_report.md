# PHAROAH ERP — Challan Numbering Strategy Validation Report (Sale & Purchase Challan)

**Scope:** Sale Challan (`s_challan.json`, `SCH-` / `WSCH-`) aur Purchase Challan (`p_challan.json`, `PCH-` / `WPCH-`) dono ke liye  
**Stage:** Design & Code Validation Only (Abhi koi source code edit nahi kiya gaya hai)

---

## Executive Verdict (Seedha Technical Faisla)

Proposed 3-part policy (**Last Challan Delete + Middle Challan Cancel + Persistent Monotonic High-Water Mark**) ko hamari current architecture me **laagu kiya ja sakta hai**, lekin **as-is bina code badlav aur bina ek rule refine kiye nahi** — kyonki repo inspection me **4 real technical traps aur 1 bada contradiction** saamne aaye hain:

1. **Internal Contradiction (Rule 1 vs Rule 3):** Rule 3 kehta hai *"HWM kabhi decrease nahi hona chahiye aur purana number kabhi dubara issue na ho"*, jabki Rule 1 me "Last Challan Delete" agar `SCH-5` delete karke next ko wapas `SCH-5` dega to HWM `5 -> 4` ghatana padega (jo multi-device sync race paida karta hai). **Safest Design:** Delete sirf last eligible draft par allow karein, **lekin HWM kabhi decrease na karein** (`SCH-5` delete hone ke baad bhi next `SCH-6` hi mile), ya HWM rollback sirf **100% unsynced + unprinted local draft** tak seemit rakhein.
2. **Purchase Challan Duplicate Ref Trap (`lib/models.dart:1211`):** `findDuplicateSupplierChallan` abhi sirf `c.isDeleted == 1` skip karta hai — `c.status == "Cancelled"` skip nahi karta! Agar aapne `PCH-2` (Supplier Ref `SUP-202`) ko **Cancel** kiya, to system aapko naya `PCH-6` usi `SUP-202` ke saath banane se block kar dega jab tak `findDuplicateSupplierChallan` ko update na kiya jaye.
3. **App New-Save Blind Overwrite Bug (`lib/pharoah_manager.dart:1573, 1703`):** `finalizeSaleChallan` aur `finalizePurchaseChallan` me `!isEditMode` hone par code same FY me matching `billNo` / `internalNo` wale kisi bhi purane record ko **UUID dekhe bina** `removeWhere` se uda deta hai! Agar App aur Web alag UUID ke saath same visible number (`SCH-1` / `PCH-1`) rakhenge to App Web ke record ko uda dega.
4. **Sync Conflict with Earlier Fix #2:** Pichhle plan ka *"Same-FY `(originalFy, billNo)` Deduplication Guard"* App aur Web ke independent same-number records (`App SCH-1` vs `Web SCH-1`) ko aapas me tod/merge kar dega. Isliye **UUID-only record identity** ko untouched rakhna zaroori hai.

---

## Architecture Reality Check: Kya Code Sach Me Karta Hai?

### 1. App aur Web Numbering Kaise Kaam Karti Hai?
- **App (`lib/logic/pharoah_numbering_engine.dart:11-91`, `lib/pharoah_manager.dart:4208-4211`):**
  - Sale Challan ke liye default prefix `"SCH-"` (`sale_challan_view.dart:54-60`, `billNo` field scan hota hai).
  - Purchase Challan ke liye default prefix `"PCH-"` (`purchase_challan_view.dart:54-60`, `internalNo` field scan hota hai — `billNo` nahi, kyunki `billNo` supplier ka ref number hota hai).
  - `PharoahNumberingEngine` ke paas `lastID_${type}_${prefix}_${companyID}_$currentFY` key hai (`line 23`) aur `updateSeriesCounter` (`line 96`) likha bhi hai — **lekin `getNextNumber()` `counterKey` ko padhta hi nahi aur Challan views `updateSeriesCounter` call bhi nahi karte!** Sirf `currentList` scan karke gap-filling loop (`lines 79-83`) chalata hai.
- **Web (`lib/web_live_sync/pharoah_web_manager.dart:4574-4642`, `lib/web_live_sync/web_pharoah_numbering_engine.dart:12-91`):**
  - `PharoahWebManager.getNextBillNumber` explicitly series badalta hai:
    - `"SCH-"` -> `"WSCH-"` (`lines 4597-4599`)
    - `"PCH-"` -> `"WPCH-"` (`lines 4594-4596`)
  - Web ke paas **koi persisted HWM counter nahi hai**; yeh har baar RAM list (`webPh.saleChallans` / `webPh.purchaseChallans`) ko scan karke gap-filling karta hai (`lines 82-86`).
- **Custom Series (`series.json`):** `series.json` App aur Web ke beech sync hota hai (`MultiFyCloudVault:32`, `SettingsSyncModule`). Agar user koi custom prefix (jaise `"DEL-"`) default bana de, to `pharoah_web_manager.dart:4594-4599` use `"WDEL-"` me **nahi** badalta — matlab tab App aur Web dono ke paas exact same prefix `"DEL-"` aa sakta hai!

### 2. Kya App aur Web Same Visible Number + Different UUID Safely Rakh Sakte Hain?
- **Sync Engines me:** **HAAN.** `SaleChallanSyncModule` (`line 65`), `PurchaseChallanSyncModule` (`line 76`), `DeltaMergeEngine` (`line 227`), `MultiFyCloudVault` (`lines 323, 370-378`), `D1SalesLedgerService` (`lines 2008, 2438`), aur `PharoahWebManager` (`lines 1126, 1220`) sab **UUID (`id`) match** karte hain. Do alag UUID wale `SCH-1` ya `PCH-1` kabhi merge/collapse nahi hote.
- **UUID Generation:**
  - App: `DateTime.now().toString()` (`pharoah_manager.dart:1548, 1664`)
  - Web Sale: `"SCH-WEB-${DateTime.now().millisecondsSinceEpoch}"` (`web_sale_challan_billing_view.dart:132`)
  - Web Purchase: `"PCH-WEB-${DateTime.now().millisecondsSinceEpoch}"` (`web_purchase_challan_billing_view.dart:641`)
  - Dono ki format alag hone se cross-environment UUID collision lagbhag impossible hai (lekin rapid double-click par millsecond same ho sakta hai — `isSaving` guard + unique suffix zaroori hai).
- **Kahan Gadbad Hogi Abhi:**
  1. `pharoah_manager.dart:1573` & `1703` (`finalizeSaleChallan` / `finalizePurchaseChallan`) new create me `c.billNo == cleanBNo` / `c.internalNo == cleanINo` se dusre device ka record list se uda deta hai!
  2. `PharoahNumberingEngine` aur `WebPharoahNumberingEngine` puri `currentList` (App + Web dono ke synced records) scan karte hain — isliye agar dono `SCH-` use karein to Web ka `SCH-5` App ka agla number `SCH-6` kar dega jabki App par sirf `SCH-1..3` the!

### 3. Stock, Batch, Party Ledger aur Accounting Impact
- `InventoryLogicCenter.rebuildAllInventory` (`pharoah_manager.dart:184-194`) aur `WebInventoryLogicCenter.rebuildWebInventory` (`pharoah_web_manager.dart:1456-1470`) **sirf `purchases`, `sales`, `saleReturns`, `purchaseReturns` padhte hain — Challans inventory quantity ya party balance ko bilkul touch nahi karte.**
- **Sirf 2 side-effects Challan save karte waqt hote hain:**
  1. `registerBatchActivity(..., qtyChange: 0.0)` batch metadata/rate history register karta hai (`pharoah_manager.dart:1600, 1729`; `pharoah_web_manager.dart:3280, 3400`).
  2. Web `addPurchaseChallanAndSync` (`pharoah_web_manager.dart:3353, 3392-3397`) Product Master par `med.purRate`, `med.mrp`, `med.rateA/B/C` (L.P.R.) aur auto-created product update kar deta hai!
- **Accounting / Billing:** Jab tak Challan `"Billed"` na ho (via `ChallanToBillConverter` ya `StitcherWizard` -> `Sale`/`Purchase` bill bane), tab tak koi accounting ya GST entry nahi hoti.

---

## Answers to Questions A–H

### A. Is this proposed policy safe and compatible with our current architecture?
**Verdict: Haan, safe aur compatible hai — par 5 zaroori adjustments ke saath:**
1. **Last Challan Delete vs Never-Decrease HWM:** Agar delete ke baad `SCH-5` reuse karne ke liye HWM `5 -> 4` kiya gaya, to multi-device me woh Rule 3 todta hai aur race paida karta hai. Best compatible rule: **HWM kabhi decrease na ho** (delete `SCH-5` -> record delete hota hai, HWM `5` rehta hai -> next `SCH-6`).
2. **Cancel vs Hard Delete Flag Separation:** Abhi `SaleChallanSyncModule.onSaleChallanDeleted:40-41` aur `PurchaseChallanSyncModule.onPurchaseChallanDeleted:40-41` delete par **`isDeleted = 1` + `status = "Cancelled"` dono** set karte hain!
   - **Rule hona chahiye:**
     - **Middle Cancel:** `isDeleted = 0`, `status = "Cancelled"` (UUID + number + history zinda rahega).
     - **Last-Draft Delete:** `isDeleted = 1`, `status = "Deleted"` (tombstone banega aur registers se permanently hatega).
3. **`findDuplicateSupplierChallan` Fix (`lib/models.dart:1211`):** Cancelled `PurchaseChallan` (`status == "Cancelled"`) ko duplicate check skip karna hoga, warna Cancelled supplier bill dubara enter hi nahi ho payega.
4. **Register Filtering & Totals (`sale_challan_register.dart:57`, `purchase_challan_register.dart:55`, `web_challan_view.dart:135, 148, 362, 376`):** Active registers aur `REGISTER VALUE: ₹...` totals ko `status != "Cancelled"` filter lagana hoga (Cancelled ko alag "Cancelled / Audit" tab ya filter me dikhana chahiye, aur edit/convert/bill/print actions lock karne honge).
5. **`finalizeSaleChallan:1573` & `finalizePurchaseChallan:1703` Fix:** New save par `billNo`/`internalNo` match karke dusri UUID delete karna band karna hoga.

---

### B. Can it fix the gap-filling and duplicate visible-number problem without creating App/Web numbering conflicts?
**Haan, bilkul.**
- **Gap-filling 100% khatam hoga:** Kyonki `next = HWM + 1` chalega, missing/deleted/cancelled numbers beech me kabhi dubara nahi bhare jayenge.
- **App vs Web conflict nahi hoga** kyunki:
  1. Default code me App (`SCH-`, `PCH-`) aur Web (`WSCH-`, `WPCH-`) ke prefixes already alag hain.
  2. Aur agar HWM scope me `env` (`APP` vs `WEB`) shaamil ho, to agar dono kabhi same prefix (`SCH-` ya custom `DEL-`) bhi chalayein, tab bhi App ka HWM (`3`) aur Web ka HWM (`5`) alag-alag chalenge!
  3. **Important Note (2 Mobile App Phones):** Agar ek hi store me **2 mobile phones (`APP` + `APP`)** offline kaam kar rahe hain, to online aane par dono ka `APP` HWM cloud se `max()` hokar sync hoga. Bilkul offline simultaneous creation me UUID alag hone se sync data loss nahi hoga, par 100% zero collision sirf online server-lease ya device-prefix se hi milta hai (offline me `HWM` offline race limit exist karti hai — par restart, delete, cancel, cache refresh aur sync par zero regression hogi).

---

### C. Exact High-Water Mark (HWM) Scope (Code Se Derived)
Code ke `PharoahNumberingEngine` (`type, prefix, companyID, currentFY`) aur `PharoahWebManager.getNextBillNumber` (`SCH-`->`WSCH-`, `PCH-`->`WPCH-`) ke hisaab se exact scope key honi chahiye:

```text
HWM Key = (storeId / storeToken) :: normalizedFY :: docType :: env :: normalizedPrefix
```

**Har dimension ka exact proof:**
1. **`storeId` / `storeToken`:** Multi-company / multi-store isolation (`PharoahNumberingEngine:23` uses `companyID`; Web uses `activeStoreToken`).
2. **`normalizedFY` (e.g. `2027-28`):** Code me `T5`/`T6` tests aur `PharoahNumberingEngine:32-44` proof karte hain ki har FY ki numbering `startFrom` (`1`) se fresh start hoti hai aur Carry-Forward challans (`originalFy != activeFy`) current FY ke counter ko aage nahi badhate.
3. **`docType` (`SALE_CHALLAN` vs `PURCHASE_CHALLAN`):** Sale aur Purchase challans ke apni alag files (`s_challan.json` vs `p_challan.json`) aur alag counters hain. *(Note: `series_master_view.dart:32` ka UI preview quirk fix hona chahiye jahan woh dono list mila deta tha).*
4. **`env` (`APP` vs `WEB`):** Agar dono custom series ya same prefix (`SCH-`) use karein to bhi App aur Web ke HWM independent rahein.
5. **`normalizedPrefix` (`SCH-`, `WSCH-`, `PCH-`, `WPCH-`, ya custom `DEL-`):** Ek hi FY aur environment me multiple series alag sequence rakhti hain (`web_pharoah_numbering_engine.dart:8-11`).

**Example of Scope Keys:**
- App Sale Challan (`MURLI`, `2027-28`): `TOKEN123::2027-28::SALE_CHALLAN::APP::SCH-` -> `HWM = 3`
- Web Sale Challan (`MURLI`, `2027-28`): `TOKEN123::2027-28::SALE_CHALLAN::WEB::WSCH-` (ya `WEB::SCH-`) -> `HWM = 5`
- App Purchase Challan (`MURLI`, `2027-28`): `TOKEN123::2027-28::PURCHASE_CHALLAN::APP::PCH-` -> `HWM = 2`
- Web Purchase Challan (`MURLI`, `2027-28`): `TOKEN123::2027-28::PURCHASE_CHALLAN::WEB::WPCH-` -> `HWM = 4`

**Where HWM Must Persist & Sync:**
- Local App: `SharedPreferences` + FY folder `hwm_state.json` / `config.json`.
- Local Web: `SharedPreferences` (browser localStorage) + `fyVault[fy]['config.json']`.
- Cloud / D1: `config.json` (ya dedicated `challan_hwm` map in `config.json`) on Google Drive + D1 `signal_events` (`max(local, remote)` merge rule, NEVER overwrite downward!).

---

### D. How Should "Last Challan Delete" Be Validated in a Multi-Device Environment?
Kisi bhi Challan `C` (number `N`, scope `S`) ko **Permanent Delete** karne se pehle yeh **5-step gate** pass hona chahiye (Sale & Purchase dono ke liye):

1. **Draft Status Check:** `C.status == "Pending"` ho (`"Billed"` ya `"Cancelled"` na ho) AND `getForwardChallanStatus(C.id).billedFy == null` ho (kisi aage wale FY me bhi bill na bana ho).
2. **Audit / Signature Check:** `SaleChallan` par `!C.isSigned && C.sigHistory.isEmpty` ho (agar customer ne sign kar diya hai to delete block, sirf Cancel allow). `PurchaseChallan` par bhi agar already synced/shared ho to check apply ho.
3. **Latest-in-Own-Scope Check:** `N == localHWM[S]` ho AND same scope `S` me local list + `fyVault` me koi bhi active ya cancelled record `> N` na ho (aur D1/Cloud me bhi koi higher number na aaya ho).
4. **Online / Sync Conflict Guard (Crucial!):**
   - Delete execute karne se pehle (agar online hai) D1/Cloud se check karein ki koi dusra device `N+1` ya `N` ke baad naya record to nahi bana chuka.
   - **Recommended Rule:** Delete approve hone par record ko hard-delete (`isDeleted = 1, status = "Deleted"`) + tombstone + D1 `DELETE` karein, **LEKIN `HWM[S]` ko `N` par hi lock rakhein (decrement NA karein)**!
   - *Kyun?* Maan lo Phone 1 ne `SCH-5` banaya -> Cloud par sync hua -> Web/Phone 2 ne use dekh liya (ya offline `SCH-6` banaya) -> Phone 1 ne `SCH-5` delete kiya. Agar HWM `5 -> 4` ghataya to Phone 1 agla `SCH-5` nayi UUID se banayega aur wapas ghost/tombstone mismatch shuru ho jayega. **HWM ko `5` par rakhne se Rule 3 ("never decrease, never reissue") 100% safe rehta hai!**
5. **Non-Latest Challan (`N < HWM[S]`):** Delete button disable/redirect hokar **"Cancel Challan"** chalaye (`isDeleted = 0, status = "Cancelled"`), jisse `SCH-2` / `PCH-2` audit me bacha rahe aur kabhi reuse na ho.

---

### E. What Happens When App & Web Independently Issue the Same Visible Number With Different UUIDs?
Maan lo App aur Web dono same prefix `"SCH-"` (ya `"PCH-"`) chalate hain aur dono ne independently **`SCH-1`** banaya:
- App record: `{ id: "2027-04-01 10:00:00.111", billNo: "SCH-1", originalFy: "2027-28", total: 1731 }`
- Web record: `{ id: "SCH-WEB-1775000001000", billNo: "SCH-1", originalFy: "2027-28", total: 500 }`

**Kya hoga step-by-step?**
1. **Sync & Merge (`SaleChallanSyncModule`, `PurchaseChallanSyncModule`, `DeltaMergeEngine`, `MultiFyCloudVault`, `D1SalesLedgerService`):**
   - Sab jagah `id == id` check hota hai -> `"2027-04-01..." != "SCH-WEB-..."` -> **dono records safely coexist karte hain**, zero collision, zero overwrite!
2. **D1 & Tombstones:**
   - App agar `SCH-1 (App UUID)` ko Cancel/Delete kare, to D1 `isSaleChallanDeleted` aur `isPurchaseChallanDeleted` (`d1_sales_ledger_service.dart:495, 514`) **UUID-first** check karte hain — non-empty UUID hone par woh `"2027-28::SCH-1"` secondary tombstone par block nahi karte! So **Web wala `SCH-1 (Web UUID)` bilkul safe rahega.**
   - *(Warning for `Google Drive Code.js` & `TombstoneEngine`):* Hard delete karte waqt jab non-empty UUID hai to `SCH-1` jaisi shared visible number ka naked/secondary key tombstone bhejna **dangerous** ho sakta hai agar legacy empty-ID fallback hit ho — isliye har new record par non-empty UUID mandatory hai (`SCH-APP-...` / `SCH-WEB-...`) aur Tombstone check non-empty UUID par sirf `id` check kare.
3. **Abhi Jo 2 Bugs Phootenge (Jo Fix Karne Honge):**
   - **Bug 1 (`pharoah_manager.dart:1573, 1703`):** Agar Web ka `SCH-1` pehle App par sync ho gaya aur uske baad App par `SCH-1` save hua, to App `cleanBNo == "SCH-1"` dekhkar Web ke `SCH-1` ko local list se remove kar dega! Isliye line `1573` & `1703` ka secondary-number `removeWhere` hatana MUST hai.
   - **Bug 2 (Cross-Contamination in `getNextNumber` Scan):** Agar App aur Web dono `"SCH-"` prefix use karein aur `PharoahNumberingEngine` puri `ph.saleChallans` list scan kare, to Web ka `SCH-5` App ki list me dikhkar App ke next number ko `SCH-4` se seedha `SCH-6` jump kara dega! Isliye numbering engine ko **sirf apni `env` ke HWM + apni `env` ke records** dekhne honge (e.g. `env == "WEB"` ke liye `id.startsWith("SCH-WEB-") || billNo.startsWith("WSCH-")`, ya dedicated persisted `env`-scoped HWM!).
   - **Register Visibility Note:** Agar App aur Web dono same `"SCH-1"` ek hi FY me banayenge to Register me 2 rows `"SCH-1"` dikhengi — UI me **"APP"** vs **"WEB PORTAL"** badge (`web_challan_view.dart:191, 458` me Web badge already hai, App me bhi add/keep karne se) user ko clearly samajh aata hai ki kaunsa kis device ka hai. (Waise best practice yeh hai ki default prefix `SCH-` vs `WSCH-` aur `PCH-` vs `WPCH-` alag hi rahein — aur `env` in HWM scope backup protection de!)

---

### F. Which Existing Code Must Change vs Which Code Must Remain Untouched?

| Status | Exact File & Function | Kya Change Karna Hai / Kyon Untouched Rahega |
|---|---|---|
| **MUST CHANGE** | `lib/logic/pharoah_numbering_engine.dart` (`getNextNumber`, `updateSeriesCounter`) | Gap-filling loop (`lines 79-83`) hata kar `max(persistedHwm, maxIssuedInScope) + 1` lagana; scope me `(companyID, FY, docType, env="APP", prefix)` aur `Cancelled` records include karna; save hote hi HWM persist + sync karna. |
| **MUST CHANGE** | `lib/web_live_sync/web_pharoah_numbering_engine.dart` (`getNextNumber`) & `pharoah_web_manager.dart:4574` (`getNextBillNumber`) | Gap-filling loop (`lines 82-86`) hata kar persisted+synced `WEB`-scoped HWM use karna (`WPCH-` / `WSCH-` / custom prefix). |
| **MUST CHANGE** | `lib/pharoah_manager.dart:1538, 1653, 3507, 3588, 4338` | (1) `finalizeSaleChallan:1573` & `finalizePurchaseChallan:1703` se `billNo`/`internalNo` overwrite `removeWhere` hatana. (2) `cancelSaleChallan` / `cancelPurchaseChallan` add karna (`isDeleted=0, status="Cancelled"`). (3) `deleteSaleChallan` / `deletePurchaseChallan` par Last-Eligible-Draft validation lagana & HWM kabhi decrement na karna. (4) `loadAllData:4338, 4350` me `"Cancelled"` handle karna. |
| **MUST CHANGE** | `lib/web_live_sync/pharoah_web_manager.dart:507, 1153, 1259, 2059, 3220, 3316, 3453, 3514` | (1) `add*` & `cancel*` & `delete*` me same HWM + Cancel + Last-Draft gate. (2) `_extractAndSyncFyVaultFromCloud` (`isVaultItemDeleted:507-534`) me `deletedRecordIds` & `localTombstoneRegistry` check lagana. (3) `_harvestD1EdgeDeltas:2059` cursor commit bug fix. |
| **MUST CHANGE** | `lib/models.dart:1211` (`findDuplicateSupplierChallan`) & `lib/web_live_sync/web_models.dart` | `if (c.isDeleted == 1 \|\| c.status.trim().toUpperCase() == "CANCELLED") continue;` add karna taki Cancelled Purchase Challan ka Supplier Ref dubara entry ho sake! |
| **MUST CHANGE** | `lib/sync_core/modules/sale_challan_sync_module.dart:40-41` & `purchase_challan_sync_module.dart:40-41` | Hard delete (`on*Deleted`) par `status = "Deleted"` set karna (na ki `"Cancelled"`), taki hard-delete aur soft-cancel mix na hon. |
| **MUST CHANGE** | `lib/sync_core/d1_sales_ledger_service.dart:825, 1761, 1873, 2126, 2271` | `loadPersistedGravestones()` startup par call karna; `on*Saved`/`on*Deleted` se premature `_updateHighestLocalSeq` hatana; `onSaleChallanCancelled` / `onPurchaseChallanCancelled` add karna; `fetchSaleDeltasWithCursor` + commit after apply. |
| **MUST CHANGE** | `lib/challans/*_register.dart`, `lib/web_live_sync/web_challan_view.dart`, `lib/modifications/sub_views/modify_challan_list.dart`, `lib/logic/party_integrity_service.dart:88-108` | Active Registers, PDF Totals, aur Party-Delete check me `Cancelled` challans ko exclude/alag tab me dikhana; non-latest challan ke UI button ko **"Cancel"** dikhana & `"Cancelled"` par edit/bill/print lock lagana. |
| **MUST CHANGE** | `lib/web_live_sync/sub_views/web_challans/web_sale_challan_billing_view.dart` & `web_purchase_challan_billing_view.dart:723` | `FINISH` button aur `_save*` top par strict `if (isSaving) return;` double-tap guard lagana. |
| **MUST CHANGE** | `google_backend/Code.js` | `s_challan.json`, `p_challan.json` ka UUID-based record merge + `config.json` me `challan_hwm` map ka monotonic `Math.max()` merge. |
| **MUST CHANGE (Tests)** | `test/challan_fy_identity_numbering_cross_sync_test.dart` (`T5`, `T6`, + new tests) | `T5` & `T6` ko update karna (kyonki abhi woh deleted `Y-99`/`Y-8` ke baad `Y-1`/`Y-2` reuse hone ko pass maante hain!) aur Scenarios 1–12 ke naye regression tests add karna. |
| **UNTOUCHED** | `effectiveOriginalFy` / `normalizeFyString`, `MultiFyCloudVault:323` UUID isolation, `ChallanLinkMatcher`, `InventoryLogicCenter.rebuildAllInventory`, `Sale`/`Purchase`/`Voucher` billing & accounting, `ChallanToBillConverter` / `StitcherWizard` (`status == "Pending"`), aur historical Challan visible numbers | Inme koi badlav nahi chahiye — `status == "Cancelled"` already `ChallanToBillConverter` & `StitcherWizard` (`status == "Pending"`) se bahar rehta hai, aur stock/ledger bilkul untouched rehte hain! |

---

### G. Status of All 12 Mandatory Test Scenarios

| # | Mandatory Scenario | Current Repo Status | Details (Sale & Purchase Challan) |
|---|---|---|---|
| **1** | Create `SCH-1..5`, delete eligible last draft `SCH-5`, create next | **MISSING** | Abhi koi test nahi. **Warning:** Strict HWM rule ke mutabik next **`SCH-6`** milna chahiye (not `SCH-5`). Agar unsynced draft rollback chahiye to conflict caveat apply hoga. Same `PCH-1..5` ke liye bhi missing. |
| **2** | Create `SCH-1..5`, cancel middle `SCH-2`, create next -> must get `SCH-6` | **MISSING + CONFLICTS WITH T5/T6** | Abhi `T5` (`line 302`) aur `T6` (`line 352`) ulta assert karte hain ki `Y-99` (`isDeleted=1`) ignore hokar `Y-1` mile! `T5`/`T6` ko update karke Cancel (`status="Cancelled"`) + HWM test likhna hoga. |
| **3** | App `SCH-1..3` & Web `SCH-1..5` independent next numbers | **PARTIAL (Purchase Bill Only)** | `e2e_sync_test.dart:227` (`E2E TEST 5`) sirf **`Purchase`** (`PUR-` vs `WPUR-`) test karta hai; Sale/Purchase **Challan** (aur same-prefix App/Web scenario) ke liye test MISSING hai. |
| **4** | Cancel App `SCH-2`, verify Web does not reactivate or overwrite Web `SCH-2` | **MISSING** | `T10` edit cascade, aur `T13`/`T18`/`T19` hard-delete test karte hain — `Cancelled` status + same visible number on Web test MISSING hai. |
| **5** | Delete latest App draft while Web has different latest number -> Web unchanged | **MISSING** | Koi test exist nahi karta (Sale ya Purchase Challan dono ke liye). |
| **6** | Restart App & Web separately -> restore HWM | **MISSING** | App/Web reload par HWM restoration (aur `loadPersistedGravestones()`) ka koi test nahi hai; Web abhi counter persist hi nahi karta. |
| **7** | Offline-created Challans from 2 devices sync -> counters never go backwards, no silent reuse | **MISSING** | Sync hone ke baad `max(local, remote)` HWM merge ka koi test nahi hai. |
| **8** | Same visible numbers with different UUIDs (Same FY & Different FY) | **PARTIAL** | **Different FY** (`2026-27` CF + `2027-28` `WSCH-1`/`SCH-1`/`WPCH-1`) **EXISTS** (`T7, T8, T18, T19, T20`). **Same FY** (`App SCH-1` + `Web SCH-1` in `2027-28` + `finalize*` non-overwrite) **MISSING**. |
| **9** | Test Sale Challan & Purchase Challan independently | **PARTIAL** | `T1–T20` me dono ke FY/cascade tests hain, par HWM, Last-Delete vs Middle-Cancel, aur `findDuplicateSupplierChallan` on `Cancelled` MISSING hain. |
| **10** | Cancel billed, partially billed, stock-affected, accounting-posted Challans | **PARTIAL** | `T10` & `T11` already verify karte hain ki `Billed` (ya `fwd.billedFy != null`) Challan delete/edit block hota hai. Cancel block on `Billed`, zero stock/ledger mutation on Pending Cancel, aur `Cancelled` Purchase Ref re-entry MISSING hain. *(Note: Partial challan billing code me exist hi nahi karti — conversion hamesha full challan ko `Billed` banati hai.)* |
| **11** | Concurrent creation from 2 devices & repeated `FINISH` / double-click | **MISSING** | `FINISH` button double-tap ya concurrent creation par zero widget/unit test hain (`web_sale_challan_billing_view.dart` & `web_purchase_challan_billing_view.dart` me abhi bug bhi zinda hai). |
| **12** | Migration of existing data with deleted, cancelled, gaps, historical numbers | **MISSING** | Existing data par bootstrap `HWM = max(persistedHwm, maxActiveOrCancelledInList, maxTombstoneSeriesNumberInFy)` ka koi migration test nahi hai. |

---

### H. Conflict Analysis With Gemini's Other 5 Proposed Fixes

Pichhli reports me humne 6 fixes propose kiye the (1: HWM Numbering + 5 other fixes). Un 5 other fixes ke saath nayi policy ka check:

| Other Fix | Conflict Status | Exact Technical Detail |
|---|---|---|
| **Fix 2: Same-FY `(originalFy, billNo)` Deduplication Guard** *(Earlier Suggestion)* | **HIGH CONFLICT — DROP / REPLACE KARNA HOGA!** | Agar aapne Sync/Merge me same-FY `(originalFy, billNo)` deduplication lagaya, to jab App aur Web independently same visible number (`SCH-1` / `PCH-1` with different UUIDs) banayenge (Scenarios 3, 4, 8), yeh guard unme se ek ko delete/overwrite kar dega! Isliye sync layer me **UUID-only** rule hi rakhein (Strict Preservation Condition #1). |
| **Fix 3: `loadPersistedGravestones()` + `fyVault` `isVaultItemDeleted` Fix** | **ZERO CONFLICT (Mandatory)** | Page reload par tombstones yaad rakhne aur `fyVault` RAM cache se deleted challan zinda hone se rokne ke liye 100% zaroori hai. |
| **Fix 4: D1 `seq` Cursor Fix** | **ZERO CONFLICT (Mandatory)** | `on*Saved`/`on*Deleted`/`on*Cancelled` par premature `_updateHighestLocalSeq` hatana aur Web edge harvest me abort-after-commit rokna dono devices par Cancel/Delete/HWM events pahunchane ke liye zaroori hai. |
| **Fix 5: Web `FINISH` Button Double-Tap Guard** | **ZERO CONFLICT (Mandatory)** | Web `web_sale_challan_billing_view.dart` aur `web_purchase_challan_billing_view.dart:723` me `if (isSaving) return;` lagane se twin challan (`WSCH-1` + `WSCH-2`) nahi banenge. |
| **Fix 6: Google Drive `Code.js` Record-Level Merge** | **ZERO CONFLICT (Enhance Needed)** | `s_challan.json` / `p_challan.json` record-level UUID merge + `Cancelled` (`isDeleted=0`) records ko tombstone na samajhna + `config.json` me `challan_hwm` ko `Math.max()` se merge karna zaroori hoga. |

---

## Step-by-Step Concrete Examples (Hinglish Me)

### Example 1: Sale Challan — Last Delete vs Middle Cancel + Independent App/Web
1. **App** par `MURLI` (`2027-28`) me bane: `SCH-1`, `SCH-2`, `SCH-3` -> App HWM (`APP::SCH-`) = **`3`**.
2. **Web** par same company & FY me bane: `WSCH-1`..`WSCH-5` (ya custom same prefix `SCH-1`..`SCH-5`) -> Web HWM (`WEB::WSCH-` ya `WEB::SCH-`) = **`5`**.
3. User ne App par beech ka **`SCH-2`** hatana chaha (`2 < HWM 3`) -> System **Delete block** karega aur bolega **"Cancel Only"**. `SCH-2` ka `status = "Cancelled"`, `isDeleted = 0`, UUID wahi rahegi. Active Register total me `SCH-2` ka amount nahi judega, par Audit/History me number reserved rahega.
4. Ab App par naya challan banega -> `App HWM (3) + 1 =` **`SCH-4`** (kabhi `SCH-2` nahi milega!). Web ka apna counter **`5`** hi rahega -> Web par agla **`WSCH-6`** (ya `SCH-6`) banega, App Cancel ka Web par koi asar nahi padega.
5. Agar user App par **`SCH-4` (latest, Pending, unsigned)** ko **Last Challan Delete** kare -> `SCH-4` hard-delete (`isDeleted=1, status="Deleted"`) ho jayega, **lekin App HWM `4` par hi rahega** (never decreases) -> agla challan **`SCH-5`** banega, jisse dusre device/sync ke saath `SCH-4` ghost collision ka zero chance rahega.

### Example 2: Purchase Challan — Cancel + Supplier Ref Re-Entry (`SUP-202`)
1. App par Supplier `ABC PHARMA` ke 3 Purchase Challan bane:
   - `PCH-1` (Ref `SUP-101`, `₹1,731`)
   - `PCH-2` (Ref `SUP-202`, `₹500`)
   - `PCH-3` (Ref `SUP-303`, `₹269`) -> `APP::PCH-` HWM = **`3`**.
2. User ko pata chala `PCH-2` (`SUP-202`) me galat item ya galat rate daal diya tha aur bill abhi nahi bana (`Pending`).
3. `2 < HWM 3` hone ke karan `PCH-2` **Cancel** hoga (`status = "Cancelled"`, `isDeleted = 0`), delete nahi.
4. Ab user `ABC PHARMA` ka wahi bill **`SUP-202`** sahi items ke saath dubara entry karta hai:
   - Kyonki hum `findDuplicateSupplierChallan` ko update karenge ki woh `status == "Cancelled"` ko ignore kare, naya entry **allow ho jayega**!
   - Aur kyunki HWM `3` par locked hai, is naye challan ko **`PCH-4`** milega — **`PCH-2` kabhi dubara issue nahi hoga**!
5. Stock par `Pending` ya `Cancelled` Purchase Challan ka zero asar rehta hai (`rebuildInventory()` sirf Purchases/Sales padhta hai).

### Example 3: Existing Data Migration (`MURLI` Store Jisme Gaps Pehle Se Hain)
- Maan lo kisi store ke `2027-28` me purane `SCH-1` aur `SCH-2` delete ho chuke hain (`tombstones.json` / D1 me `2027-28::SCH-1`, `2027-28::SCH-2` hai) aur active list me sirf `SCH-3` aur `SCH-5` hai (beech me `SCH-4` bhi deleted tha).
- Upgrade ke baad pehli baar HWM bootstrap chalega:
  - Active/Cancelled max in FY = `5` (`SCH-5`)
  - Tombstones / D1 history max in FY = `2`
  - Persisted `lastID_` = `0`
  - **`HWM = max(0, 5, 2) = 5`**
- Isliye upgrade hote hi agla challan seedhe **`SCH-6`** banega — purana `SCH-1`, `SCH-2` ya `SCH-4` kabhi zinda ya reuse nahi honge!
