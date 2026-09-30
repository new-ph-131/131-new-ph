// FILE: lib/logic/history_excel_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import '../models.dart';

class HistoryExcelService {
  static Future<void> export(List<Voucher> list, String shopName) async {
    List<List<dynamic>> rows = [];

    // Header Structure
    rows.add([
      "DATE", "VOUCHER NO", "ACCOUNT NAME", "INTERNAL LEDGER", 
      "TYPE", "MODE", "CHQ/REF NO", "DEBIT (PAID)", "CREDIT (REC)", "NARRATION", "STATUS"
    ]);

    for (var v in list) {
      bool isReceipt = v.type == "Receipt";
      bool isCan = v.status == "Cancelled";

      rows.add([
        DateFormat('dd/MM/yyyy').format(v.date),
        v.voucherNo,
        v.partyName.toUpperCase(),
        v.depositedIn.toUpperCase(),
        v.type.toUpperCase(),
        v.paymentMode,
        v.chequeNo,
        isReceipt ? 0.00 : v.amount,
        isReceipt ? v.amount : 0.00,
        v.narration,
        v.status.toUpperCase()
      ]);
    }

    String csv = const ListToCsvConverter().convert(rows);
    Uint8List bytes = Uint8List.fromList(utf8.encode(csv));
    
    String dateTag = DateFormat('ddMMM').format(DateTime.now());
    await FileSaver.instance.saveAs(
      name: "TXN_History_${shopName}_$dateTag",
      bytes: bytes,
      ext: "csv",
      mimeType: MimeType.csv
    );
  }
}
