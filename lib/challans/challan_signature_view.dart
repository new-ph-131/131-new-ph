// FILE: lib/challans/challan_signature_view.dart

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'; 
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart'; 
import 'package:path_provider/path_provider.dart'; 
import 'package:file_saver/file_saver.dart'; 
import '../pharoah_manager.dart';
import '../models.dart';
import '../pdf/sale_challan_pdf.dart';

class ChallanSignatureView extends StatefulWidget {
  final SaleChallan challan;
  final Party party;
  const ChallanSignatureView({super.key, required this.challan, required this.party});

  @override
  State<ChallanSignatureView> createState() => _ChallanSignatureViewState();
}

class _ChallanSignatureViewState extends State<ChallanSignatureView> {
  bool isSignMode = false;
  bool isProcessing = false;
  bool _isZooming = false; 
  String uniqueCode = "";
  List<Offset?> points = [];
  int currentPage = 0;
  
  final int itemsPerPage = 12; // Ek page par 12 items
  final PageController _pageController = PageController();
  final GlobalKey _signBoundaryKey = GlobalKey(); 
  final TransformationController _transformationController = TransformationController();

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeRight, DeviceOrientation.landscapeLeft]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _pageController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _generateSecureCode() {
    if (uniqueCode.isEmpty) {
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      uniqueCode = "VR-${List.generate(5, (i) => chars[Random().nextInt(chars.length)]).join()}";
      setState(() {});
    }
  }

  Future<void> _handleFinalize(PharoahManager ph) async {
    if (points.isEmpty) return;
    setState(() => isProcessing = true);
    try {
      RenderRepaintBoundary boundary = _signBoundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List sigBytes = byteData!.buffer.asUint8List();

      String savedImgPath = await ph.saveSignatureFile(widget.challan.billNo, sigBytes);
      double totalQty = widget.challan.items.fold(0.0, (sum, item) => sum + item.qty + item.freeQty);

      await ph.addSignatureToChallan(
        challanId: widget.challan.id, 
        imagePath: savedImgPath, 
        code: uniqueCode,
        amount: widget.challan.totalAmount, 
        qty: totalQty, 
        x: 0.1, y: 0.8 // Left Receiver Box Position
      );

      if (mounted) {
        final updatedChallan = ph.saleChallans.firstWhere((c) => c.id == widget.challan.id);
        _showActionHub(ph, updatedChallan);
      }
    } catch (e) { debugPrint("Error: $e"); }
    setState(() => isProcessing = false);
  }

  void _showActionHub(PharoahManager ph, SaleChallan latest) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Document Sealed"),
        content: Text("Digital Seal Code: $uniqueCode\nNote: If company modifies items, this seal will expire."),
        actions: [
          ElevatedButton.icon(
            onPressed: () async {
              final bytes = await SaleChallanPdf.generateBytes(latest, widget.party, ph.activeCompany!);
              await FileSaver.instance.saveAs(name: "Challan_${latest.billNo}", bytes: bytes, ext: "pdf", mimeType: MimeType.pdf);
            },
            icon: const Icon(Icons.download), label: const Text("SAVE TO PHONE"),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              final bytes = await SaleChallanPdf.generateBytes(latest, widget.party, ph.activeCompany!);
              final dir = await getTemporaryDirectory();
              final file = File('${dir.path}/Challan_${latest.billNo}.pdf');
              await file.writeAsBytes(bytes);
              await Share.shareXFiles([XFile(file.path)], text: "Seal Code: $uniqueCode");
            },
            icon: const Icon(Icons.share), label: const Text("SHARE"),
          ),
          TextButton(onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst), child: const Text("FINISH")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int totalPages = (widget.challan.items.length / itemsPerPage).ceil();
    if (totalPages == 0) totalPages = 1;
    bool isAtLastPage = (currentPage == totalPages - 1);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1218),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text("Receiver Review: Page ${currentPage + 1} / $totalPages", style: const TextStyle(fontSize: 14)),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: isSignMode ? Colors.red : Colors.blueAccent),
              onPressed: () {
                // Auto jump to last page for signature
                if (!isAtLastPage) {
                  _pageController.animateToPage(totalPages - 1, duration: const Duration(milliseconds: 400), curve: Curves.ease);
                }
                _transformationController.value = Matrix4.identity();
                setState(() { isSignMode = !isSignMode; _isZooming = false; });
              },
              icon: Icon(isSignMode ? Icons.close : Icons.draw, size: 18),
              label: Text(isSignMode ? "CANCEL" : "SIGN ON LAST PAGE"),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              physics: (isSignMode || _isZooming) ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
              itemCount: totalPages,
              onPageChanged: (i) => setState(() => currentPage = i),
              itemBuilder: (context, index) {
                bool isActualLastPage = (index == totalPages - 1);
                return InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 1.0, maxScale: 4.0,
                  onInteractionStart: (_) => setState(() => _isZooming = true),
                  onInteractionEnd: (_) { if (_transformationController.value.getMaxScaleOnAxis() <= 1.0) setState(() => _isZooming = false); },
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: Container(
                        width: 800, height: 550,
                        margin: const EdgeInsets.all(20),
                        color: Colors.white,
                        child: Stack(
                          children: [
                            _buildBillLayout(index, totalPages, isActualLastPage, Provider.of<PharoahManager>(context)),
                            if (isActualLastPage && isSignMode)
                              RepaintBoundary(
                                key: _signBoundaryKey,
                                child: GestureDetector(
                                  onPanStart: (d) => _generateSecureCode(),
                                  onPanUpdate: (d) => setState(() => points.add(d.localPosition)),
                                  onPanEnd: (d) => setState(() => points.add(null)),
                                  child: Container(
                                    color: Colors.blue.withOpacity(0.05),
                                    child: CustomPaint(painter: SignaturePainter(points: points), size: const Size(800, 550)),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          _buildBottomActionPanel(Provider.of<PharoahManager>(context), isAtLastPage),
        ],
      ),
    );
  }

  Widget _buildBillLayout(int pageIdx, int totalPages, bool isLastPage, PharoahManager ph) {
    final shop = ph.activeCompany!;
    return Padding(
      padding: const EdgeInsets.all(25),
      child: Column(
        children: [
          Row(children: [
            _headerBox(290, [Text(shop.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue)), Text(shop.address, style: const TextStyle(fontSize: 9)), Text("GST: ${shop.gstin}", style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold))]),
            _headerBox(175, [const Center(child: Text("DELIVERY CHALLAN", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))), const Divider(), Text("No: ${widget.challan.billNo}", style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)), Text("Date: ${DateFormat('dd/MM/yyyy').format(widget.challan.date)}", style: const TextStyle(fontSize: 9))]),
            _headerBox(335, [const Text("CONSIGNEE:", style: TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold)), Text(widget.party.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), Text("${widget.party.city} | GST: ${widget.party.gst}", style: const TextStyle(fontSize: 9))]),
          ]),
          const SizedBox(height: 20),
          _buildTable(pageIdx),
          const Spacer(),
          if (isLastPage) ...[
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 50),
                const Text("RECEIVER SIGNATURE", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black54)),
                if (uniqueCode.isNotEmpty) Text("SEAL: $uniqueCode", style: const TextStyle(fontSize: 8, color: Colors.red, fontWeight: FontWeight.bold)),
              ]), 
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text("For ${shop.name}", style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
                const SizedBox(height: 50),
                const Text("AUTHORISED SIGNATORY", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey)),
                Text("TOTAL: ₹${widget.challan.totalAmount.toStringAsFixed(2)}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))
              ]),
            ]),
          ] else
             Row(mainAxisAlignment: MainAxisAlignment.end, children: [Text("Continued to Page ${pageIdx + 2}...", style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic))]),
        ],
      ),
    );
  }

  Widget _buildTable(int pageIdx) {
    int start = pageIdx * itemsPerPage;
    int end = (start + itemsPerPage < widget.challan.items.length) ? start + itemsPerPage : widget.challan.items.length;
    var pageItems = widget.challan.items.sublist(start, end);
    return Column(children: [
      Container(color: Colors.grey[100], child: Row(children: [
        _cell("S.N", 25, true), _cell("Qty", 55, true), _cell("Pack", 45, true), _cell("Product Description", 210, true, true), 
        _cell("Batch", 75, true), _cell("Exp", 45, true), _cell("HSN", 50, true), _cell("MRP", 55, true), 
        _cell("Rate", 55, true), _cell("GST%", 30, true), _cell("Net Total", 155, true)
      ])),
      ...pageItems.map((it) => Row(children: [
        _cell(it.srNo.toString(), 25, false), _cell("${it.qty.toInt()} + ${it.freeQty.toInt()}", 55, false), _cell(it.packing, 45, false), _cell(it.name, 210, false, true), 
        _cell(it.batch, 75, false), _cell(it.exp, 45, false), _cell(it.hsn, 50, false), _cell(it.mrp.toStringAsFixed(2), 55, false), 
        _cell(it.rate.toStringAsFixed(2), 55, false), _cell("${it.gstRate.toInt()}%", 30, false), _cell(it.total.toStringAsFixed(2), 155, false)
      ])).toList(),
    ]);
  }

  Widget _cell(String t, double w, bool b, [bool isLeft = false]) => Container(width: w, padding: const EdgeInsets.all(6), decoration: BoxDecoration(border: Border.all(color: Colors.black12, width: 0.4)), child: Text(t, textAlign: isLeft ? TextAlign.left : TextAlign.center, style: TextStyle(fontSize: 9, fontWeight: b ? FontWeight.bold : FontWeight.normal)));
  Widget _headerBox(double w, List<Widget> ch) => Container(width: w, padding: const EdgeInsets.all(8), decoration: BoxDecoration(border: Border.all(width: 0.5, color: Colors.black38)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: ch));
  
  Widget _buildBottomActionPanel(PharoahManager ph, bool isLastPage) => Container(
    padding: const EdgeInsets.all(15), color: Colors.black, 
    child: Row(children: [
      if (uniqueCode.isNotEmpty) Text("SEAL: $uniqueCode", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16)), 
      const Spacer(), 
      ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: (isLastPage && points.isNotEmpty) ? Colors.green : Colors.grey.shade900, padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15)), 
        onPressed: (!isLastPage || points.isEmpty || isProcessing) ? null : () => _handleFinalize(ph), 
        icon: isProcessing ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.lock_person), 
        label: const Text("SEAL & FINALIZE")
      )
    ])
  );
}

class SignaturePainter extends CustomPainter {
  final List<Offset?> points;
  SignaturePainter({required this.points});
  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()..color = Colors.blue[900]!..strokeCap = StrokeCap.round..strokeWidth = 4.0;
    for (int i = 0; i < points.length - 1; i++) { if (points[i] != null && points[i + 1] != null) canvas.drawLine(points[i]!, points[i + 1]!, paint); }
  }
  @override bool shouldRepaint(SignaturePainter oldDelegate) => true;
}
