# ==============================================================================
# PHAROAH ERP WEB - GOOGLE COLAB BUILD & DEPLOY RUNNER
# Revision: #PH-REV-811 (FIX-NOBATCH-MULTI-MRP-FY-AND-PURCHASE-DELETE-SYNC)
# Target: Cloudflare Pages (pharoah-erp.pages.dev)
# ==============================================================================
# Security Note: No credentials are embedded in this script.
# Supply CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID via environment
# variables or Google Colab Secrets (userdata) before running.

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

CF_PROJECT_NAME = "pharoah-erp"
REPO_URL = "https://github.com/new-ph-131/131-new-ph.git"
FLUTTER_VERSION = "3.27.4"


def resolve_secret(name: str) -> str:
    val = os.environ.get(name, "").strip()
    if val:
        return val
    try:
        from google.colab import userdata  # type: ignore

        val = (userdata.get(name) or "").strip()
        if val:
            os.environ[name] = val
            return val
    except Exception:
        pass
    return ""


CF_API_TOKEN = resolve_secret("CLOUDFLARE_API_TOKEN")
CF_ACCOUNT_ID = resolve_secret("CLOUDFLARE_ACCOUNT_ID")

if not CF_API_TOKEN or not CF_ACCOUNT_ID:
    print("Blocked: CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID must be set")
    print("in environment variables or Google Colab Secrets before deploying.")
    sys.exit(1)

print("=" * 80)
print("  PHAROAH ERP - COLAB WEB DEPLOYER (#PH-REV-811)")
print("  [FIX-NOBATCH-MULTI-MRP-FY-AND-PURCHASE-DELETE-SYNC]")
print("=" * 80)

subprocess.run(["git", "config", "--global", "--add", "safe.directory", "*"], check=False)


def verify_cloudflare_project(account_id: str, token: str, project_name: str):
    proj_url = f"https://api.cloudflare.com/client/v4/accounts/{account_id}/pages/projects/{project_name}"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "User-Agent": "Pharoah-Colab-Deployer/811",
    }
    req = urllib.request.Request(proj_url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode())
            if data.get("success"):
                subdomain = data.get("result", {}).get("subdomain", f"{project_name}.pages.dev")
                return True, subdomain
            return False, f"API error: {data.get('errors')}"
    except Exception as exc:
        return False, str(exc)


ok, msg = verify_cloudflare_project(CF_ACCOUNT_ID, CF_API_TOKEN, CF_PROJECT_NAME)
if ok:
    print(f"  Project Verified: {CF_PROJECT_NAME} -> https://{msg}")
else:
    print(f"  Direct verification note: {msg}")
    print("  Proceeding to Wrangler edge deployment pipeline...")

print("\n[STEP 1/4] Syncing Latest Source Code (#PH-REV-811)...")
if os.path.exists("pubspec.yaml"):
    subprocess.run(["git", "pull", "origin", "main"], check=False)
elif os.path.exists("pharoah_erp/pubspec.yaml"):
    os.chdir("pharoah_erp")
    subprocess.run(["git", "pull", "origin", "main"], check=False)
else:
    subprocess.run(["git", "clone", "--depth", "1", REPO_URL, "pharoah_erp"], check=True)
    os.chdir("pharoah_erp")

print(f"\n[STEP 2/4] Setting up Flutter SDK ({FLUTTER_VERSION})...")
flutter_bin = "flutter"
has_flutter = subprocess.run(["which", "flutter"], capture_output=True).returncode == 0
if not has_flutter:
    flutter_dir = "/content/flutter_sdk"
    if not os.path.exists(f"{flutter_dir}/bin/flutter"):
        subprocess.run(
            ["git", "clone", "--depth", "1", "-b", FLUTTER_VERSION, "https://github.com/flutter/flutter.git", flutter_dir],
            check=True,
        )
    flutter_bin = f"{flutter_dir}/bin/flutter"

subprocess.run([flutter_bin, "--version"], check=False)

print("\n[STEP 3/4] Building Flutter Web Production Bundle (#PH-REV-811)...")
subprocess.run([flutter_bin, "pub", "get"], check=True)
build_cmd = [
    flutter_bin,
    "build",
    "web",
    "-t",
    "lib/web_live_sync/web_main.dart",
    "--release",
    "--base-href",
    "/",
    "--pwa-strategy=none",
]
t0 = time.time()
res = subprocess.run(build_cmd)
if res.returncode != 0:
    print("Flutter Web Build Failed!")
    sys.exit(1)
print(f"  Web Build Completed in {round(time.time() - t0, 1)}s!")

print(f"\n[STEP 4/4] Deploying build/web to Cloudflare Pages ({CF_PROJECT_NAME})...")
deploy_cmd = [
    "npx",
    "--yes",
    "wrangler@3",
    "pages",
    "deploy",
    "build/web",
    f"--project-name={CF_PROJECT_NAME}",
    "--branch=main",
    "--commit-dirty=true",
]
res_deploy = subprocess.run(deploy_cmd)
if res_deploy.returncode != 0:
    print("Deployment via Wrangler failed. Check logs above.")
    sys.exit(1)

print("=" * 80)
print("#PH-REV-811 LIVE WEB WORKSTATION DEPLOYED SUCCESSFULLY!")
print(f"Live Production URL: https://{CF_PROJECT_NAME}.pages.dev")
print("=" * 80)
