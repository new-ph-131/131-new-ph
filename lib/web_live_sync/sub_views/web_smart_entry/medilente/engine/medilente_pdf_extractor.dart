import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../models/medilente_bill_model.dart';
import 'medilente_direct_parser.dart';
import 'medilente_csv_generator.dart';

class MedilentePdfExtractor {
  /// 1. Extracts plain text strings from standard PDF streams
  static String extractTextFromPdfBytes(Uint8List bytes) {
    StringBuffer sb = StringBuffer();
    String content = String.fromCharCodes(bytes);

    // Search for FlateDecode / uncompressed streams
    int streamStart = 0;
    while ((streamStart = content.indexOf('stream', streamStart)) != -1) {
      int dataStart = streamStart + 6;
      if (dataStart < content.length && content[dataStart] == '\r') dataStart++;
      if (dataStart < content.length && content[dataStart] == '\n') dataStart++;

      int streamEnd = content.indexOf('endstream', dataStart);
      if (streamEnd == -1) break;

      List<int> streamBytes = bytes.sublist(dataStart, streamEnd);
      List<int> decompressed;

      try {
        decompressed = const ZLibDecoder().decodeBytes(streamBytes);
      } catch (_) {
        decompressed = streamBytes;
      }

      String streamStr = String.fromCharCodes(decompressed);
      _extractTjTokens(streamStr, sb);

      streamStart = streamEnd + 9;
    }

    String result = sb.toString();
    if (result.trim().isEmpty) {
      // Fallback: search for readable ASCII sequences
      return _extractReadableAscii(content);
    }
    return result;
  }

  static void _extractTjTokens(String str, StringBuffer out) {
    // PDF Text operators: (text) Tj or [(text)] TJ
    RegExp tjRegex = RegExp(r'\(([^)]+)\)\s*Tj', multiLine: true);
    for (var m in tjRegex.allMatches(str)) {
      out.write("${m.group(1)} ");
    }

    RegExp bracketRegex = RegExp(r'\[([^\]]+)\]\s*TJ', multiLine: true);
    for (var m in bracketRegex.allMatches(str)) {
      String inner = m.group(1) ?? '';
      RegExp sub = RegExp(r'\(([^)]+)\)');
      for (var s in sub.allMatches(inner)) {
        out.write("${s.group(1)} ");
      }
    }
    out.writeln();
  }

  static String _extractReadableAscii(String raw) {
    StringBuffer sb = StringBuffer();
    RegExp asciiWords = RegExp(r'[A-Za-z0-9\-\.\/]{2,}');
    for (var match in asciiWords.allMatches(raw)) {
      sb.write("${match.group(0)} ");
    }
    return sb.toString();
  }

  /// 2. Converts PDF directly to CSV, then parses CSV into structured bill
  static Map<String, dynamic> convertPdfToCsvAndParse(Uint8List pdfBytes) {
    String extractedText = extractTextFromPdfBytes(pdfBytes);
    MedilenteBill? bill = MedilenteDirectParser.parseRawText(extractedText);

    if (bill != null && bill.items.isNotEmpty) {
      String generatedCsv = MedilenteCsvGenerator.generateCsvString(bill);
      return {
        'success': true,
        'csv': generatedCsv,
        'bill': bill,
      };
    }

    return {
      'success': false,
      'error': 'Could not extract tabular bill data from PDF.',
    };
  }
}
