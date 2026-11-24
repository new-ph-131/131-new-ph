// FILE: lib/compliance/gst_offline_engine/gst_preflight_validator.dart
import '../../models.dart';
import '../../gateway/company_registry_model.dart';
import '../../logic/gst_compliance_helper.dart';
import 'gst_state_codes.dart';

enum GstIssueSeverity { error, warning, info }

class GstAuditIssue {
  final GstIssueSeverity severity;
  final String title;
  final String message;
  final String? billNo;

  GstAuditIssue({
    required this.severity,
    required this.title,
    required this.message,
    this.billNo,
  });
}

class GstAuditReport {
  final int totalBills;
  final int b2bBills;
  final int b2cBills;
  final int cancelledBills;
  final double totalTaxable;
  final double totalCgst;
  final double totalSgst;
  final double totalIgst;
  final double totalVal;
  final List<GstAuditIssue> issues;

  GstAuditReport({
    required this.totalBills,
    required this.b2bBills,
    required this.b2cBills,
    required this.cancelledBills,
    required this.totalTaxable,
    required this.totalCgst,
    required this.totalSgst,
    required this.totalIgst,
    required this.totalVal,
    required this.issues,
  });

  int get errorCount => issues.where((i) => i.severity == GstIssueSeverity.error).length;
  int get warningCount => issues.where((i) => i.severity == GstIssueSeverity.warning).length;
  bool get isReadyForUpload => errorCount == 0;
}

class GstPreflightValidator {
  static final RegExp _gstinRegex = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$');

  static GstAuditReport audit({
    required List<Sale> sales,
    List<SaleReturn> returns = const [],
    List<PurchaseReturn> purchaseReturns = const [],
    List<Party> parties = const [],
    required CompanyProfile shop,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    final List<GstAuditIssue> issues = [];
    final companyPos = GstStateCodes.resolvePos(shop.gstin, shop.state, defaultCode: "08");

    // Check Company GSTIN
    final compGst = shop.gstin.trim().toUpperCase();
    if (compGst.isEmpty || compGst == "N/A") {
      issues.add(GstAuditIssue(
        severity: GstIssueSeverity.error,
        title: "Missing Company GSTIN",
        message: "Active company has no GSTIN registered in Company Master.",
      ));
    } else if (!_gstinRegex.hasMatch(compGst)) {
      issues.add(GstAuditIssue(
        severity: GstIssueSeverity.warning,
        title: "Company GSTIN Format",
        message: "GSTIN '$compGst' does not match 15-character standard pattern.",
      ));
    }

    final fDate = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final tDate = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);

    final periodSales = sales.where((s) => !s.date.isBefore(fDate) && !s.date.isAfter(tDate)).toList();
    final activeSales = periodSales.where((s) => s.status == "Active").toList();
    final cancelled = periodSales.where((s) => s.status == "Cancelled").length;

    int b2bCount = 0;
    int b2cCount = 0;
    double sumTaxable = 0.0;
    double sumCgst = 0.0;
    double sumSgst = 0.0;
    double sumIgst = 0.0;
    double sumVal = 0.0;

    for (final s in activeSales) {
      sumVal += s.totalAmount;
      final partyGst = s.partyGstin.trim().toUpperCase();
      final bool hasGst = partyGst.isNotEmpty && partyGst != "N/A";

      if (hasGst) {
        b2bCount++;
        if (!_gstinRegex.hasMatch(partyGst)) {
          issues.add(GstAuditIssue(
            severity: GstIssueSeverity.warning,
            title: "Invalid Buyer GSTIN",
            message: "Party '${s.partyName}' has GSTIN '$partyGst' which may fail portal format check.",
            billNo: s.billNo,
          ));
        }
      } else {
        b2cCount++;
      }

      final pos = GstStateCodes.resolvePos(hasGst ? partyGst : null, s.partyState, defaultCode: companyPos);
      final isIntra = (pos == companyPos);

      double gross = 0.0;
      for (var it in s.items) gross += ((it.qty * it.rate) - it.discountRupees);
      final discRatio = (s.extraDiscount > 0 && gross > 0) ? (s.extraDiscount / gross) : 0.0;

      for (final it in s.items) {
        final tx = ((it.qty * it.rate) - it.discountRupees) * (1.0 - discRatio);
        final tax = tx * (it.gstRate / 100.0);
        sumTaxable += tx;

        if (isIntra) {
          sumCgst += (tax / 2.0);
          sumSgst += (tax / 2.0);
        } else {
          sumIgst += tax;
        }

        // HSN Check
        if (it.hsn.trim().replaceAll(RegExp(r'[^0-9]'), '').isEmpty) {
          issues.add(GstAuditIssue(
            severity: GstIssueSeverity.warning,
            title: "Missing Item HSN",
            message: "Item '${it.name}' in bill #${s.billNo} has no HSN code (defaulting to 3004).",
            billNo: s.billNo,
          ));
        }
      }
    }

    final periodReturns = returns.where((r) => !r.date.isBefore(fDate) && !r.date.isAfter(tDate) && r.isDeleted != 1 && r.status == "Active").toList();
    for (final ret in periodReturns) {
      final cnExpDate = GstComplianceHelper.getExpiredOriginDate(
        headerOrigDate: ret.origBillDate,
        items: ret.items,
        noteDate: ret.date,
      );
      if (cnExpDate != null && !ret.isCommercial) {
        issues.add(GstAuditIssue(
          severity: GstIssueSeverity.warning,
          title: "Sec 34(2) Time-Limit Crossed",
          message: "Credit Note '${ret.billNo}' references invoice dated ${cnExpDate.toString().substring(0, 10)} past 30 Nov cutoff — mark as Commercial Note.",
          billNo: ret.billNo,
        ));
      }
      if (ret.isCommercial) continue;

      final match = parties.firstWhere(
        (p) => (ret.partyId.isNotEmpty && p.id == ret.partyId) ||
               p.name.trim().toLowerCase() == ret.partyName.trim().toLowerCase(),
        orElse: () => Party(id: '', name: ret.partyName, gst: ret.partyGstin, state: ret.partyState),
      );
      final rGst = (match.gst.trim().isNotEmpty ? match.gst : ret.partyGstin).trim().toUpperCase();
      final rState = match.state.trim().isNotEmpty ? match.state : ret.partyState;
      final bool hasGst = rGst.isNotEmpty && rGst != "N/A";
      if (hasGst && !_gstinRegex.hasMatch(rGst)) {
        issues.add(GstAuditIssue(
          severity: GstIssueSeverity.warning,
          title: "Invalid CN Party GSTIN",
          message: "Credit Note party '${ret.partyName}' has invalid GSTIN '$rGst'.",
          billNo: ret.billNo,
        ));
      }

      sumVal -= ret.totalAmount;
      final pos = GstStateCodes.resolvePos(hasGst ? rGst : null, rState, defaultCode: companyPos);
      final isIntra = (pos == companyPos);
      double gross = 0.0;
      for (var it in ret.items) gross += ((it.qty * it.rate) - it.discountRupees);
      final discRatio = (ret.extraDiscount > 0 && gross > 0) ? (ret.extraDiscount / gross) : 0.0;
      for (final it in ret.items) {
        final tx = ((it.qty * it.rate) - it.discountRupees) * (1.0 - discRatio);
        final tax = tx * (it.gstRate / 100.0);
        sumTaxable -= tx;
        if (isIntra) {
          sumCgst -= (tax / 2.0);
          sumSgst -= (tax / 2.0);
        } else {
          sumIgst -= tax;
        }
        if (it.hsn.trim().replaceAll(RegExp(r'[^0-9]'), '').isEmpty) {
          issues.add(GstAuditIssue(
            severity: GstIssueSeverity.warning,
            title: "Missing Return Item HSN",
            message: "Item '${it.name}' in CN #${ret.billNo} has no HSN code (defaulting to 3004).",
            billNo: ret.billNo,
          ));
        }
      }
    }

    for (final pr in purchaseReturns.where((r) => !r.date.isBefore(fDate) && !r.date.isAfter(tDate) && r.isDeleted != 1 && r.status == "Active")) {
      final dnExpDate = GstComplianceHelper.getExpiredOriginDate(
        headerOrigDate: pr.origBillDate,
        items: pr.items,
        noteDate: pr.date,
      );
      if (dnExpDate != null && !pr.isCommercial) {
        issues.add(GstAuditIssue(
          severity: GstIssueSeverity.warning,
          title: "Sec 34(2) Time-Limit Crossed (DN)",
          message: "Debit Note '${pr.billNo}' references bill dated ${dnExpDate.toString().substring(0, 10)} past 30 Nov Sec 34(2) cutoff — review ITC reversal / Commercial flag.",
          billNo: pr.billNo,
        ));
      }
    }

    return GstAuditReport(
      totalBills: periodSales.length,
      b2bBills: b2bCount,
      b2cBills: b2cCount,
      cancelledBills: cancelled,
      totalTaxable: sumTaxable,
      totalCgst: sumCgst,
      totalSgst: sumSgst,
      totalIgst: sumIgst,
      totalVal: sumVal,
      issues: issues,
    );
  }
}
