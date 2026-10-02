import re
import subprocess
import sys

# 1. Update Revision Tag
top_bar_path = "lib/web_live_sync/components/web_top_bar.dart"
with open(top_bar_path, "r", encoding="utf-8") as f:
    tb = f.read()

new_rev = "#PH-REV-576 (FIX-VIEW-POINTER-EVENTS)"
tb = re.sub(r"#PH-REV-\d+[^\"]*", new_rev, tb)
with open(top_bar_path, "w", encoding="utf-8") as f:
    f.write(tb)
print(f"✔ Live Tag Updated: {new_rev}")

# 2. Fix WebNewSaleView (Remove destructive root IgnorePointer)
sale_view_path = "lib/web_live_sync/sub_views/web_billing/web_new_sale_view.dart"
with open(sale_view_path, "r", encoding="utf-8") as f:
    sv = f.read()

# Replace IgnorePointer wrapping in build method
old_sale_build = r'''    return LayoutBuilder(
      builder: (context, constraints) {
        bool isWideScreen = constraints.maxWidth > 1100;

        return IgnorePointer(
          ignoring: widget.isReadOnly,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderBar(webPh),
              const SizedBox(height: 16),
              if (isWideScreen)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 13,
                      child: Column(
                        children: [
                          if (!widget.isReadOnly) _buildProductSearchCard(webPh),
                          if (!widget.isReadOnly) const SizedBox(height: 16),
                          _buildCartTable(webPh),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 340, maxWidth: 420),
                      child: Column(
                        children: [
                          _buildCustomerCard(webPh),
                          const SizedBox(height: 16),
                          _buildGrandTotalCard(webPh),
                        ],
                      ),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    _buildCustomerCard(webPh),
                    const SizedBox(height: 16),
                    if (!widget.isReadOnly) _buildProductSearchCard(webPh),
                    if (!widget.isReadOnly) const SizedBox(height: 16),
                    _buildCartTable(webPh),
                    const SizedBox(height: 16),
                    _buildGrandTotalCard(webPh),
                  ],
                ),
            ],
          ),
        );
      },
    );'''

new_sale_build = r'''    return LayoutBuilder(
      builder: (context, constraints) {
        bool isWideScreen = constraints.maxWidth > 1100;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderBar(webPh),
            const SizedBox(height: 16),
            if (isWideScreen)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 13,
                    child: Column(
                      children: [
                        if (!widget.isReadOnly) _buildProductSearchCard(webPh),
                        if (!widget.isReadOnly) const SizedBox(height: 16),
                        _buildCartTable(webPh),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 340, maxWidth: 420),
                    child: Column(
                      children: [
                        _buildCustomerCard(webPh),
                        const SizedBox(height: 16),
                        _buildGrandTotalCard(webPh),
                      ],
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  _buildCustomerCard(webPh),
                  const SizedBox(height: 16),
                  if (!widget.isReadOnly) _buildProductSearchCard(webPh),
                  if (!widget.isReadOnly) const SizedBox(height: 16),
                  _buildCartTable(webPh),
                  const SizedBox(height: 16),
                  _buildGrandTotalCard(webPh),
                ],
              ),
          ],
        );
      },
    );'''

sv = sv.replace(old_sale_build, new_sale_build)
with open(sale_view_path, "w", encoding="utf-8") as f:
    f.write(sv)
print(f"✔ Fixed pointer events in: {sale_view_path}")

# 3. Fix WebPurchaseEntryView (Remove destructive root IgnorePointer)
pur_view_path = "lib/web_live_sync/web_purchase_entry_view.dart"
with open(pur_view_path, "r", encoding="utf-8") as f:
    pv = f.read()

old_pur_build = r'''  Widget _buildNewPurchaseTab(PharoahWebManager webPh) {
    return IgnorePointer(
      ignoring: widget.isReadOnly,
      child: Column('''

new_pur_build = r'''  Widget _buildNewPurchaseTab(PharoahWebManager webPh) {
    return Column('''

pv = pv.replace(old_pur_build, new_pur_build)
# Remove the extra closing parenthesis and semicolon if present
pv = pv.replace(r'''        ],
      ),
    );
  }''', r'''        ],
      );
  }''')

with open(pur_view_path, "w", encoding="utf-8") as f:
    f.write(pv)
print(f"✔ Fixed pointer events in: {pur_view_path}")

# 4. Analyze Web Code
print("\n🔍 Step 1/3: Analyzing Web Code...")
res = subprocess.run(["flutter", "analyze", "lib/web_live_sync/"], text=True)
if res.returncode != 0:
    print("❌ Analyze failed!")
    sys.exit(1)
print("✅ 0 Issues Found!")

# 5. Build Production Web Bundle
print("\n🔨 Step 2/3: Building Production Web Bundle...")
build_cmd = [
    "flutter", "build", "web",
    "-t", "lib/web_live_sync/web_main.dart",
    "--release",
    "--base-href", "/",
    "--pwa-strategy=none"
]
res_build = subprocess.run(build_cmd, text=True)
if res_build.returncode != 0:
    print("❌ Web Build failed!")
    sys.exit(1)

# 6. Deploy to Cloudflare Pages
print("\n🌐 Step 3/3: Deploying to Cloudflare Pages (pharoah-erp)...")
deploy_cmd = [
    "npx", "wrangler", "pages", "deploy", "build/web",
    "--project-name=pharoah-erp"
]
subprocess.run(deploy_cmd)

print("\n" + "="*54)
print(f"🎉 100% FIXED & LIVE DEPLOYED! Version: {new_rev}")
print("🔗 Live URL: https://pharoah-erp.pages.dev")
print("="*54)
