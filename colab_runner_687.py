# ==============================================================================
# 🚀 PHAROAH ERP WEB - ADVANCED GOOGLE COLAB BUILD & DEPLOY RUNNER
# Revision: #PH-REV-689 (ENTERPRISE-PERMANENT-TOMBSTONE-SHIELD-PRO)
# Target: Cloudflare Pages (pharoah-erp.pages.dev)
# ==============================================================================

import os
import sys
import json
import time
import subprocess
import urllib.request
import urllib.error

# 🔑 CONFIGURATION
CF_API_TOKEN = os.environ.get("CLOUDFLARE_API_TOKEN", "PASTE_YOUR_CLOUDFLARE_API_TOKEN_HERE").strip()
CF_PROJECT_NAME = "pharoah-erp"
REPO_URL = "https://github.com/new-ph-131/131-new-ph.git"
FLUTTER_VERSION = "3.27.4"

print("=" * 80)
print("       PHAROAH ERP - COLAB ADVANCED WEB DEPLOYER (#PH-REV-689)")
print("=" * 80)

# ==============================================================================
# STEP 1: SMART CLOUDFLARE TOKEN VERIFICATION
# ==============================================================================
print("\n🔍 [STEP 1/5] Verifying Cloudflare API Token...")

def verify_cloudflare_token(token, project_name):
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "User-Agent": "Pharoah-Colab-Deployer/1.0"
    }
    
    # 1. Check Accounts endpoint
    acc_url = "https://api.cloudflare.com/client/v4/accounts"
    req = urllib.request.Request(acc_url, headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode())
            if not data.get("success"):
                return False, None, f"API returned success=false: {data.get('errors')}"
            
            accounts = data.get("result", [])
            if not accounts:
                return False, None, "No Cloudflare accounts accessible with this token!"
            
            account = accounts[0]
            account_id = account.get("id")
            account_name = account.get("name")
            print(f"  ✔ Account Verified: {account_name} (ID: {account_id})")
            
            # 2. Check Pages project
            proj_url = f"https://api.cloudflare.com/client/v4/accounts/{account_id}/pages/projects/{project_name}"
            p_req = urllib.request.Request(proj_url, headers=headers)
            with urllib.request.urlopen(p_req) as p_resp:
                p_data = json.loads(p_resp.read().decode())
                if p_data.get("success"):
                    proj_subdomain = p_data.get("result", {}).get("subdomain", f"{project_name}.pages.dev")
                    print(f"  ✔ Project Verified: {project_name} -> {proj_subdomain}")
                    return True, account_id, f"Verified ({proj_subdomain})"
                else:
                    return False, account_id, f"Project '{project_name}' not accessible: {p_data.get('errors')}"
                    
    except urllib.error.HTTPError as e:
        err_msg = e.read().decode()
        return False, None, f"HTTP {e.code}: {err_msg}"
    except Exception as e:
        return False, None, f"Network Exception: {str(e)}"

is_valid, account_id, diagnostic_msg = verify_cloudflare_token(CF_API_TOKEN, CF_PROJECT_NAME)

if not is_valid:
    print("\n❌ CLOUDFLARE TOKEN VERIFICATION FAILED!")
    print("=" * 80)
    print("Diagnostic Output:")
    print(diagnostic_msg)
    print("=" * 80)
    print("💡 Solution Instructions:")
    print("1. Login to Cloudflare Dashboard -> My Profile -> API Tokens")
    print("2. Ensure the token has permissions: Account -> Cloudflare Pages -> Edit")
    print("3. Update CF_API_TOKEN at the top of this script.")
    sys.exit(1)

print("  🎉 Cloudflare Token is 100% VALID & Ready for Deployment!")

# Set environment variables for Wrangler
os.environ["CLOUDFLARE_API_TOKEN"] = CF_API_TOKEN
if account_id:
    os.environ["CLOUDFLARE_ACCOUNT_ID"] = account_id

# ==============================================================================
# STEP 2: REPOSITORY SYNC (#PH-REV-689)
# ==============================================================================
print("\n📥 [STEP 2/5] Syncing Source Code from GitHub...")
if os.path.exists(".git"):
    print("  Pulling latest changes from origin main...")
    subprocess.run(["git", "pull", "origin", "main"], check=False)
else:
    print(f"  Cloning {REPO_URL}...")
    subprocess.run(["git", "clone", "--depth", "1", REPO_URL, "pharoah_erp"], check=True)
    os.chdir("pharoah_erp")

# ==============================================================================
# STEP 3: FLUTTER SDK SETUP (Version 3.27.4)
# ==============================================================================
print(f"\n🛠️  [STEP 3/5] Checking Flutter SDK ({FLUTTER_VERSION})...")
flutter_bin = "flutter"

has_flutter = subprocess.run(["which", "flutter"], capture_output=True).returncode == 0
if not has_flutter:
    flutter_dir = os.path.expanduser("~/flutter")
    if not os.path.exists(flutter_dir):
        print(f"  Downloading Flutter {FLUTTER_VERSION}...")
        subprocess.run(["git", "clone", "--depth", "1", "-b", FLUTTER_VERSION, "https://github.com/flutter/flutter.git", flutter_dir], check=True)
    os.environ["PATH"] = f"{flutter_dir}/bin:" + os.environ["PATH"]
    flutter_bin = f"{flutter_dir}/bin/flutter"

subprocess.run([flutter_bin, "--version"], check=False)

# ==============================================================================
# STEP 4: PRODUCTION WEB BUILD
# ==============================================================================
print("\n🔨 [STEP 4/5] Building Flutter Web Production Assets...")
subprocess.run([flutter_bin, "pub", "get"], check=True)

build_cmd = [
    flutter_bin, "build", "web",
    "-t", "lib/web_live_sync/web_main.dart",
    "--release",
    "--base-href", "/",
    "--pwa-strategy=none"
]
print(f"  Executing: {' '.join(build_cmd)}")
t0 = time.time()
res = subprocess.run(build_cmd)
if res.returncode != 0:
    print("❌ Flutter Web Build Failed! Check logs above.")
    sys.exit(1)

build_duration = round(time.time() - t0, 1)
print(f"  ✔ Build Completed Successfully in {build_duration}s!")

# ==============================================================================
# STEP 5: DEPLOY TO CLOUDFLARE PAGES
# ==============================================================================
print("\n🚀 [STEP 5/5] Deploying to Cloudflare Pages (pharoah-erp)...")
deploy_cmd = [
    "npx", "wrangler", "pages", "deploy", "build/web",
    f"--project-name={CF_PROJECT_NAME}",
    "--commit-dirty=true"
]
deploy_res = subprocess.run(deploy_cmd)
if deploy_res.returncode == 0:
    print("\n" + "=" * 80)
    print("🎉 #PH-REV-689 WEB PORTAL DEPLOYED SUCCESSFULLY!")
    print("🔗 Live URL: https://pharoah-erp.pages.dev")
    print("🛡️ Features: Enterprise Monotonic Versioning, OCC Rebase & Sale Modification Shield")
    print("=" * 80)
else:
    print("❌ Wrangler Pages Deployment Failed! Check logs above.")
    sys.exit(1)
