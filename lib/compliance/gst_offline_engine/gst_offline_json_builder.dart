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
    final String companyGstin = shop.gstin.trim().toUpperCase();
    final String companyPos = GstStateCodes.resolvePos(companyGstin, shop.state, defaultCode: "08");

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

    final List<GstB2csItem> b2csList = b2csAggregated.values.toList();

    // -------------------------------------------------------------------------
    // 2. PROCESS CDNR & CDNUR (CREDIT NOTES FROM SALE RETURNS)
    // -------------------------------------------------------------------------
    final Map<String, List<GstCreditNote>> cdnrGrouped = {};
    final List<GstCdnurItem> cdnurList = [];

    final periodReturns = returns.where((r) {
      return !r.date.isBefore(fDate) && !r.date.isAfter(tDate) && r.status == "Active";
    }).toList();

    for (final ret in periodReturns) {
      // Find party details
      final match = parties.firstWhere(
        (p) => p.name.trim().toLowerCase() == ret.partyName.trim().toLowerCase(),
        orElse: () => Party(id: '', name: ret.partyName),
      );
      final gstin = match.gst.trim().toUpperCase();
      final pos = GstStateCodes.resolvePos(gstin.isNotEmpty ? gstin : null, match.state, defaultCode: companyPos);
      final isIntra = (pos == companyPos);
      final idt = DateFormat('dd-MM-yyyy').format(ret.date);

      // Estimate taxable vs tax from return totalAmount (defaulting to standard 12% if no items breakdown)
      final rate = 12.0;
      final txval = _round(ret.totalAmount / (1.0 + (rate / 100.0)));
      final tax = _round(ret.totalAmount - txval);
      final iamt = isIntra ? 0.0 : tax;
      final camt = isIntra ? _round(tax / 2.0) : 0.0;
      final samt = isIntra ? _round(tax / 2.0) : 0.0;

      final taxItem = GstTaxItem(
        num: 1,
        rt: rate,
        txval: txval,
        iamt: iamt,
        camt: camt,
        samt: samt,
      );

      if (gstin.length == 15) {
        final note = GstCreditNote(
          ntNum: ret.billNo.isNotEmpty ? ret.billNo : "CR-${ret.id.substring(0, 6)}",
          ntDt: idt,
          val: _round(ret.totalAmount),
          pos: pos,
          itms: [taxItem],
        );
        cdnrGrouped.putIfAbsent(gstin, () => []).add(note);
      } else {
        cdnurList.add(GstCdnurItem(
          ntNum: ret.billNo.isNotEmpty ? ret.billNo : "CR-${ret.id.substring(0, 6)}",
          ntDt: idt,
          val: _round(ret.totalAmount),
          pos: pos,
          itms: [taxItem],
        ));
      }
    }

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

    int hsnIndex = 1;
    final List<GstHsnItem> hsnList = hsnGrouped.values.map((acc) {
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

    return Gstr1OfflinePayload(
      gstin: companyGstin.isNotEmpty ? companyGstin : "08AAAAA0000A1Z5",
      fp: fp,
      gt: 0.0,
      curGt: 0.0,
      version: "GST_3.1.4",
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
