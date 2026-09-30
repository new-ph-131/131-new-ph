import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum ExpiryStatus { safe, nearExpiry, expired, invalid }

class ExpiryMaster {
  
  // ===========================================================================
  // 1. EXPIRY PARSER & STATUS LOGIC
  // ===========================================================================

  /// Medicine ki expiry string (MM/YY) ko check karke status batata hai.
  /// Logic: < 0 days (Expired), < 180 days/6 months (Near), else Safe.
  static ExpiryStatus getStatus(String exp) {
    if (exp.isEmpty || !exp.contains('/')) return ExpiryStatus.invalid;

    try {
      // 1. String ko Month aur Year mein todna
      List<String> parts = exp.split('/');
      int month = int.parse(parts[0]);
      int yearPart = int.parse(parts[1]);
      
      // Year ko 20XX format mein badalna
      int fullYear = 2000 + yearPart;

      // 2. Pharma Rule: 12/26 ka matlab hai dawa 31 Dec 2026 tak valid hai
      // Hum agle mahine ki 1 tarikh nikal kar 1 din piche jayenge
      DateTime lastDayOfExpiryMonth = DateTime(fullYear, month + 1, 0);
      
      DateTime today = DateTime.now();
      DateTime todayDateOnly = DateTime(today.year, today.month, today.day);

      // 3. Status Calculation
      if (lastDayOfExpiryMonth.isBefore(todayDateOnly)) {
        return ExpiryStatus.expired;
      }

      // Near Expiry Logic: 6 Months (Aprox 180 Days)
      int daysRemaining = lastDayOfExpiryMonth.difference(todayDateOnly).inDays;
      if (daysRemaining <= 180) {
        return ExpiryStatus.nearExpiry;
      }

      return ExpiryStatus.safe;
    } catch (e) {
      return ExpiryStatus.invalid;
    }
  }

  // ===========================================================================
  // 2. UI HELPERS (COLORS & WARNINGS)
  // ===========================================================================

  /// Status ke hisaab se UI ka color batata hai
  static Color getStatusColor(String exp) {
    ExpiryStatus status = getStatus(exp);
    switch (status) {
      case ExpiryStatus.expired:
        return Colors.red.shade700; // Ekdum Khatra
      case ExpiryStatus.nearExpiry:
        return Colors.orange.shade700; // Warning
      case ExpiryStatus.safe:
        return Colors.green.shade700; // Safe
      case ExpiryStatus.invalid:
        return Colors.grey;
    }
  }

  /// Aapka bataya hua Logic A: 14/25 jaise cases ke liye warning string
  static String? getValidationWarning(String exp) {
    if (exp.isEmpty) return null;
    
    // Format check (Regex: Digits/Digits)
    if (!RegExp(r'^\d{1,2}/\d{2}$').hasMatch(exp)) {
      return "Format: MM/YY (e.g. 12/26)";
    }

    try {
      int month = int.parse(exp.split('/')[0]);
      if (month < 1 || month > 12) {
        return "Warning: Month $month is Invalid!";
      }
    } catch (e) {}
    
    return null;
  }

  // ===========================================================================
  // 3. SALES CONTROL LOGIC
  // ===========================================================================

  /// Kya ye dawa bechi ja sakti hai?
  /// Expired dawa ko block karne ke liye Billing screen iska use karegi.
  static bool isSaleAllowed(String exp) {
    ExpiryStatus status = getStatus(exp);
    return status != ExpiryStatus.expired;
  }
}
