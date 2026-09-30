// FILE: lib/party_master.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pharoah_manager.dart';
import 'models.dart';

class PartyMasterView extends StatefulWidget {
  final bool isSelectionMode; 
  final Map<String, dynamic>? preFillData; 

  const PartyMasterView({
    super.key, 
    this.isSelectionMode = false, 
    this.preFillData 
  });

  @override
  State<PartyMasterView> createState() => _PartyMasterViewState();
}

class _PartyMasterViewState extends State<PartyMasterView> {
  String searchQuery = "";

  // NAYA: Account Groups with Professional variants
  final List<String> accountGroups = [
    "Sundry Debtors", 
    "Sundry Creditors", 
    "Bank Accounts",
    "Cash in Hand",
    "Expenses"
  ];

  @override
  void initState() {
    super.initState();
    if (widget.isSelectionMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showPartyForm();
      });
    }
  }

  // --- SEARCHABLE STATE PICKER (ORIGINAL AS-IS) ---
  void _showStateSearchPicker(BuildContext context, PharoahManager ph, Function(String) onSelect) {
    showDialog(
      context: context,
      builder: (context) {
        String localSearch = "";
        return StatefulBuilder(builder: (context, setPickerState) {
          final sortedList = ph.getSortedStates();
          final filtered = sortedList.where((s) => s.toLowerCase().contains(localSearch.toLowerCase())).toList();
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text("Select State", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(hintText: "Search State...", prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
                    onChanged: (v) => setPickerState(() => localSearch = v),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 350,
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (c, i) {
                        String sName = filtered[i];
                        bool isFrequent = (ph.parties.where((p) => p.state == sName).length) > 0;
                        return ListTile(
                          title: Text(sName, style: TextStyle(fontWeight: isFrequent ? FontWeight.bold : FontWeight.normal)),
                          trailing: isFrequent ? const Icon(Icons.stars_rounded, color: Colors.orange, size: 18) : null,
                          onTap: () { onSelect(sName); Navigator.pop(context); },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  // ===========================================================================
  // 📝 UPDATED PARTY FORM (WITH BANK/CASH & ARCHITECT SERIES)
  // ===========================================================================
  void _showPartyForm({Party? party}) {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    final pf = widget.preFillData;

    final nameC = TextEditingController(text: party?.name ?? pf?['name']);
    final phoneC = TextEditingController(text: party?.phone ?? pf?['phone']);
    final emailC = TextEditingController(text: party?.email ?? pf?['email']); 
    final addressC = TextEditingController(text: party?.address ?? pf?['address']);
    final cityC = TextEditingController(text: party?.city ?? pf?['city']);
    final gstC = TextEditingController(text: party?.gst ?? pf?['gst']);
    final panC = TextEditingController(text: party?.pan ?? pf?['pan']);
    final dlC = TextEditingController(text: party?.dl ?? pf?['dl']);
    final dlExpC = TextEditingController(text: party?.dlExp);
    final opBalC = TextEditingController(text: party?.opBal.toString() ?? "0.0");

    String selectedGroup = party?.group ?? "Sundry Debtors";
    String selectedState = party?.state ?? pf?['state'] ?? "Rajasthan";
    String selectedSeriesId = party?.defaultSeriesId ?? "";

    // PAN Auto-extraction logic (Original)
    gstC.addListener(() {
      if (gstC.text.length >= 12) {
        String extPan = gstC.text.substring(2, 12).toUpperCase();
        if (panC.text != extPan) { panC.text = extPan; }
      }
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(builder: (context, setDialogState) {
        final List<NumberingSeries> activeSeries = ph.getSeriesByType("SALE").where((s) => s.isActive).toList();

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(party == null ? "Register New Account" : "Update Details"),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _sectionTitle("ACCOUNT CLASSIFICATION"),
                  DropdownButtonFormField<String>(
                    value: selectedGroup,
                    decoration: const InputDecoration(labelText: "Account Group *", border: OutlineInputBorder(), prefixIcon: Icon(Icons.category)),
                    items: accountGroups.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setDialogState(() => selectedGroup = v!),
                  ),
                  const SizedBox(height: 20),
                  
                  _sectionTitle("BASIC INFORMATION"),
                  _inputField(nameC, "Name (Firm or Bank Name) *", Icons.business),
                  
                  // Conditional Fields: Bank/Cash ke liye address optional, party ke liye mandatory
                  Row(children: [
                    Expanded(child: _inputField(cityC, "City", Icons.location_city)),
                    const SizedBox(width: 10),
                    Expanded(child: _searchableBox(
                      label: "State / Supply Place",
                      value: selectedState,
                      icon: Icons.map_outlined,
                      onTap: () => _showStateSearchPicker(context, ph, (val) => setDialogState(() => selectedState = val)),
                    )),
                  ]),
                  
                  _inputField(phoneC, "Mobile Number", Icons.phone, isNum: true),
                  _inputField(emailC, "Email Address", Icons.email),
                  _inputField(addressC, "Full Address", Icons.location_on),

                  const SizedBox(height: 20),
                  _sectionTitle("TAX & LICENSES"),
                  _inputField(gstC, "GSTIN Number", Icons.receipt_long),
                  _inputField(panC, "PAN Card", Icons.badge_outlined),
                  Row(children: [
                    Expanded(child: _inputField(dlC, "Drug License (DL)", Icons.medical_services)),
                    const SizedBox(width: 10),
                    Expanded(child: _inputField(dlExpC, "DL Expiry", Icons.event_busy)),
                  ]),

                  const SizedBox(height: 20),
                  _sectionTitle("DEFAULTS & BALANCES"),
                  DropdownButtonFormField<String>(
                    value: selectedSeriesId.isEmpty ? null : selectedSeriesId,
                    decoration: const InputDecoration(labelText: "Default Billing Series", border: OutlineInputBorder(), prefixIcon: Icon(Icons.layers_outlined)),
                    items: activeSeries.map((s) => DropdownMenuItem<String>(value: s.id, child: Text("${s.name} (${s.prefix})"))).toList(),
                    onChanged: (v) => selectedSeriesId = v!,
                    hint: const Text("Select Default Series"),
                  ),
                  const SizedBox(height: 12),
                  _inputField(opBalC, "Current Balance (₹)", Icons.account_balance_wallet, isNum: true),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              onPressed: () {
                if (nameC.text.trim().isEmpty) return;
                final newParty = Party(
                  id: party?.id ?? DateTime.now().toString(),
                  name: nameC.text.trim().toUpperCase(),
                  group: selectedGroup,
                  phone: phoneC.text.trim(),
                  email: emailC.text.trim().toLowerCase(),
                  address: addressC.text.trim(),
                  city: cityC.text.trim().toUpperCase(),
                  state: selectedState,
                  gst: gstC.text.trim().toUpperCase(),
                  pan: panC.text.trim().toUpperCase(),
                  dl: dlC.text.trim().toUpperCase(),
                  dlExp: dlExpC.text.trim(),
                  opBal: double.tryParse(opBalC.text) ?? 0.0,
                  defaultSeriesId: selectedSeriesId, 
                );
                if (party == null) ph.parties.add(newParty);
                else { int i = ph.parties.indexWhere((p) => p.id == party.id); if (i != -1) ph.parties[i] = newParty; }
                ph.save();
                Navigator.pop(c);
                if (widget.isSelectionMode) Navigator.pop(context, newParty);
              },
              child: const Text("SAVE TO MASTER"),
            ),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final list = ph.parties.where((p) => 
      p.name.toLowerCase().contains(searchQuery.toLowerCase()) || p.group.toLowerCase().contains(searchQuery.toLowerCase())
    ).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(title: const Text("Account & Party Master"), backgroundColor: Colors.indigo, foregroundColor: Colors.white),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15), color: Colors.indigo.shade50,
            child: TextField(
              decoration: InputDecoration(hintText: "Search by Name, Group or City...", prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), filled: true, fillColor: Colors.white),
              onChanged: (v) => setState(() => searchQuery = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              padding: const EdgeInsets.all(10),
              itemBuilder: (context, index) {
                final p = list[index];
                Color grpColor = _getGroupColor(p.group);
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: grpColor.withOpacity(0.1), child: Icon(_getGroupIcon(p.group), color: grpColor)),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("${p.group} | ${p.city}, ${p.state}"),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _showPartyForm(party: p)),
                      if (p.name != "CASH") IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _confirmDelete(ph, p)),
                    ]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _showPartyForm(), backgroundColor: Colors.indigo, label: const Text("ADD NEW ACCOUNT", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
    );
  }

  Color _getGroupColor(String g) {
    if (g == "Bank Accounts") return Colors.blue.shade700;
    if (g == "Cash in Hand") return Colors.green.shade700;
    if (g == "Sundry Creditors") return Colors.orange.shade900;
    return Colors.indigo;
  }

  IconData _getGroupIcon(String g) {
    if (g == "Bank Accounts") return Icons.account_balance;
    if (g == "Cash in Hand") return Icons.payments;
    return Icons.person;
  }

  Widget _sectionTitle(String t) => Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1))));
  
  Widget _inputField(TextEditingController ctrl, String l, IconData i, {bool isNum = false}) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: ctrl, keyboardType: isNum ? TextInputType.number : TextInputType.text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold), decoration: InputDecoration(labelText: l, prefixIcon: Icon(i, size: 18), border: const OutlineInputBorder(), contentPadding: const EdgeInsets.all(10))));

  Widget _searchableBox({required String label, required String value, required IconData icon, required VoidCallback onTap}) => InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(5)), child: Row(children: [Icon(icon, color: Colors.grey, size: 18), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 9)), Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)])), const Icon(Icons.arrow_drop_down)])));

  void _confirmDelete(PharoahManager ph, Party p) {
    if (p.name == "CASH") return;

    // 1. CHECK USAGE FIRST (NAYA LOGIC)
    bool inUse = ph.isPartyInUse(p.id, p.name);

    if (inUse) {
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text("Action Restricted", style: TextStyle(color: Colors.red)),
          content: Text("You cannot delete '${p.name}' because it has active transactions (Sales/Purchases/Vouchers) linked to it."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("I UNDERSTAND")),
          ],
        ),
      );
      return;
    }

    // 2. Normal delete dialog agar party free hai
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Delete Party?"),
        content: Text("Are you sure you want to remove '${p.name}' from records?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("NO")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () { ph.deleteParty(p.id); Navigator.pop(c); }, 
            child: const Text("YES, DELETE", style: TextStyle(color: Colors.white))
          ),
        ],
      ),
    );
  }
}
