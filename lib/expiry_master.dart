import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum ExpiryStatus { safe, nearExpiry, expired, invalid }

class ExpiryMaster {
  // ===========================================================================
  // 1. EXPIRY PARSER & STATUS LOGIC (SUPPORTS NON-EXPIRY + MM/YY + MM/YYYY)
  // ===========================================================================
  static bool isNonExpiryValue(String exp) {
    final clean = exp.trim().toUpperCase();
    return clean.isEmpty ||
        clean == "N/A" ||
        clean == "NA" ||
        clean == "-" ||
        clean == "NONE" ||
        clean == "NO EXP" ||
        clean == "NO EXPIRY";
  }

  /// Medicine ki expiry string (MM/YY ya MM/YYYY) ko check karke status batata hai.
  /// Logic: Non-Expiry ("", "N/A") -> Safe, < 0 days (Expired), <= 180 days (Near), else Safe.
  static ExpiryStatus getStatus(String exp) {
    if (isNonExpiryValue(exp)) return ExpiryStatus.safe;
    if (!exp.contains('/')) return ExpiryStatus.invalid;

    try {
      List<String> parts = exp.trim().split('/');
      if (parts.length < 2) return ExpiryStatus.invalid;
      int month = int.parse(parts[0].trim());
      int yearPart = int.parse(parts[1].trim());
      if (month < 1 || month > 12) return ExpiryStatus.invalid;

      int fullYear = yearPart < 100 ? (2000 + yearPart) : yearPart;

      // Pharma Rule: 12/26 ka matlab hai dawa 31 Dec 2026 tak valid hai
      DateTime lastDayOfExpiryMonth = DateTime(fullYear, month + 1, 0);

      DateTime today = DateTime.now();
      DateTime todayDateOnly = DateTime(today.year, today.month, today.day);

      if (lastDayOfExpiryMonth.isBefore(todayDateOnly)) {
        return ExpiryStatus.expired;
      }

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
  static Color getStatusColor(String exp) {
    ExpiryStatus status = getStatus(exp);
    switch (status) {
      case ExpiryStatus.expired:
        return Colors.red.shade700;
      case ExpiryStatus.nearExpiry:
        return Colors.orange.shade700;
      case ExpiryStatus.safe:
        return Colors.green.shade700;
      case ExpiryStatus.invalid:
        return Colors.grey;
    }
  }

  static String? getValidationWarning(String exp) {
    if (isNonExpiryValue(exp)) return null;

    if (!RegExp(r'^\d{1,2}/\d{2,4}$').hasMatch(exp.trim())) {
      return "Format: MM/YY (e.g. 12/26)";
    }

    try {
      int month = int.parse(exp.trim().split('/')[0]);
      if (month < 1 || month > 12) {
        return "Warning: Month $month is Invalid!";
      }
    } catch (e) {}

    return null;
  }

  // ===========================================================================
  // 3. SALES CONTROL LOGIC
  // ===========================================================================
  static bool isSaleAllowed(String exp) {
    if (isNonExpiryValue(exp)) return true;
    ExpiryStatus status = getStatus(exp);
    return status != ExpiryStatus.expired;
  }
}
