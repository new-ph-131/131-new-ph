// FILE: lib/web_live_sync/sub_views/web_settings/web_signatures_settings_view.dart
// Revision: #PH-REV-797 (ENTERPRISE-WEB-SERIES-AUDIT-AND-D1-SERVICE-SEPARATION)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../pharoah_web_manager.dart';
import '../../../models.dart';
import 'web_settings_sync_coordinator.dart';

class WebSignaturesSettingsView extends StatefulWidget {
  final VoidCallback onBack;
  const WebSignaturesSettingsView({super.key, required this.onBack});

  @override
  State<WebSignaturesSettingsView> createState() => _WebSignaturesSettingsViewState();
}

class _WebSignaturesSettingsViewState extends State<WebSignaturesSettingsView> {
  late bool showStaffSign;
  late TextEditingController labelC;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    final webPh = Provider.of<PharoahWebManager>(context, listen: false);
    showStaffSign = webPh.appConfig.showStaffSign;
    labelC = TextEditingController(text: webPh.appConfig.signLabel);
  }

  @override
  void dispose() {
    labelC.dispose();
    super.dispose();
  }

  Future<void> _save(PharoahWebManager webPh) async {
    setState(() => isSaving = true);
    final cfg = webPh.appConfig;
    cfg.showStaffSign = showStaffSign;
    cfg.signLabel = labelC.text.trim();

    bool synced = await WebSettingsSyncCoordinator.saveAndBroadcastConfig(
      webPh: webPh,
      updatedConfig: cfg,
    );

    setState(() => isSaving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(synced
              ? "✅ Signature & Series Settings Synced to Cloud & App!"
              : "⚠️ Saved locally, cloud sync retrying in background."),
          backgroundColor: synced ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  void _showWebSeriesManagerDialog(PharoahWebManager webPh) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _WebSeriesManagerDialog(webPh: webPh),
    );
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    // Live Web upcoming bill numbers
    final String nextSale = webPh.getNextBillNumber("SALE", "W-", 1);
    final String nextPur = webPh.getNextBillNumber("PURCHASE", "WPUR-", 1);
    final String nextChallan = webPh.getNextBillNumber("CHALLAN", "WSCH-", 1);
    final String nextCN = webPh.getNextBillNumber("RETURN", "WCN-", 101);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: ListView(
        children: [
          // Header
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text("SETTINGS HUB", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.security, color: Colors.blueAccent, size: 24),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "SIGNATURE & SERIES AUDIT",
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                  Text(
                    "Authorised Signatures and Web Invoicing Numbering Schemes",
                    style: TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 30),

          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 680),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.blueAccent.withOpacity(0.3), width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Authorised Signatory Block Switch
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: showStaffSign ? Colors.blue.withOpacity(0.12) : Colors.black26,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: showStaffSign ? Colors.blueAccent : Colors.white10),
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("SHOW AUTHORISED SIGNATORY BLOCK", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: const Text("Prints company stamp & signature block on invoices and delivery challans", style: TextStyle(color: Colors.white54, fontSize: 10)),
                      value: showStaffSign,
                      activeColor: Colors.blueAccent,
                      onChanged: (val) => setState(() => showStaffSign = val),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Authorised Signatory Designation Input
                  const Text("AUTHORISED SIGNATORY DESIGNATION", style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: TextField(
                      controller: labelC,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: "e.g., Authorised Signatory / Store Manager",
                        hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                      ),
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 36),

                  // 3. Web Invoice Numbering Schemes Card
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.format_list_numbered_rounded, color: Colors.blueAccent, size: 22),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                "WEB INVOICING NUMBERING SCHEMES",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.6),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.blueAccent, width: 0.5),
                              ),
                              child: const Text("WEB DUAL-SERIES ACTIVE", style: TextStyle(color: Colors.blueAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Web ERP uses distinct 'W-' numbering prefixes to guarantee zero bill number collisions with the Mobile App (INV- / PUR-).",
                          style: TextStyle(color: Colors.white54, fontSize: 10.5),
                        ),
                        const SizedBox(height: 14),

                        // Upcoming Bill Numbers Grid
                        Row(
                          children: [
                            Expanded(child: _webSeriesBadge("Sale Invoices", "Prefix: W-", nextSale, Icons.receipt_long_rounded)),
                            const SizedBox(width: 10),
                            Expanded(child: _webSeriesBadge("Purchase Inward", "Prefix: WPUR-", nextPur, Icons.shopping_cart_rounded)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _webSeriesBadge("Delivery Challan", "Prefix: WSCH-", nextChallan, Icons.local_shipping_rounded)),
                            const SizedBox(width: 10),
                            Expanded(child: _webSeriesBadge("Credit Note", "Prefix: WCN-", nextCN, Icons.assignment_return_rounded)),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Manage Numbering Schemes Action
                        SizedBox(
                          width: double.infinity,
                          height: 40,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.blueAccent),
                              foregroundColor: Colors.blueAccent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => _showWebSeriesManagerDialog(webPh),
                            icon: const Icon(Icons.settings_suggest_rounded, size: 16),
                            label: const Text("MANAGE WEB NUMBERING SCHEMES", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // 4. Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: isSaving ? null : () => _save(webPh),
                      icon: isSaving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.save_rounded, size: 18),
                      label: Text(
                        isSaving ? "SAVING SIGNATURES..." : "SAVE SIGNATURE SETTINGS",
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _webSeriesBadge(String title, String subtitle, String nextBill, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blueAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 9)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(nextBill, style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 10)),
          ),
        ],
      ),
    );
  }
}

/// 📋 _WebSeriesManagerDialog
/// Web dialog matching the App's SeriesMasterView for full control of numbering series
class _WebSeriesManagerDialog extends StatefulWidget {
  final PharoahWebManager webPh;
  const _WebSeriesManagerDialog({required this.webPh});

  @override
  State<_WebSeriesManagerDialog> createState() => _WebSeriesManagerDialogState();
}

class _WebSeriesManagerDialogState extends State<_WebSeriesManagerDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> types = ["SALE", "PURCHASE", "CHALLAN", "RETURN"];
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: types.length, vsync: this);
    _ensureWebDefaultsAndDeduplicate();
  }

  void _ensureWebDefaultsAndDeduplicate() {
    List<NumberingSeries> current = List.from(widget.webPh.numberingSeries);
    bool modified = false;

    // Deduplicate by (type, prefix) and (type, name)
    Map<String, NumberingSeries> uniqueMap = {};
    for (var s in current) {
      final key = "${s.type.toUpperCase()}_${s.name.trim().toLowerCase()}";
      final prefixKey = "${s.type.toUpperCase()}_${s.prefix.trim().toUpperCase()}";
      if (uniqueMap.containsKey(key)) {
        if (s.isDefault && !uniqueMap[key]!.isDefault) {
          uniqueMap[key] = s;
        }
        modified = true;
      } else if (uniqueMap.containsKey(prefixKey)) {
        if (s.isDefault && !uniqueMap[prefixKey]!.isDefault) {
          uniqueMap[prefixKey] = s;
        }
        modified = true;
      } else {
        uniqueMap[key] = s;
        uniqueMap[prefixKey] = s;
      }
    }
    final distinctList = uniqueMap.values.toSet().toList();
    if (distinctList.length != current.length) {
      current = distinctList;
      modified = true;
    }

    // Ensure Web Default Series (W-, WPUR-, WSCH-, WCN-)
    bool hasWebSale = current.any((s) => s.type.toUpperCase() == "SALE" && s.prefix.trim().toUpperCase() == "W-");
    if (!hasWebSale) {
      for (var s in current) {
        if (s.type.toUpperCase() == "SALE" && s.prefix.trim().toUpperCase() == "INV-") {
          s.isDefault = false;
        }
      }
      current.add(NumberingSeries(
        id: 'web_sale_default',
        name: 'Web Standard Retail',
        type: 'SALE',
        prefix: 'W-',
        startNumber: 1,
        isDefault: true,
        isActive: true,
      ));
      modified = true;
    }

    bool hasWebPur = current.any((s) => s.type.toUpperCase() == "PURCHASE" && s.prefix.trim().toUpperCase() == "WPUR-");
    if (!hasWebPur) {
      current.add(NumberingSeries(
        id: 'web_pur_default',
        name: 'Web Standard Purchase',
        type: 'PURCHASE',
        prefix: 'WPUR-',
        startNumber: 1,
        isDefault: true,
        isActive: true,
      ));
      modified = true;
    }

    bool hasWebSch = current.any((s) => s.type.toUpperCase() == "CHALLAN" && s.prefix.trim().toUpperCase() == "WSCH-");
    if (!hasWebSch) {
      current.add(NumberingSeries(
        id: 'web_sch_default',
        name: 'Web Standard Challan',
        type: 'CHALLAN',
        prefix: 'WSCH-',
        startNumber: 1,
        isDefault: true,
        isActive: true,
      ));
      modified = true;
    }

    bool hasWebCn = current.any((s) => s.type.toUpperCase() == "RETURN" && s.prefix.trim().toUpperCase() == "WCN-");
    if (!hasWebCn) {
      current.add(NumberingSeries(
        id: 'web_cn_default',
        name: 'Web Standard Credit Note',
        type: 'RETURN',
        prefix: 'WCN-',
        startNumber: 1,
        isDefault: true,
        isActive: true,
      ));
      modified = true;
    }

    if (modified) {
      widget.webPh.numberingSeries = current;
      WebSettingsSyncCoordinator.saveAndBroadcastSeries(
        webPh: widget.webPh,
        updatedSeries: current,
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showSeriesForm({NumberingSeries? existing, String? defaultType}) {
    final nameC = TextEditingController(text: existing?.name ?? "");
    final prefixC = TextEditingController(text: existing?.prefix ?? (defaultType == "PURCHASE" ? "WPUR-" : "W-"));
    final startNoC = TextEditingController(text: (existing?.startNumber ?? 1).toString());
    String selType = existing?.type ?? defaultType ?? types[_tabController.index];
    bool isDef = existing?.isDefault ?? false;
    bool isAct = existing?.isActive ?? true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white12)),
            title: Text(existing == null ? "Add Web Numbering Series" : "Edit Web Series", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selType,
                    dropdownColor: const Color(0xFF0F172A),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: "Transaction Type",
                      labelStyle: TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(),
                    ),
                    items: types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (v) => setDialogState(() => selType = v!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameC,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: const InputDecoration(labelText: "Series Name (e.g. Retail Web)", labelStyle: TextStyle(color: Colors.white70), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: prefixC,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: "Prefix (e.g. W-, WPUR-, WRET-)", labelStyle: TextStyle(color: Colors.white70), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: startNoC,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Start From Number", labelStyle: TextStyle(color: Colors.white70), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text("Mark as Default", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    value: isDef,
                    activeColor: Colors.blueAccent,
                    onChanged: (v) => setDialogState(() => isDef = v),
                  ),
                  SwitchListTile(
                    title: const Text("Active (In Use)", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    value: isAct,
                    activeColor: Colors.blueAccent,
                    onChanged: (v) => setDialogState(() => isAct = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL", style: TextStyle(color: Colors.white54))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
                onPressed: () async {
                  if (nameC.text.trim().isEmpty || prefixC.text.trim().isEmpty) return;
                  final prefixClean = prefixC.text.trim().toUpperCase();
                  final ns = NumberingSeries(
                    id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                    name: nameC.text.trim(),
                    type: selType,
                    prefix: prefixClean,
                    startNumber: int.tryParse(startNoC.text) ?? 1,
                    isDefault: isDef,
                    isActive: isAct,
                  );

                  List<NumberingSeries> current = List.from(widget.webPh.numberingSeries);
                  if (isDef) {
                    for (var s in current) {
                      if (s.type == selType) s.isDefault = false;
                    }
                  }

                  if (existing == null) {
                    current.add(ns);
                  } else {
                    int i = current.indexWhere((x) => x.id == ns.id);
                    if (i != -1) current[i] = ns;
                  }

                  await WebSettingsSyncCoordinator.saveAndBroadcastSeries(
                    webPh: widget.webPh,
                    updatedSeries: current,
                  );

                  if (mounted) setState(() {});
                  Navigator.pop(c);
                },
                child: const Text("SAVE SERIES"),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Colors.white12)),
      child: Container(
        width: 700,
        height: 520,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.format_list_numbered_rounded, color: Colors.blueAccent, size: 22),
                const SizedBox(width: 10),
                const Text("WEB NUMBERING SERIES CONFIGURATION", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white54), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 10),
            TabBar(
              controller: _tabController,
              labelColor: Colors.blueAccent,
              unselectedLabelColor: Colors.white54,
              indicatorColor: Colors.blueAccent,
              tabs: types.map((t) => Tab(text: t)).toList(),
            ),
            const Divider(color: Colors.white10, height: 20),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: types.map((t) => _buildSeriesTab(t)).toList(),
              ),
            ),
            const Divider(color: Colors.white10, height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 16, color: Colors.blueAccent),
                  label: const Text("ADD NEW SERIES", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                  onPressed: () => _showSeriesForm(defaultType: types[_tabController.index]),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
                  onPressed: () => Navigator.pop(context),
                  child: const Text("DONE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeriesTab(String type) {
    final list = widget.webPh.numberingSeries
        .where((s) => s.type.toUpperCase() == type.toUpperCase() && s.prefix.trim().toUpperCase() != "INV-")
        .toList();
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.format_list_bulleted_rounded, color: Colors.white24, size: 36),
            const SizedBox(height: 8),
            Text("No custom series defined for $type.", style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              type == "SALE" ? "Default Web fallback prefix: W-" : (type == "PURCHASE" ? "Default fallback: WPUR-" : "Default fallback: WSCH-"),
              style: const TextStyle(color: Colors.cyanAccent, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (c, i) {
        final s = list[i];
        return Card(
          color: const Color(0xFF1E293B),
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: s.isDefault ? Colors.blueAccent : Colors.white12),
          ),
          child: ListTile(
            title: Row(
              children: [
                Text(s.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                if (s.isDefault) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.blueAccent, borderRadius: BorderRadius.circular(4)),
                    child: const Text("DEFAULT", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                  ),
                ],
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: s.isActive ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: s.isActive ? Colors.greenAccent : Colors.redAccent, width: 0.5),
                  ),
                  child: Text(s.isActive ? "ACTIVE" : "STOPPED", style: TextStyle(color: s.isActive ? Colors.greenAccent : Colors.redAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            subtitle: Text("Prefix: ${s.prefix} | Start From: ${s.startNumber}", style: const TextStyle(color: Colors.white54, fontSize: 11)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_note_rounded, color: Colors.blueAccent, size: 20),
                  onPressed: () => _showSeriesForm(existing: s),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                  onPressed: () async {
                    List<NumberingSeries> current = List.from(widget.webPh.numberingSeries);
                    current.removeWhere((x) => x.id == s.id);
                    await WebSettingsSyncCoordinator.saveAndBroadcastSeries(
                      webPh: widget.webPh,
                      updatedSeries: current,
                    );
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
