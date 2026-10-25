// FILE: lib/compliance/gst_offline_engine/gst_state_codes.dart
/// Complete GSTN State and Union Territory Directory (37 Codes)
/// Fully compliant with GST Offline Utility v3.2 and CBIC Specifications.
class GstStateCodes {
  static const Map<String, String> codeToName = {
    "01": "Jammu & Kashmir",
    "02": "Himachal Pradesh",
    "03": "Punjab",
    "04": "Chandigarh",
    "05": "Uttarakhand",
    "06": "Haryana",
    "07": "Delhi",
    "08": "Rajasthan",
    "09": "Uttar Pradesh",
    "10": "Bihar",
    "11": "Sikkim",
    "12": "Arunachal Pradesh",
    "13": "Nagaland",
    "14": "Manipur",
    "15": "Mizoram",
    "16": "Tripura",
    "17": "Meghalaya",
    "18": "Assam",
    "19": "West Bengal",
    "20": "Jharkhand",
    "21": "Odisha",
    "22": "Chhattisgarh",
    "23": "Madhya Pradesh",
    "24": "Gujarat",
    "26": "Dadra & Nagar Haveli and Daman & Diu",
    "27": "Maharashtra",
    "29": "Karnataka",
    "30": "Goa",
    "31": "Lakshadweep",
    "32": "Kerala",
    "33": "Tamil Nadu",
    "34": "Puducherry",
    "35": "Andaman & Nicobar Islands",
    "36": "Telangana",
    "37": "Andhra Pradesh",
    "38": "Ladakh",
    "97": "Other Territory",
  };

  /// Normalizes state name to standard 2-digit GST code
  static String resolvePos(String? gstin, String? stateName, {String defaultCode = "08"}) {
    // 1. If GSTIN is provided, first 2 characters are strictly the State Code
    if (gstin != null) {
      final cleanGst = gstin.trim().toUpperCase();
      if (cleanGst.length >= 2) {
        final prefix = cleanGst.substring(0, 2);
        if (codeToName.containsKey(prefix)) {
          return prefix;
        }
      }
    }

    // 2. If state name is provided, match against directory
    if (stateName != null && stateName.trim().isNotEmpty) {
      final cleanName = stateName.trim().toLowerCase();
      for (final entry in codeToName.entries) {
        final entryName = entry.value.toLowerCase();
        if (cleanName == entryName ||
            cleanName.contains(entryName) ||
            entryName.contains(cleanName) ||
            cleanName.startsWith(entry.key)) {
          return entry.key;
        }
      }
      
      // Common aliases
      if (cleanName.contains("up") || cleanName.contains("uttar")) return "09";
      if (cleanName.contains("mp") || cleanName.contains("madhya")) return "23";
      if (cleanName.contains("raj") || cleanName.contains("rajasthan")) return "08";
      if (cleanName.contains("delhi") || cleanName.contains("ncr")) return "07";
      if (cleanName.contains("maha") || cleanName.contains("bombay")) return "27";
      if (cleanName.contains("bengal") || cleanName.contains("kolkata")) return "19";
      if (cleanName.contains("gujarat")) return "24";
      if (cleanName.contains("punjab")) return "03";
      if (cleanName.contains("haryana")) return "06";
      if (cleanName.contains("bihar")) return "10";
    }

    // 3. Fallback to default code
    return defaultCode;
  }

  /// Returns full CSV POS label format (e.g. "08-Rajasthan")
  static String getPosCsvLabel(String posCode) {
    final name = codeToName[posCode] ?? "Other Territory";
    return "$posCode-$name";
  }

  /// Checks whether transaction is intra-state (same state) or inter-state
  static bool isIntraState(String companyPos, String recipientPos) {
    return companyPos.trim() == recipientPos.trim();
  }
}
