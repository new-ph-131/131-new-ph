# PHAROAH ERP — Independent Challan FY / Identity / Numbering / Cross-FY Sync Code Review

**Review date:** 2026-11-15  
**Repository:** `new-ph-131/131-new-ph`  
**Branch reviewed:** `main`  
**Exact reviewed HEAD:** `de501981ba75f9b3c527b4c960b7579d4916143c`  
**Implementation revision:** `#PH-REV-814`  
**Review type:** Read-only independent source review against the committed implementation and CI evidence  
**Source changes made by this review:** None

---

## 1. Executive verdict

The `#PH-REV-814` implementation is substantial and the latest main-branch CI is green, including Android APK build and Flutter Web build/deployment. However, the source does **not** yet justify the implementation report's claim that Challan identity, Original FY preservation, and cross-FY synchronization are 100% complete.

The review found multiple remaining correctness risks in the exact areas this change was intended to fix:

1. App Challan edit paths read the old list index **after removing the edited record**, which can assign the wrong Original FY or throw a range error.
2. Bill-to-Challan status matching still mixes UUIDs and human-readable numbers. A number collision can mark a different Challan Billed/Pending even when both Challans have different non-empty IDs.
3. The Multi-FY vault's Purchase Challan branch still permits two different non-empty IDs to merge by composite fields in the same FY.
4. Cross-FY propagation overwrites the destination copy's version without checking whether that destination version is newer.
5. Legacy Original FY is still inferred from the Challan date, and serialization persists that inferred value. The storage/vault provenance needed to distinguish an edited date from the creation FY is not implemented.
6. Equal version + equal timestamp with conflicting payload is still arrival-order dependent.
7. The Web Stitcher batch-save route still contains a second Challan status/version update after `addSaleAndSync` / `addPurchaseAndSync`.
8. The 13-test suite does not exercise several critical production methods; one identity test is a locally reimplemented toy predicate rather than a test of production code.

**Recommendation:** Keep the current implementation and successful deployment intact, but do not mark this work fully closed until the P1 items below are corrected and the missing production-path regression tests pass.

---

## 2. What is genuinely implemented

The following changes are present in the reviewed source:

- `SaleChallan` and `PurchaseChallan` now have an `originalFy` field, and it is serialized/deserialized.
- App and Web numbering engines have FY-aware filtering for Carry Forward Challans.
- Sale Challan sync-module matching is ID-first when IDs are present.
- Purchase Challan sync-module matching has a constrained legacy fallback when one side has no ID.
- Cross-FY disk and Web vault helper methods update existing records by exact Challan ID.
- D1 Fast Pull now invokes helpers to derive Billed/Pending status from bill events.
- The Web Stitcher single-draft route delegates Challan status mutation to `addSaleAndSync` / `addPurchaseAndSync`.
- `#PH-REV-814` is present in the relevant revision labels.

These are meaningful improvements; this review is not recommending a rollback or a rewrite.

---

## 3. Findings requiring correction

### F-01 — P1: App Challan edit reads the old index after removing the record

**Files:** `lib/pharoah_manager.dart`  
**Sale path:** around line 1226  
**Purchase path:** around line 1331

Both `finalizeSaleChallan` and `finalizePurchaseChallan` calculate `existingIdx`, then remove the existing Challan from the list, and only afterwards read:

```dart
final String targetOfy = (existingIdx != -1)
    ? challans[existingIdx].effectiveOriginalFy
    : currentFY;
```

The index refers to the pre-removal list. After removal:

- If the edited record was the last item, indexing can throw `RangeError`.
- If it was not the last item, the old index can now refer to the next Challan and copy that other record's Original FY.
- This defeats the stated requirement that editing a Challan's date/details must preserve its own Original FY.

**Required correction:** Capture the existing record's `effectiveOriginalFy` (and any other required immutable metadata) into a local variable before removal. Do not read the list again using the stale index. Add App tests for editing the first, middle, and last Sale/Purchase Challan, including a Carry Forward Challan.

### F-02 — P1: Bill-to-Challan matching still falls back to numbers despite a non-empty UUID

**Affected production paths include:**

- `lib/pharoah_manager.dart` around lines 712–724 (Sale bill save) and 889 onward (Purchase bill save).
- `lib/web_live_sync/pharoah_web_manager.dart` around lines 2385–2400 (Sale bill save) and 2625–2640 (Purchase bill save).
- `lib/sync_core/d1_sales_ledger_service.dart` around lines 1217–1230 (D1 bill-save helper).
- `lib/sync_core/orchestrator/master_sync_orchestrator.dart` around the SALE/PURCHASE envelope handling and linked-Challan status loops.

The current pattern builds one set containing `linkedChallanIds`, `sourceChallanId`, and `sourceChallanNo`, then checks a Challan using conditions such as:

```dart
targetKeys.contains(challan.id) ||
targetKeys.contains(challan.billNo)
```

Purchase paths similarly match `internalNo` and/or supplier `billNo`.

This reintroduces the exact namespace collision the Primary ID Rule was meant to prevent. Example:

- Old FY Challan: ID `UUID-A`, number `Y-1`.
- New FY Challan: ID `UUID-B`, number `Y-1`.
- A bill linked by `sourceChallanNo = Y-1` can affect both records, although their non-empty IDs differ.

A single mixed set also loses the information about whether a value came from an ID field or a number field.

**Required correction:** Resolve each line/link with typed identity:
1. If `sourceChallanId` / linked Challan UUID is present, match only exact UUID.
2. Only when that specific link has no UUID may a legacy number fallback be attempted.
3. Legacy fallback must be scoped by the appropriate Original FY and, for Purchase, the existing supplier identity rules.
4. Never compare an ID string against a bill number/internal number namespace.

Add tests where two Challans have different non-empty IDs but identical Sale number, Purchase internal number, or supplier bill reference; only the explicitly linked ID may change.

### F-03 — P1: MultiFyCloudVault still merges distinct Purchase Challan IDs by composite key

**File:** `lib/sync_core/multi_fy_cloud_vault.dart` around lines 286–300.

The special Purchase branch is shared by both `purc.json` and `p_challan.json`. When candidate and existing records both have non-empty IDs:

- Exact ID match correctly returns the existing row.
- If IDs differ but FYs are the same, the code can still return the existing row when `internalNo + partyId + billNo` match.

That exception may be intentional for the separate Purchase-bill supplier duplicate identity policy in `purc.json`, but it is not safe for `p_challan.json`. Two Purchase Challans with different UUIDs are different records, even if their displayed numbers or supplier references coincide.

**Required correction:** Split the behavior by file/document type. Preserve the established composite duplicate rule for Purchase bills only where that business rule requires it. For `p_challan.json`, two non-empty different IDs must never match by composite key. Add a real `mergeJsonListLww(fileName: 'p_challan.json')` regression test with same-FY, same-number, same-party, same-internalNo but different UUIDs.

### F-04 — P1: Cross-FY propagation can downgrade a destination copy's version

**Files:**
- `lib/pharoah_manager.dart` around line 1154.
- `lib/web_live_sync/pharoah_web_manager.dart` around line 2936.

Both propagation helpers find a matching existing UUID and assign the supplied `customVersion` directly:

```dart
item['version'] = customVersion ?? ((item['version'] ?? 1) + 1);
item['updatedAt'] = nowMs;
```

There is no comparison against the destination copy's existing version. If the active-FY copy is at version 3 while an older FY copy is already at version 5, propagation can replace version 5 with version 3. That violates monotonic versioning and can make a later stale event appear newer.

**Required correction:** Define one shared, documented propagation conflict rule. Never lower a destination version. If the source mutation is not newer than the destination, do not overwrite it blindly; reconcile by the project's deterministic version/event ordering. Add tests for destination version greater than, equal to, and lower than source version.

Also verify that the propagated inactive-FY mutation is actually included in the intended cloud/outbox/snapshot path. The helper itself rewrites a disk JSON file or a `fyVault` entry; that alone is not proof that every remote device receives a correctly FY-scoped mutation.

### F-05 — P1: Legacy Original FY is still date-derived, not recovered from storage provenance

**File:** `lib/models.dart` around lines 674–680 and the corresponding PurchaseChallan getter.

When `originalFy` is empty, `effectiveOriginalFy` derives the FY from `date`. Then `toMap()` writes `effectiveOriginalFy` back into both `originalFy` and `original_fy`.

This permanently persists the date-derived guess. It cannot distinguish:
- a legacy Challan created in FY A and later carried forward,
- a legacy Challan whose date was edited after creation,
- a legacy record loaded from an old FY folder or vault,
- a malformed/missing historical date.

The new T3 test explicitly asserts date-derived FY fallback, so it currently blesses this limitation instead of proving provenance recovery.

**Required correction:** Preserve Original FY using trustworthy provenance available at the loading boundary (existing stored metadata first; otherwise the actual original record source/vault/transfer metadata where available). Do not treat an edited date as stronger than reliable source-FY provenance. If provenance genuinely cannot be established, keep the record marked as unresolved/legacy and use a conservative, explicit policy rather than silently persisting a guessed FY. Do not use the current date as a historical fallback.

### F-06 — P1: Equal Version + Equal Timestamp with different payload remains arrival-order dependent

**Files:** `lib/sync_core/modules/sale_challan_sync_module.dart` and `lib/sync_core/modules/purchase_challan_sync_module.dart`.

Both modules reject a lower version and reject an equal-version event with an older timestamp. But when both version and timestamp are equal, the incoming payload is accepted unconditionally.

If Device A and Device B produce different status/payload values with the same version and timestamp, whichever event arrives last wins. Different delivery order can therefore produce different final states.

**Required correction:** Use an existing stable event/mutation identifier or introduce a deterministic tie-break field that is persisted and propagated. Exact identical payloads should be idempotent no-ops. Conflicting payloads with identical version/timestamp must resolve identically regardless of arrival order. Do not use “incoming wins”.

### F-07 — P2: Web Stitcher batch-save still performs a second Challan status/version mutation

**File:** `lib/web_live_sync/web_challan_stitcher_wizard.dart` around lines 359 and 421.

The single-draft route calls `addSaleAndSync` / `addPurchaseAndSync` and no longer repeats the Challan mutation. However, the batch-save route still calls `addSaleAndSync(newSale)` and then loops through `b['challanIds']` to set status, increment version, and enqueue another Challan mutation. The Purchase batch route has the equivalent pattern.

The manager method already performs this work. The remaining batch loop can cause a duplicate version increment/outbox event, contrary to the implementation report's claim that the redundant second loop was removed.

**Required correction:** Remove only the redundant second Challan mutation from the batch path after confirming that the manager method covers all required IDs and item-level source links. Retain inventory/batch activity work. Add separate single-save and batch-save regression tests to assert exactly one Challan version bump and one intended mutation per conversion.

### F-08 — P2: Current regression suite does not prove the claimed production scenarios

**File:** `test/challan_fy_identity_numbering_cross_sync_test.dart`.

The suite contains 13 test declarations, but important coverage gaps remain:

- T8 reimplements a tiny local `isMatch` predicate; it does not call `MultiFyCloudVault._findMatchingRecordIndex` or another production matching method.
- T9 tests Sale Challan merge in `s_challan.json`; it does not test the Purchase Challan `p_challan.json` exception described in F-03.
- T3 asserts date fallback instead of storage-provenance recovery.
- T10 checks lower-version rejection; T11 checks a higher timestamp at equal version. There is no equal-version/equal-timestamp conflicting-payload determinism test.
- T12 tests the D1 save helper, but there is no corresponding production delete/revert helper test.
- No test exercises App disk-folder propagation or Web vault propagation.
- No test exercises the App/Web bill-save and bill-delete matching paths against same-number/different-ID Challans.
- No test exercises the Web Stitcher batch path and its duplicate mutation.
- No end-to-end offline-device/reconnect reconciliation test is present.

**Required correction:** Add focused production-method tests for each listed behavior. Keep the test suite narrow and deterministic; do not replace production tests with locally reimplemented predicates.

### F-09 — P2: Missing/invalid Challan date handling can silently invent the current FY or throw

**File:** `lib/models.dart` around line 545 and corresponding PurchaseChallan.fromMap.

The constructors use `DateTime.parse(map['date'] ?? DateTime.now().toIso8601String())`. A missing date therefore becomes today's date, while a malformed date can throw. Since `effectiveOriginalFy` falls back to `date`, a missing historical date can become the current FY when serialized.

**Required correction:** Use safe parsing and preserve an unresolved legacy state when date/provenance is unavailable. Do not silently assign today's date to a historical Challan. Add missing-date and malformed-date tests for both models.

---

## 4. CI / build / deployment evidence

The current `main` HEAD is `de501981ba75f9b3c527b4c960b7579d4916143c`.

Latest runs for that exact HEAD:

- **Flutter Web Portal + Android APK:** run `43694500014` — success. The job steps include Flutter tests, Android release APK build, Web portal build, upload, and production Cloudflare Pages deployment.
- **Android APK:** run `43694500076` — success. The release APK build and artifact upload completed.

There were earlier failed workflow runs for intermediate implementation commits (`5bdb3f01`, `2d1673cb`, `12282f88`, and `130ff937`); subsequent commits fixed compilation/test issues, and the latest HEAD runs are green.

**What this proves:** CI completed the configured build/test/deploy steps for the latest commit.

**What this does not prove:** Actual Android-device ↔ Web-browser live synchronization, offline queue replay, old-FY-device reconciliation, or correct behavior against real production data. No real multi-device runtime test evidence was found in the reviewed implementation report or workflow steps.

---

## 5. Safe, narrowly scoped correction order

1. Fix the App stale-index Original FY bug in both Sale and Purchase Challan edit paths.
2. Enforce typed ID-first matching across App, Web, D1, and MasterSync bill-save/delete paths.
3. Split `p_challan.json` matching from `purc.json` supplier duplicate handling in MultiFyCloudVault.
4. Make cross-FY propagation monotonic and verify inactive-FY cloud propagation.
5. Resolve legacy Original FY from provenance; stop persisting date-derived guesses as authoritative metadata.
6. Add deterministic equal-version/equal-timestamp conflict resolution.
7. Remove the duplicate Challan mutation from Web Stitcher batch-save only.
8. Add production-path regression tests, then rerun Flutter analyze/tests, Web build, Android APK build, and Cloudflare deployment.
9. Perform a controlled real-device test: App→Web and Web→App, Original FY vs Active FY, conversion, delete/rebill, and offline reconnect. Verify exact IDs, statuses, versions, tombstones, and both FY storage copies.

## 6. Scope and preservation constraints

- Do not rewrite the sync architecture or refactor unrelated modules.
- Preserve the existing Purchase supplier duplicate rule for Purchase bills; apply strict UUID identity specifically to Challans.
- Preserve Sale/Purchase business workflows, inventory/batch accounting, Opening Balance, ledgers, and the previously fixed Purchase Sync behavior.
- Do not create new Challan copies during status propagation.
- Do not resurrect tombstoned Challans.
- Do not claim live multi-device sync based only on unit tests or successful deployment.

**Final review status: NOT READY FOR 100% closure.** The implementation is a strong partial completion with green latest CI, but F-01 through F-06 are correctness issues in the target workflows and should be corrected before treating #PH-REV-814 as fully complete.
