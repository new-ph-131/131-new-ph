import 'package:flutter/material.dart';
import 'app_date_logic.dart'; // Date Master se connection

class PharoahDateController {
  
  // ===========================================================================
  // 1. STRICT DATE PICKER (THE LOCK)
  // ===========================================================================

  /// Poore ERP mein jahan bhi user ko date select karni hai, isi function ko call karega.
  /// Ye function calendar ko Financial Year ke andar lock kar deta hai.
  static Future<DateTime?> pickDate({
    required BuildContext context,
    required String currentFY,
    required DateTime initialDate,
  }) async {
    
    // Boundary nikalna Date Master (AppDateLogic) se
    DateTime first = AppDateLogic.getFYStart(currentFY);
    DateTime last = AppDateLogic.getFYEnd(currentFY);

    // Initial date safety check (Kahin current date FY se bahar na ho)
    DateTime safeInitial = initialDate;
    if (safeInitial.isBefore(first)) safeInitial = first;
    if (safeInitial.isAfter(last)) safeInitial = last;

    // Flutter Date Picker ko range boundaries ke saath show karna
    return await showDatePicker(
      context: context,
      initialDate: safeInitial,
      firstDate: first, 
      lastDate: last,   // Yahan LOCK lag raha hai
      
      // Professional Design Settings
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.indigo.shade900, // Header Color
              onPrimary: Colors.white,         // Header Text Color
              onSurface: Colors.black,         // Body Text Color
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: Colors.indigo.shade900, // Button Color
              ),
            ),
          ),
          child: child!,
        );
      },
    );
  }

  // ===========================================================================
  // 2. INITIALIZATION HELPER
  // ===========================================================================

  /// Naya bill ya voucher khulte waqt default date kya honi chahiye.
  /// Ye Date Master se 'Smart Date' uthata hai.
  static DateTime getInitialBillDate(String fy) {
    return AppDateLogic.getSmartDate(fy);
  }
}
