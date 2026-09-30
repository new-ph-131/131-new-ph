// FILE: lib/pharoah_smart_logic.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class PharoahSmartLogic {
  
  // ===========================================================================
  // 1. SMART SALE NUMBER GENERATOR (Company-Specific)
  // ===========================================================================
  static Future<String> getNextSaleNumber(List<Sale> allSales, String companyID) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Har dukan ki apni key (lastBillID_PH-C-XXXX)
    String idKey = 'lastBillID_$companyID';
    String prefixKey = 'billPrefix_$companyID';
    
    int lastId = prefs.getInt(idKey) ?? 0;
    String prefix = prefs.getString(prefixKey) ?? "INV-";

    // Maujooda bills mein se sirf is prefix wale numbers nikalna
    List<int> existingNums = [];
    for (var s in allSales) {
      if (s.billNo.startsWith(prefix)) {
        String numPart = s.billNo.replaceFirst(prefix, "");
        int? n = int.tryParse(numPart);
        if (n != null) existingNums.add(n);
      }
    }
    
    if (existingNums.isEmpty) return "${prefix}1";

    existingNums.sort();

    // Gap Filling Logic: Agar koi bill delete hua hai toh wo number reuse karo
    for (int i = 1; i <= lastId; i++) {
      if (!existingNums.contains(i)) return "$prefix$i"; 
    }

    // Agar koi gap nahi hai toh agla number
    return "$prefix${lastId + 1}";
  }

  // ===========================================================================
  // 2. SMART PURCHASE ID GENERATOR (Company-Specific)
  // ===========================================================================
  static Future<String> getNextPurchaseNumber(String companyID) async {
    final prefs = await SharedPreferences.getInstance();
    String key = 'lastPurID_$companyID';
    int lastId = prefs.getInt(key) ?? 0;
    return "PUR-${lastId + 1}";
  }

  // ===========================================================================
  // 3. MEDICINE SERIES ID (PH-10001 Series)
  // ===========================================================================
  static Future<String> getNextMedicineSystemID(String companyID) async {
    final prefs = await SharedPreferences.getInstance();
    String key = 'med_counter_$companyID';
    int lastCounter = prefs.getInt(key) ?? 10000; // 10000 se shuru
    return "PH-${lastCounter + 1}";
  }

  // ===========================================================================
  // 4. COUNTER UPDATER (Isse save karte waqt call karenge)
  // ===========================================================================
  static Future<void> updateCountersAfterSave({
    required String type, // "SALE", "PURCHASE", or "MED"
    required String usedID, 
    required String companyID,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (type == "SALE") {
      String prefix = prefs.getString('billPrefix_$companyID') ?? "INV-";
      if (usedID.startsWith(prefix)) {
        int? num = int.tryParse(usedID.replaceFirst(prefix, ""));
        int currentMax = prefs.getInt('lastBillID_$companyID') ?? 0;
        if (num != null && num > currentMax) {
          await prefs.setInt('lastBillID_$companyID', num);
        }
      }
    } 
    else if (type == "PURCHASE") {
      int? num = int.tryParse(usedID.replaceFirst("PUR-", ""));
      int currentMax = prefs.getInt('lastPurID_$companyID') ?? 0;
      if (num != null && num > currentMax) {
        await prefs.setInt('lastPurID_$companyID', num);
      }
    }
    else if (type == "MED") {
      int? num = int.tryParse(usedID.replaceFirst("PH-", ""));
      int currentMax = prefs.getInt('med_counter_$companyID') ?? 10000;
      if (num != null && num > currentMax) {
        await prefs.setInt('med_counter_$companyID', num);
      }
    }
  }
}
