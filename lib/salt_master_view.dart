import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pharoah_manager.dart';
import 'models.dart';
import 'logic/master_cascade_service.dart';

class SaltMasterView extends StatefulWidget {
  const SaltMasterView({super.key});
  @override
  State<SaltMasterView> createState() => _SaltMasterViewState();
}

class _SaltMasterViewState extends State<SaltMasterView> {
  String search = "";

  void _showForm({Salt? salt}) {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    final nameC = TextEditingController(text: salt?.name);
    final String? oldName = salt?.name;
    String selType = salt?.type ?? "Mono";

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(salt == null ? "Add New Salt" : "Edit Salt"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameC,
                  decoration: const InputDecoration(labelText: "Salt Name"),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 15),
                DropdownButtonFormField<String>(
                  value: ["Mono", "Duo", "Multi"].contains(selType) ? selType : "Mono",
                  decoration: const InputDecoration(labelText: "Combination Type", border: OutlineInputBorder()),
                  items: ["Mono", "Duo", "Multi"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setDialogState(() => selType = v!),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
              ElevatedButton(
                onPressed: () {
                  final clean = nameC.text.trim().toUpperCase();
                  if (clean.isEmpty) return;
                  if (salt == null) {
                    ph.saveOrUpdateSalt(Salt(id: "", name: clean, type: selType));
                  } else {
                    ph.saveOrUpdateSalt(
                      Salt(id: salt.id, name: clean, type: selType, version: salt.version, updatedAt: salt.updatedAt),
                      previousName: oldName,
                    );
                  }
                  Navigator.pop(c);
                },
                child: const Text("SAVE"),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDelete(PharoahManager ph, Salt salt) {
    final linkedCount = ph.medicines.where((m) => MasterCascadeService.belongsToSalt(m, salt)).length;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Delete Salt?"),
        content: Text(
          linkedCount > 0
              ? "'${salt.name}' is linked to $linkedCount product(s). Deleting it will unlink those products and sync across all devices."
              : "Are you sure you want to delete '${salt.name}'?",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              ph.deleteSalt(salt.id);
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
    final list = ph.salts.where((s) => s.name.toLowerCase().contains(search.toLowerCase())).toList();

    return Scaffold(
      appBar: AppBar(title: const Text("Salt / Composition Master"), backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: "Search Salt...",
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
                final salt = list[i];
                final itemCount = ph.medicines.where((m) => MasterCascadeService.belongsToSalt(m, salt)).length;
                return ListTile(
                  leading: const Icon(Icons.science, color: Colors.deepOrange),
                  title: Text(salt.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("Type: ${salt.type} • $itemCount Product(s)"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit), onPressed: () => _showForm(salt: salt)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _confirmDelete(ph, salt),
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
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}
