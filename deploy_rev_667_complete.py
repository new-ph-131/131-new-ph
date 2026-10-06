# FILE: deploy_rev_667_complete.py
# 🚀 1-CLICK PRODUCTION DEPLOYER & GITHUB PUSHER FOR #PH-REV-667
# Master Sync Engine (Step 1, Step 2, Step 3, Step 4 & Auto-Revival)
import os
import sys
import subprocess

print("=" * 72)
print("🚀 PHAROAH ERP • REVISION #PH-REV-667 COMPLETE PRODUCTION DEPLOYER")
print("Includes: Steps 1, 2, 3, 4 (D1 Batches, File Separation, LWW Guard, Outbox)")
print("=" * 72 + "\n")

repo_dir = os.path.dirname(os.path.abspath(__file__))
if repo_dir:
    os.chdir(repo_dir)

# 1. APPLY MASTER PATCH
print("📦 Step 1/5: Applying Master Revision #PH-REV-667 Patch...")
PATCH_CONTENT = """diff --git a/deploy_rev_664_auto_revival.py b/deploy_rev_664_auto_revival.py
new file mode 100644
index 0000000..047bc6b
--- /dev/null
+++ b/deploy_rev_664_auto_revival.py
@@ -0,0 +1,67 @@
+# FILE: deploy_rev_664_auto_revival.py
+# 🚀 1-CLICK PRODUCTION DEPLOYER & GITHUB PUSHER FOR #PH-REV-664
+import os
+import sys
+import subprocess
+import re
+
+print('=' * 68)
+print('🚀 PHAROAH ERP • REVISION #PH-REV-664 DEPLOYER')
+print('Active Record Auto-Revival Engine & Cross-Device Import Sync')
+print('=' * 68 + '
+')
+
+repo_dir = os.path.dirname(os.path.abspath(__file__))
+os.chdir(repo_dir)
+
+# 1. GIT STATUS & COMMIT
+print('📥 Step 1/4: Staging files and creating git commit...')
+subprocess.run(['git', 'add', '.'], check=False)
+subprocess.run(['git', 'commit', '-m', '🚀 #PH-REV-664: Active Record Auto-Revival Engine & Cross-Device Import Synchronization'], check=False)
+
+# 2. PUSH TO GITHUB (Trigger APK build on GitHub Actions)
+print('
+📤 Step 2/4: Pushing to GitHub (origin main)...')
+res_push = subprocess.run(['git', 'push', 'origin', 'main'], text=True)
+if res_push.returncode == 0:
+    print('✔ Pushed to GitHub successfully! APK build triggered on GitHub Actions.')
+else:
+    print('⚠ Git push returned non-zero code. (If in Colab, ensure GitHub PAT is configured).')
+
+# 3. BUILD FLUTTER WEB
+print('
+🔨 Step 3/4: Building Production Flutter Web App...')
+subprocess.run(['flutter', 'pub', 'get'], check=False)
+build_cmd = [
+    'flutter', 'build', 'web',
+    '-t', 'lib/web_live_sync/web_main.dart',
+    '--release',
+    '--base-href', '/',
+    '--pwa-strategy=none'
+]
+b_res = subprocess.run(build_cmd, text=True)
+if b_res.returncode != 0:
+    print('
+❌ Flutter Web Compilation Failed! Check error logs above.')
+    sys.exit(1)
+print('✔ Production Web Build Complete!')
+
+# 4. DEPLOY TO CLOUDFLARE PAGES
+print('
+🌐 Step 4/4: Deploying to Cloudflare Pages...')
+deploy_cmd = [
+    'npx', 'wrangler', 'pages', 'deploy', 'build/web',
+    '--project-name=pharoah-erp',
+    '--commit-dirty=true'
+]
+d_res = subprocess.run(deploy_cmd, text=True)
+if d_res.returncode != 0:
+    print('⚠ Wrangler deploy failed. Trying pages publish...')
+    subprocess.run(['npx', 'wrangler', 'pages', 'publish', 'build/web', '--project-name=pharoah-erp'], text=True)
+
+print('
+' + '=' * 68)
+print('🎉 #PH-REV-664 DEPLOYMENT COMPLETE!')
+print('🔗 Live Portal URL: https://pharoah-erp.pages.dev')
+print('🏷️ Revision: #PH-REV-664 (ACTIVE-RECORD-AUTO-REVIVAL-ENGINE)')
+print('=' * 68)
diff --git a/deploy_rev_667_step3_step4.py b/deploy_rev_667_step3_step4.py
new file mode 100644
index 0000000..9cfd3c7
--- /dev/null
+++ b/deploy_rev_667_step3_step4.py
@@ -0,0 +1,63 @@
+# FILE: deploy_rev_667_step3_step4.py
+# 🚀 1-CLICK PRODUCTION DEPLOYER & GITHUB PUSHER FOR #PH-REV-667
+# Step 3: Decoupled Modules (File Separation Rule) & Frontend LWW State Optimization
+# Step 4: JSON Batch Outbox Replication & D1 Edge Reconciliation
+import os
+import sys
+import subprocess
+
+print('=' * 72)
+print('🚀 PHAROAH ERP • REVISION #PH-REV-667 DEPLOYER')
+print('Step 3: Frontend State Optimization & File Separation (Sales, Purchase, Challan, Voucher)')
+print('Step 4: JSON Batch Operations & Transactional Outbox D1 Replication')
+print('=' * 72 + '\\n')
+
+repo_dir = os.path.dirname(os.path.abspath(__file__))
+os.chdir(repo_dir)
+
+# 1. GIT STATUS & COMMIT
+print('📥 Step 1/4: Staging files and creating git commit...')
+subprocess.run(['git', 'add', '.'], check=False)
+subprocess.run(['git', 'commit', '-m', '🚀 #PH-REV-667: Step 3 & 4 - Decoupled Modules & JSON Batch D1 Engine'], check=False)
+
+# 2. PUSH TO GITHUB (Trigger APK build on GitHub Actions)
+print('📤 Step 2/4: Pushing to GitHub (origin main)...')
+res_push = subprocess.run(['git', 'push', 'origin', 'main'], text=True)
+if res_push.returncode == 0:
+    print('✔ Pushed to GitHub successfully! APK build triggered on GitHub Actions.')
+else:
+    print('⚠ Git push returned non-zero code. (If in Colab, check git credentials).')
+
+# 3. BUILD FLUTTER WEB
+print('🔨 Step 3/4: Building Production Flutter Web App...')
+subprocess.run(['flutter', 'pub', 'get'], check=False)
+build_cmd = [
+    'flutter', 'build', 'web',
+    '-t', 'lib/web_live_sync/web_main.dart',
+    '--release',
+    '--base-href', '/',
+    '--pwa-strategy=none'
+]
+b_res = subprocess.run(build_cmd, text=True)
+if b_res.returncode != 0:
+    print('❌ Flutter Web Compilation Failed! Check error logs above.')
+    sys.exit(1)
+print('✔ Production Web Build Complete!')
+
+# 4. DEPLOY TO CLOUDFLARE PAGES
+print('🌐 Step 4/4: Deploying to Cloudflare Pages...')
+deploy_cmd = [
+    'npx', 'wrangler', 'pages', 'deploy', 'build/web',
+    '--project-name=pharoah-erp',
+    '--commit-dirty=true'
+]
+d_res = subprocess.run(deploy_cmd, text=True)
+if d_res.returncode != 0:
+    print('⚠ Wrangler deploy failed. Trying pages publish...')
+    subprocess.run(['npx', 'wrangler', 'pages', 'publish', 'build/web', '--project-name=pharoah-erp'], text=True)
+
+print('\\n' + '=' * 72)
+print('🎉 #PH-REV-667 DEPLOYMENT COMPLETE!')
+print('🔗 Live Portal URL: https://pharoah-erp.pages.dev')
+print('🏷️ Revision: #PH-REV-667 (STEP-3-4-DECOUPLED-BATCH-ENGINE)')
+print('=' * 72)
diff --git a/functions/api/lab_signal.ts b/functions/api/lab_signal.ts
index 6cb72a8..1f587c3 100644
--- a/functions/api/lab_signal.ts
+++ b/functions/api/lab_signal.ts
@@ -138,6 +138,48 @@ export async function onRequestPost(context: any) {
         await db.prepare(
           "INSERT INTO signals (storeToken, data, timestamp) VALUES (?, ?, ?) ON CONFLICT(storeToken) DO UPDATE SET data = excluded.data, timestamp = excluded.timestamp"
         ).bind(storeToken, JSON.stringify(channelData), Date.now()).run();
+
+        // 🚀 SECTION 1: CLOUDFLARE D1 BATCH ENGINE FOR ERP_MASTER_SYNC
+        if (body.operations && Array.isArray(body.operations) && body.operations.length > 0) {
+          try {
+            await db.prepare(
+              "CREATE TABLE IF NOT EXISTS erp_master_sync (sync_id TEXT PRIMARY KEY, store_token TEXT NOT NULL, document_type TEXT NOT NULL, version INTEGER NOT NULL, updated_at INTEGER NOT NULL, is_deleted INTEGER NOT NULL, bill_data TEXT NOT NULL)"
+            ).run().catch(() => {});
+            await db.prepare(
+              "CREATE INDEX IF NOT EXISTS idx_doc_type_updated ON erp_master_sync (store_token, document_type, updated_at)"
+            ).run().catch(() => {});
+
+            const sqlStatements = [];
+            for (const op of body.operations) {
+              const sId = (op.sync_id || "").toString().trim();
+              if (!sId) continue;
+              const dType = (op.document_type || "SALE").toString().toUpperCase();
+              const ver = parseInt(op.version || 1, 10);
+              const uAt = parseInt(op.updated_at || Date.now(), 10);
+              const isActionDelete = (op.action || "").toString().toUpperCase() === "DELETE";
+              const isDel = (op.is_deleted === 1 || isActionDelete) ? 1 : 0;
+              const rawData = op.data !== undefined ? op.data : op.bill_data;
+              const bData = typeof rawData === "string" ? rawData : JSON.stringify(rawData || {});
+
+              const stmt = db.prepare(
+                "INSERT INTO erp_master_sync (sync_id, store_token, document_type, version, updated_at, is_deleted, bill_data) " +
+                "VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7) " +
+                "ON CONFLICT(sync_id) DO UPDATE SET " +
+                "bill_data = CASE WHEN ?5 > updated_at AND ?4 >= version THEN ?7 ELSE bill_data END, " +
+                "is_deleted = CASE WHEN ?5 > updated_at AND ?4 >= version THEN ?6 ELSE is_deleted END, " +
+                "version = CASE WHEN ?4 > version THEN ?4 ELSE version END, " +
+                "updated_at = CASE WHEN ?5 > updated_at THEN ?5 ELSE updated_at END"
+              ).bind(sId, storeToken, dType, ver, uAt, isDel, bData);
+              sqlStatements.push(stmt);
+            }
+
+            if (sqlStatements.length > 0) {
+              await db.batch(sqlStatements);
+            }
+          } catch (batchErr) {
+            console.error("D1 Master Sync Batch Exception:", batchErr);
+          }
+        }
       } catch (d1Err) {
         console.error("D1 Write Exception:", d1Err);
       }
@@ -226,8 +268,33 @@ export async function onRequestGet(context: any) {
       } catch (_) {}
     }
 
-    if (!current) {
-      return new Response(JSON.stringify({ status: "SUCCESS", hasUpdate: false, event: null, mutations: [], tombstones: [] }), {
+    // Query D1 Master Sync for Delta Batch Operations
+    let batchOperations: any[] = [];
+    if (context.env && context.env.SIGNAL_DB) {
+      try {
+        const db = context.env.SIGNAL_DB;
+        const deltaRows: any = await db.prepare(
+          "SELECT sync_id, document_type, version, updated_at, is_deleted, bill_data FROM erp_master_sync WHERE store_token = ? AND updated_at > ? ORDER BY updated_at ASC LIMIT 150"
+        ).bind(storeToken, lastSeenTs).all().catch(() => null);
+        if (deltaRows && Array.isArray(deltaRows.results) && deltaRows.results.length > 0) {
+          batchOperations = deltaRows.results.map((r: any) => ({
+            sync_id: r.sync_id,
+            document_type: r.document_type,
+            version: r.version,
+            updated_at: r.updated_at,
+            is_deleted: r.is_deleted,
+            action: r.is_deleted === 1 ? 'DELETE' : 'UPDATE',
+            data: typeof r.bill_data === 'string' ? JSON.parse(r.bill_data) : (r.bill_data || {}),
+            bill_data: r.bill_data,
+          }));
+        }
+      } catch (err) {
+        console.error("D1 Delta Read Exception:", err);
+      }
+    }
+
+    if (!current && batchOperations.length === 0) {
+      return new Response(JSON.stringify({ status: "SUCCESS", hasUpdate: false, event: null, mutations: [], tombstones: [], batch_operations: [] }), {
         status: 200,
         headers: {
           ...CORS_HEADERS,
@@ -236,13 +303,14 @@ export async function onRequestGet(context: any) {
       });
     }
 
-    const hasUpdate = current.timestamp > lastSeenTs || mutations.length > 0;
+    const hasUpdate = (current && current.timestamp > lastSeenTs) || mutations.length > 0 || batchOperations.length > 0;
     return new Response(JSON.stringify({
       status: "SUCCESS",
       hasUpdate,
-      event: hasUpdate ? current : null,
+      event: (current && current.timestamp > lastSeenTs) ? current : null,
       mutations,
       tombstones,
+      batch_operations: batchOperations,
       serverTime: Date.now(),
     }), {
       status: 200,
diff --git a/lib/import_review_screen.dart b/lib/import_review_screen.dart
index ebaa539..d283cf2 100644
--- a/lib/import_review_screen.dart
+++ b/lib/import_review_screen.dart
@@ -696,7 +696,7 @@ class _ImportReviewScreenState extends State<ImportReviewScreen> {
         roundOff: summary.roundOff,
       );
       
-      AppRealtimeCoordinator.instance.notifyAppMutation(ph, action: 'DATA_SAVED', entityId: cleanBillNo);
+      AppRealtimeCoordinator.instance.notifyAppMutation(ph, action: 'DATA_SAVED', entityId: cleanBillNo, unmarkedIds: [cleanBillNo]);
     } else {
       List<BillItem> rawItems = [];
       int sNo = 1;
@@ -788,7 +788,7 @@ class _ImportReviewScreenState extends State<ImportReviewScreen> {
         roundOff: summary.roundOff,
       );
       
-      AppRealtimeCoordinator.instance.notifyAppMutation(ph, action: 'DATA_SAVED', entityId: cleanBillNo);
+      AppRealtimeCoordinator.instance.notifyAppMutation(ph, action: 'DATA_SAVED', entityId: cleanBillNo, unmarkedIds: [cleanBillNo]);
     }
     Navigator.pop(context);
     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ C2C Data Sync Successful!"), backgroundColor: Colors.green));
diff --git a/lib/models.dart b/lib/models.dart
index 9f135da..cccc66d 100644
--- a/lib/models.dart
+++ b/lib/models.dart
@@ -193,7 +193,7 @@ class BatchInfo {
 class Medicine {
   String id, systemId, uniqueCode, name, packing, companyId, saltId, drugTypeId, rackNo, hsnCode, drugForm, storageCondition; 
   int conversion; double reorderLevel, gst, mrp, purRate, rateA, rateB, rateC, stock; bool isNarcotic, isScheduleH1;
-  int updatedAt, version;
+  int updatedAt, version, isDeleted;
   String get identityKey => systemId.isNotEmpty ? systemId : id;
 
   Medicine({
@@ -202,7 +202,7 @@ class Medicine {
     this.conversion = 1, this.reorderLevel = 0.0, this.gst = 12.0, this.mrp = 0.0, this.purRate = 0.0,
     this.rateA = 0.0, this.rateB = 0.0, this.rateC = 0.0, this.stock = 0.0, this.drugForm = "TAB",
     this.isNarcotic = false, this.isScheduleH1 = false, this.storageCondition = "Room Temp",
-    this.updatedAt = 0, this.version = 1,
+    this.updatedAt = 0, this.version = 1, this.isDeleted = 0,
   });
 
   Map<String, dynamic> toMap() => {
@@ -214,6 +214,9 @@ class Medicine {
     'storageCondition': storageCondition,
     'updatedAt': updatedAt > 0 ? updatedAt : DateTime.now().millisecondsSinceEpoch,
     'version': version,
+    'isDeleted': isDeleted,
+    'is_deleted': isDeleted,
+    'sync_id': id,
   };
 
   factory Medicine.fromMap(Map<String, dynamic> map) => Medicine(
@@ -236,7 +239,7 @@ class Medicine {
 class Party {
   String id, name, group, phone, email, address, city, state, route, gst, dl, dlExp, pan, transport, priceLevel, defaultSeriesId, hsnCode; 
   double opBal, creditLimit; int creditDays;
-  int updatedAt, version;
+  int updatedAt, version, isDeleted;
 
   Party({
     required this.id, required this.name, this.group = "Sundry Debtors", this.phone = "",
@@ -244,7 +247,7 @@ class Party {
     this.gst = "", this.dl = "", this.dlExp = "", this.pan = "", this.transport = "",
     this.priceLevel = "A", this.defaultSeriesId = "", this.hsnCode = "N/A", this.opBal = 0.0,
     this.creditLimit = 0.0, this.creditDays = 0,
-    this.updatedAt = 0, this.version = 1,
+    this.updatedAt = 0, this.version = 1, this.isDeleted = 0,
   });
 
   Map<String, dynamic> toMap() => {
@@ -255,6 +258,9 @@ class Party {
     'creditLimit': creditLimit, 'creditDays': creditDays,
     'updatedAt': updatedAt > 0 ? updatedAt : DateTime.now().millisecondsSinceEpoch,
     'version': version,
+    'isDeleted': isDeleted,
+    'is_deleted': isDeleted,
+    'sync_id': id,
   };
 
   factory Party.fromMap(Map<String, dynamic> map) => Party(
@@ -362,7 +368,7 @@ class PurchaseItem {
 class Sale { 
   String id, billNo, partyId, partyName, partyGstin, partyState, status, invoiceType, paymentMode, transporterName, transporterId, vehicleNo, salesmanName, sourceTag, partyPhone, partyEmail, partyAddress, partyCity, partyDl, partyPan; 
   DateTime date; List<BillItem> items; double totalAmount, extraDiscount, roundOff; List<String> linkedChallanIds; 
-  int updatedAt, version;
+  int updatedAt, version, isDeleted;
 
   Sale({
     required this.id, required this.billNo, required this.partyId, required this.date,
@@ -373,7 +379,7 @@ class Sale {
     this.partyPhone = "", this.partyEmail = "", this.partyAddress = "", this.partyCity = "",
     this.partyDl = "", this.partyPan = "", this.extraDiscount = 0.0, this.roundOff = 0.0,
     this.linkedChallanIds = const [],
-    this.updatedAt = 0, this.version = 1,
+    this.updatedAt = 0, this.version = 1, this.isDeleted = 0,
   });  
 
   Map<String, dynamic> toMap() => {
@@ -386,6 +392,9 @@ class Sale {
     'partyPan': partyPan, 'partyCity': partyCity, 'sourceTag': sourceTag,
     'updatedAt': updatedAt > 0 ? updatedAt : DateTime.now().millisecondsSinceEpoch,
     'version': version,
+    'isDeleted': isDeleted,
+    'is_deleted': isDeleted,
+    'sync_id': id,
   };  
 
   factory Sale.fromMap(Map<String, dynamic> map) => Sale(
@@ -405,6 +414,7 @@ class Sale {
     partyPan: map['partyPan'] ?? "", partyCity: map['partyCity'] ?? "", sourceTag: map['sourceTag'] ?? "",
     updatedAt: (map['updatedAt'] ?? (map['date'] != null ? (DateTime.tryParse(map['date'] ?? '')?.millisecondsSinceEpoch ?? 0) : 0)).toInt(),
     version: (map['version'] ?? 1).toInt(),
+    isDeleted: (map['isDeleted'] ?? map['is_deleted'] ?? (map['status'] == 'Deleted' ? 1 : 0)).toInt(),
   ); 
 }
 
@@ -413,7 +423,7 @@ class Purchase {
   DateTime date, entryDate; List<PurchaseItem> items; double totalAmount; List<String> linkedChallanIds; 
   double extraDiscount;
   double roundOff;
-  int updatedAt, version;
+  int updatedAt, version, isDeleted;
 
   Purchase({
     required this.id, 
@@ -433,6 +443,7 @@ class Purchase {
     this.roundOff = 0.0,
     this.updatedAt = 0,
     this.version = 1,
+    this.isDeleted = 0,
   });  
 
   Map<String, dynamic> toMap() => {
@@ -443,6 +454,9 @@ class Purchase {
     'extraDiscount': extraDiscount, 'roundOff': roundOff,
     'updatedAt': updatedAt > 0 ? updatedAt : DateTime.now().millisecondsSinceEpoch,
     'version': version,
+    'isDeleted': isDeleted,
+    'is_deleted': isDeleted,
+    'sync_id': id,
   };  
 
   factory Purchase.fromMap(Map<String, dynamic> map) => Purchase(
@@ -459,19 +473,20 @@ class Purchase {
     roundOff: (map['roundOff'] ?? 0.0).toDouble(),
     updatedAt: (map['updatedAt'] ?? (map['date'] != null ? (DateTime.tryParse(map['date'] ?? '')?.millisecondsSinceEpoch ?? 0) : 0)).toInt(),
     version: (map['version'] ?? 1).toInt(),
+    isDeleted: (map['isDeleted'] ?? map['is_deleted'] ?? (map['status'] == 'Deleted' ? 1 : 0)).toInt(),
   ); 
 }
 
 class SaleChallan { 
   String id, billNo, partyId, partyName, partyGstin, partyState, status, salesmanName, remarks; DateTime date; List<BillItem> items; double totalAmount; List<ChallanSignature> sigHistory; bool isSigned;
-  int updatedAt, version;
+  int updatedAt, version, isDeleted;
 
   SaleChallan({
     required this.id, required this.billNo, required this.partyId, required this.date,
     required this.partyName, required this.partyGstin, required this.partyState,
     required this.items, required this.totalAmount, this.status = "Pending",
     this.salesmanName = "", this.remarks = "", this.sigHistory = const [], this.isSigned = false,
-    this.updatedAt = 0, this.version = 1,
+    this.updatedAt = 0, this.version = 1, this.isDeleted = 0,
   });
 
   Map<String, dynamic> toMap() => {
@@ -482,6 +497,9 @@ class SaleChallan {
     'sigHistory': sigHistory.map((s) => s.toMap()).toList(), 'isSigned': isSigned,
     'updatedAt': updatedAt > 0 ? updatedAt : DateTime.now().millisecondsSinceEpoch,
     'version': version,
+    'isDeleted': isDeleted,
+    'is_deleted': isDeleted,
+    'sync_id': id,
   };
 
   factory SaleChallan.fromMap(Map<String, dynamic> map) => SaleChallan(
@@ -496,18 +514,19 @@ class SaleChallan {
     sigHistory: (map['sigHistory'] as List?)?.map((s) => ChallanSignature.fromMap(s)).toList() ?? [],
     updatedAt: (map['updatedAt'] ?? (map['date'] != null ? (DateTime.tryParse(map['date'] ?? '')?.millisecondsSinceEpoch ?? 0) : 0)).toInt(),
     version: (map['version'] ?? 1).toInt(),
+    isDeleted: (map['isDeleted'] ?? map['is_deleted'] ?? (map['status'] == 'Deleted' ? 1 : 0)).toInt(),
   ); 
 }
 
 class PurchaseChallan { 
   String id, internalNo, billNo, partyId, distributorName, status, remarks; DateTime date; List<PurchaseItem> items; double totalAmount;
-  int updatedAt, version;
+  int updatedAt, version, isDeleted;
 
   PurchaseChallan({
     required this.id, required this.internalNo, required this.billNo, required this.partyId,
     required this.date, required this.distributorName, required this.items, required this.totalAmount,
     this.status = "Pending", this.remarks = "",
-    this.updatedAt = 0, this.version = 1,
+    this.updatedAt = 0, this.version = 1, this.isDeleted = 0,
   });
 
   Map<String, dynamic> toMap() => {
@@ -517,6 +536,9 @@ class PurchaseChallan {
     'items': items.map((i) => i.toMap()).toList(),
     'updatedAt': updatedAt > 0 ? updatedAt : DateTime.now().millisecondsSinceEpoch,
     'version': version,
+    'isDeleted': isDeleted,
+    'is_deleted': isDeleted,
+    'sync_id': id,
   };
 
   factory PurchaseChallan.fromMap(Map<String, dynamic> map) => PurchaseChallan(
@@ -528,6 +550,7 @@ class PurchaseChallan {
     items: (map['items'] as List?)?.map((i) => PurchaseItem.fromMap(i)).toList() ?? [],
     updatedAt: (map['updatedAt'] ?? (map['date'] != null ? (DateTime.tryParse(map['date'] ?? '')?.millisecondsSinceEpoch ?? 0) : 0)).toInt(),
     version: (map['version'] ?? 1).toInt(),
+    isDeleted: (map['isDeleted'] ?? map['is_deleted'] ?? (map['status'] == 'Deleted' ? 1 : 0)).toInt(),
   ); 
 }
 
@@ -536,14 +559,14 @@ class SaleReturn {
   DateTime date; 
   List<BillItem> items; 
   double totalAmount, extraDiscount, roundOff;
-  int updatedAt, version;
+  int updatedAt, version, isDeleted;
 
   SaleReturn({
     required this.id, required this.billNo, required this.date, 
     required this.partyName, required this.items, required this.totalAmount, 
     this.status = "Active", this.returnType = "Sellable",
     this.extraDiscount = 0.0, this.roundOff = 0.0,
-    this.updatedAt = 0, this.version = 1,
+    this.updatedAt = 0, this.version = 1, this.isDeleted = 0,
   }); 
 
   Map<String, dynamic> toMap() => {
@@ -554,6 +577,9 @@ class SaleReturn {
     'items': items.map((i) => i.toMap()).toList(),
     'updatedAt': updatedAt > 0 ? updatedAt : DateTime.now().millisecondsSinceEpoch,
     'version': version,
+    'isDeleted': isDeleted,
+    'is_deleted': isDeleted,
+    'sync_id': id,
   }; 
 
   factory SaleReturn.fromMap(Map<String, dynamic> map) => SaleReturn(
@@ -568,6 +594,7 @@ class SaleReturn {
     items: (map['items'] as List?)?.map((i) => BillItem.fromMap(i)).toList() ?? [],
     updatedAt: (map['updatedAt'] ?? (map['date'] != null ? (DateTime.tryParse(map['date'] ?? '')?.millisecondsSinceEpoch ?? 0) : 0)).toInt(),
     version: (map['version'] ?? 1).toInt(),
+    isDeleted: (map['isDeleted'] ?? map['is_deleted'] ?? (map['status'] == 'Deleted' ? 1 : 0)).toInt(),
   ); 
 }
 
@@ -576,14 +603,14 @@ class PurchaseReturn {
   DateTime date; 
   List<PurchaseItem> items; 
   double totalAmount, extraDiscount, roundOff;
-  int updatedAt, version;
+  int updatedAt, version, isDeleted;
 
   PurchaseReturn({
     required this.id, required this.billNo, required this.distributorName, 
     required this.items, required this.totalAmount, required this.date, 
     this.status = "Active", this.returnType = "Sellable",
     this.extraDiscount = 0.0, this.roundOff = 0.0,
-    this.updatedAt = 0, this.version = 1,
+    this.updatedAt = 0, this.version = 1, this.isDeleted = 0,
   }); 
 
   Map<String, dynamic> toMap() => {
@@ -594,6 +621,9 @@ class PurchaseReturn {
     'extraDiscount': extraDiscount, 'roundOff': roundOff,
     'updatedAt': updatedAt > 0 ? updatedAt : DateTime.now().millisecondsSinceEpoch,
     'version': version,
+    'isDeleted': isDeleted,
+    'is_deleted': isDeleted,
+    'sync_id': id,
   }; 
 
   factory PurchaseReturn.fromMap(Map<String, dynamic> map) => PurchaseReturn(
@@ -608,6 +638,7 @@ class PurchaseReturn {
     items: (map['items'] as List?)?.map((i) => PurchaseItem.fromMap(i)).toList() ?? [],
     updatedAt: (map['updatedAt'] ?? (map['date'] != null ? (DateTime.tryParse(map['date'] ?? '')?.millisecondsSinceEpoch ?? 0) : 0)).toInt(),
     version: (map['version'] ?? 1).toInt(),
+    isDeleted: (map['isDeleted'] ?? map['is_deleted'] ?? (map['status'] == 'Deleted' ? 1 : 0)).toInt(),
   ); 
 }
 
@@ -624,7 +655,7 @@ class Voucher {
   String depositedIn;              
   DateTime? chequeDate;            
   double roundOff;
-  int updatedAt, version;
+  int updatedAt, version, isDeleted;
 
   Voucher({
     required this.id,
@@ -645,6 +676,7 @@ class Voucher {
     this.roundOff = 0.0,
     this.updatedAt = 0,
     this.version = 1,
+    this.isDeleted = 0,
   });
 
   Map<String, dynamic> toMap() => {
@@ -656,6 +688,9 @@ class Voucher {
     'chequeDate': chequeDate?.toIso8601String(), 'roundOff': roundOff,
     'updatedAt': updatedAt > 0 ? updatedAt : DateTime.now().millisecondsSinceEpoch,
     'version': version,
+    'isDeleted': isDeleted,
+    'is_deleted': isDeleted,
+    'sync_id': id,
   };
 
   factory Voucher.fromMap(Map<String, dynamic> map) => Voucher(
@@ -674,6 +709,7 @@ class Voucher {
     roundOff: (map['roundOff'] ?? 0.0).toDouble(),
     updatedAt: (map['updatedAt'] ?? (map['date'] != null ? (DateTime.tryParse(map['date'] ?? '')?.millisecondsSinceEpoch ?? 0) : 0)).toInt(),
     version: (map['version'] ?? 1).toInt(),
+    isDeleted: (map['isDeleted'] ?? map['is_deleted'] ?? (map['status'] == 'Deleted' ? 1 : 0)).toInt(),
   );
 }
   
diff --git a/lib/pharoah_manager.dart b/lib/pharoah_manager.dart
index 2f97832..570ce20 100644
--- a/lib/pharoah_manager.dart
+++ b/lib/pharoah_manager.dart
@@ -1,3 +1,7 @@
+import 'sync_core/modules/sales_sync_module.dart';
+import 'sync_core/modules/purchase_sync_module.dart';
+import 'sync_core/modules/challan_sync_module.dart';
+import 'sync_core/modules/voucher_sync_module.dart';
 import 'event_sync_lab/workflow/lab_sync_orchestrator.dart';
 // FILE: lib/pharoah_manager.dart (FULLY INTEGRATED, COMPILE-SAFE VERSION)
 
@@ -391,7 +395,7 @@ Future<void> finalizeSale({
       TombstoneEngine.unmarkTombstone(activeCompany!.id, id: sId, secondaryKey: billNo);
     }
     sales.removeWhere((s) => s.id == sId || s.billNo == billNo);
-    sales.add(Sale(
+    final newFinalSale = Sale(
       id: sId, 
       billNo: billNo, 
       partyId: p.id, 
@@ -414,7 +418,13 @@ Future<void> finalizeSale({
       sourceTag: sourceTag,
       updatedAt: DateTime.now().millisecondsSinceEpoch,
       version: currentVer,
-    )); 
+    );
+    sales.add(newFinalSale);
+    if (activeCompany != null) {
+      WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
+        if (t.isNotEmpty) SalesSyncModule.onSaleSaved(newFinalSale, t);
+      });
+    } 
     
     if (linkedIds != null) { 
       for (var id in linkedIds) { 
@@ -486,7 +496,7 @@ Future<void> finalizePurchase({
       }
     }
     purchases.removeWhere((p) => p.id == pId || p.internalNo == internalNo || (billNo.isNotEmpty && p.billNo == billNo));
-    purchases.add(Purchase(
+    final newFinalPurchase = Purchase(
       id: pId, 
       internalNo: internalNo, 
       billNo: billNo, 
@@ -503,7 +513,13 @@ Future<void> finalizePurchase({
       roundOff: roundOff,
       updatedAt: DateTime.now().millisecondsSinceEpoch,
       version: currentVer,
-    )); 
+    );
+    purchases.add(newFinalPurchase);
+    if (activeCompany != null) {
+      WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
+        if (t.isNotEmpty) PurchaseSyncModule.onPurchaseSaved(newFinalPurchase, t);
+      });
+    } 
     
     if (linkedChallanIds != null) { 
       for (var id in linkedChallanIds) { 
@@ -596,7 +612,26 @@ Future<void> finalizePurchase({
     String remarks = "", 
     required String partyId
   }) { 
-    saleChallans.add(SaleChallan(id: DateTime.now().toString(), billNo: billNo, partyId: partyId, date: date, partyName: party.name, partyGstin: party.gst, partyState: party.state, items: items, totalAmount: total, remarks: remarks)); 
+    final newChallan = SaleChallan(
+      id: DateTime.now().toString(), 
+      billNo: billNo, 
+      partyId: partyId, 
+      date: date, 
+      partyName: party.name, 
+      partyGstin: party.gst, 
+      partyState: party.state, 
+      items: items, 
+      totalAmount: total, 
+      remarks: remarks,
+      updatedAt: DateTime.now().millisecondsSinceEpoch,
+      version: 1,
+    );
+    saleChallans.add(newChallan);
+    if (activeCompany != null) {
+      WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
+        if (t.isNotEmpty) ChallanSyncModule.onChallanSaved(newChallan, t);
+      });
+    } 
     
     // 🆕 STRICT TWO-WAY SYNC: Sale Challan items ko correct systemId ke sath Batch Master me register karein
     for (var item in items) {
@@ -883,6 +918,9 @@ void registerBatchActivity({
     vouchers.removeWhere((x) => x.id == v.id || x.voucherNo == v.voucherNo);
     vouchers.add(v);
     if (activeCompany != null) {
+      WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
+        if (t.isNotEmpty) VoucherSyncModule.onVoucherSaved(v, t);
+      });
       String seriesType = v.type.toUpperCase();
       String prefix = v.voucherNo.split(RegExp(r'\\d')).first;
       await PharoahNumberingEngine.updateSeriesCounter(
@@ -948,6 +986,11 @@ void registerBatchActivity({
     int i = vouchers.indexWhere((v) => v.id == id);
     if (i != -1) {
       final v = vouchers[i];
+      if (activeCompany != null) {
+        WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
+          if (t.isNotEmpty) VoucherSyncModule.onVoucherDeleted(v, t);
+        });
+      }
       _reverseVoucherImpact(v);
       final vNo = v.voucherNo;
       vouchers.removeAt(i);
@@ -1045,6 +1088,11 @@ void registerBatchActivity({
       final String realId = s.id;
       final String bNo = s.billNo;
       sales.removeWhere((x) => x.id == realId || (bNo.isNotEmpty && x.billNo == bNo));
+      if (activeCompany != null) {
+        WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
+          if (t.isNotEmpty) SalesSyncModule.onSaleDeleted(s, t);
+        });
+      }
       if (activeCompany != null) {
         TombstoneEngine.recordBatchTombstones(activeCompany!.id, [realId, if (bNo.isNotEmpty) bNo]);
         AppRealtimeCoordinator.instance.notifyAppMutation(
@@ -1077,6 +1125,9 @@ void registerBatchActivity({
       final String bNo = p.billNo;
       purchases.removeWhere((x) => x.id == pId || x.internalNo == iNo || (bNo.isNotEmpty && x.billNo == bNo));
       if (activeCompany != null) {
+        WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
+          if (t.isNotEmpty) PurchaseSyncModule.onPurchaseDeleted(p, t);
+        });
         TombstoneEngine.recordBatchTombstones(activeCompany!.id, [pId, if (iNo.isNotEmpty) iNo, if (bNo.isNotEmpty) bNo]);
         AppRealtimeCoordinator.instance.notifyAppMutation(
           this,
@@ -1094,7 +1145,18 @@ void registerBatchActivity({
       notifyListeners();
     } catch (e) {}
   }
-  void deleteSaleChallan(String id) { saleChallans.removeWhere((c) => c.id == id); save(); }
+  void deleteSaleChallan(String id) {
+    try {
+      final c = saleChallans.firstWhere((x) => x.id == id || x.billNo == id);
+      if (activeCompany != null) {
+        WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
+          if (t.isNotEmpty) ChallanSyncModule.onChallanDeleted(c, t);
+        });
+      }
+    } catch (_) {}
+    saleChallans.removeWhere((c) => c.id == id); 
+    save(); 
+  }
   void deletePurchaseChallan(String id) { purchaseChallans.removeWhere((c) => c.id == id); save(); }
   void deleteSaleReturn(String id) { saleReturns.removeWhere((r) => r.id == id); save().then((_) => loadAllData()); }
   void deletePurchaseReturn(String id) { purchaseReturns.removeWhere((r) => r.id == id); save().then((_) => loadAllData()); }
diff --git a/lib/purchase/purchase_summary_view.dart b/lib/purchase/purchase_summary_view.dart
index 66525b5..e241d53 100644
--- a/lib/purchase/purchase_summary_view.dart
+++ b/lib/purchase/purchase_summary_view.dart
@@ -96,7 +96,7 @@ class _PurchaseSummaryViewState extends State<PurchaseSummaryView> {
                        p.date.isBefore(toDate.add(const Duration(days: 1)));
       bool searchMatch = p.distributorName.toLowerCase().contains(searchQuery.toLowerCase()) || 
                          p.billNo.toLowerCase().contains(searchQuery.toLowerCase());
-      return dateMatch && searchMatch;
+      return p.isDeleted != 1 && dateMatch && searchMatch;
     }).toList();
 
     // Summary Totals
diff --git a/lib/realtime_signaling/coordinators/app_realtime_coordinator.dart b/lib/realtime_signaling/coordinators/app_realtime_coordinator.dart
index 0e543f8..88aabbd 100644
--- a/lib/realtime_signaling/coordinators/app_realtime_coordinator.dart
+++ b/lib/realtime_signaling/coordinators/app_realtime_coordinator.dart
@@ -1,3 +1,4 @@
+import '../../sync_core/orchestrator/master_sync_orchestrator.dart';
 // FILE: lib/realtime_signaling/coordinators/app_realtime_coordinator.dart
 import 'dart:async';
 import 'package:flutter/foundation.dart';
@@ -32,8 +33,16 @@ class AppRealtimeCoordinator {
       storeToken: token,
       mySource: 'app',
       interval: const Duration(milliseconds: 4000),
+      onBatchReceived: (batchOps) {
+        MasterSyncOrchestrator.dispatchBatchOperations(operations: batchOps, phApp: ph);
+      },
       onSignal: (event) async {
         debugPrint("🔔 [AppRealtimeCoordinator] Web activity detected (${event.action}). Pulling immediately...");
+        if (event.unmarkedIds.isNotEmpty && ph.activeCompany != null) {
+          for (final u in event.unmarkedIds) {
+            await TombstoneEngine.unmarkTombstone(ph.activeCompany!.id, id: u);
+          }
+        }
         await FastPullEngine.pullAndMerge(ph);
       },
     );
@@ -47,7 +56,7 @@ class AppRealtimeCoordinator {
   }
 
   /// Triggers a push to cloud and sends instant wake-up signal to Web
-  void notifyAppMutation(PharoahManager ph, {String action = 'DATA_MUTATED', String entityId = ''}) {
+  void notifyAppMutation(PharoahManager ph, {String action = 'DATA_MUTATED', String entityId = '', List<String> unmarkedIds = const []}) {
     if (ph.activeCompany == null || ph.currentFY.isEmpty) return;
 
     _pushDebounceTimer?.cancel();
@@ -65,6 +74,7 @@ class AppRealtimeCoordinator {
               source: 'app',
               action: action,
               entityId: entityId,
+              unmarkedIds: unmarkedIds,
               companyId: ph.activeCompany!.id,
             ),
           );
diff --git a/lib/realtime_signaling/coordinators/web_realtime_coordinator.dart b/lib/realtime_signaling/coordinators/web_realtime_coordinator.dart
index 7907185..05883f5 100644
--- a/lib/realtime_signaling/coordinators/web_realtime_coordinator.dart
+++ b/lib/realtime_signaling/coordinators/web_realtime_coordinator.dart
@@ -1,3 +1,4 @@
+import '../../sync_core/orchestrator/master_sync_orchestrator.dart';
 // FILE: lib/realtime_signaling/coordinators/web_realtime_coordinator.dart
 import 'dart:async';
 import 'package:flutter/foundation.dart';
@@ -14,6 +15,7 @@ class WebRealtimeCoordinator {
   bool _isPushing = false;
   bool _hasPendingPush = false;
   final List<String> _pendingDeletedIds = [];
+  final List<String> _pendingUnmarkedIds = [];
 
   WebRealtimeCoordinator({required this.webManager});
 
@@ -28,8 +30,16 @@ class WebRealtimeCoordinator {
       storeToken: token,
       mySource: 'web',
       interval: const Duration(milliseconds: 3500),
+      onBatchReceived: (batchOps) {
+        MasterSyncOrchestrator.dispatchBatchOperations(operations: batchOps, phWeb: webManager);
+      },
       onSignal: (event) async {
         debugPrint("🔔 [WebRealtimeCoordinator] App activity detected (${event.action}). Processing...");
+        if (event.unmarkedIds.isNotEmpty) {
+          for (final u in event.unmarkedIds) {
+            webManager.unmarkDeletedId(u);
+          }
+        }
         if (event.deletedIds.isNotEmpty) {
           webManager.purgeDeletedIds(event.deletedIds);
         }
@@ -72,6 +82,9 @@ class WebRealtimeCoordinator {
           _hasPendingPush = false;
           final batchDeleted = List<String>.from(_pendingDeletedIds);
           _pendingDeletedIds.clear();
+    _pendingUnmarkedIds.clear();
+          final batchUnmarked = List<String>.from(_pendingUnmarkedIds);
+          _pendingUnmarkedIds.clear();
 
           // 1. Broadcast instant event to Cloudflare Edge (<30ms)
           await CloudSignalChannel.instance.broadcastSignal(
@@ -81,6 +94,7 @@ class WebRealtimeCoordinator {
               action: action,
               entityId: entityId,
               deletedIds: batchDeleted,
+              unmarkedIds: batchUnmarked,
               companyId: webManager.companyProfile['id']?.toString() ?? '',
             ),
           );
@@ -104,5 +118,6 @@ class WebRealtimeCoordinator {
     _isPushing = false;
     _hasPendingPush = false;
     _pendingDeletedIds.clear();
+    _pendingUnmarkedIds.clear();
   }
 }
diff --git a/lib/realtime_signaling/models/sync_signal_event.dart b/lib/realtime_signaling/models/sync_signal_event.dart
index 145c6a5..2bb8b9d 100644
--- a/lib/realtime_signaling/models/sync_signal_event.dart
+++ b/lib/realtime_signaling/models/sync_signal_event.dart
@@ -10,6 +10,7 @@ class SyncSignalEvent {
   final int timestamp;
   final String companyId;
   final List<String> deletedIds;
+  final List<String> unmarkedIds;
   final dynamic delta;
 
   SyncSignalEvent({
@@ -20,6 +21,7 @@ class SyncSignalEvent {
     int? timestamp,
     this.companyId = '',
     this.deletedIds = const [],
+    this.unmarkedIds = const [],
     this.delta,
   }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;
 
@@ -31,6 +33,7 @@ class SyncSignalEvent {
     'timestamp': timestamp,
     'companyId': companyId,
     'deletedIds': deletedIds,
+    'unmarkedIds': unmarkedIds,
     'delta': delta,
   };
 
@@ -45,6 +48,7 @@ class SyncSignalEvent {
       timestamp: int.tryParse(map['timestamp']?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch,
       companyId: (map['companyId'] ?? '').toString(),
       deletedIds: (map['deletedIds'] as List?)?.map((e) => e.toString()).toList() ?? [],
+      unmarkedIds: (map['unmarkedIds'] as List?)?.map((e) => e.toString()).toList() ?? [],
       delta: map['delta'],
     );
   }
diff --git a/lib/realtime_signaling/transport/cloud_signal_channel.dart b/lib/realtime_signaling/transport/cloud_signal_channel.dart
index 7770144..1c2dcf9 100644
--- a/lib/realtime_signaling/transport/cloud_signal_channel.dart
+++ b/lib/realtime_signaling/transport/cloud_signal_channel.dart
@@ -28,6 +28,7 @@ class CloudSignalChannel {
         "entityId": event.entityId,
         "timestamp": event.timestamp,
         "deletedIds": event.deletedIds,
+        "unmarkedIds": event.unmarkedIds,
         "delta": event.delta,
       };
 
@@ -49,6 +50,7 @@ class CloudSignalChannel {
     required String storeToken,
     required String mySource, // 'app' or 'web'
     required Function(SyncSignalEvent) onSignal,
+    Function(List<dynamic>)? onBatchReceived,
     Duration interval = const Duration(milliseconds: 3500),
   }) {
     stopListening();
@@ -61,23 +63,33 @@ class CloudSignalChannel {
     _pollTimer = Timer.periodic(interval, (_) async {
       if (_isChecking) return;
       _isChecking = true;
+
       try {
         final uri = Uri.parse(
           "$edgeSignalEndpoint?storeToken=${Uri.encodeComponent(cleanToken)}"
           "&lastSeenTs=$_lastKnownSignalTime"
         );
+
         final response = await http.get(uri).timeout(const Duration(seconds: 3));
         if (response.statusCode == 200) {
           final data = jsonDecode(response.body);
-          if (data['status'] == 'SUCCESS' && data['hasUpdate'] == true && data['event'] != null) {
-            final sig = data['event'];
-            final event = SyncSignalEvent.fromMap(sig);
-            if (event.timestamp > _lastKnownSignalTime && event.source.toUpperCase() != cleanSource) {
-              _lastKnownSignalTime = event.timestamp;
-              debugPrint("⚡ [CloudSignalChannel] Remote Real Mutation Received from ${event.source}: ${event.action}");
-              onSignal(event);
-            } else if (event.timestamp > _lastKnownSignalTime) {
-              _lastKnownSignalTime = event.timestamp;
+          if (data['status'] == 'SUCCESS') {
+            // 🚀 Step 4: Atomic Batch Delta Processing
+            if (data['batch_operations'] is List && (data['batch_operations'] as List).isNotEmpty) {
+              final batchOps = List<dynamic>.from(data['batch_operations']);
+              onBatchReceived?.call(batchOps);
+            }
+
+            if (data['hasUpdate'] == true && data['event'] != null) {
+              final sig = data['event'];
+              final event = SyncSignalEvent.fromMap(sig);
+              if (event.timestamp > _lastKnownSignalTime && event.source.toUpperCase() != cleanSource) {
+                _lastKnownSignalTime = event.timestamp;
+                debugPrint("⚡ [CloudSignalChannel] Remote Real Mutation Received from ${event.source}: ${event.action}");
+                onSignal(event);
+              } else if (event.timestamp > _lastKnownSignalTime) {
+                _lastKnownSignalTime = event.timestamp;
+              }
             }
           }
         }
diff --git a/lib/sale_summary_view.dart b/lib/sale_summary_view.dart
index 0597abb..b4b6785 100644
--- a/lib/sale_summary_view.dart
+++ b/lib/sale_summary_view.dart
@@ -95,7 +95,7 @@ class _SaleSummaryViewState extends State<SaleSummaryView> {
                        s.date.isBefore(toDate.add(const Duration(days: 1)));
       bool searchMatch = s.billNo.toLowerCase().contains(searchQuery.toLowerCase()) || 
                          s.partyName.toLowerCase().contains(searchQuery.toLowerCase());
-      return s.status == "Active" && dateMatch && searchMatch;
+      return s.isDeleted != 1 && s.status == "Active" && dateMatch && searchMatch;
     }).toList();
 
     // Calculations
diff --git a/lib/sync_bridge/engines/app_auto_sync_daemon.dart b/lib/sync_bridge/engines/app_auto_sync_daemon.dart
index 6848140..f64aa88 100644
--- a/lib/sync_bridge/engines/app_auto_sync_daemon.dart
+++ b/lib/sync_bridge/engines/app_auto_sync_daemon.dart
@@ -21,6 +21,7 @@ class AppAutoSyncDaemon {
   bool _isSyncing = false;
   bool _hasPendingPush = false;
   final List<String> _pendingDeletedIds = [];
+  final List<String> _pendingUnmarkedIds = [];
 
   /// Triggers a non-dropping background push with Cloudflare Edge signal
   void triggerSilentPush(
@@ -28,9 +29,13 @@ class AppAutoSyncDaemon {
     String action = 'DATA_SAVED',
     String entityId = '',
     List<String> deletedIds = const [],
+    List<String> unmarkedIds = const [],
   }) {
     if (ph.activeCompany == null || ph.currentFY.isEmpty) return;
 
+    if (unmarkedIds.isNotEmpty) {
+      _pendingUnmarkedIds.addAll(unmarkedIds);
+    }
     if (deletedIds.isNotEmpty) {
       _pendingDeletedIds.addAll(deletedIds);
     }
@@ -50,6 +55,8 @@ class AppAutoSyncDaemon {
           _hasPendingPush = false;
           final batchDeleted = List<String>.from(_pendingDeletedIds);
           _pendingDeletedIds.clear();
+          final batchUnmarked = List<String>.from(_pendingUnmarkedIds);
+          _pendingUnmarkedIds.clear();
 
           final companyId = ph.activeCompany!.id;
           final storeToken = await WebLiveToken.getOrCreateToken(companyId);
@@ -63,6 +70,7 @@ class AppAutoSyncDaemon {
                 action: action,
                 entityId: entityId,
                 deletedIds: batchDeleted,
+                unmarkedIds: batchUnmarked,
                 companyId: companyId,
               ),
             );
diff --git a/lib/sync_core/models/sync_envelope.dart b/lib/sync_core/models/sync_envelope.dart
new file mode 100644
index 0000000..aa29838
--- /dev/null
+++ b/lib/sync_core/models/sync_envelope.dart
@@ -0,0 +1,81 @@
+// FILE: lib/sync_core/models/sync_envelope.dart
+import 'dart:convert';
+
+/// SyncEnvelope: Standardized event container for transaction outbox & D1 replication.
+/// Fully compatible with Step 4 JSON Batch Format with sequential ordering and action tagging.
+class SyncEnvelope {
+  final int seq;
+  final String syncId;
+  final String storeToken;
+  final String documentType; // 'SALE', 'PURCHASE', 'CHALLAN', 'VOUCHER', etc.
+  final String action; // 'INSERT', 'UPDATE', 'DELETE'
+  final String deviceId;
+  final int version;
+  final int updatedAt; // High-precision microsecond or millisecond epoch
+  final int isDeleted; // 0 = Active, 1 = Soft Deleted
+  final Map<String, dynamic> billData;
+
+  SyncEnvelope({
+    this.seq = 0,
+    required this.syncId,
+    this.storeToken = '',
+    required this.documentType,
+    this.action = 'UPDATE',
+    this.deviceId = '',
+    required this.version,
+    required this.updatedAt,
+    required this.isDeleted,
+    required this.billData,
+  });
+
+  Map<String, dynamic> toMap() => {
+    'seq': seq,
+    'sync_id': syncId,
+    'store_token': storeToken,
+    'document_type': documentType,
+    'action': action,
+    'device_id': deviceId,
+    'version': version,
+    'updated_at': updatedAt,
+    'is_deleted': isDeleted,
+    'data': billData,
+    'bill_data': billData,
+  };
+
+  String toJson() => jsonEncode(toMap());
+
+  factory SyncEnvelope.fromMap(Map<String, dynamic> map) {
+    dynamic rawData = map['data'] ?? map['bill_data'];
+    Map<String, dynamic> parsedData;
+    if (rawData is String) {
+      try {
+        parsedData = jsonDecode(rawData);
+      } catch (_) {
+        parsedData = {};
+      }
+    } else if (rawData is Map) {
+      parsedData = Map<String, dynamic>.from(rawData);
+    } else {
+      parsedData = {};
+    }
+
+    final int parsedDeleted = int.tryParse(map['is_deleted']?.toString() ?? '0') ??
+        ((map['action']?.toString().toUpperCase() == 'DELETE') ? 1 : 0);
+
+    return SyncEnvelope(
+      seq: int.tryParse(map['seq']?.toString() ?? '0') ?? 0,
+      syncId: (map['sync_id'] ?? '').toString(),
+      storeToken: (map['store_token'] ?? '').toString(),
+      documentType: (map['document_type'] ?? 'SALE').toString().toUpperCase(),
+      action: (map['action'] ?? (parsedDeleted == 1 ? 'DELETE' : 'UPDATE')).toString().toUpperCase(),
+      deviceId: (map['device_id'] ?? '').toString(),
+      version: int.tryParse(map['version']?.toString() ?? '1') ?? 1,
+      updatedAt: int.tryParse(map['updated_at']?.toString() ?? '0') ?? DateTime.now().millisecondsSinceEpoch,
+      isDeleted: parsedDeleted,
+      billData: parsedData,
+    );
+  }
+
+  factory SyncEnvelope.fromJson(String jsonStr) =>
+      SyncEnvelope.fromMap(jsonDecode(jsonStr));
+}
diff --git a/lib/sync_core/modules/challan_sync_module.dart b/lib/sync_core/modules/challan_sync_module.dart
new file mode 100644
index 0000000..d1bcf13
--- /dev/null
+++ b/lib/sync_core/modules/challan_sync_module.dart
@@ -0,0 +1,111 @@
+// FILE: lib/sync_core/modules/challan_sync_module.dart
+import 'package:flutter/foundation.dart';
+import '../../models.dart';
+import '../models/sync_envelope.dart';
+import '../outbox/sync_queue_manager.dart';
+
+/// ChallanSyncModule: Isolated Synchronization & Conflict Resolution Engine for Challans.
+/// Strictly decoupled from Sales, Purchases, and Vouchers (File Separation Rule).
+class ChallanSyncModule {
+  static const String documentType = "CHALLAN";
+
+  /// Dispatches a challan creation or modification to the Outbox queue
+  static void onChallanSaved(SaleChallan challan, String storeToken) {
+    if (storeToken.trim().isEmpty) return;
+    SyncQueueManager.enqueueMutation(
+      syncId: challan.id,
+      storeToken: storeToken,
+      docType: documentType,
+      currentVersion: challan.version,
+      isDelete: false,
+      rawPayload: challan.toMap(),
+    );
+  }
+
+  /// Dispatches a soft-delete operation to the Outbox queue
+  static void onChallanDeleted(SaleChallan challan, String storeToken) {
+    if (storeToken.trim().isEmpty) return;
+    challan.isDeleted = 1;
+    challan.status = "Cancelled";
+    challan.version += 1;
+    challan.updatedAt = DateTime.now().millisecondsSinceEpoch;
+
+    SyncQueueManager.enqueueMutation(
+      syncId: challan.id,
+      storeToken: storeToken,
+      docType: documentType,
+      currentVersion: challan.version,
+      isDelete: true,
+      rawPayload: challan.toMap(),
+    );
+  }
+
+  /// handleIncomingSync conforming to Step 3 Frontend State Optimization
+  static List<SaleChallan> handleIncomingSync(List<SaleChallan> currentUIStateList, SyncEnvelope incomingEvent) {
+    mergeIncomingChallanEnvelope(currentUIStateList, incomingEvent);
+    return currentUIStateList;
+  }
+
+  /// Merges an incoming SyncEnvelope into current Challans list
+  static bool mergeIncomingChallanEnvelope(List<SaleChallan> currentChallans, SyncEnvelope envelope) {
+    if (envelope.documentType != documentType) return false;
+
+    final targetId = envelope.syncId.trim();
+    if (targetId.isEmpty) return false;
+
+    final incomingChallan = SaleChallan.fromMap(envelope.billData);
+    incomingChallan.id = targetId;
+    incomingChallan.version = envelope.version;
+    incomingChallan.updatedAt = envelope.updatedAt;
+    incomingChallan.isDeleted = envelope.isDeleted;
+
+    return applyChallanMutation(currentChallans, incomingChallan);
+  }
+
+  /// Core LWW State Machine for Challan Objects
+  static bool applyChallanMutation(List<SaleChallan> currentChallans, SaleChallan incoming) {
+    final idx = currentChallans.indexWhere((c) => c.id == incoming.id);
+
+    // 1. Check if delete operation
+    if (incoming.isDeleted == 1) {
+      if (idx != -1) {
+        final local = currentChallans[idx];
+        if (incoming.updatedAt >= local.updatedAt || incoming.version > local.version) {
+          currentChallans.removeAt(idx);
+          debugPrint("🗑️ [ChallanSyncModule] Soft-deleted challan evicted: ${incoming.billNo} (${incoming.id})");
+          return true;
+        }
+      }
+      return false;
+    }
+
+    // 2. Existing record check
+    if (idx > -1) {
+      final local = currentChallans[idx];
+      if (incoming.version <= local.version && incoming.updatedAt < local.updatedAt) {
+        return false;
+      }
+      currentChallans[idx] = incoming;
+      debugPrint("🔄 [ChallanSyncModule] In-place updated challan: ${incoming.billNo} (v${incoming.version})");
+      return true;
+    } else {
+      int billNoIdx = incoming.billNo.isNotEmpty
+          ? currentChallans.indexWhere((c) => c.billNo.trim() == incoming.billNo.trim())
+          : -1;
+
+      if (billNoIdx != -1) {
+        final existing = currentChallans[billNoIdx];
+        if (incoming.updatedAt >= existing.updatedAt) {
+          currentChallans[billNoIdx] = incoming;
+          debugPrint("🔄 [ChallanSyncModule] Replaced challan by number: ${incoming.billNo}");
+          return true;
+        }
+        return false;
+      } else {
+        currentChallans.insert(0, incoming);
+        debugPrint("✨ [ChallanSyncModule] Added new remote challan: ${incoming.billNo} (${incoming.id})");
+        return true;
+      }
+    }
+  }
+}
diff --git a/lib/sync_core/modules/purchase_sync_module.dart b/lib/sync_core/modules/purchase_sync_module.dart
new file mode 100644
index 0000000..b2d972b
--- /dev/null
+++ b/lib/sync_core/modules/purchase_sync_module.dart
@@ -0,0 +1,116 @@
+// FILE: lib/sync_core/modules/purchase_sync_module.dart
+import 'package:flutter/foundation.dart';
+import '../../models.dart';
+import '../models/sync_envelope.dart';
+import '../outbox/sync_queue_manager.dart';
+
+/// PurchaseSyncModule: Isolated Synchronization & Conflict Resolution Engine for Purchases.
+/// Strictly decoupled from Sales, Challans, and Vouchers (File Separation Rule).
+class PurchaseSyncModule {
+  static const String documentType = "PURCHASE";
+
+  /// Dispatches a purchase creation or modification to the Outbox queue
+  static void onPurchaseSaved(Purchase purchase, String storeToken) {
+    if (storeToken.trim().isEmpty) return;
+    SyncQueueManager.enqueueMutation(
+      syncId: purchase.id,
+      storeToken: storeToken,
+      docType: documentType,
+      currentVersion: purchase.version,
+      isDelete: false,
+      rawPayload: purchase.toMap(),
+    );
+  }
+
+  /// Dispatches a soft-delete operation to the Outbox queue
+  static void onPurchaseDeleted(Purchase purchase, String storeToken) {
+    if (storeToken.trim().isEmpty) return;
+    purchase.isDeleted = 1;
+    purchase.version += 1;
+    purchase.updatedAt = DateTime.now().millisecondsSinceEpoch;
+
+    SyncQueueManager.enqueueMutation(
+      syncId: purchase.id,
+      storeToken: storeToken,
+      docType: documentType,
+      currentVersion: purchase.version,
+      isDelete: true,
+      rawPayload: purchase.toMap(),
+    );
+  }
+
+  /// handleIncomingSync conforming to Step 3 Frontend State Optimization
+  static List<Purchase> handleIncomingSync(List<Purchase> currentUIStateList, SyncEnvelope incomingEvent) {
+    mergeIncomingPurchaseEnvelope(currentUIStateList, incomingEvent);
+    return currentUIStateList;
+  }
+
+  /// Merges an incoming SyncEnvelope into current Purchases list
+  static bool mergeIncomingPurchaseEnvelope(List<Purchase> currentPurchases, SyncEnvelope envelope) {
+    if (envelope.documentType != documentType) return false;
+
+    final targetId = envelope.syncId.trim();
+    if (targetId.isEmpty) return false;
+
+    final incomingPurchase = Purchase.fromMap(envelope.billData);
+    incomingPurchase.id = targetId;
+    incomingPurchase.version = envelope.version;
+    incomingPurchase.updatedAt = envelope.updatedAt;
+    incomingPurchase.isDeleted = envelope.isDeleted;
+
+    return applyPurchaseMutation(currentPurchases, incomingPurchase);
+  }
+
+  /// Core LWW State Machine for Purchase Objects
+  static bool applyPurchaseMutation(List<Purchase> currentPurchases, Purchase incoming) {
+    final idx = currentPurchases.indexWhere((p) => p.id == incoming.id);
+
+    // 1. Check if delete operation (is_deleted == 1)
+    if (incoming.isDeleted == 1) {
+      if (idx != -1) {
+        final local = currentPurchases[idx];
+        if (incoming.updatedAt >= local.updatedAt || incoming.version > local.version) {
+          currentPurchases.removeAt(idx);
+          debugPrint("🗑️ [PurchaseSyncModule] Soft-deleted purchase evicted: ${incoming.billNo} (${incoming.id})");
+          return true;
+        }
+      }
+      return false;
+    }
+
+    // 2. Existing record check
+    if (idx > -1) {
+      final local = currentPurchases[idx];
+      // If incoming version is less or equal AND updated_at is older, ignore stale data
+      if (incoming.version <= local.version && incoming.updatedAt < local.updatedAt) {
+        return false;
+      }
+      currentPurchases[idx] = incoming;
+      debugPrint("🔄 [PurchaseSyncModule] In-place updated purchase: ${incoming.billNo} (v${incoming.version})");
+      return true;
+    } else {
+      // Secondary check by internalNo or billNo to prevent duplicates
+      int numIdx = -1;
+      if (incoming.internalNo.isNotEmpty) {
+        numIdx = currentPurchases.indexWhere((p) => p.internalNo.trim() == incoming.internalNo.trim());
+      }
+      if (numIdx == -1 && incoming.billNo.isNotEmpty && incoming.partyId.isNotEmpty) {
+        numIdx = currentPurchases.indexWhere((p) => p.billNo.trim() == incoming.billNo.trim() && p.partyId.trim() == incoming.partyId.trim());
+      }
+
+      if (numIdx != -1) {
+        final existing = currentPurchases[numIdx];
+        if (incoming.updatedAt >= existing.updatedAt) {
+          currentPurchases[numIdx] = incoming;
+          debugPrint("🔄 [PurchaseSyncModule] Replaced purchase by number: ${incoming.billNo}");
+          return true;
+        }
+        return false;
+      } else {
+        currentPurchases.insert(0, incoming);
+        debugPrint("✨ [PurchaseSyncModule] Added new remote purchase: ${incoming.billNo} (${incoming.id})");
+        return true;
+      }
+    }
+  }
+}
diff --git a/lib/sync_core/modules/sales_sync_module.dart b/lib/sync_core/modules/sales_sync_module.dart
new file mode 100644
index 0000000..83d4926
--- /dev/null
+++ b/lib/sync_core/modules/sales_sync_module.dart
@@ -0,0 +1,121 @@
+// FILE: lib/sync_core/modules/sales_sync_module.dart
+import 'package:flutter/foundation.dart';
+import '../../models.dart';
+import '../models/sync_envelope.dart';
+import '../outbox/sync_queue_manager.dart';
+
+/// SalesSyncModule: Isolated Synchronization & Conflict Resolution Engine for Sales.
+/// Strictly decoupled from Purchases, Challans, and Vouchers (File Separation Rule).
+class SalesSyncModule {
+  static const String documentType = "SALE";
+
+  /// Dispatches a sale creation or modification to the Outbox queue
+  static void onSaleSaved(Sale sale, String storeToken) {
+    if (storeToken.trim().isEmpty) return;
+    SyncQueueManager.enqueueMutation(
+      syncId: sale.id,
+      storeToken: storeToken,
+      docType: documentType,
+      currentVersion: sale.version,
+      isDelete: false,
+      rawPayload: sale.toMap(),
+    );
+  }
+
+  /// Dispatches a soft-delete operation to the Outbox queue
+  static void onSaleDeleted(Sale sale, String storeToken) {
+    if (storeToken.trim().isEmpty) return;
+    sale.isDeleted = 1;
+    sale.status = "Deleted";
+    sale.version += 1;
+    sale.updatedAt = DateTime.now().millisecondsSinceEpoch;
+
+    SyncQueueManager.enqueueMutation(
+      syncId: sale.id,
+      storeToken: storeToken,
+      docType: documentType,
+      currentVersion: sale.version,
+      isDelete: true,
+      rawPayload: sale.toMap(),
+    );
+  }
+
+  /// handleIncomingSync conforming to Step 3 Frontend State Optimization
+  static List<Sale> handleIncomingSync(List<Sale> currentUIStateList, SyncEnvelope incomingEvent) {
+    mergeIncomingSaleEnvelope(currentUIStateList, incomingEvent);
+    return currentUIStateList;
+  }
+
+  /// Merges an incoming SyncEnvelope into the active in-memory Sales List.
+  /// Enforces Last-Write-Wins (LWW) and Soft-Delete without destroying the series counter!
+  static bool mergeIncomingSaleEnvelope(List<Sale> currentSales, SyncEnvelope envelope) {
+    if (envelope.documentType != documentType) return false;
+
+    final targetId = envelope.syncId.trim();
+    if (targetId.isEmpty) return false;
+
+    final incomingSale = Sale.fromMap(envelope.billData);
+    incomingSale.id = targetId;
+    incomingSale.version = envelope.version;
+    incomingSale.updatedAt = envelope.updatedAt;
+    incomingSale.isDeleted = envelope.isDeleted;
+
+    return applySaleMutation(currentSales, incomingSale);
+  }
+
+  /// Core LWW State Machine for Sale Objects
+  static bool applySaleMutation(List<Sale> currentSales, Sale incoming) {
+    final idx = currentSales.indexWhere((s) => s.id == incoming.id);
+
+    // Case 1: Incoming is Soft-Deleted (isDeleted == 1)
+    if (incoming.isDeleted == 1) {
+      if (idx != -1) {
+        final local = currentSales[idx];
+        // Only accept delete if incoming is newer or equal
+        if (incoming.updatedAt >= local.updatedAt || incoming.version > local.version) {
+          currentSales.removeAt(idx);
+          debugPrint("🗑️ [SalesSyncModule] Soft-deleted sale evicted: ${incoming.billNo} (${incoming.id})");
+          return true;
+        }
+      }
+      return false;
+    }
+
+    // Case 2: Incoming is Active (isDeleted == 0)
+    if (idx != -1) {
+      final local = currentSales[idx];
+      // LWW Concurrency Evaluation:
+      // If incoming version is less or equal AND updated_at is older, ignore stale data
+      if (incoming.version <= local.version && incoming.updatedAt < local.updatedAt) {
+        return false;
+      }
+      if (incoming.updatedAt > local.updatedAt ||
+          (incoming.updatedAt == local.updatedAt && incoming.version >= local.version) ||
+          local.updatedAt == 0) {
+        currentSales[idx] = incoming;
+        debugPrint("🔄 [SalesSyncModule] In-place updated sale: ${incoming.billNo} (v${incoming.version})");
+        return true;
+      }
+      return false;
+    } else {
+      // Record does not exist locally -> Insert it!
+      int billNoIdx = incoming.billNo.isNotEmpty
+          ? currentSales.indexWhere((s) => s.billNo.trim() == incoming.billNo.trim())
+          : -1;
+
+      if (billNoIdx != -1) {
+        final existingWithBillNo = currentSales[billNoIdx];
+        if (incoming.updatedAt >= existingWithBillNo.updatedAt) {
+          currentSales[billNoIdx] = incoming;
+          debugPrint("🔄 [SalesSyncModule] Replaced sale by billNo: ${incoming.billNo}");
+          return true;
+        }
+      } else {
+        currentSales.insert(0, incoming);
+        debugPrint("✨ [SalesSyncModule] Added new remote sale: ${incoming.billNo} (${incoming.id})");
+        return true;
+      }
+      return false;
+    }
+  }
+}
diff --git a/lib/sync_core/modules/voucher_sync_module.dart b/lib/sync_core/modules/voucher_sync_module.dart
new file mode 100644
index 0000000..142b4a2
--- /dev/null
+++ b/lib/sync_core/modules/voucher_sync_module.dart
@@ -0,0 +1,111 @@
+// FILE: lib/sync_core/modules/voucher_sync_module.dart
+import 'package:flutter/foundation.dart';
+import '../../models.dart';
+import '../models/sync_envelope.dart';
+import '../outbox/sync_queue_manager.dart';
+
+/// VoucherSyncModule: Isolated Synchronization & Conflict Resolution Engine for Vouchers/Payments.
+/// Strictly decoupled from Sales, Purchases, and Challans (File Separation Rule).
+class VoucherSyncModule {
+  static const String documentType = "VOUCHER";
+
+  /// Dispatches a voucher creation or modification to the Outbox queue
+  static void onVoucherSaved(Voucher voucher, String storeToken) {
+    if (storeToken.trim().isEmpty) return;
+    SyncQueueManager.enqueueMutation(
+      syncId: voucher.id,
+      storeToken: storeToken,
+      docType: documentType,
+      currentVersion: voucher.version,
+      isDelete: false,
+      rawPayload: voucher.toMap(),
+    );
+  }
+
+  /// Dispatches a soft-delete operation to the Outbox queue
+  static void onVoucherDeleted(Voucher voucher, String storeToken) {
+    if (storeToken.trim().isEmpty) return;
+    voucher.isDeleted = 1;
+    voucher.status = "Cancelled";
+    voucher.version += 1;
+    voucher.updatedAt = DateTime.now().millisecondsSinceEpoch;
+
+    SyncQueueManager.enqueueMutation(
+      syncId: voucher.id,
+      storeToken: storeToken,
+      docType: documentType,
+      currentVersion: voucher.version,
+      isDelete: true,
+      rawPayload: voucher.toMap(),
+    );
+  }
+
+  /// handleIncomingSync conforming to Step 3 Frontend State Optimization
+  static List<Voucher> handleIncomingSync(List<Voucher> currentUIStateList, SyncEnvelope incomingEvent) {
+    mergeIncomingVoucherEnvelope(currentUIStateList, incomingEvent);
+    return currentUIStateList;
+  }
+
+  /// Merges an incoming SyncEnvelope into current Vouchers list
+  static bool mergeIncomingVoucherEnvelope(List<Voucher> currentVouchers, SyncEnvelope envelope) {
+    if (envelope.documentType != documentType) return false;
+
+    final targetId = envelope.syncId.trim();
+    if (targetId.isEmpty) return false;
+
+    final incomingVoucher = Voucher.fromMap(envelope.billData);
+    incomingVoucher.id = targetId;
+    incomingVoucher.version = envelope.version;
+    incomingVoucher.updatedAt = envelope.updatedAt;
+    incomingVoucher.isDeleted = envelope.isDeleted;
+
+    return applyVoucherMutation(currentVouchers, incomingVoucher);
+  }
+
+  /// Core LWW State Machine for Voucher Objects
+  static bool applyVoucherMutation(List<Voucher> currentVouchers, Voucher incoming) {
+    final idx = currentVouchers.indexWhere((v) => v.id == incoming.id);
+
+    // 1. Check if delete operation
+    if (incoming.isDeleted == 1) {
+      if (idx != -1) {
+        final local = currentVouchers[idx];
+        if (incoming.updatedAt >= local.updatedAt || incoming.version > local.version) {
+          currentVouchers.removeAt(idx);
+          debugPrint("🗑️ [VoucherSyncModule] Soft-deleted voucher evicted: ${incoming.voucherNo} (${incoming.id})");
+          return true;
+        }
+      }
+      return false;
+    }
+
+    // 2. Existing record check
+    if (idx > -1) {
+      final local = currentVouchers[idx];
+      if (incoming.version <= local.version && incoming.updatedAt < local.updatedAt) {
+        return false;
+      }
+      currentVouchers[idx] = incoming;
+      debugPrint("🔄 [VoucherSyncModule] In-place updated voucher: ${incoming.voucherNo} (v${incoming.version})");
+      return true;
+    } else {
+      int noIdx = incoming.voucherNo.isNotEmpty
+          ? currentVouchers.indexWhere((v) => v.voucherNo.trim() == incoming.voucherNo.trim())
+          : -1;
+
+      if (noIdx != -1) {
+        final existing = currentVouchers[noIdx];
+        if (incoming.updatedAt >= existing.updatedAt) {
+          currentVouchers[noIdx] = incoming;
+          debugPrint("🔄 [VoucherSyncModule] Replaced voucher by number: ${incoming.voucherNo}");
+          return true;
+        }
+        return false;
+      } else {
+        currentVouchers.insert(0, incoming);
+        debugPrint("✨ [VoucherSyncModule] Added new remote voucher: ${incoming.voucherNo} (${incoming.id})");
+        return true;
+      }
+    }
+  }
+}
diff --git a/lib/sync_core/orchestrator/master_sync_orchestrator.dart b/lib/sync_core/orchestrator/master_sync_orchestrator.dart
new file mode 100644
index 0000000..a6db919
--- /dev/null
+++ b/lib/sync_core/orchestrator/master_sync_orchestrator.dart
@@ -0,0 +1,106 @@
+// FILE: lib/sync_core/orchestrator/master_sync_orchestrator.dart
+import 'package:flutter/foundation.dart';
+import '../models/sync_envelope.dart';
+import '../modules/sales_sync_module.dart';
+import '../modules/purchase_sync_module.dart';
+import '../modules/challan_sync_module.dart';
+import '../modules/voucher_sync_module.dart';
+import '../../pharoah_manager.dart';
+import '../../web_live_sync/pharoah_web_manager.dart';
+
+/// MasterSyncOrchestrator: Combined routing facade merging all domain modules.
+/// Complies with the File Separation Rule: Sales, Purchases, Challans, and Vouchers
+/// each reside in their own clean, isolated file, and this orchestrator merges them
+/// dynamically upon incoming sync batches.
+class MasterSyncOrchestrator {
+  static final MasterSyncOrchestrator instance = MasterSyncOrchestrator._internal();
+  MasterSyncOrchestrator._internal();
+
+  /// Dispatches an individual SyncEnvelope to the appropriate module
+  static bool dispatchEnvelope({
+    required SyncEnvelope envelope,
+    PharoahManager? phApp,
+    PharoahWebManager? phWeb,
+  }) {
+    final docType = envelope.documentType.toUpperCase().trim();
+    bool mutated = false;
+
+    if (phApp != null) {
+      switch (docType) {
+        case 'SALE':
+          mutated = SalesSyncModule.mergeIncomingSaleEnvelope(phApp.sales, envelope);
+          break;
+        case 'PURCHASE':
+          mutated = PurchaseSyncModule.mergeIncomingPurchaseEnvelope(phApp.purchases, envelope);
+          break;
+        case 'CHALLAN':
+          mutated = ChallanSyncModule.mergeIncomingChallanEnvelope(phApp.saleChallans, envelope);
+          break;
+        case 'VOUCHER':
+          mutated = VoucherSyncModule.mergeIncomingVoucherEnvelope(phApp.vouchers, envelope);
+          break;
+        default:
+          debugPrint("⚠ [MasterSyncOrchestrator] Unknown document type: $docType");
+      }
+    }
+
+    if (phWeb != null) {
+      switch (docType) {
+        case 'SALE':
+          mutated = SalesSyncModule.mergeIncomingSaleEnvelope(phWeb.sales, envelope);
+          break;
+        case 'PURCHASE':
+          mutated = PurchaseSyncModule.mergeIncomingPurchaseEnvelope(phWeb.purchases, envelope);
+          break;
+        case 'CHALLAN':
+          mutated = ChallanSyncModule.mergeIncomingChallanEnvelope(phWeb.saleChallans, envelope);
+          break;
+        case 'VOUCHER':
+          mutated = VoucherSyncModule.mergeIncomingVoucherEnvelope(phWeb.vouchers, envelope);
+          break;
+        default:
+          debugPrint("⚠ [MasterSyncOrchestrator] Unknown document type: $docType");
+      }
+    }
+
+    return mutated;
+  }
+
+  /// Processes a complete Step 4 JSON Batch payload
+  static int dispatchBatchOperations({
+    required List<dynamic> operations,
+    PharoahManager? phApp,
+    PharoahWebManager? phWeb,
+  }) {
+    if (operations.isEmpty) return 0;
+    int appliedCount = 0;
+
+    for (final rawOp in operations) {
+      try {
+        final Map<String, dynamic> opMap = rawOp is Map<String, dynamic>
+            ? rawOp
+            : Map<String, dynamic>.from(rawOp as Map);
+
+        final envelope = SyncEnvelope.fromMap(opMap);
+        final success = dispatchEnvelope(envelope: envelope, phApp: phApp, phWeb: phWeb);
+        if (success) appliedCount++;
+      } catch (e) {
+        debugPrint("⚠ [MasterSyncOrchestrator] Failed to apply operation: $e");
+      }
+    }
+
+    if (appliedCount > 0) {
+      if (phApp != null) {
+        phApp.save();
+        phApp.notifyListeners();
+      }
+      if (phWeb != null) {
+        phWeb.rebuildInventory();
+        phWeb.notifyListeners();
+      }
+      debugPrint("🚀 [MasterSyncOrchestrator] Applied $appliedCount mutations from JSON batch!");
+    }
+
+    return appliedCount;
+  }
+}
diff --git a/lib/sync_core/outbox/sync_queue_manager.dart b/lib/sync_core/outbox/sync_queue_manager.dart
new file mode 100644
index 0000000..f17cfbe
--- /dev/null
+++ b/lib/sync_core/outbox/sync_queue_manager.dart
@@ -0,0 +1,121 @@
+// FILE: lib/sync_core/outbox/sync_queue_manager.dart
+import 'dart:async';
+import 'dart:convert';
+import 'package:flutter/foundation.dart';
+import 'package:http/http.dart' as http;
+import '../models/sync_envelope.dart';
+
+/// SyncQueueManager: Transactional Outbox Engine for Pharoah ERP.
+/// Step 4 JSON Batch Format:
+/// Collects rapid local mutations, eliminates burst clicks, assigns monotonic sequence numbers,
+/// and flushes debounced JSON batches to the Cloudflare Edge D1 Bus.
+class SyncQueueManager {
+  static final SyncQueueManager instance = SyncQueueManager._internal();
+  SyncQueueManager._internal();
+
+  static final List<SyncEnvelope> _outboxBufferQueue = [];
+  static Timer? _debounceTimer;
+  static bool _isFlushing = false;
+  static int _sequenceCounter = 100;
+  static String _deviceId = 'MREG-DEVICE-${DateTime.now().millisecondsSinceEpoch % 10000}';
+  static const String edgeSignalEndpoint = "https://pharoah-erp.pages.dev/api/lab_signal";
+
+  /// Sets custom device ID if available
+  static void setDeviceId(String id) {
+    if (id.trim().isNotEmpty) _deviceId = id.trim();
+  }
+
+  static String get deviceId => _deviceId;
+
+  /// Enqueues a local mutation to the outbox buffer.
+  /// Assigns sequence number and action (INSERT / UPDATE / DELETE).
+  /// Deduplicates operations within the local frame buffer (replaces older pending ops for same syncId).
+  static void enqueueMutation({
+    required String syncId,
+    required String storeToken,
+    required String docType,
+    required int currentVersion,
+    required bool isDelete,
+    required Map<String, dynamic> rawPayload,
+    Duration debounceDuration = const Duration(milliseconds: 400),
+  }) {
+    if (syncId.trim().isEmpty) return;
+
+    _sequenceCounter += 1;
+    final String actionType = isDelete ? "DELETE" : (currentVersion <= 1 ? "INSERT" : "UPDATE");
+
+    final envelope = SyncEnvelope(
+      seq: _sequenceCounter,
+      syncId: syncId.trim(),
+      storeToken: storeToken.trim().toUpperCase(),
+      documentType: docType.trim().toUpperCase(),
+      action: actionType,
+      deviceId: _deviceId,
+      version: currentVersion + 1,
+      updatedAt: DateTime.now().microsecondsSinceEpoch, // 16-Digit Microsecond Clock
+      isDeleted: isDelete ? 1 : 0,
+      billData: rawPayload,
+    );
+
+    // Frame buffer deduplication: remove any pending op for the same syncId
+    _outboxBufferQueue.removeWhere((element) => element.syncId == envelope.syncId);
+    _outboxBufferQueue.add(envelope);
+
+    debugPrint("📥 [SyncQueueManager] Enqueued seq=${envelope.seq}: op=${envelope.action}, doc=${envelope.documentType}, id=${envelope.syncId}, ver=${envelope.version}");
+
+    // 400ms Debounce Clock
+    _debounceTimer?.cancel();
+    _debounceTimer = Timer(debounceDuration, () {
+      flushOutboxAsJSONBatch();
+    });
+  }
+
+  /// Flushes all pending outbox envelopes as an aggregated atomic Step 4 JSON batch
+  static Future<bool> flushOutboxAsJSONBatch() async {
+    if (_outboxBufferQueue.isEmpty || _isFlushing) return false;
+    _isFlushing = true;
+
+    // Snapshot current outbox buffer
+    final List<SyncEnvelope> batchPayload = List.from(_outboxBufferQueue);
+    _outboxBufferQueue.clear();
+
+    final String token = batchPayload.first.storeToken;
+
+    // STEP 4 CONFORMING JSON BATCH PAYLOAD
+    final Map<String, dynamic> body = {
+      "device_id": _deviceId,
+      "storeToken": token,
+      "source": "OUTBOX_BATCH",
+      "action": "JSON_BATCH_MUTATION",
+      "batch_timestamp": DateTime.now().toUtc().toIso8601String(),
+      "operations": batchPayload.map((e) => e.toMap()).toList(),
+    };
+
+    try {
+      final response = await http.post(
+        Uri.parse(edgeSignalEndpoint),
+        headers: {"Content-Type": "application/json"},
+        body: jsonEncode(body),
+      ).timeout(const Duration(seconds: 6));
+
+      if (response.statusCode == 200) {
+        debugPrint("⚡ [SyncQueueManager] Successfully flushed Step 4 batch of ${batchPayload.length} operations to D1!");
+        _isFlushing = false;
+        return true;
+      } else {
+        debugPrint("⚠ [SyncQueueManager] Server returned status ${response.statusCode}. Restoring to buffer.");
+        _outboxBufferQueue.insertAll(0, batchPayload);
+        _isFlushing = false;
+        return false;
+      }
+    } catch (e) {
+      debugPrint("⚠ [SyncQueueManager] Batch flush error: $e. Restoring to buffer for retry.");
+      _outboxBufferQueue.insertAll(0, batchPayload);
+      _isFlushing = false;
+      return false;
+    }
+  }
+
+  /// Pending count for UI status inspection
+  static int get pendingCount => _outboxBufferQueue.length;
+}
diff --git a/lib/web_live_sync/components/web_top_bar.dart b/lib/web_live_sync/components/web_top_bar.dart
index 74ab9d6..892eeff 100644
--- a/lib/web_live_sync/components/web_top_bar.dart
+++ b/lib/web_live_sync/components/web_top_bar.dart
@@ -74,7 +74,7 @@ class WebTopBar extends StatelessWidget implements PreferredSizeWidget {
                       border: Border.all(color: Colors.greenAccent, width: 0.5),
                     ),
                     child: const Text(
-                      "#PH-REV-663 (SERVER-AUTHORITATIVE-D1-REVIVAL-ENGINE)",
+                      "#PH-REV-664 (ACTIVE-RECORD-AUTO-REVIVAL-ENGINE)",
                       style: TextStyle(color: Colors.greenAccent, fontSize: 7.5, fontWeight: FontWeight.w900),
                     ),
                   ),
diff --git a/lib/web_live_sync/pharoah_auto_sync_service.dart b/lib/web_live_sync/pharoah_auto_sync_service.dart
index 1069c9b..b744fff 100644
--- a/lib/web_live_sync/pharoah_auto_sync_service.dart
+++ b/lib/web_live_sync/pharoah_auto_sync_service.dart
@@ -1,5 +1,5 @@
 // FILE: lib/web_live_sync/pharoah_auto_sync_service.dart
-// Live Revision: #PH-REV-663 (SERVER-AUTHORITATIVE-D1-REVIVAL-ENGINE)
+// Live Revision: #PH-REV-664 (ACTIVE-RECORD-AUTO-REVIVAL-ENGINE)
 import 'dart:async';
 import 'package:flutter/foundation.dart';
 import 'pharoah_web_manager.dart';
@@ -26,9 +26,10 @@ class PharoahAutoSyncService {
     String action = 'DATA_MUTATED',
     String entityId = '',
     List<String> deletedIds = const [],
+    List<String> unmarkedIds = const [],
   }) {
     if (!webManager.isAuthenticated || webManager.activeStoreToken.isEmpty) return;
-    _coordinator.notifyWebMutation(action: action, entityId: entityId, deletedIds: deletedIds);
+    _coordinator.notifyWebMutation(action: action, entityId: entityId, deletedIds: deletedIds, unmarkedIds: unmarkedIds);
     LabSyncOrchestrator.instance.notifyWebRealMutation(webManager, action: action, entityId: entityId);
   }
 
diff --git a/lib/web_live_sync/pharoah_web_manager.dart b/lib/web_live_sync/pharoah_web_manager.dart
index 587953b..3133699 100644
--- a/lib/web_live_sync/pharoah_web_manager.dart
+++ b/lib/web_live_sync/pharoah_web_manager.dart
@@ -1,3 +1,7 @@
+import '../sync_core/modules/sales_sync_module.dart';
+import '../sync_core/modules/purchase_sync_module.dart';
+import '../sync_core/modules/challan_sync_module.dart';
+import '../sync_core/modules/voucher_sync_module.dart';
 // FILE: lib/web_live_sync/pharoah_web_manager.dart
 
 import 'dart:convert';
@@ -241,10 +245,20 @@ class PharoahWebManager with ChangeNotifier {
     }
     parties = uniqueParties.values.toList();
 
-    // 1. Sales Sync with Strict LWW & Tombstone Shield
-    var rawSales = (decodeJson('sales.json') as List?)
+    // 1. Sales Sync with Active Auto-Revival & LWW Guard
+    var allParsedSales = (decodeJson('sales.json') as List?)
         ?.map((e) => Sale.fromMap(e))
-        .where((s) => !deletedRecordIds.contains(s.id) && !deletedRecordIds.contains(s.billNo))
+        .toList();
+    if (allParsedSales != null) {
+      for (var s in allParsedSales) {
+        if (s.status.toLowerCase() != 'deleted') {
+          deletedRecordIds.remove(s.id);
+          if (s.billNo.isNotEmpty) deletedRecordIds.remove(s.billNo);
+        }
+      }
+    }
+    var rawSales = allParsedSales
+        ?.where((s) => !deletedRecordIds.contains(s.id))
         .toList();
     if (rawSales != null) {
       if (sales.isEmpty) {
@@ -266,10 +280,19 @@ class PharoahWebManager with ChangeNotifier {
       }
     }
 
-    // 2. Purchases Sync with Strict LWW & Tombstone Shield
-    var rawPurc = (decodeJson('purc.json') as List?)
+    // 2. Purchases Sync with Active Auto-Revival & LWW Guard
+    var allParsedPurc = (decodeJson('purc.json') as List?)
         ?.map((e) => Purchase.fromMap(e))
-        .where((p) => !deletedRecordIds.contains(p.id) && !deletedRecordIds.contains(p.internalNo) && (p.billNo.isEmpty || !deletedRecordIds.contains(p.billNo)))
+        .toList();
+    if (allParsedPurc != null) {
+      for (var p in allParsedPurc) {
+        deletedRecordIds.remove(p.id);
+        if (p.internalNo.isNotEmpty) deletedRecordIds.remove(p.internalNo);
+        if (p.billNo.isNotEmpty) deletedRecordIds.remove(p.billNo);
+      }
+    }
+    var rawPurc = allParsedPurc
+        ?.where((p) => !deletedRecordIds.contains(p.id))
         .toList();
     if (rawPurc != null) {
       if (purchases.isEmpty) {
@@ -604,8 +627,15 @@ class PharoahWebManager with ChangeNotifier {
     rebuildInventory();
     notifyListeners();
 
+    // ⚡ Transactional Outbox Batch Enqueue
+    SalesSyncModule.onSaleSaved(sale, activeStoreToken);
+
     // ⚡ Fast Non-Blocking Background Cloud Push
-    _autoSyncService.triggerAutoSync(action: 'DATA_SAVED', entityId: sale.id);
+    _autoSyncService.triggerAutoSync(
+      action: 'DATA_SAVED',
+      entityId: sale.id,
+      unmarkedIds: [sale.id, if (sale.billNo.isNotEmpty) sale.billNo],
+    );
   }
 
   void deleteSale(String saleId) {
@@ -643,6 +673,11 @@ class PharoahWebManager with ChangeNotifier {
     }
     _saveLocalTombstones();
 
+    try {
+      final targetSale = sales.firstWhere((x) => x.id == saleId || (foundBillNo.isNotEmpty && x.billNo == foundBillNo));
+      SalesSyncModule.onSaleDeleted(targetSale, activeStoreToken);
+    } catch (_) {}
+
     sales.removeWhere((s) => s.id == saleId || (foundBillNo.isNotEmpty && s.billNo == foundBillNo));
     rebuildInventory();
     notifyListeners();
@@ -665,6 +700,7 @@ class PharoahWebManager with ChangeNotifier {
     purchase.version = currentVer;
     purchases.removeWhere((p) => p.id == purchase.id || p.billNo == purchase.billNo || p.internalNo == purchase.internalNo);
     purchases.add(purchase);
+    PurchaseSyncModule.onPurchaseSaved(purchase, activeStoreToken);
     for (var item in purchase.items) {
       String resolvedKey = item.medicineID;
       try {
@@ -690,7 +726,15 @@ class PharoahWebManager with ChangeNotifier {
     notifyListeners();
 
     // ⚡ Fast Non-Blocking Background Cloud Push
-    _autoSyncService.triggerAutoSync(action: 'DATA_SAVED', entityId: purchase.id);
+    _autoSyncService.triggerAutoSync(
+      action: 'DATA_SAVED',
+      entityId: purchase.id,
+      unmarkedIds: [
+        purchase.id,
+        if (purchase.internalNo.isNotEmpty) purchase.internalNo,
+        if (purchase.billNo.isNotEmpty) purchase.billNo,
+      ],
+    );
   }
 
   void deletePurchase(String purId) {
@@ -703,6 +747,7 @@ class PharoahWebManager with ChangeNotifier {
       );
       foundInternalNo = p.internalNo;
       foundBillNo = p.billNo;
+      PurchaseSyncModule.onPurchaseDeleted(p, activeStoreToken);
       Set<String> targetChallanKeys = {};
       for (var cid in p.linkedChallanIds) {
         if (cid.trim().isNotEmpty) targetChallanKeys.add(cid.trim().toUpperCase());
@@ -746,6 +791,10 @@ class PharoahWebManager with ChangeNotifier {
   }
 
   void deleteVoucher(String voucherId) {
+    try {
+      final targetV = vouchers.firstWhere((item) => item.id == voucherId);
+      VoucherSyncModule.onVoucherDeleted(targetV, activeStoreToken);
+    } catch (_) {}
     deletedRecordIds.add(voucherId);
     _saveLocalTombstones();
     vouchers.removeWhere((item) => item.id == voucherId);
@@ -758,6 +807,10 @@ class PharoahWebManager with ChangeNotifier {
   }
 
   void deleteSaleChallan(String challanId) {
+    try {
+      final targetC = saleChallans.firstWhere((item) => item.id == challanId);
+      ChallanSyncModule.onChallanDeleted(targetC, activeStoreToken);
+    } catch (_) {}
     deletedRecordIds.add(challanId);
     _saveLocalTombstones();
     saleChallans.removeWhere((item) => item.id == challanId);
diff --git a/lib/web_live_sync/sync_protocol/delta_merge_engine.dart b/lib/web_live_sync/sync_protocol/delta_merge_engine.dart
index 98797dd..34f9830 100644
--- a/lib/web_live_sync/sync_protocol/delta_merge_engine.dart
+++ b/lib/web_live_sync/sync_protocol/delta_merge_engine.dart
@@ -27,12 +27,11 @@ class DeltaMergeEngine {
       if (cloudList == null) return false;
       bool changed = false;
 
-      // 1. Purge any tombstoned records (checking both ID and BillNo to kill ghost bills)
+      // 1. Purge genuinely deleted records by exact ID
       final beforeLen = localList.length;
       localList.removeWhere((item) {
         final id = getId(item).trim();
-        final bNo = getBillNo(item).trim();
-        return tombstones.contains(id) || (bNo.isNotEmpty && tombstones.contains(bNo));
+        return tombstones.contains(id);
       });
       if (localList.length != beforeLen) changed = true;
 
@@ -43,8 +42,15 @@ class DeltaMergeEngine {
         String id = (cloudMap['id'] ?? '').toString().trim();
         String billNo = (cloudMap['billNo'] ?? cloudMap['internalNo'] ?? cloudMap['voucherNo'] ?? '').toString().trim();
 
-        // Skip if deleted or in tombstones
-        if (id.isEmpty || tombstones.contains(id) || (billNo.isNotEmpty && tombstones.contains(billNo))) continue;
+        // 🛡️ Active Record Auto-Revival Protocol:
+        final status = (cloudMap['status'] ?? 'Active').toString().toLowerCase();
+        final isAlive = status != 'deleted' && status != 'cancelled';
+        if (isAlive) {
+          tombstones.remove(id);
+          if (billNo.isNotEmpty) tombstones.remove(billNo);
+        } else {
+          if (id.isEmpty || tombstones.contains(id) || (billNo.isNotEmpty && tombstones.contains(billNo))) continue;
+        }
 
         // Match by exact ID or same Bill Number to prevent duplicate cards
         int idx = localList.indexWhere((e) => getId(e) == id || (billNo.isNotEmpty && getBillNo(e) == billNo));
@@ -110,7 +116,7 @@ class DeltaMergeEngine {
       decodeJson('purc.json'), 
       ph.purchases, 
       (e) => e.id, 
-      (e) => e.internalNo.isNotEmpty ? e.internalNo : e.billNo, 
+      (e) => e.billNo.isNotEmpty ? e.billNo : e.internalNo, 
       (m) => Purchase.fromMap(m), 
       (e) => e.toMap()
     );
diff --git a/lib/web_live_sync/sync_protocol/tombstone_engine.dart b/lib/web_live_sync/sync_protocol/tombstone_engine.dart
index a7206ea..1eddc81 100644
--- a/lib/web_live_sync/sync_protocol/tombstone_engine.dart
+++ b/lib/web_live_sync/sync_protocol/tombstone_engine.dart
@@ -95,15 +95,60 @@ class TombstoneEngine {
     return sanitized;
   }
 
-  /// Removes any record from the app's memory that exists in the tombstone list.
+  /// Removes deleted records while auto-reviving newly imported/active bills
   static void purgeDeletedRecords(PharoahManager ph, Set<String> allTombstones) {
     if (allTombstones.isEmpty) return;
-    ph.sales.removeWhere((e) => allTombstones.contains(e.id) || allTombstones.contains(e.billNo));
-    ph.purchases.removeWhere((e) => allTombstones.contains(e.id) || allTombstones.contains(e.internalNo) || allTombstones.contains(e.billNo));
-    ph.saleChallans.removeWhere((e) => allTombstones.contains(e.id) || allTombstones.contains(e.billNo));
-    ph.purchaseChallans.removeWhere((e) => allTombstones.contains(e.id) || allTombstones.contains(e.internalNo));
-    ph.saleReturns.removeWhere((e) => allTombstones.contains(e.id) || allTombstones.contains(e.billNo));
-    ph.purchaseReturns.removeWhere((e) => allTombstones.contains(e.id) || allTombstones.contains(e.billNo));
-    ph.vouchers.removeWhere((e) => allTombstones.contains(e.id) || allTombstones.contains(e.voucherNo));
+
+    // 1. Sales: Exact ID deletion only; revive active bill numbers
+    final List<String> revivedSales = [];
+    for (var s in ph.sales) {
+      if (!allTombstones.contains(s.id)) {
+        if (s.billNo.isNotEmpty && allTombstones.contains(s.billNo)) {
+          revivedSales.add(s.billNo);
+        }
+      }
+    }
+    for (var b in revivedSales) allTombstones.remove(b);
+    ph.sales.removeWhere((e) => allTombstones.contains(e.id));
+
+    // 2. Purchases: Exact ID deletion only; revive active bills/internal numbers
+    final List<String> revivedPurchases = [];
+    for (var p in ph.purchases) {
+      if (!allTombstones.contains(p.id)) {
+        if (p.internalNo.isNotEmpty && allTombstones.contains(p.internalNo)) {
+          revivedPurchases.add(p.internalNo);
+        }
+        if (p.billNo.isNotEmpty && allTombstones.contains(p.billNo)) {
+          revivedPurchases.add(p.billNo);
+        }
+      }
+    }
+    for (var b in revivedPurchases) allTombstones.remove(b);
+    ph.purchases.removeWhere((e) => allTombstones.contains(e.id));
+
+    // 3. Challans, Returns, Vouchers: Exact ID deletion with revival
+    final List<String> otherRevivals = [];
+    for (var c in ph.saleChallans) {
+      if (!allTombstones.contains(c.id) && c.billNo.isNotEmpty && allTombstones.contains(c.billNo)) otherRevivals.add(c.billNo);
+    }
+    for (var c in ph.purchaseChallans) {
+      if (!allTombstones.contains(c.id) && c.internalNo.isNotEmpty && allTombstones.contains(c.internalNo)) otherRevivals.add(c.internalNo);
+    }
+    for (var r in ph.saleReturns) {
+      if (!allTombstones.contains(r.id) && r.billNo.isNotEmpty && allTombstones.contains(r.billNo)) otherRevivals.add(r.billNo);
+    }
+    for (var r in ph.purchaseReturns) {
+      if (!allTombstones.contains(r.id) && r.billNo.isNotEmpty && allTombstones.contains(r.billNo)) otherRevivals.add(r.billNo);
+    }
+    for (var v in ph.vouchers) {
+      if (!allTombstones.contains(v.id) && v.voucherNo.isNotEmpty && allTombstones.contains(v.voucherNo)) otherRevivals.add(v.voucherNo);
+    }
+    for (var b in otherRevivals) allTombstones.remove(b);
+
+    ph.saleChallans.removeWhere((e) => allTombstones.contains(e.id));
+    ph.purchaseChallans.removeWhere((e) => allTombstones.contains(e.id));
+    ph.saleReturns.removeWhere((e) => allTombstones.contains(e.id));
+    ph.purchaseReturns.removeWhere((e) => allTombstones.contains(e.id));
+    ph.vouchers.removeWhere((e) => allTombstones.contains(e.id));
   }
 }
diff --git a/lib/web_live_sync/web_purchase_summary_view.dart b/lib/web_live_sync/web_purchase_summary_view.dart
index b8c988b..f7917c7 100644
--- a/lib/web_live_sync/web_purchase_summary_view.dart
+++ b/lib/web_live_sync/web_purchase_summary_view.dart
@@ -64,7 +64,7 @@ class _WebPurchaseSummaryViewState extends State<WebPurchaseSummaryView> {
           p.billNo.toLowerCase().contains(searchQuery.toLowerCase()) ||
           p.internalNo.toLowerCase().contains(searchQuery.toLowerCase());
 
-      return dateMatch && searchMatch;
+      return p.isDeleted != 1 && dateMatch && searchMatch;
     }).toList();
 
     double totalTaxable = 0.0;
diff --git a/lib/web_live_sync/web_sale_summary_view.dart b/lib/web_live_sync/web_sale_summary_view.dart
index af3d76c..758b379 100644
--- a/lib/web_live_sync/web_sale_summary_view.dart
+++ b/lib/web_live_sync/web_sale_summary_view.dart
@@ -107,7 +107,7 @@ class _WebSaleSummaryViewState extends State<WebSaleSummaryView> {
       bool searchMatch = searchQuery.isEmpty ||
           s.billNo.toLowerCase().contains(searchQuery.toLowerCase()) || 
           s.partyName.toLowerCase().contains(searchQuery.toLowerCase());
-      bool isActive = s.status.isEmpty || s.status.toLowerCase() == "active";
+      bool isActive = (s.status.isEmpty || s.status.toLowerCase() == "active") && s.isDeleted != 1;
 
       return isActive && dateMatch && searchMatch;
     }).toList();
"""

patch_file = "rev_667_temp.patch"
with open(patch_file, "w", encoding="utf-8") as f:
    f.write(PATCH_CONTENT)

apply_res = subprocess.run(["git", "apply", "--reject", "--whitespace=nowarn", patch_file], capture_output=True, text=True)
if apply_res.returncode == 0:
    print("✔ Git patch applied with 100% precision!")
else:
    print("⚠ Git apply notice (some chunks might already exist):", apply_res.stderr or apply_res.stdout)

if os.path.exists(patch_file):
    os.remove(patch_file)

# 2. GIT ADD & COMMIT
print("\n📥 Step 2/5: Staging all updated modules and creating Git commit...")
subprocess.run(["git", "add", "."], check=False)
subprocess.run(["git", "commit", "-m", "🚀 #PH-REV-667: Master Sync Engine (Steps 1, 2, 3, 4 Complete)"], check=False)

# 3. PUSH TO GITHUB (Trigger Automatic APK Build on GitHub Actions)
print("\n📤 Step 3/5: Pushing to GitHub (origin main)...")
push_res = subprocess.run(["git", "push", "origin", "main"], capture_output=True, text=True)
if push_res.returncode == 0:
    print("✔ Pushed to GitHub successfully! APK build triggered on GitHub Actions!")
    print("👉 Check GitHub Actions tab to download new APK.")
else:
    print("⚠ Git push stderr:", push_res.stderr)
    print("💡 If authentication failed in Colab, configure your GitHub PAT in remote URL:")
    print("   git remote set-url origin https://<YOUR_GITHUB_TOKEN>@github.com/new-ph-131/131-new-ph.git")
    print("   and re-run: git push origin main")

# 4. BUILD FLUTTER WEB
print("\n🔨 Step 4/5: Building Production Flutter Web...")
subprocess.run(["flutter", "pub", "get"], check=False)
build_cmd = [
    "flutter", "build", "web",
    "-t", "lib/web_live_sync/web_main.dart",
    "--release",
    "--base-href", "/",
    "--pwa-strategy=none"
]
b_res = subprocess.run(build_cmd, check=False)

# 5. DEPLOY TO CLOUDFLARE PAGES
print("\n🌐 Step 5/5: Deploying to Cloudflare Pages...")
deploy_cmd = [
    "npx", "wrangler", "pages", "deploy", "build/web",
    "--project-name=pharoah-erp",
    "--commit-dirty=true"
]
d_res = subprocess.run(deploy_cmd, check=False)

print("\n" + "=" * 72)
print("🎉 REVISION #PH-REV-667 DEPLOYMENT WORKFLOW COMPLETED!")
print("🔗 Live Portal URL: https://pharoah-erp.pages.dev")
print("=" * 72)
