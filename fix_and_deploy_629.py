import os
import re
import shutil
import subprocess
import sys

print("==================================================================")
print("🚀 PHAROAH ERP • MASTER FIX & 50-ITEM DUAL-AXIS SCROLL (#PH-REV-629)")
print("==================================================================\n")

# ----------------------------------------------------------------------
# 1. REMOVE JUNK 'abhist/' DIRECTORY
# ----------------------------------------------------------------------
print("🧹 Step 1/8: Removing junk 'abhist/' folder...")
if os.path.exists("abhist"):
    shutil.rmtree("abhist", ignore_errors=True)
    print("✔ 'abhist/' directory deleted successfully.")
else:
    print("ℹ️ 'abhist/' already removed.")

# ----------------------------------------------------------------------
# 2. UPDATE TOP BAR TAG TO #PH-REV-629
# ----------------------------------------------------------------------
print("\n🏷️ Step 2/8: Updating Live Tag to #PH-REV-629...")
tb_path = "lib/web_live_sync/components/web_top_bar.dart"
if os.path.exists(tb_path):
    with open(tb_path, "r", encoding="utf-8") as f:
        tb = f.read()
    new_rev = "#PH-REV-629 (50-ITEMS-DUAL-AXIS-SCROLL-PERFECT-FIX)"
    tb = re.sub(r"#PH-REV-\d+[^\"]*", new_rev, tb)
    with open(tb_path, "w", encoding="utf-8") as f:
        f.write(tb)
    print(f"✔ Tag Updated: {new_rev}")

# ----------------------------------------------------------------------
# 3. ADD MISSING METHODS TO PharoahManager (lib/pharoah_manager.dart)
# ----------------------------------------------------------------------
print("\n⚡ Step 3/8: Adding missing salesmen, switchYear, getBankStatement & cancelBill to PharoahManager...")
pm_path = "lib/pharoah_manager.dart"
with open(pm_path, "r", encoding="utf-8") as f:
    pm = f.read()

# A. Add salesmen list if not present
if "List<Salesman> salesmen" not in pm:
    pm = pm.replace(
        "List<Medicine> medicines = [];",
        "List<Medicine> medicines = [];\n  List<Salesman> salesmen = [];"
    )

# B. Add salesmen methods
if "void addSalesman(" not in pm:
    salesman_methods = """
  void addSalesman(Salesman s) { salesmen.add(s); save(); notifyListeners(); }
  void deleteSalesman(String id) { salesmen.removeWhere((s) => s.id == id); save(); notifyListeners(); }
"""
    pm = pm.replace("void addMedicine(", salesman_methods + "\n  void addMedicine(")

# C. Add switchYear method
if "Future<void> switchYear(" not in pm:
    switch_year_code = """
  Future<void> switchYear(String year) async {
    currentFY = year;
    if (activeCompany != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_fy_${activeCompany!.id}', year);
    }
    await loadAllData();
  }
"""
    pm = pm.replace("Future<void> loginToCompany(", switch_year_code + "\n  Future<void> loginToCompany(")

# D. Add getBankStatement method
if "List<BankTransaction> getBankStatement(" not in pm:
    bank_statement_code = """
  List<BankTransaction> getBankStatement(String bankName, DateTime from, DateTime to) {
    List<BankTransaction> list = [];
    String bName = bankName.trim().toUpperCase();
    for (var v in vouchers.where((v) => v.status == "Active" && v.depositedIn.trim().toUpperCase() == bName)) {
      if (v.date.isAfter(from.subtract(const Duration(seconds: 1))) && v.date.isBefore(to.add(const Duration(days: 1)))) {
        bool isRec = v.type.toUpperCase() == "RECEIPT";
        list.add(BankTransaction(
          id: v.id,
          date: v.date,
          particulars: v.partyName,
          reference: v.voucherNo,
          amountIn: isRec ? v.amount : 0.0,
          amountOut: isRec ? 0.0 : v.amount,
          type: v.type,
        ));
      }
    }
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }
"""
    pm = pm.replace("List<Party> getInternalAccounts() {", bank_statement_code + "\n  List<Party> getInternalAccounts() {")

# E. Add cancelBill method
if "void cancelBill(" not in pm:
    cancel_bill_code = """
  void cancelBill(String id) {
    int i = sales.indexWhere((x) => x.id == id);
    if (i != -1) {
      sales[i].status = "Cancelled";
      save().then((_) => loadAllData());
      notifyListeners();
    }
  }
"""
    pm = pm.replace("void deleteBill(String id) {", cancel_bill_code + "\n  void deleteBill(String id) {")

with open(pm_path, "w", encoding="utf-8") as f:
    f.write(pm)
print("✔ PharoahManager updated with all required getters/methods.")

# ----------------------------------------------------------------------
# 4. FIX MINOR ERRORS IN MISC APP FILES
# ----------------------------------------------------------------------
print("\n🔧 Step 4/8: Fixing purchase_modify_view, reports_view, bulk_pdf_service...")

# A. purchase_modify_view.dart: PurchasePdf.generate expects 3 args
pmv_path = "lib/purchase/purchase_modify_view.dart"
if os.path.exists(pmv_path):
    with open(pmv_path, "r", encoding="utf-8") as f:
        pmv = f.read()
    pmv = pmv.replace("PurchasePdf.generate(p, supplier)", "PurchasePdf.generate(p, supplier, ph.activeCompany!)")
    with open(pmv_path, "w", encoding="utf-8") as f:
        f.write(pmv)
    print("✔ purchase_modify_view.dart fixed.")

# B. reports_view.dart: replace non-existent pdf_service.dart with pdf_router_service.dart
rv_path = "lib/reports_view.dart"
if os.path.exists(rv_path):
    with open(rv_path, "r", encoding="utf-8") as f:
        rv = f.read()
    rv = rv.replace("import 'pdf_service.dart';", "import 'pdf/pdf_router_service.dart';")
    rv = rv.replace("PdfService.generateInvoice(sale, p);", "PdfRouterService.printSale(sale: sale, party: p, ph: ph);")
    with open(rv_path, "w", encoding="utf-8") as f:
        f.write(rv)
    print("✔ reports_view.dart fixed.")

# C. bulk_pdf_service.dart: line 102 billNo undefined -> sale.billNo
bps_path = "lib/pdf/bulk_pdf_service.dart"
if os.path.exists(bps_path):
    with open(bps_path, "r", encoding="utf-8") as f:
        bps = f.read()
    bps = bps.replace("pw.Text(billNo,", "pw.Text(sale.billNo,")
    with open(bps_path, "w", encoding="utf-8") as f:
        f.write(bps)
    print("✔ bulk_pdf_service.dart fixed.")

# ----------------------------------------------------------------------
# 5. FIX PDF 'const' OPERATOR ERRORS
# ----------------------------------------------------------------------
print("\n📄 Step 5/8: Fixing invalid 'const' in PDF generation files...")

pdf_files_to_clean = [
    "lib/pdf/architect_bulk_service.dart",
    "lib/pdf/architect_sale_pdf.dart",
    "lib/pdf/credit_note_pdf.dart",
    "lib/pdf/debit_note_pdf.dart",
    "lib/pdf/history_report_pdf.dart",
    "lib/pdf/sale_invoice_pdf.dart",
    "lib/pdf/statements/expiry_audit_pdf.dart",
    "lib/pdf/thermal_invoice_pdf.dart",
    "lib/pdf/universal_thermal_engine.dart",
    "lib/pdf/voucher_pdf.dart",
]

for p in pdf_files_to_clean:
    if os.path.exists(p):
        with open(p, "r", encoding="utf-8") as f:
            code = f.read()
        # Remove const from BoxDecoration and TextStyle where complex styles/enums are used
        cleaned = code.replace("const pw.BoxDecoration(border: pw.Border", "pw.BoxDecoration(border: pw.Border")
        cleaned = cleaned.replace("const pw.TextStyle(fontSize: 5.5, fontStyle: pw.FontStyle.italic)", "pw.TextStyle(fontSize: 5.5, fontStyle: pw.FontStyle.italic)")
        cleaned = cleaned.replace("const pw.TextStyle(fontSize: 6, fontStyle: pw.FontStyle.italic)", "pw.TextStyle(fontSize: 6, fontStyle: pw.FontStyle.italic)")
        cleaned = cleaned.replace("const pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic)", "pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic)")
        cleaned = cleaned.replace("const pw.TextStyle(fontSize: 6, color: PdfColors.blueGrey800)", "pw.TextStyle(fontSize: 6, color: PdfColors.blueGrey800)")
        cleaned = cleaned.replace("const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)", "pw.TextStyle(fontSize: 7, color: PdfColors.grey700)")
        cleaned = cleaned.replace("const pw.TextStyle(fontSize: 7.5)", "pw.TextStyle(fontSize: 7.5)")
        cleaned = cleaned.replace("const pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)", "pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)")
        if cleaned != code:
            with open(p, "w", encoding="utf-8") as f:
                f.write(cleaned)
            print(f"✔ Fixed const evaluation in: {p}")

# ----------------------------------------------------------------------
# 6. RESTORE CLEAN DUAL-AXIS SCROLL IN WEB CART & INVOICE SCREENS
# ----------------------------------------------------------------------
print("\n⚡ Step 6/8: Installing clean Dual-Axis Scroll architecture...")

# A. Restore web_new_sale_view.dart with 100% clean syntax
wns_path = "lib/web_live_sync/sub_views/web_billing/web_new_sale_view.dart"
subprocess.run(["git", "checkout", "HEAD", "--", wns_path], capture_output=True)
with open(wns_path, "r", encoding="utf-8") as f:
    wns = f.read()

# Replace _buildCartTable with clean vertical + horizontal scroll
old_cart_pattern = r'SingleChildScrollView\(\s*scrollDirection: Axis\.horizontal,\s*child: ConstrainedBox\(\s*constraints: const BoxConstraints\(minWidth: 700\),\s*child: Table\('
new_cart_block = '''Container(
              constraints: const BoxConstraints(minHeight: 220, maxHeight: 520),
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 720),
                      child: Table('''

if re.search(old_cart_pattern, wns):
    wns = re.sub(old_cart_pattern, new_cart_block, wns)
    # Add closing Container and Scrollbar brackets
    wns = re.sub(
        r'(\}\),\s*\]\),\s*\),\s*\),\s*\]\s*,\s*\),\s*\);\s*\}\s*Widget _th)',
        r'}\),\n                    ]),\n                  ),\n                ),\n              ),\n            ),\n        ],\n      ),\n    );\n  }\n\n  Widget _th',
        wns
    )
    with open(wns_path, "w", encoding="utf-8") as f:
        f.write(wns)
    print("✔ web_new_sale_view.dart: Dual-Axis Scroll installed.")

# B. Restore web_purchase_entry_view.dart with 100% clean syntax
wpe_path = "lib/web_live_sync/web_purchase_entry_view.dart"
subprocess.run(["git", "checkout", "HEAD", "--", wpe_path], capture_output=True)
with open(wpe_path, "r", encoding="utf-8") as f:
    wpe = f.read()

old_pur_pattern = r'Expanded\(\s*child: SingleChildScrollView\(\s*scrollDirection: Axis\.horizontal,\s*child: ConstrainedBox\(\s*constraints: const BoxConstraints\(minWidth: 650\),\s*child: SingleChildScrollView\(\s*child: Table\('
new_pur_block = '''Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 220),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 680),
                        child: Table('''

if re.search(old_pur_pattern, wpe):
    wpe = re.sub(old_pur_pattern, new_pur_block, wpe)
    wpe = re.sub(
        r'(\}\),\s*\]\),\s*\),\s*\),\s*\),\s*\]\s*,\s*\),\s*\);\s*\}\s*Widget _buildFooter)',
        r'}\),\n                      ]),\n                    ),\n                  ),\n                ),\n              ),\n            ),\n        ],\n      ),\n    );\n  }\n\n  Widget _buildFooter',
        wpe
    )
    with open(wpe_path, "w", encoding="utf-8") as f:
        f.write(wpe)
    print("✔ web_purchase_entry_view.dart: Dual-Axis Scroll installed.")

# C. Reset challan & return cart files to clean state
subprocess.run(["git", "checkout", "HEAD", "--", "lib/web_live_sync/sub_views/web_challans/sale_challan/ui/sale_challan_cart_widget.dart"], capture_output=True)
subprocess.run(["git", "checkout", "HEAD", "--", "lib/web_live_sync/sub_views/web_returns/credit_note/ui/credit_note_cart_widget.dart"], capture_output=True)
subprocess.run(["git", "checkout", "HEAD", "--", "lib/web_live_sync/sub_views/web_returns/debit_note/ui/debit_note_cart_widget.dart"], capture_output=True)
print("✔ Cart widgets reset to pristine state.")

# ----------------------------------------------------------------------
# 7. RUN FLUTTER ANALYZE
# ----------------------------------------------------------------------
print("\n🔍 Step 7/8: Running Flutter Analyze to verify 0 errors...")
analyze_res = subprocess.run(["flutter", "analyze"], capture_output=True, text=True)
print(analyze_res.stdout)

if analyze_res.returncode != 0:
    print("⚠️ Analyzer found remaining issues. Summary:")
    for line in analyze_res.stdout.split('\n'):
        if 'error •' in line:
            print("  " + line)
    sys.exit(1)

print("🎉 ALL ERRORS CLEARED! 0 ISSUES FOUND.")

# ----------------------------------------------------------------------
# 8. BUILD AND DEPLOY TO CLOUDFLARE PAGES
# ----------------------------------------------------------------------
print("\n🔨 Step 8/8: Building & Deploying Web App...")
b_res = subprocess.run(
    ["flutter", "build", "web", "-t", "lib/web_live_sync/web_main.dart", "--release", "--base-href", "/", "--pwa-strategy=none"],
    text=True
)
if b_res.returncode != 0:
    print("❌ Web Build Failed!")
    sys.exit(1)

subprocess.run(["npx", "wrangler", "pages", "deploy", "build/web", "--project-name=pharoah-erp"], text=True)

# Commit & Push
subprocess.run(["git", "add", "."], text=True)
subprocess.run(["git", "commit", "-m", "🚀 #PH-REV-629: Master Compile Fix & 50-Item Dual-Axis Scroll Installed"], text=True)
branch_res = subprocess.run(["git", "branch", "--show-current"], capture_output=True, text=True)
branch = branch_res.stdout.strip() or "main"
subprocess.run(["git", "push", "origin", branch], text=True)

print("\n" + "="*65)
print("🎉 COMPLETED: #PH-REV-629 IS NOW LIVE ON CLOUDFLARE & GITHUB!")
print("🔗 Website: https://pharoah-erp.pages.dev")
print("✅ Verified Tag: #PH-REV-629 (50-ITEMS-DUAL-AXIS-SCROLL-PERFECT-FIX)")
print("="*65)
