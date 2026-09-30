// FILE: lib/administration/bank_master_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../pharoah_manager.dart';
import '../../models.dart';

class BankMasterView extends StatefulWidget {
  const BankMasterView({super.key});

  @override
  State<BankMasterView> createState() => _BankMasterViewState();
}

class _BankMasterViewState extends State<BankMasterView> {
  String search = "";

  void _showBankForm({Bank? bank}) {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    
    final nameC = TextEditingController(text: bank?.name);
    final branchC = TextEditingController(text: bank?.branch);
    final accC = TextEditingController(text: bank?.accountNo);
    // Note: Opening balance handles through a separate ledger logic usually, 
    // but for simplicity, we can store it in metadata or extend the model later.

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(bank == null ? "Add New Bank Account" : "Edit Bank Details"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _input(nameC, "Bank Name (e.g. ICICI Bank)", Icons.account_balance),
              _input(branchC, "Branch Name", Icons.location_on),
              _input(accC, "Account Number", Icons.numbers),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
            onPressed: () {
              if (nameC.text.isEmpty) return;
              
              final newBank = Bank(
                id: bank?.id ?? DateTime.now().toString(),
                name: nameC.text.toUpperCase(),
                branch: branchC.text.toUpperCase(),
                accountNo: accC.text,
              );

              if (bank == null) ph.addBank(newBank);
              else {
                int i = ph.banks.indexWhere((x) => x.id == bank.id);
                if (i != -1) ph.banks[i] = newBank;
                ph.save();
              }
              Navigator.pop(c);
            },
            child: const Text("SAVE BANK", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final list = ph.banks.where((b) => b.name.toLowerCase().contains(search.toLowerCase())).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: const Text("Bank Accounts (Our Banks)"),
        backgroundColor: Colors.indigo.shade800,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            color: Colors.indigo.shade50,
            child: TextField(
              decoration: const InputDecoration(
                hintText: "Search Bank Name...",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (v) => setState(() => search = v),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text("No bank accounts added yet."))
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: list.length,
                    itemBuilder: (c, i) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(backgroundColor: Colors.indigo, child: Icon(Icons.account_balance, color: Colors.white, size: 20)),
                        title: Text(list[i].name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("Branch: ${list[i].branch} | Acc: ${list[i].accountNo}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _showBankForm(bank: list[i])),
                            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _confirmDelete(ph, list[i])),
                          ],
                        ),
                      ),
                    ),
                  ),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showBankForm(),
        backgroundColor: Colors.indigo.shade800,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("ADD BANK ACCOUNT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _input(TextEditingController ctrl, String label, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: TextField(
      controller: ctrl,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 20), border: const OutlineInputBorder()),
    ),
  );

  void _confirmDelete(PharoahManager ph, Bank b) {
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text("Delete Bank?"),
      content: Text("Are you sure you want to remove '${b.name}'?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("NO")),
        ElevatedButton(onPressed: () { ph.deleteBank(b.id); Navigator.pop(c); }, child: const Text("YES, DELETE")),
      ],
    ));
  }
}
