// FILE: lib/returns/purchase_return_register.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../pharoah_date_controller.dart';
import '../app_date_logic.dart';
import 'purchase_return_view.dart';

class PurchaseReturnRegister extends StatefulWidget {
  const PurchaseReturnRegister({super.key});

  @override
  State<PurchaseReturnRegister> createState() => _PurchaseReturnRegisterState();
}

class _PurchaseReturnRegisterState extends State<PurchaseReturnRegister> {
  String searchQuery = "";
  DateTime fromDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime toDate = DateTime.now();
  bool _isInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final ph = Provider.of<PharoahManager>(context, listen: false);
      toDate = AppDateLogic.getSmartDate(ph.currentFY);
      fromDate = toDate.subtract(const Duration(days: 30));
      DateTime fyStart = AppDateLogic.getFYStart(ph.currentFY);
      if (fromDate.isBefore(fyStart)) fromDate = fyStart;
      _isInit = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    // LOGIC: Filter Purchase Returns
    final list = ph.purchaseReturns.reversed.where((ret) {
      bool matchesSearch = ret.distributorName.toLowerCase().contains(searchQuery.toLowerCase()) || 
                           ret.billNo.toLowerCase().contains(searchQuery.toLowerCase());
      bool matchesDate = ret.date.isAfter(fromDate.subtract(const Duration(days: 1))) && 
                         ret.date.isBefore(toDate.add(const Duration(days: 1)));
      return matchesSearch && matchesDate;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFFBF7F3), // Light Brownish tint
      appBar: AppBar(
        title: const Text("Purchase Return Register", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        backgroundColor: Colors.brown.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.picture_as_pdf_outlined), onPressed: () {
            // Future PDF Report Logic
          }),
        ],
      ),
      body: Column(
        children: [
          _buildFilterPanel(ph),
          Expanded(
            child: list.isEmpty 
              ? const Center(child: Text("No Debit Notes found."))
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

  Widget _buildFilterPanel(PharoahManager ph) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.brown.shade800,
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
      ),
      child: Column(
        children: [
          TextField(
            style: const TextStyle(color: Colors.white),
            onChanged: (v) => setState(() => searchQuery = v),
            decoration: InputDecoration(
              hintText: "Search Supplier or Debit Note No...",
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
          )
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

  Widget _buildReturnCard(PurchaseReturn ret, PharoahManager ph) {
    bool isBreakage = ret.returnType == "Breakage";
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: () => _showActionMenu(ret, ph),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.brown.shade50, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.remove_shopping_cart_rounded, color: Colors.brown.shade800),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ret.distributorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text("DN No: ${ret.billNo} • ${DateFormat('dd/MM/yy').format(ret.date)}", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    const SizedBox(height: 4),
                    _typeBadge(ret.returnType, isBreakage),
                  ],
                ),
              ),
              Text("₹${ret.totalAmount.toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.brown.shade900)),
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

  void _showActionMenu(PurchaseReturn ret, PharoahManager ph) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (c) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ret.distributorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Divider(),
            _menuTile(Icons.visibility_outlined, "View DN Items", Colors.blue, () {
              Navigator.pop(c);
              Navigator.push(context, MaterialPageRoute(builder: (c) => PurchaseReturnView())); // Can add readOnly later
            }),
            _menuTile(Icons.print_rounded, "Print Debit Note", Colors.teal, () {
              Navigator.pop(c);
              // Future PDF Logic
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

  void _confirmDelete(PurchaseReturn ret, PharoahManager ph) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Delete Debit Note?"),
        content: const Text("This will reverse stock and delete the return record permanently."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () {
            ph.deletePurchaseReturn(ret.id);
            Navigator.pop(c);
          }, child: const Text("YES, DELETE", style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }
}
