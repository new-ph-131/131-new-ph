import re

path = 'lib/web_live_sync/pharoah_web_manager.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add List<ShortageItem> shortages = []; if not present
if 'List<ShortageItem> shortages = [];' not in content:
    content = content.replace(
        'List<PurchaseReturn> purchaseReturns = [];',
        'List<PurchaseReturn> purchaseReturns = [];\n  List<ShortageItem> shortages = [];'
    )

# 2. Add calculatePartyBalance & getPartyStatementData if not present
if 'double calculatePartyBalance' not in content:
    ledger_methods = """
  // ===========================================================================
  // 📊 LEDGER STATEMENT & BALANCE ENGINE
  // ===========================================================================
  double calculatePartyBalance(Party p) {
    double total = p.opBal;
    for (var s in sales.where((s) => (s.partyId == p.id || s.partyName == p.name) && s.status == "Active")) {
      total += s.totalAmount;
    }
    for (var pur in purchases.where((pur) => (pur.partyId == p.id || pur.distributorName == p.name))) {
      total -= pur.totalAmount;
    }
    for (var sr in saleReturns.where((r) => r.partyName == p.name && r.status == "Active")) {
      total -= sr.totalAmount;
    }
    for (var pr in purchaseReturns.where((r) => r.distributorName == p.name && r.status == "Active")) {
      total += pr.totalAmount;
    }
    for (var v in vouchers.where((v) => (v.partyId == p.id || v.partyName == p.name) && v.status == "Active")) {
      if (v.type.toUpperCase() == "RECEIPT") total -= v.amount;
      if (v.type.toUpperCase() == "PAYMENT" || v.type.toUpperCase() == "EXPENSE") total += v.amount;
    }
    return total;
  }

  List<Map<String, dynamic>> getPartyStatementData({
    required String partyId,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    double runningBal = 0.0;
    String pName = "";
    Party? partyObj;

    try {
      partyObj = parties.firstWhere((element) => element.id == partyId || element.name == partyId);
      runningBal = partyObj.opBal;
      pName = partyObj.name;
    } catch (e) {
      return [];
    }

    List<Map<String, dynamic>> allTxns = [];

    for (var s in sales.where((s) => (s.partyId == partyId || s.partyName == pName) && s.status == "Active")) {
      allTxns.add({'date': s.date, 'ref': s.billNo, 'type': 'SALE', 'dr': s.totalAmount, 'cr': 0.0, 'particulars': 'Sale Invoice #${s.billNo}', 'obj': s});
    }
    for (var p in purchases.where((p) => (p.partyId == partyId || p.distributorName == pName))) {
      allTxns.add({'date': p.date, 'ref': p.billNo, 'type': 'PURCHASE', 'dr': 0.0, 'cr': p.totalAmount, 'particulars': 'Purchase Inward #${p.billNo}', 'obj': p});
    }
    for (var sr in saleReturns.where((r) => r.partyName == pName && r.status == "Active")) {
      allTxns.add({'date': sr.date, 'ref': sr.billNo, 'type': 'CN', 'dr': 0.0, 'cr': sr.totalAmount, 'particulars': 'Credit Note #${sr.billNo}', 'obj': sr});
    }
    for (var pr in purchaseReturns.where((r) => r.distributorName == pName && r.status == "Active")) {
      allTxns.add({'date': pr.date, 'ref': pr.billNo, 'type': 'DN', 'dr': pr.totalAmount, 'cr': 0.0, 'particulars': 'Debit Note #${pr.billNo}', 'obj': pr});
    }
    for (var v in vouchers.where((v) => (v.partyId == partyId || v.partyName == pName) && v.status == "Active")) {
      bool isPay = v.type.toUpperCase() == "PAYMENT" || v.type.toUpperCase() == "EXPENSE";
      allTxns.add({
        'date': v.date,
        'ref': v.voucherNo,
        'type': v.type.toUpperCase(),
        'dr': isPay ? v.amount : 0.0,
        'cr': isPay ? 0.0 : v.amount,
        'particulars': "${v.type.toUpperCase()} (${v.paymentMode})",
        'obj': v,
      });
    }

    allTxns.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

    List<Map<String, dynamic>> filteredLedger = [];
    double periodOpBal = runningBal;

    DateTime fStart = DateTime(fromDate.year, fromDate.month, fromDate.day);
    DateTime tEnd = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);

    for (var txn in allTxns) {
      DateTime tDate = txn['date'] as DateTime;
      if (tDate.isBefore(fStart)) {
        periodOpBal += ((txn['dr'] as double) - (txn['cr'] as double));
      } else if (!tDate.isAfter(tEnd)) {
        filteredLedger.add(txn);
      }
    }

    double currentRunning = periodOpBal;
    List<Map<String, dynamic>> finalResult = [];

    finalResult.add({
      'date': fromDate,
      'ref': 'B/F',
      'type': 'OPENING',
      'dr': 0.0,
      'cr': 0.0,
      'bal': periodOpBal,
      'particulars': 'Opening Balance B/F',
    });

    for (var txn in filteredLedger) {
      currentRunning += ((txn['dr'] as double) - (txn['cr'] as double));
      txn['bal'] = currentRunning;
      finalResult.add(txn);
    }

    return finalResult;
  }
"""
    last_brace = content.rfind('}')
    if last_brace != -1:
        content = content[:last_brace] + ledger_methods + "\n}\n"

# 3. Add Shortage methods if not present
if 'double calculateAvgMonthlySale' not in content:
    shortage_methods = """
  // ===========================================================================
  // 📈 SHORTAGE LOGIC & 1.5x AUTO-SCAN
  // ===========================================================================
  double calculateAvgMonthlySale(String mid) {
    DateTime thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    double grossSaleQty = 0.0;
    double returnedQty = 0.0;

    for (var s in sales.where((s) => s.status == "Active" && s.date.isAfter(thirtyDaysAgo))) {
      for (var item in s.items.where((it) => it.medicineID == mid)) {
        grossSaleQty += (item.qty + item.freeQty);
      }
    }

    for (var r in saleReturns.where((r) => r.status == "Active" && r.date.isAfter(thirtyDaysAgo))) {
      for (var item in r.items.where((it) => it.medicineID == mid && !it.isBreakage)) {
        returnedQty += (item.qty + item.freeQty);
      }
    }

    double netMonthlySale = grossSaleQty - returnedQty;
    return netMonthlySale < 0 ? 0.0 : netMonthlySale;
  }

  void runAutoShortageScan() {
    shortages.removeWhere((s) => s.source == "Auto");
    for (var m in medicines) {
      double avg = calculateAvgMonthlySale(m.id);
      double requiredStock = avg * 1.5;
      if (m.stock < requiredStock && requiredStock > 0) {
        String cName = "N/A";
        try {
          cName = companies.firstWhere((c) => c.id == m.companyId).name;
        } catch (_) {
          cName = m.companyId.isNotEmpty ? m.companyId : "N/A";
        }

        shortages.add(ShortageItem(
          id: "auto_${m.id}",
          medicineId: m.id,
          medicineName: m.name,
          companyName: cName,
          qtyRequired: requiredStock - m.stock,
          currentStock: m.stock,
          date: DateTime.now(),
          source: "Auto",
        ));
      }
    }
    notifyListeners();
    _autoSyncService.triggerAutoSync();
  }

  void addManualShortage({required Medicine med, required double qty, String cust = ""}) {
    String cName = "N/A";
    try {
      cName = companies.firstWhere((c) => c.id == med.companyId).name;
    } catch (_) {
      cName = med.companyId.isNotEmpty ? med.companyId : "N/A";
    }

    shortages.add(ShortageItem(
      id: "MAN-${DateTime.now().millisecondsSinceEpoch}",
      medicineId: med.id,
      medicineName: med.name,
      companyName: cName,
      qtyRequired: qty,
      currentStock: med.stock,
      date: DateTime.now(),
      customerName: cust,
      source: "Manual",
    ));
    notifyListeners();
    _autoSyncService.triggerAutoSync();
  }

  void deleteShortage(String id) {
    shortages.removeWhere((s) => s.id == id);
    notifyListeners();
    _autoSyncService.triggerAutoSync();
  }
"""
    last_brace = content.rfind('}')
    if last_brace != -1:
        content = content[:last_brace] + shortage_methods + "\n}\n"

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print('✔ Perfect injection completed in pharoah_web_manager.dart')
