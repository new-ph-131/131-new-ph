// FILE: lib/web_live_sync/sub_views/web_returns/credit_note/ui/web_credit_note_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../web_models.dart';
import '../../../../pharoah_web_manager.dart';
import '../../../../web_app_date_logic.dart';
import '../../../../../logic/gst_compliance_helper.dart';
import '../logic/credit_note_controller.dart';
import 'credit_note_header_widget.dart';
import 'credit_note_cart_widget.dart';
import 'credit_note_footer_widget.dart';

class WebCreditNoteScreen extends StatefulWidget {
  final VoidCallback onBack;
  final SaleReturn? existingRecord;
  final bool isReadOnly;
  final bool initialBreakageMode;

  const WebCreditNoteScreen({
    super.key,
    required this.onBack,
    this.existingRecord,
    this.isReadOnly = false,
    this.initialBreakageMode = false,
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
      initialBreakageMode: widget.initialBreakageMode,
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
        final bool canComm =
            GstComplianceHelper.isCommercialNoteAllowed(webPh.appConfig);
        return CallbackShortcuts(
          bindings: _controller.isReadOnly
              ? const {}
              : {
                  const SingleActivator(LogicalKeyboardKey.f2): () async {
                    if (!_controller.isSaving) {
                      bool ok = await _controller.saveCreditNote(context, webPh);
                      if (ok) widget.onBack();
                    }
                  },
                  const SingleActivator(LogicalKeyboardKey.keyP, control: true):
                      () async {
                    if (!_controller.isSaving) {
                      bool ok = await _controller.saveCreditNote(context, webPh,
                          andPrint: true);
                      if (ok) widget.onBack();
                    }
                  },
                },
          child: Focus(
            autofocus: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // TOP COMPACT COMMAND STRIP
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white10,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: widget.onBack,
                        icon: const Icon(Icons.arrow_back_rounded, size: 14),
                        label: const Text("HUB",
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                      ),
                      const Icon(Icons.assignment_return_rounded,
                          color: Color(0xFFF87171), size: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.isReadOnly
                                ? "VIEW CREDIT NOTE (AUDIT)"
                                : (widget.existingRecord != null
                                    ? "MODIFY CREDIT NOTE"
                                    : "CREDIT NOTE WORKBENCH"),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                            ),
                          ),
                          Text(
                            _controller.noteNoC.text,
                            style: const TextStyle(
                              color: Color(0xFFF87171),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      // Date Chip
                      InkWell(
                        onTap: _controller.isReadOnly
                            ? null
                            : () async {
                                final fyStart =
                                    WebAppDateLogic.getFYStart(webPh.financialYear);
                                final fyEnd =
                                    WebAppDateLogic.getFYEnd(webPh.financialYear);
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: GstComplianceHelper.clampPickerDate(
                                    _controller.selectedDate,
                                    fyStart,
                                    fyEnd,
                                  ),
                                  firstDate: fyStart,
                                  lastDate: fyEnd,
                                );
                                if (picked != null) {
                                  _controller.setDate(picked, webPh: webPh);
                                }
                              },
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.calendar_month_rounded,
                                  color: Color(0xFFF87171), size: 14),
                              const SizedBox(width: 6),
                              Text(
                                DateFormat('dd/MM/yyyy')
                                    .format(_controller.selectedDate),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // SELLABLE vs BREAKAGE segmented toggle
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _topSegBtn(
                              "SELLABLE (+)",
                              !_controller.isBreakageMode,
                              const Color(0xFF10B981),
                              _controller.isReadOnly
                                  ? null
                                  : () => _controller.toggleBreakageMode(false),
                            ),
                            _topSegBtn(
                              "EXPIRY / BREAKAGE",
                              _controller.isBreakageMode,
                              const Color(0xFFEA580C),
                              _controller.isReadOnly
                                  ? null
                                  : () => _controller.toggleBreakageMode(true),
                            ),
                          ],
                        ),
                      ),
                      // CREDIT vs CASH
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _topSegBtn(
                              "CREDIT",
                              _controller.paymentMode == "CREDIT",
                              const Color(0xFF2563EB),
                              _controller.isReadOnly
                                  ? null
                                  : () => _controller.setPaymentMode("CREDIT"),
                            ),
                            _topSegBtn(
                              "CASH",
                              _controller.paymentMode == "CASH",
                              const Color(0xFF059669),
                              _controller.isReadOnly
                                  ? null
                                  : () => _controller.setPaymentMode("CASH"),
                            ),
                          ],
                        ),
                      ),
                      if (canComm || _controller.isCommercial)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _controller.isCommercial
                                ? const Color(0x44F59E0B)
                                : const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _controller.isCommercial
                                  ? const Color(0xFFF59E0B)
                                  : Colors.white12,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _controller.isCommercial ? "COMMERCIAL" : "GST NOTE",
                                style: TextStyle(
                                  color: _controller.isCommercial
                                      ? const Color(0xFFFBBF24)
                                      : Colors.white70,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Switch.adaptive(
                                value: _controller.isCommercial,
                                activeColor: const Color(0xFFF59E0B),
                                onChanged: (_controller.isReadOnly || !canComm)
                                    ? null
                                    : (val) =>
                                        _controller.toggleCommercial(val, webPh: webPh),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                if (widget.isReadOnly) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0x22EF4444),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.redAccent.withAlpha(140)),
                    ),
                    child: const Text(
                      "READ-ONLY AUDIT VIEW: Editing & deletion are locked on this Credit Note.",
                      style: TextStyle(
                        color: Color(0xFFFCA5A5),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),

                // SPLIT WORKBENCH BODY
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 1060) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 68,
                            child: CreditNoteCartWidget(
                              controller: _controller,
                              webPh: webPh,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 32,
                            child: Column(
                              children: [
                                CreditNoteHeaderWidget(
                                  controller: _controller,
                                  webPh: webPh,
                                ),
                                const SizedBox(height: 12),
                                CreditNoteFooterWidget(
                                  controller: _controller,
                                  webPh: webPh,
                                  onSuccess: widget.onBack,
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        CreditNoteHeaderWidget(
                          controller: _controller,
                          webPh: webPh,
                        ),
                        const SizedBox(height: 12),
                        CreditNoteCartWidget(
                          controller: _controller,
                          webPh: webPh,
                        ),
                        const SizedBox(height: 12),
                        CreditNoteFooterWidget(
                          controller: _controller,
                          webPh: webPh,
                          onSuccess: widget.onBack,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _topSegBtn(
      String label, bool active, Color activeColor, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: active ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.white54,
            fontSize: 9.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
