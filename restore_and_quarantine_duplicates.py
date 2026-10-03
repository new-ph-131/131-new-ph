import os
import shutil

print("🔄 Step 1: Restoring all lib files from 'abhist/' back to original locations...\n")

if not os.path.exists("abhist"):
    print("ℹ️ 'abhist/' folder nahi mila. Nothing to restore.")
else:
    restored_count = 0
    for root, dirs, files in os.walk("abhist"):
        for f in files:
            src_path = os.path.join(root, f)
            rel_path = os.path.relpath(src_path, "abhist")
            dest_dir = os.path.dirname(rel_path)
            if dest_dir:
                os.makedirs(dest_dir, exist_ok=True)
            shutil.move(src_path, rel_path)
            print(f"↩️ Restored to original path: {rel_path}")
            restored_count += 1

    print(f"\n✔ Total {restored_count} files restored back to lib/!")

print("\n" + "-"*60)
print("🔍 Step 2: Isolating ONLY the 100% confirmed accidental duplicate...")

# Sirf wahi file jo actual me duplicate class definition hai:
# 'lib/purchase/file_name.dart' (is me PurchaseEntryView hai jo 'purchase_entry_view.dart' me already hai)
duplicate_files = [
    "lib/purchase/file_name.dart"
]

isolated_count = 0
for dup in duplicate_files:
    if os.path.exists(dup):
        dest = os.path.join("abhist", dup)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.move(dup, dest)
        print(f"📁 Isolated duplicate into abhist: {dup}")
        isolated_count += 1

print("\n" + "="*60)
print(f"✔ SUMMARY: Saari lib files wapas unki jagah par aa gayi hain!")
print(f"✔ Sirf {isolated_count} confirmed duplicate file ('file_name.dart') alag 'abhist/' me rakhi gayi hai.")
print("="*60 + "\n")
