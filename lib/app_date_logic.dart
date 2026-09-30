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
    DateTime now = DateTime.now();
    if (now.month >= 4) {
      // April se December tak: Current Year se Agla Year
      return "${now.year}-${(now.year + 1).toString().substring(2)}";
    } else {
      // January se March tak: Pichla Year se Current Year
      return "${now.year - 1}-${now.year.toString().substring(2)}";
    }
  }

  // ===========================================================================
  // 2. BOUNDARY LOGIC (FOR CALENDAR LOCKING)
  // ===========================================================================

  /// Kisi bhi FY String (jaise "2024-25") ka Start Date (1st April) nikalna.
  static DateTime getFYStart(String fy) {
    try {
      List<String> parts = fy.split('-');
      int startYear = int.parse(parts[0]);
      // Agar year '24' format mein hai toh '2024' banayein
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
      // Agle saal ki 31st March (End of FY)
      return DateTime(startYear + 1, 3, 31, 23, 59, 59);
    } catch (e) {
      return DateTime(DateTime.now().year + 1, 3, 31);
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
      return "Error";
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
    DateTime fyStart = getFYStart(currentFY);
    DateTime fyEnd = getFYEnd(currentFY);
    return pickedDate.isAfter(fyStart.subtract(const Duration(days: 1))) && 
           pickedDate.isBefore(fyEnd.add(const Duration(days: 1)));
  }
}
