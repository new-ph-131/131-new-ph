import 'models.dart';

class InventoryEngine {
  /// SALE DELETE होने पर: बेचा हुआ माल वापस स्टॉक में जोड़ता है
  static void reverseSaleStock(Sale sale, List<Medicine> medicines) {
    for (var item in sale.items) {
      try {
        // बिल वाले आइटम को मास्टर इन्वेंट्री में ढूंढें
        Medicine med = medicines.firstWhere((m) => m.id == item.medicineID);
        
        // बेचा हुआ माल (Qty + Free) वापस दुकान के स्टॉक में जोड़ें
        med.stock += (item.qty + item.freeQty);
        
      } catch (e) {
        // अगर दवा मास्टर लिस्ट से ही डिलीट हो गई है तो एरर स्किप करें
      }
    }
  }

  /// PURCHASE DELETE होने पर: खरीदा हुआ माल स्टॉक से घटाता है
  static void reversePurchaseStock(Purchase purchase, List<Medicine> medicines) {
    for (var item in purchase.items) {
      try {
        // बिल वाले आइटम को मास्टर इन्वेंट्री में ढूंढें
        Medicine med = medicines.firstWhere((m) => m.id == item.medicineID);
        
        // खरीदा हुआ माल (Qty + Free) दुकान के स्टॉक से वापस कम करें
        med.stock -= (item.qty + item.freeQty);
        
      } catch (e) {
        // एरर हैंडलिंग
      }
    }
  }
}
