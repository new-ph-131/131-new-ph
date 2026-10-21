// FILE: lib/web_live_sync/sub_views/web_stock/services/stock_excel_export_service.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import '../../../web_models.dart';
import '../../pharoah_web_manager.dart';

class StockExcelExportService {
  static Future<void> exportStockCsv({
    required List<Medicine> medicines,
    required PharoahWebManager webPh,
    required String selectedCompanyName,
    required String activeFilter,
  }) async {
    final List<List<dynamic>> rows = [];

    // Title & Metadata Headers
    final shopName = (webPh.companyProfile['name'] ?? webPh.companyName ?? 'PHAROAH STORE').toString().toUpperCase();
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    rows.add(["STORE:", shopName, "", "EXPORT DATE:", dateStr]);
    rows.add(["FILTER:", activeFilter, "", "COMPANY:", selectedCompanyName]);
    rows.add([]); // empty row

    // Table Headers
    rows.add([
      "SR NO",
      "ITEM CODE",
      "PRODUCT NAME",
      "PACKING",
      "FORM",
      "COMPANY / MANUFACTURER",
      "RACK LOCATION",
      "GST %",
      "CURRENT STOCK",
      "PURCHASE RATE (RS)",
      "MRP (RS)",
      "PURCHASE VALUATION (RS)",
      "MRP VALUATION (RS)",
      "ACTIVE BATCH COUNT",
      "REORDER LEVEL",
      "STOCK STATUS"
    ]);

    int sr = 1;
    for (var m in medicines) {
      String cName = selectedCompanyName;
      if (selectedCompanyName == "All Companies") {
        if (m.companyId.isNotEmpty) {
          try {
            cName = webPh.companies.firstWhere((c) => c.id == m.companyId || c.name.toUpperCase() == m.companyId.toUpperCase()).name;
          } catch (_) {
            cName = m.companyId;
          }
        } else {
          cName = "Unassigned";
        }
      }

      final batches = webPh.batchHistory[m.identityKey] ?? [];
      final activeBatches = batches.where((b) => b.qty > 0).length;
      final purVal = m.stock * m.purRate;
      final mrpVal = m.stock * m.mrp;

      String status = "IN STOCK";
      if (m.stock <= 0) {
        status = "OUT OF STOCK";
      } else if (m.reorderLevel > 0 && m.stock <= m.reorderLevel) {
        status = "LOW STOCK";
      }

      rows.add([
        sr++,
        m.systemId.isNotEmpty ? m.systemId : m.id,
        m.name.toUpperCase(),
        m.packing,
        m.drugForm,
        cName.toUpperCase(),
        m.rackNo.isNotEmpty ? m.rackNo : "-",
        "${m.gst.toInt()}%",
        m.stock.toInt(),
        m.purRate.toStringAsFixed(2),
        m.mrp.toStringAsFixed(2),
        purVal.toStringAsFixed(2),
        mrpVal.toStringAsFixed(2),
        activeBatches,
        m.reorderLevel.toInt(),
        status
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final bytes = Uint8List.fromList(utf8.encode(csv));
    final fileDate = DateFormat('ddMMMyy_HHmm').format(DateTime.now());
    final safeComp = selectedCompanyName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

    await FileSaver.instance.saveFile(
      name: "Stock_Analysis_${safeComp}_$fileDate",
      bytes: bytes,
      ext: "csv",
      mimeType: MimeType.csv,
    );
  }
}
