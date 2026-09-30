import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pharoah_manager.dart';
import 'models.dart';

class RouteMasterView extends StatefulWidget {
  const RouteMasterView({super.key});

  @override
  State<RouteMasterView> createState() => _RouteMasterViewState();
}

class _RouteMasterViewState extends State<RouteMasterView> {
  final TextEditingController _routeController = TextEditingController();
  String _searchQuery = "";

  // --- Naya Route jodne ke liye dialog ---
  void _showAddRouteDialog(BuildContext context, PharoahManager ph) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Add New Route / Area", style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: _routeController,
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
            onPressed: () {
              _routeController.clear();
              Navigator.pop(context);
            },
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () {
              if (_routeController.text.trim().isNotEmpty) {
                final newRoute = RouteArea(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: _routeController.text.trim().toUpperCase(),
                );
                ph.addRoute(newRoute);
                _routeController.clear();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Route Added Successfully!")),
                );
              }
            },
            child: const Text("ADD ROUTE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    // Filtered list for search
    final filteredRoutes = ph.routes.where((r) => 
      r.name.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();

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
          // --- SEARCH BAR ---
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

          // --- ROUTE LIST ---
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
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _confirmDelete(ph, route),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddRouteDialog(context, ph),
        backgroundColor: Colors.teal,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("CREATE NEW ROUTE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _confirmDelete(PharoahManager ph, RouteArea route) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Delete Route?"),
        content: Text("Are you sure you want to delete '${route.name}'? This will not affect existing parties but will remove it from the master list."),
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
