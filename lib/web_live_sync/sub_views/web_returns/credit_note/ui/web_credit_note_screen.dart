// FILE: lib/web_live_sync/sub_views/web_returns/credit_note/ui/web_credit_note_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../web_models.dart';
import '../../../../pharoah_web_manager.dart';
import '../logic/credit_note_controller.dart';
import 'credit_note_header_widget.dart';
import 'credit_note_cart_widget.dart';
import 'credit_note_footer_widget.dart';

class WebCreditNoteScreen extends StatefulWidget {
  final VoidCallback onBack;
  final SaleReturn? existingRecord;
  final bool isReadOnly;

  const WebCreditNoteScreen({
    super.key,
    required this.onBack,
    this.existingRecord,
    this.isReadOnly = false,
  });

  @override
  State<WebCreditNoteScreen> createState() => _WebCreditNoteScreenState();
}

class _WebCreditNoteScreenState extends State<WebCreditNoteScreen> {
  late final CreditNoteController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CreditNoteController();
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
                const Icon(Icons.assignment_return_rounded, color: Color(0xFFF87171), size: 20),
                const SizedBox(width: 8),
                Text(
                  widget.isReadOnly
                      ? "VIEW CREDIT NOTE"
                      : (widget.existingRecord != null ? "MODIFY CREDIT NOTE" : "NEW SALE RETURN / CREDIT NOTE"),
                  style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                ),
              ],
            ),
            const SizedBox(height: 14),

            CreditNoteHeaderWidget(controller: _controller, webPh: webPh),
            const SizedBox(height: 14),

            CreditNoteCartWidget(controller: _controller, webPh: webPh),
            const SizedBox(height: 14),

            CreditNoteFooterWidget(
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
