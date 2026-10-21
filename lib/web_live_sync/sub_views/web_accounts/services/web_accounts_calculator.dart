// FILE: lib/web_live_sync/sub_views/web_accounts/services/web_accounts_calculator.dart
// Revision: #PH-REV-743 (ENTERPRISE-CASH-VS-CREDIT-LEDGER-ENGINE)

import '../../../../models.dart';
import '../../../web_models.dart';

/// 🏛️ WebAccountsCalculator
/// Decoupled, production-grade financial ledger & party balance calculation engine.
/// Adheres strictly to standard double-entry principles (Marg ERP / Tally Prime model)
/// where Cash Sales/Purchases are settled at point of sale without generating false debtor/creditor balances.
class WebAccountsCalculator {
  /// Computes true net party balance (Receivable Dr > 0, Payable Cr < 0).
  /// Cash sales & cash purchases do NOT create outstanding debtor/creditor debt.
  static double calculatePartyBalance({
    required Party party,
    required List<Sale> sales,
    required List<Purchase> purchases,
    required List<SaleReturn> saleReturns,
    required List<PurchaseReturn> purchaseReturns,
    required List<Voucher> vouchers,
  }) {
    double total = party.opBal;

    // 1. Sales: Only CREDIT sales increase receivable outstanding.
    // Cash sales are settled instantly at counter.
    for (var s in sales.where((s) =>
        (s.partyId == party.id || s.partyName.trim().toUpperCase() == party.name.trim().toUpperCase()) &&
        s.status == "Active")) {
      if (s.paymentMode.trim().toUpperCase() == "CREDIT") {
        total += s.totalAmount;
      }
    }

    // 2. Purchases: Only CREDIT purchases increase payable debt to distributor.
    for (var pur in purchases.where((pur) =>
        (pur.partyId == party.id || pur.distributorName.trim().toUpperCase() == party.name.trim().toUpperCase()))) {
      if (pur.paymentMode.trim().toUpperCase() == "CREDIT") {
        total -= pur.totalAmount;
      }
    }

    // 3. Sale Returns (Credit Notes) reduce customer receivable.
    for (var sr in saleReturns.where((r) =>
        r.partyName.trim().toUpperCase() == party.name.trim().toUpperCase() && r.status == "Active")) {
      total -= sr.totalAmount;
    }

    // 4. Purchase Returns (Debit Notes) reduce supplier payable.
    for (var pr in purchaseReturns.where((r) =>
        r.distributorName.trim().toUpperCase() == party.name.trim().toUpperCase() && r.status == "Active")) {
      total += pr.totalAmount;
    }

    // 5. Vouchers: Receipts (Customer paid) reduce Dr; Payments/Expenses increase Dr / reduce Cr.
    for (var v in vouchers.where((v) =>
        (v.partyId == party.id || v.partyName.trim().toUpperCase() == party.name.trim().toUpperCase()) &&
        v.status == "Active")) {
      final type = v.type.toUpperCase();
      if (type == "RECEIPT") {
        total -= v.amount;
      } else if (type == "PAYMENT" || type == "EXPENSE") {
        total += v.amount;
      }
    }

    return total;
  }

  /// Generates chronological party statement timeline with full transparent audit trail.
  /// Cash sales appear with clear Counter Cash Settlement so net effect is ₹0.00 while maintaining history.
  static List<Map<String, dynamic>> getPartyStatementData({
    required Party party,
    required DateTime fromDate,
    required DateTime toDate,
    required List<Sale> sales,
    required List<Purchase> purchases,
    required List<SaleReturn> saleReturns,
    required List<PurchaseReturn> purchaseReturns,
    required List<Voucher> vouchers,
  }) {
    final String pName = party.name.trim().toUpperCase();
    final String pId = party.id;

    List<Map<String, dynamic>> allTxns = [];

    // 1. Sales
    for (var s in sales.where((s) =>
        (s.partyId == pId || s.partyName.trim().toUpperCase() == pName) && s.status == "Active")) {
      final isCash = s.paymentMode.trim().toUpperCase() == "CASH";
      if (isCash) {
        // Tally / Marg ERP model: Show sale with counter cash settlement line
        allTxns.add({
          'date': s.date,
          'ref': s.billNo,
          'type': 'SALE (CASH)',
          'dr': s.totalAmount,
          'cr': 0.0,
          'particulars': 'Sale Invoice #${s.billNo} [CASH SALE]',
          'obj': s,
        });
        allTxns.add({
          'date': s.date,
          'ref': "SETTLE-${s.billNo}",
          'type': 'CASH SETTLEMENT',
          'dr': 0.0,
          'cr': s.totalAmount,
          'particulars': 'Immediate Cash Cleared at Counter #${s.billNo}',
          'obj': s,
        });
      } else {
        allTxns.add({
          'date': s.date,
          'ref': s.billNo,
          'type': 'SALE (CREDIT)',
          'dr': s.totalAmount,
          'cr': 0.0,
          'particulars': 'Sale Invoice #${s.billNo}',
          'obj': s,
        });
      }
    }

    // 2. Purchases
    for (var p in purchases.where((p) =>
        (p.partyId == pId || p.distributorName.trim().toUpperCase() == pName))) {
      final isCash = p.paymentMode.trim().toUpperCase() == "CASH";
      if (isCash) {
        allTxns.add({
          'date': p.date,
          'ref': p.billNo,
          'type': 'PURCHASE (CASH)',
          'dr': 0.0,
          'cr': p.totalAmount,
          'particulars': 'Purchase Inward #${p.billNo} [CASH PURCHASE]',
          'obj': p,
        });
        allTxns.add({
          'date': p.date,
          'ref': "SETTLE-${p.billNo}",
          'type': 'CASH SETTLEMENT',
          'dr': p.totalAmount,
          'cr': 0.0,
          'particulars': 'Immediate Cash Paid to Supplier #${p.billNo}',
          'obj': p,
        });
      } else {
        allTxns.add({
          'date': p.date,
          'ref': p.billNo,
          'type': 'PURCHASE (CREDIT)',
          'dr': 0.0,
          'cr': p.totalAmount,
          'particulars': 'Purchase Inward #${p.billNo}',
          'obj': p,
        });
      }
    }

    // 3. Sale Returns (Credit Notes)
    for (var sr in saleReturns.where((r) =>
        r.partyName.trim().toUpperCase() == pName && r.status == "Active")) {
      allTxns.add({
        'date': sr.date,
        'ref': sr.billNo,
        'type': 'CN',
        'dr': 0.0,
        'cr': sr.totalAmount,
        'particulars': 'Credit Note #${sr.billNo}',
        'obj': sr,
      });
    }

    // 4. Purchase Returns (Debit Notes)
    for (var pr in purchaseReturns.where((r) =>
        r.distributorName.trim().toUpperCase() == pName && r.status == "Active")) {
      allTxns.add({
        'date': pr.date,
        'ref': pr.billNo,
        'type': 'DN',
        'dr': pr.totalAmount,
        'cr': 0.0,
        'particulars': 'Debit Note #${pr.billNo}',
        'obj': pr,
      });
    }

    // 5. Vouchers
    for (var v in vouchers.where((v) =>
        (v.partyId == pId || v.partyName.trim().toUpperCase() == pName) && v.status == "Active")) {
      final isPay = v.type.toUpperCase() == "PAYMENT" || v.type.toUpperCase() == "EXPENSE";
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

    // Sort chronologically by date
    allTxns.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

    // Calculate opening balance before fromDate
    double runningBal = party.opBal;
    for (var item in allTxns) {
      DateTime dt = item['date'] as DateTime;
      if (dt.isBefore(fromDate)) {
        runningBal += (item['dr'] as double);
        runningBal -= (item['cr'] as double);
      }
    }

    List<Map<String, dynamic>> finalStatement = [];
    finalStatement.add({
      'date': fromDate,
      'ref': 'OP-BAL',
      'type': 'OPENING',
      'dr': runningBal >= 0 ? runningBal : 0.0,
      'cr': runningBal < 0 ? runningBal.abs() : 0.0,
      'balance': runningBal,
      'bal': runningBal,
      'particulars': 'Opening Balance B/F',
    });

    for (var item in allTxns) {
      DateTime dt = item['date'] as DateTime;
      if (!dt.isBefore(fromDate) && !dt.isAfter(toDate.add(const Duration(days: 1)))) {
        runningBal += (item['dr'] as double);
        runningBal -= (item['cr'] as double);
        item['balance'] = runningBal;
        item['bal'] = runningBal;
        finalStatement.add(item);
      }
    }

    return finalStatement;
  }

  /// Section 269ST Income Tax Compliance check:
  /// Verifies if cash transactions with a party exceed ₹2,00,000 on a single day.
  static bool isCashLimitExceeded({
    required String partyId,
    required double newAmount,
    required List<Voucher> vouchers,
  }) {
    DateTime today = DateTime.now();
    double todayTotal = vouchers
        .where((v) =>
            v.partyId == partyId &&
            v.paymentMode.toLowerCase() == "cash" &&
            v.date.day == today.day &&
            v.date.month == today.month &&
            v.date.year == today.year &&
            v.status == "Active")
        .fold(0.0, (sum, v) => sum + v.amount);
    return (todayTotal + newAmount) > 200000;
  }

  /// Returns unsettled credit bills for a party (used for Receipt / Payment bill-linking)
  static List<Map<String, dynamic>> getPendingBills({
    required String partyId,
    required bool isReceipt,
    required List<Sale> sales,
    required List<Purchase> purchases,
    required List<Voucher> vouchers,
  }) {
    List<Map<String, dynamic>> pending = [];
    DateTime now = DateTime.now();

    if (isReceipt) {
      for (var s in sales.where((s) =>
          (s.partyId == partyId || s.partyName == partyId) &&
          s.paymentMode == "CREDIT" &&
          s.status == "Active")) {
        bool alreadySettled = vouchers.any(
            (v) => v.linkedBillNumbers.contains(s.billNo) && v.status == "Active");
        if (!alreadySettled) {
          int days = now.difference(s.date).inDays;
          pending.add({
            'date': s.date,
            'billNo': s.billNo,
            'amount': s.totalAmount,
            'dueDays': days,
          });
        }
      }
    } else {
      for (var p in purchases.where((p) =>
          (p.partyId == partyId || p.distributorName == partyId) &&
          p.paymentMode == "CREDIT")) {
        bool alreadySettled = vouchers.any(
            (v) => v.linkedBillNumbers.contains(p.billNo) && v.status == "Active");
        if (!alreadySettled) {
          int days = now.difference(p.date).inDays;
          pending.add({
            'date': p.date,
            'billNo': p.billNo,
            'amount': p.totalAmount,
            'dueDays': days,
          });
        }
      }
    }

    pending.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
    return pending;
  }
}
