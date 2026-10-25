// FILE: lib/compliance/gst_offline_engine/gst_offline_csv_builder.dart
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import '../../models.dart';
import '../../gateway/company_registry_model.dart';
import 'gst_state_codes.dart';

/// Builds Official CSVs matching GST Offline Utility Release 3.2 / V2.2 Specification
class GstOfflineCsvBuilder {
  /// Builds official b2b,sez,de.csv
  static String buildB2bCsv({
    required List<Sale> sales,
    required List<Party> parties,
    required CompanyProfile shop,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    final companyPos = GstStateCodes.resolvePos(shop.gstin, shop.state, defaultCode: "08");
    final fDate = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final tDate = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);

    final List<List<dynamic>> rows = [
      [
        "GSTIN/UIN of Recipient",
        "Receiver Name",
        "Invoice Number",
        "Invoice date",
        "Invoice Value",
        "Place Of Supply",
        "Reverse Charge",
        "Applicable % of Tax Rate",
        "Invoice Type",
        "E-Commerce GSTIN",
        "Rate",
        "Taxable Value",
        "Cess Amount"
      ]
    ];

    final b2bSales = sales.where((s) {
      final inWindow = !s.date.isBefore(fDate) && !s.date.isAfter(tDate);
      if (!inWindow || s.status != "Active") return false;
      return s.partyGstin.trim().length == 15;
    }).toList();

    for (final s in b2bSales) {
      final pos = GstStateCodes.resolvePos(s.partyGstin, s.partyState, defaultCode: companyPos);
      final posLabel = GstStateCodes.getPosCsvLabel(pos);
      final idt = DateFormat('dd-MMM-yy').format(s.date); // e.g. 14-Jul-24 or 14-Jul-17

      // Group items by rate
      final Map<double, double> rateTaxable = {};
      double gross = 0.0;
      for (var it in s.items) gross += ((it.qty * it.rate) - it.discountRupees);
      final discRatio = (s.extraDiscount > 0 && gross > 0) ? (s.extraDiscount / gross) : 0.0;

      for (var it in s.items) {
        final tx = ((it.qty * it.rate) - it.discountRupees) * (1.0 - discRatio);
        rateTaxable[it.gstRate] = (rateTaxable[it.gstRate] ?? 0.0) + tx;
      }

      for (final entry in rateTaxable.entries) {
        rows.add([
          s.partyGstin.trim().toUpperCase(),
          s.partyName,
          s.billNo,
          idt,
          s.totalAmount.toStringAsFixed(2),
          posLabel,
          "N",
          "",
          "Regular B2B",
          "",
          entry.key.toStringAsFixed(0),
          entry.value.toStringAsFixed(2),
          "0.00"
        ]);
      }
    }

    return const ListToCsvConverter().convert(rows);
  }

  /// Builds official b2cs.csv
  static String buildB2csCsv({
    required List<Sale> sales,
    required CompanyProfile shop,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    final companyPos = GstStateCodes.resolvePos(shop.gstin, shop.state, defaultCode: "08");
    final fDate = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final tDate = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);

    final List<List<dynamic>> rows = [
      [
        "Type",
        "Place Of Supply",
        "Rate",
        "Applicable % of Tax Rate",
        "Taxable Value",
        "Cess Amount",
        "E-Commerce GSTIN"
      ]
    ];

    final Map<String, double> grouped = {};

    for (final s in sales) {
      final inWindow = !s.date.isBefore(fDate) && !s.date.isAfter(tDate);
      if (!inWindow || s.status != "Active" || s.partyGstin.trim().length == 15) continue;

      final pos = GstStateCodes.resolvePos(null, s.partyState, defaultCode: companyPos);
      final isIntra = (pos == companyPos);
      if (!isIntra && s.totalAmount > 100000.0) continue; // Large B2C belongs to B2CL

      double gross = 0.0;
      for (var it in s.items) gross += ((it.qty * it.rate) - it.discountRupees);
      final discRatio = (s.extraDiscount > 0 && gross > 0) ? (s.extraDiscount / gross) : 0.0;

      for (var it in s.items) {
        final tx = ((it.qty * it.rate) - it.discountRupees) * (1.0 - discRatio);
        final key = "${pos}_${it.gstRate}";
        grouped[key] = (grouped[key] ?? 0.0) + tx;
      }
    }

    for (final entry in grouped.entries) {
      final parts = entry.key.split('_');
      final pos = parts[0];
      final rate = double.tryParse(parts[1]) ?? 12.0;
      rows.add([
        "OE",
        GstStateCodes.getPosCsvLabel(pos),
        rate.toStringAsFixed(0),
        "",
        entry.value.toStringAsFixed(2),
        "0.00",
        ""
      ]);
    }

    return const ListToCsvConverter().convert(rows);
  }

  /// Builds official hsn.csv (Release 3.2 with Rate column)
  static String buildHsnCsv({
    required List<Sale> sales,
    required CompanyProfile shop,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    final companyPos = GstStateCodes.resolvePos(shop.gstin, shop.state, defaultCode: "08");
    final fDate = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final tDate = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);

    final List<List<dynamic>> rows = [
      [
        "HSN",
        "Description",
        "UQC",
        "Total Quantity",
        "Total Value",
        "Taxable Value",
        "Integrated Tax Amount",
        "Central Tax Amount",
        "State/UT Tax Amount",
        "Cess Amount",
        "Rate"
      ]
    ];

    final Map<String, _HsnCsvAcc> grouped = {};

    for (final s in sales) {
      final inWindow = !s.date.isBefore(fDate) && !s.date.isAfter(tDate);
      if (!inWindow || s.status != "Active") continue;

      final pos = GstStateCodes.resolvePos(s.partyGstin, s.partyState, defaultCode: companyPos);
      final isIntra = (pos == companyPos);

      double gross = 0.0;
      for (var it in s.items) gross += ((it.qty * it.rate) - it.discountRupees);
      final discRatio = (s.extraDiscount > 0 && gross > 0) ? (s.extraDiscount / gross) : 0.0;

      for (var it in s.items) {
        String cleanHsn = it.hsn.trim().replaceAll(RegExp(r'[^0-9]'), '');
        if (cleanHsn.isEmpty) cleanHsn = "3004";
        final rate = it.gstRate;
        final key = "${cleanHsn}_$rate";

        final tx = ((it.qty * it.rate) - it.discountRupees) * (1.0 - discRatio);
        final tax = tx * (rate / 100.0);
        final val = tx + tax;

        final iamt = isIntra ? 0.0 : tax;
        final camt = isIntra ? (tax / 2.0) : 0.0;
        final samt = isIntra ? (tax / 2.0) : 0.0;

        if (grouped.containsKey(key)) {
          final acc = grouped[key]!;
          acc.qty += (it.qty + it.freeQty);
          acc.val += val;
          acc.txval += tx;
          acc.iamt += iamt;
          acc.camt += camt;
          acc.samt += samt;
        } else {
          grouped[key] = _HsnCsvAcc(
            hsn: cleanHsn,
            desc: it.name.isNotEmpty ? it.name : "Pharmaceutical Medicament",
            qty: (it.qty + it.freeQty),
            val: val,
            txval: tx,
            iamt: iamt,
            camt: camt,
            samt: samt,
            rate: rate,
          );
        }
      }
    }

    for (final acc in grouped.values) {
      rows.add([
        acc.hsn,
        acc.desc,
        "NOS-NUMBERS",
        acc.qty.toStringAsFixed(2),
        acc.val.toStringAsFixed(2),
        acc.txval.toStringAsFixed(2),
        acc.iamt.toStringAsFixed(2),
        acc.camt.toStringAsFixed(2),
        acc.samt.toStringAsFixed(2),
        "0.00",
        acc.rate.toStringAsFixed(0)
      ]);
    }

    return const ListToCsvConverter().convert(rows);
  }

  /// Builds official docs.csv
  static String buildDocsCsv({
    required List<Sale> sales,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    final fDate = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final tDate = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);

    final List<List<dynamic>> rows = [
      ["Nature of Document", "Sr. No. From", "Sr. No. To", "Total Number", "Cancelled"]
    ];

    final periodSales = sales.where((s) {
      return !s.date.isBefore(fDate) && !s.date.isAfter(tDate);
    }).toList();

    if (periodSales.isNotEmpty) {
      final from = periodSales.first.billNo;
      final to = periodSales.last.billNo;
      final total = periodSales.length;
      final cancelled = periodSales.where((s) => s.status == "Cancelled").length;

      rows.add([
        "Invoices for outward supply",
        from,
        to,
        total,
        cancelled
      ]);
    }

    return const ListToCsvConverter().convert(rows);
  }
}

class _HsnCsvAcc {
  String hsn;
  String desc;
  double qty;
  double val;
  double txval;
  double iamt;
  double camt;
  double samt;
  double rate;

  _HsnCsvAcc({
    required this.hsn,
    required this.desc,
    required this.qty,
    required this.val,
    required this.txval,
    required this.iamt,
    required this.camt,
    required this.samt,
    required this.rate,
  });
}
