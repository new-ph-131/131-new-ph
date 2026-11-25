// FILE: lib/web_live_sync/sub_views/web_returns/shared/web_pull_from_bill_modal.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../web_models.dart';
import '../../../pharoah_web_manager.dart';
import '../../../../logic/return_history_engine.dart';

class WebPullFromBillResultLine {
  final Medicine medicine;
  final ReturnHistoryInvoiceLine line;
  final double qty;

  const WebPullFromBillResultLine({
    required this.medicine,
    required this.line,
    required this.qty,
  });
}

class WebPullFromBillModal extends StatefulWidget {
  final bool isSale;
  final Party party;
  final PharoahWebManager webPh;
  final List<dynamic> currentCartItems;
  final String? excludeNoteId;
  final String? initialBillNo;
  final Function(List<WebPullFromBillResultLine> picked) onAddSelected;

  const WebPullFromBillModal({
    super.key,
    required this.isSale,
    required this.party,
    required this.webPh,
    this.currentCartItems = const [],
    this.excludeNoteId,
    this.initialBillNo,
    required this.onAddSelected,
  });

  @override
  State<WebPullFromBillModal> createState() => _WebPullFromBillModalState();
}

class _WebPullFromBillModalState extends State<WebPullFromBillModal> {
  final TextEditingController _billSearchC = TextEditingController();
  late List<ReturnRecentBill> _bills;
  ReturnRecentBill? _selectedBill;
  final Set<int> _checkedLineIndexes = {};
  final Map<int, TextEditingController> _qtyControllers = {};

  Color get _accent =>
      widget.isSale ? const Color(0xFFF87171) : const Color(0xFFFBBF24);
  Color get _primaryBtn =>
      widget.isSale ? const Color(0xFFDC2626) : const Color(0xFFD97706);

  @override
  void initState() {
    super.initState();
    _bills = ReturnHistoryEngine.getRecentPartyBills(
      isSale: widget.isSale,
      partyId: widget.party.id,
      partyName: widget.party.name,
      sales: widget.webPh.sales,
      purchases: widget.webPh.purchases,
      saleReturns: widget.webPh.saleReturns,
      purchaseReturns: widget.webPh.purchaseReturns,
      currentCartItems: widget.currentCartItems,
      excludeNoteId: widget.excludeNoteId,
      limit: 30,
    );
    if (_bills.isNotEmpty) {
      if (widget.initialBillNo != null && widget.initialBillNo!.trim().isNotEmpty) {
        final match = _bills.where((b) =>
            b.billNo.trim().toUpperCase() ==
            widget.initialBillNo!.trim().toUpperCase());
        _selectBill(match.isNotEmpty ? match.first : _bills.first);
      } else {
        _selectBill(_bills.first);
      }
    }
  }

  @override
  void dispose() {
    _billSearchC.dispose();
    _clearLineControllers();
    super.dispose();
  }

  void _clearLineControllers() {
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    _qtyControllers.clear();
  }

  void _selectBill(ReturnRecentBill bill) {
    _clearLineControllers();
    _checkedLineIndexes.clear();
    _selectedBill = bill;
    for (int i = 0; i < bill.lines.length; i++) {
      final ln = bill.lines[i];
      final defQty = ln.availableQty > 0 ? ln.availableQty : ln.billedQty;
      _qtyControllers[i] = TextEditingController(text: formatQty(defQty));
      if (ln.availableQty > 0) {
        _checkedLineIndexes.add(i);
      }
    }
    setState(() {});
  }

  void _selectAllAvailable() {
    if (_selectedBill == null) return;
    setState(() {
      _checkedLineIndexes.clear();
      for (int i = 0; i < _selectedBill!.lines.length; i++) {
        if (_selectedBill!.lines[i].availableQty > 0) {
          _checkedLineIndexes.add(i);
        }
      }
    });
  }

  Medicine _resolveMedicine(ReturnRecentBillLine line) {
    try {
      return widget.webPh.medicines.firstWhere(
        (m) =>
            (line.medicineID.isNotEmpty && m.id == line.medicineID) ||
            m.name.trim().toUpperCase() == line.name.trim().toUpperCase(),
      );
    } catch (_) {
      return Medicine(
        id: line.medicineID,
        name: line.name,
        packing: line.packing,
        mrp: line.mrp,
        gst: line.gstRate,
        hsnCode: line.hsn,
        rateA: line.rate,
        purRate: line.rate,
      );
    }
  }

  void _submitSelected() {
    if (_selectedBill == null || _checkedLineIndexes.isEmpty) return;
    final List<WebPullFromBillResultLine> out = [];
    for (final idx in (_checkedLineIndexes.toList()..sort())) {
      final ln = _selectedBill!.lines[idx];
      final qty = double.tryParse(_qtyControllers[idx]?.text ?? "0") ?? 0.0;
      if (qty <= 0) continue;
      out.add(WebPullFromBillResultLine(
        medicine: _resolveMedicine(ln),
        line: ln.toInvoiceLine(),
        qty: qty,
      ));
    }
    if (out.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter Qty > 0 for at least one checked item."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    Navigator.pop(context);
    widget.onAddSelected(out);
  }

  @override
  Widget build(BuildContext context) {
    final q = _billSearchC.text.trim().toLowerCase();
    final visibleBills = q.isEmpty
        ? _bills
        : _bills
            .where((b) =>
                b.billNo.toLowerCase().contains(q) ||
                b.lines.any((l) =>
                    l.name.toLowerCase().contains(q) ||
                    l.batch.toLowerCase().contains(q)))
            .toList();

    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Colors.white12),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 14, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _primaryBtn.withAlpha(50),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.receipt_long_rounded, color: _accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "PULL ITEMS FROM ${widget.isSale ? 'SALE' : 'PURCHASE'} BILL",
                  style: TextStyle(
                    color: _accent,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  "${widget.party.name} • Multi-Item Return Selector",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 820,
        height: 520,
        child: _bills.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 46, color: Colors.white.withAlpha(50)),
                    const SizedBox(height: 10),
                    Text(
                      "No active ${widget.isSale ? 'sales' : 'purchases'} found for ${widget.party.name}.",
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // LEFT: RECENT BILLS LIST
                  SizedBox(
                    width: 245,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 36,
                            child: TextField(
                              controller: _billSearchC,
                              style: const TextStyle(color: Colors.white, fontSize: 11.5),
                              decoration: InputDecoration(
                                hintText: "Search Bill, Item, Batch...",
                                hintStyle: const TextStyle(color: Colors.white38, fontSize: 10.5),
                                prefixIcon: Icon(Icons.search_rounded, color: _accent, size: 15),
                                filled: true,
                                fillColor: Colors.black26,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView.builder(
                              itemCount: visibleBills.length,
                              itemBuilder: (c, idx) {
                                final b = visibleBills[idx];
                                final bool isSel = _selectedBill?.billNo == b.billNo &&
                                    _selectedBill?.date == b.date;
                                return InkWell(
                                  onTap: () => _selectBill(b),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.all(9),
                                    decoration: BoxDecoration(
                                      color: isSel
                                          ? _primaryBtn.withAlpha(55)
                                          : const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSel ? _accent : Colors.white10,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                b.billNo,
                                                style: TextStyle(
                                                  color: isSel ? _accent : Colors.white,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 11.5,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Text(
                                              "₹${b.totalAmount.toStringAsFixed(0)}",
                                              style: const TextStyle(
                                                color: Colors.greenAccent,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          "${DateFormat('dd/MM/yy').format(b.date)} • ${b.lines.length} items",
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 9.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // RIGHT: BILL LINES CHECKLIST
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: _selectedBill == null
                          ? const Center(
                              child: Text("Select a bill on the left",
                                  style: TextStyle(color: Colors.white54)),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      "BILL ${_selectedBill!.billNo} (${DateFormat('dd/MM/yyyy').format(_selectedBill!.date)})",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: _selectAllAvailable,
                                      child: Text(
                                        "Select All Avail",
                                        style: TextStyle(color: _accent, fontSize: 11),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          setState(() => _checkedLineIndexes.clear()),
                                      child: const Text(
                                        "Clear",
                                        style: TextStyle(color: Colors.white54, fontSize: 11),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(color: Colors.white10, height: 12),
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: _selectedBill!.lines.length,
                                    itemBuilder: (c, idx) {
                                      final ln = _selectedBill!.lines[idx];
                                      final checked = _checkedLineIndexes.contains(idx);
                                      final avail = ln.availableQty > 0.0001;
                                      final qtyCtrl = _qtyControllers[idx]!;
                                      final typedQty = double.tryParse(qtyCtrl.text) ?? 0.0;
                                      final overReturn = typedQty > ln.availableQty + 0.0001;

                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 7),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: checked
                                              ? _primaryBtn.withAlpha(35)
                                              : const Color(0xFF1E293B),
                                          borderRadius: BorderRadius.circular(9),
                                          border: Border.all(
                                            color: checked
                                                ? _accent.withAlpha(160)
                                                : Colors.white10,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Checkbox(
                                              value: checked,
                                              activeColor: _primaryBtn,
                                              onChanged: (v) {
                                                setState(() {
                                                  if (v == true) {
                                                    _checkedLineIndexes.add(idx);
                                                  } else {
                                                    _checkedLineIndexes.remove(idx);
                                                  }
                                                });
                                              },
                                            ),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    "${ln.name} (${ln.packing})",
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 12,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    "Batch: ${ln.batch} • Exp: ${ln.exp} • Rate: ₹${ln.rate.toStringAsFixed(2)}${ln.discountPer > 0 ? ' (-${ln.discountPer.toStringAsFixed(1)}%)' : ''} • GST: ${ln.gstRate.toInt()}%",
                                                    style: const TextStyle(
                                                      color: Colors.white54,
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    "Billed: ${formatQty(ln.billedQty)} • Ret: ${formatQty(ln.alreadyReturnedQty)} • Avail: ${formatQty(ln.availableQty)}",
                                                    style: TextStyle(
                                                      color: avail
                                                          ? Colors.greenAccent
                                                          : Colors.redAccent,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                SizedBox(
                                                  width: 78,
                                                  height: 34,
                                                  child: TextField(
                                                    controller: qtyCtrl,
                                                    keyboardType: TextInputType.number,
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      color: overReturn
                                                          ? Colors.orangeAccent
                                                          : Colors.white,
                                                      fontWeight: FontWeight.w900,
                                                      fontSize: 12,
                                                    ),
                                                    decoration: InputDecoration(
                                                      labelText: "RET QTY",
                                                      labelStyle: const TextStyle(
                                                          color: Colors.white54, fontSize: 8.5),
                                                      filled: true,
                                                      fillColor: Colors.black26,
                                                      contentPadding:
                                                          const EdgeInsets.symmetric(horizontal: 6),
                                                      border: OutlineInputBorder(
                                                        borderRadius: BorderRadius.circular(7),
                                                        borderSide: BorderSide(
                                                          color: overReturn
                                                              ? Colors.orangeAccent
                                                              : Colors.white24,
                                                        ),
                                                      ),
                                                    ),
                                                    onChanged: (_) => setState(() {
                                                      _checkedLineIndexes.add(idx);
                                                    }),
                                                  ),
                                                ),
                                                if (overReturn)
                                                  const Padding(
                                                    padding: EdgeInsets.only(top: 2),
                                                    child: Text(
                                                      "Over-return!",
                                                      style: TextStyle(
                                                        color: Colors.orangeAccent,
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  height: 42,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _primaryBtn,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed:
                                        _checkedLineIndexes.isEmpty ? null : _submitSelected,
                                    icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
                                    label: Text(
                                      "ADD ${_checkedLineIndexes.length} SELECTED ITEMS TO NOTE",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900, fontSize: 11.5),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
