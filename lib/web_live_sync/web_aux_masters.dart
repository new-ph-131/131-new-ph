// FILE: lib/web_live_sync/web_aux_masters.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'web_models.dart';
import 'pharoah_web_manager.dart';

class WebAuxMastersView extends StatefulWidget {
  final VoidCallback onBack;
  final int initialTabIndex;

  const WebAuxMastersView({
    super.key,
    required this.onBack,
    this.initialTabIndex = 0,
  });

  @override
  State<WebAuxMastersView> createState() => _WebAuxMastersViewState();
}

class _WebAuxMastersViewState extends State<WebAuxMastersView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String searchQuery = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() => searchQuery = "");
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // 1. COMPANY BRAND DIALOG
  // ===========================================================================
  void _showCompanyDialog(PharoahWebManager webPh, {Company? comp}) {
    final nameC = TextEditingController(text: comp?.name);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Colors.white12),
        ),
        title: Text(
          comp == null ? "ADD COMPANY BRAND" : "EDIT COMPANY BRAND",
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        content: _inputField("COMPANY / MANUFACTURER NAME *", nameC, isCaps: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              if (nameC.text.trim().isEmpty) return;
              if (comp == null) {
                webPh.getOrCreateCompany(nameC.text.trim());
              } else {
                comp.name = nameC.text.trim().toUpperCase();
              }
              Navigator.pop(c);
              setState(() {});
            },
            child: const Text("SAVE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 2. SALT COMPOSITION DIALOG
  // ===========================================================================
  void _showSaltDialog(PharoahWebManager webPh, {Salt? salt}) {
    final nameC = TextEditingController(text: salt?.name);
    String selType = salt?.type ?? "Mono";

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Colors.white12),
          ),
          title: Text(
            salt == null ? "ADD SALT COMPOSITION" : "EDIT SALT COMPOSITION",
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _inputField("SALT / MOLECULE NAME *", nameC, isCaps: true),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selType,
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: "COMBINATION TYPE",
                  labelStyle: const TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                items: ["Mono", "Duo", "Multi"].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setDialogState(() => selType = v!),
              ),
            ],
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                if (nameC.text.trim().isEmpty) return;
                if (salt == null) {
                  String id = "SL-${1000 + webPh.salts.length + 1}";
                  webPh.salts.add(Salt(id: id, name: nameC.text.trim().toUpperCase(), type: selType));
                } else {
                  salt.name = nameC.text.trim().toUpperCase();
                  salt.type = selType;
                }
                Navigator.pop(c);
                setState(() {});
              },
              child: const Text("SAVE", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 3. ROUTE / AREA DIALOG
  // ===========================================================================
  void _showRouteDialog(PharoahWebManager webPh, {RouteArea? route}) {
    final nameC = TextEditingController(text: route?.name);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Colors.white12),
        ),
        title: Text(
          route == null ? "ADD DELIVERY ROUTE" : "EDIT DELIVERY ROUTE",
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        content: _inputField("ROUTE / AREA NAME *", nameC, isCaps: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              if (nameC.text.trim().isEmpty) return;
              if (route == null) {
                String id = "RT-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";
                webPh.routes.add(RouteArea(id: id, name: nameC.text.trim().toUpperCase()));
              } else {
                route.name = nameC.text.trim().toUpperCase();
              }
              Navigator.pop(c);
              setState(() {});
            },
            child: const Text("SAVE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

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
              const Icon(Icons.stars_rounded, color: Color(0xFFF59E0B), size: 22),
              const SizedBox(width: 10),
              const Text(
                "BUSINESS AUXILIARY MASTERS",
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 15),

          // Tabs Switcher
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF38BDF8),
              labelColor: const Color(0xFF38BDF8),
              unselectedLabelColor: Colors.white54,
              tabs: [
                Tab(text: "COMPANIES (${webPh.companies.length})", icon: const Icon(Icons.business_rounded, size: 16)),
                Tab(text: "SALTS (${webPh.salts.length})", icon: const Icon(Icons.science_rounded, size: 16)),
                Tab(text: "ROUTES (${webPh.routes.length})", icon: const Icon(Icons.map_rounded, size: 16)),
              ],
            ),
          ),
          const SizedBox(height: 15),

          // Search & Action Row
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: TextField(
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: "Search in active master list...",
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 11),
                      prefixIcon: Icon(Icons.search, color: Color(0xFF38BDF8), size: 16),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 9),
                    ),
                    onChanged: (v) => setState(() => searchQuery = v),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                onPressed: () {
                  if (_tabController.index == 0) _showCompanyDialog(webPh);
                  if (_tabController.index == 1) _showSaltDialog(webPh);
                  if (_tabController.index == 2) _showRouteDialog(webPh);
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text("ADD NEW", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCompanyList(webPh),
                _buildSaltList(webPh),
                _buildRouteList(webPh),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyList(PharoahWebManager webPh) {
    final list = webPh.companies.where((c) => c.name.toLowerCase().contains(searchQuery.toLowerCase())).toList();
    if (list.isEmpty) return const Center(child: Text("No companies found.", style: TextStyle(color: Colors.white38)));

    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (c, i) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(8)),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.business_rounded, color: Color(0xFFF59E0B), size: 18),
          title: Text(list[i].name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          subtitle: Text("ID: ${list[i].id}", style: const TextStyle(color: Colors.white38, fontSize: 9.5)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_note_rounded, size: 18, color: Color(0xFF38BDF8)),
                onPressed: () => _showCompanyDialog(webPh, comp: list[i]),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                onPressed: () {
                  setState(() => webPh.companies.removeAt(i));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSaltList(PharoahWebManager webPh) {
    final list = webPh.salts.where((s) => s.name.toLowerCase().contains(searchQuery.toLowerCase())).toList();
    if (list.isEmpty) return const Center(child: Text("No salts found.", style: TextStyle(color: Colors.white38)));

    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (c, i) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(8)),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.science_rounded, color: Color(0xFF10B981), size: 18),
          title: Text(list[i].name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          subtitle: Text("Type: ${list[i].type} | ID: ${list[i].id}", style: const TextStyle(color: Colors.white38, fontSize: 9.5)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_note_rounded, size: 18, color: Color(0xFF38BDF8)),
                onPressed: () => _showSaltDialog(webPh, salt: list[i]),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                onPressed: () {
                  setState(() => webPh.salts.removeAt(i));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouteList(PharoahWebManager webPh) {
    final list = webPh.routes.where((r) => r.name.toLowerCase().contains(searchQuery.toLowerCase())).toList();
    if (list.isEmpty) return const Center(child: Text("No delivery routes found.", style: TextStyle(color: Colors.white38)));

    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (c, i) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(8)),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.map_rounded, color: Color(0xFF06B6D4), size: 18),
          title: Text(list[i].name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_note_rounded, size: 18, color: Color(0xFF38BDF8)),
                onPressed: () => _showRouteDialog(webPh, route: list[i]),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                onPressed: () {
                  setState(() => webPh.routes.removeAt(i));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputField(String label, TextEditingController ctrl, {bool isCaps = false}) {
    return TextField(
      controller: ctrl,
      textCapitalization: isCaps ? TextCapitalization.characters : TextCapitalization.none,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold),
        filled: true,
        fillColor: Colors.black26,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }
}
