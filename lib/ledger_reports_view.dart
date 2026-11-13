import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'pharoah_manager.dart';
import 'models.dart';
import 'finance/party_ledger_statement_view.dart';
import 'logic/app_accounts_calculator.dart';

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
                final isCash = p.name.trim().toUpperCase() == "CASH" || p.group.trim().toLowerCase().contains("cash");
                final isBank = p.group.trim().toLowerCase().contains("bank");

                double balance = _calculateBalance(ph, p);
                bool isDr = balance >= 0; // Dr = Mangte hain (Green), Cr = Dene hain (Red)

                return Card(
                  elevation: 1,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => PartyLedgerStatementView(initialParty: p))),
                    leading: CircleAvatar(
                      backgroundColor: isCash ? Colors.teal.shade50 : (isBank ? Colors.indigo.shade50 : (isDr ? Colors.green.shade50 : Colors.red.shade50)),
                      child: Icon(isCash ? Icons.account_balance_wallet_rounded : (isBank ? Icons.account_balance_rounded : Icons.person), color: isCash ? Colors.teal.shade800 : (isBank ? Colors.indigo.shade800 : (isDr ? Colors.green : Colors.red))),
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
                        Text(isCash ? "IN HAND" : (isBank ? "BANK BAL" : (isDr ? "RECEIVABLE" : "PAYABLE")), style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: isDr ? Colors.green : Colors.red)),
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

  // --- BALANCE CALCULATION LOGIC (DOUBLE-ENTRY CASH VS CREDIT DECOUPLED #PH-REV-744) ---
  double _calculateBalance(PharoahManager ph, Party p) {
    return ph.calculatePartyBalance(p);
  }
}

// --- SCREEN 2: SINGLE PARTY DETAILED LEDGER ---
class SingleLedgerDetailView extends StatelessWidget {
  final Party party;
  const SingleLedgerDetailView({super.key, required this.party});

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final rawStmt = AppAccountsCalculator.getPartyStatementData(
      party: party,
      fromDate: DateTime(2000, 1, 1),
      toDate: DateTime(2100, 12, 31),
      sales: ph.sales,
      purchases: ph.purchases,
      saleReturns: ph.saleReturns,
      purchaseReturns: ph.purchaseReturns,
      vouchers: ph.vouchers,
    );

    final List<Map<String, dynamic>> history = rawStmt.map((item) => {
      'date': item['date'],
      'desc': item['particulars'] ?? item['type'] ?? '',
      'dr': (item['dr'] as num?)?.toDouble() ?? 0.0,
      'cr': (item['cr'] as num?)?.toDouble() ?? 0.0,
      'bal': (item['balance'] as num?)?.toDouble() ?? (item['bal'] as num?)?.toDouble() ?? 0.0,
    }).toList();

    final double running = ph.calculatePartyBalance(party);

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
