# FILE: deploy_final_web.py
# Universal 1-Click Production Deployment Script for Google Colab & CI/CD
import os
import sys
import subprocess
import re

print("=" * 68)
print("🚀 PHAROAH ERP • UNIVERSAL 1-CLICK PRODUCTION DEPLOYER")
print("=" * 68 + "
")

# Set Cloudflare Token
cf_token = os.environ.get("CLOUDFLARE_API_TOKEN", "")
if not cf_token and len(sys.argv) > 1:
    cf_token = sys.argv[1].strip()
os.environ["CLOUDFLARE_API_TOKEN"] = cf_token

# 1. DIRECTORY DETECTION & GIT SYNC
repo_dir = os.path.dirname(os.path.abspath(__file__))
os.chdir(repo_dir)

print("📥 Step 1/4: Fetching & Fast-Forwarding Latest Code from GitHub...")
try:
    subprocess.run(["git", "fetch", "origin", "main"], check=True)
    subprocess.run(["git", "reset", "--hard", "origin/main"], check=True)
    commit_res = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True, check=True)
    commit_hash = commit_res.stdout.strip()
    print(f"✔ Synced to Latest Commit: {commit_hash}")
except Exception as e:
    print(f"⚠ Git Sync Notice: {e} (Proceeding with local files)")
    commit_hash = "LOCAL"

# 2. READ CURRENT REVISION TAG
current_tag = "LATEST"
tb_path = "lib/web_live_sync/components/web_top_bar.dart"
if os.path.exists(tb_path):
    with open(tb_path, "r", encoding="utf-8") as f:
        content = f.read()
    m = re.search(r"#PH-REV-\d+[^"]*", content)
    if m:
        current_tag = m.group(0)

print(f"🏷️ Active Live Revision: {current_tag}")

# 3. FLUTTER WEB BUILD
print("🔨 Step 2/4: Resolving Dependencies (flutter pub get)...")
subprocess.run(["flutter", "pub", "get"], check=False)

print("⚡ Step 3/4: Building Production Web App (flutter build web)...")
build_cmd = [
    "flutter", "build", "web",
    "-t", "lib/web_live_sync/web_main.dart",
    "--release",
    "--base-href", "/",
    "--pwa-strategy=none"
]
b_res = subprocess.run(build_cmd, text=True)
if b_res.returncode != 0:
    print("❌ Flutter Web Compilation Failed! Check the error logs above.")
    sys.exit(1)

print("✔ Production Web Build Complete!")

# 4. DEPLOY TO CLOUDFLARE PAGES
print("🌐 Step 4/4: Deploying to Cloudflare Pages (pharoah-erp)...")
deploy_cmd = [
    "npx", "wrangler", "pages", "deploy", "build/web",
    "--project-name=pharoah-erp",
    "--branch=main",
    "--commit-dirty=true"
]
d_res = subprocess.run(deploy_cmd, text=True)

if d_res.returncode != 0:
    print("⚠ Direct deploy failed, trying wrangler pages publish with token...")
    pub_cmd = [
        "npx", "wrangler", "pages", "publish", "build/web",
        "--project-name=pharoah-erp",
        "--branch=main"
    ]
    p_res = subprocess.run(pub_cmd, text=True)
    if p_res.returncode != 0:
        print("
" + "=" * 68)
        print("❌ CLOUDFLARE DEPLOYMENT FAILED!")
        print("Wrangler could not upload files to Cloudflare Pages.")
        print("Please verify your Cloudflare API token permissions:")
        print("  Token must have permissions: 'Account - Cloudflare Pages - Edit'")
        print("=" * 68)
        sys.exit(1)

print("
" + "=" * 68)
print("🎉 DEPLOYMENT 100% SUCCESSFUL!")
print(f"🔗 Live URL: https://pharoah-erp.pages.dev")
print(f"🏷️ Deployed Revision: {current_tag}")
print(f"📦 Commit: {commit_hash}")
print("=" * 68)
