// FILE: lib/logic/return_history_engine.dart
// Shared Batch-First Return History, Already-Returned Balance, FIFO/LIFO Split & Pull-From-Bill Engine
// Used by both Mobile/Desktop App and Web Live Workstation.

import '../models.dart';

class ReturnHistoryInvoiceLine {
  final String billNo;
  final String internalNo;
  final DateTime date;
  final String batch;
  final String exp;
  final String packing;
  final String hsn;
  final double billedQty;
  final double billedFreeQty;
  final double alreadyReturnedQty;
  final double alreadyReturnedFreeQty;
  final double rate;
  final double mrp;
  final double gstRate;
  final double discountPer;
  final double discountRupees;
  final double rateA;
  final double rateB;
  final double rateC;
  final String appliedRateType;
  final double rateCFormula;

  const ReturnHistoryInvoiceLine({
    required this.billNo,
    this.internalNo = "",
    required this.date,
    required this.batch,
    required this.exp,
    required this.packing,
    required this.hsn,
    required this.billedQty,
    this.billedFreeQty = 0.0,
    this.alreadyReturnedQty = 0.0,
    this.alreadyReturnedFreeQty = 0.0,
    required this.rate,
    required this.mrp,
    required this.gstRate,
    this.discountPer = 0.0,
    this.discountRupees = 0.0,
    this.rateA = 0.0,
    this.rateB = 0.0,
    this.rateC = 0.0,
    this.appliedRateType = "A",
    this.rateCFormula = 0.0,
  });

  double get availableQty =>
      (billedQty - alreadyReturnedQty) > 0 ? (billedQty - alreadyReturnedQty) : 0.0;

  double get effectiveDiscPer {
    if (discountPer > 0.0001) return discountPer;
    final gross = billedQty * rate;
    if (gross > 0 && discountRupees > 0.0001) {
      return (discountRupees / gross) * 100.0;
    }
    return 0.0;
  }

  Map<String, dynamic> toHistoryMap() => {
        'billNo': billNo,
        'internalNo': internalNo,
        'date': date,
        'batch': batch,
        'exp': exp,
        'packing': packing,
        'hsn': hsn,
        'qty': availableQty > 0 ? availableQty : billedQty,
        'billedQty': billedQty,
        'free': billedFreeQty,
        'availableQty': availableQty,
        'alreadyReturnedQty': alreadyReturnedQty,
        'rate': rate,
        'purchaseRate': rate,
        'mrp': mrp,
        'gst': gstRate,
        'discountPer': effectiveDiscPer,
        'discountRupees': discountRupees,
        'rateA': rateA,
        'rateB': rateB,
        'rateC': rateC,
        'appliedRateType': appliedRateType,
        'rateCFormula': rateCFormula,
      };
}

class ReturnBatchGroup {
  final String batchKey;
  final String batchDisplay;
  final String exp;
  final String packing;
  final String hsn;
  final int billCount;
  final double totalBilledQty;
  final double totalBilledFreeQty;
  final double totalReturnedQty;
  final double totalReturnedFreeQty;
  final double minRate;
  final double maxRate;
  final double latestRate;
  final double latestMrp;
  final double latestGstRate;
  final double latestDiscPer;
  final DateTime latestDate;
  final List<ReturnHistoryInvoiceLine> invoices;

  const ReturnBatchGroup({
    required this.batchKey,
    required this.batchDisplay,
    required this.exp,
    required this.packing,
    required this.hsn,
    required this.billCount,
    required this.totalBilledQty,
    required this.totalBilledFreeQty,
    required this.totalReturnedQty,
    required this.totalReturnedFreeQty,
    required this.minRate,
    required this.maxRate,
    required this.latestRate,
    required this.latestMrp,
    required this.latestGstRate,
    required this.latestDiscPer,
    required this.latestDate,
    required this.invoices,
  });

  double get netReturnableQty =>
      (totalBilledQty - totalReturnedQty) > 0 ? (totalBilledQty - totalReturnedQty) : 0.0;

  bool get hasRateVariance => (maxRate - minRate).abs() > 0.01;

  bool get isExpired => ReturnHistoryEngine.isExpiryPast(exp);
}

class ReturnRecentBillLine {
  final String medicineID;
  final String name;
  final String packing;
  final String hsn;
  final String batch;
  final String exp;
  final double billedQty;
  final double billedFreeQty;
  final double alreadyReturnedQty;
  final double rate;
  final double mrp;
  final double gstRate;
  final double discountPer;
  final double discountRupees;
  final double rateA;
  final double rateB;
  final double rateC;
  final String appliedRateType;
  final double rateCFormula;
  final String billNo;
  final String internalNo;
  final DateTime date;

  const ReturnRecentBillLine({
    required this.medicineID,
    required this.name,
    required this.packing,
    required this.hsn,
    required this.batch,
    required this.exp,
    required this.billedQty,
    required this.billedFreeQty,
    required this.alreadyReturnedQty,
    required this.rate,
    required this.mrp,
    required this.gstRate,
    required this.discountPer,
    required this.discountRupees,
    required this.rateA,
    required this.rateB,
    required this.rateC,
    required this.appliedRateType,
    required this.rateCFormula,
    required this.billNo,
    this.internalNo = "",
    required this.date,
  });

  double get availableQty =>
      (billedQty - alreadyReturnedQty) > 0 ? (billedQty - alreadyReturnedQty) : 0.0;

  ReturnHistoryInvoiceLine toInvoiceLine() => ReturnHistoryInvoiceLine(
        billNo: billNo,
        internalNo: internalNo,
        date: date,
        batch: batch,
        exp: exp,
        packing: packing,
        hsn: hsn,
        billedQty: billedQty,
        billedFreeQty: billedFreeQty,
        alreadyReturnedQty: alreadyReturnedQty,
        rate: rate,
        mrp: mrp,
        gstRate: gstRate,
        discountPer: discountPer,
        discountRupees: discountRupees,
        rateA: rateA,
        rateB: rateB,
        rateC: rateC,
        appliedRateType: appliedRateType,
        rateCFormula: rateCFormula,
      );
}

class ReturnRecentBill {
  final String billNo;
  final String internalNo;
  final DateTime date;
  final double totalAmount;
  final List<ReturnRecentBillLine> lines;

  const ReturnRecentBill({
    required this.billNo,
    this.internalNo = "",
    required this.date,
    required this.totalAmount,
    required this.lines,
  });
}

class ReturnAllocationItem {
  final ReturnHistoryInvoiceLine line;
  final double allocatedQty;

  const ReturnAllocationItem({required this.line, required this.allocatedQty});
}

class ReturnAllocationResult {
  final List<ReturnAllocationItem> allocations;
  final bool hasOverReturn;
  final double netReturnable;

  const ReturnAllocationResult({
    required this.allocations,
    required this.hasOverReturn,
    required this.netReturnable,
  });
}

class ReturnHistoryEngine {
  static bool isExpiryPast(String exp, {DateTime? now}) {
    final clean = exp.trim();
    if (clean.isEmpty) return false;
    final ref = now ?? DateTime.now();
    final parts = clean.split(RegExp(r'[/\-]'));
    if (parts.length == 2) {
      int? a = int.tryParse(parts[0]);
      int? b = int.tryParse(parts[1]);
      if (a == null || b == null) return false;
      int month;
      int year;
      if (parts[0].length == 4) {
        year = a;
        month = b;
      } else {
        month = a;
        year = b < 100 ? 2000 + b : b;
      }
      if (month < 1 || month > 12) return false;
      final lastDay = DateTime(year, month + 1, 0, 23, 59, 59);
      return ref.isAfter(lastDay);
    }
    return false;
  }

  static bool _matchesParty({
    required String targetId,
    required String targetName,
    required String docPartyId,
    required String docPartyName,
  }) {
    final cId = targetId.trim();
    final cName = targetName.trim().toLowerCase();
    final dId = docPartyId.trim();
    final dName = docPartyName.trim().toLowerCase();
    return (cId.isNotEmpty && dId.isNotEmpty && cId == dId) ||
        (cName.isNotEmpty && dName.isNotEmpty && cName == dName);
  }

  static bool _matchesMedicine({
    required String targetMedId,
    required String targetMedName,
    required String itemMedId,
    required String itemName,
  }) {
    final cId = targetMedId.trim();
    final cName = targetMedName.trim().toLowerCase();
    final iId = itemMedId.trim();
    final iName = itemName.trim().toLowerCase();
    return (cId.isNotEmpty && iId.isNotEmpty && cId == iId) ||
        (cName.isNotEmpty && iName.isNotEmpty && cName == iName);
  }

  static String _batchKey(String batch) {
    final clean = batch.trim().toUpperCase();
    return clean.isEmpty ? "NO-BATCH" : clean;
  }

  static List<ReturnBatchGroup> buildBatchGroups({
    required bool isSale,
    required String partyId,
    required String partyName,
    required String medicineId,
    required String medicineName,
    required List<Sale> sales,
    required List<Purchase> purchases,
    required List<SaleReturn> saleReturns,
    required List<PurchaseReturn> purchaseReturns,
    List<dynamic> currentCartItems = const [],
    String? excludeNoteId,
  }) {
    // 1. Collect raw billed lines
    final List<ReturnHistoryInvoiceLine> rawLines = [];
    if (isSale) {
      for (final s in sales) {
        if (s.isDeleted == 1 || s.status != "Active") continue;
        if (!_matchesParty(
          targetId: partyId,
          targetName: partyName,
          docPartyId: s.partyId,
          docPartyName: s.partyName,
        )) {
          continue;
        }
        for (final it in s.items) {
          if (!_matchesMedicine(
            targetMedId: medicineId,
            targetMedName: medicineName,
            itemMedId: it.medicineID,
            itemName: it.name,
          )) {
            continue;
          }
          rawLines.add(ReturnHistoryInvoiceLine(
            billNo: s.billNo,
            date: s.date,
            batch: it.batch,
            exp: it.exp,
            packing: it.packing,
            hsn: it.hsn,
            billedQty: it.qty,
            billedFreeQty: it.freeQty,
            rate: it.rate,
            mrp: it.mrp,
            gstRate: it.gstRate,
            discountPer: it.discountPer,
            discountRupees: it.discountRupees,
            appliedRateType: it.appliedRateType,
            rateCFormula: it.rateCFormula,
          ));
        }
      }
    } else {
      for (final p in purchases) {
        if (p.isDeleted == 1 ||
            p.gstStatus == "Cancelled" ||
            p.gstStatus == "Deleted") {
          continue;
        }
        if (!_matchesParty(
          targetId: partyId,
          targetName: partyName,
          docPartyId: p.partyId,
          docPartyName: p.distributorName,
        )) {
          continue;
        }
        for (final it in p.items) {
          if (!_matchesMedicine(
            targetMedId: medicineId,
            targetMedName: medicineName,
            itemMedId: it.medicineID,
            itemName: it.name,
          )) {
            continue;
          }
          rawLines.add(ReturnHistoryInvoiceLine(
            billNo: p.billNo,
            internalNo: p.internalNo,
            date: p.date,
            batch: it.batch,
            exp: it.exp,
            packing: it.packing,
            hsn: it.hsn,
            billedQty: it.qty,
            billedFreeQty: it.freeQty,
            rate: it.purchaseRate,
            mrp: it.mrp,
            gstRate: it.gstRate,
            discountPer: it.discountPer,
            discountRupees: it.discountRupees,
            rateA: it.rateA,
            rateB: it.rateB,
            rateC: it.rateC,
            appliedRateType: it.appliedRateType,
            rateCFormula: it.rateCFormula,
          ));
        }
      }
    }

    if (rawLines.isEmpty) return [];

    // 2. Collect already returned quantities by (batchKey, billNo) + unlinked by batchKey
    final Map<String, double> returnedByBatchAndBill = {};
    final Map<String, double> returnedFreeByBatchAndBill = {};
    final Map<String, double> unlinkedReturnedByBatch = {};
    final Map<String, double> totalReturnedByBatch = {};
    final Map<String, double> totalReturnedFreeByBatch = {};

    void addReturnEntry({
      required String itemMedId,
      required String itemName,
      required String batch,
      required String origBillNo,
      required double qty,
      required double freeQty,
    }) {
      if (!_matchesMedicine(
        targetMedId: medicineId,
        targetMedName: medicineName,
        itemMedId: itemMedId,
        itemName: itemName,
      )) {
        return;
      }
      final bKey = _batchKey(batch);
      final billKey = origBillNo.trim().toUpperCase();
      totalReturnedByBatch[bKey] = (totalReturnedByBatch[bKey] ?? 0.0) + qty;
      totalReturnedFreeByBatch[bKey] =
          (totalReturnedFreeByBatch[bKey] ?? 0.0) + freeQty;
      if (billKey.isNotEmpty) {
        final composite = "$bKey||$billKey";
        returnedByBatchAndBill[composite] =
            (returnedByBatchAndBill[composite] ?? 0.0) + qty;
        returnedFreeByBatchAndBill[composite] =
            (returnedFreeByBatchAndBill[composite] ?? 0.0) + freeQty;
      } else {
        unlinkedReturnedByBatch[bKey] =
            (unlinkedReturnedByBatch[bKey] ?? 0.0) + qty;
      }
    }

    if (isSale) {
      for (final sr in saleReturns) {
        if (sr.isDeleted == 1 || sr.status == "Cancelled") continue;
        if (excludeNoteId != null &&
            excludeNoteId.isNotEmpty &&
            sr.id == excludeNoteId) {
          continue;
        }
        if (!_matchesParty(
          targetId: partyId,
          targetName: partyName,
          docPartyId: sr.partyId,
          docPartyName: sr.partyName,
        )) {
          continue;
        }
        for (final it in sr.items) {
          final effBill =
              it.origBillNo.trim().isNotEmpty ? it.origBillNo : sr.origBillNo;
          addReturnEntry(
            itemMedId: it.medicineID,
            itemName: it.name,
            batch: it.batch,
            origBillNo: effBill,
            qty: it.qty,
            freeQty: it.freeQty,
          );
        }
      }
    } else {
      for (final pr in purchaseReturns) {
        if (pr.isDeleted == 1 || pr.status == "Cancelled") continue;
        if (excludeNoteId != null &&
            excludeNoteId.isNotEmpty &&
            pr.id == excludeNoteId) {
          continue;
        }
        if (!_matchesParty(
          targetId: partyId,
          targetName: partyName,
          docPartyId: pr.partyId,
          docPartyName: pr.distributorName,
        )) {
          continue;
        }
        for (final it in pr.items) {
          final effBill =
              it.origBillNo.trim().isNotEmpty ? it.origBillNo : pr.origBillNo;
          addReturnEntry(
            itemMedId: it.medicineID,
            itemName: it.name,
            batch: it.batch,
            origBillNo: effBill,
            qty: it.qty,
            freeQty: it.freeQty,
          );
        }
      }
    }

    for (final it in currentCartItems) {
      addReturnEntry(
        itemMedId: (it.medicineID ?? '').toString(),
        itemName: (it.name ?? '').toString(),
        batch: (it.batch ?? '').toString(),
        origBillNo: (it.origBillNo ?? '').toString(),
        qty: ((it.qty ?? 0) as num).toDouble(),
        freeQty: ((it.freeQty ?? 0) as num).toDouble(),
      );
    }

    // 3. Group lines by batch
    final Map<String, List<ReturnHistoryInvoiceLine>> grouped = {};
    for (final line in rawLines) {
      final bKey = _batchKey(line.batch);
      grouped.putIfAbsent(bKey, () => []).add(line);
    }

    // 4. Attach returned qty per bill & compute batch summaries
    final List<ReturnBatchGroup> groups = [];
    for (final entry in grouped.entries) {
      final bKey = entry.key;
      final list = List<ReturnHistoryInvoiceLine>.from(entry.value)
        ..sort((a, b) => b.date.compareTo(a.date));

      final Map<String, double> remainingBillReturn = {};
      for (final l in list) {
        final composite = "$bKey||${l.billNo.trim().toUpperCase()}";
        if (returnedByBatchAndBill.containsKey(composite)) {
          remainingBillReturn[composite] = returnedByBatchAndBill[composite]!;
        }
      }
      double remainingUnlinked = unlinkedReturnedByBatch[bKey] ?? 0.0;

      final List<ReturnHistoryInvoiceLine> enriched = [];
      for (final l in list) {
        final composite = "$bKey||${l.billNo.trim().toUpperCase()}";
        double retForLine = 0.0;
        final explicitAvail = remainingBillReturn[composite] ?? 0.0;
        if (explicitAvail > 0) {
          final take =
              explicitAvail <= l.billedQty ? explicitAvail : l.billedQty;
          retForLine += take;
          remainingBillReturn[composite] = explicitAvail - take;
        }
        if (remainingUnlinked > 0 && retForLine < l.billedQty) {
          final cap = l.billedQty - retForLine;
          final take = remainingUnlinked <= cap ? remainingUnlinked : cap;
          retForLine += take;
          remainingUnlinked -= take;
        }
        enriched.add(ReturnHistoryInvoiceLine(
          billNo: l.billNo,
          internalNo: l.internalNo,
          date: l.date,
          batch: l.batch,
          exp: l.exp,
          packing: l.packing,
          hsn: l.hsn,
          billedQty: l.billedQty,
          billedFreeQty: l.billedFreeQty,
          alreadyReturnedQty: retForLine,
          alreadyReturnedFreeQty: returnedFreeByBatchAndBill[composite] ?? 0.0,
          rate: l.rate,
          mrp: l.mrp,
          gstRate: l.gstRate,
          discountPer: l.discountPer,
          discountRupees: l.discountRupees,
          rateA: l.rateA,
          rateB: l.rateB,
          rateC: l.rateC,
          appliedRateType: l.appliedRateType,
          rateCFormula: l.rateCFormula,
        ));
      }

      double totalBilled = 0.0;
      double totalFree = 0.0;
      double minR = enriched.first.rate;
      double maxR = enriched.first.rate;
      for (final e in enriched) {
        totalBilled += e.billedQty;
        totalFree += e.billedFreeQty;
        if (e.rate < minR) minR = e.rate;
        if (e.rate > maxR) maxR = e.rate;
      }

      final latest = enriched.first;
      groups.add(ReturnBatchGroup(
        batchKey: bKey,
        batchDisplay: latest.batch.trim().isNotEmpty ? latest.batch.trim() : "NO-BATCH",
        exp: latest.exp,
        packing: latest.packing,
        hsn: latest.hsn,
        billCount: enriched.length,
        totalBilledQty: totalBilled,
        totalBilledFreeQty: totalFree,
        totalReturnedQty: totalReturnedByBatch[bKey] ?? 0.0,
        totalReturnedFreeQty: totalReturnedFreeByBatch[bKey] ?? 0.0,
        minRate: minR,
        maxRate: maxR,
        latestRate: latest.rate,
        latestMrp: latest.mrp,
        latestGstRate: latest.gstRate,
        latestDiscPer: latest.effectiveDiscPer,
        latestDate: latest.date,
        invoices: enriched,
      ));
    }

    groups.sort((a, b) => b.latestDate.compareTo(a.latestDate));
    return groups;
  }

  static ReturnAllocationResult allocateReturnQty({
    required ReturnBatchGroup group,
    required double requestedQty,
    bool newestFirst = true,
  }) {
    if (requestedQty <= 0 || group.invoices.isEmpty) {
      return ReturnAllocationResult(
        allocations: const [],
        hasOverReturn: false,
        netReturnable: group.netReturnableQty,
      );
    }

    final ordered = newestFirst
        ? group.invoices
        : group.invoices.reversed.toList();
    double remaining = requestedQty;
    final List<ReturnAllocationItem> out = [];

    for (final line in ordered) {
      if (remaining <= 0.0001) break;
      final avail = line.availableQty;
      if (avail <= 0.0001) continue;
      final take = remaining <= avail ? remaining : avail;
      out.add(ReturnAllocationItem(line: line, allocatedQty: take));
      remaining -= take;
    }

    final bool hasOverReturn = remaining > 0.0001;
    if (hasOverReturn) {
      // Assign remaining overflow onto the primary selected invoice so no qty is silently dropped
      final primary = ordered.first;
      final existingIdx = out.indexWhere((a) =>
          a.line.billNo == primary.billNo && a.line.date == primary.date);
      if (existingIdx != -1) {
        final prev = out[existingIdx];
        out[existingIdx] = ReturnAllocationItem(
          line: prev.line,
          allocatedQty: prev.allocatedQty + remaining,
        );
      } else {
        out.insert(0, ReturnAllocationItem(line: primary, allocatedQty: remaining));
      }
    }

    return ReturnAllocationResult(
      allocations: out,
      hasOverReturn: hasOverReturn,
      netReturnable: group.netReturnableQty,
    );
  }

  static List<ReturnRecentBill> getRecentPartyBills({
    required bool isSale,
    required String partyId,
    required String partyName,
    required List<Sale> sales,
    required List<Purchase> purchases,
    required List<SaleReturn> saleReturns,
    required List<PurchaseReturn> purchaseReturns,
    List<dynamic> currentCartItems = const [],
    String? excludeNoteId,
    int limit = 15,
  }) {
    final Map<String, double> returnedByKey = {};

    void trackReturn(String billNo, String medId, String medName, String batch, double qty) {
      final b = billNo.trim().toUpperCase();
      if (b.isEmpty) return;
      final mKey = medId.trim().isNotEmpty ? medId.trim() : medName.trim().toLowerCase();
      final key = "$b||$mKey||${_batchKey(batch)}";
      returnedByKey[key] = (returnedByKey[key] ?? 0.0) + qty;
    }

    if (isSale) {
      for (final sr in saleReturns) {
        if (sr.isDeleted == 1 || sr.status == "Cancelled") continue;
        if (excludeNoteId != null && excludeNoteId.isNotEmpty && sr.id == excludeNoteId) continue;
        if (!_matchesParty(targetId: partyId, targetName: partyName, docPartyId: sr.partyId, docPartyName: sr.partyName)) continue;
        for (final it in sr.items) {
          trackReturn(it.origBillNo.trim().isNotEmpty ? it.origBillNo : sr.origBillNo, it.medicineID, it.name, it.batch, it.qty);
        }
      }
    } else {
      for (final pr in purchaseReturns) {
        if (pr.isDeleted == 1 || pr.status == "Cancelled") continue;
        if (excludeNoteId != null && excludeNoteId.isNotEmpty && pr.id == excludeNoteId) continue;
        if (!_matchesParty(targetId: partyId, targetName: partyName, docPartyId: pr.partyId, docPartyName: pr.distributorName)) continue;
        for (final it in pr.items) {
          trackReturn(it.origBillNo.trim().isNotEmpty ? it.origBillNo : pr.origBillNo, it.medicineID, it.name, it.batch, it.qty);
        }
      }
    }

    for (final it in currentCartItems) {
      trackReturn(
        (it.origBillNo ?? '').toString(),
        (it.medicineID ?? '').toString(),
        (it.name ?? '').toString(),
        (it.batch ?? '').toString(),
        ((it.qty ?? 0) as num).toDouble(),
      );
    }

    final List<ReturnRecentBill> bills = [];
    if (isSale) {
      final filtered = sales
          .where((s) =>
              s.isDeleted != 1 &&
              s.status == "Active" &&
              _matchesParty(
                targetId: partyId,
                targetName: partyName,
                docPartyId: s.partyId,
                docPartyName: s.partyName,
              ))
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      for (final s in filtered.take(limit)) {
        final lines = s.items.map((it) {
          final mKey = it.medicineID.trim().isNotEmpty ? it.medicineID.trim() : it.name.trim().toLowerCase();
          final key = "${s.billNo.trim().toUpperCase()}||$mKey||${_batchKey(it.batch)}";
          return ReturnRecentBillLine(
            medicineID: it.medicineID,
            name: it.name,
            packing: it.packing,
            hsn: it.hsn,
            batch: it.batch,
            exp: it.exp,
            billedQty: it.qty,
            billedFreeQty: it.freeQty,
            alreadyReturnedQty: returnedByKey[key] ?? 0.0,
            rate: it.rate,
            mrp: it.mrp,
            gstRate: it.gstRate,
            discountPer: it.discountPer,
            discountRupees: it.discountRupees,
            rateA: 0.0,
            rateB: 0.0,
            rateC: 0.0,
            appliedRateType: it.appliedRateType,
            rateCFormula: it.rateCFormula,
            billNo: s.billNo,
            date: s.date,
          );
        }).toList();
        bills.add(ReturnRecentBill(
          billNo: s.billNo,
          date: s.date,
          totalAmount: s.totalAmount,
          lines: lines,
        ));
      }
    } else {
      final filtered = purchases
          .where((p) =>
              p.isDeleted != 1 &&
              p.gstStatus != "Cancelled" &&
              p.gstStatus != "Deleted" &&
              _matchesParty(
                targetId: partyId,
                targetName: partyName,
                docPartyId: p.partyId,
                docPartyName: p.distributorName,
              ))
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      for (final p in filtered.take(limit)) {
        final lines = p.items.map((it) {
          final mKey = it.medicineID.trim().isNotEmpty ? it.medicineID.trim() : it.name.trim().toLowerCase();
          final key = "${p.billNo.trim().toUpperCase()}||$mKey||${_batchKey(it.batch)}";
          return ReturnRecentBillLine(
            medicineID: it.medicineID,
            name: it.name,
            packing: it.packing,
            hsn: it.hsn,
            batch: it.batch,
            exp: it.exp,
            billedQty: it.qty,
            billedFreeQty: it.freeQty,
            alreadyReturnedQty: returnedByKey[key] ?? 0.0,
            rate: it.purchaseRate,
            mrp: it.mrp,
            gstRate: it.gstRate,
            discountPer: it.discountPer,
            discountRupees: it.discountRupees,
            rateA: it.rateA,
            rateB: it.rateB,
            rateC: it.rateC,
            appliedRateType: it.appliedRateType,
            rateCFormula: it.rateCFormula,
            billNo: p.billNo,
            internalNo: p.internalNo,
            date: p.date,
          );
        }).toList();
        bills.add(ReturnRecentBill(
          billNo: p.billNo,
          internalNo: p.internalNo,
          date: p.date,
          totalAmount: p.totalAmount,
          lines: lines,
        ));
      }
    }
    return bills;
  }

  static BillItem buildBillItemFromLine({
    required Medicine med,
    required ReturnHistoryInvoiceLine line,
    required double qty,
    double freeQty = 0.0,
    required int srNo,
    required bool isLocal,
    required bool isBreakage,
    required bool isCommercial,
    String? idOverride,
  }) {
    final double discPer = line.effectiveDiscPer;
    final double gross = qty * line.rate;
    final double discRupees = discPer > 0
        ? double.parse((gross * (discPer / 100.0)).toStringAsFixed(2))
        : 0.0;
    final double taxable = (gross - discRupees) > 0 ? (gross - discRupees) : 0.0;
    final double gstRate = line.gstRate;
    final double tax = isCommercial ? 0.0 : taxable * (gstRate / 100.0);
    final double total = double.parse((taxable + tax).toStringAsFixed(2));
    return BillItem(
      id: idOverride ?? "CN-${DateTime.now().microsecondsSinceEpoch}-$srNo",
      srNo: srNo,
      medicineID: med.id,
      name: med.name,
      packing: line.packing.isNotEmpty ? line.packing : med.packing,
      batch: line.batch,
      exp: line.exp,
      hsn: line.hsn.isNotEmpty ? line.hsn : med.hsnCode,
      mrp: line.mrp > 0 ? line.mrp : med.mrp,
      qty: qty,
      freeQty: freeQty,
      rate: line.rate,
      gstRate: gstRate,
      cgst: isLocal ? tax / 2.0 : 0.0,
      sgst: isLocal ? tax / 2.0 : 0.0,
      igst: isLocal ? 0.0 : tax,
      total: total,
      discountRupees: discRupees,
      discountPer: discPer,
      isBreakage: isBreakage,
      appliedRateType: line.appliedRateType,
      rateCFormula: line.rateCFormula,
      origBillNo: line.billNo,
      origBillDate: line.date,
      isManualOrigin: line.billNo.trim().isEmpty,
    );
  }

  static PurchaseItem buildPurchaseItemFromLine({
    required Medicine med,
    required ReturnHistoryInvoiceLine line,
    required double qty,
    double freeQty = 0.0,
    required int srNo,
    required bool isBreakage,
    required bool isCommercial,
    String? idOverride,
  }) {
    final double discPer = line.effectiveDiscPer;
    final double gross = qty * line.rate;
    final double discRupees = discPer > 0
        ? double.parse((gross * (discPer / 100.0)).toStringAsFixed(2))
        : 0.0;
    final double taxable = (gross - discRupees) > 0 ? (gross - discRupees) : 0.0;
    final double gstRate = line.gstRate;
    final double tax = isCommercial ? 0.0 : taxable * (gstRate / 100.0);
    final double total = double.parse((taxable + tax).toStringAsFixed(2));
    return PurchaseItem(
      id: idOverride ?? "DN-${DateTime.now().microsecondsSinceEpoch}-$srNo",
      srNo: srNo,
      medicineID: med.id,
      name: med.name,
      packing: line.packing.isNotEmpty ? line.packing : med.packing,
      batch: line.batch,
      exp: line.exp,
      hsn: line.hsn.isNotEmpty ? line.hsn : med.hsnCode,
      mrp: line.mrp > 0 ? line.mrp : med.mrp,
      qty: qty,
      freeQty: freeQty,
      purchaseRate: line.rate,
      gstRate: gstRate,
      total: total,
      rateA: line.rateA > 0 ? line.rateA : med.rateA,
      rateB: line.rateB > 0 ? line.rateB : med.rateB,
      rateC: line.rateC > 0 ? line.rateC : med.rateC,
      discountPer: discPer,
      discountRupees: discRupees,
      isBreakage: isBreakage,
      appliedRateType: line.appliedRateType,
      rateCFormula: line.rateCFormula,
      origBillNo: line.billNo,
      origBillDate: line.date,
      isManualOrigin: line.billNo.trim().isEmpty,
    );
  }

  static BillItem recalcBillItemQty(
    BillItem item, {
    required double qty,
    double? freeQty,
    required bool isLocal,
    required bool isCommercial,
  }) {
    final double safeQty = qty < 0 ? 0.0 : qty;
    final double gross = safeQty * item.rate;
    final double discPer = item.discountPer > 0
        ? item.discountPer
        : (item.qty > 0 && item.discountRupees > 0
            ? ((item.discountRupees / (item.qty * item.rate)) * 100.0)
            : 0.0);
    final double discRupees = discPer > 0
        ? double.parse((gross * (discPer / 100.0)).toStringAsFixed(2))
        : 0.0;
    final double taxable = (gross - discRupees) > 0 ? (gross - discRupees) : 0.0;
    final double tax = isCommercial ? 0.0 : taxable * (item.gstRate / 100.0);
    return BillItem(
      id: item.id,
      srNo: item.srNo,
      medicineID: item.medicineID,
      name: item.name,
      packing: item.packing,
      batch: item.batch,
      exp: item.exp,
      hsn: item.hsn,
      mrp: item.mrp,
      qty: safeQty,
      freeQty: freeQty ?? item.freeQty,
      rate: item.rate,
      gstRate: item.gstRate,
      cgst: isLocal ? tax / 2.0 : 0.0,
      sgst: isLocal ? tax / 2.0 : 0.0,
      igst: isLocal ? 0.0 : tax,
      total: double.parse((taxable + tax).toStringAsFixed(2)),
      discountRupees: discRupees,
      discountPer: item.discountPer,
      isBreakage: item.isBreakage,
      sourceChallanNo: item.sourceChallanNo,
      sourceChallanId: item.sourceChallanId,
      appliedRateType: item.appliedRateType,
      rateCFormula: item.rateCFormula,
      origBillNo: item.origBillNo,
      origBillDate: item.origBillDate,
      isManualOrigin: item.isManualOrigin,
    );
  }

  static PurchaseItem recalcPurchaseItemQty(
    PurchaseItem item, {
    required double qty,
    double? freeQty,
    required bool isCommercial,
  }) {
    final double safeQty = qty < 0 ? 0.0 : qty;
    final double gross = safeQty * item.purchaseRate;
    final double discPer = item.discountPer > 0
        ? item.discountPer
        : (item.qty > 0 && item.discountRupees > 0
            ? ((item.discountRupees / (item.qty * item.purchaseRate)) * 100.0)
            : 0.0);
    final double discRupees = discPer > 0
        ? double.parse((gross * (discPer / 100.0)).toStringAsFixed(2))
        : 0.0;
    final double taxable = (gross - discRupees) > 0 ? (gross - discRupees) : 0.0;
    final double tax = isCommercial ? 0.0 : taxable * (item.gstRate / 100.0);
    return PurchaseItem(
      id: item.id,
      srNo: item.srNo,
      medicineID: item.medicineID,
      name: item.name,
      packing: item.packing,
      batch: item.batch,
      exp: item.exp,
      hsn: item.hsn,
      mrp: item.mrp,
      qty: safeQty,
      freeQty: freeQty ?? item.freeQty,
      purchaseRate: item.purchaseRate,
      gstRate: item.gstRate,
      total: double.parse((taxable + tax).toStringAsFixed(2)),
      rateA: item.rateA,
      rateB: item.rateB,
      rateC: item.rateC,
      discountPer: item.discountPer,
      discountRupees: discRupees,
      isBreakage: item.isBreakage,
      sourceChallanNo: item.sourceChallanNo,
      sourceChallanId: item.sourceChallanId,
      appliedRateType: item.appliedRateType,
      rateCFormula: item.rateCFormula,
      origBillNo: item.origBillNo,
      origBillDate: item.origBillDate,
      isManualOrigin: item.isManualOrigin,
    );
  }
}
