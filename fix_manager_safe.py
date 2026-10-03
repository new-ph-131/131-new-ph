import sys

path = 'lib/web_live_sync/pharoah_web_manager.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

if 'double calculatePartyBalance' in content:
    print('✔ calculatePartyBalance already exists.')
    sys.exit(0)

methods_to_add = """
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
        'particulars': f"{v.type.toUpperCase()} ({v.paymentMode})",
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

last_brace_idx = content.rfind('}')
if last_brace_idx != -1:
    updated = content[:last_brace_idx] + methods_to_add + "\n}\n"
    with open(path, 'w', encoding='utf-8') as f:
        f.write(updated)
    print('✔ Successfully injected ledger methods cleanly via Python rfind.')
else:
    print('❌ Closing brace not found.')
