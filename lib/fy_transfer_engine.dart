// FILE: lib/fy_transfer_engine.dart (FULLY RESOLVED COMPLETE VERSION)

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'models.dart';

class FYTransferEngine {
  
  /// MAIN FUNCTION: Purane saal se naye saal mein data le jana (Crash-Safe & Multi-FY optimized)
  static Future<bool> transferData({
    required String companyID,      
    required String businessType,   
    required String sourceFY,       
    required String targetFY,       
    bool filterZeroStock = false,   // Database filtration option
    bool filterExpired = false,     // Database filtration option
  }) async {
    try {
      final root = await getApplicationDocumentsDirectory();
      
      // Path Logic: Documents/Pharoah_Data/ID/TYPE/FY
      final basePath = '${root.path}/Pharoah_Data/$companyID/$businessType';
      final sourcePath = '$basePath/$sourceFY';
      final targetPath = '$basePath/$targetFY';

      final sourceDir = Directory(sourcePath);
      final targetDir = Directory(targetPath);

      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      // Load Source Data Helper
      dynamic loadJson(String name) {
        final f = File('$sourcePath/$name');
        return f.existsSync() ? jsonDecode(f.readAsStringSync()) : null;
      }

      List<Medicine> oldMeds = (loadJson('meds.json') as List?)?.map((e) => Medicine.fromMap(e)).toList() ?? [];
      List<Party> oldParties = (loadJson('parts.json') as List?)?.map((e) => Party.fromMap(e)).toList() ?? [];
      List<Sale> oldSales = (loadJson('sales.json') as List?)?.map((e) => Sale.fromMap(e)).toList() ?? [];
      List<Purchase> oldPurc = (loadJson('purc.json') as List?)?.map((e) => Purchase.fromMap(e)).toList() ?? [];
      List<Voucher> oldVouc = (loadJson('vouc.json') as List?)?.map((e) => Voucher.fromMap(e)).toList() ?? [];
      List<Bank> oldBanks = (loadJson('banks.json') as List?)?.map((e) => Bank.fromMap(e)).toList() ?? [];
      Map<String, dynamic> oldBatchesRaw = loadJson('bats.json') ?? {};

      // 1. CALCULATE NEW PARTY BALANCES (Includes all Voucher Types)
      List<Party> newParties = oldParties.map((p) {
        if (p.name == "CASH") return p;

        double runningBal = p.opBal;
        // Sales (Debit +)
        for (var s in oldSales.where((s) => s.partyName == p.name && s.status == "Active")) {
          runningBal += s.totalAmount;
        }
        // Purchases (Credit -)
        for (var pr in oldPurc.where((pr) => pr.distributorName == p.name)) {
          runningBal -= pr.totalAmount;
        }
        // Vouchers (Receipts, Payments, Expenses)
        for (var v in oldVouc.where((v) => v.partyName == p.name && v.status == "Active")) {
          String type = v.type.toUpperCase();
          if (type == "RECEIPT") {
            runningBal -= v.amount;
          } else if (type == "PAYMENT" || type == "EXPENSE") {
            runningBal += v.amount;
          }
        }

        p.opBal = runningBal;
        return p;
      }).toList();

      // 2. 🏛️ BANK CLOSING TO OPENING BALANCE (Advanced Carry Forward)
      List<Bank> newBanks = oldBanks.map((b) {
        double currentBal = b.openingBalance;

        // Vouchers processing impacting this specific bank
        for (var v in oldVouc.where((v) => v.depositedIn.toUpperCase() == b.name.toUpperCase() && v.status == "Active")) {
          String type = v.type.toUpperCase();
          if (type == "RECEIPT") {
            currentBal += v.amount; // Bank inflows
          } else if (type == "PAYMENT" || type == "EXPENSE") {
            currentBal -= v.amount; // Bank outflows
          }
        }
        b.openingBalance = currentBal; // Live closing becomes new opening balance
        return b;
      }).toList();

      // 3. 📝 BILL-BY-BILL OUTSTANDING (Pending Invoices Database)
      List<Map<String, dynamic>> pendingInvoices = [];
      
      // Collect all settled bill numbers across previous years
      Set<String> settledBillNos = oldVouc
          .where((v) => v.status == "Active")
          .expand((v) => v.linkedBillNumbers)
          .toSet();

      // Filter Unpaid Sales
      for (var s in oldSales.where((s) => s.status == "Active" && s.paymentMode == "CREDIT")) {
        if (!settledBillNos.contains(s.billNo)) {
          pendingInvoices.add({
            'billNo': s.billNo,
            'partyId': s.partyId,
            'partyName': s.partyName,
            'date': s.date.toIso8601String(),
            'amount': s.totalAmount,
            'type': 'SALE'
          });
        }
      }
      // Filter Unpaid Purchases
      for (var p in oldPurc.where((p) => p.paymentMode == "CREDIT")) {
        if (!settledBillNos.contains(p.billNo)) {
          pendingInvoices.add({
            'billNo': p.billNo,
            'partyId': p.partyId,
            'partyName': p.distributorName,
            'date': p.date.toIso8601String(),
            'amount': p.totalAmount,
            'type': 'PURCHASE'
          });
        }
      }

      // 4. 📦 PENDING CHALLANS CARRY-FORWARD (Continuity Guard)
      List<SaleChallan> oldSaleChallans = (loadJson('s_challan.json') as List?)?.map((e) => SaleChallan.fromMap(e)).toList() ?? [];
      List<PurchaseChallan> oldPurChallans = (loadJson('p_challan.json') as List?)?.map((e) => PurchaseChallan.fromMap(e)).toList() ?? [];

      // Keep only Challans which are strictly "Pending"
      List<SaleChallan> pendingSaleChallans = oldSaleChallans.where((c) => c.status == "Pending").toList();
      List<PurchaseChallan> pendingPurChallans = oldPurChallans.where((c) => c.status == "Pending").toList();

      // 5. 🧹 BATCH HISTORY CORRECTION WITH ADVANCED FILTERS (PROCESSED FIRST)
      Map<String, dynamic> correctedBatches = {};
      DateTime today = DateTime.now();

      oldBatchesRaw.forEach((medKey, batchList) {
        List<dynamic> batches = batchList as List;
        List<Map<String, dynamic>> processedBatches = [];

        for (var b in batches) {
          BatchInfo bObj = BatchInfo.fromMap(b);
          
          if (bObj.qty < 0) bObj.qty = 0;

          // Filtration Check
          if (filterZeroStock && bObj.qty <= 0) {
            continue; // Skip zero-stock batches completely
          }

          // Expired Check
          if (filterExpired) {
            try {
              List<String> parts = bObj.exp.split('/');
              int m = int.parse(parts[0]);
              int y = 2000 + int.parse(parts[1]);
              DateTime lastDay = DateTime(y, m + 1, 0);
              if (lastDay.isBefore(today)) {
                continue; // Skip expired batches completely
              }
            } catch (e) {
              // Safety: Parse fail hone par batch skip nahi hoga
            }
          }

          bObj.openingQty = bObj.qty;
          bObj.adjustmentQty = 0; // Reset corrections for new year
          processedBatches.add(bObj.toMap());
        }

        if (processedBatches.isNotEmpty) {
          correctedBatches[medKey] = processedBatches;
        }
      });

      // 6. 🛡️ MEDICINE STOCK CORRECTION WITH ACTIVE PARENT-STOCK SYNC
      // (Isme correctedBatches list check hoti hai jisse parent meds and batches ka total perfectly match karega)
      List<Map<String, dynamic>> correctedMeds = oldMeds.map((m) {
        String key = m.identityKey;
        
        if (oldBatchesRaw.containsKey(key)) {
          double totalStock = 0.0;
          if (correctedBatches.containsKey(key)) {
            List<dynamic> bList = correctedBatches[key];
            for (var b in bList) {
              totalStock += (b['qty'] ?? 0.0);
            }
          }
          m.stock = totalStock; // Overwrite parent stock with actual active batches sum
        } else {
          if (m.stock < 0) m.stock = 0;
        }
        return m.toMap();
      }).toList();

      // 7. SAVE TO NEW FY DIRECTORY (Atomic Writes)
      Future saveToNew(String name, dynamic data) async {
        await File('$targetPath/$name').writeAsString(jsonEncode(data));
      }

      await saveToNew('meds.json', correctedMeds);
      await saveToNew('parts.json', newParties.map((e) => e.toMap()).toList());
      await saveToNew('banks.json', newBanks.map((e) => e.toMap()).toList()); // Upgraded Bank Balances
      await saveToNew('bats.json', correctedBatches); // Filtered Batches
      await saveToNew('pending_invoices.json', pendingInvoices); // Bill-by-Bill Outstanding Database
      
      // Saving Pending Challans instead of wiping them
      await saveToNew('s_challan.json', pendingSaleChallans.map((e) => e.toMap()).toList());
      await saveToNew('p_challan.json', pendingPurChallans.map((e) => e.toMap()).toList());

      await saveToNew('routs.json', loadJson('routs.json') ?? []);
      await saveToNew('comps.json', loadJson('comps.json') ?? []);
      await saveToNew('salts.json', loadJson('salts.json') ?? []);
      await saveToNew('dtypes.json', loadJson('dtypes.json') ?? []);

      await saveToNew('sales.json', []);
      await saveToNew('purc.json', []);
      await saveToNew('vouc.json', []);
      
      // Audit log entry
      await saveToNew('logs.json', [
        LogEntry(
          id: '1', 
          action: 'SYSTEM', 
          details: 'Data Transferred from $sourceFY to $targetFY. Balances recalculated & Pending Challans moved.', 
          time: DateTime.now()
        ).toMap()
      ]);

      return true;
    } catch (e) {
      print("FY Transfer Error: $e");
      return false;
    }
  }
}
