// FILE: lib/web_live_sync/web_pharoah_numbering_engine.dart

import 'web_models.dart';

class WebPharoahNumberingEngine {
  /// Coordinated sequential gap-filling number generator matching Mobile App
  static String getNextNumber({
    required String prefix,
    required int startFrom,
    required List<dynamic> currentList,
  }) {
    List<int> existingNumbers = [];
    String cleanPrefix = prefix.trim().toUpperCase();

    for (var item in currentList) {
      String idToParse = "";
      try {
        if (item is Sale) {
          idToParse = item.billNo;
        } else if (item is Purchase) {
          idToParse = item.internalNo;
        } else if (item is SaleChallan) {
          idToParse = item.billNo;
        } else if (item is PurchaseChallan) {
          idToParse = item.internalNo;
        } else if (item is SaleReturn) {
          idToParse = item.billNo;
        } else if (item is PurchaseReturn) {
          idToParse = item.billNo;
        } else if (item is Voucher) {
          idToParse = item.voucherNo;
        } else if (item is Medicine) {
          idToParse = item.systemId;
        } else if (item is Map<String, dynamic>) {
          idToParse = (item['billNo'] ?? item['internalNo'] ?? item['voucherNo'] ?? item['systemId'] ?? '').toString();
        }
      } catch (_) {
        idToParse = "";
      }

      String upperId = idToParse.trim().toUpperCase();
      String numPart = upperId;
      if (numPart.startsWith("WDN-")) numPart = numPart.substring(4);
      else if (numPart.startsWith("DN-")) numPart = numPart.substring(3);
      else if (numPart.startsWith("WCN-")) numPart = numPart.substring(4);
      else if (numPart.startsWith("CN-")) numPart = numPart.substring(3);
      else if (numPart.startsWith("WPUR-")) numPart = numPart.substring(5);
      else if (numPart.startsWith("PUR-")) numPart = numPart.substring(4);
      else if (numPart.startsWith("WSCH-")) numPart = numPart.substring(5);
      else if (numPart.startsWith("SCH-")) numPart = numPart.substring(4);
      else if (numPart.startsWith("WPCH-")) numPart = numPart.substring(5);
      else if (numPart.startsWith("PCH-")) numPart = numPart.substring(4);
      else if (numPart.startsWith("W-")) numPart = numPart.substring(2);
      else if (numPart.startsWith("INV-")) numPart = numPart.substring(4);
      else if (cleanPrefix.isNotEmpty && numPart.startsWith(cleanPrefix)) numPart = numPart.replaceFirst(cleanPrefix, "");

      int? n = int.tryParse(numPart.trim());
      if (n != null) existingNumbers.add(n);
    }

    if (existingNumbers.isNotEmpty) {
      existingNumbers.sort();
      // Continuous gap-filling check
      for (int i = startFrom; i <= existingNumbers.last; i++) {
        if (!existingNumbers.contains(i)) {
          return "$prefix$i";
        }
      }
      return "$prefix${existingNumbers.last + 1}";
    }

    return "$prefix$startFrom";
  }
}
