// FILE: lib/web_live_sync/web_pharoah_numbering_engine.dart
// Revision: #PH-REV-795 (ENTERPRISE-STRICT-SERIES-PREFIX-ISOLATION)

import 'web_models.dart';

class WebPharoahNumberingEngine {
  /// Coordinated sequential gap-filling number generator matching Mobile App.
  /// 🛡️ STRICT SERIES PREFIX ISOLATION:
  /// Evaluates only records that strictly match the requested [prefix].
  /// App bills (INV-1, PUR-1) and Web bills (W-1, WPUR-1) or custom series (GST-1)
  /// never cross-contaminate or increment each other's sequences.
  static String getNextNumber({
    required String prefix,
    required int startFrom,
    required List<dynamic> currentList,
  }) {
    List<int> existingNumbers = [];
    final String cleanPrefix = prefix.trim().toUpperCase();

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
          idToParse = (item['billNo'] ??
                  item['internalNo'] ??
                  item['voucherNo'] ??
                  item['systemId'] ??
                  '')
              .toString();
        }
      } catch (_) {
        idToParse = "";
      }

      final String upperId = idToParse.trim().toUpperCase();

      // 🛡️ Strict Prefix Match: Only extract sequential integer if the ID starts with this exact prefix
      if (cleanPrefix.isNotEmpty && upperId.startsWith(cleanPrefix)) {
        final String numPart = upperId.substring(cleanPrefix.length).trim();
        final int? n = int.tryParse(numPart);
        if (n != null) {
          existingNumbers.add(n);
        }
      }
    }

    if (existingNumbers.isNotEmpty) {
      existingNumbers.sort();
      // Continuous gap-filling check starting from startFrom
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
