import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/amazon_bill_model.dart';
import '../engine/amazon_direct_parser.dart';
import '../engine/amazon_pdf_extractor.dart';

class AmazonFilePickerView extends StatefulWidget {
  final VoidCallback onBack;
  final Function(AmazonBill) onBillLoaded;

  const AmazonFilePickerView({
    super.key,
    required this.onBack,
    required this.onBillLoaded,
  });

  @override
  State<AmazonFilePickerView> createState() => _AmazonFilePickerViewState();
}

class _AmazonFilePickerViewState extends State<AmazonFilePickerView> {
  bool isProcessing = false;
  String statusMessage = "";

  void _processSelectedFile() async {
    setState(() {
      isProcessing = true;
      statusMessage = "Opening file browser...";
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      if (result == null || result.files.isEmpty) {
        setState(() => isProcessing = false);
        return;
      }

      final file = result.files.first;
      setState(() => statusMessage = "Reading file: ${file.name}...");

      Uint8List? bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception("File is empty.");
      }

      setState(() => statusMessage = "Extracting text...");
      String rawText = await AmazonPdfExtractor.extractTextAsync(bytes);

      setState(() => statusMessage = "Parsing Amagen / Marg Invoice...");
      AmazonBill bill = AmazonDirectParser.parseRawText(rawText);

      setState(() => isProcessing = false);
      widget.onBillLoaded(bill);
    } catch (e) {
      setState(() => isProcessing = false);
      if (mounted) {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text("Extraction Error", style: TextStyle(color: Colors.white, fontSize: 14)),
            content: Text("$e", style: const TextStyle(color: Colors.white70, fontSize: 12)),
            actions: [
              ElevatedButton(onPressed: () => Navigator.pop(c), child: const Text("OK")),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white12, foregroundColor: Colors.white),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text("BACK TO SMART HUB", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 16),
              const Icon(Icons.shopping_bag_rounded, color: Color(0xFFF59E0B), size: 24),
              const SizedBox(width: 10),
              const Text(
                "AMAGEN / UNIVERSAL MARG INVOICE IMPORTER",
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 35),
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 640),
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 50),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFF59E0B).withAlpha(100), width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: const BoxDecoration(color: Color(0x26F59E0B), shape: BoxShape.circle),
                    child: const Icon(Icons.cloud_upload_rounded, color: Color(0xFFF59E0B), size: 50),
                  ),
                  const SizedBox(height: 22),
                  const Text("Upload Amagen Pharma Invoice PDF", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    "Intra-state GST (CGST + SGST), Free Quantity, and 1X10/1*15 packing auto-detected seamlessly.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 11.5, height: 1.5),
                  ),
                  const SizedBox(height: 30),
                  if (isProcessing) ...[
                    const CircularProgressIndicator(color: Color(0xFFF59E0B)),
                    const SizedBox(height: 14),
                    Text(statusMessage, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        onPressed: _processSelectedFile,
                        icon: const Icon(Icons.file_open_rounded, size: 20),
                        label: const Text("SELECT AMAGEN PHARMA PDF", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
