// FILE: lib/logic/gst_compliance_helper.dart
import '../compliance/gst_offline_engine/gst_state_codes.dart';
import 'app_settings_model.dart';
import '../models.dart';

/// Shared GST Rule 53(1A), POS Resolution & Section 34(2) Time-Limit Helper
/// Used by both Mobile/Desktop App and Web Live Workstation.
class GstComplianceHelper {
  static const String otherReasonCode = "07-Other / Expired / Damaged";

  static const List<String> standardReasons = [
    "01-Sales Return",
    "02-Post Sale Discount",
    "03-Deficiency in services",
    "04-Correction in invoice",
    "05-Change in POS",
    "06-Finalization of Provisional assessment",
    otherReasonCode,
  ];

  static bool isOtherReason(String reason) =>
      reason.trim().toLowerCase() == otherReasonCode.toLowerCase();

  static bool isCommercialNoteAllowed(AppConfig config) =>
      config.developerAllowCommercialNoteToUser && config.userEnableCommercialNote;

  /// Parses an existing stored reason into (dropdown value, custom remark text).
  static ({String selectedReason, String customRemark}) parseReason(String rawReason) {
    final trimmed = rawReason.trim();
    if (trimmed.isEmpty) {
      return (selectedReason: standardReasons.first, customRemark: "");
    }
    final lower = trimmed.toLowerCase();
    for (final r in standardReasons) {
      if (r.toLowerCase() == lower) {
        return (selectedReason: r, customRemark: "");
      }
    }
    final prefixColon = "${otherReasonCode.toLowerCase()}:";
    final prefixDash = "${otherReasonCode.toLowerCase()} -";
    if (lower.startsWith(prefixColon)) {
      return (
        selectedReason: otherReasonCode,
        customRemark: trimmed.substring(prefixColon.length).trim(),
      );
    }
    if (lower.startsWith(prefixDash)) {
      return (
        selectedReason: otherReasonCode,
        customRemark: trimmed.substring(prefixDash.length).trim(),
      );
    }
    if (lower == "07-expiry / breakage" ||
        lower == "07-expired" ||
        lower == "08-others" ||
        lower == "07-others") {
      return (selectedReason: otherReasonCode, customRemark: trimmed);
    }
    return (selectedReason: otherReasonCode, customRemark: trimmed);
  }

  /// Formats the selected Rule 53(1A) dropdown value + optional custom remark for persistence.
  static String formatReason(String selectedReason, String customRemark) {
    final cleanReason = selectedReason.trim().isNotEmpty
        ? selectedReason.trim()
        : standardReasons.first;
    final cleanRemark = customRemark.trim();
    if (isOtherReason(cleanReason)) {
      if (cleanRemark.isEmpty) return otherReasonCode;
      if (cleanRemark.toLowerCase().startsWith("07-") ||
          cleanRemark.toLowerCase().startsWith("08-")) {
        return cleanRemark;
      }
      return "$otherReasonCode: $cleanRemark";
    }
    return cleanReason;
  }

  /// Resolves Place of Supply (2-digit GST code) using GSTIN first, then State Name.
  /// Falls back to [companyPos] when party state & GSTIN are both missing.
  static bool isIntraStateReturn({
    required String? shopGstin,
    required String? shopState,
    required String? partyGstin,
    required String? partyState,
  }) {
    final String companyPos = GstStateCodes.resolvePos(
      shopGstin,
      shopState,
      defaultCode: "08",
    );
    final String partyPos = GstStateCodes.resolvePos(
      partyGstin,
      partyState,
      defaultCode: companyPos,
    );
    return GstStateCodes.isIntraState(companyPos, partyPos);
  }

  /// Resolves 2-digit POS code for display/reporting.
  static String resolvePartyPosCode({
    required String? shopGstin,
    required String? shopState,
    required String? partyGstin,
    required String? partyState,
  }) {
    final String companyPos = GstStateCodes.resolvePos(
      shopGstin,
      shopState,
      defaultCode: "08",
    );
    return GstStateCodes.resolvePos(
      partyGstin,
      partyState,
      defaultCode: companyPos,
    );
  }

  /// CGST Section 34(2) Statutory Time-Limit:
  /// 30th November following the end of the Financial Year in which the
  /// original tax invoice was issued.
  static DateTime getSection34CutoffDate(DateTime origInvoiceDate) {
    final int fyEndYear =
        origInvoiceDate.month >= 4 ? origInvoiceDate.year + 1 : origInvoiceDate.year;
    return DateTime(fyEndYear, 11, 30, 23, 59, 59);
  }

  /// Returns true when [noteDate] crosses the Section 34(2) cutoff date for [origInvoiceDate],
  /// meaning GST tax cannot be reversed and a Commercial Credit/Debit Note (without GST) should be issued.
  static bool isSection34Expired({
    required DateTime? origInvoiceDate,
    required DateTime noteDate,
  }) {
    if (origInvoiceDate == null) return false;
    final cutoff = getSection34CutoffDate(origInvoiceDate);
    return noteDate.isAfter(cutoff);
  }

  /// Clamps a candidate date inside [firstDate, lastDate] so showDatePicker never throws AssertionError.
  static DateTime clampPickerDate(DateTime date, DateTime firstDate, DateTime lastDate) {
    if (date.isBefore(firstDate)) return firstDate;
    if (date.isAfter(lastDate)) return lastDate;
    return date;
  }

  static String formatShortDate(DateTime dt) {
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final yy = (dt.year % 100).toString().padLeft(2, '0');
    return "$dd/$mm/$yy";
  }

  /// Summarizes per-item original invoice references across a multi-invoice return.
  static ({
    int uniqueCount,
    String headerBillNo,
    DateTime? headerDate,
    String footerRefText,
  }) summarizeOriginInvoices(
    List<dynamic> items, {
    String fallbackBillNo = "",
    DateTime? fallbackDate,
  }) {
    final Map<String, ({String billNo, DateTime? date})> unique = {};
    DateTime? earliest;

    for (final it in items) {
      final String bNo = (it.origBillNo ?? "").toString().trim();
      final DateTime? bDate = it.origBillDate as DateTime?;
      if (bNo.isEmpty) continue;
      final key = bNo.toUpperCase();
      if (!unique.containsKey(key)) {
        unique[key] = (billNo: bNo, date: bDate);
      } else if (unique[key]!.date == null && bDate != null) {
        unique[key] = (billNo: unique[key]!.billNo, date: bDate);
      }
      if (bDate != null && (earliest == null || bDate.isBefore(earliest))) {
        earliest = bDate;
      }
    }

    if (unique.isEmpty) {
      final cleanFallback = fallbackBillNo.trim();
      if (cleanFallback.isEmpty) {
        return (uniqueCount: 0, headerBillNo: "", headerDate: null, footerRefText: "");
      }
      final ref = fallbackDate != null
          ? "$cleanFallback (${formatShortDate(fallbackDate)})"
          : cleanFallback;
      return (
        uniqueCount: 1,
        headerBillNo: cleanFallback,
        headerDate: fallbackDate,
        footerRefText: ref,
      );
    }

    if (unique.length == 1) {
      final only = unique.values.first;
      final d = only.date ?? fallbackDate;
      final ref = d != null ? "${only.billNo} (${formatShortDate(d)})" : only.billNo;
      return (
        uniqueCount: 1,
        headerBillNo: only.billNo,
        headerDate: d,
        footerRefText: ref,
      );
    }

    final refs = unique.values
        .map((e) => e.date != null ? "${e.billNo} (${formatShortDate(e.date!)})" : e.billNo)
        .join(", ");
    return (
      uniqueCount: unique.length,
      headerBillNo: "Multi (${unique.length} Inv)",
      headerDate: earliest ?? fallbackDate,
      footerRefText: refs,
    );
  }

  /// Checks Section 34(2) expiry across header date AND all non-manual line items.
  static DateTime? getExpiredOriginDate({
    DateTime? headerOrigDate,
    required List<dynamic> items,
    required DateTime noteDate,
  }) {
    DateTime? earliestExpired;
    for (final it in items) {
      if (it.isManualOrigin == true) continue;
      final DateTime? d = it.origBillDate as DateTime?;
      if (d != null && isSection34Expired(origInvoiceDate: d, noteDate: noteDate)) {
        if (earliestExpired == null || d.isBefore(earliestExpired)) {
          earliestExpired = d;
        }
      }
    }
    if (headerOrigDate != null &&
        isSection34Expired(origInvoiceDate: headerOrigDate, noteDate: noteDate)) {
      if (earliestExpired == null || headerOrigDate.isBefore(earliestExpired)) {
        earliestExpired = headerOrigDate;
      }
    }
    return earliestExpired;
  }

  static bool isAnyOriginExpired({
    DateTime? headerOrigDate,
    required List<dynamic> items,
    required DateTime noteDate,
  }) =>
      getExpiredOriginDate(
        headerOrigDate: headerOrigDate,
        items: items,
        noteDate: noteDate,
      ) !=
      null;

  /// Auto-populates missing origin invoices on non-manual Credit Note items from Sales History.
  /// Strictly leaves manual entries (`isManualOrigin == true`) blank.
  static List<BillItem> resolveMissingBillItemOrigins({
    required List<BillItem> items,
    required List<Sale> sales,
    required String partyId,
    required String partyName,
  }) {
    final cleanPid = partyId.trim();
    final cleanPname = partyName.trim().toLowerCase();
    if (cleanPid.isEmpty && cleanPname.isEmpty) return items;

    final partySales = sales
        .where((s) =>
            s.isDeleted != 1 &&
            s.status == "Active" &&
            ((cleanPid.isNotEmpty && s.partyId.trim() == cleanPid) ||
                (cleanPname.isNotEmpty && s.partyName.trim().toLowerCase() == cleanPname)))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    if (partySales.isEmpty) return items;

    return items.map((it) {
      if (it.isManualOrigin || it.origBillNo.trim().isNotEmpty) return it;
      final targetMedId = it.medicineID.trim();
      final targetMedName = it.name.trim().toLowerCase();
      final targetBatch = it.batch.trim().toLowerCase();

      for (final s in partySales) {
        if (s.billNo.trim().isEmpty) continue;
        for (final sIt in s.items) {
          final medMatch = (targetMedId.isNotEmpty && sIt.medicineID.trim() == targetMedId) ||
              (targetMedName.isNotEmpty && sIt.name.trim().toLowerCase() == targetMedName);
          if (!medMatch) continue;
          final batchMatch = targetBatch.isEmpty ||
              sIt.batch.trim().toLowerCase() == targetBatch;
          if (batchMatch) {
            return it.copyWith(origBillNo: s.billNo.trim(), origBillDate: s.date);
          }
        }
      }
      return it;
    }).toList();
  }

  /// Auto-populates missing origin bills on non-manual Debit Note items from Purchase History.
  /// Strictly leaves manual entries (`isManualOrigin == true`) blank.
  static List<PurchaseItem> resolveMissingPurchaseItemOrigins({
    required List<PurchaseItem> items,
    required List<Purchase> purchases,
    required String partyId,
    required String partyName,
  }) {
    final cleanPid = partyId.trim();
    final cleanPname = partyName.trim().toLowerCase();
    if (cleanPid.isEmpty && cleanPname.isEmpty) return items;

    final partyPurchases = purchases
        .where((p) =>
            p.isDeleted != 1 &&
            p.gstStatus != "Cancelled" &&
            p.gstStatus != "Deleted" &&
            ((cleanPid.isNotEmpty && p.partyId.trim() == cleanPid) ||
                (cleanPname.isNotEmpty && p.distributorName.trim().toLowerCase() == cleanPname)))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    if (partyPurchases.isEmpty) return items;

    return items.map((it) {
      if (it.isManualOrigin || it.origBillNo.trim().isNotEmpty) return it;
      final targetMedId = it.medicineID.trim();
      final targetMedName = it.name.trim().toLowerCase();
      final targetBatch = it.batch.trim().toLowerCase();

      for (final p in partyPurchases) {
        if (p.billNo.trim().isEmpty) continue;
        for (final pIt in p.items) {
          final medMatch = (targetMedId.isNotEmpty && pIt.medicineID.trim() == targetMedId) ||
              (targetMedName.isNotEmpty && pIt.name.trim().toLowerCase() == targetMedName);
          if (!medMatch) continue;
          final batchMatch = targetBatch.isEmpty ||
              pIt.batch.trim().toLowerCase() == targetBatch;
          if (batchMatch) {
            return it.copyWith(origBillNo: p.billNo.trim(), origBillDate: p.date);
          }
        }
      }
      return it;
    }).toList();
  }
}
