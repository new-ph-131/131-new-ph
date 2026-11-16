// FILE: lib/challans/sale_challan_register.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:io'; 
import '../pharoah_manager.dart';
import '../models.dart';
import '../logic/pharoah_numbering_engine.dart';
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
  String fyFilter = "ALL"; // ALL | CURRENT | CARRY
  String statusFilter = "ACTIVE"; // ACTIVE | CANCELLED
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  bool _isInit = false;
  String _boundFy = "";

  bool _isCarryForward(SaleChallan ch, String currentFy) {
    return isStrictCarryForwardFy(ch.effectiveOriginalFy, currentFy);
  }

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

    final list = ph.saleChallans.where((ch) {
      if (ch.isDeleted == 1) return false;
      final bool isCancelled = ch.status == "Cancelled";
      final bool isPending = ch.status == "Pending";
      final bool isBilled = ch.status == "Billed";
      if (statusFilter == "ACTIVE" && isCancelled) return false;
      if (statusFilter == "PENDING" && !isPending) return false;
      if (statusFilter == "BILLED" && !isBilled) return false;
      if (statusFilter == "CANCELLED" && !isCancelled) return false;
      bool matchesSearch = ch.partyName.toLowerCase().contains(searchQuery.toLowerCase()) ||
                           ch.billNo.toLowerCase().contains(searchQuery.toLowerCase());
      final cOnly = dOnly(ch.date);
      bool isCarry = _isCarryForward(ch, ph.currentFY);
      final bool isBilledCfInActiveFy = isCarry && isBilled &&
          (ch.billedInFy.trim().isEmpty || normalizeFyString(ch.billedInFy) == normalizeFyString(ph.currentFY));
      bool matchesDate = (!cOnly.isBefore(fOnly) && !cOnly.isAfter(tOnly)) ||
          isPending ||
          statusFilter == "CANCELLED" ||
          statusFilter == "BILLED" ||
          isBilledCfInActiveFy;
      bool matchesFy = fyFilter == "ALL" ||
          (fyFilter == "CURRENT" && !isCarry) ||
          (fyFilter == "CARRY" && isCarry);
      return matchesSearch && matchesDate && matchesFy;
    }).toList()
      ..sort((a, b) {
        final c = b.date.compareTo(a.date);
        return c != 0 ? c : b.updatedAt.compareTo(a.updatedAt);
      });

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
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _fyTabChip("ALL", "ALL"),
              const SizedBox(width: 8),
              _fyTabChip("CURRENT FY", "CURRENT"),
              const SizedBox(width: 8),
              _fyTabChip("CARRY-FORWARD", "CARRY"),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _statusTabChip("ALL ACTIVE", "ACTIVE"),
              const SizedBox(width: 8),
              _statusTabChip("PENDING", "PENDING"),
              const SizedBox(width: 8),
              _statusTabChip("BILLED", "BILLED"),
              const SizedBox(width: 8),
              _statusTabChip("CANCELLED", "CANCELLED"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fyTabChip(String label, String key) {
    final bool selected = fyFilter == key;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => fyFilter = key),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? Colors.white : Colors.white24),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? const Color(0xFF1A237E) : Colors.white70,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusTabChip(String label, String key) {
    final bool selected = statusFilter == key;
    Color textColor = const Color(0xFF1A237E);
    if (key == "CANCELLED") {
      textColor = Colors.red.shade900;
    } else if (key == "PENDING") {
      textColor = Colors.amber.shade900;
    } else if (key == "BILLED") {
      textColor = Colors.teal.shade900;
    }
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => statusFilter = key),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? Colors.white : Colors.white24),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? textColor : Colors.white70,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
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
    bool isCancelled = ch.status == "Cancelled";
    bool isWeb = PharoahNumberingEngine.isWebChallanRecord(ch);
    bool isCarry = _isCarryForward(ch, ph.currentFY);
    final fwd = ph.getForwardChallanStatus(ch.id, isPurchase: false);
    final String cfLabel = (!ch.hasValidDate && ch.effectiveOriginalFy.isEmpty)
        ? "CF / LEGACY"
        : (ch.effectiveOriginalFy.isNotEmpty ? "CF • ${ch.effectiveOriginalFy}" : "CF / LEGACY");
    
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
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text("${ch.billNo} • ${DateFormat('dd/MM/yyyy').format(ch.date)}", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: isWeb ? Colors.blue.shade50 : Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: isWeb ? Colors.blue.shade300 : Colors.indigo.shade300, width: 0.5),
                          ),
                          child: Text(
                            isWeb ? "WEB PORTAL" : "APP",
                            style: TextStyle(color: isWeb ? Colors.blue.shade900 : Colors.indigo.shade900, fontSize: 7.5, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                    if (isCarry || fwd.billedFy != null || fwd.shiftedFy != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (isCarry) _fyOriginBadge(cfLabel, Colors.deepPurple),
                            if (isCarry && ch.status == "Billed" && ch.billedInvoiceNo.isNotEmpty)
                              _fyOriginBadge("BILL: ${ch.billedInvoiceNo}", Colors.teal),
                            if (fwd.billedFy != null)
                              _fyOriginBadge(ph.getBilledInvoiceNoForChallan(ch.id, isPurchase: false, forwardFy: fwd.billedFy) != null && ph.getBilledInvoiceNoForChallan(ch.id, isPurchase: false, forwardFy: fwd.billedFy)!.isNotEmpty ? "BILLED IN ${fwd.billedFy} (${ph.getBilledInvoiceNoForChallan(ch.id, isPurchase: false, forwardFy: fwd.billedFy)})" : "BILLED IN ${fwd.billedFy}", Colors.teal)
                            else if (fwd.shiftedFy != null)
                              _fyOriginBadge("SHIFTED → ${fwd.shiftedFy}", Colors.indigo),
                          ],
                        ),
                      ),
                    if (isTampered) const Text("⚠️ EDITED AFTER SIGNING", style: TextStyle(color: Colors.orange, fontSize: 8, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              // --- 📬 SMART DISPATCH (MAIL) ---
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (ph.config.isMailActive && !isCancelled)
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

  Widget _fyOriginBadge(String text, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.shade300, width: 0.6),
      ),
      child: Text(
        text,
        style: TextStyle(color: color.shade900, fontSize: 8, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _statusBadge(String status, bool isPending) {
    final bool isCancelled = status.trim().toLowerCase() == "cancelled";
    final Color bg = isCancelled ? Colors.red.shade50 : (isPending ? Colors.orange.shade50 : Colors.green.shade50);
    final Color fg = isCancelled ? Colors.red.shade900 : (isPending ? Colors.orange.shade900 : Colors.green.shade900);
    return Container(
      margin: const EdgeInsets.only(top: 5),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
      child: Text(status.toUpperCase(), style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: fg)),
    );
  }

  void _showActionMenu(SaleChallan ch, PharoahManager ph) {
    bool hasSign = ch.isSigned && ch.sigHistory.isNotEmpty;
    bool isTampered = false;
    if (hasSign) {
      isTampered = ch.totalAmount.toStringAsFixed(2) != ch.sigHistory.last.signedAmount.toStringAsFixed(2);
    }
    final fwd = ph.getForwardChallanStatus(ch.id, isPurchase: false);
    final bool isCancelled = ch.status == "Cancelled";
    final bool isBilledLocked = ch.status == "Billed" || fwd.billedFy != null;
    final bool isLocked = isBilledLocked || isCancelled;
    final bool canDelete = !isBilledLocked && ph.canDeleteSaleChallan(ch.id);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (c) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ch.partyName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (isTampered && !isCancelled) const Text("⚠️ DETAILS CHANGED AFTER SIGNING", style: TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.bold)),
            const Divider(),
            
            if (hasSign)
              _menuTile(Icons.assignment_turned_in, "View Signature Proof", Colors.green, () {
                Navigator.pop(c);
                _showSignaturePreview(ch);
              }),

            if (isTampered && !isLocked)
              _menuTile(Icons.draw_rounded, "Re-Verify (Re-Sign)", Colors.orange, () {
                Navigator.pop(c);
                _reSignChallan(ch, ph);
              }),

            _menuTile(Icons.visibility, "View Items", Colors.blue, () {
              Navigator.pop(c);
              Navigator.push(context, MaterialPageRoute(builder: (c) => SaleChallanView(existingRecord: ch, isReadOnly: true)));
            }),

            _menuTile(
              isLocked ? Icons.lock_outline : Icons.edit,
              isCancelled ? "Modify Locked (Cancelled)" : (isBilledLocked ? "Modify Locked (Billed)" : "Modify Challan"),
              isLocked ? Colors.grey : Colors.orange,
              () {
                if (isLocked) {
                  Navigator.pop(c);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(isCancelled ? "🔒 Locked: Cancelled challan cannot be modified." : "🔒 Locked: Bill already generated. Delete linked Bill first."),
                  ));
                  return;
                }
                Navigator.pop(c);
                Navigator.push(context, MaterialPageRoute(builder: (c) => SaleChallanView(existingRecord: ch)));
              },
            ),

            _menuTile(
              isCancelled ? Icons.lock_outline : Icons.print,
              isCancelled ? "Print Locked (Cancelled)" : "Print / Share PDF",
              isCancelled ? Colors.grey : Colors.teal,
              () async {
                if (isCancelled) {
                  Navigator.pop(c);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("🔒 Locked: Cancelled challan cannot be printed.")),
                  );
                  return;
                }
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
              },
            ),

            _menuTile(
              isBilledLocked
                  ? Icons.lock_outline
                  : (canDelete
                      ? Icons.delete_forever
                      : (isCancelled ? Icons.lock_outline : Icons.cancel_outlined)),
              isBilledLocked
                  ? "Delete Locked (Billed)"
                  : (canDelete
                      ? (isCancelled ? "Delete Cancelled (Last)" : "Delete Draft (Last)")
                      : (isCancelled ? "Locked: Cancelled (Middle)" : "Cancel Challan")),
              isBilledLocked
                  ? Colors.grey
                  : (canDelete
                      ? Colors.red
                      : (isCancelled ? Colors.grey : Colors.deepOrange)),
              () {
                if (isBilledLocked) {
                  Navigator.pop(c);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("🔒 Locked: Bill already generated. Delete linked Bill first."),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                Navigator.pop(c);
                if (canDelete) {
                  _confirmDelete(ch, ph);
                } else if (isCancelled) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("🔒 Cancelled challan is retained for audit trail compliance. Only the last challan in series can be deleted."),
                      backgroundColor: Colors.orange,
                    ),
                  );
                } else {
                  _confirmCancel(ch, ph);
                }
              },
            ),
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
    final fwd = ph.getForwardChallanStatus(ch.id, isPurchase: false);
    if (ch.status == "Billed" || fwd.billedFy != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🔒 Locked: Bill already generated. Delete linked Bill first."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Delete Challan?"),
        content: Text(
          ch.status == "Cancelled"
              ? "Are you sure? This will permanently delete cancelled challan ${ch.billNo} and reclaim the number."
              : "Are you sure? This will remove the record and reverse stock impact.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("NO")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final bool ok = await ph.deleteSaleChallanAsync(ch.id);
              if (c.mounted) Navigator.pop(c);
              if (!ok && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: const Text("🔒 Delete blocked: Only the last eligible challan can be permanently deleted."),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            child: const Text("YES, DELETE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmCancel(SaleChallan ch, PharoahManager ph) {
    final fwd = ph.getForwardChallanStatus(ch.id, isPurchase: false);
    if (ch.status == "Billed" || fwd.billedFy != null || ch.status == "Cancelled") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🔒 Cannot cancel Billed or already Cancelled challan."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Cancel Challan?"),
        content: Text("Challan ${ch.billNo} will be marked Cancelled for audit trail. Its number will not be reused."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("NO")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
            onPressed: () async {
              final bool ok = await ph.cancelSaleChallan(ch.id);
              if (c.mounted) Navigator.pop(c);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? "🚫 Sale Challan ${ch.billNo} Cancelled (audit preserved)." : "🔒 Could not cancel challan."),
                    backgroundColor: ok ? Colors.deepOrange : Colors.orange,
                  ),
                );
              }
            },
            child: const Text("YES, CANCEL CHALLAN", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
