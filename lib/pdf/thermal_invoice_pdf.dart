// FILE: lib/pdf/thermal_invoice_pdf.dart

import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../gateway/company_registry_model.dart';
import '../logic/app_settings_model.dart';

class ThermalInvoicePdf {
  static Future<void> generate(Sale sale, Party party, CompanyProfile shop, AppConfig config) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80, // 80mm Standard Thermal
        margin: const pw.EdgeInsets.all(5),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // --- HEADER ---
              pw.Center(
                child: pw.Column(children: [
                  if (config.showLogo && config.logoPath != null && File(config.logoPath!).existsSync())
                    pw.Container(width: 40, height: 40, child: pw.Image(pw.MemoryImage(File(config.logoPath!).readAsBytesSync()))),
                  pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  pw.Text(shop.address, style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.center),
                  pw.Text("GSTIN: ${shop.gstin}", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                  pw.Divider(thickness: 0.5),
                ]),
              ),

              // --- BILL INFO ---
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text("Bill: ${sale.billNo}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                pw.Text(DateFormat('dd/MM/yy').format(sale.date), style: const pw.TextStyle(fontSize: 8)),
              ]),
              pw.Text("Cust: ${party.name}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              pw.Divider(thickness: 0.5),

              // --- ITEM TABLE ---
              pw.Row(children: [
                pw.Expanded(flex: 7, child: pw.Text("ITEM", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                pw.Expanded(flex: 3, child: pw.Text("AMT", textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
              ]),
              pw.SizedBox(height: 2),

              ...sale.items.map((it) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 1),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(it.name, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    pw.Row(children: [
                      pw.Text("Qty: ${it.qty.toInt()} x ${it.rate.toStringAsFixed(2)}", style: const pw.TextStyle(fontSize: 7)),
                      pw.Spacer(),
                      pw.Text(it.total.toStringAsFixed(2), style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                    ]),
                  ],
                ),
              )).toList(),

              pw.Divider(thickness: 0.5),

              // --- TOTALS ---
              _sumRow("GROSS TOTAL", sale.totalAmount * 0.88),
              _sumRow("GST TOTAL", sale.totalAmount * 0.12),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text("NET PAYABLE", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.Text("Rs. ${sale.totalAmount.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ]),

              pw.SizedBox(height: 10),

              // --- BARCODE / QR ---
              pw.Center(
                child: pw.Column(children: [
                  pw.Container(
                    height: 30, width: 100,
                    child: pw.BarcodeWidget(barcode: pw.Barcode.code128(), data: sale.billNo, drawText: false),
                  ),
                  pw.Text(sale.billNo, style: const pw.TextStyle(fontSize: 6)),
                ]),
              ),
              pw.SizedBox(height: 5),
              pw.Center(child: pw.Text("Thank You! Visit Again", style: const pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic))),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Receipt_${sale.billNo}');
  }

  static pw.Widget _sumRow(String l, double v) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
    pw.Text(l, style: const pw.TextStyle(fontSize: 7)),
    pw.Text(v.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 7)),
  ]);
}
