// FILE: lib/administration/staff_management_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../pharoah_manager.dart';
import '../../models.dart';

class StaffManagementView extends StatefulWidget {
  const StaffManagementView({super.key});

  @override
  State<StaffManagementView> createState() => _StaffManagementViewState();
}

class _StaffManagementViewState extends State<StaffManagementView> {
  // --- UI: SALESMAN ENTRY FORM (POPUP) ---
  void _showSalesmanForm({Salesman? sman}) {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    
    final nameC = TextEditingController(text: sman?.name);
    final phoneC = TextEditingController(text: sman?.phone);
    
    // Default route selection logic
    String? selectedRoute = sman?.route;
    if (selectedRoute == null || selectedRoute.isEmpty) {
      if (ph.routes.isNotEmpty) selectedRoute = ph.routes[0].name;
    }

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text(sman == null ? "Register New Salesman" : "Edit Salesman Info"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildField(nameC, "Full Name", Icons.person, isCaps: true),
                _buildField(phoneC, "Mobile Number", Icons.phone, isNum: true),
                const SizedBox(height: 15),
                
                // --- ROUTE SELECTION DROPDOWN ---
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("ASSIGNED AREA / ROUTE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                ),
                const SizedBox(height: 5),
                DropdownButtonFormField<String>(
                  value: selectedRoute,
                  decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.map_rounded)),
                  items: ph.routes.map((r) => DropdownMenuItem(value: r.name, child: Text(r.name))).toList(),
                  onChanged: (v) => setDialogState(() => selectedRoute = v),
                  hint: const Text("Select Route"),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade900),
              onPressed: () {
                if (nameC.text.trim().isEmpty) return;

                final newSman = Salesman(
                  id: sman?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameC.text.trim().toUpperCase(),
                  phone: phoneC.text.trim(),
                  route: selectedRoute ?? "No Route",
                );

                if (sman == null) {
                  ph.addSalesman(newSman);
                } else {
                  int idx = ph.salesmen.indexWhere((x) => x.id == sman.id);
                  if (idx != -1) ph.salesmen[idx] = newSman;
                  ph.save();
                }
                
                Navigator.pop(c);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Salesman Record Saved!")));
              },
              child: const Text("SAVE STAFF", style: TextStyle(color: Colors.white)),
            )
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: const Text("Staff & Salesman Master"),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
      ),
      body: ph.salesmen.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: ph.salesmen.length,
              itemBuilder: (c, i) {
                final s = ph.salesmen[i];
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: const CircleAvatar(backgroundColor: Colors.red, child: Icon(Icons.badge, color: Colors.white)),
                    title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("Area: ${s.route} | Phone: ${s.phone}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _showSalesmanForm(sman: s)),
                        IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _confirmDelete(ph, s)),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showSalesmanForm(),
        backgroundColor: Colors.red.shade900,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text("ADD SALESMAN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // --- UI HELPERS ---
  Widget _buildField(TextEditingController ctrl, String label, IconData icon, {bool isNum = false, bool isCaps = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: ctrl,
        keyboardType: isNum ? TextInputType.number : TextInputType.text,
        textCapitalization: isCaps ? TextCapitalization.characters : TextCapitalization.none,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), border: const OutlineInputBorder()),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.group_off_rounded, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 10),
          const Text("No salesman registered yet.", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  void _confirmDelete(PharoahManager ph, Salesman s) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Remove Salesman?"),
        content: Text("Are you sure you want to delete '${s.name}' from records?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("NO")),
          ElevatedButton(onPressed: () { ph.deleteSalesman(s.id); Navigator.pop(c); }, child: const Text("YES, DELETE")),
        ],
      ),
    );
  }
}
