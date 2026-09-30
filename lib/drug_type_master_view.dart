import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pharoah_manager.dart';
import 'models.dart';

class DrugTypeMasterView extends StatefulWidget {
  const DrugTypeMasterView({super.key});
  @override State<DrugTypeMasterView> createState() => _DrugTypeMasterViewState();
}

class _DrugTypeMasterViewState extends State<DrugTypeMasterView> {
  String search = "";

  void _showForm({DrugType? dtype}) {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    final nameC = TextEditingController(text: dtype?.name);

    showDialog(context: context, builder: (c) => AlertDialog(
      title: Text(dtype == null ? "Add Category" : "Edit Category"),
      content: TextField(controller: nameC, decoration: const InputDecoration(labelText: "Category Name (e.g. Schedule H)"), textCapitalization: TextCapitalization.characters),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
        ElevatedButton(onPressed: () {
          if (nameC.text.isEmpty) return;
          if (dtype == null) {
            ph.addDrugType(DrugType(id: DateTime.now().toString(), name: nameC.text.toUpperCase()));
          } else {
            int i = ph.drugTypes.indexWhere((x) => x.id == dtype.id);
            ph.drugTypes[i].name = nameC.text.toUpperCase();
            ph.save();
          }
          Navigator.pop(c);
        }, child: const Text("SAVE"))
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final list = ph.drugTypes.where((d) => d.name.toLowerCase().contains(search.toLowerCase())).toList();

    return Scaffold(
      appBar: AppBar(title: const Text("Drug Category Master"), backgroundColor: Colors.cyan.shade700),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(
          decoration: const InputDecoration(hintText: "Search Category...", prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
          onChanged: (v) => setState(() => search = v),
        )),
        Expanded(child: ListView.builder(
          itemCount: list.length,
          itemBuilder: (c, i) => ListTile(
            leading: const Icon(Icons.verified_user, color: Colors.cyan),
            title: Text(list[i].name, style: const TextStyle(fontWeight: FontWeight.bold)),
            trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => _showForm(dtype: list[i])),
          ),
        )),
      ]),
      floatingActionButton: FloatingActionButton(onPressed: () => _showForm(), child: const Icon(Icons.add), backgroundColor: Colors.cyan.shade700, foregroundColor: Colors.white),
    );
  }
}
