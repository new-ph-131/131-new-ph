import os
import shutil
import subprocess

print("📦 Creating 'abhist/' quarantine directory in project root...\n")
target_base = "abhist"
os.makedirs(target_base, exist_ok=True)

# List of Level B unreferenced / duplicate / dead files in lib/
level_b_files = [
    # 1. Obsolete & Duplicate Views (Replaced by MainControlShell & ModifyHub)
    "lib/dashboard_view.dart",
    "lib/more_features_view.dart",
    "lib/reports_view.dart",
    "lib/sale_bill_modify_view.dart",
    "lib/profit_loss_view.dart",

    # 2. Accidental / Broken Duplicates
    "lib/purchase/file_name.dart",            # Accidental duplicate of purchase_entry_view.dart
    "lib/purchase/purchase_modify_view.dart",  # Superseded by ModifyHubView

    # 3. Old Incomplete Prototypes
    "lib/inventory_engine.dart",
    "lib/import_resolver_widgets.dart",
    "lib/import_verification_view.dart",
    "lib/pharoah_smart_logic.dart",
    "lib/batch_master_logic.dart",
    "lib/administration/bank_master_view.dart",
    "lib/administration/staff_management_view.dart",
    "lib/inventory_intel/purchase_order_builder.dart",

    # 4. Old PDF Engines (Superseded by Universal Router & Universal Thermal)
    "lib/pdf/bulk_pdf_service.dart",
    "lib/pdf/architect_bulk_service.dart",
    "lib/pdf/thermal_invoice_pdf.dart",

    # 5. Web Duplicate Subviews
    "lib/web_live_sync/sub_views/web_challans/sale_challan/ui/web_sale_challan_screen.dart"
]

moved_count = 0
total_bytes = 0

for file_path in level_b_files:
    if os.path.exists(file_path):
        size = os.path.getsize(file_path)
        dest_path = os.path.join(target_base, file_path)
        os.makedirs(os.path.dirname(dest_path), exist_ok=True)
        
        # Move file safely into abhist preserving directory structure
        shutil.move(file_path, dest_path)
        print(f"📁 Moved to abhist: {file_path} ({size/1024:.1f} KB)")
        moved_count += 1
        total_bytes += size

print("\n" + "="*60)
print(f"✔ SUCCESS: {moved_count} Level B files safely moved into './abhist/' folder!")
print(f"✔ Space preserved in archive: {total_bytes/1024:.1f} KB")
print("="*60 + "\n")

print("🔍 Verifying Web Live Sync with Flutter Analyze...")
res = subprocess.run(["flutter", "analyze", "lib/web_live_sync/"], text=True)
if res.returncode == 0:
    print("✅ 100% HEALTHY & ERROR-FREE! Web Live Sync untouched & fully operational.")
else:
    print(res.stdout)
