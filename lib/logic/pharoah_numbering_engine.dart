// FILE: lib/logic/pharoah_numbering_engine.dart (UPGRADED FINANCIAL YEAR NAMESPACE)

import 'package:shared_preferences/shared_preferences.dart';

class PharoahNumberingEngine {
  
  // ===========================================================================
  // 1. GET NEXT SMART NUMBER (FY-Isolated, Gap-Filling Sequential Engine)
  // ===========================================================================
  static Future<String> getNextNumber({
    required String type,           // SALE, PURCHASE, PRODUCT, etc.
    required String companyID,      
    required String prefix,         
    required int startFrom,         
    required List<dynamic> currentList, 
  }) async {
    
    final prefs = await SharedPreferences.getInstance();
    
    // --- NAYA: Active FY ko read karke namespace banana ---
    String currentFY = prefs.getString('active_fy_$companyID') ?? "default_fy";
    String counterKey = 'lastID_${type}_${prefix}_${companyID}_$currentFY';
    
    List<int> existingNumbers = [];

    // STEP A: SCAN CURRENT MEMORY FOR THE PREFIX
    for (var item in currentList) {
      String idToParse = "";
      
      try {
        if (type == "PURCHASE" || type == "CHALLAN_PUR") {
          idToParse = item.internalNo;
        } 
        else if (type == "PRODUCT") {
          idToParse = item.systemId;
        } 
        else if (type == "RECEIPT" || type == "PAYMENT") {
          idToParse = item.voucherNo; 
        }
        else {
          idToParse = item.billNo; 
        }
      } catch (e) {
        idToParse = ""; 
      }

      if (idToParse.startsWith(prefix)) {
        String numPart = idToParse.replaceFirst(prefix, "");
        int? n = int.tryParse(numPart);
        if (n != null) existingNumbers.add(n);
      }
    }

    // STEP B: SEQUENTIAL & GAP FILLING LOGIC
    if (existingNumbers.isNotEmpty) {
      existingNumbers.sort();
      
      // Look for the first available gap from startFrom
      for (int i = startFrom; i <= existingNumbers.last; i++) {
        if (!existingNumbers.contains(i)) {
          return "$prefix$i"; // Found a missing number
        }
      }
      
      // No gaps, return next incremental number
      return "$prefix${existingNumbers.last + 1}";
    }

    // STEP C: START FROM DEFAULT IF LIST IS EMPTY
    return "$prefix$startFrom";
  }

  // ===========================================================================
  // 2. UPDATE PERSISTENT POINTER (FY-Isolated)
  // ===========================================================================
  static Future<void> updateSeriesCounter({
    required String type,
    required String companyID,
    required String usedNumber,
    required String prefix,
  }) async {
    if (!usedNumber.startsWith(prefix)) return;

    final prefs = await SharedPreferences.getInstance();
    
    // Naya Year Namespace Key
    String currentFY = prefs.getString('active_fy_$companyID') ?? "default_fy";
    String counterKey = 'lastID_${type}_${prefix}_${companyID}_$currentFY';
    
    String numStr = usedNumber.replaceFirst(prefix, "");
    int? usedInt = int.tryParse(numStr);
    
    if (usedInt != null) {
      int currentSaved = prefs.getInt(counterKey) ?? 0;
      if (usedInt > currentSaved) {
        await prefs.setInt(counterKey, usedInt);
      }
    }
  }

  // ===========================================================================
  // 3. COUNTER RESET (DANGER ZONE - Isolated to Active FY)
  // ===========================================================================
  static Future<void> resetSeries({
    required String type,
    required String companyID,
    required String prefix,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    String currentFY = prefs.getString('active_fy_$companyID') ?? "default_fy";
    String counterKey = 'lastID_${type}_${prefix}_${companyID}_$currentFY';
    await prefs.remove(counterKey);
  }
}
