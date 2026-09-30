import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/medilente_bill_model.dart';
import '../engine/medilente_direct_parser.dart';
import '../engine/medilente_pdf_extractor.dart';
import 'medilente_review_screen.dart';

class MedilenteFilePickerView extends StatefulWidget {
  final VoidCallback onBack;

  const MedilenteFilePickerView({super.key, required this.onBack});

  @override
  State<MedilenteFilePickerView> createState() => _MedilenteFilePickerViewState();
}

class _MedilenteFilePickerViewState extends State<MedilenteFilePickerView> {
  bool isProcessing = false;
  String statusMessage = "";

  void _processSelectedFile() async {
    setState(() {
      isProcessing = true;
      statusMessage = "Selecting file...";
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'csv', 'txt'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() => isProcessing = false);
        return;
      }

      final file = result.files.first;
      final bytes = file.bytes;

      if (bytes == null || bytes.isEmpty) {
        setState(() => isProcessing = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Selected file is empty!"), backgroundColor: Colors.redAccent),
          );
        }
        return;
      }

      String ext = (file.extension ?? '').toLowerCase();
      MedilenteBill? parsedBill;

      if (ext == 'pdf') {
        setState(() => statusMessage = "Extracting PDF & Converting to CSV...");
        final conv = MedilentePdfExtractor.convertPdfToCsvAndParse(bytes);
        if (conv['success'] == true) {
          parsedBill = conv['bill'] as MedilenteBill;
        } else {
          // Fallback direct parser attempt
          String raw = String.fromCharCodes(bytes);
          parsedBill = MedilenteDirectParser.parseRawText(raw);
        }
      } else {
        // Direct CSV / Text file
        setState(() => statusMessage = "Reading CSV file...");
        String text = utf8.decode(bytes, allowMalformed: true);
        parsedBill = MedilenteDirectParser.parseRawText(text);
      }

      setState(() => isProcessing = false);

      if (parsedBill != null && parsedBill.items.isNotEmpty) {
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (c) => Scaffold(
                backgroundColor: const Color(0xFF0F172A),
                body: MedilenteReviewScreen(
                  bill: parsedBill!,
                  onBack: () => Navigator.pop(c),
                ),
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Failed to parse Medilente items from this file. Please ensure it is a valid Medilente invoice."),
              backgroundColor: Colors.redAccent,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Processing Error: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
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
              const Icon(Icons.medical_services_rounded, color: Color(0xFF10B981), size: 24),
              const SizedBox(width: 10),
              const Text(
                "MEDILENTE SMART INVOICE IMPORTER",
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 35),

          // Upload File Card (No Preset Samples)
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 620),
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 50),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF10B981).withAlpha(100), width: 1.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 25, offset: Offset(0, 10))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: const BoxDecoration(color: Color(0x2610B981), shape: BoxShape.circle),
                    child: const Icon(Icons.cloud_upload_rounded, color: Color(0xFF10B981), size: 50),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    "Upload Medilente Invoice (PDF / CSV)",
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "PDF will be automatically converted to CSV in memory, parsed, and verified item-by-item with your inventory masters.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.5),
                  ),
                  const SizedBox(height: 30),
                  if (isProcessing) ...[
                    const CircularProgressIndicator(color: Color(0xFF10B981)),
                    const SizedBox(height: 14),
                    Text(statusMessage, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        onPressed: _processSelectedFile,
                        icon: const Icon(Icons.file_open_rounded, size: 20),
                        label: const Text(
                          "SELECT MEDILENTE PDF / CSV",
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.8),
                        ),
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
