import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'pharoah_manager.dart';
import 'models.dart';
import 'pharoah_date_controller.dart';
import 'app_date_logic.dart';
import 'logic/pharoah_numbering_engine.dart';
import 'pdf/pdf_router_service.dart';

class VoucherEntryView extends StatefulWidget {
  final String type; // Receipt or Payment
  final Voucher? existingVoucher; 
  final bool isReadOnly; 

  const VoucherEntryView({
    super.key, 
    required this.type, 
    this.existingVoucher,
    this.isReadOnly = false, 
  });

  @override State<VoucherEntryView> createState() => _VoucherEntryViewState();
}

class _VoucherEntryViewState extends State<VoucherEntryView> {
  final amountC = TextEditingController();
  final narrationC = TextEditingController();
  final chequeNoC = TextEditingController();
  final partyBankC = TextEditingController();
  final partySearchC = TextEditingController();

  DateTime selectedEntryDate = DateTime.now(); 
  DateTime selectedChequeDate = DateTime.now(); 
  Party? selectedParty;
  Party? selectedInternalAccount; 
  String payMode = "Cash";
  Map<String, String> billPaymentModes = {};
  Map<String, String> billDepositBanks = {};
  Map<String, DateTime> billChequeDates = {};
  final Map<String, TextEditingController> billChequeControllers = {};
  String voucherNo = "Loading...";
  bool isUpdateMode = false;

  List<Map<String, dynamic>> pendingBills = [];
  List<String> selectedBillNumbers = [];
  Map<String, double> billAllocations = {};
  double runningTotal = 0.0;
  String partyQuery = "";

  @override
  void initState() {
    super.initState();
    _initVoucherSession();
  }

  void _initVoucherSession() async {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    
    if (widget.existingVoucher != null) {
      isUpdateMode = true;
      final v = widget.existingVoucher!;
      voucherNo = v.voucherNo;
      amountC.text = v.amount.toString();
      narrationC.text = v.narration.replaceAll("[CANCELLED] ", "");
      payMode = v.paymentMode;
      selectedEntryDate = v.date;
      selectedChequeDate = v.chequeDate ?? v.date;
      chequeNoC.text = v.chequeNo;
      partyBankC.text = v.bankName;
      selectedBillNumbers = List.from(v.linkedBillNumbers);
      billAllocations = Map.from(v.billAllocations);
      if (billAllocations.isEmpty && selectedBillNumbers.isNotEmpty) {
        for (var bNo in selectedBillNumbers) {
          billAllocations[bNo] = v.getAllocatedAmount(bNo);
        }
      }
      runningTotal = v.amount;

      try {
        selectedParty = ph.parties.firstWhere((p) => p.id == v.partyId);
        selectedInternalAccount = ph.parties.firstWhere((p) => p.name == v.depositedIn);
        pendingBills = ph.getPendingBills(selectedParty!.id, widget.type.toUpperCase() == "RECEIPT", excludeVoucherId: v.id);
      } catch (e) { debugPrint("Sync Error: $e"); }

    } else {
      selectedEntryDate = PharoahDateController.getInitialBillDate(ph.currentFY);
      selectedChequeDate = selectedEntryDate;
      
      String typeKey = widget.type.toUpperCase(); 
      var series = ph.getDefaultSeries(typeKey);

      // Filter list to get correct next number
      List<Voucher> filteredList = ph.vouchers.where((v) => v.type.toUpperCase() == typeKey).toList();

      voucherNo = await PharoahNumberingEngine.getNextNumber(
        type: typeKey, 
        companyID: ph.activeCompany!.id,
        prefix: series.prefix, 
        startFrom: series.startNumber, 
        currentList: filteredList,
      );
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    Color themeColor = widget.type.toUpperCase() == "RECEIPT" ? Colors.green.shade800 : Colors.red.shade800;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: Text("${widget.isReadOnly ? 'VIEW' : (isUpdateMode ? 'MODIFY' : 'NEW')} ${widget.type.toUpperCase()}"),
        backgroundColor: widget.isReadOnly ? Colors.blueGrey : themeColor,
      ),
      body: IgnorePointer(
        ignoring: widget.isReadOnly,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, 
            children: [
              // 1. Header with Voucher No and Date
              Row(
                children: [
                  Expanded(
                    child: _infoTile("VOUCHER NO", voucherNo, Icons.tag_rounded, color: themeColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _dateTile("ENTRY DATE", selectedEntryDate, (d) => setState(() => selectedEntryDate = d), ph.currentFY, themeColor),
                  ),
                ],
              ),
              const SizedBox(height: 25),

              _sectionLabel("2. ACCOUNT / PARTY DETAILS"),
              const SizedBox(height: 10),
              if (selectedParty == null)
                TextField(
                  controller: partySearchC,
                  decoration: const InputDecoration(hintText: "Search Party Name...", prefixIcon: Icon(Icons.person_search), border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
                  onChanged: (v) => setState(() => partyQuery = v),
                )
              else
                _selectedItemCard(selectedParty!.name, "City: ${selectedParty!.city}", themeColor, () => setState(() { selectedParty = null; selectedBillNumbers.clear(); })),

              if (selectedParty == null && partyQuery.isNotEmpty)
                _buildSearchDropdown(ph),

              const SizedBox(height: 25),

              if (selectedParty != null) ...[
                _sectionLabel("3. PAYMENT MODE & INTERNAL LEDGER"),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'Cash', label: Text('Cash'), icon: Icon(Icons.money)),
                    ButtonSegment(value: 'Bank', label: Text('Bank')),
                  ],
                  selected: {payMode},
                  onSelectionChanged: (v) => setState(() => payMode = v.first),
                ),
                const SizedBox(height: 15),
                DropdownButtonFormField<Party>(
                  value: selectedInternalAccount,
                  decoration: const InputDecoration(labelText: "Our Internal Account", border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
                  items: ph.getInternalAccounts()
                    .where((p) => payMode == "Cash" ? p.group == "Cash in Hand" : p.group == "Bank Accounts")
                    .map((p) => DropdownMenuItem(value: p, child: Text(p.name))).toList(),
                  onChanged: (v) => setState(() => selectedInternalAccount = v),
                ),

                if (payMode == "Bank") ...[
                  const SizedBox(height: 20),
                  _sectionLabel("4. CHEQUE / INSTRUMENT DETAILS"),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _input(chequeNoC, "Cheque No.", Icons.numbers)),
                    const SizedBox(width: 10),
                    Expanded(child: _dateTile("CHEQUE DATE", selectedChequeDate, (d) => setState(() => selectedChequeDate = d), ph.currentFY, Colors.blueGrey)),
                  ]),
                ],

                const SizedBox(height: 25),
                _sectionLabel("5. BILL ADJUSTMENT"),
                const SizedBox(height: 10),
                _buildAdjustmentTrigger(themeColor, ph),

                const SizedBox(height: 30),
                _sectionLabel("6. FINAL AMOUNT & NARRATION"),
                const SizedBox(height: 10),
                TextField(
                  controller: amountC, keyboardType: TextInputType.number, 
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  decoration: const InputDecoration(labelText: "VOUCHER AMOUNT ₹", border: OutlineInputBorder(), prefixIcon: Icon(Icons.currency_rupee)),
                ),
                const SizedBox(height: 15),
                TextField(controller: narrationC, decoration: const InputDecoration(labelText: "Narration / Note", border: OutlineInputBorder(), prefixIcon: Icon(Icons.notes))),
                
                const SizedBox(height: 40),
                if (!widget.isReadOnly) 
                  SizedBox(
                    width: double.infinity, height: 60,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: themeColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                      onPressed: () => _handleFinalSave(ph),
                      child: Text(isUpdateMode ? "UPDATE TRANSACTION" : "FINALIZE & SAVE", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
              ]
            ],
          ),
        ),
      ),
    );
  }

  // --- HELPER WIDGETS ---

  Widget _infoTile(String l, String v, IconData i, {VoidCallback? onTap, Color? color}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l, style: const TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(children: [
                Icon(i, size: 14, color: color ?? Colors.blueGrey),
                const SizedBox(width: 5),
                Text(v, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String t) => Text(t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1));
  Widget _input(TextEditingController c, String l, IconData i) => TextField(controller: c, decoration: InputDecoration(labelText: l, prefixIcon: Icon(i, size: 20), border: const OutlineInputBorder(), filled: true, fillColor: Colors.white));
  
  Widget _dateTile(String l, DateTime d, Function(DateTime) onPick, String fy, Color col) => InkWell(
    onTap: () async {
      DateTime? p = await PharoahDateController.pickDate(context: context, currentFY: fy, initialDate: d);
      if (p != null) onPick(p);
    },
    child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border.all(color: col.withOpacity(0.4)), borderRadius: BorderRadius.circular(8), color: Colors.white), 
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, style: const TextStyle(fontSize: 8, color: Colors.grey)),
          Text(DateFormat('dd-MM-yyyy').format(d), style: TextStyle(fontWeight: FontWeight.bold, color: col)),
        ]),
        Icon(Icons.calendar_month, color: col, size: 20),
      ])),
  );

  Widget _buildAdjustmentTrigger(Color col, PharoahManager ph) => InkWell(
    onTap: () => _openReferenceWizard(ph),
    child: Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: col.withOpacity(0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: col.withOpacity(0.3))),
      child: Row(children: [Icon(Icons.auto_fix_high, color: col), const SizedBox(width: 15), Text(selectedBillNumbers.isEmpty ? "Tap to select pending bills" : "${selectedBillNumbers.length} Bills Adjusted", style: TextStyle(fontWeight: FontWeight.bold, color: col)), const Spacer(), const Icon(Icons.chevron_right)]),
    ),
  );

  Widget _selectedItemCard(String t, String s, Color c, VoidCallback onClear) => ListTile(tileColor: c.withOpacity(0.05), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: c)), title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(s), trailing: widget.isReadOnly ? null : IconButton(icon: const Icon(Icons.cancel, color: Colors.red), onPressed: onClear));
  
  Widget _buildSearchDropdown(PharoahManager ph) => Container(height: 180, decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]), child: ListView(children: ph.parties.where((p) => p.name.toLowerCase().contains(partyQuery.toLowerCase())).map((p) => ListTile(title: Text(p.name), onTap: () => setState(() => selectedParty = p))).toList()));

  // --- LOGIC METHODS ---

  void _openReferenceWizard(PharoahManager ph) {
    if (selectedParty == null || widget.isReadOnly) return;
    pendingBills = ph.getPendingBills(
      selectedParty!.id,
      widget.type.toUpperCase() == "RECEIPT",
      excludeVoucherId: widget.existingVoucher?.id,
    );

    // Map of text controllers for each bill
    final Map<String, TextEditingController> wizardControllers = {};
    for (var b in pendingBills) {
      String bNo = b['billNo'].toString();
      double due = (b['amount'] as num).toDouble();
      double curAlloc = billAllocations[bNo] ?? (selectedBillNumbers.contains(bNo) ? due : due);
      wizardControllers[bNo] = TextEditingController(text: curAlloc.toStringAsFixed(2));
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (c) => StatefulBuilder(builder: (context, setWizardState) {
        void recalculateRunning() {
          double total = 0.0;
          for (var bNo in selectedBillNumbers) {
            total += (billAllocations[bNo] ?? 0.0);
          }
          runningTotal = total;
        }

        void autoFifo() {
          double target = double.tryParse(amountC.text) ?? 0.0;
          if (target <= 0) {
            target = pendingBills.fold(0.0, (s, b) => s + (b['amount'] as num).toDouble());
          }
          double remaining = target;
          selectedBillNumbers.clear();
          billAllocations.clear();
          for (var b in pendingBills) {
            String bNo = b['billNo'].toString();
            double due = (b['amount'] as num).toDouble();
            if (remaining <= 0) {
              wizardControllers[bNo]?.text = "0.00";
              continue;
            }
            double alloc = remaining >= due ? due : remaining;
            alloc = double.parse(alloc.toStringAsFixed(2));
            selectedBillNumbers.add(bNo);
            billAllocations[bNo] = alloc;
            wizardControllers[bNo]?.text = alloc.toStringAsFixed(2);
            remaining -= alloc;
          }
          recalculateRunning();
          setWizardState(() {});
        }

        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("BILL SETTLEMENT: ${selectedParty!.name}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text("Marg ERP Agst Ref Partial Allocation", style: TextStyle(color: Colors.grey.shade600, fontSize: 10)),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(c)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.auto_awesome, size: 14),
                    label: const Text("AUTO (FIFO)", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    onPressed: autoFifo,
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      setWizardState(() {
                        selectedBillNumbers.clear();
                        billAllocations.clear();
                        for (var b in pendingBills) {
                          String bNo = b['billNo'].toString();
                          double due = (b['amount'] as num).toDouble();
                          selectedBillNumbers.add(bNo);
                          billAllocations[bNo] = due;
                          wizardControllers[bNo]?.text = due.toStringAsFixed(2);
                        }
                        recalculateRunning();
                      });
                    },
                    child: const Text("SELECT ALL", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setWizardState(() {
                        selectedBillNumbers.clear();
                        billAllocations.clear();
                        recalculateRunning();
                      });
                    },
                    child: const Text("CLEAR", style: TextStyle(fontSize: 10, color: Colors.red)),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: pendingBills.length,
                  itemBuilder: (context, i) {
                    final b = pendingBills[i];
                    String bNo = b['billNo'].toString();
                    double due = (b['amount'] as num).toDouble();
                    double totalAmt = ((b['totalAmount'] ?? due) as num).toDouble();
                    double paidAmt = ((b['paidAmount'] ?? 0.0) as num).toDouble();
                    bool isSel = selectedBillNumbers.contains(bNo);
                    TextEditingController ctrl = wizardControllers[bNo]!;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      elevation: 0.5,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: isSel ? Colors.indigo.shade300 : Colors.grey.shade200, width: isSel ? 1.5 : 1),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Checkbox(
                                  value: isSel,
                                  activeColor: Colors.indigo,
                                  onChanged: (v) {
                                    setWizardState(() {
                                      if (v == true) {
                                        selectedBillNumbers.add(bNo);
                                        billAllocations[bNo] = due;
                                        ctrl.text = due.toStringAsFixed(2);
                                      } else {
                                        selectedBillNumbers.remove(bNo);
                                        billAllocations.remove(bNo);
                                      }
                                      recalculateRunning();
                                    });
                                  },
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(bNo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(4)),
                                            child: Text("${b['dueDays']}d due", style: TextStyle(color: Colors.orange.shade800, fontSize: 9, fontWeight: FontWeight.bold)),
                                          ),
                                          if (paidAmt > 0.01) ...[
                                            const SizedBox(width: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                                              child: Text("PARTIAL", style: TextStyle(color: Colors.blue.shade800, fontSize: 8, fontWeight: FontWeight.bold)),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "Date: ${DateFormat('dd/MM/yy').format(b['date'])} | Bill: ₹${totalAmt.toStringAsFixed(2)} | Paid: ₹${paidAmt.toStringAsFixed(2)}",
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ),
                                Text("Due: ₹${due.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.green)),
                              ],
                            ),
                            if (isSel) ...[
                              const Divider(height: 12),
                              Row(
                                children: [
                                  const SizedBox(width: 48),
                                  const Text("Adjust ₹: ", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 6),
                                  SizedBox(
                                    width: 100,
                                    height: 32,
                                    child: TextField(
                                      controller: ctrl,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                      ),
                                      onChanged: (val) {
                                        double p = double.tryParse(val) ?? 0.0;
                                        if (p > due) {
                                          p = due;
                                          ctrl.text = due.toStringAsFixed(2);
                                        }
                                        setWizardState(() {
                                          if (p > 0) {
                                            if (!selectedBillNumbers.contains(bNo)) selectedBillNumbers.add(bNo);
                                            billAllocations[bNo] = p;
                                          } else {
                                            selectedBillNumbers.remove(bNo);
                                            billAllocations.remove(bNo);
                                          }
                                          recalculateRunning();
                                        });
                                      },
                                    ),
                                  ),
                                  const Spacer(),
                                  Text("Allocated: ₹${(billAllocations[bNo] ?? 0.0).toStringAsFixed(2)}", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("${selectedBillNumbers.length} Bills Selected", style: TextStyle(color: Colors.indigo.shade900, fontWeight: FontWeight.bold, fontSize: 12)),
                    Text("Total: ₹${runningTotal.toStringAsFixed(2)}", style: TextStyle(color: Colors.indigo.shade900, fontWeight: FontWeight.w900, fontSize: 15)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.indigo),
                onPressed: () {
                  setState(() => amountC.text = runningTotal.toStringAsFixed(2));
                  Navigator.pop(c);
                },
                child: const Text("APPLY SELECTION", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        );
      }),
    );
  }

  void _handleFinalSave(PharoahManager ph) async {
    double amt = double.tryParse(amountC.text) ?? 0;
    if (selectedParty == null || amt <= 0 || selectedInternalAccount == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All fields are mandatory!")));
      return;
    }

    int newVersion = 1;
    if (isUpdateMode && widget.existingVoucher != null) {
      newVersion = widget.existingVoucher!.version + 1;
    }

    Map<String, double> finalAllocations = {};
    if (selectedBillNumbers.isNotEmpty) {
      for (var b in selectedBillNumbers) {
        finalAllocations[b] = billAllocations[b] ?? 0.0;
      }
    }

    List<Map<String, dynamic>> finalChequeInstruments = [];
    for (var bNo in selectedBillNumbers) {
      String mode = billPaymentModes[bNo] ?? payMode;
      if (mode.toLowerCase() == "bank") {
        String bBank = billDepositBanks[bNo] ?? selectedInternalAccount?.name ?? '';
        String bChqNo = billChequeControllers[bNo]?.text.trim() ?? chequeNoC.text.trim();
        DateTime bChqDate = billChequeDates[bNo] ?? selectedChequeDate;
        finalChequeInstruments.add({
          'billNo': bNo,
          'amount': billAllocations[bNo] ?? 0.0,
          'paymentMode': mode,
          'bankName': bBank,
          'depositedIn': bBank,
          'chequeNo': bChqNo,
          'chequeDate': bChqDate.toIso8601String(),
        });
      }
    }

    final v = Voucher(
      id: isUpdateMode ? widget.existingVoucher!.id : DateTime.now().millisecondsSinceEpoch.toString(),
      type: widget.type.toUpperCase(),
      voucherNo: voucherNo,
      date: selectedEntryDate,
      partyId: selectedParty!.id,
      partyName: selectedParty!.name,
      amount: amt,
      paymentMode: payMode,
      bankName: payMode == "Bank" ? selectedInternalAccount!.name : "",
      depositedIn: selectedInternalAccount!.name,
      chequeNo: chequeNoC.text,
      chequeDate: payMode == "Bank" ? selectedChequeDate : null,
      narration: narrationC.text,
      status: "Active",
      linkedBillNumbers: selectedBillNumbers,
      billAllocations: finalAllocations,
      chequeInstruments: finalChequeInstruments,
      version: newVersion,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      isDeleted: 0,
    );

    await ph.finalizeVoucher(v);
    _showSuccessHub(ph, v.id);
  }

  void _showSuccessHub(PharoahManager ph, String vId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 10), Text("Entry Recorded!")]),
        content: const Text("Would you like to print the 1/4 A4 voucher now?"),
        actions: [
          TextButton(onPressed: () => Navigator.popUntil(context, (route) => route.isFirst), child: const Text("LATER / GO HOME")),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () async {
              final vObj = ph.vouchers.firstWhere((v) => v.id == vId);
              final pObj = ph.parties.firstWhere((p) => p.id == vObj.partyId, orElse: () => Party(id:'0', name: vObj.partyName));
              await PdfRouterService.printVoucher(voucher: vObj, party: pObj, ph: ph);
            }, 
            icon: const Icon(Icons.print, color: Colors.white), 
            label: const Text("PRINT VOUCHER", style: TextStyle(color: Colors.white))
          )
        ],
      ),
    );
  }
}
