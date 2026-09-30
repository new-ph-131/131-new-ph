// FILE: lib/web_live_sync/app_sync_engine.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import 'weblivetoken.dart';
import 'web_cloud_config.dart';

class AppSyncEngine {
  static const List<String> _coreFiles = [
    'meds.json', 'parts.json', 'sales.json', 'purc.json',
    'bats.json', 'vouc.json', 's_challan.json', 'p_challan.json',
    's_return.json', 'p_return.json', 'banks.json', 'config.json',
    'series.json', 'shortage.json', 'routs.json', 'comps.json', 'salts.json'
  ];

  /// 🔄 BULLETPROOF 2-WAY SYNC ENGINE (FULL TRANSACTIONS & PURCHASES DELTA MERGE)
  static Future<bool> pushStoreData(PharoahManager ph) async {
    try {
      if (ph.activeCompany == null || ph.currentFY.isEmpty) return false;
      final workingDir = await ph.getWorkingPath();
      if (workingDir.isEmpty) return false;

      final prefs = await SharedPreferences.getInstance();
      final companyId = ph.activeCompany!.id;
      final storeToken = await WebLiveToken.getOrCreateToken(companyId);

      final String? lastSyncStr = prefs.getString('last_cloud_sync_time');
      final DateTime lastSyncTime = lastSyncStr != null && lastSyncStr.isNotEmpty
          ? DateTime.tryParse(lastSyncStr) ?? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.fromMillisecondsSinceEpoch(0);

      // Track set of known imported web IDs
      final String syncHistoryKey = 'all_imported_web_sales_$companyId';
      final Set<String> importedHistory = (prefs.getStringList(syncHistoryKey) ?? []).toSet();

      // Current IDs in App
      final Set<String> currentAppSaleIds = ph.sales.map((s) => s.id).toSet();
      final Set<String> currentAppSaleBillNos = ph.sales.map((s) => s.billNo).toSet();
      final Set<String> currentAppPurIds = ph.purchases.map((p) => p.id).toSet();
      final Set<String> currentAppPurInternalNos = ph.purchases.map((p) => p.internalNo).toSet();
      final Set<String> currentAppVoucIds = ph.vouchers.map((v) => v.id).toSet();
      final Set<String> currentAppSchIds = ph.saleChallans.map((c) => c.id).toSet();
      final Set<String> currentAppPchIds = ph.purchaseChallans.map((c) => c.id).toSet();
      final Set<String> currentAppSrIds = ph.saleReturns.map((r) => r.id).toSet();
      final Set<String> currentAppPrIds = ph.purchaseReturns.map((r) => r.id).toSet();

      // -----------------------------------------------------------------------
      // STEP 1: SMART PULL & DELTA MERGE
      // -----------------------------------------------------------------------
      try {
        final pullUri = Uri.parse(
          "${WebCloudConfig.cloudRelayEndpoint}?action=PULL_STORE_DATA"
          "&storeToken=${Uri.encodeComponent(storeToken)}"
          "&username=${Uri.encodeComponent(ph.activeCompany!.adminUser.toLowerCase())}"
          "&password=${Uri.encodeComponent(ph.activeCompany!.password)}"
        );

        final pullRes = await http.get(pullUri).timeout(const Duration(seconds: 15));
        if (pullRes.statusCode == 200 && !pullRes.body.contains("ERROR")) {
          final Map<String, dynamic> cloudData = jsonDecode(pullRes.body);
          if (cloudData['status'] == 'SUCCESS' && cloudData['files'] != null) {
            final Map<String, dynamic> cloudFiles = cloudData['files'];
            bool hasAnyNewData = false;

            // 1. Merge Web Sales
            if (cloudFiles['sales.json'] != null) {
              List<dynamic> cloudSalesList = jsonDecode(cloudFiles['sales.json'].toString());

              for (var rawSale in cloudSalesList) {
                final saleMap = rawSale as Map<String, dynamic>;
                String sId = saleMap['id'] ?? '';
                String bNo = saleMap['billNo'] ?? '';
                String tag = saleMap['sourceTag'] ?? '';
                bool isWebBill = tag == 'WEB-PORTAL' || sId.startsWith('SALE-WEB');

                if (isWebBill) {
                  if (importedHistory.contains(sId) && !currentAppSaleIds.contains(sId)) {
                    continue; // Skip locally deleted bill
                  }

                  if (!importedHistory.contains(sId) && !currentAppSaleIds.contains(sId)) {
                    int? billEpoch;
                    if (sId.startsWith('SALE-WEB-')) {
                      billEpoch = int.tryParse(sId.replaceFirst('SALE-WEB-', ''));
                    }
                    if (billEpoch != null && lastSyncTime.millisecondsSinceEpoch > 0) {
                      DateTime billCreatedAt = DateTime.fromMillisecondsSinceEpoch(billEpoch);
                      if (billCreatedAt.isBefore(lastSyncTime)) {
                        importedHistory.add(sId);
                        continue;
                      }
                    }

                    if (!currentAppSaleBillNos.contains(bNo)) {
                      ph.sales.add(Sale.fromMap(saleMap));
                      importedHistory.add(sId);
                      currentAppSaleIds.add(sId);
                      currentAppSaleBillNos.add(bNo);
                      hasAnyNewData = true;
                    }
                  } else {
                    importedHistory.add(sId);
                  }
                }
              }
            }

            // 2. 🔥 Merge Web Purchases (Stock Inward)
            if (cloudFiles['purc.json'] != null) {
              List<dynamic> cloudPurList = jsonDecode(cloudFiles['purc.json'].toString());

              for (var rawPur in cloudPurList) {
                final purMap = rawPur as Map<String, dynamic>;
                String pId = purMap['id'] ?? '';
                String intNo = purMap['internalNo'] ?? '';
                String tag = purMap['sourceTag'] ?? '';
                bool isWebPur = tag == 'WEB-PORTAL' || pId.startsWith('PUR-WEB');

                if (isWebPur && !currentAppPurIds.contains(pId) && !currentAppPurInternalNos.contains(intNo)) {
                  ph.purchases.add(Purchase.fromMap(purMap));
                  currentAppPurIds.add(pId);
                  currentAppPurInternalNos.add(intNo);
                  hasAnyNewData = true;
                }
              }
            }

            // 3. Merge Web Vouchers (Receipts / Payments)
            if (cloudFiles['vouc.json'] != null) {
              List<dynamic> cloudVoucList = jsonDecode(cloudFiles['vouc.json'].toString());

              for (var rawVouc in cloudVoucList) {
                final voucMap = rawVouc as Map<String, dynamic>;
                String vId = voucMap['id'] ?? '';
                bool isWebVouc = vId.startsWith('VCT-WEB') || vId.startsWith('PAY-WEB');

                if (isWebVouc && !currentAppVoucIds.contains(vId)) {
                  ph.vouchers.add(Voucher.fromMap(voucMap));
                  currentAppVoucIds.add(vId);
                  hasAnyNewData = true;
                }
              }
            }

            // 4. Merge Web Delivery & Inward Challans
            if (cloudFiles['s_challan.json'] != null) {
              List<dynamic> cloudSchList = jsonDecode(cloudFiles['s_challan.json'].toString());
              for (var rawSch in cloudSchList) {
                final schMap = rawSch as Map<String, dynamic>;
                String scId = schMap['id'] ?? '';
                if (scId.startsWith('SCH-WEB') && !currentAppSchIds.contains(scId)) {
                  ph.saleChallans.add(SaleChallan.fromMap(schMap));
                  currentAppSchIds.add(scId);
                  hasAnyNewData = true;
                }
              }
            }
            if (cloudFiles['p_challan.json'] != null) {
              List<dynamic> cloudPchList = jsonDecode(cloudFiles['p_challan.json'].toString());
              for (var rawPch in cloudPchList) {
                final pchMap = rawPch as Map<String, dynamic>;
                String pcId = pchMap['id'] ?? '';
                if (pcId.startsWith('PCH-WEB') && !currentAppPchIds.contains(pcId)) {
                  ph.purchaseChallans.add(PurchaseChallan.fromMap(pchMap));
                  currentAppPchIds.add(pcId);
                  hasAnyNewData = true;
                }
              }
            }

            // 5. Merge Web Returns (CN / DN)
            if (cloudFiles['s_return.json'] != null) {
              List<dynamic> cloudSrList = jsonDecode(cloudFiles['s_return.json'].toString());
              for (var rawSr in cloudSrList) {
                final srMap = rawSr as Map<String, dynamic>;
                String srId = srMap['id'] ?? '';
                if (srId.startsWith('CN-WEB') && !currentAppSrIds.contains(srId)) {
                  ph.saleReturns.add(SaleReturn.fromMap(srMap));
                  currentAppSrIds.add(srId);
                  hasAnyNewData = true;
                }
              }
            }
            if (cloudFiles['p_return.json'] != null) {
              List<dynamic> cloudPrList = jsonDecode(cloudFiles['p_return.json'].toString());
              for (var rawPr in cloudPrList) {
                final prMap = rawPr as Map<String, dynamic>;
                String prId = prMap['id'] ?? '';
                if (prId.startsWith('DN-WEB') && !currentAppPrIds.contains(prId)) {
                  ph.purchaseReturns.add(PurchaseReturn.fromMap(prMap));
                  currentAppPrIds.add(prId);
                  hasAnyNewData = true;
                }
              }
            }

                                    // 6. Merge Web Parties (STRICT CLEAN GST & NAME DEDUPLICATION)
            if (cloudFiles['parts.json'] != null) {
              List<dynamic> cloudPartsList = jsonDecode(cloudFiles['parts.json'].toString());

              for (var rawPart in cloudPartsList) {
                final partMap = rawPart as Map<String, dynamic>;
                String pName = (partMap['name'] ?? '').toString().toUpperCase().trim();
                String cleanName = pName.replaceAll(RegExp(r'[^A-Z0-9]'), '');
                String pGst = (partMap['gst'] ?? '').toString().toUpperCase().trim();

                if (cleanName.isEmpty) continue;

                int existingIdx = ph.parties.indexWhere((p) {
                  if (pGst.isNotEmpty && pGst != 'N/A' && p.gst.toUpperCase().trim() == pGst) return true;
                  return p.name.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase() == cleanName;
                });

                if (existingIdx != -1) {
                  final oldP = ph.parties[existingIdx];
                  final incoming = Party.fromMap(partMap);
                  ph.parties[existingIdx] = Party(
                    id: oldP.id,
                    name: oldP.name,
                    group: incoming.group,
                    phone: incoming.phone.isNotEmpty ? incoming.phone : oldP.phone,
                    email: incoming.email.isNotEmpty ? incoming.email : oldP.email,
                    address: incoming.address.isNotEmpty ? incoming.address : oldP.address,
                    city: incoming.city.isNotEmpty ? incoming.city : oldP.city,
                    state: incoming.state,
                    gst: incoming.gst.isNotEmpty && incoming.gst != 'N/A' ? incoming.gst : oldP.gst,
                    dl: incoming.dl.isNotEmpty && incoming.dl != 'N/A' ? incoming.dl : oldP.dl,
                    pan: incoming.pan.isNotEmpty ? incoming.pan : oldP.pan,
                    opBal: incoming.opBal != 0.0 ? incoming.opBal : oldP.opBal,
                  );
                } else {
                  ph.parties.add(Party.fromMap(partMap));
                  hasAnyNewData = true;
                }
              }

              // Deduplicate existing list
              Map<String, Party> uniqueP = {};
              for (var p in ph.parties) {
                String k = (p.gst.isNotEmpty && p.gst != 'N/A')
                    ? p.gst.toUpperCase().trim()
                    : p.name.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
                if (!uniqueP.containsKey(k)) uniqueP[k] = p;
              }
              ph.parties = uniqueP.values.toList();
            }

            // 7. Merge Web Products (STRICT CLEAN NAME DEDUPLICATION)
            if (cloudFiles['meds.json'] != null) {
              List<dynamic> cloudMedsList = jsonDecode(cloudFiles['meds.json'].toString());

              for (var rawMed in cloudMedsList) {
                final medMap = rawMed as Map<String, dynamic>;
                String mName = (medMap['name'] ?? '').toString().toUpperCase().trim();
                String cleanName = mName.replaceAll(RegExp(r'[^A-Z0-9]'), '');

                if (cleanName.isEmpty) continue;

                int existingIdx = ph.medicines.indexWhere((m) {
                  return m.name.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase() == cleanName;
                });

                if (existingIdx != -1) {
                  final oldM = ph.medicines[existingIdx];
                  final incoming = Medicine.fromMap(medMap);
                  ph.medicines[existingIdx] = Medicine(
                    id: oldM.id,
                    systemId: oldM.systemId.isNotEmpty ? oldM.systemId : incoming.systemId,
                    name: oldM.name,
                    packing: incoming.packing.isNotEmpty ? incoming.packing : oldM.packing,
                    companyId: incoming.companyId.isNotEmpty ? incoming.companyId : oldM.companyId,
                    saltId: incoming.saltId.isNotEmpty ? incoming.saltId : oldM.saltId,
                    hsnCode: incoming.hsnCode.isNotEmpty ? incoming.hsnCode : oldM.hsnCode,
                    gst: incoming.gst,
                    mrp: incoming.mrp > 0 ? incoming.mrp : oldM.mrp,
                    purRate: incoming.purRate > 0 ? incoming.purRate : oldM.purRate,
                    rateA: incoming.rateA > 0 ? incoming.rateA : oldM.rateA,
                    rateB: incoming.rateB > 0 ? incoming.rateB : oldM.rateB,
                    rateC: incoming.rateC > 0 ? incoming.rateC : oldM.rateC,
                    stock: oldM.stock > 0 ? oldM.stock : incoming.stock,
                    drugForm: incoming.drugForm,
                  );
                } else {
                  ph.medicines.add(Medicine.fromMap(medMap));
                  hasAnyNewData = true;
                }
              }

              // Deduplicate existing list
              Map<String, Medicine> uniqueM = {};
              for (var m in ph.medicines) {
                String k = m.name.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
                if (!uniqueM.containsKey(k)) uniqueM[k] = m;
              }
              ph.medicines = uniqueM.values.toList();
            }
            if (hasAnyNewData) {
              await ph.save();
            }

            await ph.loadAllData();
          }
        }
      } catch (e) {
        debugPrint("Smart pull error: $e");
      }

      // -----------------------------------------------------------------------
      // STEP 2: PUSH CONSOLIDATED LOCAL APP DATABASE TO CLOUD
      // -----------------------------------------------------------------------
      Map<String, String> filesPayload = {};
      for (var name in _coreFiles) {
        final file = File('$workingDir/$name');
        if (await file.exists()) {
          filesPayload[name] = await file.readAsString();
        }
      }

      final payload = {
        "action": WebCloudConfig.actionPushStore,
        "storeToken": storeToken,
        "companyId": ph.activeCompany!.id,
        "companyName": ph.activeCompany!.name,
        "adminUser": ph.activeCompany!.adminUser,
        "adminPassword": ph.activeCompany!.password,
        "fy": ph.currentFY,
        "registryProfile": ph.activeCompany!.toMap(),
        "files": filesPayload,
        "syncedAt": DateTime.now().toIso8601String(),
      };

      final client = http.Client();
      final request = http.Request('POST', Uri.parse(WebCloudConfig.cloudRelayEndpoint))
        ..headers.addAll(WebCloudConfig.standardHeaders)
        ..body = jsonEncode(payload)
        ..followRedirects = true;

      final streamedResponse = await client.send(request).timeout(WebCloudConfig.networkTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 400) {
        await prefs.setStringList(syncHistoryKey, importedHistory.toList());
        await prefs.setString('last_cloud_sync_time', DateTime.now().toIso8601String());
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("AppSyncEngine Error: $e");
      return false;
    }
  }

  static Future<String> getLastSyncFormattedTime() async {
    final prefs = await SharedPreferences.getInstance();
    String? timeStr = prefs.getString('last_cloud_sync_time');
    if (timeStr == null || timeStr.isEmpty) return "Never";
    try {
      DateTime dt = DateTime.parse(timeStr);
      String pad(int n) => n.toString().padLeft(2, '0');
      return "${pad(dt.day)}/${pad(dt.month)}/${dt.year} at ${pad(dt.hour)}:${pad(dt.minute)}";
    } catch (_) {
      return "Never";
    }
  }
}
