#!/usr/bin/env python3
import os
import re

print("\n" + "="*65)
print("🔍 PHAROAH ERP • SMART PROJECT DEEP AUDIT")
print("="*65 + "\n")

# 1. Root Level Android/Gradle Duplicate Files
root_stray_candidates = [
    "AndroidManifest.xml",
    "MainActivity.kt",
    "build.gradle.kts",
    "settings.gradle.kts",
    "gradle.properties",
    "gradle-wrapper.properties",
    "launch_background.xml",
    "proguard-rules.pro"
]

stray_files = []
for f in root_stray_candidates:
    if os.path.exists(f):
        size_kb = os.path.getsize(f) / 1024
        stray_files.append((f, size_kb))

# 2. Heavy Zips & Log/Text Dumps in Root
junk_dumps = []
for f in os.listdir("."):
    if f.endswith(".zip") or f in ["latest_error.txt", "out.txt"] or f.endswith(".log"):
        size_kb = os.path.getsize(f) / 1024
        junk_dumps.append((f, size_kb))

# 3. One-Time Fix / Patch Scripts in Root
one_time_scripts = []
for f in os.listdir("."):
    if f.endswith(".py") and f not in ["live_web_terminal.py", "audit_project_files.py"]:
        size_kb = os.path.getsize(f) / 1024
        one_time_scripts.append((f, size_kb))

# 4. Deep Dead Dart Files Analysis in lib/
all_dart_files = {}
for root, _, files in os.walk("lib"):
    for file in files:
        if file.endswith(".dart"):
            full_path = os.path.join(root, file)
            all_dart_files[full_path] = {
                "name": file,
                "is_entry": full_path in ["lib/main.dart", "lib/web_live_sync/web_main.dart"],
                "imported_by": []
            }

# Extract all imports across all dart files
for path in all_dart_files.keys():
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
            for line in content.splitlines():
                line = line.strip()
                if line.startswith("import ") or line.startswith("export "):
                    # Extract target uri
                    m = re.search(r"['\"]([^'\"]+)['\"]", line)
                    if m:
                        uri = m.group(1)
                        if uri.startswith("package:pharoah_erp/"):
                            resolved = os.path.normpath(os.path.join("lib", uri.replace("package:pharoah_erp/", "")))
                        elif not uri.startswith("package:") and not uri.startswith("dart:"):
                            resolved = os.path.normpath(os.path.join(os.path.dirname(path), uri))
                        else:
                            continue
                        
                        if resolved in all_dart_files:
                            all_dart_files[resolved]["imported_by"].append(path)
    except Exception:
        pass

dead_dart_files = []
for path, info in all_dart_files.items():
    if not info["is_entry"] and len(info["imported_by"]) == 0:
        size_kb = os.path.getsize(path) / 1024
        dead_dart_files.append((path, size_kb))

# Output Generation
report_lines = []
def print_and_record(text):
    print(text)
    report_lines.append(text)

print_and_record("📁 [CATEGORY 1] ROOT-LEVEL STRAY / DUPLICATE ANDROID FILES:")
print_and_record("   (Note: Ye files 'android/' ke andar already hain, root me galti se copy hui thi)")
if stray_files:
    for f, sz in stray_files:
        print_and_record(f"   ❌ {f:<26} ({sz:.1f} KB)")
else:
    print_and_record("   ✔ Koi stray file nahi mili.")

print_and_record("\n" + "-"*65)
print_and_record("📦 [CATEGORY 2] HEAVY BACKUP ZIPS & DUMP LOGS:")
print_and_record("   (Note: Space khane wali purani zip files aur error dumps)")
if junk_dumps:
    for f, sz in junk_dumps:
        print_and_record(f"   ⚠️  {f:<38} ({sz:.1f} KB)")
else:
    print_and_record("   ✔ Koi junk dump nahi mila.")

print_and_record("\n" + "-"*65)
print_and_record("📜 [CATEGORY 3] OLD ONE-TIME PYTHON PATCH / DEPLOY SCRIPTS:")
print_and_record("   (Note: Purane step scripts aur fixes jinka kaam complete ho chuka hai)")
if one_time_scripts:
    for f, sz in one_time_scripts:
        print_and_record(f"   ⚙️  {f:<38} ({sz:.1f} KB)")
else:
    print_and_record("   ✔ Koi purani script nahi mili.")

print_and_record("\n" + "-"*65)
print_and_record("🔍 [CATEGORY 4] DEAD / UNREFERENCED DART FILES (IN LIB):")
print_and_record("   (Note: Ye dart files project me kahi bhi import ya use nahi ho rahi)")
if dead_dart_files:
    for f, sz in dead_dart_files:
        print_and_record(f"   🚫 {f:<42} ({sz:.1f} KB)")
else:
    print_and_record("   ✔ Saari dart files active aur linked hain.")

total_files = len(stray_files) + len(junk_dumps) + len(one_time_scripts) + len(dead_dart_files)
total_kb = sum(sz for _, sz in stray_files) + sum(sz for _, sz in junk_dumps) + sum(sz for _, sz in one_time_scripts) + sum(sz for _, sz in dead_dart_files)

print_and_record("\n" + "="*65)
print_and_record(f"📊 SUMMARY: Total {total_files} Faltu/Unused Files Detected | Space: {total_kb/1024:.2f} MB")
print_and_record("="*65 + "\n")

# Save report to file as well
with open("project_cleanup_audit.txt", "w", encoding="utf-8") as rf:
    rf.write("\n".join(report_lines))
print("💾 Audit Report saved to: project_cleanup_audit.txt\n")
