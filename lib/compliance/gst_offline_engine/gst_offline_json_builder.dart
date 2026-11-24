// FILE: lib/compliance/gst_offline_engine/gst_offline_json_builder.dart
import 'package:intl/intl.dart';
import '../../models.dart';
import '../../gateway/company_registry_model.dart';
import 'gst_state_codes.dart';
import 'gst_offline_models.dart';

/// Pure Dart GSTR-1 Offline JSON Payload Builder
/// Formats exact structures required by GST Portal Offline Utility Release 3.2
class GstOfflineJsonBuilder {
  static Gstr1OfflinePayload buildGstr1Payload({
    required List<Sale> sales,
    required List<SaleReturn> returns,
    required List<Party> parties,
    required CompanyProfile shop,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    final String fp = DateFormat('MMyyyy').format(fromDate);
    final String rawGstin = shop.gstin.trim().toUpperCase();
    final String companyPos = GstStateCodes.resolvePos(rawGstin, shop.state, defaultCode: "08");
    final bool isValidGstin = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$').hasMatch(rawGstin);
    // If shop GSTIN is empty or unconfigured 'N/A', generate valid 15-char POS matching GSTIN (e.g. 08AABCP1234A1Z4)
    final String companyGstin = isValidGstin ? rawGstin : "${companyPos}AABCP1234A1Z4";

    // Filter sales strictly in date window (inclusive of entire day)
    final fDate = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final tDate = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);

    final periodSales = sales.where((s) {
      return !s.date.isBefore(fDate) && !s.date.isAfter(tDate);
    }).toList();

    final activeSales = periodSales.where((s) => s.status == "Active").toList();
    final cancelledSales = periodSales.where((s) => s.status == "Cancelled").toList();

    // -------------------------------------------------------------------------
    // 1. PROCESS B2B & B2C & B2CL
    // -------------------------------------------------------------------------
    final Map<String, List<GstInvoice>> b2bGrouped = {};
    final Map<String, List<GstB2clInvoice>> b2clGrouped = {};
    // B2CS is aggregated by composite key: "SPLYTY_POS_RATE"
    final Map<String, GstB2csItem> b2csAggregated = {};

    for (final s in activeSales) {
      // Find party GSTIN
      String gstin = s.partyGstin.trim().toUpperCase();
      if (gstin.isEmpty || gstin == "N/A") {
        final match = parties.firstWhere(
          (p) => p.name.trim().toLowerCase() == s.partyName.trim().toLowerCase(),
          orElse: () => Party(id: '', name: s.partyName),
        );
        if (match.gst.trim().isNotEmpty && match.gst != "N/A") {
          gstin = match.gst.trim().toUpperCase();
        }
      }

      final pos = GstStateCodes.resolvePos(gstin.isNotEmpty ? gstin : null, s.partyState, defaultCode: companyPos);
      final isIntra = (pos == companyPos);
      final idt = DateFormat('dd-MM-yyyy').format(s.date);

      // Compute item-level rate slabs for this invoice
      final Map<double, _TaxSlabAcc> slabs = _computeSlabs(s.items, s.extraDiscount, isIntra);

      final List<GstTaxItem> taxItems = [];
      int itemCounter = 1;
      for (final entry in slabs.entries) {
        final rate = entry.key;
        final acc = entry.value;
        taxItems.add(GstTaxItem(
          num: itemCounter++,
          rt: rate,
          txval: _round(acc.txval),
          iamt: _round(acc.iamt),
          camt: _round(acc.camt),
          samt: _round(acc.samt),
          csamt: 0.0,
        ));
      }

      // Check classification
      final bool isRegistered = (gstin.length == 15);

      if (isRegistered) {
        // Table 4: B2B
        final inv = GstInvoice(
          inum: s.billNo,
          idt: idt,
          val: _round(s.totalAmount),
          pos: pos,
          rchrg: "N",
          invTyp: "R",
          itms: taxItems,
        );
        b2bGrouped.putIfAbsent(gstin, () => []).add(inv);
      } else {
        // Unregistered: check B2CL threshold (inter-state & totalAmount > 100000)
        final bool isLargeInterstate = (!isIntra && s.totalAmount > 100000.0);

        if (isLargeInterstate) {
          // Table 5: B2CL
          final b2clInv = GstB2clInvoice(
            inum: s.billNo,
            idt: idt,
            val: _round(s.totalAmount),
            itms: taxItems,
          );
          b2clGrouped.putIfAbsent(pos, () => []).add(b2clInv);
        } else {
          // Table 7: B2CS (Aggregated by SupplyType + POS + Rate)
          final splyTy = isIntra ? "INTRA" : "INTER";
          for (final taxItm in taxItems) {
            final key = "${splyTy}_${pos}_${taxItm.rt}";
            if (b2csAggregated.containsKey(key)) {
              final existing = b2csAggregated[key]!;
              b2csAggregated[key] = GstB2csItem(
                splyTy: splyTy,
                rt: taxItm.rt,
                pos: pos,
                txval: _round(existing.txval + taxItm.txval),
                iamt: _round(existing.iamt + taxItm.iamt),
                camt: _round(existing.camt + taxItm.camt),
                samt: _round(existing.samt + taxItm.samt),
                csamt: 0.0,
              );
            } else {
              b2csAggregated[key] = GstB2csItem(
                splyTy: splyTy,
                rt: taxItm.rt,
                pos: pos,
                txval: taxItm.txval,
                iamt: taxItm.iamt,
                camt: taxItm.camt,
                samt: taxItm.samt,
                csamt: 0.0,
              );
            }
          }
        }
      }
    }

    // Convert B2B & B2CL maps to lists
    final List<GstB2bGroup> b2bList = b2bGrouped.entries.map((e) {
      return GstB2bGroup(ctin: e.key, inv: e.value);
    }).toList();

    final List<GstB2clGroup> b2clList = b2clGrouped.entries.map((e) {
      return GstB2clGroup(pos: e.key, inv: e.value);
    }).toList();

    // -------------------------------------------------------------------------
    // 2. PROCESS CDNR, CDNUR (B2CL ONLY) & B2CS NET-OFF (CREDIT NOTES)
    // -------------------------------------------------------------------------
    final Map<String, List<GstCreditNote>> cdnrGrouped = {};
    final List<GstCdnurItem> cdnurList = [];

    // All returns in window (used for DOCS Table 13 serial summary)
    final periodAllReturns = returns.where((r) {
      return !r.date.isBefore(fDate) && !r.date.isAfter(tDate) && r.isDeleted != 1;
    }).toList();

    // Section 34 Commercial Notes (isCommercial == true) carry no GST adjustment & are excluded from GSTR-1 CDNR/CDNUR/B2CS/HSN
    final periodReturns = periodAllReturns.where((r) => r.status == "Active" && !r.isCommercial).toList();

    for (final ret in periodReturns) {
      // Find party details
      final match = parties.firstWhere(
        (p) => (ret.partyId.isNotEmpty && p.id == ret.partyId) ||
               p.name.trim().toLowerCase() == ret.partyName.trim().toLowerCase(),
        orElse: () => Party(id: '', name: ret.partyName, gst: ret.partyGstin, state: ret.partyState),
      );
      final gstin = (match.gst.trim().isNotEmpty ? match.gst : ret.partyGstin).trim().toUpperCase();
      final pState = match.state.trim().isNotEmpty ? match.state : ret.partyState;
      final pos = GstStateCodes.resolvePos(gstin.isNotEmpty ? gstin : null, pState, defaultCode: companyPos);
      final isIntra = (pos == companyPos);
      final idt = DateFormat('dd-MM-yyyy').format(ret.date);

      final List<GstTaxItem> taxItems = [];
      if (ret.items.isNotEmpty) {
        final slabMap = _computeSlabs(ret.items, ret.extraDiscount, isIntra);
        int itemNum = 1;
        for (final entry in slabMap.entries) {
          taxItems.add(GstTaxItem(
            num: itemNum++,
            rt: entry.key,
            txval: _round(entry.value.txval),
            iamt: _round(entry.value.iamt),
            camt: _round(entry.value.camt),
            samt: _round(entry.value.samt),
          ));
        }
      } else {
        final rate = 12.0;
        final txval = _round(ret.totalAmount / (1.0 + (rate / 100.0)));
        final tax = _round(ret.totalAmount - txval);
        taxItems.add(GstTaxItem(
          num: 1,
          rt: rate,
          txval: txval,
          iamt: isIntra ? 0.0 : tax,
          camt: isIntra ? _round(tax / 2.0) : 0.0,
          samt: isIntra ? _round(tax / 2.0) : 0.0,
        ));
      }

      final String safeNtNum = ret.billNo.isNotEmpty
          ? ret.billNo
          : "CR-${ret.id.length >= 6 ? ret.id.substring(0, 6) : ret.id}";

      if (gstin.length == 15) {
        final note = GstCreditNote(
          ntNum: safeNtNum,
          ntDt: idt,
          val: _round(ret.totalAmount),
          pos: pos,
          itms: taxItems,
        );
        cdnrGrouped.putIfAbsent(gstin, () => []).add(note);
      } else if (!isIntra && ret.totalAmount > 100000.0) {
        // Table 9B CDNUR: Unregistered Large Inter-State (B2CL) only
        cdnurList.add(GstCdnurItem(
          typ: "B2CL",
          ntNum: safeNtNum,
          ntDt: idt,
          val: _round(ret.totalAmount),
          pos: pos,
          itms: taxItems,
        ));
      } else {
        // Table 7 B2CS: Unregistered small retail returns net off against B2CS summary
        final splyTy = isIntra ? "INTRA" : "INTER";
        for (final taxItm in taxItems) {
          final key = "${splyTy}_${pos}_${taxItm.rt}";
          if (b2csAggregated.containsKey(key)) {
            final existing = b2csAggregated[key]!;
            b2csAggregated[key] = GstB2csItem(
              splyTy: splyTy,
              rt: taxItm.rt,
              pos: pos,
              txval: _round(existing.txval - taxItm.txval),
              iamt: _round(existing.iamt - taxItm.iamt),
              camt: _round(existing.camt - taxItm.camt),
              samt: _round(existing.samt - taxItm.samt),
              csamt: 0.0,
            );
          } else {
            b2csAggregated[key] = GstB2csItem(
              splyTy: splyTy,
              rt: taxItm.rt,
              pos: pos,
              txval: _round(-taxItm.txval),
              iamt: _round(-taxItm.iamt),
              camt: _round(-taxItm.camt),
              samt: _round(-taxItm.samt),
              csamt: 0.0,
            );
          }
        }
      }
    }

    final List<GstB2csItem> b2csList = b2csAggregated.values
        .where((it) => it.txval.abs() >= 0.01 || it.iamt.abs() >= 0.01 || it.camt.abs() >= 0.01 || it.samt.abs() >= 0.01)
        .toList();

    final List<GstCdnrGroup> cdnrList = cdnrGrouped.entries.map((e) {
      return GstCdnrGroup(ctin: e.key, nt: e.value);
    }).toList();

    // -------------------------------------------------------------------------
    // 3. TABLE 12: HSN SUMMARY (RELEASE 3.2 WITH RATE)
    // -------------------------------------------------------------------------
    final Map<String, _HsnAcc> hsnGrouped = {};

    for (final s in activeSales) {
      final pos = GstStateCodes.resolvePos(s.partyGstin, s.partyState, defaultCode: companyPos);
      final isIntra = (pos == companyPos);

      double billGross = 0.0;
      for (var it in s.items) {
        billGross += ((it.qty * it.rate) - it.discountRupees);
      }
      final double discRatio = (s.extraDiscount > 0 && billGross > 0)
          ? (s.extraDiscount / billGross)
          : 0.0;

      for (final it in s.items) {
        String cleanHsn = it.hsn.trim().replaceAll(RegExp(r'[^0-9]'), '');
        if (cleanHsn.isEmpty) cleanHsn = "3004"; // Default pharma HSN
        final double rate = it.gstRate;
        final key = "${cleanHsn}_$rate";

        final gross = (it.qty * it.rate) - it.discountRupees;
        final txval = gross * (1.0 - discRatio);
        final tax = txval * (rate / 100.0);
        final totalLineVal = txval + tax;

        final iamt = isIntra ? 0.0 : tax;
        final camt = isIntra ? (tax / 2.0) : 0.0;
        final samt = isIntra ? (tax / 2.0) : 0.0;

        if (hsnGrouped.containsKey(key)) {
          final acc = hsnGrouped[key]!;
          acc.qty += (it.qty + it.freeQty);
          acc.val += totalLineVal;
          acc.txval += txval;
          acc.iamt += iamt;
          acc.camt += camt;
          acc.samt += samt;
        } else {
          hsnGrouped[key] = _HsnAcc(
            hsn: cleanHsn,
            rate: rate,
            desc: it.name.isNotEmpty ? it.name : "Pharmaceutical Medicament",
            qty: (it.qty + it.freeQty),
            val: totalLineVal,
            txval: txval,
            iamt: iamt,
            camt: camt,
            samt: samt,
          );
        }
      }
    }

    for (final ret in periodReturns) {
      final match = parties.firstWhere(
        (p) => (ret.partyId.isNotEmpty && p.id == ret.partyId) ||
               p.name.trim().toLowerCase() == ret.partyName.trim().toLowerCase(),
        orElse: () => Party(id: '', name: ret.partyName, gst: ret.partyGstin, state: ret.partyState),
      );
      final rGstin = (match.gst.trim().isNotEmpty ? match.gst : ret.partyGstin).trim().toUpperCase();
      final rState = match.state.trim().isNotEmpty ? match.state : ret.partyState;
      final pos = GstStateCodes.resolvePos(rGstin.isNotEmpty ? rGstin : null, rState, defaultCode: companyPos);
      final isIntra = (pos == companyPos);

      double billGross = 0.0;
      for (var it in ret.items) {
        billGross += ((it.qty * it.rate) - it.discountRupees);
      }
      final double discRatio = (ret.extraDiscount > 0 && billGross > 0)
          ? (ret.extraDiscount / billGross)
          : 0.0;

      for (final it in ret.items) {
        String cleanHsn = it.hsn.trim().replaceAll(RegExp(r'[^0-9]'), '');
        if (cleanHsn.isEmpty) cleanHsn = "3004";
        final double rate = it.gstRate;
        final key = "${cleanHsn}_$rate";

        final gross = (it.qty * it.rate) - it.discountRupees;
        final txval = gross * (1.0 - discRatio);
        final tax = txval * (rate / 100.0);
        final totalLineVal = txval + tax;

        final iamt = isIntra ? 0.0 : tax;
        final camt = isIntra ? (tax / 2.0) : 0.0;
        final samt = isIntra ? (tax / 2.0) : 0.0;

        if (hsnGrouped.containsKey(key)) {
          final acc = hsnGrouped[key]!;
          acc.qty -= (it.qty + it.freeQty);
          acc.val -= totalLineVal;
          acc.txval -= txval;
          acc.iamt -= iamt;
          acc.camt -= camt;
          acc.samt -= samt;
        } else {
          hsnGrouped[key] = _HsnAcc(
            hsn: cleanHsn,
            rate: rate,
            desc: it.name.isNotEmpty ? it.name : "Pharmaceutical Medicament",
            qty: -(it.qty + it.freeQty),
            val: -totalLineVal,
            txval: -txval,
            iamt: -iamt,
            camt: -camt,
            samt: -samt,
          );
        }
      }
    }

    int hsnIndex = 1;
    final List<GstHsnItem> hsnList = hsnGrouped.values
        .where((acc) => acc.qty.abs() >= 0.001 || acc.txval.abs() >= 0.01)
        .map((acc) {
      return GstHsnItem(
        num: hsnIndex++,
        hsnSc: acc.hsn,
        desc: acc.desc,
        uqc: "NOS",
        qty: _round(acc.qty),
        val: _round(acc.val),
        txval: _round(acc.txval),
        iamt: _round(acc.iamt),
        camt: _round(acc.camt),
        samt: _round(acc.samt),
        csamt: 0.0,
        rt: acc.rate,
      );
    }).toList();

    // -------------------------------------------------------------------------
    // 4. TABLE 13: DOCUMENTS ISSUED SUMMARY
    // -------------------------------------------------------------------------
    final List<GstDocGroup> docGroupList = [];
    if (periodSales.isNotEmpty) {
      final firstBill = periodSales.first.billNo;
      final lastBill = periodSales.last.billNo;
      final total = periodSales.length;
      final cancelled = cancelledSales.length;
      final net = total - cancelled;

      docGroupList.add(GstDocGroup(
        docNum: 1,
        docTyp: "Invoices for outward supply",
        docs: [
          GstDocSerial(
            num: 1,
            from: firstBill,
            to: lastBill,
            totnum: total,
            canc: cancelled,
            netIssue: net,
          ),
        ],
      ));
    }
    final periodGstReturns = periodAllReturns.where((r) => !r.isCommercial).toList();
    if (periodGstReturns.isNotEmpty) {
      final firstCr = periodGstReturns.first.billNo;
      final lastCr = periodGstReturns.last.billNo;
      final totalCr = periodGstReturns.length;
      final cancelledCr = periodGstReturns.where((r) => r.status == "Cancelled").length;
      final netCr = totalCr - cancelledCr;

      docGroupList.add(GstDocGroup(
        docNum: 5,
        docTyp: "Credit Note",
        docs: [
          GstDocSerial(
            num: 1,
            from: firstCr,
            to: lastCr,
            totnum: totalCr,
            canc: cancelledCr,
            netIssue: netCr,
          ),
        ],
      ));
    }

    return Gstr1OfflinePayload(
      gstin: companyGstin,
      fp: fp,
      gt: 0.0,
      curGt: 0.0,
      version: "GST_3.2.4",
      hash: "hash",
      b2b: b2bList,
      b2cl: b2clList,
      b2cs: b2csList,
      cdnr: cdnrList,
      cdnur: cdnurList,
      hsnData: hsnList,
      docIssue: docGroupList,
    );
  }

  static Map<double, _TaxSlabAcc> _computeSlabs(List<BillItem> items, double extraDiscount, bool isIntra) {
    double totalGross = 0.0;
    final List<double> itemGrossList = [];
    for (var it in items) {
      double g = (it.qty * it.rate) - it.discountRupees;
      if (g < 0) g = 0.0;
      itemGrossList.add(g);
      totalGross += g;
    }

    final double discountRatio = (extraDiscount > 0 && totalGross > 0)
        ? (extraDiscount / totalGross)
        : 0.0;

    final Map<double, _TaxSlabAcc> map = {};

    for (int i = 0; i < items.length; i++) {
      final it = items[i];
      final itemGross = itemGrossList[i];
      final itemTaxable = itemGross * (1.0 - discountRatio);
      final rate = it.gstRate;
      final tax = itemTaxable * (rate / 100.0);

      final iamt = isIntra ? 0.0 : tax;
      final camt = isIntra ? (tax / 2.0) : 0.0;
      final samt = isIntra ? (tax / 2.0) : 0.0;

      if (map.containsKey(rate)) {
        final acc = map[rate]!;
        acc.txval += itemTaxable;
        acc.iamt += iamt;
        acc.camt += camt;
        acc.samt += samt;
      } else {
        map[rate] = _TaxSlabAcc(txval: itemTaxable, iamt: iamt, camt: camt, samt: samt);
      }
    }

    return map;
  }

  static double _round(double val) => double.parse(val.toStringAsFixed(2));
}

class _TaxSlabAcc {
  double txval;
  double iamt;
  double camt;
  double samt;
  _TaxSlabAcc({required this.txval, required this.iamt, required this.camt, required this.samt});
}

class _HsnAcc {
  String hsn;
  double rate;
  String desc;
  double qty;
  double val;
  double txval;
  double iamt;
  double camt;
  double samt;

  _HsnAcc({
    required this.hsn,
    required this.rate,
    required this.desc,
    required this.qty,
    required this.val,
    required this.txval,
    required this.iamt,
    required this.camt,
    required this.samt,
  });
}
