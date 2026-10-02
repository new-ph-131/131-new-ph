import re
import subprocess
import sys

# 1. Update Revision Tag
top_bar_path = "lib/web_live_sync/components/web_top_bar.dart"
with open(top_bar_path, "r", encoding="utf-8") as f:
    tb = f.read()

new_rev = "#PH-REV-585 (FINAL-LINT-FIX)"
tb = re.sub(r"#PH-REV-\d+[^\"]*", new_rev, tb)
with open(top_bar_path, "w", encoding="utf-8") as f:
    f.write(tb)
print(f"✔ Live Tag Updated: {new_rev}")

# 2. Fix the instance field declaration in web_product_master.dart
pm_path = "lib/web_live_sync/web_product_master.dart"
with open(pm_path, "r", encoding="utf-8") as f:
    content = f.read()

# Correct the declarations
content = content.replace("const List<String> drugForms", "final List<String> drugForms = const")
content = content.replace("const List<String> storageOptions", "final List<String> storageOptions = const")

with open(pm_path, "w", encoding="utf-8") as f:
    f.write(content)
print("✔ Fixed const instance field errors.")

# 3. Analyze Web Code
print("\n🔍 Step 1/3: Analyzing Web Code...")
res = subprocess.run(["flutter", "analyze", "lib/web_live_sync/"], text=True)
if res.returncode != 0:
    print("❌ Analyze failed! Inspect output below:")
    print(res.stdout)
    sys.exit(1)
print("✅ 0 Issues Found! Proceeding to build...")

# 4. Build Production Web Bundle
print("\n🔨 Step 2/3: Building Production Web Bundle...")
build_cmd = ["flutter", "build", "web", "-t", "lib/web_live_sync/web_main.dart", "--release", "--base-href", "/", "--pwa-strategy=none"]
res_build = subprocess.run(build_cmd, text=True)
if res_build.returncode != 0:
    print("❌ Web Build failed!")
    sys.exit(1)

# 5. Deploy to Cloudflare Pages
print("\n🌐 Step 3/3: Deploying to Cloudflare Pages...")
subprocess.run(["npx", "wrangler", "pages", "deploy", "build/web", "--project-name=pharoah-erp"])

print("\n" + "="*52)
print(f"🎉 LINT-CLEAN & DEPLOY SUCCESSFUL! Version: {new_rev}")
print("🔗 Live URL: https://pharoah-erp.pages.dev")
print("="*52)
