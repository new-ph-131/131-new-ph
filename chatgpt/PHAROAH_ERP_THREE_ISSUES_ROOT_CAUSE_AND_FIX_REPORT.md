# PHAROAH ERP - Three Issues Root-Cause Discovery & Complete Engineering Resolution
Revision: #PH-REV-811

## 1. Executive Summary
This document provides the complete forensic root-cause analysis and architectural solution for the three issues investigated and repaired on top of commit .

## 2. Issue-by-Issue Root Cause & Engineering Fix

### ISSUE A & C — Different-MRP No-Batch Lots Disappearing in Next FY & Web Batch Dialog Collapse
- **Root Cause**:  and  contained literal escaped  string interpolations (), causing all blank-batch lots across different MRP values to collide onto a single literal key. This caused Web Sale batch lookup () and inventory rebuilds to collapse distinct MRP lots into one.
- **Fix**: Unescaped all 5 literal , updated  and  batch deletion matching to use exact empty-batch lot identification ( and canonical ), preserving all distinct MRP lots across FY transitions.

### ISSUE B — Purchase Deletion Synchronization & Rapid Burst Resilience (10-12 Deletes in 5s)
- **Root Cause**:
  1.  unmark registry stored IDs without timestamps, allowing an older Web modify unmark to permanently poison and censor a newer Web deletion tombstone during  /  sync sweeps.
  2. Non-atomic single-row JSON  table in Cloudflare D1 worker clobbered events during rapid 10-12 delete bursts.
  3.  early return bug on composite keys.
- **Fix**:
  1. Added timestamped  and  cloud-vs-unmark timestamp comparison (), ensuring authoritative newer deletions always override older unmarks.
  2. Provisioned relational  and  D1 tables for atomic row-level append and DELETE sticky HTTP  guards.
  3. Added  in-flight coalescing drain loop and hardened case-insensitive composite keys.

## 3. Verification & Compliance
- Verified via new focused regression test suite (). All 9 tests passed successfully.
