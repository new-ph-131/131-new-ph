// FILE: lib/web_live_sync/sub_views/web_accounts/services/web_accounts_calculator.dart
// Revision: #PH-REV-746 (STANDARD-ERP-LEDGER-FLOW-AND-DUAL-ENTRY-CASH-BANK)
import '../../../../models.dart';
import '../../../web_models.dart';

/// 🏛️ WebAccountsCalculator
/// Production-grade enterprise financial ledger & party balance calculation engine.
/// Adheres strictly to standard double-entry principles (Marg ERP / Tally Prime model):
/// 1. Same-Day Entry Ordering: Invoices first, immediate settlements second, returns third, payments/receipts fourth.
/// 2. Cash Sales/Purchases settled at point of sale without creating debtor/creditor debt.
/// 3. Complete Dual-Leg Double Entry for Cash-in-Hand and Bank Account ledgers.
/// 4. Full running balance audit trail with proper opening balances.
class WebAccountsCalculator {
  /// Standard Marg ERP / Tally Priority ranking for transactions on the same calendar date:
  /// 0: Opening Balance
  /// 1: Invoices / Primary Charges (Sales, Purchases)
  /// 2: Immediate Counter Cash Settlements
  /// 3: Returns / Notes (Credit Notes, Debit Notes)
  /// 4: Financial Vouchers (Receipts, Payments, Expenses, Contras)
  /// 5: Miscellaneous
  static int getTransactionTypePriority(String type) {
    final t = type.trim().toUpperCase();
    if (t == 'OPENING' || t.startsWith('OP-')) return 0;
    if (t.startsWith('SALE') || t.startsWith('PURCHASE')) {
      if (t.contains('RETURN')) return 3;
      return 1;
    }
    if (t.contains('CASH SETTLEMENT') || t.contains('SETTLE-')) return 2;
    if (t.contains('CN') || t.contains('DN') || t.contains('CREDIT NOTE') || t.contains('DEBIT NOTE') || t.contains('RETURN')) return 3;
    if (t.startsWith('RECEIPT') || t.startsWith('PAYMENT') || t.startsWith('EXPENSE') || t.startsWith('CONTRA')) return 4;
    return 5;
  }

  /// Sorts ledger entries using canonical ERP hierarchy:
  /// Calendar Date -> Type Priority (Sale before Receipt) -> Exact Timestamp -> Reference ID
  static void sortTransactionsMargOrder(List<Map<String, dynamic>> txns) {
    txns.sort((a, b) {
      final dtA = a['date'] as DateTime;
      final dtB = b['date'] as DateTime;
      final dayA = DateTime(dtA.year, dtA.month, dtA.day);
      final dayB = DateTime(dtB.year, dtB.month, dtB.day);
      final dayCompare = dayA.compareTo(dayB);
      if (dayCompare != 0) return dayCompare;

      final prioA = getTransactionTypePriority((a['type'] ?? '').toString());
      final prioB = getTransactionTypePriority((b['type'] ?? '').toString());
      if (prioA != prioB) return prioA.compareTo(prioB);

      final exactCompare = dtA.compareTo(dtB);
      if (exactCompare != 0) return exactCompare;

      final refA = (a['ref'] ?? '').toString();
      final refB = (b['ref'] ?? '').toString();
      return refA.compareTo(refB);
    });
  }

  /// Computes true net party balance (Receivable Dr > 0, Payable Cr < 0).
  /// For Cash Account: Returns live Cash-in-Hand.
  /// For Bank Accounts: Returns live Bank Balance.
  /// For Sundry Debtors/Creditors: Credit sales/purchases and settlement vouchers only.
  static double calculatePartyBalance({
    required Party party,
    required List<Sale> sales,
    required List<Purchase> purchases,
    required List<SaleReturn> saleReturns,
    required List<PurchaseReturn> purchaseReturns,
    required List<Voucher> vouchers,
  }) {
    final String pName = party.name.trim().toUpperCase();
    final String pGroup = party.group.trim().toLowerCase();

    // 💵 CASE 1: CASH IN HAND LEDGER
    if (pName == 'CASH' || pName == 'CASH IN HAND' || pGroup == 'cash in hand' || party.id == 'cash') {
      double cashBal = party.opBal;
      // Inward: Cash Sales
      for (var s in sales.where((s) => s.isDeleted != 1 && (s.status.isEmpty || s.status == 'Active') && s.paymentMode.trim().toUpperCase() == 'CASH')) {
        cashBal += s.totalAmount;
      }
      // Outward: Cash Purchases
      for (var p in purchases.where((p) => p.isDeleted != 1 && p.paymentMode.trim().toUpperCase() == 'CASH')) {
        cashBal -= p.totalAmount;
      }
      // Vouchers: Receipts, Payments, Contras
      for (var v in vouchers.where((v) => v.isDeleted != 1 && v.status == 'Active')) {
        final type = v.type.trim().toUpperCase();
        if (v.chequeInstruments.isNotEmpty && (type == 'RECEIPT' || type == 'PAYMENT' || type == 'EXPENSE')) {
          for (var inst in v.chequeInstruments) {
            String imode = (inst['paymentMode'] ?? '').toString().trim().toUpperCase();
            String idep = (inst['depositedIn'] ?? '').toString().trim().toUpperCase();
            if (imode == 'CASH' || idep == 'CASH' || idep == 'CASH IN HAND') {
              double iamt = (inst['amount'] as num?)?.toDouble() ?? 0.0;
              if (type == 'RECEIPT') cashBal += iamt;
              else cashBal -= iamt;
            }
          }
          continue;
        }
        final mode = v.paymentMode.trim().toUpperCase();
        final dep = v.depositedIn.trim().toUpperCase();
        final src = v.bankName.trim().toUpperCase();
        final isCash = mode == 'CASH' || dep == 'CASH' || dep == 'CASH IN HAND';

        if (type == 'RECEIPT' && isCash) {
          cashBal += v.amount;
        } else if ((type == 'PAYMENT' || type == 'EXPENSE') && isCash) {
          cashBal -= v.amount;
        } else if (type == 'CONTRA') {
          if (src == 'CASH' || src == 'CASH IN HAND' || mode == 'CASH') {
            cashBal -= v.amount; // Cash deposited into bank
          }
          if (dep == 'CASH' || dep == 'CASH IN HAND') {
            cashBal += v.amount; // Cash withdrawn from bank
          }
        }
      }
      return cashBal;
    }

    // 🏦 CASE 2: BANK ACCOUNTS
    if (pGroup == 'bank accounts' || pGroup == 'bank') {
      double bankBal = party.opBal;
      final bankModes = {'BANK', 'ONLINE', 'UPI', 'CHEQUE', 'CARD', 'NEFT', 'RTGS'};

      for (var v in vouchers.where((v) => v.isDeleted != 1 && v.status == 'Active')) {
        final type = v.type.trim().toUpperCase();
        if (v.chequeInstruments.isNotEmpty && (type == 'RECEIPT' || type == 'PAYMENT' || type == 'EXPENSE')) {
          for (var inst in v.chequeInstruments) {
            String idep = (inst['depositedIn'] ?? inst['bankName'] ?? '').toString().trim().toUpperCase();
            if (idep == pName) {
              double iamt = (inst['amount'] as num?)?.toDouble() ?? 0.0;
              if (type == 'RECEIPT') bankBal += iamt;
              else bankBal -= iamt;
            }
          }
          continue;
        }
        final mode = v.paymentMode.trim().toUpperCase();
        final dep = v.depositedIn.trim().toUpperCase();
        final src = v.bankName.trim().toUpperCase();
        final isThisBankDep = dep == pName;
        final isThisBankSrc = src == pName;

        if (type == 'RECEIPT' && (isThisBankDep || (dep.isEmpty && bankModes.contains(mode)))) {
          bankBal += v.amount;
        } else if ((type == 'PAYMENT' || type == 'EXPENSE') && (isThisBankSrc || isThisBankDep || (dep.isEmpty && bankModes.contains(mode)))) {
          bankBal -= v.amount;
        } else if (type == 'CONTRA') {
          if (isThisBankDep) bankBal += v.amount; // Inward deposit
          if (isThisBankSrc) bankBal -= v.amount; // Outward withdrawal
        }
      }
      for (var s in sales.where((s) => s.isDeleted != 1 && (s.status.isEmpty || s.status == 'Active') && bankModes.contains(s.paymentMode.trim().toUpperCase()))) {
        bankBal += s.totalAmount;
      }
      for (var p in purchases.where((p) => p.isDeleted != 1 && bankModes.contains(p.paymentMode.trim().toUpperCase()))) {
        bankBal -= p.totalAmount;
      }
      return bankBal;
    }

    // 👥 CASE 3: SUNDRY DEBTORS & CREDITORS
    double total = party.opBal;
    final String pId = party.id;

    for (var s in sales.where((s) =>
        s.isDeleted != 1 &&
        (s.partyId == pId || s.partyName.trim().toUpperCase() == pName) &&
        (s.status.isEmpty || s.status == 'Active'))) {
      if (s.paymentMode.trim().toUpperCase() == 'CREDIT') {
        total += s.totalAmount;
      }
    }
    for (var pur in purchases.where((pur) =>
        pur.isDeleted != 1 &&
        (pur.partyId == pId || pur.distributorName.trim().toUpperCase() == pName))) {
      if (pur.paymentMode.trim().toUpperCase() == 'CREDIT') {
        total -= pur.totalAmount;
      }
    }
    for (var sr in saleReturns.where((r) =>
        r.isDeleted != 1 &&
        r.partyName.trim().toUpperCase() == pName &&
        (r.status.isEmpty || r.status == 'Active'))) {
      total -= sr.totalAmount;
    }
    for (var pr in purchaseReturns.where((r) =>
        r.isDeleted != 1 &&
        r.distributorName.trim().toUpperCase() == pName &&
        (r.status.isEmpty || r.status == 'Active'))) {
      total += pr.totalAmount;
    }
    for (var v in vouchers.where((v) =>
        v.isDeleted != 1 &&
        (v.partyId == pId || v.partyName.trim().toUpperCase() == pName) &&
        v.status == 'Active')) {
      final type = v.type.trim().toUpperCase();
      if (type == 'RECEIPT') {
        total -= v.amount;
      } else if (type == 'PAYMENT' || type == 'EXPENSE') {
        total += v.amount;
      }
    }
    return total;
  }

  /// Generates chronological party statement timeline with full transparent audit trail.
  /// Enforces same-day Marg ERP priority and dual-sided double entry reflection.
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
    final String pGroup = party.group.trim().toLowerCase();
    List<Map<String, dynamic>> allTxns = [];

    // 💵 1. CASH IN HAND STATEMENT
    if (pName == 'CASH' || pName == 'CASH IN HAND' || pGroup == 'cash in hand' || pId == 'cash') {
      // Cash Sales (Dr Inward)
      for (var s in sales.where((s) => s.isDeleted != 1 && (s.status.isEmpty || s.status == 'Active') && s.paymentMode.trim().toUpperCase() == 'CASH')) {
        allTxns.add({
          'date': s.date,
          'ref': s.billNo,
          'type': 'SALE (CASH)',
          'dr': s.totalAmount,
          'cr': 0.0,
          'particulars': s.partyName.isNotEmpty ? "Cash Sale: ${s.partyName}" : "Counter Cash Sale",
          'obj': s,
        });
      }
      // Cash Purchases (Cr Outward)
      for (var p in purchases.where((p) => p.isDeleted != 1 && p.paymentMode.trim().toUpperCase() == 'CASH')) {
        allTxns.add({
          'date': p.date,
          'ref': p.billNo,
          'type': 'PURCHASE (CASH)',
          'dr': 0.0,
          'cr': p.totalAmount,
          'particulars': p.distributorName.isNotEmpty ? "Cash Pur: ${p.distributorName}" : "Cash Purchase",
          'obj': p,
        });
      }
      // Cash Vouchers
      for (var v in vouchers.where((v) => v.isDeleted != 1 && v.status == 'Active')) {
        final type = v.type.trim().toUpperCase();
        final mode = v.paymentMode.trim().toUpperCase();
        final dep = v.depositedIn.trim().toUpperCase();
        final src = v.bankName.trim().toUpperCase();
        final isCash = mode == 'CASH' || dep == 'CASH' || dep == 'CASH IN HAND';

        if (type == 'RECEIPT' && isCash) {
          allTxns.add({
            'date': v.date,
            'ref': v.voucherNo,
            'type': 'RECEIPT',
            'dr': v.amount,
            'cr': 0.0,
            'particulars': "Receipt: ${v.partyName}",
            'obj': v,
          });
        } else if ((type == 'PAYMENT' || type == 'EXPENSE') && isCash) {
          allTxns.add({
            'date': v.date,
            'ref': v.voucherNo,
            'type': type,
            'dr': 0.0,
            'cr': v.amount,
            'particulars': "${type}: ${v.partyName}",
            'obj': v,
          });
        } else if (type == 'CONTRA') {
          if (src == 'CASH' || src == 'CASH IN HAND' || mode == 'CASH') {
            allTxns.add({
              'date': v.date,
              'ref': v.voucherNo,
              'type': 'CONTRA',
              'dr': 0.0,
              'cr': v.amount,
              'particulars': "Contra: Cash Deposited into ${v.depositedIn.isNotEmpty ? v.depositedIn : 'Bank'}",
              'obj': v,
            });
          }
          if (dep == 'CASH' || dep == 'CASH IN HAND') {
            allTxns.add({
              'date': v.date,
              'ref': v.voucherNo,
              'type': 'CONTRA',
              'dr': v.amount,
              'cr': 0.0,
              'particulars': "Contra: Cash Withdrawn from ${v.bankName.isNotEmpty ? v.bankName : 'Bank'}",
              'obj': v,
            });
          }
        }
      }
    }
    // 🏦 2. BANK ACCOUNT STATEMENT
    else if (pGroup == 'bank accounts' || pGroup == 'bank') {
      final bankModes = {'BANK', 'ONLINE', 'UPI', 'CHEQUE', 'CARD', 'NEFT', 'RTGS'};

      for (var v in vouchers.where((v) => v.isDeleted != 1 && v.status == 'Active')) {
        final type = v.type.trim().toUpperCase();
        if (v.chequeInstruments.isNotEmpty && (type == 'RECEIPT' || type == 'PAYMENT' || type == 'EXPENSE')) {
          for (var inst in v.chequeInstruments) {
            String idep = (inst['depositedIn'] ?? inst['bankName'] ?? '').toString().trim().toUpperCase();
            if (idep == pName) {
              double iamt = (inst['amount'] as num?)?.toDouble() ?? 0.0;
              String ichq = inst['chequeNo']?.toString() ?? '';
              String ibill = inst['billNo']?.toString() ?? '';
              allTxns.add({
                'date': v.date,
                'ref': v.voucherNo,
                'type': type,
                'dr': type == 'RECEIPT' ? iamt : 0.0,
                'cr': type == 'RECEIPT' ? 0.0 : iamt,
                'particulars': "${type == 'RECEIPT' ? 'Receipt' : type}: ${v.partyName}${ibill.isNotEmpty ? ' (Agst ' + ibill + ')' : ''}${ichq.isNotEmpty ? ' [Chq: ' + ichq + ']' : ''}",
                'obj': v,
              });
            }
          }
          continue;
        }
        final mode = v.paymentMode.trim().toUpperCase();
        final dep = v.depositedIn.trim().toUpperCase();
        final src = v.bankName.trim().toUpperCase();
        final isThisBankDep = dep == pName;
        final isThisBankSrc = src == pName;

        if (type == 'RECEIPT' && (isThisBankDep || (dep.isEmpty && bankModes.contains(mode)))) {
          allTxns.add({
            'date': v.date,
            'ref': v.voucherNo,
            'type': 'RECEIPT',
            'dr': v.amount,
            'cr': 0.0,
            'particulars': "Receipt: ${v.partyName}${v.chequeNo.isNotEmpty ? ' [Chq: ' + v.chequeNo + ']' : ''}",
            'obj': v,
          });
        } else if ((type == 'PAYMENT' || type == 'EXPENSE') && (isThisBankSrc || isThisBankDep || (dep.isEmpty && bankModes.contains(mode)))) {
          allTxns.add({
            'date': v.date,
            'ref': v.voucherNo,
            'type': type,
            'dr': 0.0,
            'cr': v.amount,
            'particulars': "${type}: ${v.partyName}${v.chequeNo.isNotEmpty ? ' [Chq: ' + v.chequeNo + ']' : ''}",
            'obj': v,
          });
        } else if (type == 'CONTRA') {
          if (isThisBankDep) {
            allTxns.add({
              'date': v.date,
              'ref': v.voucherNo,
              'type': 'CONTRA',
              'dr': v.amount,
              'cr': 0.0,
              'particulars': "Contra: Deposit from ${v.bankName.isNotEmpty ? v.bankName : 'Cash'}",
              'obj': v,
            });
          }
          if (isThisBankSrc) {
            allTxns.add({
              'date': v.date,
              'ref': v.voucherNo,
              'type': 'CONTRA',
              'dr': 0.0,
              'cr': v.amount,
              'particulars': "Contra: Withdrawal to ${v.depositedIn.isNotEmpty ? v.depositedIn : 'Cash'}",
              'obj': v,
            });
          }
        }
      }
      for (var s in sales.where((s) => s.isDeleted != 1 && (s.status.isEmpty || s.status == 'Active') && bankModes.contains(s.paymentMode.trim().toUpperCase()))) {
        allTxns.add({
          'date': s.date,
          'ref': s.billNo,
          'type': "SALE (${s.paymentMode.toUpperCase()})",
          'dr': s.totalAmount,
          'cr': 0.0,
          'particulars': "Direct Bank Sale: ${s.partyName}",
          'obj': s,
        });
      }
      for (var p in purchases.where((p) => p.isDeleted != 1 && bankModes.contains(p.paymentMode.trim().toUpperCase()))) {
        allTxns.add({
          'date': p.date,
          'ref': p.billNo,
          'type': "PURCHASE (${p.paymentMode.toUpperCase()})",
          'dr': 0.0,
          'cr': p.totalAmount,
          'particulars': "Direct Bank Pur: ${p.distributorName}",
          'obj': p,
        });
      }
    }
    // 👥 3. STANDARD SUNDRY DEBTOR / CREDITOR STATEMENT
    else {
      // Sales
      for (var s in sales.where((s) =>
          s.isDeleted != 1 &&
          (s.partyId == pId || s.partyName.trim().toUpperCase() == pName) &&
          (s.status.isEmpty || s.status == 'Active'))) {
        final modeUp = s.paymentMode.trim().toUpperCase();
        final isImmediatePaid = modeUp.isNotEmpty && modeUp != 'CREDIT';
        if (isImmediatePaid) {
          allTxns.add({
            'date': s.date,
            'ref': s.billNo,
            'type': 'SALE ($modeUp)',
            'dr': s.totalAmount,
            'cr': 0.0,
            'particulars': "Sale Invoice #${s.billNo} [$modeUp SALE]",
            'obj': s,
          });
          allTxns.add({
            'date': s.date,
            'ref': "SETTLE-${s.billNo}",
            'type': 'CASH SETTLEMENT',
            'dr': 0.0,
            'cr': s.totalAmount,
            'particulars': "Immediate $modeUp Cleared at Counter #${s.billNo}",
            'obj': s,
          });
        } else {
          allTxns.add({
            'date': s.date,
            'ref': s.billNo,
            'type': 'SALE (CREDIT)',
            'dr': s.totalAmount,
            'cr': 0.0,
            'particulars': "Sale Invoice #${s.billNo}",
            'obj': s,
          });
        }
      }

      // Purchases
      for (var p in purchases.where((p) =>
          p.isDeleted != 1 &&
          (p.partyId == pId || p.distributorName.trim().toUpperCase() == pName))) {
        final modeUp = p.paymentMode.trim().toUpperCase();
        final isImmediatePaid = modeUp.isNotEmpty && modeUp != 'CREDIT';
        if (isImmediatePaid) {
          allTxns.add({
            'date': p.date,
            'ref': p.billNo,
            'type': 'PURCHASE ($modeUp)',
            'dr': 0.0,
            'cr': p.totalAmount,
            'particulars': "Purchase Inward #${p.billNo} [$modeUp PURCHASE]",
            'obj': p,
          });
          allTxns.add({
            'date': p.date,
            'ref': "SETTLE-${p.billNo}",
            'type': 'CASH SETTLEMENT',
            'dr': p.totalAmount,
            'cr': 0.0,
            'particulars': "Immediate $modeUp Paid to Supplier #${p.billNo}",
            'obj': p,
          });
        } else {
          allTxns.add({
            'date': p.date,
            'ref': p.billNo,
            'type': 'PURCHASE (CREDIT)',
            'dr': 0.0,
            'cr': p.totalAmount,
            'particulars': "Purchase Inward #${p.billNo}",
            'obj': p,
          });
        }
      }

      // Returns
      for (var sr in saleReturns.where((r) =>
          r.isDeleted != 1 &&
          r.partyName.trim().toUpperCase() == pName &&
          (r.status.isEmpty || r.status == 'Active'))) {
        allTxns.add({
          'date': sr.date,
          'ref': sr.billNo,
          'type': 'CN',
          'dr': 0.0,
          'cr': sr.totalAmount,
          'particulars': "Credit Note #${sr.billNo}",
          'obj': sr,
        });
      }
      for (var pr in purchaseReturns.where((r) =>
          r.isDeleted != 1 &&
          r.distributorName.trim().toUpperCase() == pName &&
          (r.status.isEmpty || r.status == 'Active'))) {
        allTxns.add({
          'date': pr.date,
          'ref': pr.billNo,
          'type': 'DN',
          'dr': pr.totalAmount,
          'cr': 0.0,
          'particulars': "Debit Note #${pr.billNo}",
          'obj': pr,
        });
      }

      // Vouchers
      for (var v in vouchers.where((v) =>
          v.isDeleted != 1 &&
          (v.partyId == pId || v.partyName.trim().toUpperCase() == pName) &&
          v.status == 'Active')) {
        final vTypeUp = v.type.trim().toUpperCase();
        final isPay = vTypeUp == 'PAYMENT' || vTypeUp == 'EXPENSE';
        allTxns.add({
          'date': v.date,
          'ref': v.voucherNo,
          'type': vTypeUp,
          'dr': isPay ? v.amount : 0.0,
          'cr': isPay ? 0.0 : v.amount,
          'particulars': "$vTypeUp (${v.paymentMode})",
          'obj': v,
        });
      }
    }

    // 🏆 Sort using Marg ERP / Standard ERP entry priority matrix
    sortTransactionsMargOrder(allTxns);

    // Calculate opening balance before fromDate
    final DateTime startOfFromDate = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final DateTime endOfToDate = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59, 999);
    double runningBal = party.opBal;
    for (var item in allTxns) {
      DateTime dt = item['date'] as DateTime;
      if (dt.isBefore(startOfFromDate)) {
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
      if (!dt.isBefore(startOfFromDate) && !dt.isAfter(endOfToDate)) {
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
            v.paymentMode.toLowerCase() == 'cash' &&
            v.date.day == today.day &&
            v.date.month == today.month &&
            v.date.year == today.year &&
            v.isDeleted != 1 && v.status == 'Active')
        .fold(0.0, (sum, v) => sum + v.amount);
    return (todayTotal + newAmount) > 200000;
  }

  /// Returns unsettled and partially settled credit bills for a party
  /// Follows Marg ERP 9+ / Tally Agst Ref bill-by-bill dynamic allocation:
  /// - Excludes `excludeVoucherId` when modifying/auditing so currently allocated amounts do not hide bills.
  /// - Supports partial settlements (e.g. ₹9 paid on ₹10 leaves ₹1 pending).
  /// - Automatically un-settles bills when vouchers are modified to a lower amount or deleted/cancelled.
  static List<Map<String, dynamic>> getPendingBills({
    required String partyId,
    required bool isReceipt,
    required List<Sale> sales,
    required List<Purchase> purchases,
    required List<Voucher> vouchers,
    String? excludeVoucherId,
    List<Party> parties = const [],
    List<Map<String, dynamic>> carriedPendingInvoices = const [],
  }) {
    List<Map<String, dynamic>> pending = [];
    DateTime now = DateTime.now();
    final String cleanPartyId = partyId.trim();
    String partyNameUpper = cleanPartyId.toUpperCase();
    for (final p in parties) {
      if (p.id.trim() == cleanPartyId || p.name.trim().toUpperCase() == partyNameUpper) {
        partyNameUpper = p.name.trim().toUpperCase();
        break;
      }
    }

    bool matchesParty(String recPartyId, String recPartyName) {
      if (cleanPartyId.isNotEmpty && recPartyId.trim() == cleanPartyId) return true;
      final rNameUp = recPartyName.trim().toUpperCase();
      return partyNameUpper.isNotEmpty && rNameUp == partyNameUpper;
    }

    final activeVouchers = vouchers.where((v) {
      if (v.status != 'Active' || v.isDeleted != 0) return false;
      if (!matchesParty(v.partyId, v.partyName)) return false;
      if (excludeVoucherId != null &&
          excludeVoucherId.isNotEmpty &&
          (v.id == excludeVoucherId || v.voucherNo == excludeVoucherId)) {
        return false;
      }
      return true;
    }).toList();

    final Set<String> seenBills = {};

    if (isReceipt) {
      for (var s in sales.where((s) =>
          s.isDeleted != 1 &&
          matchesParty(s.partyId, s.partyName) &&
          s.paymentMode.trim().toUpperCase() == 'CREDIT' &&
          (s.status.isEmpty || s.status == 'Active'))) {
        final bKey = s.billNo.trim().toUpperCase();
        if (bKey.isNotEmpty) seenBills.add(bKey);
        double billTotal = s.totalAmount;
        double totalSettled = 0.0;

        for (var v in activeVouchers) {
          totalSettled += v.getAllocatedAmount(s.billNo);
        }

        if (totalSettled > billTotal) totalSettled = billTotal;
        double remainingDue = billTotal - totalSettled;
        remainingDue = double.parse(remainingDue.toStringAsFixed(2));

        if (remainingDue > 0.01) {
          int days = now.difference(s.date).inDays;
          pending.add({
            'date': s.date,
            'billNo': s.billNo,
            'amount': remainingDue,
            'totalAmount': billTotal,
            'paidAmount': totalSettled,
            'dueDays': days,
            'status': totalSettled > 0.01 ? 'PARTIAL' : 'UNSETTLED',
          });
        }
      }
    } else {
      for (var p in purchases.where((p) =>
          p.isDeleted != 1 &&
          matchesParty(p.partyId, p.distributorName) &&
          p.paymentMode.trim().toUpperCase() == 'CREDIT')) {
        final bKey = p.billNo.trim().toUpperCase();
        if (bKey.isNotEmpty) seenBills.add(bKey);
        double billTotal = p.totalAmount;
        double totalSettled = 0.0;

        for (var v in activeVouchers) {
          totalSettled += v.getAllocatedAmount(p.billNo);
        }

        if (totalSettled > billTotal) totalSettled = billTotal;
        double remainingDue = billTotal - totalSettled;
        remainingDue = double.parse(remainingDue.toStringAsFixed(2));

        if (remainingDue > 0.01) {
          int days = now.difference(p.date).inDays;
          pending.add({
            'date': p.date,
            'billNo': p.billNo,
            'amount': remainingDue,
            'totalAmount': billTotal,
            'paidAmount': totalSettled,
            'dueDays': days,
            'status': totalSettled > 0.01 ? 'PARTIAL' : 'UNSETTLED',
          });
        }
      }
    }

    // Include prior-FY unpaid credit invoices carried forward via pending_invoices.json
    final String expectedType = isReceipt ? 'SALE' : 'PURCHASE';
    for (final inv in carriedPendingInvoices) {
      final String invType = (inv['type'] ?? '').toString().trim().toUpperCase();
      if (invType.isNotEmpty && invType != expectedType) continue;
      final String invPartyId = (inv['partyId'] ?? '').toString();
      final String invPartyName = (inv['partyName'] ?? '').toString();
      if (!matchesParty(invPartyId, invPartyName)) continue;

      final String invBillNo = (inv['billNo'] ?? '').toString().trim();
      final String invKey = invBillNo.toUpperCase();
      if (invBillNo.isEmpty || seenBills.contains(invKey)) continue;

      final double carriedDue = (inv['amount'] as num?)?.toDouble() ?? 0.0;
      if (carriedDue <= 0.01) continue;

      double settledInCurrentFy = 0.0;
      for (var v in activeVouchers) {
        settledInCurrentFy += v.getAllocatedAmount(invBillNo);
      }
      if (settledInCurrentFy > carriedDue) settledInCurrentFy = carriedDue;
      final double remainingDue = double.parse((carriedDue - settledInCurrentFy).toStringAsFixed(2));
      if (remainingDue > 0.01) {
        final DateTime invDate = DateTime.tryParse((inv['date'] ?? '').toString()) ?? now;
        final int days = now.difference(invDate).inDays;
        seenBills.add(invKey);
        pending.add({
          'date': invDate,
          'billNo': invBillNo,
          'amount': remainingDue,
          'totalAmount': carriedDue,
          'paidAmount': settledInCurrentFy,
          'dueDays': days,
          'status': settledInCurrentFy > 0.01 ? 'PARTIAL' : 'UNSETTLED',
          'isCarriedForward': true,
        });
      }
    }

    pending.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
    return pending;
  }
}
