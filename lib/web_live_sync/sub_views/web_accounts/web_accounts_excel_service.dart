// FILE: lib/web_live_sync/sub_views/web_accounts/web_accounts_excel_service.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import '../../web_models.dart';

class WebAccountsExcelService {
  static Future<void> exportVouchersCsv(List<Voucher> list, String shopName) async {
    List<List<dynamic>> rows = [];

    rows.add([
      "DATE", "VOUCHER NO", "ACCOUNT / PARTY NAME", "INTERNAL ACCOUNT",
      "TYPE", "PAYMENT MODE", "CHQ / REF NO", "CHEQUE DATE",
      "DEBIT (PAID)", "CREDIT (REC)", "NARRATION", "SETTLED BILLS", "STATUS"
    ]);

    for (var v in list) {
      bool isRec = v.type.toUpperCase() == "RECEIPT";
      rows.add([
        DateFormat('dd/MM/yyyy').format(v.date),
        v.voucherNo,
        v.partyName.toUpperCase(),
        v.depositedIn.toUpperCase(),
        v.type.toUpperCase(),
        v.paymentMode,
        v.chequeNo,
        v.chequeDate != null ? DateFormat('dd/MM/yyyy').format(v.chequeDate!) : "",
        isRec ? 0.0 : v.amount,
        isRec ? v.amount : 0.0,
        v.narration,
        v.linkedBillNumbers.join(", "),
        v.status.toUpperCase(),
      ]);
    }

    String csv = const ListToCsvConverter().convert(rows);
    Uint8List bytes = Uint8List.fromList(utf8.encode(csv));

    String dateTag = DateFormat('ddMMMyy').format(DateTime.now());
    await FileSaver.instance.saveFile(
      name: "Voucher_Register_${shopName.replaceAll(' ', '_')}_$dateTag",
      bytes: bytes,
      ext: "csv",
      mimeType: MimeType.csv,
    );
  }

  static Future<void> exportDaybookCsv(List<Map<String, dynamic>> entries, DateTime date, String shopName) async {
    List<List<dynamic>> rows = [];

    rows.add([
      "TIME / DATE", "TRANSACTION TYPE", "PARTY / PARTICULARS", "REFERENCE / BILL",
      "PAYMENT MODE", "INFLOW (IN ₹)", "OUTFLOW (OUT ₹)"
    ]);

    for (var e in entries) {
      bool isIn = e['isIn'] as bool? ?? false;
      double amt = (e['amount'] as num?)?.toDouble() ?? 0.0;
      rows.add([
        DateFormat('dd/MM/yyyy hh:mm a').format(e['time'] as DateTime),
        e['type'],
        e['party'],
        e['ref'],
        e['mode'] ?? 'N/A',
        isIn ? amt : 0.0,
        isIn ? 0.0 : amt,
      ]);
    }

    String csv = const ListToCsvConverter().convert(rows);
    Uint8List bytes = Uint8List.fromList(utf8.encode(csv));

    String dateTag = DateFormat('ddMMyy').format(date);
    await FileSaver.instance.saveFile(
      name: "Daybook_${shopName.replaceAll(' ', '_')}_$dateTag",
      bytes: bytes,
      ext: "csv",
      mimeType: MimeType.csv,
    );
  }
}
