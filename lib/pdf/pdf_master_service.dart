// FILE: lib/pdf/pdf_master_service.dart
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PdfMasterService {
  // Common Box Style (Aapke original format ke hisab se)
  static pw.Widget headerBox({required double width, required double height, required pw.Widget child}) {
    return pw.Container(
      width: width, 
      height: height, 
      padding: const pw.EdgeInsets.all(4), 
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)), 
      child: child
    );
  }

  // Common Table Column Style
  static pw.Widget tableCol(String text, double width, {pw.Alignment align = pw.Alignment.center}) {
    return pw.Container(
      width: width, 
      height: 18, 
      alignment: align, 
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)), 
      child: pw.Text(text, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))
    );
  }

  // Asli Number to Words Formula (Jo dono files mein common hai)
  static String numberToWords(int amount) {
    if (amount == 0) return "ZERO";
    var units = ["", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN", "ELEVEN", "TWELVE", "THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN", "SEVENTEEN", "EIGHTEEN", "NINETEEN"];
    var tens = ["", "", "TWENTY", "THIRTY", "FORTY", "FIFTY", "SIXTY", "SEVENTY", "EIGHTY", "NINETY"];
    if (amount < 20) return units[amount];
    if (amount < 100) return tens[(amount / 10).floor()] + (amount % 10 != 0 ? " " + units[amount % 10] : "");
    if (amount < 1000) return units[(amount / 100).floor()] + " HUNDRED" + (amount % 100 != 0 ? " AND " + numberToWords(amount % 100) : "");
    if (amount < 100000) return numberToWords((amount / 1000).floor()) + " THOUSAND" + (amount % 1000 != 0 ? " " + numberToWords(amount % 1000) : "");
    if (amount < 10000000) return numberToWords((amount / 100000).floor()) + " LAKH" + (amount % 100000 != 0 ? " " + numberToWords(amount % 100000) : "");
    return amount.toString();
  }
  // ---------------------------------------------------------------------------
  // 📠 NAYA: THERMAL DIVIDER (For 80mm Strip)
  // ---------------------------------------------------------------------------
  static pw.Widget thermalDivider() {
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Text(
        "--------------------------------------------------------------------------",
        style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
        maxLines: 1,
      ),
    );
  }
}
