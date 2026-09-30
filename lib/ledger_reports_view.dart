import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'pharoah_manager.dart';
import 'models.dart';

class LedgerReportsView extends StatefulWidget {
  const LedgerReportsView({super.key});
  @override State<LedgerReportsView> createState() => _LedgerReportsViewState();
}

class _LedgerReportsViewState extends State<LedgerReportsView> {
  String searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    
    // Sirf wahi parties dikhayenge jinme search match ho rahi hai
    final filteredParties = ph.parties.where((p) => 
      p.name.toLowerCase().contains(searchQuery.toLowerCase())
    ).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: const Text("Khaata / Ledger Reports"),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // --- SEARCH BAR ---
          Container(
            padding: const EdgeInsets.all(15),
            color: Colors.indigo.shade50,
            child: TextField(
              decoration: InputDecoration(
                hintText: "Search Party/Customer Name...",
                prefixIcon: const Icon(Icons.search, color: Colors.indigo),
                filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: EdgeInsets.zero
              ),
              onChanged: (v) => setState(() => searchQuery = v),
            ),
          ),

          // --- PARTY LIST WITH BALANCES ---
          Expanded(
            child: ListView.builder(
              itemCount: filteredParties.length,
              padding: const EdgeInsets.all(10),
              itemBuilder: (context, index) {
                final p = filteredParties[index];
                if (p.name == "CASH") return const SizedBox.shrink(); // Cash ka ledger alag hota hai

                double balance = _calculateBalance(ph, p);
                bool isDr = balance >= 0; // Dr = Mangte hain (Green), Cr = Dene hain (Red)

                return Card(
                  elevation: 1,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => SingleLedgerDetailView(party: p))),
                    leading: CircleAvatar(
                      backgroundColor: isDr ? Colors.green.shade50 : Colors.red.shade50,
                      child: Icon(Icons.person, color: isDr ? Colors.green : Colors.red),
                    ),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(p.city.isEmpty ? p.group : "${p.group} | ${p.city}"),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          "₹${balance.abs().toStringAsFixed(2)}",
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: isDr ? Colors.green.shade700 : Colors.red.shade700),
                        ),
                        Text(isDr ? "RECEIVABLE" : "PAYABLE", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: isDr ? Colors.green : Colors.red)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- BALANCE CALCULATION LOGIC ---
  double _calculateBalance(PharoahManager ph, Party p) {
    double total = p.opBal; // Starting with Opening Balance

    // 1. Sales Add (Debit)
    for (var s in ph.sales.where((s) => s.partyName == p.name && s.status == "Active")) {
      total += s.totalAmount;
    }
    // 2. Purchases Subtract (Credit)
    for (var pur in ph.purchases.where((pur) => pur.distributorName == p.name)) {
      total -= pur.totalAmount;
    }
    // 3. Vouchers (Receipt/Payment)
    // lib/ledger_reports_view.dart mein calculation line update karein:

    // 3. Vouchers (Receipt/Payment)
    for (var v in ph.vouchers.where((v) => v.partyName == p.name && v.status == "Active")) { // 👈 ADDED: && v.status == "Active"
      if (v.type == "Receipt") total -= v.amount;
      if (v.type == "Payment") total += v.amount;
    }
    return total;
  }
}

// --- SCREEN 2: SINGLE PARTY DETAILED LEDGER ---
class SingleLedgerDetailView extends StatelessWidget {
  final Party party;
  const SingleLedgerDetailView({super.key, required this.party});

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    List<Map<String, dynamic>> history = [];

    // Data collect karna (Same logic as Daybook but for 1 party)
    history.add({'date': DateTime(2024), 'desc': "Opening Balance", 'dr': party.opBal > 0 ? party.opBal : 0.0, 'cr': party.opBal < 0 ? party.opBal.abs() : 0.0});
    
    for (var s in ph.sales.where((s) => s.partyName == party.name && s.status == "Active")) {
      history.add({'date': s.date, 'desc': "Sale Bill #${s.billNo}", 'dr': s.totalAmount, 'cr': 0.0});
    }
    for (var pur in ph.purchases.where((pur) => pur.distributorName == party.name)) {
      history.add({'date': pur.date, 'desc': "Pur Bill #${pur.billNo}", 'dr': 0.0, 'cr': pur.totalAmount});
    }
    for (var v in ph.vouchers.where((v) => v.partyName == party.name)) {
      history.add({'date': v.date, 'desc': "${v.type} (${v.paymentMode})", 'dr': v.type == "Payment" ? v.amount : 0.0, 'cr': v.type == "Receipt" ? v.amount : 0.0});
    }

    history.sort((a, b) => a['date'].compareTo(b['date']));

    // Running Balance Calculation
    double running = 0;
    for (var item in history) {
      running += (item['dr'] - item['cr']);
      item['bal'] = running;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(party.name),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: () => _shareReminder(party, running),
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.indigo.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("NET BALANCE:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                Text(
                  "₹${running.abs().toStringAsFixed(2)} ${running >= 0 ? 'Dr' : 'Cr'}",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: running >= 0 ? Colors.green.shade700 : Colors.red.shade700),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: history.length,
              itemBuilder: (c, i) {
                final item = history[i];
                return Container(
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                  child: ListTile(
                    dense: true,
                    title: Row(
                      children: [
                        Text(DateFormat('dd/MM/yy').format(item['date']), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(item['desc'], style: const TextStyle(fontWeight: FontWeight.w500))),
                      ],
                    ),
                    subtitle: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("In: ₹${item['dr']}", style: const TextStyle(color: Colors.green, fontSize: 11)),
                        Text("Out: ₹${item['cr']}", style: const TextStyle(color: Colors.red, fontSize: 11)),
                        Text("Bal: ₹${item['bal'].abs().toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                      ],
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  void _shareReminder(Party p, double bal) {
    String msg = "प्रिय ${p.name},\n\nआपका Pharoah ERP में कुल बकाया राशि ₹${bal.abs().toStringAsFixed(2)} ${bal > 0 ? 'Debit (देय)' : 'Credit'} है। कृपया जल्द से जल्द भुगतान करने का कष्ट करें।\n\nधन्यवाद!";
    Share.share(msg);
  }
}
