// FILE: lib/returns/sale_return_register.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../pharoah_date_controller.dart';
import '../app_date_logic.dart';
import 'sale_return_view.dart';
import '../pdf/pdf_router_service.dart';
// Note: Iske liye humein SaleReturnPdf ki zaroorat padegi aage

class SaleReturnRegister extends StatefulWidget {
  const SaleReturnRegister({super.key});

  @override
  State<SaleReturnRegister> createState() => _SaleReturnRegisterState();
}

class _SaleReturnRegisterState extends State<SaleReturnRegister> {
  String searchQuery = "";
  DateTime fromDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime toDate = DateTime.now();
  bool _isInit = false;
  String _boundFy = "";
  bool showCancelled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ph = Provider.of<PharoahManager>(context, listen: false);
    if (!_isInit || _boundFy != ph.currentFY) {
      final range = AppDateLogic.getRegisterDateRange(ph.currentFY);
      fromDate = range.fromDate;
      toDate = range.toDate;
      _boundFy = ph.currentFY;
      _isInit = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    DateTime dOnly(DateTime d) => DateTime(d.year, d.month, d.day);
    final fOnly = dOnly(fromDate);
    final tOnly = dOnly(toDate);

    // Filter Logic
    final baseList = ph.saleReturns.reversed.where((ret) {
      if (ret.isDeleted == 1) return false;
      bool matchesSearch = ret.partyName.toLowerCase().contains(searchQuery.toLowerCase()) || 
                           ret.billNo.toLowerCase().contains(searchQuery.toLowerCase());
      final rOnly = dOnly(ret.date);
      bool matchesDate = !rOnly.isBefore(fOnly) && !rOnly.isAfter(tOnly);
      return matchesSearch && matchesDate;
    }).toList();
    final int cancelledCount = baseList.where((r) => r.status == "Cancelled").length;
    final list = showCancelled
        ? baseList
        : baseList.where((r) => r.status != "Cancelled").toList();

    return Scaffold(
      backgroundColor: const Color(0xFFFFF5F5), // Light Red tint
      appBar: AppBar(
        title: const Text("Sales Return Register", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildFilterPanel(ph, cancelledCount),
          Expanded(
            child: list.isEmpty 
              ? const Center(child: Text("No Returns found."))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  itemBuilder: (context, index) => _buildReturnCard(list[index], ph),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPanel(PharoahManager ph, int cancelledCount) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.shade900,
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
      ),
      child: Column(
        children: [
          TextField(
            style: const TextStyle(color: Colors.white),
            onChanged: (v) => setState(() => searchQuery = v),
            decoration: InputDecoration(
              hintText: "Search Party or Return No...",
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
              prefixIcon: const Icon(Icons.search, color: Colors.white70),
              filled: true, fillColor: Colors.white.withOpacity(0.15),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              _dateChip("FROM: ${DateFormat('dd/MM/yy').format(fromDate)}", () async {
                DateTime? p = await PharoahDateController.pickDate(context: context, currentFY: ph.currentFY, initialDate: fromDate);
                if(p != null) setState(() => fromDate = p);
              }),
              const SizedBox(width: 10),
              _dateChip("TO: ${DateFormat('dd/MM/yy').format(toDate)}", () async {
                DateTime? p = await PharoahDateController.pickDate(context: context, currentFY: ph.currentFY, initialDate: toDate);
                if(p != null) setState(() => toDate = p);
              }),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: () => setState(() => showCancelled = !showCancelled),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: showCancelled ? Colors.white : Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      showCancelled ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                      size: 14,
                      color: showCancelled ? Colors.red.shade900 : Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "Show Cancelled Returns ($cancelledCount)",
                      style: TextStyle(
                        color: showCancelled ? Colors.red.shade900 : Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateChip(String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white24)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.calendar_today, size: 12, color: Colors.white70),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReturnCard(SaleReturn ret, PharoahManager ph) {
    bool isBreakage = ret.returnType == "Breakage";
    bool isCancelled = ret.status == "Cancelled";
    return Card(
      elevation: isCancelled ? 0.5 : 2,
      color: isCancelled ? Colors.red.shade50.withOpacity(0.55) : Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: isCancelled ? BorderSide(color: Colors.red.shade200) : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _showActionMenu(ret, ph),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isCancelled ? Colors.red.shade100 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isCancelled ? Icons.block_rounded : Icons.assignment_return_rounded,
                  color: isCancelled ? Colors.red.shade700 : Colors.red.shade900,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ret.partyName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isCancelled ? Colors.black54 : Colors.black87,
                      ),
                    ),
                    Text(
                      "No: ${ret.billNo} • ${DateFormat('dd/MM/yy').format(ret.date)}",
                      style: TextStyle(
                        color: isCancelled ? Colors.red.shade400 : Colors.grey,
                        fontSize: 11,
                        decoration: isCancelled ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _typeBadge(ret.returnType, isBreakage),
                        if (ret.isCommercial)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(5)),
                            child: Text("COMMERCIAL", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                          ),
                        if (isCancelled)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(5), border: Border.all(color: Colors.red.shade300)),
                            child: Text("CANCELLED", style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.red.shade900)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                "₹${ret.totalAmount.toStringAsFixed(2)}",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: isCancelled ? Colors.grey : Colors.red.shade900,
                  decoration: isCancelled ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeBadge(String type, bool isBreakage) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isBreakage ? Colors.orange.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(type.toUpperCase(), style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: isBreakage ? Colors.orange.shade900 : Colors.blue.shade900)),
    );
  }

  void _showActionMenu(SaleReturn ret, PharoahManager ph) {
    final bool isCancelled = ret.status == "Cancelled";
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (c) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ret.partyName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Divider(),
            _menuTile(Icons.visibility_outlined, "View Return Items", Colors.blue, () {
              Navigator.pop(c);
              Navigator.push(context, MaterialPageRoute(builder: (c) => SaleReturnView(existingRecord: ret, isReadOnly: true)));
            }),
            _menuTile(Icons.print_rounded, "Print Credit Note", Colors.teal, () async {
              Navigator.pop(c);
              final party = ph.parties.firstWhere(
                (p) => (ret.partyId.isNotEmpty && p.id == ret.partyId) ||
                       p.name.trim().toLowerCase() == ret.partyName.trim().toLowerCase(),
                orElse: () => Party(
                  id: ret.partyId.isNotEmpty ? ret.partyId : "0",
                  name: ret.partyName,
                  gst: ret.partyGstin,
                  state: ret.partyState.isNotEmpty ? ret.partyState : (ph.activeCompany?.state ?? "Rajasthan"),
                ),
              );
              await PdfRouterService.printCreditNote(returnObj: ret, party: party, ph: ph);
            }),
            if (!isCancelled)
              _menuTile(Icons.block_rounded, "Cancel Return (Reverse Stock)", Colors.orange.shade900, () {
                Navigator.pop(c);
                _confirmCancel(ret, ph);
              }),
            _menuTile(Icons.delete_forever_rounded, "Delete Permanently", Colors.red, () {
              Navigator.pop(c);
              _confirmDelete(ret, ph);
            }),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _menuTile(IconData icon, String t, Color c, VoidCallback onTap) => 
      ListTile(leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: c.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: c, size: 20)), title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), onTap: onTap);

  void _confirmCancel(SaleReturn ret, PharoahManager ph) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Cancel Return?"),
        content: Text(
          "This will mark Credit Note ${ret.billNo} as CANCELLED, reverse any stock added by this return, and neutralize the customer ledger balance while keeping the voucher in your audit trail.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("KEEP ACTIVE")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
            onPressed: () {
              ph.cancelReturn(ret.id, true);
              Navigator.pop(c);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("🚫 Return ${ret.billNo} Cancelled & Stock Reversed!"), backgroundColor: Colors.orange.shade900),
              );
            },
            child: const Text("YES, CANCEL RETURN", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(SaleReturn ret, PharoahManager ph) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Delete Return?"),
        content: const Text("This will reverse stock and delete the credit note permanently."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () {
            ph.deleteSaleReturn(ret.id);
            Navigator.pop(c);
          }, child: const Text("YES, DELETE")),
        ],
      ),
    );
  }
}
