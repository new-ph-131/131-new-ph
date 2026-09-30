// FILE: lib/challans/sale_challan_register.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:io'; 
import '../pharoah_manager.dart';
import '../models.dart';
import '../pharoah_date_controller.dart';
import '../app_date_logic.dart';
import 'sale_challan_view.dart';
import 'challan_signature_view.dart'; 
import '../pdf/pdf_router_service.dart';
import '../pdf/sale_challan_report_pdf.dart';

class SaleChallanRegister extends StatefulWidget {
  const SaleChallanRegister({super.key});

  @override
  State<SaleChallanRegister> createState() => _SaleChallanRegisterState();
}

class _SaleChallanRegisterState extends State<SaleChallanRegister> {
  String searchQuery = "";
  DateTime fromDate = DateTime.now();
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

    final list = ph.saleChallans.reversed.where((ch) {
      bool matchesSearch = ch.partyName.toLowerCase().contains(searchQuery.toLowerCase()) || 
                           ch.billNo.toLowerCase().contains(searchQuery.toLowerCase());
      bool matchesDate = ch.date.isAfter(fromDate.subtract(const Duration(days: 1))) && 
                         ch.date.isBefore(toDate.add(const Duration(days: 1)));
      return matchesSearch && matchesDate;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        title: const Text("Sale Challan Register", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined), 
            tooltip: "Export Summary Report",
            onPressed: () async {
              if (ph.activeCompany != null && list.isNotEmpty) {
                await SaleChallanReportPdf.generate(list, fromDate, toDate, ph.activeCompany!);
              }
            }
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterPanel(ph),
          Expanded(
            child: list.isEmpty 
              ? const Center(child: Text("No Challans found."))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  itemBuilder: (context, index) => _buildChallanCard(list[index], ph),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPanel(PharoahManager ph) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF1A237E),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
      ),
      child: Column(
        children: [
          TextField(
            style: const TextStyle(color: Colors.white),
            onChanged: (v) => setState(() => searchQuery = v),
            decoration: InputDecoration(
              hintText: "Search Party or Challan No...",
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
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

  Widget _buildChallanCard(SaleChallan ch, PharoahManager ph) {
    bool isPending = ch.status == "Pending";
    
    // --- INTEGRITY LOGIC ---
    bool hasSign = ch.isSigned && ch.sigHistory.isNotEmpty;
    bool isTampered = false;
    if (hasSign) {
      isTampered = ch.totalAmount.toStringAsFixed(2) != ch.sigHistory.last.signedAmount.toStringAsFixed(2);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: isTampered ? Colors.orange : Colors.transparent, width: 1.5)
      ),
      child: InkWell(
        onTap: () => _showActionMenu(ch, ph),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isTampered ? Colors.orange.withOpacity(0.1) : const Color(0xFF1A237E).withOpacity(0.05), 
                  borderRadius: BorderRadius.circular(12)
                ),
                child: Icon(
                  isTampered ? Icons.warning_amber_rounded : Icons.local_shipping_rounded, 
                  color: isTampered ? Colors.orange : const Color(0xFF1A237E)
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ch.partyName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    Text("${ch.billNo} • ${DateFormat('dd/MM/yyyy').format(ch.date)}", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    if (isTampered) const Text("⚠️ EDITED AFTER SIGNING", style: TextStyle(color: Colors.orange, fontSize: 8, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              // --- 📬 SMART DISPATCH (MAIL) ---
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (ph.config.isMailActive)
                    IconButton(
                      icon: Icon(
                        ph.config.isAuditMode ? Icons.forward_to_inbox_rounded : Icons.alternate_email, 
                        color: ph.config.isAuditMode ? Colors.indigo.shade900 : const Color(0xFF1A237E), 
                        size: 22
                      ),
                      tooltip: ph.config.isAuditMode ? "Forward to CA (Auditor)" : "Mail to Customer",
                      onPressed: () {
                        final partyObj = ph.parties.firstWhere(
                          (p) => p.name == ch.partyName, 
                          orElse: () => Party(id: 'temp', name: ch.partyName, gst: ch.partyGstin, state: ch.partyState)
                        );
                        PdfRouterService.emailDocument(
                          context: context,
                          doc: ch,
                          party: partyObj,
                          ph: ph,
                          type: "CHALLAN",
                        );
                      },
                    ),
                  const SizedBox(width: 5),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("₹${ch.totalAmount.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1A237E))),
                      Row(
                        children: [
                          if (hasSign) Icon(Icons.verified, size: 14, color: isTampered ? Colors.orange : Colors.green),
                          const SizedBox(width: 4),
                          _statusBadge(ch.status, isPending),
                        ],
                      ),
                    ],
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(String status, bool isPending) {
    return Container(
      margin: const EdgeInsets.only(top: 5),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: isPending ? Colors.orange.shade50 : Colors.green.shade50, borderRadius: BorderRadius.circular(5)),
      child: Text(status.toUpperCase(), style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: isPending ? Colors.orange.shade900 : Colors.green.shade900)),
    );
  }

  void _showActionMenu(SaleChallan ch, PharoahManager ph) {
    bool hasSign = ch.isSigned && ch.sigHistory.isNotEmpty;
    bool isTampered = false;
    if (hasSign) {
      isTampered = ch.totalAmount.toStringAsFixed(2) != ch.sigHistory.last.signedAmount.toStringAsFixed(2);
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (c) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ch.partyName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (isTampered) const Text("⚠️ DETAILS CHANGED AFTER SIGNING", style: TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.bold)),
            const Divider(),
            
            if (hasSign)
              _menuTile(Icons.assignment_turned_in, "View Signature Proof", Colors.green, () {
                Navigator.pop(c);
                _showSignaturePreview(ch);
              }),

            if (isTampered && ch.status != "Billed")
              _menuTile(Icons.draw_rounded, "Re-Verify (Re-Sign)", Colors.orange, () {
                Navigator.pop(c);
                _reSignChallan(ch, ph);
              }),

            _menuTile(Icons.visibility, "View Items", Colors.blue, () {
              Navigator.pop(c);
              Navigator.push(context, MaterialPageRoute(builder: (c) => SaleChallanView(existingRecord: ch, isReadOnly: true)));
            }),

            _menuTile(Icons.edit, "Modify Challan", ch.status == "Billed" ? Colors.grey : Colors.orange, () {
              if (ch.status == "Billed") {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Locked: Bill has already been generated!")));
                return;
              }
              Navigator.pop(c);
              Navigator.push(context, MaterialPageRoute(builder: (c) => SaleChallanView(existingRecord: ch)));
            }),

            _menuTile(Icons.print, "Print / Share PDF", Colors.teal, () async {
              Navigator.pop(c); 
              if (ph.activeCompany == null) return;
              Party targetParty;
              try {
                targetParty = ph.parties.firstWhere((p) => p.name == ch.partyName);
              } catch (e) {
                targetParty = Party(id: 'temp', name: ch.partyName, gst: ch.partyGstin, state: ch.partyState);
              }
              await PdfRouterService.printChallan(
                challan: ch, 
                party: targetParty, 
                ph: ph, 
                isSaleChallan: true
              );
            }),

            _menuTile(Icons.delete_forever, "Delete Challan", Colors.red, () {
              Navigator.pop(c);
              _confirmDelete(ch, ph);
            }),
          ],
        ),
      ),
    );
  }

  Widget _menuTile(IconData icon, String t, Color c, VoidCallback onTap) => ListTile(leading: Icon(icon, color: c), title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)), onTap: onTap);

  void _showSignaturePreview(SaleChallan ch) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text("Digital Seal: ${ch.sigHistory.last.verificationCode}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Verified on: ${DateFormat('dd/MM/yy HH:mm').format(ch.sigHistory.last.signDate)}", style: const TextStyle(fontSize: 10)),
            const SizedBox(height: 15),
            Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
              child: Image.file(File(ch.sigHistory.last.imagePath)),
            ),
            const Divider(height: 30),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Signed At Amount:", style: TextStyle(fontSize: 11)),
              Text("₹${ch.sigHistory.last.signedAmount.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            ]),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("CLOSE"))],
      ),
    );
  }

  void _reSignChallan(SaleChallan ch, PharoahManager ph) {
    Party party = ph.parties.firstWhere((p) => p.name == ch.partyName, orElse: () => Party(id:'0', name: ch.partyName));
    Navigator.push(context, MaterialPageRoute(
      builder: (c) => ChallanSignatureView(challan: ch, party: party)
    ));
  }

  void _confirmDelete(SaleChallan ch, PharoahManager ph) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Delete Challan?"),
        content: const Text("Are you sure? This will remove the record and reverse stock impact."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("NO")),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () {
            ph.deleteSaleChallan(ch.id);
            Navigator.pop(c);
          }, child: const Text("YES, DELETE", style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }
}
