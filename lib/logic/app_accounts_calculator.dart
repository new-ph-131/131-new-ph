// FILE: lib/logic/app_accounts_calculator.dart
// Revision: #PH-REV-744 (APP-DOUBLE-ENTRY-ACCOUNTS-CALCULATOR)
import '../models.dart';
import '../finance/bank_transaction_model.dart';

/// 🏛️ AppAccountsCalculator
/// Decoupled, production-grade financial ledger & dual-leg accounting engine for Mobile App.
/// Adheres strictly to standard double-entry principles (Marg ERP / Tally Prime model):
/// 1. Cash Sales & Purchases settle at counter without creating false debtor/creditor debt.
/// 2. Credit Sales & Purchases post to Party Ledgers (Sundry Debtors / Creditors).
/// 3. Receipts & Payments update both Party Ledger and Cash/Bank Ledger (Dual-Leg).
/// 4. Contra vouchers update Cash and Bank accounts authoritatively.
class AppAccountsCalculator {
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
    final String pName = party.name.trim().toUpperCase();
    final String pId = party.id;

    // 1. Sales: Only CREDIT sales increase customer receivable outstanding.
    // Cash sales are settled instantly at counter without creating debtor balance.
    for (var s in sales.where((s) =>
        (s.partyId == pId || s.partyName.trim().toUpperCase() == pName) &&
        s.status == "Active")) {
      if (s.paymentMode.trim().toUpperCase() == "CREDIT") {
        total += s.totalAmount;
      }
    }

    // 2. Purchases: Only CREDIT purchases increase payable debt to distributor.
    for (var pur in purchases.where((pur) =>
        (pur.partyId == pId || pur.distributorName.trim().toUpperCase() == pName))) {
      if (pur.paymentMode.trim().toUpperCase() == "CREDIT") {
        total -= pur.totalAmount;
      }
    }

    // 3. Sale Returns (Credit Notes) reduce customer receivable.
    for (var sr in saleReturns.where((r) =>
        r.partyName.trim().toUpperCase() == pName && r.status == "Active")) {
      total -= sr.totalAmount;
    }

    // 4. Purchase Returns (Debit Notes) reduce supplier payable.
    for (var pr in purchaseReturns.where((r) =>
        r.distributorName.trim().toUpperCase() == pName && r.status == "Active")) {
      total += pr.totalAmount;
    }

    // 5. Vouchers: Receipts (Customer paid) reduce Dr; Payments/Expenses increase Dr / reduce Cr.
    for (var v in vouchers.where((v) =>
        (v.partyId == pId || v.partyName.trim().toUpperCase() == pName) &&
        v.status == "Active")) {
      final type = v.type.trim().toUpperCase();
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
      final isPay = v.type.trim().toUpperCase() == "PAYMENT" || v.type.trim().toUpperCase() == "EXPENSE";
      allTxns.add({
        'date': v.date,
        'ref': v.voucherNo,
        'type': v.type.trim().toUpperCase(),
        'dr': isPay ? v.amount : 0.0,
        'cr': isPay ? 0.0 : v.amount,
        'particulars': "${v.type.trim().toUpperCase()} (${v.paymentMode})",
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

  /// 💵 Calculates running Cash-in-Hand Balance (Cash in Counter Drawer).
  static double calculateCashInHandBalance({
    required List<Sale> sales,
    required List<Purchase> purchases,
    required List<Voucher> vouchers,
    double openingCash = 0.0,
  }) {
    double bal = openingCash;

    // 1. Inward from Cash Sales
    for (var s in sales.where((s) => s.status == "Active" && s.paymentMode.trim().toUpperCase() == "CASH")) {
      bal += s.totalAmount;
    }

    // 2. Outward for Cash Purchases
    for (var p in purchases.where((p) => p.paymentMode.trim().toUpperCase() == "CASH")) {
      bal -= p.totalAmount;
    }

    // 3. Vouchers
    for (var v in vouchers.where((v) => v.status == "Active")) {
      final type = v.type.trim().toUpperCase();
      final mode = v.paymentMode.trim().toUpperCase();
      final isCashMode = mode == "CASH";

      if (type == "RECEIPT" && isCashMode) {
        bal += v.amount;
      } else if ((type == "PAYMENT" || type == "EXPENSE") && isCashMode) {
        bal -= v.amount;
      } else if (type == "CONTRA") {
        final src = v.bankName.trim().toUpperCase();
        final dest = v.depositedIn.trim().toUpperCase();
        // If cash deposited into bank: Cash decreases
        if (src == "CASH" || src == "CASH IN HAND" || mode == "CASH") {
          bal -= v.amount;
        }
        // If cash withdrawn from bank: Cash increases
        if (dest == "CASH" || dest == "CASH IN HAND") {
          bal += v.amount;
        }
      }
    }

    return bal;
  }

  /// 📜 Full chronological Cash-in-Hand Register (Cash Book).
  static List<Map<String, dynamic>> getCashBookStatement({
    required DateTime fromDate,
    required DateTime toDate,
    required List<Sale> sales,
    required List<Purchase> purchases,
    required List<Voucher> vouchers,
    double openingCash = 0.0,
  }) {
    List<Map<String, dynamic>> allCashTxns = [];

    // 1. Cash Sales (Inward +)
    for (var s in sales.where((s) => s.status == "Active" && s.paymentMode.trim().toUpperCase() == "CASH")) {
      allCashTxns.add({
        'date': s.date,
        'ref': s.billNo,
        'particulars': s.partyName.isNotEmpty ? "Cash Sale: ${s.partyName}" : "Counter Cash Sale",
        'type': 'CASH SALE',
        'in': s.totalAmount,
        'out': 0.0,
      });
    }

    // 2. Cash Purchases (Outward -)
    for (var p in purchases.where((p) => p.paymentMode.trim().toUpperCase() == "CASH")) {
      allCashTxns.add({
        'date': p.date,
        'ref': p.billNo,
        'particulars': p.distributorName.isNotEmpty ? "Cash Pur: ${p.distributorName}" : "Cash Purchase",
        'type': 'CASH PURCHASE',
        'in': 0.0,
        'out': p.totalAmount,
      });
    }

    // 3. Vouchers
    for (var v in vouchers.where((v) => v.status == "Active")) {
      final type = v.type.trim().toUpperCase();
      final mode = v.paymentMode.trim().toUpperCase();
      final isCashMode = mode == "CASH";

      if (type == "RECEIPT" && isCashMode) {
        allCashTxns.add({
          'date': v.date,
          'ref': v.voucherNo,
          'particulars': "Receipt: ${v.partyName}",
          'type': 'RECEIPT',
          'in': v.amount,
          'out': 0.0,
        });
      } else if ((type == "PAYMENT" || type == "EXPENSE") && isCashMode) {
        allCashTxns.add({
          'date': v.date,
          'ref': v.voucherNo,
          'particulars': "${type}: ${v.partyName}",
          'type': type,
          'in': 0.0,
          'out': v.amount,
        });
      } else if (type == "CONTRA") {
        final src = v.bankName.trim().toUpperCase();
        final dest = v.depositedIn.trim().toUpperCase();
        if (src == "CASH" || src == "CASH IN HAND" || mode == "CASH") {
          allCashTxns.add({
            'date': v.date,
            'ref': v.voucherNo,
            'particulars': "Contra: Deposited into $dest",
            'type': 'CONTRA (DEPOSIT)',
            'in': 0.0,
            'out': v.amount,
          });
        }
        if (dest == "CASH" || dest == "CASH IN HAND") {
          allCashTxns.add({
            'date': v.date,
            'ref': v.voucherNo,
            'particulars': "Contra: Withdrawn from $src",
            'type': 'CONTRA (WITHDRAWAL)',
            'in': v.amount,
            'out': 0.0,
          });
        }
      }
    }

    allCashTxns.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

    // Calculate opening cash before fromDate
    double runningBal = openingCash;
    for (var item in allCashTxns) {
      DateTime dt = item['date'] as DateTime;
      if (dt.isBefore(fromDate)) {
        runningBal += (item['in'] as double);
        runningBal -= (item['out'] as double);
      }
    }

    List<Map<String, dynamic>> statement = [];
    statement.add({
      'date': fromDate,
      'ref': 'OP-BAL',
      'particulars': 'Opening Cash Balance B/F',
      'type': 'OPENING',
      'in': runningBal >= 0 ? runningBal : 0.0,
      'out': runningBal < 0 ? runningBal.abs() : 0.0,
      'balance': runningBal,
    });

    for (var item in allCashTxns) {
      DateTime dt = item['date'] as DateTime;
      if (!dt.isBefore(fromDate) && !dt.isAfter(toDate.add(const Duration(days: 1)))) {
        runningBal += (item['in'] as double);
        runningBal -= (item['out'] as double);
        item['balance'] = runningBal;
        statement.add(item);
      }
    }

    return statement;
  }

  /// 🏦 Generates complete Dual-Leg Bank Statement / Passbook for a given Bank Account.
  static List<BankTransaction> getBankBookStatement({
    required String bankName,
    required DateTime fromDate,
    required DateTime toDate,
    required List<Sale> sales,
    required List<Purchase> purchases,
    required List<Voucher> vouchers,
  }) {
    List<BankTransaction> list = [];
    final String bName = bankName.trim().toUpperCase();
    if (bName.isEmpty) return list;

    final bankModes = {'BANK', 'ONLINE', 'UPI', 'CHEQUE', 'CARD', 'NEFT', 'RTGS'};

    // 1. Direct Bank Sales (Inward +)
    for (var s in sales.where((s) => s.status == "Active")) {
      final mode = s.paymentMode.trim().toUpperCase();
      if (bankModes.contains(mode)) {
        if (!s.date.isBefore(fromDate) && !s.date.isAfter(toDate.add(const Duration(days: 1)))) {
          list.add(BankTransaction(
            id: s.id,
            date: s.date,
            particulars: s.partyName.isNotEmpty ? "Sale: ${s.partyName}" : "Direct Bank Sale",
            reference: "Bill #${s.billNo} ($mode)",
            amountIn: s.totalAmount,
            amountOut: 0.0,
            type: "SALE ($mode)",
          ));
        }
      }
    }

    // 2. Direct Bank Purchases (Outward -)
    for (var p in purchases) {
      final mode = p.paymentMode.trim().toUpperCase();
      if (bankModes.contains(mode)) {
        if (!p.date.isBefore(fromDate) && !p.date.isAfter(toDate.add(const Duration(days: 1)))) {
          list.add(BankTransaction(
            id: p.id,
            date: p.date,
            particulars: p.distributorName.isNotEmpty ? "Pur: ${p.distributorName}" : "Direct Bank Pur",
            reference: "Bill #${p.billNo} ($mode)",
            amountIn: 0.0,
            amountOut: p.totalAmount,
            type: "PURCHASE ($mode)",
          ));
        }
      }
    }

    // 3. Vouchers
    for (var v in vouchers.where((v) => v.status == "Active")) {
      if (v.date.isBefore(fromDate) || v.date.isAfter(toDate.add(const Duration(days: 1)))) {
        continue;
      }

      final type = v.type.trim().toUpperCase();
      final mode = v.paymentMode.trim().toUpperCase();
      final dep = v.depositedIn.trim().toUpperCase();
      final src = v.bankName.trim().toUpperCase();

      if (type == "RECEIPT") {
        if (dep == bName || (dep.isEmpty && bankModes.contains(mode))) {
          list.add(BankTransaction(
            id: v.id,
            date: v.date,
            particulars: "Receipt: ${v.partyName}",
            reference: "${v.voucherNo} (${v.paymentMode})",
            amountIn: v.amount,
            amountOut: 0.0,
            type: v.type,
          ));
        }
      } else if (type == "PAYMENT" || type == "EXPENSE") {
        if (dep == bName || src == bName || (dep.isEmpty && bankModes.contains(mode))) {
          list.add(BankTransaction(
            id: v.id,
            date: v.date,
            particulars: "${type}: ${v.partyName}",
            reference: "${v.voucherNo} (${v.paymentMode})",
            amountIn: 0.0,
            amountOut: v.amount,
            type: v.type,
          ));
        }
      } else if (type == "CONTRA") {
        // Cash deposit or Bank-to-Bank transfer INTO this bank
        if (dep == bName) {
          list.add(BankTransaction(
            id: v.id,
            date: v.date,
            particulars: "Contra Inward (from ${src.isNotEmpty ? src : 'Cash'})",
            reference: v.voucherNo,
            amountIn: v.amount,
            amountOut: 0.0,
            type: "CONTRA IN",
          ));
        }
        // Cash withdrawal or Bank-to-Bank transfer FROM this bank
        if (src == bName) {
          list.add(BankTransaction(
            id: v.id,
            date: v.date,
            particulars: "Contra Outward (to ${dep.isNotEmpty ? dep : 'Cash'})",
            reference: v.voucherNo,
            amountIn: 0.0,
            amountOut: v.amount,
            type: "CONTRA OUT",
          ));
        }
      }
    }

    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
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
