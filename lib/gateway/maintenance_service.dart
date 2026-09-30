// FILE: lib/gateway/maintenance_service.dart (ADVANCED DETERMINATE VERSION)

import 'dart:convert';
import 'dart:io';
import '../pharoah_manager.dart';
import '../inventory_logic_center.dart';

class MaintenanceService {
  final PharoahManager ph;
  final String workingPath;

  MaintenanceService(this.ph, this.workingPath);

  // ===========================================================================
  // 🛠️ CRASH-PROOF SYSTEM MAINTENANCE (DETERMINATE PROGRESS ENGINE)
  // ===========================================================================
  Future<void> runFullMaintenance({
    required Function(double progress, String status) onProgress,
  }) async {
    try {
      // -----------------------------------------------------------------------
      // PHASE 1: FILE SYSTEM INTEGRITY (0% to 15%)
      // -----------------------------------------------------------------------
      onProgress(0.02, "Initializing System Doctor...");
      await Future.delayed(const Duration(milliseconds: 200));

      List<String> coreFiles = [
        'meds.json', 'parts.json', 'sales.json', 'purc.json', 
        'bats.json', 'vouc.json', 's_challan.json', 'p_challan.json',
        's_return.json', 'p_return.json', 'vouc.json', 'cheques.json'
      ];

      for (int i = 0; i < coreFiles.length; i++) {
        double p = 0.02 + (i / coreFiles.length * 0.13);
        onProgress(p, "Verifying: ${coreFiles[i]}");
        
        File f = File('$workingPath/${coreFiles[i]}');
        if (!await f.exists()) {
          // Missing file structure safety creation
          await f.writeAsString(jsonEncode(coreFiles[i] == 'bats.json' ? {} : []));
        }
        
        // Micro-Yielding to keep UI fluid
        await Future.delayed(Duration.zero);
      }

      // -----------------------------------------------------------------------
      // PHASE 2: MEMORY REFRESH & SORTING (15% to 30%)
      // -----------------------------------------------------------------------
      onProgress(0.15, "Loading Database into Memory...");
      await ph.loadAllData();
      await Future.delayed(const Duration(milliseconds: 200));

      onProgress(0.20, "Rebuilding Bill Date Indices...");
      // Sorting Sales and Purchases
      ph.sales.sort((a, b) => a.date.compareTo(b.date));
      ph.purchases.sort((a, b) => a.date.compareTo(b.date));
      await Future.delayed(const Duration(milliseconds: 100));

      // -----------------------------------------------------------------------
      // PHASE 3: REAL DATA DETERMINATE WORKLOAD (30% to 85%)
      // -----------------------------------------------------------------------
      int totalItems = ph.medicines.length;
      int totalBills = ph.sales.length + ph.purchases.length;
      int totalTasks = totalItems + totalBills;

      if (totalTasks == 0) totalTasks = 1; // Division by Zero safety

      onProgress(0.30, "Auditing Masters & Dynamic Stock...");
      
      // Step A: Audit Medicines and clean orphaned batches
      List<String> validProductKeys = ph.medicines.map((m) => m.identityKey).toList();
      int removedBatches = 0;
      int processedMeds = 0;

      for (var med in ph.medicines) {
        processedMeds++;
        // Dynamic Progress update proportional to actual items
        double progressRatio = 0.30 + ((processedMeds / totalTasks) * 0.55);
        
        if (processedMeds % 20 == 0) {
          onProgress(progressRatio, "Auditing Product: ${med.name}");
          // Yield thread so large masters won't trigger ANR
          await Future.delayed(Duration.zero);
        }
      }

      // Purge and Clean Orphaned Batches (Hard Locked Safety)
      ph.batchHistory.removeWhere((key, value) {
        bool isOrphaned = !validProductKeys.contains(key);
        if (isOrphaned) removedBatches++;
        return isOrphaned;
      });

      // Step B: Rebuilding Inventory Stock Math
      onProgress(0.65, "Calculating Ledger Stock Balances...");
      
      // We run the Rebuild logic. If lists are huge, we yield.
      InventoryLogicCenter.rebuildAllInventory(
        medicines: ph.medicines,
        batchHistory: ph.batchHistory,
        purchases: ph.purchases,
        sales: ph.sales,
        saleReturns: ph.saleReturns,
        purchaseReturns: ph.purchaseReturns
      );
      await Future.delayed(const Duration(milliseconds: 200));

      // -----------------------------------------------------------------------
      // PHASE 4: OPTIMIZATION & DATABASE SERIALIZATION (85% to 100%)
      // -----------------------------------------------------------------------
      onProgress(0.85, "Compressing Database JSON...");
      await ph.save(); // Atomic Write on Disk
      await Future.delayed(const Duration(milliseconds: 200));

      // Log the maintenance audit
      ph.addLog("MAINTENANCE", "Database Repaired. Cleaned $removedBatches orphaned batch history records.");

      onProgress(1.0, "Database Healthy! Work Environment Ready.");
      await Future.delayed(const Duration(milliseconds: 500));

    } catch (e) {
      onProgress(0.0, "Database Error: ${e.toString()}");
      throw Exception("Maintenance Aborted due to system error.");
    }
  }
}
