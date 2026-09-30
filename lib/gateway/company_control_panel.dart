// FILE: lib/gateway/company_control_panel.dart (FULLY RESOLVED CONSOLIDATED VERSION)

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import '../pharoah_manager.dart';
import 'company_registry_model.dart';
import 'maintenance_service.dart';
import 'modify_company_view.dart';
import 'export_service.dart';
import '../app_date_logic.dart'; // Import to calculate smart next financial year

class CompanyControlPanelView extends StatefulWidget {
  const CompanyControlPanelView({super.key});

  @override
  State<CompanyControlPanelView> createState() => _CompanyControlPanelViewState();
}

class _CompanyControlPanelViewState extends State<CompanyControlPanelView> {
  bool isMaintenanceRunning = false;
  String maintenanceStatus = "";
  double maintenanceProgress = 0.0;

  // --- 🛡️ NAYA: REPORT CARD STATE VARIABLES ---
  bool isMaintenanceCompleted = false; // Sync finished flag
  String successReportTitle = "";      // Banner Title
  List<String> successReportDetails = []; // Bullet points

  // ===========================================================================
  // 🏢 1. POPUP: FINANCIAL YEAR SELECTOR
  // ===========================================================================
  void _showFYSelectionDialog(PharoahManager ph, CompanyProfile comp) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Select Financial Year", style: TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: comp.fYears.length,
            itemBuilder: (context, i) {
              String fy = comp.fYears[i];
              return Card(
                elevation: 0,
                color: Colors.blue.shade50,
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const Icon(Icons.calendar_today, color: Colors.blue),
                  title: Text(fy, style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: const Icon(Icons.play_circle_fill, color: Colors.green),
                  onTap: () {
                    Navigator.pop(c);
                    ph.loginToCompany(comp, fy);
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 🛠️ 2. THE FILE MAINTENANCE PROCESS (WITH SILENT LOADING & REPORT CARD)
  // ===========================================================================
  void _runMaintenance(PharoahManager ph) async {
    String latestFY = ph.activeCompany?.fYears.last ?? "";
    if (latestFY.isEmpty) return;

    setState(() {
      isMaintenanceRunning = true;
      isMaintenanceCompleted = false; // Reset completed status
      maintenanceProgress = 0.0;
      maintenanceStatus = "Waking up Database Doctor...";
    });

    try {
      // 1. SILENT LOAD: Bina notify kiye background data reload kiya (No-flashing)
      await ph.loadDataForMaintenanceSilently(latestFY);
      String path = await ph.getWorkingPath();

      final engine = MaintenanceService(ph, path);
      
      // Drive progress in real-time from actual calculated tasks
      await engine.runFullMaintenance(onProgress: (p, s) {
        if (mounted) {
          setState(() {
            maintenanceProgress = p;
            maintenanceStatus = s;
          });
        }
      });

      // 2. SILENT RESET: Bina screen change kiye saal reset kiya
      ph.resetYearSilently();

      // --- 🏛️ NAYA: Audit Report Card Setup ---
      if (mounted) {
        setState(() {
          isMaintenanceCompleted = true; // Show success report card
          successReportTitle = "DATABASE INTEGRITY REPAIR COMPLETE";
          successReportDetails = [
            "• Structural Integrity: Verified & Healthy",
            "• Dynamic Stock Rebuild: Calculated & Synced",
            "• Orphaned Batches: Purged & Cleaned up from disk",
            "• Date & Cache Indices: Optimised successfully",
            "• Atomic Save: Compressed JSON saved on Disk"
          ];
        });
      }

    } catch (e) {
      ph.resetYearSilently();
      if (mounted) {
        setState(() {
          isMaintenanceRunning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error during maintenance: $e"), backgroundColor: Colors.red)
        );
      }
    }
  }

  // ===========================================================================
  // 🏛️ 3. NAYA: PROVISIONAL BALANCE SYNC (CASCADE COMPATIBLE WITH SUCCESS CARD)
  // ===========================================================================
  void _runProvisionalSync(PharoahManager ph, String startYear) async {
    setState(() {
      isMaintenanceRunning = true;
      isMaintenanceCompleted = false; // Reset completed status
      maintenanceProgress = 0.0;
      maintenanceStatus = "Initializing Cascade Sync...";
    });

    try {
      String targetFY = ph.activeCompany!.fYears.last;
      String prevFY = ph.activeCompany!.fYears[ph.activeCompany!.fYears.length - 2];

      // Main sync engine call passing parameters directly on file-level
      bool success = await ph.syncOpeningBalancesFromPreviousYear(
        startYear: startYear,
        onStepProgress: (p, s) {
          if (mounted) {
            setState(() {
              maintenanceProgress = p;
              maintenanceStatus = s;
            });
          }
        }
      );

      // --- 🏛️ NAYA: Sync Report Card Setup ---
      if (success && mounted) {
        setState(() {
          isMaintenanceCompleted = true; // Show success report card
          successReportTitle = "CARRY BALANCES SYNC COMPLETE";
          successReportDetails = [
            "• Ledger Balances: Re-calculated & Synced successfully",
            "• Bank Accounts: Cash flow closing balances carried forward",
            "• Missing Masters: Missing parties & items delta imported",
            "• Pending Challans: Transferred smoothly to naye saal",
            "• Current Year Data: 100% Untouched and Safe"
          ];
        });
      } else if (mounted) {
        setState(() {
          isMaintenanceRunning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ Sync Failed! Please check year folders."), backgroundColor: Colors.red)
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isMaintenanceRunning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Sync Error: $e"), backgroundColor: Colors.red)
        );
      }
    }
  }

  // ===========================================================================
  // 🚀 4. NEW FINANCIAL YEAR SETUP (WITH WARNING CHECKLIST & AUTO-FILL)
  // ===========================================================================
  void _showNewYearDialog(PharoahManager ph) {
    // A. AUTO-FILL LOGIC: automatically pre-fills next logical year
    String lastFY = ph.activeCompany!.fYears.last;
    String suggestedNextFY = AppDateLogic.getNextFYString(lastFY);
    final fyC = TextEditingController(text: suggestedNextFY);

    // B. CHECKLIST WATCHDOG: scans for unbilled pending challans
    final pendingChallans = ph.saleChallans.where((c) => c.status == "Pending").toList();

    // Checkbox Local States
    bool skipZeroStock = false;
    bool skipExpired = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder( // StatefulBuilder lagaya taaki checkboxes tick ho sakein
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text("Setup New Financial Year"),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Checklist Warning Box
                    if (pendingChallans.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50, 
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200)
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Warning: ${pendingChallans.length} Pending Challans Found!", 
                                    style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)
                                  ),
                                  const SizedBox(height: 3),
                                  const Text(
                                    "Unbilled stocks cannot be carried forward properly. Please bill them or ignore to proceed.", 
                                    style: TextStyle(fontSize: 9, color: Colors.black87)
                                  ),
                                ],
                              )
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 15),
                    ],
                    
                    const Text("Enter target Financial Year name:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: fyC, 
                      decoration: const InputDecoration(
                        labelText: "Target FY (MM/YY format)", 
                        border: OutlineInputBorder(), 
                        hintText: "e.g. 2026-27"
                      )
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const Text("DATABASE OPTIMIZATION FILTERS (MARG STYLE)", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
                    const SizedBox(height: 8),

                    // Checkbox 1: Zero Stock Filter
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      activeColor: Colors.purple,
                      title: const Text("Skip Zero-Stock Batches", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      subtitle: const Text("Dead stock will not be copied (Lightweight DB)", style: TextStyle(fontSize: 9)),
                      value: skipZeroStock, 
                      onChanged: (v) => setDialogState(() => skipZeroStock = v!),
                    ),

                    // Checkbox 2: Expired Stock Filter
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      activeColor: Colors.purple,
                      title: const Text("Skip Expired Batches", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      subtitle: const Text("Expired items will not be transfered", style: TextStyle(fontSize: 9)),
                      value: skipExpired, 
                      onChanged: (v) => setDialogState(() => skipExpired = v!),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL", style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
                onPressed: () async {
                  if (fyC.text.isEmpty) return;
                  Navigator.pop(c); // Close Dialog
                  
                  // Trigger Immersive Progress Screen for transfer
                  setState(() {
                    isMaintenanceRunning = true;
                    isMaintenanceCompleted = false;
                    maintenanceStatus = "Transferring Masters, Checking Filters & Closing Balances...";
                    maintenanceProgress = 0.50; // Set half way
                  });

                  bool ok = await ph.startNewFinancialYear(
                    fyC.text.trim(),
                    filterZeroStock: skipZeroStock,
                    filterExpired: skipExpired,
                  );

                  setState(() {
                    isMaintenanceRunning = false;
                  });
                  
                  if (ok && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("✅ New Financial Year environment built!"), backgroundColor: Colors.green)
                    );
                  }
                }, 
                child: const Text("START TRANSFER")
              )
            ],
          );
        }
      ),
    );
  }

  // ===========================================================================
  // 🏢 5. THE IMMERSIVE "SPLASH" PROGRESS & SUCCESS OVERLAY
  // ===========================================================================
  Widget _buildMaintenanceOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.95), // Deeper dim for report contrast
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // --- CASE A: SYSTEM REPORT CARD ---
              if (isMaintenanceCompleted) ...[
                const Icon(Icons.verified_rounded, color: Colors.greenAccent, size: 90),
                const SizedBox(height: 20),
                const Text(
                  "SUCCESS!", 
                  style: TextStyle(color: Colors.greenAccent, fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 2)
                ),
                const SizedBox(height: 10),
                Text(
                  successReportTitle, 
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1)
                ),
                const SizedBox(height: 25),
                
                // Report details container
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white10)
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: successReportDetails.map((detail) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        detail,
                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)
                      ),
                    )).toList(),
                  ),
                ),
                const SizedBox(height: 40),

                // Prominent Manual Dismiss Button
                SizedBox(
                  width: 200, height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green, // Fixed truncation to green
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25))
                    ),
                    onPressed: () {
                      setState(() {
                        isMaintenanceRunning = false;
                        isMaintenanceCompleted = false;
                      });
                    },
                    icon: const Icon(Icons.done_all_rounded),
                    label: const Text("FINISH & RETURN", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                )
              ]
              
              // --- CASE B: DYNAMIC PROGRESS CURTAIN ---
              else ...[
                const Icon(Icons.health_and_safety_outlined, color: Colors.orange, size: 85),
                const SizedBox(height: 30),
                Text(
                  "${(maintenanceProgress * 100).toInt()}%",
                  style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                const SizedBox(height: 15),
                SizedBox(
                  width: 240,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: maintenanceProgress,
                      color: Colors.orange,
                      backgroundColor: Colors.white10,
                      minHeight: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 25),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    maintenanceStatus.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                  ),
                ),
                const SizedBox(height: 60),
                const Text(
                  "DO NOT CLOSE OR MINIMIZE APP",
                  style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 🏛️ 6. NAYA: PROVISIONAL SYNC BANNER WIDGET (MARG STYLE - CASCADE UPGRADE)
  // ===========================================================================
  Widget _buildProvisionalSyncBanner(PharoahManager ph) {
    // Current year ke piche ke saare saal select karne ka list
    List<String> sourceYears = ph.activeCompany!.fYears.sublist(0, ph.activeCompany!.fYears.length - 1);
    String selectedSourceYear = sourceYears.last; // Default to immediate previous year

    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (c) => StatefulBuilder( // StatefulBuilder for dropdown updates
            builder: (context, setDialogState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const Row(children: [Icon(Icons.sync_alt_rounded, color: Colors.teal), SizedBox(width: 10), Text("Carry Balances")]),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "This will recalculate all closing ledger & stock balances from your chosen year, and cascade them forward to all subsequent years automatically.",
                      style: TextStyle(fontSize: 12)
                    ),
                    const SizedBox(height: 15),
                    const Text("Select starting year of modification:", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedSourceYear,
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                      items: sourceYears.map((y) => DropdownMenuItem(value: y, child: Text(y))).toList(),
                      onChanged: (v) => setDialogState(() => selectedSourceYear = v!),
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      "Your active transactions in all years will remain 100% safe & untouched.",
                      style: TextStyle(fontSize: 10, color: Colors.blueGrey, fontStyle: FontStyle.italic)
                    ),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL", style: TextStyle(color: Colors.grey))),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                    onPressed: () {
                      Navigator.pop(c);
                      _runProvisionalSync(ph, selectedSourceYear); // Pass the selected source year
                    },
                    child: const Text("START CASCADE SYNC"),
                  )
                ],
              );
            }
          )
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00796B), Color(0xFF004D40)], // Premium Teal gradient
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.teal.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
              child: const Icon(Icons.sync_alt_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 15),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("CARRY BALANCES (PROVISIONAL)", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  SizedBox(height: 3),
                  Text("Sync opening balances & stock from previous years", style: TextStyle(color: Colors.white70, fontSize: 10)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 7. MAIN SCREEN BUILDER
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final comp = ph.activeCompany;
    if (comp == null) return const Scaffold(body: Center(child: Text("Error: No active company")));

    bool isAdmin = ph.loggedInStaff == null;
    bool canMaintain = isAdmin || (ph.loggedInStaff?.canRunMaintenance ?? false);
    bool canExport = isAdmin || (ph.loggedInStaff?.canExportData ?? false);

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Text(comp.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        leading: IconButton(icon: const Icon(Icons.logout), onPressed: () => ph.clearSession()),
      ),
      body: Stack( // Wrapped with Stack to overlay the Progress Curtain
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildHeaderCard(comp, isAdmin),
                const SizedBox(height: 25),

                // --- 🏛️ NAYA: CONDITIONAL PROVISIONAL SYNC BANNER (MARG STYLE) ---
                if (comp.fYears.length > 1) ...[
                  _buildProvisionalSyncBanner(ph),
                  const SizedBox(height: 20),
                ],

                GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 1.1,
                  ),
                  children: [
                    _menuItem("LOGIN TO WORK", Icons.play_circle_fill_rounded, Colors.green, () => _showFYSelectionDialog(ph, comp)),
                    if (canMaintain)
                      _menuItem("FILE MAINTENANCE", Icons.health_and_safety_rounded, Colors.orange.shade800, () => _runMaintenance(ph)),
                    if (canExport)
                      _menuItem("BACKUP & EXPORT", Icons.cloud_upload_rounded, Colors.blue, () => ExportService(ph).exportEntireCompany(comp)),
                    if (isAdmin)
                      _menuItem("NEW YEAR SETUP", Icons.fiber_new_rounded, Colors.purple, () => _showNewYearDialog(ph)),
                    if (isAdmin)
                      _menuItem("MODIFY COMPANY", Icons.settings_applications_rounded, Colors.blueGrey, () => Navigator.push(context, MaterialPageRoute(builder: (c) => ModifyCompanyView(comp: comp)))),
                    if (isAdmin)
                      _menuItem("DELETE COMPANY", Icons.delete_forever_rounded, Colors.red, () => _confirmDelete(ph)),
                  ],
                ),
              ],
            ),
          ),
          
          // --- THE IMMERSIVE "CURTAIN" PROGRESS OVERLAY ---
          if (isMaintenanceRunning) 
            _buildMaintenanceOverlay(),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(CompanyProfile comp, bool isAdmin) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: Row(children: [
          const CircleAvatar(radius: 30, backgroundColor: Color(0xFFF0F2F5), child: Icon(Icons.business_rounded, size: 30, color: Color(0xFF0D47A1))),
          const SizedBox(width: 15),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(comp.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0D47A1))),
            Text("Business Type: ${comp.businessType}", style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
          ]))
      ]),
    );
  }

  Widget _menuItem(String title, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap, 
      borderRadius: BorderRadius.circular(20), 
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(20), 
          border: Border.all(color: color.withOpacity(0.1), width: 2)
        ), 
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, 
          children: [
            Icon(icon, color: color, size: 40), 
            const SizedBox(height: 12), 
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))
          ]
        )
      )
    );
  }

  void _confirmDelete(PharoahManager ph) {
    int clickCount = 0;
    showDialog(context: context, builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text("PERMANENT DELETE"),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text("Warning: All data folders will be wiped permanently.", style: TextStyle(fontSize: 12, color: Colors.red)),
                const SizedBox(height: 15),
                Text("Confirm deletion: $clickCount/15"),
                LinearProgressIndicator(value: clickCount/15),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("STOP")),
              ElevatedButton(onPressed: () async {
                setDialogState(() => clickCount++);
                if (clickCount >= 15) {
                  final root = await getApplicationDocumentsDirectory();
                  final dir = Directory('${root.path}/Pharoah_Data/${ph.activeCompany!.id}');
                  if (await dir.exists()) await dir.delete(recursive: true);
                  ph.companiesRegistry.removeWhere((x) => x.id == ph.activeCompany!.id);
                  await ph.saveRegistry();
                  ph.clearSession();
                  if (context.mounted) Navigator.pop(context);
                }
              }, child: const Text("YES, DELETE")),
            ],
          );
        });
    });
  }
}
