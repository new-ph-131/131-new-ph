# Pharoah ERP Test Results — Revision #PH-REV-811

### 1. New Regression Test Suite
- **Suite**: `test/three_issues_independent_regression_test.dart`
- **Command**: `flutter test test/three_issues_independent_regression_test.dart`
- **Result**: **9 / 9 Tests Passed (100%)**

| Test Name | Result |
|---|---|
| `makeLotKey & makeSyncKey produce distinct evaluated keys for different MRPs when batch & expiry are blank` | **PASSED** |
| `Issue C: WebBatchResolver returns BOTH distinct NO BATCH MRP lots without collapse (normal + post-FY zero purRate)` | **PASSED** |
| `Issue A: Two NO BATCH MRP lots (100 & 50, qty 10 each) survive FY1 -> FY2 carry-forward, rebuild, and WebBatchResolver` | **PASSED** |
| `Issue A: Deleting ONE blank-batch MRP lot via MasterSyncOrchestrator or BatchCascadeEngine preserves the OTHER MRP lot` | **PASSED** |
| `Issue B: App Purchase (mixed-case billNo) -> Web Modify -> Web Delete cannot resurrect via stale UPDATE or Cloud JSON merge` | **PASSED** |
| `isPurchaseDeleted checks composite keys even when UUID is non-empty and differs from tombstoned UUID` | **PASSED** |
| `CloudSignalChannel.aggregateRemoteSignals sorts out-of-order modify+delete chronologically so delete wins` | **PASSED** |
| `SyncQueueManager retains all 12 rapid Purchase delete operations in frame buffer without dropping any` | **PASSED** |
| `Sale edit -> delete workflow remains intact via MasterSyncOrchestrator and D1SalesLedgerService` | **PASSED** |

---

### 2. Full Repository Test Suites
- **Command**: `flutter test test/*.dart`
- **Result**: **34 / 34 Tests Passed (100% Success Rate)**

| Suite | Tests Passed | Status |
|---|---|---|
| `test/three_issues_independent_regression_test.dart` | 9 / 9 | **PASSED** |
| `test/four_issues_comprehensive_regression_test.dart` | 4 / 4 | **PASSED** |
| `test/multi_fy_purchase_regression_test.dart` | 3 / 3 | **PASSED** |
| `test/decimal_fy_duplicate_regression_test.dart` | 5 / 5 | **PASSED** |
| `test/stock_ledger_regression_test.dart` | 6 / 6 | **PASSED** |
| `test/e2e_sync_test.dart` | 5 / 5 | **PASSED** |
| `test/sync_bridge_test.dart` | 1 / 1 | **PASSED** |
| `test/widget_test.dart` | 1 / 1 | **PASSED** |
| **Total** | **34 / 34** | **ALL PASSED** |
