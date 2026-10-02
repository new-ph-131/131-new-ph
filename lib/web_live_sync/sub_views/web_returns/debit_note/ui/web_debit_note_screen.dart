// FILE: lib/web_live_sync/sub_views/web_returns/debit_note/ui/web_debit_note_screen.dart
// ignore_for_file: prefer_const_constructors, unnecessary_const

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../web_models.dart';
import '../../../../pharoah_web_manager.dart';
import '../logic/debit_note_controller.dart';
import 'debit_note_header_widget.dart';
import 'debit_note_cart_widget.dart';
import 'debit_note_footer_widget.dart';

class WebDebitNoteScreen extends StatefulWidget {
  final VoidCallback onBack;
  final PurchaseReturn? existingRecord;
  final bool isReadOnly;

  const WebDebitNoteScreen({
    super.key,
    required this.onBack,
    this.existingRecord,
    this.isReadOnly = false,
  });

  @override
  State<WebDebitNoteScreen> createState() => _WebDebitNoteScreenState();
}

class _WebDebitNoteScreenState extends State<WebDebitNoteScreen> {
  late final DebitNoteController _controller;

  @override
  void initState() {
    super.initState();
    _controller = DebitNoteController();
    final webPh = Provider.of<PharoahWebManager>(context, listen: false);
    _controller.init(
      webPh: webPh,
      existingRecord: widget.existingRecord,
      readOnly: widget.isReadOnly,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white12,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded, size: 14),
                  label: const Text("BACK TO RETURNS HUB", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.remove_shopping_cart_rounded, color: Color(0xFFFBBF24), size: 20),
                const SizedBox(width: 8),
                Text(
                  widget.isReadOnly
                      ? "VIEW DEBIT NOTE"
                      : (widget.existingRecord != null ? "MODIFY DEBIT NOTE" : "NEW PURCHASE RETURN / DEBIT NOTE"),
                  style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                ),
              ],
            ),
            const SizedBox(height: 14),

            DebitNoteHeaderWidget(controller: _controller, webPh: webPh),
            const SizedBox(height: 14),

            DebitNoteCartWidget(controller: _controller, webPh: webPh),
            const SizedBox(height: 14),

            DebitNoteFooterWidget(
              controller: _controller,
              webPh: webPh,
              onSuccess: widget.onBack,
            ),
          ],
        );
      },
    );
  }
}
