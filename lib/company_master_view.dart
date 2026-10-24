import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pharoah_manager.dart';
import 'models.dart';
import 'logic/master_cascade_service.dart';

class CompanyMasterView extends StatefulWidget {
  const CompanyMasterView({super.key});
  @override
  State<CompanyMasterView> createState() => _CompanyMasterViewState();
}

class _CompanyMasterViewState extends State<CompanyMasterView> {
  String search = "";

  void _showForm({Company? comp}) {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    final nameC = TextEditingController(text: comp?.name);
    final String? oldName = comp?.name;

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(comp == null ? "Add Company" : "Edit Company"),
        content: TextField(
          controller: nameC,
          decoration: const InputDecoration(labelText: "Company Name"),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () {
              final clean = nameC.text.trim().toUpperCase();
              if (clean.isEmpty) return;
              if (comp == null) {
                ph.saveOrUpdateCompany(Company(id: "", name: clean));
              } else {
                ph.saveOrUpdateCompany(
                  Company(id: comp.id, name: clean, version: comp.version, updatedAt: comp.updatedAt),
                  previousName: oldName,
                );
              }
              Navigator.pop(c);
            },
            child: const Text("SAVE"),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(PharoahManager ph, Company comp) {
    final linkedCount = ph.medicines.where((m) => MasterCascadeService.belongsToCompany(m, comp)).length;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Delete Company?"),
        content: Text(
          linkedCount > 0
              ? "'${comp.name}' is linked to $linkedCount product(s). Deleting it will unlink those products and sync across all devices."
              : "Are you sure you want to delete '${comp.name}'?",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              ph.deleteCompany(comp.id);
              Navigator.pop(c);
            },
            child: const Text("DELETE"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final list = ph.companies.where((c) => c.name.toLowerCase().contains(search.toLowerCase())).toList();

    return Scaffold(
      appBar: AppBar(title: const Text("Company Master"), backgroundColor: Colors.brown, foregroundColor: Colors.white),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: "Search Company...",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => search = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (c, i) {
                final comp = list[i];
                final itemCount = ph.medicines.where((m) => MasterCascadeService.belongsToCompany(m, comp)).length;
                return ListTile(
                  leading: const Icon(Icons.business, color: Colors.brown),
                  title: Text(comp.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("$itemCount Linked Product(s)"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit), onPressed: () => _showForm(comp: comp)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _confirmDelete(ph, comp),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}
