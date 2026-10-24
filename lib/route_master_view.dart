import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pharoah_manager.dart';
import 'models.dart';
import 'logic/master_cascade_service.dart';

class RouteMasterView extends StatefulWidget {
  const RouteMasterView({super.key});

  @override
  State<RouteMasterView> createState() => _RouteMasterViewState();
}

class _RouteMasterViewState extends State<RouteMasterView> {
  String _searchQuery = "";

  void _showRouteDialog(BuildContext context, PharoahManager ph, {RouteArea? route}) {
    final ctrl = TextEditingController(text: route?.name);
    final String? oldName = route?.name;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          route == null ? "Add New Route / Area" : "Edit Route / Area",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: "Route Name",
            hintText: "e.g. CITY CENTER / HIGHWAY",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () {
              final clean = ctrl.text.trim().toUpperCase();
              if (clean.isNotEmpty) {
                if (route == null) {
                  ph.saveOrUpdateRoute(RouteArea(id: "", name: clean));
                } else {
                  ph.saveOrUpdateRoute(
                    RouteArea(id: route.id, name: clean, version: route.version, updatedAt: route.updatedAt),
                    previousName: oldName,
                  );
                }
                Navigator.pop(context);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(content: Text(route == null ? "Route Added Successfully!" : "Route Updated & Cascaded to Parties!")),
                );
              }
            },
            child: Text(route == null ? "ADD ROUTE" : "SAVE ROUTE", style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final filteredRoutes = ph.routes.where((r) => r.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: const Text("Route / Area Master"),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            color: Colors.teal.shade50,
            child: TextField(
              decoration: InputDecoration(
                hintText: "Search Route...",
                prefixIcon: const Icon(Icons.search, color: Colors.teal),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          Expanded(
            child: filteredRoutes.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.map_outlined, size: 80, color: Colors.grey.shade300),
                        const SizedBox(height: 10),
                        const Text("No routes defined yet.", style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: filteredRoutes.length,
                    itemBuilder: (context, index) {
                      final route = filteredRoutes[index];
                      final partyCount = ph.parties.where((p) => MasterCascadeService.belongsToRoute(p, route)).length;
                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.teal.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.location_on, color: Colors.teal, size: 20),
                          ),
                          title: Text(
                            route.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          subtitle: Text("$partyCount Linked Party(s)"),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.teal),
                                onPressed: () => _showRouteDialog(context, ph, route: route),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () => _confirmDelete(ph, route),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRouteDialog(context, ph),
        backgroundColor: Colors.teal,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("CREATE NEW ROUTE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _confirmDelete(PharoahManager ph, RouteArea route) {
    final partyCount = ph.parties.where((p) => MasterCascadeService.belongsToRoute(p, route)).length;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Delete Route?"),
        content: Text(
          partyCount > 0
              ? "Are you sure you want to delete '${route.name}'? $partyCount mapped party(s) will have their route cleared."
              : "Are you sure you want to delete '${route.name}'?",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("NO")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              ph.deleteRoute(route.id);
              Navigator.pop(c);
            },
            child: const Text("YES, DELETE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
