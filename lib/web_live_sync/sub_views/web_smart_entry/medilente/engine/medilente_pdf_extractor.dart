// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:typed_data';
import 'dart:js' as js;
import '../models/medilente_bill_model.dart';
import 'medilente_direct_parser.dart';
import 'medilente_csv_generator.dart';

class MedilentePdfExtractor {
  static Future<String> extractTextAsync(Uint8List bytes) async {
    try {
      if (js.context.hasProperty('extractPdfTextFromBytes')) {
        final completer = Completer<String>();
        // Pass as plain Dart List<int> so JS receives a clean JS Array
        final promise = js.context.callMethod('extractPdfTextFromBytes', [bytes.toList()]);

        promise.callMethod('then', [
          js.allowInterop((result) {
            completer.complete(result?.toString() ?? '');
          }),
          js.allowInterop((error) {
            completer.complete('');
          })
        ]);

        String text = await completer.future.timeout(const Duration(seconds: 10), onTimeout: () => '');
        if (text.trim().length > 10) {
          return text;
        }
      }
    } catch (_) {}

    // Fallback ascii decode
    StringBuffer asciiBuf = StringBuffer();
    for (int b in bytes) {
      if (b >= 32 && b <= 126) {
        asciiBuf.write(String.fromCharCode(b));
      } else if (b == 10 || b == 13) {
        asciiBuf.writeln();
      }
    }
    return asciiBuf.toString();
  }

  static Future<Map<String, dynamic>> convertPdfToCsvAndParse(Uint8List pdfBytes) async {
    String extracted = await extractTextAsync(pdfBytes);
    MedilenteBill? bill = MedilenteDirectParser.parseRawText(extracted);

    if (bill != null && bill.items.isNotEmpty) {
      String csv = MedilenteCsvGenerator.generateCsvString(bill);
      return {
        'success': true,
        'csv': csv,
        'bill': bill,
        'rawText': extracted,
      };
    }
    return {
      'success': false,
      'error': 'Failed to parse Medilente items from PDF.',
      'rawText': extracted,
    };
  }
}
