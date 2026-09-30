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
      if (upperId.startsWith(cleanPrefix)) {
        String numPart = upperId.replaceFirst(cleanPrefix, "").trim();
        int? n = int.tryParse(numPart);
        if (n != null) existingNumbers.add(n);
      }
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
