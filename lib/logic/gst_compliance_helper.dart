// FILE: lib/logic/gst_compliance_helper.dart
import '../compliance/gst_offline_engine/gst_state_codes.dart';
import 'app_settings_model.dart';

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
}
