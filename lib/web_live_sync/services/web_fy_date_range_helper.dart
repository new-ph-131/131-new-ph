// FILE: lib/web_live_sync/services/web_fy_date_range_helper.dart
// Revision: #PH-REV-799 (ENTERPRISE-MULTI-FY-DATE-GUARD-AND-REGISTER-VISIBILITY)

import '../web_app_date_logic.dart';

class WebFyDateRangeHelper {
  /// Returns a valid [fromDate, toDate] range strictly inside [activeFy] so that
  /// new Financial Year (e.g. 2027-28), current Financial Year (2026-27), and
  /// Back Financial Year (2025-26) registers NEVER suffer from inverted date ranges
  /// (fromDate > toDate) or hidden bills.
  static ({DateTime fromDate, DateTime toDate}) computeRegisterDateRange(
    String activeFy, {
    Iterable<DateTime>? recordDates,
  }) {
    final DateTime fyStartRaw = WebAppDateLogic.getFYStart(activeFy);
    final DateTime fyEndRaw = WebAppDateLogic.getFYEnd(activeFy);
    final DateTime fyStart = DateTime(fyStartRaw.year, fyStartRaw.month, fyStartRaw.day);
    final DateTime fyEnd = DateTime(fyEndRaw.year, fyEndRaw.month, fyEndRaw.day);

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    // Default start is always 1st April of active Financial Year so no early-year bills are hidden
    DateTime fromDate = fyStart;
    DateTime toDate;

    if (today.isBefore(fyStart) || today.isAfter(fyEnd)) {
      // Future / newly started Financial Year (e.g. 2027-28) or Back Year (e.g. 2025-26):
      // Cover the entire Financial Year (01 Apr to 31 Mar) so every entry is immediately visible!
      toDate = fyEnd;
    } else {
      // Current Financial Year: cover from 01 Apr up to today (or fyEnd if post-dated bills exist)
      toDate = today;
    }

    if (recordDates != null) {
      for (final dt in recordDates) {
        final dOnly = DateTime(dt.year, dt.month, dt.day);
        if (!dOnly.isBefore(fyStart) && !dOnly.isAfter(fyEnd)) {
          if (dOnly.isBefore(fromDate)) fromDate = dOnly;
          if (dOnly.isAfter(toDate)) toDate = dOnly;
        }
      }
    }

    if (toDate.isBefore(fromDate)) {
      toDate = fyEnd;
    }

    return (fromDate: fromDate, toDate: toDate);
  }

  /// Ensures a transaction date being saved in [activeFy] falls within [activeFy].
  /// If a stale widget state passed a date from another year, aligns it to the active FY smart date.
  static DateTime ensureDateInActiveFy(DateTime candidateDate, String activeFy) {
    if (activeFy.trim().isEmpty) return candidateDate;
    final DateTime fyStart = WebAppDateLogic.getFYStart(activeFy);
    final DateTime fyEnd = WebAppDateLogic.getFYEnd(activeFy);
    final DateTime dOnly = DateTime(candidateDate.year, candidateDate.month, candidateDate.day);
    final DateTime startOnly = DateTime(fyStart.year, fyStart.month, fyStart.day);
    final DateTime endOnly = DateTime(fyEnd.year, fyEnd.month, fyEnd.day);

    if (dOnly.isBefore(startOnly) || dOnly.isAfter(endOnly)) {
      return WebAppDateLogic.getSmartDate(activeFy);
    }
    return candidateDate;
  }
}
