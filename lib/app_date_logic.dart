import 'package:intl/intl.dart';

class AppDateLogic {
  // ===========================================================================
  // 1. FINANCIAL YEAR DETECTOR (FOR SETUP & INSTALL)
  // ===========================================================================

  /// Aaj ki system date dekh kar automatic Financial Year (FY) string nikalta hai.
  /// April-March Cycle Logic:
  /// Agar aaj 15 May 2024 hai -> "2024-25"
  /// Agar aaj 10 Feb 2025 hai -> "2024-25"
  static String getCurrentFYString() {
    return getFYForDate(DateTime.now());
  }

  /// Kisi bhi specific DateTime se uska Indian Financial Year ("YYYY-YY") nikalta hai.
  static String getFYForDate(DateTime dt) {
    if (dt.month >= 4) {
      return "${dt.year}-${(dt.year + 1).toString().substring(2)}";
    } else {
      return "${dt.year - 1}-${dt.year.toString().substring(2)}";
    }
  }

  /// Normalizes and sorts a list of Financial Year strings chronologically (e.g. ["2025-26", "2026-27"])
  static List<String> sortFYList(Iterable<String> fys) {
    final cleaned = fys
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e.contains("-"))
        .toSet()
        .toList();
    cleaned.sort((a, b) {
      int ya = int.tryParse(a.split("-").first) ?? 0;
      int yb = int.tryParse(b.split("-").first) ?? 0;
      if (ya < 2000 && ya > 0) ya += 2000;
      if (yb < 2000 && yb > 0) yb += 2000;
      return ya.compareTo(yb);
    });
    return cleaned;
  }

  // ===========================================================================
  // 2. BOUNDARY LOGIC (FOR CALENDAR LOCKING)
  // ===========================================================================

  /// Kisi bhi FY String (jaise "2024-25") ka Start Date (1st April) nikalna.
  static DateTime getFYStart(String fy) {
    try {
      List<String> parts = fy.split('-');
      int startYear = int.parse(parts[0]);
      if (startYear < 2000) startYear += 2000;
      return DateTime(startYear, 4, 1);
    } catch (e) {
      return DateTime(DateTime.now().year, 4, 1);
    }
  }

  /// Kisi bhi FY String ka End Date (31st March) nikalna.
  static DateTime getFYEnd(String fy) {
    try {
      List<String> parts = fy.split('-');
      int startYear = int.parse(parts[0]);
      if (startYear < 2000) startYear += 2000;
      return DateTime(startYear + 1, 3, 31, 23, 59, 59);
    } catch (e) {
      return DateTime(DateTime.now().year + 1, 3, 31, 23, 59, 59);
    }
  }

  // ===========================================================================
  // 3. SYSTEM ADMIN LOGIC (FOR YEAR TRANSFER)
  // ===========================================================================

  /// Current FY string se agla Financial Year calculate karna.
  /// Input: "2024-25" -> Output: "2025-26"
  static String getNextFYString(String currentFY) {
    try {
      int startYear = int.parse(currentFY.split('-')[0]);
      if (startYear < 2000) startYear += 2000;
      int nextStart = startYear + 1;
      int nextEnd = startYear + 2;
      return "$nextStart-${nextEnd.toString().substring(2)}";
    } catch (e) {
      return getCurrentFYString();
    }
  }

  // ===========================================================================
  // 4. UI HELPERS (FOR BILLING & DISPLAY)
  // ===========================================================================

  /// Naya bill kholte waqt Smart Date decide karna.
  /// Agar aaj ki date FY ke range mein hai toh 'Today' dikhayega.
  /// Agar user purane saal mein entry kar raha hai toh '31st March' dikhayega.
  static DateTime getSmartDate(String currentFY) {
    DateTime now = DateTime.now();
    DateTime fyStart = getFYStart(currentFY);
    DateTime fyEnd = getFYEnd(currentFY);

    if (now.isAfter(fyStart.subtract(const Duration(seconds: 1))) &&
        now.isBefore(fyEnd.add(const Duration(seconds: 1)))) {
      return now;
    } else if (now.isAfter(fyEnd)) {
      return fyEnd; // Lock to last day of selected FY
    } else {
      return fyStart; // Lock to first day of selected FY
    }
  }

  /// Global Date Formatter: dd/MM/yyyy
  static String format(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  /// Safety Check: Kya koi date kisi specific FY ke andar hai?
  static bool isValidInFY(DateTime pickedDate, String currentFY) {
    if (currentFY.trim().isEmpty) return true;
    DateTime fyStart = getFYStart(currentFY);
    DateTime fyEnd = getFYEnd(currentFY);
    return !pickedDate.isBefore(fyStart) && !pickedDate.isAfter(fyEnd);
  }
}
