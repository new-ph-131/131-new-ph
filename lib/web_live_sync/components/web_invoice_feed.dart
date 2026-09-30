// FILE: lib/web_live_sync/components/web_invoice_feed.dart

import 'package:flutter/material.dart';
import '../web_models.dart';
import '../pharoah_web_manager.dart';
import '../web_pdf_router_service.dart';
import '../web_app_date_logic.dart';

class WebInvoiceFeed extends StatelessWidget {
  final PharoahWebManager webPh;
  final Function(Sale sale)? onViewBill;

  const WebInvoiceFeed({
    super.key,
    required this.webPh,
    this.onViewBill,
  });

  @override
  Widget build(BuildContext context) {
    final List<Sale> salesList = webPh.sales.reversed.where((s) => s.status == "Active").toList();
    final int displayCount = salesList.length > 10 ? 10 : salesList.length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: Colors.cyanAccent, size: 20),
              const SizedBox(width: 10),
              const Text(
                "LIVE STORE INVOICES FEED",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                "${salesList.length} Total Bills Recorded",
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 25),

          if (salesList.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(35),
                child: Text(
                  "No invoices recorded in this store database yet.",
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 750),
                child: Table(
                  columnWidths: const {
                    0: FixedColumnWidth(90),
                    1: FixedColumnWidth(120),
                    2: FlexColumnWidth(3),
                    3: FixedColumnWidth(110),
                    4: FixedColumnWidth(130),
                    5: FixedColumnWidth(140),
                  },
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Colors.white10)),
                      ),
                      children: [
                        _th("TYPE"),
                        _th("BILL NO"),
                        _th("PARTY / CUSTOMER", isLeft: true),
                        _th("DATE"),
                        _th("AMOUNT"),
                        _th("ACTIONS"),
                      ],
                    ),
                    for (int i = 0; i < displayCount; i++)
                      TableRow(
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Colors.white10)),
                        ),
                        children: [
                          _tdBadge(salesList[i].paymentMode),
                          _td(salesList[i].billNo, isBold: true),
                          _td(salesList[i].partyName, isLeft: true, isBold: true),
                          _td(WebAppDateLogic.format(salesList[i].date)),
                          _td("₹${salesList[i].totalAmount.toStringAsFixed(2)}", isBold: true, color: Colors.greenAccent),
                          _tdActions(salesList[i], context),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _th(String text, {bool isLeft = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Text(
          text,
          textAlign: isLeft ? TextAlign.left : TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
        ),
      );

  Widget _td(String text, {bool isLeft = false, bool isBold = false, Color color = Colors.white}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Text(
          text,
          textAlign: isLeft ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      );

  Widget _tdBadge(String type) {
    Color bg = const Color(0x2610B981);
    Color fg = Colors.greenAccent;

    if (type.toUpperCase().contains("CREDIT")) {
      bg = const Color(0x263B82F6);
      fg = Colors.blueAccent;
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(type.toUpperCase(), style: TextStyle(color: fg, fontSize: 9, fontWeight: FontWeight.w900)),
      ),
    );
  }

  Widget _tdActions(Sale sale, BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.print_outlined, size: 16, color: Color(0xFF38BDF8)),
          tooltip: "Print Landscape Preview",
          onPressed: () {
            final partyObj = webPh.parties.firstWhere(
              (p) => p.name == sale.partyName,
              orElse: () => Party(id: 'temp', name: sale.partyName, gst: sale.partyGstin, state: sale.partyState),
            );
            final shopProfile = CompanyProfile.fromMap(webPh.companyProfile);

            WebPdfRouterService.printSaleInvoice(
              sale: sale,
              party: partyObj,
              shop: shopProfile,
              config: webPh.appConfig,
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.download_rounded, size: 16, color: Colors.greenAccent),
          tooltip: "Download PDF File (Save to Files)",
          onPressed: () {
            final partyObj = webPh.parties.firstWhere(
              (p) => p.name == sale.partyName,
              orElse: () => Party(id: 'temp', name: sale.partyName, gst: sale.partyGstin, state: sale.partyState),
            );
            final shopProfile = CompanyProfile.fromMap(webPh.companyProfile);

            WebPdfRouterService.downloadSalePdf(
              sale: sale,
              party: partyObj,
              shop: shopProfile,
              config: webPh.appConfig,
            );
          },
        ),
      ],
    );
  }
}
