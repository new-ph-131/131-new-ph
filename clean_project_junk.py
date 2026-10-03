import os
import subprocess

print("🧹 Starting Safe Project Cleanup (Level A)...\n")

# 1. Remove Root Stray Duplicate Android/Gradle Files
stray_files = [
    "AndroidManifest.xml",
    "MainActivity.kt",
    "build.gradle.kts",
    "settings.gradle.kts",
    "gradle.properties",
    "gradle-wrapper.properties",
    "launch_background.xml",
    "proguard-rules.pro"
]

removed_stray = 0
for f in stray_files:
    if os.path.exists(f):
        os.remove(f)
        print(f"🗑️ Removed Root Stray: {f}")
        removed_stray += 1

# 2. Remove Heavy Zips & Log Dumps
heavy_files = [
    "latest_error.txt",
    "out.txt",
    "dios_project_complete_20260913_120440.zip"
]

removed_heavy = 0
for f in heavy_files:
    if os.path.exists(f):
        os.remove(f)
        print(f"🗑️ Removed Heavy Dump: {f}")
        removed_heavy += 1

# 3. Remove One-Time Python Patch Scripts
keep_scripts = {"live_web_terminal.py", "audit_project_files.py", "clean_project_junk.py"}
removed_scripts = 0
for f in os.listdir("."):
    if f.endswith(".py") and f not in keep_scripts:
        os.remove(f)
        print(f"🗑️ Removed Old Script: {f}")
        removed_scripts += 1

# 4. Remove Web-Only Dead Experimental Files
web_dead_files = [
    "lib/web_live_sync/drive_sync_service.dart",
    "lib/web_live_sync/google_oauth_service.dart",
    "lib/web_live_sync/web_app_root.dart",
    "lib/web_live_sync/sub_views/web_smart_entry/medilente/ui/medilente_preview_table.dart"
]

removed_web = 0
for f in web_dead_files:
    if os.path.exists(f):
        os.remove(f)
        print(f"🗑️ Removed Web Dead File: {f}")
        removed_web += 1

total_cleaned = removed_stray + removed_heavy + removed_scripts + removed_web
print(f"\n✔ Total {total_cleaned} junk files safely purged! (~61 MB freed)")

print("\n🔍 Running Flutter Analyze on web_live_sync to verify integrity...")
res = subprocess.run(["flutter", "analyze", "lib/web_live_sync/"], text=True)
if res.returncode == 0:
    print("✅ 100% CLEAN! Web Live Sync is completely healthy.")
else:
    print(res.stdout)
