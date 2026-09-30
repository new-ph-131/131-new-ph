import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pharoah_manager.dart';
import 'models.dart';

class SaltMasterView extends StatefulWidget {
  const SaltMasterView({super.key});
  @override State<SaltMasterView> createState() => _SaltMasterViewState();
}

class _SaltMasterViewState extends State<SaltMasterView> {
  String search = "";

  void _showForm({Salt? salt}) {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    final nameC = TextEditingController(text: salt?.name);
    String selType = salt?.type ?? "Mono";

    showDialog(context: context, builder: (c) => StatefulBuilder(builder: (context, setDialogState) {
      return AlertDialog(
        title: Text(salt == null ? "Add New Salt" : "Edit Salt"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameC, decoration: const InputDecoration(labelText: "Salt Name"), textCapitalization: TextCapitalization.characters),
          const SizedBox(height: 15),
          DropdownButtonFormField<String>(
            value: selType,
            decoration: const InputDecoration(labelText: "Combination Type", border: OutlineInputBorder()),
            items: ["Mono", "Duo", "Multi"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (v) => setDialogState(() => selType = v!),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(onPressed: () {
            if (nameC.text.isEmpty) return;
            if (salt == null) {
              ph.addSalt(Salt(id: DateTime.now().toString(), name: nameC.text.toUpperCase(), type: selType));
            } else {
              int i = ph.salts.indexWhere((x) => x.id == salt.id);
              ph.salts[i].name = nameC.text.toUpperCase();
              ph.salts[i].type = selType;
              ph.save();
            }
            Navigator.pop(c);
          }, child: const Text("SAVE"))
        ],
      );
    }));
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final list = ph.salts.where((s) => s.name.toLowerCase().contains(search.toLowerCase())).toList();

    return Scaffold(
      appBar: AppBar(title: const Text("Salt / Composition Master"), backgroundColor: Colors.deepOrange),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(
          decoration: const InputDecoration(hintText: "Search Salt...", prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
          onChanged: (v) => setState(() => search = v),
        )),
        Expanded(child: ListView.builder(
          itemCount: list.length,
          itemBuilder: (c, i) => ListTile(
            leading: const Icon(Icons.science, color: Colors.deepOrange),
            title: Text(list[i].name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("Type: ${list[i].type}"),
            trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => _showForm(salt: list[i])),
          ),
        )),
      ]),
      floatingActionButton: FloatingActionButton(onPressed: () => _showForm(), child: const Icon(Icons.add), backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
    );
  }
}
