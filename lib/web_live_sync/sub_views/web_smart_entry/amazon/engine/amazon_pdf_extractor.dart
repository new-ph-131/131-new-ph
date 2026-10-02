import 'dart:typed_data';
import '../../medilente/engine/medilente_pdf_extractor.dart';
import '../models/amazon_bill_model.dart';
import 'amazon_direct_parser.dart';

class AmazonPdfExtractor {
  static Future<String> extractTextAsync(Uint8List bytes) async {
    return await MedilentePdfExtractor.extractTextAsync(bytes);
  }

  static Future<Map<String, dynamic>> parsePdf(Uint8List pdfBytes) async {
    String text = await extractTextAsync(pdfBytes);
    AmazonBill bill = AmazonDirectParser.parseRawText(text);
    return {
      'success': true,
      'bill': bill,
      'rawText': text,
    };
  }
}
