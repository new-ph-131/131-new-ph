// FILE: lib/fy_transfer_engine.dart
// Revision: #PH-REV-787 (MARG-GRADE-MULTI-FY-CASCADE-AND-CLOUD-VAULT)

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'models.dart';
import 'inventory_logic_center.dart';

class FYTransferEngine {
  static const List<String> allFyFileNames = [
    'meds.json',
    'parts.json',
    'banks.json',
    'bats.json',
    'pending_invoices.json',
    's_challan.json',
    'p_challan.json',
    's_return.json',
    'p_return.json',
    'routs.json',
    'comps.json',
    'salts.json',
    'dtypes.json',
    'series.json',
    'sales.json',
    'purc.json',
    'vouc.json',
    'gst_sessions.json',
    'cheques.json',
    'shortage.json',
    'config.json',
    'logs.json',
  ];

  static bool _sameName(String a, String b) {
    final ca = a.trim().toUpperCase();
    final cb = b.trim().toUpperCase();
    return ca.isNotEmpty && ca == cb;
  }

  /// Calculates exact Party Closing Balance for a given year (including Sales, Purchases,
  /// Sale Returns / Credit Notes, Purchase Returns / Debit Notes, and Vouchers).
  static double calculatePartyClosingBalance({
    required Party party,
    required List<Sale> sales,
    required List<Purchase> purchases,
    required List<SaleReturn> saleReturns,
    required List<PurchaseReturn> purchaseReturns,
    required List<Voucher> vouchers,
  }) {
    if (party.name.trim().toUpperCase() == "CASH") return party.opBal;
    double runningBal = party.opBal;
    final String pId = party.id.trim();
    final String pName = party.name.trim();

    // 1. Sales (Debit +)
    for (final s in sales) {
      if (s.isDeleted == 1 || s.status == "Cancelled") continue;
      if ((pId.isNotEmpty && s.partyId.trim() == pId) || _sameName(s.partyName, pName)) {
        runningBal += s.totalAmount;
      }
    }

    // 2. Purchases (Credit -)
    for (final pr in purchases) {
      if (pr.isDeleted == 1) continue;
      if ((pId.isNotEmpty && pr.partyId.trim() == pId) || _sameName(pr.distributorName, pName)) {
        runningBal -= pr.totalAmount;
      }
    }

    // 3. Sale Returns / Credit Notes (Credit -)
    for (final sr in saleReturns) {
      if (sr.isDeleted == 1 || sr.status == "Cancelled") continue;
      if (_sameName(sr.partyName, pName)) {
        runningBal -= sr.totalAmount;
      }
    }

    // 4. Purchase Returns / Debit Notes (Debit +)
    for (final pr in purchaseReturns) {
      if (pr.isDeleted == 1 || pr.status == "Cancelled") continue;
      if (_sameName(pr.distributorName, pName)) {
        runningBal += pr.totalAmount;
      }
    }

    // 5. Vouchers (Receipts, Payments, Expenses)
    for (final v in vouchers) {
      if (v.isDeleted == 1 || v.status != "Active") continue;
      if ((pId.isNotEmpty && v.partyId.trim() == pId) || _sameName(v.partyName, pName)) {
        final String type = v.type.trim().toUpperCase();
        if (type == "RECEIPT") {
          runningBal -= v.amount;
        } else if (type == "PAYMENT" || type == "EXPENSE") {
          runningBal += v.amount;
        }
      }
    }

    return double.parse(runningBal.toStringAsFixed(2));
  }

  /// Calculates Bank Closing Balance for a given year
  static double calculateBankClosingBalance({
    required Bank bank,
    required List<Voucher> vouchers,
  }) {
    double currentBal = bank.openingBalance;
    final String bankName = bank.name.trim().toUpperCase();
    for (final v in vouchers) {
      if (v.isDeleted == 1 || v.status != "Active") continue;
      if (v.depositedIn.trim().toUpperCase() == bankName) {
        final String type = v.type.trim().toUpperCase();
        if (type == "RECEIPT") {
          currentBal += v.amount;
        } else if (type == "PAYMENT" || type == "EXPENSE") {
          currentBal -= v.amount;
        }
      }
    }
    return double.parse(currentBal.toStringAsFixed(2));
  }

  /// Builds Bill-by-Bill Unsettled Credit Invoices list from a year's transactions
  static List<Map<String, dynamic>> buildPendingInvoices({
    required List<Sale> sales,
    required List<Purchase> purchases,
    required List<Voucher> vouchers,
  }) {
    final List<Map<String, dynamic>> pendingInvoices = [];
    final activeVouchers = vouchers.where((v) => v.isDeleted != 1 && v.status == "Active").toList();

    for (final s in sales.where((s) => s.isDeleted != 1 && s.status == "Active" && s.paymentMode.toUpperCase() == "CREDIT")) {
      final double billTotal = s.totalAmount;
      double totalSettled = 0.0;
      for (final v in activeVouchers) {
        totalSettled += v.getAllocatedAmount(s.billNo);
      }
      final double remainingDue = billTotal - totalSettled;
      if (remainingDue > 0.01) {
        pendingInvoices.add({
          'billNo': s.billNo,
          'partyId': s.partyId,
          'partyName': s.partyName,
          'date': s.date.toIso8601String(),
          'amount': double.parse(remainingDue.toStringAsFixed(2)),
          'type': 'SALE',
        });
      }
    }

    for (final p in purchases.where((p) => p.isDeleted != 1 && p.paymentMode.toUpperCase() == "CREDIT")) {
      final double billTotal = p.totalAmount;
      double totalSettled = 0.0;
      for (final v in activeVouchers) {
        totalSettled += v.getAllocatedAmount(p.billNo);
      }
      final double remainingDue = billTotal - totalSettled;
      if (remainingDue > 0.01) {
        pendingInvoices.add({
          'billNo': p.billNo,
          'partyId': p.partyId,
          'partyName': p.distributorName,
          'date': p.date.toIso8601String(),
          'amount': double.parse(remainingDue.toStringAsFixed(2)),
          'type': 'PURCHASE',
        });
      }
    }

    return pendingInvoices;
  }

  /// Pure-Dart Carry Forward Engine (Works for both App Disk and Web In-Memory Vault):
  /// Takes a map of raw JSON strings for `sourceFY` and returns a complete map of raw JSON strings for a brand-new `targetFY`.
  static Map<String, String> computeCarryForwardFromFiles({
    required Map<String, String> sourceFiles,
    required String sourceFY,
    required String targetFY,
    bool filterZeroStock = false,
    bool filterExpired = false,
  }) {
    dynamic loadJson(String name) {
      final raw = sourceFiles[name];
      if (raw == null || raw.trim().isEmpty) return null;
      try {
        return jsonDecode(raw);
      } catch (_) {
        return null;
      }
    }

    final List<Medicine> oldMeds = (loadJson('meds.json') as List?)?.map((e) => Medicine.fromMap(e)).toList() ?? [];
    final List<Party> oldParties = (loadJson('parts.json') as List?)?.map((e) => Party.fromMap(e)).toList() ?? [];
    final List<Sale> oldSales = (loadJson('sales.json') as List?)
            ?.map((e) => Sale.fromMap(e))
            .where((s) => !s.id.startsWith('SESS_') && s.id != 'APP_CONFIG_MASTER' && s.billNo.trim().isNotEmpty)
            .toList() ??
        [];
    final List<Purchase> oldPurc = (loadJson('purc.json') as List?)?.map((e) => Purchase.fromMap(e)).toList() ?? [];
    final List<Voucher> oldVouc = (loadJson('vouc.json') as List?)?.map((e) => Voucher.fromMap(e)).toList() ?? [];
    final List<SaleReturn> oldSaleReturns = (loadJson('s_return.json') as List?)?.map((e) => SaleReturn.fromMap(e)).toList() ?? [];
    final List<PurchaseReturn> oldPurReturns = (loadJson('p_return.json') as List?)?.map((e) => PurchaseReturn.fromMap(e)).toList() ?? [];
    final List<Bank> oldBanks = (loadJson('banks.json') as List?)?.map((e) => Bank.fromMap(e)).toList() ?? [];
    final Map<String, dynamic> oldBatchesRaw = (loadJson('bats.json') is Map) ? Map<String, dynamic>.from(loadJson('bats.json')) : {};

    // STEP 0: Rebuild source year inventory first so every batch closing qty is 100% accurate
    final Map<String, List<BatchInfo>> sourceBatchHistory = {};
    oldBatchesRaw.forEach((medKey, bList) {
      if (bList is List) {
        sourceBatchHistory[medKey] = bList.map((b) => BatchInfo.fromMap(b)).toList();
      }
    });
    InventoryLogicCenter.rebuildAllInventory(
      medicines: oldMeds,
      batchHistory: sourceBatchHistory,
      purchases: oldPurc,
      sales: oldSales,
      saleReturns: oldSaleReturns,
      purchaseReturns: oldPurReturns,
    );

    // 1. CALCULATE NEW PARTY OPENING BALANCES (Includes Sales, Purchases, Returns & Vouchers)
    final List<Party> newParties = oldParties.map((p) {
      p.opBal = calculatePartyClosingBalance(
        party: p,
        sales: oldSales,
        purchases: oldPurc,
        saleReturns: oldSaleReturns,
        purchaseReturns: oldPurReturns,
        vouchers: oldVouc,
      );
      return p;
    }).toList();

    // 2. BANK CLOSING TO OPENING BALANCE
    final List<Bank> newBanks = oldBanks.map((b) {
      b.openingBalance = calculateBankClosingBalance(bank: b, vouchers: oldVouc);
      return b;
    }).toList();

    // 3. BILL-BY-BILL OUTSTANDING (pending_invoices.json)
    final List<Map<String, dynamic>> pendingInvoices = buildPendingInvoices(
      sales: oldSales,
      purchases: oldPurc,
      vouchers: oldVouc,
    );

    // 4. PENDING CHALLANS CARRY-FORWARD
    final List<SaleChallan> oldSaleChallans = (loadJson('s_challan.json') as List?)?.map((e) => SaleChallan.fromMap(e)).toList() ?? [];
    final List<PurchaseChallan> oldPurChallans = (loadJson('p_challan.json') as List?)?.map((e) => PurchaseChallan.fromMap(e)).toList() ?? [];
    final List<SaleChallan> pendingSaleChallans = oldSaleChallans.where((c) => c.isDeleted != 1 && c.status == "Pending").toList();
    final List<PurchaseChallan> pendingPurChallans = oldPurChallans.where((c) => c.isDeleted != 1 && c.status == "Pending").toList();

    // 5. BATCH HISTORY CARRY-FORWARD (Closing qty -> New Opening qty)
    final Map<String, dynamic> correctedBatches = {};
    final DateTime today = DateTime.now();

    sourceBatchHistory.forEach((medKey, batches) {
      final List<Map<String, dynamic>> processedBatches = [];
      for (final bObj in batches) {
        if (bObj.qty < 0) bObj.qty = 0;

        if (filterZeroStock && bObj.qty <= 0) {
          continue;
        }

        if (filterExpired) {
          try {
            final List<String> parts = bObj.exp.split('/');
            final int m = int.parse(parts[0]);
            int y = int.parse(parts[1]);
            if (y < 2000) y += 2000;
            final DateTime lastDay = DateTime(y, m + 1, 0);
            if (lastDay.isBefore(today)) {
              continue;
            }
          } catch (_) {}
        }

        bObj.openingQty = bObj.qty;
        bObj.adjustmentQty = 0;
        processedBatches.add(bObj.toMap());
      }

      if (processedBatches.isNotEmpty) {
        correctedBatches[medKey] = processedBatches;
      }
    });

    // 6. MEDICINE STOCK SYNC WITH CARRIED BATCHES
    final List<Map<String, dynamic>> correctedMeds = oldMeds.map((m) {
      final String key = m.identityKey;
      double totalStock = 0.0;
      if (correctedBatches.containsKey(key)) {
        final List<dynamic> bList = correctedBatches[key];
        for (final b in bList) {
          totalStock += ((b['qty'] as num?)?.toDouble() ?? 0.0);
        }
      }
      m.stock = totalStock >= 0 ? totalStock : 0.0;
      return m.toMap();
    }).toList();

    // 7. RESET NUMBERING SERIES TO START AT #1 FOR NEW FINANCIAL YEAR
    final List<NumberingSeries> oldSeries = (loadJson('series.json') as List?)?.map((e) => NumberingSeries.fromMap(e)).toList() ?? [];
    final List<Map<String, dynamic>> resetSeries = oldSeries.map((s) {
      s.startNumber = 1;
      return s.toMap();
    }).toList();

    final Map<String, String> targetFiles = {
      'meds.json': jsonEncode(correctedMeds),
      'parts.json': jsonEncode(newParties.map((e) => e.toMap()).toList()),
      'banks.json': jsonEncode(newBanks.map((e) => e.toMap()).toList()),
      'bats.json': jsonEncode(correctedBatches),
      'pending_invoices.json': jsonEncode(pendingInvoices),
      's_challan.json': jsonEncode(pendingSaleChallans.map((e) => e.toMap()).toList()),
      'p_challan.json': jsonEncode(pendingPurChallans.map((e) => e.toMap()).toList()),
      'routs.json': jsonEncode(loadJson('routs.json') ?? []),
      'comps.json': jsonEncode(loadJson('comps.json') ?? []),
      'salts.json': jsonEncode(loadJson('salts.json') ?? []),
      'dtypes.json': jsonEncode(loadJson('dtypes.json') ?? []),
      'series.json': jsonEncode(resetSeries),
      'config.json': jsonEncode(loadJson('config.json') ?? {}),
      // Fresh empty transaction registers for the new Financial Year
      'sales.json': jsonEncode([]),
      'purc.json': jsonEncode([]),
      'vouc.json': jsonEncode([]),
      's_return.json': jsonEncode([]),
      'p_return.json': jsonEncode([]),
      'gst_sessions.json': jsonEncode([]),
      'cheques.json': jsonEncode([]),
      'shortage.json': jsonEncode([]),
      'logs.json': jsonEncode([
        LogEntry(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          action: 'SYSTEM',
          details: 'New Financial Year $targetFY initialized from $sourceFY. Opening balances, stock & pending challans carried forward.',
          time: DateTime.now(),
        ).toMap(),
      ]),
    };

    return targetFiles;
  }

  /// Pure-Dart Multi-Year Cascade Step (Marg ERP Back-Year Edit -> Next Year Auto-Heal):
  /// Rebuilds `prevFiles` stock/balances, cascades closing balances into `targetFiles` opening balances
  /// while preserving `targetFiles` own transactions and new batches, and rebuilds `targetFiles` live stock!
  static ({Map<String, String> healedPrevFiles, Map<String, String> healedTargetFiles}) cascadeSingleYearStep({
    required Map<String, String> prevFiles,
    required Map<String, String> targetFiles,
    required String prevFY,
    required String targetFY,
  }) {
    dynamic loadMapJson(Map<String, String> map, String name) {
      final raw = map[name];
      if (raw == null || raw.trim().isEmpty) return null;
      try {
        return jsonDecode(raw);
      } catch (_) {
        return null;
      }
    }

    final Map<String, String> outPrev = Map<String, String>.from(prevFiles);
    final Map<String, String> outTarget = Map<String, String>.from(targetFiles);

    // 1. Parse Previous Year
    final List<Medicine> prevMeds = (loadMapJson(outPrev, 'meds.json') as List?)?.map((e) => Medicine.fromMap(e)).toList() ?? [];
    final List<Party> prevParties = (loadMapJson(outPrev, 'parts.json') as List?)?.map((e) => Party.fromMap(e)).toList() ?? [];
    final List<Sale> prevSales = (loadMapJson(outPrev, 'sales.json') as List?)
            ?.map((e) => Sale.fromMap(e))
            .where((s) => !s.id.startsWith('SESS_') && s.id != 'APP_CONFIG_MASTER' && s.billNo.trim().isNotEmpty)
            .toList() ??
        [];
    final List<Purchase> prevPurc = (loadMapJson(outPrev, 'purc.json') as List?)?.map((e) => Purchase.fromMap(e)).toList() ?? [];
    final List<Voucher> prevVouc = (loadMapJson(outPrev, 'vouc.json') as List?)?.map((e) => Voucher.fromMap(e)).toList() ?? [];
    final List<SaleReturn> prevSaleReturns = (loadMapJson(outPrev, 's_return.json') as List?)?.map((e) => SaleReturn.fromMap(e)).toList() ?? [];
    final List<PurchaseReturn> prevPurReturns = (loadMapJson(outPrev, 'p_return.json') as List?)?.map((e) => PurchaseReturn.fromMap(e)).toList() ?? [];
    final List<Bank> prevBanks = (loadMapJson(outPrev, 'banks.json') as List?)?.map((e) => Bank.fromMap(e)).toList() ?? [];
    final Map<String, dynamic> prevBatchesRaw = (loadMapJson(outPrev, 'bats.json') is Map)
        ? Map<String, dynamic>.from(loadMapJson(outPrev, 'bats.json'))
        : {};

    final Map<String, List<BatchInfo>> prevBatchHistory = {};
    prevBatchesRaw.forEach((medKey, bList) {
      if (bList is List) {
        prevBatchHistory[medKey] = bList.map((b) => BatchInfo.fromMap(b)).toList();
      }
    });

    // Rebuild Previous Year Inventory first so its closing batch qty is 100% accurate!
    InventoryLogicCenter.rebuildAllInventory(
      medicines: prevMeds,
      batchHistory: prevBatchHistory,
      purchases: prevPurc,
      sales: prevSales,
      saleReturns: prevSaleReturns,
      purchaseReturns: prevPurReturns,
    );

    outPrev['meds.json'] = jsonEncode(prevMeds.map((e) => e.toMap()).toList());
    outPrev['bats.json'] = jsonEncode(
      prevBatchHistory.map((k, v) => MapEntry(k, v.map((b) => b.toMap()).toList())),
    );

    // 2. Parse Target Year
    final List<Medicine> targetMeds = (loadMapJson(outTarget, 'meds.json') as List?)?.map((e) => Medicine.fromMap(e)).toList() ?? [];
    final List<Party> targetParties = (loadMapJson(outTarget, 'parts.json') as List?)?.map((e) => Party.fromMap(e)).toList() ?? [];
    final List<Bank> targetBanks = (loadMapJson(outTarget, 'banks.json') as List?)?.map((e) => Bank.fromMap(e)).toList() ?? [];
    final List<Sale> targetSales = (loadMapJson(outTarget, 'sales.json') as List?)
            ?.map((e) => Sale.fromMap(e))
            .where((s) => !s.id.startsWith('SESS_') && s.id != 'APP_CONFIG_MASTER' && s.billNo.trim().isNotEmpty)
            .toList() ??
        [];
    final List<Purchase> targetPurc = (loadMapJson(outTarget, 'purc.json') as List?)?.map((e) => Purchase.fromMap(e)).toList() ?? [];
    final List<SaleReturn> targetSaleReturns = (loadMapJson(outTarget, 's_return.json') as List?)?.map((e) => SaleReturn.fromMap(e)).toList() ?? [];
    final List<PurchaseReturn> targetPurReturns = (loadMapJson(outTarget, 'p_return.json') as List?)?.map((e) => PurchaseReturn.fromMap(e)).toList() ?? [];
    final Map<String, dynamic> targetBatchesRaw = (loadMapJson(outTarget, 'bats.json') is Map)
        ? Map<String, dynamic>.from(loadMapJson(outTarget, 'bats.json'))
        : {};

    final Map<String, List<BatchInfo>> targetBatchHistory = {};
    targetBatchesRaw.forEach((medKey, bList) {
      if (bList is List) {
        targetBatchHistory[medKey] = bList.map((b) => BatchInfo.fromMap(b)).toList();
      }
    });

    // 3. Re-calculate Party Closing Balances from prevFY -> targetFY opBal
    final Map<String, double> recalculatedPartyBalsById = {};
    final Map<String, double> recalculatedPartyBalsByName = {};
    for (final p in prevParties) {
      if (p.name.trim().toUpperCase() == "CASH") continue;
      final double closingBal = calculatePartyClosingBalance(
        party: p,
        sales: prevSales,
        purchases: prevPurc,
        saleReturns: prevSaleReturns,
        purchaseReturns: prevPurReturns,
        vouchers: prevVouc,
      );
      if (p.id.trim().isNotEmpty) recalculatedPartyBalsById[p.id.trim()] = closingBal;
      recalculatedPartyBalsByName[p.name.trim().toUpperCase()] = closingBal;
    }

    final Set<String> targetPartyIds = targetParties.map((p) => p.id.trim()).toSet();
    final Set<String> targetPartyNames = targetParties.map((p) => p.name.trim().toUpperCase()).toSet();
    final List<Party> updatedParties = targetParties.map((p) {
      if (recalculatedPartyBalsById.containsKey(p.id.trim())) {
        p.opBal = recalculatedPartyBalsById[p.id.trim()]!;
      } else if (recalculatedPartyBalsByName.containsKey(p.name.trim().toUpperCase())) {
        p.opBal = recalculatedPartyBalsByName[p.name.trim().toUpperCase()]!;
      }
      return p;
    }).toList();

    for (final p in prevParties) {
      if (!targetPartyIds.contains(p.id.trim()) && !targetPartyNames.contains(p.name.trim().toUpperCase())) {
        p.opBal = recalculatedPartyBalsById[p.id.trim()] ?? recalculatedPartyBalsByName[p.name.trim().toUpperCase()] ?? p.opBal;
        updatedParties.add(p);
      }
    }

    // 4. Re-calculate Bank Closing Balances from prevFY -> targetFY openingBalance
    final Map<String, double> recalculatedBankBals = {};
    for (final b in prevBanks) {
      recalculatedBankBals[b.id] = calculateBankClosingBalance(bank: b, vouchers: prevVouc);
      recalculatedBankBals[b.name.trim().toUpperCase()] = recalculatedBankBals[b.id]!;
    }
    final List<Bank> updatedBanks = targetBanks.map((b) {
      if (recalculatedBankBals.containsKey(b.id)) {
        b.openingBalance = recalculatedBankBals[b.id]!;
      } else if (recalculatedBankBals.containsKey(b.name.trim().toUpperCase())) {
        b.openingBalance = recalculatedBankBals[b.name.trim().toUpperCase()]!;
      }
      return b;
    }).toList();
    final Set<String> targetBankNames = updatedBanks.map((b) => b.name.trim().toUpperCase()).toSet();
    for (final b in prevBanks) {
      if (!targetBankNames.contains(b.name.trim().toUpperCase())) {
        b.openingBalance = recalculatedBankBals[b.id] ?? b.openingBalance;
        updatedBanks.add(b);
      }
    }

    // 5. Cascade Batch Opening Stock (`openingQty`) into targetFY while preserving targetFY new batches & adjustments!
    prevBatchHistory.forEach((medKey, prevBatches) {
      final List<BatchInfo> targetList = targetBatchHistory[medKey] ?? [];
      for (final pb in prevBatches) {
        final double carriedOpening = pb.qty >= 0 ? pb.qty : 0.0;
        final String cleanBatchNo = pb.batch.trim().toUpperCase();
        final int idx = targetList.indexWhere((tb) => tb.batch.trim().toUpperCase() == cleanBatchNo);
        if (idx != -1) {
          targetList[idx].openingQty = carriedOpening;
        } else if (carriedOpening > 0) {
          final BatchInfo carriedCopy = BatchInfo.fromMap(pb.toMap());
          carriedCopy.openingQty = carriedOpening;
          carriedCopy.qty = carriedOpening;
          carriedCopy.adjustmentQty = 0;
          targetList.add(carriedCopy);
        }
      }
      if (targetList.isNotEmpty) {
        targetBatchHistory[medKey] = targetList;
      }
    });

    // Ensure any missing Medicines from prevFY are present in targetMeds
    final Set<String> targetMedKeys = targetMeds.map((m) => m.identityKey).toSet();
    final List<Medicine> updatedMeds = List<Medicine>.from(targetMeds);
    for (final pm in prevMeds) {
      if (!targetMedKeys.contains(pm.identityKey)) {
        updatedMeds.add(Medicine.fromMap(pm.toMap()));
      }
    }

    // 6. CRITICAL MARG STEP: Rebuild targetFY Live Inventory (`newOpeningQty + targetFY_Purc - targetFY_Sales + Returns`)!
    InventoryLogicCenter.rebuildAllInventory(
      medicines: updatedMeds,
      batchHistory: targetBatchHistory,
      purchases: targetPurc,
      sales: targetSales,
      saleReturns: targetSaleReturns,
      purchaseReturns: targetPurReturns,
    );

    // 7. Update Pending Invoices & Carry Forward any newly added Pending Challans
    final List<Map<String, dynamic>> pendingInvoices = buildPendingInvoices(
      sales: prevSales,
      purchases: prevPurc,
      vouchers: prevVouc,
    );

    final List<SaleChallan> prevSaleChallans = (loadMapJson(outPrev, 's_challan.json') as List?)?.map((e) => SaleChallan.fromMap(e)).toList() ?? [];
    final List<SaleChallan> targetSaleChallans = (loadMapJson(outTarget, 's_challan.json') as List?)?.map((e) => SaleChallan.fromMap(e)).toList() ?? [];
    final Set<String> targetScIds = targetSaleChallans.map((c) => c.id).toSet();
    for (final sc in prevSaleChallans.where((c) => c.isDeleted != 1 && c.status == "Pending")) {
      if (!targetScIds.contains(sc.id)) {
        targetSaleChallans.add(sc);
      }
    }

    final List<PurchaseChallan> prevPurChallans = (loadMapJson(outPrev, 'p_challan.json') as List?)?.map((e) => PurchaseChallan.fromMap(e)).toList() ?? [];
    final List<PurchaseChallan> targetPurChallans = (loadMapJson(outTarget, 'p_challan.json') as List?)?.map((e) => PurchaseChallan.fromMap(e)).toList() ?? [];
    final Set<String> targetPcIds = targetPurChallans.map((c) => c.id).toSet();
    for (final pc in prevPurChallans.where((c) => c.isDeleted != 1 && c.status == "Pending")) {
      if (!targetPcIds.contains(pc.id)) {
        targetPurChallans.add(pc);
      }
    }

    // Delta merge static master lists (Routes, Companies, Salts)
    final List<RouteArea> prevRouts = (loadMapJson(outPrev, 'routs.json') as List?)?.map((e) => RouteArea.fromMap(e)).toList() ?? [];
    final List<RouteArea> targetRouts = (loadMapJson(outTarget, 'routs.json') as List?)?.map((e) => RouteArea.fromMap(e)).toList() ?? [];
    final Set<String> targetRouteIds = targetRouts.map((r) => r.id).toSet();
    targetRouts.addAll(prevRouts.where((r) => !targetRouteIds.contains(r.id)));

    final List<Company> prevComps = (loadMapJson(outPrev, 'comps.json') as List?)?.map((e) => Company.fromMap(e)).toList() ?? [];
    final List<Company> targetComps = (loadMapJson(outTarget, 'comps.json') as List?)?.map((e) => Company.fromMap(e)).toList() ?? [];
    final Set<String> targetCompIds = targetComps.map((c) => c.id).toSet();
    targetComps.addAll(prevComps.where((c) => !targetCompIds.contains(c.id)));

    final List<Salt> prevSalts = (loadMapJson(outPrev, 'salts.json') as List?)?.map((e) => Salt.fromMap(e)).toList() ?? [];
    final List<Salt> targetSalts = (loadMapJson(outTarget, 'salts.json') as List?)?.map((e) => Salt.fromMap(e)).toList() ?? [];
    final Set<String> targetSaltIds = targetSalts.map((s) => s.id).toSet();
    targetSalts.addAll(prevSalts.where((s) => !targetSaltIds.contains(s.id)));

    outTarget['meds.json'] = jsonEncode(updatedMeds.map((e) => e.toMap()).toList());
    outTarget['parts.json'] = jsonEncode(updatedParties.map((e) => e.toMap()).toList());
    outTarget['banks.json'] = jsonEncode(updatedBanks.map((e) => e.toMap()).toList());
    outTarget['bats.json'] = jsonEncode(
      targetBatchHistory.map((k, v) => MapEntry(k, v.map((b) => b.toMap()).toList())),
    );
    outTarget['pending_invoices.json'] = jsonEncode(pendingInvoices);
    outTarget['s_challan.json'] = jsonEncode(targetSaleChallans.map((e) => e.toMap()).toList());
    outTarget['p_challan.json'] = jsonEncode(targetPurChallans.map((e) => e.toMap()).toList());
    outTarget['routs.json'] = jsonEncode(targetRouts.map((e) => e.toMap()).toList());
    outTarget['comps.json'] = jsonEncode(targetComps.map((e) => e.toMap()).toList());
    outTarget['salts.json'] = jsonEncode(targetSalts.map((e) => e.toMap()).toList());

    return (healedPrevFiles: outPrev, healedTargetFiles: outTarget);
  }

  // ===========================================================================
  // DISK-BASED FINANCIAL YEAR TRANSFER (APP)
  // ===========================================================================
  static Future<bool> transferData({
    required String companyID,
    required String businessType,
    required String sourceFY,
    required String targetFY,
    bool filterZeroStock = false,
    bool filterExpired = false,
  }) async {
    try {
      final root = await getApplicationDocumentsDirectory();
      final sourcePath = '${root.path}/Pharoah_Data/$companyID/$businessType/$sourceFY';
      final targetPath = '${root.path}/Pharoah_Data/$companyID/$businessType/$targetFY';

      final targetDir = Directory(targetPath);
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final Map<String, String> sourceFiles = {};
      for (final fileName in allFyFileNames) {
        final f = File('$sourcePath/$fileName');
        if (f.existsSync()) {
          sourceFiles[fileName] = await f.readAsString();
        }
      }

      final Map<String, String> targetFiles = computeCarryForwardFromFiles(
        sourceFiles: sourceFiles,
        sourceFY: sourceFY,
        targetFY: targetFY,
        filterZeroStock: filterZeroStock,
        filterExpired: filterExpired,
      );

      for (final entry in targetFiles.entries) {
        await File('$targetPath/${entry.key}').writeAsString(entry.value);
      }

      return true;
    } catch (e) {
      print("FY Transfer Error: $e");
      return false;
    }
  }
}
