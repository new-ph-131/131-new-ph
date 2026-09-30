// FILE: lib/web_live_sync/web_party_master.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'web_models.dart';
import 'pharoah_web_manager.dart';

class WebPartyMasterView extends StatefulWidget {
  final VoidCallback onBack;

  const WebPartyMasterView({super.key, required this.onBack});

  @override
  State<WebPartyMasterView> createState() => _WebPartyMasterViewState();
}

class _WebPartyMasterViewState extends State<WebPartyMasterView> {
  String searchQuery = "";
  final List<String> accountGroups = [
    "Sundry Debtors",
    "Sundry Creditors",
    "Bank Accounts",
    "Cash in Hand",
    "Expenses",
  ];

  final List<String> states = [
    "Andhra Pradesh", "Assam", "Bihar", "Chhattisgarh", "Goa", "Gujarat", "Haryana",
    "Himachal Pradesh", "Jharkhand", "Karnataka", "Kerala", "Madhya Pradesh",
    "Maharashtra", "Manipur", "Meghalaya", "Mizoram", "Nagaland", "Odisha",
    "Punjab", "Rajasthan", "Sikkim", "Tamil Nadu", "Telangana", "Tripura",
    "Uttar Pradesh", "Uttarakhand", "West Bengal", "Delhi",
  ];

  void _showPartyForm(PharoahWebManager webPh, {Party? party}) {
    final nameC = TextEditingController(text: party?.name);
    final phoneC = TextEditingController(text: party?.phone);
    final emailC = TextEditingController(text: party?.email);
    final addressC = TextEditingController(text: party?.address);
    final cityC = TextEditingController(text: party?.city);
    final gstC = TextEditingController(text: party?.gst);
    final panC = TextEditingController(text: party?.pan);
    final dlC = TextEditingController(text: party?.dl);
    final dlExpC = TextEditingController(text: party?.dlExp);
    final transportC = TextEditingController(text: party?.transport);
    final opBalC = TextEditingController(text: party?.opBal.toString() ?? "0.0");
    final creditLimitC = TextEditingController(text: party?.creditLimit.toString() ?? "0.0");
    final creditDaysC = TextEditingController(text: party?.creditDays.toString() ?? "30");

    String selectedGroup = party?.group ?? "Sundry Debtors";
    String selectedState = party?.state ?? "Rajasthan";
    String selectedPriceLevel = party?.priceLevel ?? "A";
    String selectedRoute = party?.route ?? "";

    // Auto-extract PAN from GSTIN (Same as original App logic)
    gstC.addListener(() {
      if (gstC.text.length >= 12) {
        String extPan = gstC.text.substring(2, 12).toUpperCase();
        if (panC.text != extPan) {
          panC.text = extPan;
        }
      }
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Colors.white12),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0x332563EB),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF38BDF8), size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  party == null ? "ADD NEW PARTY / LEDGER" : "EDIT PARTY DETAILS",
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SizedBox(
              width: 580,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _inputField("FIRM / CUSTOMER NAME *", nameC, Icons.business, isCaps: true),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedGroup,
                            dropdownColor: const Color(0xFF1E293B),
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            decoration: _dropdownDecor("ACCOUNT GROUP *"),
                            items: accountGroups.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                            onChanged: (v) => setDialogState(() => selectedGroup = v!),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: states.contains(selectedState) ? selectedState : "Rajasthan",
                            dropdownColor: const Color(0xFF1E293B),
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            decoration: _dropdownDecor("STATE (FOR GST)"),
                            items: states.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                            onChanged: (v) => setDialogState(() => selectedState = v!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _inputField("MOBILE NUMBER", phoneC, Icons.phone, isNum: true)),
                        const SizedBox(width: 10),
                        Expanded(child: _inputField("EMAIL ID", emailC, Icons.email)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _inputField("GSTIN NUMBER", gstC, Icons.receipt_long, isCaps: true)),
                        const SizedBox(width: 10),
                        Expanded(child: _inputField("PAN CARD (AUTO)", panC, Icons.badge_outlined, isCaps: true)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _inputField("DRUG LICENSE (DL)", dlC, Icons.medical_services, isCaps: true)),
                        const SizedBox(width: 10),
                        Expanded(child: _inputField("DL EXPIRY", dlExpC, Icons.event_busy, isCaps: true)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _inputField("CITY", cityC, Icons.location_city, isCaps: true)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedPriceLevel,
                            dropdownColor: const Color(0xFF1E293B),
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            decoration: _dropdownDecor("PRICE LEVEL"),
                            items: ["A", "B", "C"].map((p) => DropdownMenuItem(value: p, child: Text("Rate $p"))).toList(),
                            onChanged: (v) => setDialogState(() => selectedPriceLevel = v!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _inputField("OFFICE / SHOP ADDRESS", addressC, Icons.location_on),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _inputField("OPENING BALANCE ₹", opBalC, Icons.account_balance_wallet, isNum: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _inputField("CREDIT LIMIT ₹", creditLimitC, Icons.speed, isNum: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _inputField("CREDIT DAYS", creditDaysC, Icons.timer, isNum: true)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedRoute.isEmpty ? null : (webPh.routes.any((r) => r.name == selectedRoute) ? selectedRoute : null),
                            dropdownColor: const Color(0xFF1E293B),
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            decoration: _dropdownDecor("ASSIGNED ROUTE"),
                            items: webPh.routes.map((r) => DropdownMenuItem(value: r.name, child: Text(r.name))).toList(),
                            onChanged: (v) => setDialogState(() => selectedRoute = v ?? ""),
                            hint: const Text("Select Route", style: TextStyle(color: Colors.white38, fontSize: 11)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: _inputField("TRANSPORT", transportC, Icons.local_shipping_outlined)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  if (nameC.text.trim().isEmpty) return;

                  final newParty = Party(
                    id: party?.id ?? "PARTY-${DateTime.now().millisecondsSinceEpoch}",
                    name: nameC.text.trim().toUpperCase(),
                    group: selectedGroup,
                    phone: phoneC.text.trim(),
                    email: emailC.text.trim().toLowerCase(),
                    address: addressC.text.trim(),
                    city: cityC.text.trim().toUpperCase(),
                    state: selectedState,
                    gst: gstC.text.trim().toUpperCase().isEmpty ? "N/A" : gstC.text.trim().toUpperCase(),
                    pan: panC.text.trim().toUpperCase(),
                    dl: dlC.text.trim().toUpperCase().isEmpty ? "N/A" : dlC.text.trim().toUpperCase(),
                    dlExp: dlExpC.text.trim(),
                    opBal: double.tryParse(opBalC.text) ?? 0.0,
                    creditLimit: double.tryParse(creditLimitC.text) ?? 0.0,
                    creditDays: int.tryParse(creditDaysC.text) ?? 30,
                    priceLevel: selectedPriceLevel,
                    route: selectedRoute,
                    transport: transportC.text.trim(),
                  );

                  if (party == null) {
                    webPh.addParty(newParty);
                  } else {
                    webPh.updateParty(newParty);
                  }

                  Navigator.pop(c);
                },
                child: const Text("SAVE PARTY", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);
    final filteredList = webPh.parties.where((p) =>
        p.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
        p.city.toLowerCase().contains(searchQuery.toLowerCase()) ||
        p.group.toLowerCase().contains(searchQuery.toLowerCase()) ||
        p.phone.toLowerCase().contains(searchQuery.toLowerCase()) ||
        p.gst.toLowerCase().contains(searchQuery.toLowerCase())).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white12,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text("BACK", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.group_rounded, color: Color(0xFF38BDF8), size: 22),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "PARTY & LEDGER MASTER",
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                  Text(
                    "${webPh.parties.length} Total Accounts (Customers & Suppliers)",
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ],
              ),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () => _showPartyForm(webPh),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text("ADD NEW PARTY", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 25),

          // Search Box
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: const InputDecoration(
                hintText: "Search Party by Name, City, Group, GSTIN, Phone...",
                hintStyle: TextStyle(color: Colors.white38, fontSize: 11),
                prefixIcon: Icon(Icons.search, color: Color(0xFF38BDF8), size: 18),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (v) => setState(() => searchQuery = v),
            ),
          ),
          const SizedBox(height: 16),

          // Parties Table
          Expanded(
            child: filteredList.isEmpty
                ? const Center(
                    child: Text("No parties found matching search query.", style: TextStyle(color: Colors.white38)),
                  )
                : SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 800),
                      child: Table(
                        columnWidths: const {
                          0: FixedColumnWidth(130),
                          1: FlexColumnWidth(3),
                          2: FixedColumnWidth(100),
                          3: FixedColumnWidth(100),
                          4: FixedColumnWidth(130),
                          5: FixedColumnWidth(100),
                          6: FixedColumnWidth(90),
                        },
                        children: [
                          TableRow(
                            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                            children: [
                              _th("GROUP"),
                              _th("PARTY / FIRM NAME", isLeft: true),
                              _th("CITY"),
                              _th("PHONE"),
                              _th("GSTIN"),
                              _th("BALANCE"),
                              _th("ACTIONS"),
                            ],
                          ),
                          for (final p in filteredList)
                            TableRow(
                              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                              children: [
                                _tdGroupBadge(p.group),
                                _td(p.name, isLeft: true, isBold: true),
                                _td(p.city),
                                _td(p.phone.isEmpty ? "-" : p.phone),
                                _td(p.gst),
                                _td("₹${p.opBal.toStringAsFixed(2)}", isBold: true, color: p.opBal > 0 ? Colors.greenAccent : (p.opBal < 0 ? Colors.redAccent : Colors.white70)),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_note_rounded, size: 18, color: Color(0xFF38BDF8)),
                                      tooltip: "Edit Party",
                                      onPressed: () => _showPartyForm(webPh, party: p),
                                    ),
                                    if (p.name != "CASH")
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                                        tooltip: "Delete Party",
                                        onPressed: () => _confirmDelete(webPh, p),
                                      ),
                                  ],
                                ),
                              ],
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

  Widget _th(String t, {bool isLeft = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
    child: Text(t, textAlign: isLeft ? TextAlign.left : TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
  );

  Widget _td(String t, {bool isLeft = false, bool isBold = false, Color color = Colors.white}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
    child: Text(t, textAlign: isLeft ? TextAlign.left : TextAlign.center, style: TextStyle(color: color, fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal), overflow: TextOverflow.ellipsis),
  );

  Widget _tdGroupBadge(String group) {
    Color bg = const Color(0x332563EB);
    Color fg = const Color(0xFF38BDF8);

    if (group.contains("Creditors")) {
      bg = const Color(0x33F59E0B);
      fg = const Color(0xFFFBBF24);
    } else if (group.contains("Bank")) {
      bg = const Color(0x3306B6D4);
      fg = const Color(0xFF22D3EE);
    } else if (group.contains("Expenses")) {
      bg = const Color(0x33DC2626);
      fg = const Color(0xFFF87171);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
          child: Text(group, style: TextStyle(color: fg, fontSize: 8.5, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }

  Widget _inputField(String label, TextEditingController ctrl, IconData icon, {bool isNum = false, bool isCaps = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      textCapitalization: isCaps ? TextCapitalization.characters : TextCapitalization.none,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold),
        prefixIcon: Icon(icon, color: const Color(0xFF38BDF8), size: 16),
        filled: true,
        fillColor: Colors.black26,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }

  InputDecoration _dropdownDecor(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold),
      filled: true,
      fillColor: Colors.black26,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }

  void _confirmDelete(PharoahWebManager webPh, Party p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("Delete Party?", style: TextStyle(color: Colors.white, fontSize: 14)),
        content: Text("Are you sure you want to remove '${p.name}' from records?", style: const TextStyle(color: Colors.white70, fontSize: 11)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              webPh.deleteParty(p.id);
              Navigator.pop(ctx);
            },
            child: const Text("DELETE"),
          ),
        ],
      ),
    );
  }
}
