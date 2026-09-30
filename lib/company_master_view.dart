import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pharoah_manager.dart';
import 'models.dart';

class CompanyMasterView extends StatefulWidget {
  const CompanyMasterView({super.key});
  @override State<CompanyMasterView> createState() => _CompanyMasterViewState();
}

class _CompanyMasterViewState extends State<CompanyMasterView> {
  String search = "";

  void _showForm({Company? comp}) {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    final nameC = TextEditingController(text: comp?.name);

    showDialog(context: context, builder: (c) => AlertDialog(
      title: Text(comp == null ? "Add Company" : "Edit Company"),
      content: TextField(
        controller: nameC, 
        decoration: const InputDecoration(labelText: "Company Name"),
        textCapitalization: TextCapitalization.characters,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
        ElevatedButton(onPressed: () {
          if (nameC.text.isEmpty) return;
          if (comp == null) {
            ph.addCompany(Company(id: DateTime.now().toString(), name: nameC.text.toUpperCase()));
          } else {
            int i = ph.companies.indexWhere((x) => x.id == comp.id);
            ph.companies[i].name = nameC.text.toUpperCase();
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
    final list = ph.companies.where((c) => c.name.toLowerCase().contains(search.toLowerCase())).toList();

    return Scaffold(
      appBar: AppBar(title: const Text("Company Master"), backgroundColor: Colors.brown),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(
          decoration: const InputDecoration(hintText: "Search Company...", prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
          onChanged: (v) => setState(() => search = v),
        )),
        Expanded(child: ListView.builder(
          itemCount: list.length,
          itemBuilder: (c, i) => ListTile(
            leading: const Icon(Icons.business, color: Colors.brown),
            title: Text(list[i].name, style: const TextStyle(fontWeight: FontWeight.bold)),
            trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => _showForm(comp: list[i])),
          ),
        )),
      ]),
      floatingActionButton: FloatingActionButton(onPressed: () => _showForm(), child: const Icon(Icons.add), backgroundColor: Colors.brown, foregroundColor: Colors.white),
    );
  }
}
