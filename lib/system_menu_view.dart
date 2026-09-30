import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'audit_logs_view.dart';
import 'file_management_view.dart';
import 'user_master_view.dart';
import 'pharoah_manager.dart';
import 'widgets.dart';
import 'app_date_logic.dart'; // NAYA: Date Master Connection

class SystemMenuView extends StatelessWidget {
  final VoidCallback onLogout;
  const SystemMenuView({super.key, required this.onLogout});

// FILE: lib/system_menu_view.dart

  // ===========================================================================
  // 🚀 SMART FY TRANSFER ENGINE (WITH CHALLAN WATCHDOG)
  // ===========================================================================
  void _handleFYTransfer(BuildContext context, PharoahManager ph) {
    String current = ph.currentFY;
    
    // 1. AUTO-CALCULATE NEXT YEAR (e.g. 2024-25 -> 2025-26)
    int startYear = int.parse(current.split('-')[0]);
    if (startYear < 2000) startYear += 2000;
    String nextFY = "${startYear + 1}-${(startYear + 2).toString().substring(2)}";

    // 2. CHECK FOR PENDING CHALLANS
    final pendingChallans = ph.saleChallans.where((c) => c.status == "Pending").toList();

    if (pendingChallans.isNotEmpty) {
      // --- ALERT: PENDING CHALLANS DETECTED ---
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [Icon(Icons.warning_amber_rounded, color: Colors.red), SizedBox(width: 10), Text("Pending Challans!")]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Naye saal mein jaane se pehle in challans ko check karein. Inka bill abhi tak nahi bana hai:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              SizedBox(
                height: 150, width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: pendingChallans.length,
                  itemBuilder: (context, i) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.circle, size: 8, color: Colors.red),
                    title: Text(pendingChallans[i].partyName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    subtitle: Text("Challan: ${pendingChallans[i].billNo} | ₹${pendingChallans[i].totalAmount.toStringAsFixed(0)}", style: const TextStyle(fontSize: 9)),
                  ),
                ),
              ),
              const Divider(),
              const Text("Note: Transfer ke baad ye challans purane saal mein hi reh jayenge.", style: TextStyle(fontSize: 10, color: Colors.blueGrey, fontStyle: FontStyle.italic)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("GO BACK & FIX")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade900),
              onPressed: () { Navigator.pop(c); _showFinalConfirmation(context, ph, nextFY); }, 
              child: const Text("IGNORE & CONTINUE")
            ),
          ],
        ),
      );
    } else {
      // No pending challans, go straight to confirmation
      _showFinalConfirmation(context, ph, nextFY);
    }
  }

  // --- SUB-DIALOG: FINAL FY CONFIRMATION ---
  void _showFinalConfirmation(BuildContext context, PharoahManager ph, String nextFY) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text("Confirm New Year: $nextFY"),
        content: const Text("System will now:\n1. Copy Item & Party Master.\n2. Carry forward Ledger Balances.\n3. Transfer Closing Stock as Opening Stock.\n\nTransactions (Bills/Vouchers) will start from Zero."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade900),
            onPressed: () async {
              Navigator.pop(c);
              showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));
              
              bool success = await ph.startNewFinancialYear(nextFY);
              
              if (context.mounted) {
                Navigator.pop(context); // Close Loader
                if (success) _showSuccessDialog(context, nextFY);
                else ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Transfer Error!")));
              }
            },
            child: Text("START $nextFY NOW", style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(BuildContext context, String nextFY) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text("Transfer Successful!"),
        content: Text("Ab aap $nextFY ke Financial Year mein hain. Saara stock aur balance naye saal mein aa gaya hai."),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst), 
            child: const Text("GO TO DASHBOARD")
          )
        ],
      ),
    );
  }

  // --- MASTER RESET LOGIC ---
  void _startResetProcess(BuildContext context) {
    final List<Map<String, String>> steps = [
      {"t": "Step 1/7", "m": "Kya aap vastav me sara data delete karna chahte hain?", "b": "CONTINUE"},
      {"t": "Step 7/7", "m": "Ok, ye aakhri mauka hai. Tap 'WIPE NOW' to format database.", "b": "WIPE EVERYTHING NOW"},
    ];
    _showVerificationStep(context, steps, 0);
  }

  void _showVerificationStep(BuildContext context, List<Map<String, String>> steps, int index) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text(steps[index]['t']!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: Text(steps[index]['m']!),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(c);
              if (index < steps.length - 1) _showVerificationStep(context, steps, index + 1);
              else _performMasterReset(context);
            },
            child: Text(steps[index]['b']!, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _performMasterReset(BuildContext context) async {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    await ph.masterReset();
    if (context.mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(title: const Text("System Administration"), backgroundColor: Colors.blue.shade900, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("MAINTENANCE & YEAR-END TOOLS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1)),
          const SizedBox(height: 15),
          
          InkWell(
            onTap: () => _handleFYTransfer(context, ph),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.blue.shade900, Colors.blue.shade700]),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Row(children: [
                Icon(Icons.rocket_launch, color: Colors.white, size: 30),
                SizedBox(width: 15),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("START NEXT FINANCIAL YEAR", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  Text("Carry forward Stock & Balances automatic", style: TextStyle(color: Colors.white70, fontSize: 11)),
                ])),
                Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
              ]),
            ),
          ),
          
          const SizedBox(height: 25),

          GridView.count(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.85,
            children: [
              ActionIconBtn(title: "Company", icon: Icons.business_rounded, color: Colors.indigo, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => UserMasterView(onLogout: onLogout)))),
              ActionIconBtn(title: "Audit Logs", icon: Icons.history_edu_rounded, color: Colors.brown, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AuditLogsView()))),
              ActionIconBtn(title: "Backup", icon: Icons.cloud_done_rounded, color: Colors.blueGrey, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const FileManagementView()))),
              ActionIconBtn(title: "Change FY", icon: Icons.calendar_month_rounded, color: Colors.teal, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const FileManagementView()))),
              ActionIconBtn(title: "Admin User", icon: Icons.admin_panel_settings_rounded, color: Colors.deepPurple, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => UserMasterView(onLogout: onLogout)))),
              ActionIconBtn(title: "Reset Data", icon: Icons.delete_forever_rounded, color: Colors.red, onTap: () => _startResetProcess(context)),
            ],
          ),
        ]),
      ),
    );
  }
}
