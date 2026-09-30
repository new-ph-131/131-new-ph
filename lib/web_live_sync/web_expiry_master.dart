// FILE: lib/web_live_sync/web_expiry_master.dart

export '../../expiry_master.dart';
import 'package:flutter/material.dart';
import '../../expiry_master.dart';

class WebExpiryMaster {
  static ExpiryStatus getStatus(String exp) => ExpiryMaster.getStatus(exp);
  static Color getStatusColor(String exp) => ExpiryMaster.getStatusColor(exp);
  static bool isSaleAllowed(String exp) => ExpiryMaster.isSaleAllowed(exp);
  static String? getValidationWarning(String exp) => ExpiryMaster.getValidationWarning(exp);
}
