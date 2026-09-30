// FILE: lib/administration/system_user_master_view.dart (Replacement Code - FIXED)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../pharoah_manager.dart';
import 'system_user_model.dart';

class SystemUserMasterView extends StatefulWidget {
  const SystemUserMasterView({super.key});

  @override
  State<SystemUserMasterView> createState() => _SystemUserMasterViewState();
}

class _SystemUserMasterViewState extends State<SystemUserMasterView> {
  
  // --- UI: ADD/EDIT STAFF DIALOG ---
  void _showUserForm({SystemUser? user}) {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    
    final nameC = TextEditingController(text: user?.name);
    final userC = TextEditingController(text: user?.username);
    final passC = TextEditingController(text: user?.password);
    
    // Permission States
    bool pDelete = user?.canDeleteBill ?? false;
    bool pEdit = user?.canEditBill ?? false;         
    bool pRate = user?.canViewPurchaseRate ?? false;
    bool pFinance = user?.canViewFinance ?? false;
    bool pExport = user?.canExportData ?? false;
    bool pMaintenance = user?.canRunMaintenance ?? false; 

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(user == null ? "Create Staff Access" : "Edit Staff Rights", 
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildInput(nameC, "Staff Full Name", Icons.person_outline),
                  _buildInput(userC, "Login Username", Icons.alternate_email),
                  _buildInput(passC, "Login Password", Icons.lock_open_rounded),
                  const Divider(height: 30),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text("CONTROL PERMISSIONS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
                  ),
                  const SizedBox(height: 10),
                  _buildToggle("Can Delete Bills", pDelete, (v) => setDialogState(() => pDelete = v)),
                  _buildToggle("Can Edit / Modify Bills", pEdit, (v) => setDialogState(() => pEdit = v)),
                  _buildToggle("Can View Purchase Rate", pRate, (v) => setDialogState(() => pRate = v)),
                  _buildToggle("Can View Finance Hub", pFinance, (v) => setDialogState(() => pFinance = v)),
                  _buildToggle("Can Export/Backup Data", pExport, (v) => setDialogState(() => pExport = v)),
                  _buildToggle("Can Run Maintenance", pMaintenance, (v) => setDialogState(() => pMaintenance = v)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              onPressed: () {
                if (userC.text.isEmpty || passC.text.isEmpty) return;

                final newUser = SystemUser(
                  id: user?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameC.text.toUpperCase(),
                  username: userC.text.trim().toLowerCase(),
                  password: passC.text,
                  canDeleteBill: pDelete,
                  canEditBill: pEdit,
                  canViewPurchaseRate: pRate,
                  canViewFinance: pFinance,
                  canExportData: pExport,
                  canRunMaintenance: pMaintenance,
                );

                if (user == null) ph.addSystemUser(newUser);
                else ph.updateSystemUser(newUser);

                Navigator.pop(c);
              },
              child: const Text("SAVE STAFF LOGIN"),
            )
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    // Only Admin can access this
    if (ph.loggedInStaff != null) {
      return const Scaffold(body: Center(child: Text("ACCESS DENIED: ADMIN ONLY")));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Staff Management & Security"),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
      ),
      body: ph.systemUsers.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(15),
              itemCount: ph.systemUsers.length,
              itemBuilder: (c, i) {
                final u = ph.systemUsers[i];
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: ExpansionTile(
                    leading: const CircleAvatar(backgroundColor: Colors.indigo, child: Icon(Icons.person, color: Colors.white)),
                    title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Text("User ID: ${u.username}"),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(15),
                        child: Column(
                          children: [
                            _permissionRow("Delete Bill", u.canDeleteBill),
                            _permissionRow("Edit Bill", u.canEditBill),
                            _permissionRow("Purchase Rate", u.canViewPurchaseRate),
                            _permissionRow("Finance Hub", u.canViewFinance),
                            _permissionRow("Export Tool", u.canExportData),
                            _permissionRow("Maintenance", u.canRunMaintenance),
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(onPressed: () => _showUserForm(user: u), icon: const Icon(Icons.edit, size: 16), label: const Text("Edit Rights")),
                                TextButton.icon(onPressed: () => ph.deleteSystemUser(u.id), icon: const Icon(Icons.delete, color: Colors.red, size: 16), label: const Text("Remove", style: TextStyle(color: Colors.red))),
                              ],
                            )
                          ],
                        ),
                      )
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUserForm(),
        backgroundColor: Colors.indigo.shade900,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text("ADD STAFF LOGIN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // --- UI HELPERS ---
  Widget _buildInput(TextEditingController ctrl, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 20), border: const OutlineInputBorder()),
      ),
    );
  }

  Widget _buildToggle(String label, bool val, Function(bool) onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      value: val,
      activeColor: Colors.green,
      onChanged: onChanged,
    );
  }

  Widget _permissionRow(String label, bool isGranted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Icon(isGranted ? Icons.check_circle : Icons.cancel, color: isGranted ? Colors.green : Colors.red, size: 16),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 15),
          const Text("No staff members added yet.", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
