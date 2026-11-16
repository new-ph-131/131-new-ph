// FILE: lib/challans/purchase_challan_register.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../logic/pharoah_numbering_engine.dart';
import '../pharoah_date_controller.dart';
import '../app_date_logic.dart';
import 'purchase_challan_view.dart';
import '../pdf/pdf_router_service.dart';
import '../pdf/purchase_challan_report_pdf.dart';

class PurchaseChallanRegister extends StatefulWidget {
  const PurchaseChallanRegister({super.key});

  @override
  State<PurchaseChallanRegister> createState() => _PurchaseChallanRegisterState();
}

class _PurchaseChallanRegisterState extends State<PurchaseChallanRegister> {
  String searchQuery = "";
  String fyFilter = "ALL"; // ALL | CURRENT | CARRY
  String statusFilter = "ACTIVE"; // ACTIVE | CANCELLED
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  bool _isInit = false;
  String _boundFy = "";

  bool _isCarryForward(PurchaseChallan ch, String currentFy) {
    final ofy = ch.effectiveOriginalFy;
    final curr = normalizeFyString(currentFy);
    return ofy.isEmpty || (curr.isNotEmpty && ofy != curr);
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

    final list = ph.purchaseChallans.where((ch) {
      if (ch.isDeleted == 1) return false;
      final bool isCancelled = ch.status == "Cancelled";
      if (statusFilter == "ACTIVE" && isCancelled) return false;
      if (statusFilter == "CANCELLED" && !isCancelled) return false;
      bool matchesSearch = ch.distributorName.toLowerCase().contains(searchQuery.toLowerCase()) ||
                           ch.billNo.toLowerCase().contains(searchQuery.toLowerCase()) ||
                           ch.internalNo.toLowerCase().contains(searchQuery.toLowerCase());
      final cOnly = dOnly(ch.date);
      bool matchesDate = (!cOnly.isBefore(fOnly) && !cOnly.isAfter(tOnly)) || ch.status == "Pending" || statusFilter == "CANCELLED";
      bool isCarry = _isCarryForward(ch, ph.currentFY);
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
      backgroundColor: const Color(0xFFFDF8F1),
      appBar: AppBar(
        title: const Text("Purchase Challan Register"),
        backgroundColor: Colors.amber.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined), 
            tooltip: "Export Register PDF",
            onPressed: () async {
              if (ph.activeCompany != null && list.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Generating Inward Report...")));
                await PurchaseChallanReportPdf.generate(list, fromDate, toDate, ph.activeCompany!);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No data found to export!")));
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
              ? const Center(child: Text("No Purchase Challans found."))
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
      decoration: BoxDecoration(
        color: Colors.amber.shade900,
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
      ),
      child: Column(
        children: [
          TextField(
            style: const TextStyle(color: Colors.white),
            onChanged: (v) => setState(() => searchQuery = v),
            decoration: InputDecoration(
              hintText: "Search Supplier or Bill No...",
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
              _statusTabChip("ACTIVE CHALLANS", "ACTIVE"),
              const SizedBox(width: 8),
              _statusTabChip("CANCELLED / AUDIT", "CANCELLED"),
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
              color: selected ? Colors.amber.shade900 : Colors.white70,
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
              color: selected ? (key == "CANCELLED" ? Colors.red.shade900 : Colors.amber.shade900) : Colors.white70,
              fontSize: 9.5,
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
              const Icon(Icons.calendar_month, size: 12, color: Colors.white70),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChallanCard(PurchaseChallan ch, PharoahManager ph) {
    bool isCancelled = ch.status == "Cancelled";
    bool isWeb = PharoahNumberingEngine.isWebChallanRecord(ch);
    bool isCarry = _isCarryForward(ch, ph.currentFY);
    final fwd = ph.getForwardChallanStatus(ch.id, isPurchase: true);
    final String cfLabel = (!ch.hasValidDate && ch.effectiveOriginalFy.isEmpty)
        ? "CF / LEGACY"
        : (ch.effectiveOriginalFy.isNotEmpty ? "CF • ${ch.effectiveOriginalFy}" : "CF / LEGACY");

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: () => _showActionMenu(ch, ph),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.inventory_2_rounded, color: Colors.amber.shade900),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ch.distributorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text("Ref: ${ch.billNo} • ID: ${ch.internalNo}", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: isWeb ? Colors.amber.shade50 : Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: isWeb ? Colors.amber.shade400 : Colors.indigo.shade300, width: 0.5),
                          ),
                          child: Text(
                            isWeb ? "WEB PORTAL" : "APP",
                            style: TextStyle(color: isWeb ? Colors.amber.shade900 : Colors.indigo.shade900, fontSize: 7.5, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                    Text(DateFormat('dd MMM yyyy').format(ch.date), style: TextStyle(color: Colors.amber.shade900, fontSize: 10, fontWeight: FontWeight.bold)),
                    if (isCarry || fwd.billedFy != null || fwd.shiftedFy != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (isCarry) _fyOriginBadge(cfLabel, Colors.deepPurple),
                            if (fwd.billedFy != null)
                              _fyOriginBadge("BILLED IN ${fwd.billedFy}", Colors.teal)
                            else if (fwd.shiftedFy != null)
                              _fyOriginBadge("SHIFTED → ${fwd.shiftedFy}", Colors.indigo),
                          ],
                        ),
                      ),
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
                        color: ph.config.isAuditMode ? Colors.indigo.shade900 : Colors.amber.shade900, 
                        size: 22
                      ),
                      tooltip: ph.config.isAuditMode ? "Forward to CA (Auditor)" : "Mail to Supplier",
                      onPressed: () {
                        final partyObj = ph.parties.firstWhere(
                          (p) => p.name == ch.distributorName, 
                          orElse: () => Party(id: 'temp', name: ch.distributorName)
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
                      Text("₹${ch.totalAmount.toStringAsFixed(0)}", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.amber.shade900)),
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isCancelled ? Colors.red.shade50 : (ch.status == "Pending" ? Colors.orange.shade50 : Colors.green.shade50),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          ch.status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: isCancelled ? Colors.red.shade900 : (ch.status == "Pending" ? Colors.orange.shade900 : Colors.green.shade900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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

  void _showActionMenu(PurchaseChallan ch, PharoahManager ph) {
    final fwd = ph.getForwardChallanStatus(ch.id, isPurchase: true);
    final bool isCancelled = ch.status == "Cancelled";
    final bool isBilledLocked = ch.status == "Billed" || fwd.billedFy != null;
    final bool isLocked = isBilledLocked || isCancelled;
    final bool canDelete = !isBilledLocked && ph.canDeletePurchaseChallan(ch.id);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (c) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 5, width: 40, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            Text(ch.distributorName, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text("Challan: ${ch.billNo} (${ch.internalNo})", style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const Divider(height: 30),

            _menuTile(Icons.visibility_outlined, "View Inward Details", Colors.blue, () {
              Navigator.pop(c);
              Navigator.push(context, MaterialPageRoute(builder: (c) => PurchaseChallanView(existingRecord: ch, isReadOnly: true)));
            }),

            _menuTile(
              isLocked ? Icons.lock_outline : Icons.edit_note_rounded,
              isCancelled ? "Modify Locked (Cancelled)" : (isBilledLocked ? "Modify Locked (Billed)" : "Modify / Edit Items"),
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
                Navigator.push(context, MaterialPageRoute(builder: (c) => PurchaseChallanView(existingRecord: ch)));
              },
            ),

            _menuTile(
              isCancelled ? Icons.lock_outline : Icons.print_rounded,
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
                if(ph.activeCompany != null) {
                  final party = ph.parties.firstWhere((p) => p.name == ch.distributorName, orElse: () => Party(id: '0', name: ch.distributorName));
                  await PdfRouterService.printChallan(
                    challan: ch, 
                    party: party, 
                    ph: ph, 
                    isSaleChallan: false
                  );
                }
              },
            ),

            _menuTile(
              isBilledLocked
                  ? Icons.lock_outline
                  : (canDelete
                      ? Icons.delete_forever_rounded
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
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _menuTile(IconData icon, String t, Color c, VoidCallback onTap) => 
      ListTile(leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: c.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: c, size: 20)), title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), onTap: onTap);

  void _confirmDelete(PurchaseChallan ch, PharoahManager ph) {
    final fwd = ph.getForwardChallanStatus(ch.id, isPurchase: true);
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
        title: const Text("Delete Record?"),
        content: Text(
          ch.status == "Cancelled"
              ? "Are you sure? This will permanently delete cancelled inward challan ${ch.internalNo} and reclaim the number."
              : "This will reverse stock and remove the entry permanently.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final bool ok = await ph.deletePurchaseChallanAsync(ch.id);
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

  void _confirmCancel(PurchaseChallan ch, PharoahManager ph) {
    final fwd = ph.getForwardChallanStatus(ch.id, isPurchase: true);
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
        title: const Text("Cancel Purchase Challan?"),
        content: Text("Inward ${ch.internalNo} (Ref: ${ch.billNo}) will be marked Cancelled. You may re-enter the supplier ref with a new challan if needed."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("NO")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
            onPressed: () async {
              final bool ok = await ph.cancelPurchaseChallan(ch.id);
              if (c.mounted) Navigator.pop(c);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? "🚫 Purchase Challan ${ch.internalNo} Cancelled (audit preserved)." : "🔒 Could not cancel challan."),
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
