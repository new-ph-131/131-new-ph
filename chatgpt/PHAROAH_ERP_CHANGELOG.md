# Pharoah ERP Changelog — Revision #PH-REV-811
- **Inventory Logic**: Unescaped all literal  interpolations in  and .
- **Batch Deletion Isolation**: Hardened  and  to isolate blank-batch deletion by MRP and purchase rate.
- **Tombstone Anti-Poisoning**: Added timestamped  and robust  LWW comparison to prevent older unmarks from overriding newer Web deletions.
- **D1 Edge Ledger**: Provisioned relational  and  tables in Cloudflare D1 worker () and added HTTP  deleted sticky guards.
- **Outbox Coalescing**: Added  coalescing queue drain for rapid 10–12 purchase delete bursts.
- **Revision Bump**: Updated UI headers and sidebars to .
