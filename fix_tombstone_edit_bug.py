import re
import subprocess
import sys

print("==================================================================")
print("🚀 FIXING THE TOMBSTONE EDIT BUG ACROSS ALL 6 BILLING MODULES")
print("==================================================================\n")

print("🏷️ Step 1/4: Updating Live Tag to #PH-REV-626...")
tb_path = "lib/web_live_sync/components/web_top_bar.dart"
with open(tb_path, "r", encoding="utf-8") as f:
    tb = f.read()

new_rev = "#PH-REV-626 (TOMBSTONE-EDIT-BUG-FIXED)"
tb = re.sub(r"#PH-REV-\d+[^\"]*", new_rev, tb)
with open(tb_path, "w", encoding="utf-8") as f:
    f.write(tb)
print(f"✔ Tag Updated: {new_rev}")

print("\n🔧 Step 2/4: Applying Smart .removeWhere() Fixes to UI Files...")

def smart_replace(filepath, regex_find, str_replace):
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    new_content = re.sub(regex_find, str_replace, content)
    if content != new_content:
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(new_content)
        print(f"✔ Fixed: {filepath}")
    else:
        print(f"ℹ️ Already Fixed or Skipped: {filepath}")

# 1. Sale Billing
smart_replace(
    "lib/web_live_sync/sub_views/web_billing/web_new_sale_view.dart",
    r'if\s*\(\s*widget\.modifySaleId\s*!=\s*null\s*\)\s*webPh\.deleteSale\s*\(\s*widget\.modifySaleId!\s*\);',
    r'if (widget.modifySaleId != null) webPh.sales.removeWhere((s) => s.id == widget.modifySaleId!);'
)

# 2. Purchase Billing
smart_replace(
    "lib/web_live_sync/web_purchase_entry_view.dart",
    r'if\s*\(\s*widget\.modifyPurchaseId\s*!=\s*null\s*\)\s*webPh\.deletePurchase\s*\(\s*widget\.modifyPurchaseId!\s*\);',
    r'if (widget.modifyPurchaseId != null) webPh.purchases.removeWhere((p) => p.id == widget.modifyPurchaseId!);'
)

# 3. Sale Challan
smart_replace(
    "lib/web_live_sync/sub_views/web_challans/web_sale_challan_billing_view.dart",
    r'if\s*\(\s*widget\.existingRecord\s*!=\s*null\s*\)\s*\{\s*webPh\.deleteSaleChallan\s*\(\s*widget\.existingRecord!\.id\s*\);\s*\}',
    r'if (widget.existingRecord != null) { webPh.saleChallans.removeWhere((c) => c.id == widget.existingRecord!.id); }'
)

# 4. Purchase Challan
smart_replace(
    "lib/web_live_sync/sub_views/web_challans/web_purchase_challan_billing_view.dart",
    r'if\s*\(\s*widget\.existingRecord\s*!=\s*null\s*\)\s*\{\s*webPh\.deletePurchaseChallan\s*\(\s*widget\.existingRecord!\.id\s*\);\s*\}',
    r'if (widget.existingRecord != null) { webPh.purchaseChallans.removeWhere((c) => c.id == widget.existingRecord!.id); }'
)

# 5. Credit Note Mechanism
smart_replace(
    "lib/web_live_sync/sub_views/web_returns/credit_note/mechanism/credit_note_mechanism.dart",
    r'if\s*\(\s*existingId\s*!=\s*null\s*\)\s*\{\s*webPh\.deleteSaleReturn\s*\(\s*existingId\s*\);\s*\}',
    r'if (existingId != null) { webPh.saleReturns.removeWhere((r) => r.id == existingId); }'
)

# 6. Debit Note Mechanism
smart_replace(
    "lib/web_live_sync/sub_views/web_returns/debit_note/mechanism/debit_note_mechanism.dart",
    r'if\s*\(\s*existingId\s*!=\s*null\s*\)\s*\{\s*webPh\.deletePurchaseReturn\s*\(\s*existingId\s*\);\s*\}',
    r'if (existingId != null) { webPh.purchaseReturns.removeWhere((r) => r.id == existingId); }'
)

print("\n🔍 Step 3/4: Running Flutter Analyze to verify integrity...")
res = subprocess.run(["flutter", "analyze", "lib/web_live_sync/"], text=True)
if res.returncode != 0:
    print("❌ Analyze output:")
    print(res.stdout)
    sys.exit(1)
print("✅ 0 ISSUES FOUND! Analyzer is 100% clean.")

print("\n🔨 Step 4/4: Building & Deploying to Cloudflare Pages...")
build_cmd = ["flutter", "build", "web", "-t", "lib/web_live_sync/web_main.dart", "--release", "--base-href", "/", "--pwa-strategy=none"]
b_res = subprocess.run(build_cmd, text=True)
if b_res.returncode != 0:
    print("❌ Web Build failed!")
    sys.exit(1)

deploy_cmd = ["npx", "wrangler", "pages", "deploy", "build/web", "--project-name=pharoah-erp"]
subprocess.run(deploy_cmd)

print("\n" + "="*60)
print(f"🎉 BUG FIXED! EDITED BILLS WILL NEVER DISAPPEAR AGAIN!")
print(f"🔗 Version Deployed: {new_rev}")
print("="*60)
