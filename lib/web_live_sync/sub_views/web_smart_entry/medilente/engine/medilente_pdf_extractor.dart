// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:typed_data';
import 'dart:js' as js;
import 'package:archive/archive.dart';
import '../models/medilente_bill_model.dart';
import 'medilente_direct_parser.dart';
import 'medilente_csv_generator.dart';

class MedilentePdfExtractor {
  static Future<String> extractTextAsync(Uint8List bytes) async {
    try {
      if (js.context.hasProperty('extractPdfTextFromBytes')) {
        final completer = Completer<String>();
        final promise = js.context.callMethod('extractPdfTextFromBytes', [bytes]);

        promise.callMethod('then', [
          js.allowInterop((result) {
            completer.complete(result?.toString() ?? '');
          }),
          js.allowInterop((error) {
            completer.complete('');
          })
        ]);

        String text = await completer.future.timeout(const Duration(seconds: 12), onTimeout: () => '');
        if (text.trim().length > 30) {
          return text;
        }
      }
    } catch (_) {}

    String dartExtracted = _extractTextWithDartFlate(bytes);
    if (dartExtracted.trim().length > 30) {
      return dartExtracted;
    }

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

  static String _extractTextWithDartFlate(Uint8List bytes) {
    try {
      String pdfStr = String.fromCharCodes(bytes);
      StringBuffer extracted = StringBuffer();
      
      final streamRegex = RegExp(r'stream\r?\n', caseSensitive: false);
      final endStreamRegex = RegExp(r'\r?\nendstream', caseSensitive: false);

      var streamMatches = streamRegex.allMatches(pdfStr).toList();
      var endMatches = endStreamRegex.allMatches(pdfStr).toList();

      for (int i = 0; i < streamMatches.length && i < endMatches.length; i++) {
        int start = streamMatches[i].end;
        int end = endMatches[i].start;
        if (end > start) {
          try {
            Uint8List streamBytes = bytes.sublist(start, end);
            List<int> decoded;
            try {
              decoded = const ZLibDecoder().decodeBytes(streamBytes, verify: false);
            } catch (_) {
              decoded = streamBytes;
            }
            String content = String.fromCharCodes(decoded.where((b) => (b >= 32 && b <= 126) || b == 10 || b == 13));
            
            final tjRegex = RegExp(r'\(([^)]+)\)');
            var matches = tjRegex.allMatches(content);
            for (var m in matches) {
              String t = m.group(1)?.trim() ?? "";
              if (t.isNotEmpty) {
                extracted.write("$t ");
              }
            }
            extracted.writeln();
          } catch (_) {}
        }
      }
      return extracted.toString();
    } catch (_) {
      return "";
    }
  }

  static Future<Map<String, dynamic>> convertPdfToCsvAndParse(Uint8List pdfBytes) async {
    String extracted = await extractTextAsync(pdfBytes);
    MedilenteBill bill = MedilenteDirectParser.parseRawText(extracted);

    if (bill.items.isNotEmpty) {
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
