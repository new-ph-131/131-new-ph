# Pharoah ERP - Revision #PH-REV-811 Permanent Audit & Verification Artifacts

**Base Commit**: `8beb64a`  
**Fix Commit**: `bbc3b2da3a4f008a5c64b2c166867b2ad7ff9c46`  
**Revision Badge**: `#PH-REV-811 (FIX-NOBATCH-MULTI-MRP-FY-AND-PURCHASE-DELETE-SYNC)`  

This folder contains the complete, permanent audit artifacts, root-cause analyses, regression test results, and post-build verification reports for the three scoped issues resolved in Pharoah ERP:

1. **Issue A**: Different-MRP, blank-batch/blank-expiry lots disappearing in the next Financial Year.
2. **Issue B**: Purchase modification and rapid deletion synchronization reliability (`App <-> Web <-> Cloudflare D1 Edge`).
3. **Issue C**: Web Sale batch selection dialog displaying incomplete lots for multi-MRP blank-batch items.

### 📁 Files in this Directory:
- `PHAROAH_ERP_REV_811_POST_BUILD_VERIFICATION.md`: Independent post-build verification report covering all 3 issues, 34/34 passing tests, forensic discoveries, and deployment status.
- `PHAROAH_ERP_THREE_ISSUES_ROOT_CAUSE_AND_FIX_REPORT.md`: Detailed engineering root-cause investigation and architectural fix documentation.
- `PHAROAH_ERP_TEST_RESULTS.md`: Exact test suite names, execution commands, and full test outputs.
- `PHAROAH_ERP_CHANGELOG.md`: Detailed changelog of all modified components across App, Web, and Cloudflare Worker.
- `PHAROAH_ERP_EVIDENCE.md`: Forensic evidence index and Git commit provenance.
- `PHAROAH_ERP_PATCH.diff`: Full unified git diff between base commit `8beb64a` and `#PH-REV-811`.
