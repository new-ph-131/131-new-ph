import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pharoah_manager.dart';
import 'company_registry_model.dart';
import 'multi_setup_view.dart';
import 'export_service.dart'; 

class CompanyListScreen extends StatefulWidget {
  const CompanyListScreen({super.key});
  @override
  State<CompanyListScreen> createState() => _CompanyListScreenState();
}

class _CompanyListScreenState extends State<CompanyListScreen> {
  String searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final list = ph.companiesRegistry.where((c) => 
      c.name.toLowerCase().contains(searchQuery.toLowerCase()) || 
      c.id.toLowerCase().contains(searchQuery.toLowerCase())
    ).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text("Pharoah ERP Gateway", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_backup_restore_rounded),
            tooltip: "Restore",
            onPressed: () async {
              bool success = await ExportService(ph).importCompany();
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Restored!")));
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_business_rounded, size: 28),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const MultiSetupView(isFirstRun: false))),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            color: const Color(0xFF0D47A1),
            child: TextField(
              onChanged: (v) => setState(() => searchQuery = v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Search your business...",
                hintStyle: const TextStyle(color: Colors.white60),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                filled: true, fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text("No business found."))
                : ListView.builder(
                    padding: const EdgeInsets.all(15),
                    itemCount: list.length,
                    itemBuilder: (c, i) {
                      final comp = list[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.shade200)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(15),
                          leading: const CircleAvatar(child: Icon(Icons.business)),
                          title: Text(comp.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("ID: ${comp.id} | ${comp.businessType}"),
                          onTap: () { ph.activeCompany = comp; ph.notifyListeners(); },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
