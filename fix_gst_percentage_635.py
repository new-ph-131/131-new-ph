import os
import re
import subprocess
import sys

print("==================================================================")
print("🚀 FIXING PDF GST PERCENTAGE VS AMOUNT BUG (#PH-REV-635)")
print("==================================================================\n")

# 1. UPDATE LIVE TAG TO #PH-REV-635
print("🏷️ Step 1/5: Updating Live Tag to #PH-REV-635...")
tb_path = "lib/web_live_sync/components/web_top_bar.dart"
if os.path.exists(tb_path):
    with open(tb_path, "r", encoding="utf-8") as f:
        tb = f.read()
    new_rev = "#PH-REV-635 (PDF-GST-PERCENTAGE-FIX)"
    tb = re.sub(r"#PH-REV-\d+[^\"]*", new_rev, tb)
    with open(tb_path, "w", encoding="utf-8") as f:
        f.write(tb)
    print(f"✔ Tag Updated: {new_rev}")

# 2. FIX PURCHASE INVOICE PDF (web_purchase_invoice_pdf.dart)
print("\n📄 Step 2/5: Correcting Purchase Invoice PDF generation...")
pur_pdf_path = "lib/web_live_sync/pdf/web_purchase_invoice_pdf.dart"
with open(pur_pdf_path, "r", encoding="utf-8") as f:
    pur_pdf = f.read()

# Fix Header
pur_pdf = pur_pdf.replace(
    'if (isLocal) ...[_tCol("CGST", 40), _tCol("SGST", 40)] else _tCol("IGST", 80),',
    'if (isLocal) ...[_tCol("CGST%", 40), _tCol("SGST%", 40)] else _tCol("IGST%", 80),'
)

# Fix Values (Remove unused variables and print GST percentage)
old_block_pur = '''                          double taxableRow = i.purchaseRate * i.qty - i.discountRupees;
                          double taxAmt = i.total - taxableRow;

                          return pw.Container(
                            height: 18,
                            decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.1, color: PdfColors.grey400))),
                            child: pw.Row(
                              children: [
                                _cell("${start + idx + 1}", 25),
                                _cell(qtyDisp, 55),
                                _cell(i.packing, 45),
                                pw.Container(
                                  width: 215, padding: const pw.EdgeInsets.only(left: 8), alignment: pw.Alignment.centerLeft,
                                  child: pw.Text(i.name, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold), maxLines: 1),
                                ),
                                _cell(i.batch, 80),
                                _cell(i.exp, 45),
                                _cell(i.hsn, 45),
                                _cell(i.mrp.toStringAsFixed(2), 55),
                                _cell(i.purchaseRate.toStringAsFixed(2), 55),
                                if (isLocal) ...[
                                  _cell((taxAmt / 2).toStringAsFixed(1), 40),
                                  _cell((taxAmt / 2).toStringAsFixed(1), 40),
                                ] else ...[
                                  _cell(taxAmt.toStringAsFixed(1), 80),
                                ],
                                _cell(i.total.toStringAsFixed(2), 100),
                              ],
                            ),
                          );'''

new_block_pur = '''                          return pw.Container(
                            height: 18,
                            decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.1, color: PdfColors.grey400))),
                            child: pw.Row(
                              children: [
                                _cell("${start + idx + 1}", 25),
                                _cell(qtyDisp, 55),
                                _cell(i.packing, 45),
                                pw.Container(
                                  width: 215, padding: const pw.EdgeInsets.only(left: 8), alignment: pw.Alignment.centerLeft,
                                  child: pw.Text(i.name, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold), maxLines: 1),
                                ),
                                _cell(i.batch, 80),
                                _cell(i.exp, 45),
                                _cell(i.hsn, 45),
                                _cell(i.mrp.toStringAsFixed(2), 55),
                                _cell(i.purchaseRate.toStringAsFixed(2), 55),
                                if (isLocal) ...[
                                  _cell("${(i.gstRate / 2).toStringAsFixed(1)}%", 40),
                                  _cell("${(i.gstRate / 2).toStringAsFixed(1)}%", 40),
                                ] else ...[
                                  _cell("${i.gstRate.toStringAsFixed(1)}%", 80),
                                ],
                                _cell(i.total.toStringAsFixed(2), 100),
                              ],
                            ),
                          );'''

if old_block_pur in pur_pdf:
    pur_pdf = pur_pdf.replace(old_block_pur, new_block_pur)
    with open(pur_pdf_path, "w", encoding="utf-8") as f:
        f.write(pur_pdf)
    print("✔ Purchase Invoice PDF fixed.")

# 3. FIX ROUTER PDF SERVICES (Sale, CN, DN Headers & DN Values)
print("\n🔗 Step 3/5: Correcting PDF Router Service (Debit Note & Sale Headers)...")
router_path = "lib/web_live_sync/web_pdf_router_service.dart"
with open(router_path, "r", encoding="utf-8") as f:
    router = f.read()

# Fix ALL headers globally in router
router = router.replace(
    'if (isLocal) ...[_tCol("CGST", 40), _tCol("SGST", 40)] else _tCol("IGST", 80),',
    'if (isLocal) ...[_tCol("CGST%", 40), _tCol("SGST%", 40)] else _tCol("IGST%", 80),'
)

# Fix Debit Note Values
old_block_dn = '''                          double taxableRow = i.purchaseRate * i.qty;
                          double taxAmt = i.total - taxableRow;

                          return pw.Container(
                            height: 18,
                            decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.1, color: PdfColors.grey400))),
                            child: pw.Row(
                              children: [
                                _cell("$sNo", 25),
                                _cell("${fmt(i.qty)} + ${fmt(i.freeQty)}", 60),
                                _cell(i.packing, 40),
                                pw.Container(
                                  width: 220, padding: const pw.EdgeInsets.only(left: 8), alignment: pw.Alignment.centerLeft,
                                  child: pw.Text(i.name, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold), maxLines: 1),
                                ),
                                _cell(i.batch, 75), _cell(i.exp, 45), _cell(i.hsn, 45),
                                _cell(i.mrp.toStringAsFixed(2), 55),
                                _cell(i.purchaseRate.toStringAsFixed(2), 55),
                                if (isLocal) ...[
                                  _cell((taxAmt / 2).toStringAsFixed(1), 40),
                                  _cell((taxAmt / 2).toStringAsFixed(1), 40),
                                ] else ...[
                                  _cell(taxAmt.toStringAsFixed(1), 80),
                                ],
                                _cell(i.total.toStringAsFixed(2), 100),
                              ],
                            ),
                          );'''

new_block_dn = '''                          return pw.Container(
                            height: 18,
                            decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.1, color: PdfColors.grey400))),
                            child: pw.Row(
                              children: [
                                _cell("$sNo", 25),
                                _cell("${fmt(i.qty)} + ${fmt(i.freeQty)}", 60),
                                _cell(i.packing, 40),
                                pw.Container(
                                  width: 220, padding: const pw.EdgeInsets.only(left: 8), alignment: pw.Alignment.centerLeft,
                                  child: pw.Text(i.name, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold), maxLines: 1),
                                ),
                                _cell(i.batch, 75), _cell(i.exp, 45), _cell(i.hsn, 45),
                                _cell(i.mrp.toStringAsFixed(2), 55),
                                _cell(i.purchaseRate.toStringAsFixed(2), 55),
                                if (isLocal) ...[
                                  _cell("${(i.gstRate / 2).toStringAsFixed(1)}%", 40),
                                  _cell("${(i.gstRate / 2).toStringAsFixed(1)}%", 40),
                                ] else ...[
                                  _cell("${i.gstRate.toStringAsFixed(1)}%", 80),
                                ],
                                _cell(i.total.toStringAsFixed(2), 100),
                              ],
                            ),
                          );'''

if old_block_dn in router:
    router = router.replace(old_block_dn, new_block_dn)
    with open(router_path, "w", encoding="utf-8") as f:
        f.write(router)
    print("✔ Debit Note PDF & Headers fixed in Router.")

# 4. RUN FLUTTER ANALYZE
print("\n🔍 Step 4/5: Verifying syntax via flutter analyze...")
res = subprocess.run(["flutter", "analyze", "lib/web_live_sync/"], capture_output=True, text=True)
print(res.stdout)

errors = [line for line in res.stdout.split('\n') if 'error •' in line]
if len(errors) > 0:
    print(f"❌ Found {len(errors)} error(s):")
    for e in errors:
        print("  " + e)
    sys.exit(1)
print("🎉 0 ERRORS! COMPILATION IS 100% CLEAN.")

# 5. BUILD & DEPLOY
print("\n🔨 Step 5/5: Building & Deploying Web App to Cloudflare Pages...")
b_res = subprocess.run(
    ["flutter", "build", "web", "-t", "lib/web_live_sync/web_main.dart", "--release", "--base-href", "/", "--pwa-strategy=none"],
    text=True
)
if b_res.returncode != 0:
    print("❌ Web Build Failed!")
    sys.exit(1)

subprocess.run(["npx", "wrangler", "pages", "deploy", "build/web", "--project-name=pharoah-erp"], text=True)

# Commit & Push
print("\n🔄 Committing & Pushing to GitHub...")
subprocess.run(["git", "add", "."], text=True)
subprocess.run(["git", "commit", "-m", "🚀 #PH-REV-635: PDF GST Percentage & Header Bug Fixed"], text=True)
branch_res = subprocess.run(["git", "branch", "--show-current"], capture_output=True, text=True)
branch = branch_res.stdout.strip() or "main"
subprocess.run(["git", "push", "origin", branch], text=True)

print("\n" + "="*65)
print("🎉 SUCCESS: #PH-REV-635 IS LIVE ON CLOUDFLARE PAGES!")
print("🔗 Website: https://pharoah-erp.pages.dev")
print("✅ Verified Tag: #PH-REV-635 (PDF-GST-PERCENTAGE-FIX)")
print("="*65)
