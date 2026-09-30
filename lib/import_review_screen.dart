// FILE: lib/import_review_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'pharoah_manager.dart';
import 'models.dart';
import 'party_master.dart';
import 'product_master.dart';
import 'batch_sync_engine.dart';
import 'logic/pharoah_numbering_engine.dart';
import 'app_date_logic.dart';

class ImportReviewScreen extends StatefulWidget {
  final List<List<dynamic>> csvData;
  final String importType; 
  final String exchangeMode; 

  const ImportReviewScreen({
    super.key, 
    required this.csvData, 
    required this.importType, 
    required this.exchangeMode
  });

  @override
  State<ImportReviewScreen> createState() => _ImportReviewScreenState();
}

class _ImportReviewScreenState extends State<ImportReviewScreen> {
  List<Map<String, dynamic>> reviewedItems = [];
  Map<String, dynamic> partyInfoInFile = {};
  Party? matchedParty;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _processUniversalLogic();
  }

  void _processUniversalLogic() {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    final data = widget.csvData;
    if (data.length < 2) return;
    
   var r1 = data[1];

    // --- SMART DATE WATCHDOG START (NEW) ---
    String rawCsvDate = r1[0]?.toString() ?? "";
    DateTime finalAdjustedDate;
    String dateAdjustmentNote = "";
    bool isDateAdjusted = false;

    // Active Financial Year Boundaries
    DateTime fyStart = AppDateLogic.getFYStart(ph.currentFY);
    DateTime fyEnd = AppDateLogic.getFYEnd(ph.currentFY);

    try {
      DateTime parsedDate = DateFormat('dd/MM/yyyy').parse(rawCsvDate.trim());
      
      if (parsedDate.isBefore(fyStart)) {
        // Maal pichle saal ka hai -> Force to 1st April of current active year
        finalAdjustedDate = fyStart;
        isDateAdjusted = true;
        dateAdjustmentNote = "[Date Adjusted: Original Csv Date $rawCsvDate]";
      } else if (parsedDate.isAfter(fyEnd)) {
        // Future date case -> Force to 31st March
        finalAdjustedDate = fyEnd;
        isDateAdjusted = true;
        dateAdjustmentNote = "[Date Adjusted: Original Csv Date $rawCsvDate]";
      } else {
        // Sahi range mein hai -> Keep original
        finalAdjustedDate = parsedDate;
      }
    } catch (e) {
      // Parse error fallback -> Force to FY Start
      finalAdjustedDate = fyStart;
      isDateAdjusted = true;
      dateAdjustmentNote = "[Date Adjusted: Parse Fail Fallback]";
    }
    // --- SMART DATE WATCHDOG END ---

    partyInfoInFile = {
      'name': r1[2]?.toString().trim().toUpperCase() ?? "UNKNOWN",
      'gst': r1[3]?.toString().trim().toUpperCase() ?? "",
      'dl': r1[4]?.toString().trim().toUpperCase() ?? "",
      'pan': r1[5]?.toString().trim().toUpperCase() ?? "",
      'phone': r1[6]?.toString().trim() ?? "", 
      'email': r1[7]?.toString().trim().toLowerCase() ?? "",
      'address': r1[8]?.toString().trim().toUpperCase() ?? "",
      'city': r1[9]?.toString().trim().toUpperCase() ?? "",
      'state': r1[10]?.toString().trim() ?? "Rajasthan",
      'billNo': r1[1]?.toString() ?? "DRAFT",
      
      // Adjusted Date and Flags
      'date': finalAdjustedDate, // Store as DateTime object directly
      'isDateAdjusted': isDateAdjusted,
      'dateAdjustmentNote': dateAdjustmentNote,
      'rawCsvDate': rawCsvDate,

   // 🆕 BACKWARD COMPATIBLE & SECURE PARSING:
      // Naya format (39 columns): Index 37 is Extra Discount, Index 38 is Round Off
      // Purana format (38 columns): Extra Discount is 0.0, Index 37 is Round Off
      'extraDisc': r1.length >= 39 ? (double.tryParse(r1[37].toString()) ?? 0.0) : 0.0,
      'roundOff': r1.length >= 39 
          ? (double.tryParse(r1[38].toString()) ?? 0.0) 
          : (r1.length >= 38 ? (double.tryParse(r1[37].toString()) ?? 0.0) : 0.0),
    };

    try {
      matchedParty = ph.parties.firstWhere((p) => 
        (p.gst.isNotEmpty && p.gst == partyInfoInFile['gst']) || p.name == partyInfoInFile['name']
      );
    } catch (e) { matchedParty = null; }

    reviewedItems.clear();
    for (int i = 1; i < data.length; i++) {
      var row = data[i];
      if (row.length < 34) continue;

      String csvName = row[18]?.toString().toUpperCase().trim() ?? "UNKNOWN";
      String csvPack = row[19]?.toString().toUpperCase().trim() ?? "N/A";
      double qty = double.tryParse(row[28].toString()) ?? 0.0;
      double rate = widget.importType == "PURCHASE" 
          ? (double.tryParse(row[31].toString()) ?? 0.0) 
          : (double.tryParse(row[32].toString()) ?? 0.0);
      
      double gstPer = double.tryParse(row[33].toString()) ?? 12.0;
      double csvTotal = double.tryParse(row[34].toString()) ?? 0.0;
      double itemDiscPer = (row.length > 35) ? (double.tryParse(row[35].toString()) ?? 0.0) : 0.0;

      double gross = qty * rate;
      double discAmt = gross * (itemDiscPer / 100);
      double taxable = gross - discAmt;
      double taxAmt = taxable * (gstPer / 100); // Variable consistency fixed
      double systemTotal = double.parse((taxable + taxAmt).toStringAsFixed(2));

      bool isLocal = partyInfoInFile['state'].toString().toLowerCase() == (ph.activeCompany?.state.toLowerCase() ?? "rajasthan");

      Medicine? match;
      try { match = ph.medicines.firstWhere((m) => m.name == csvName && m.packing == csvPack); } 
      catch (e) { try { match = ph.medicines.firstWhere((m) => m.name == csvName); } catch (e) { match = null; } }

      reviewedItems.add({
        'name': csvName, 'pack': csvPack, 'hsn': row[20]?.toString() ?? "3004",
        'mfg': row[21]?.toString().toUpperCase() ?? "N/A", 'salt': row[22]?.toString().toUpperCase() ?? "N/A",
        'form': row[23]?.toString().toUpperCase() ?? "TAB", 'isNaco': row[24]?.toString() == "YES",
        'isH1': row[25]?.toString() == "YES", 'batch': row[26]?.toString().trim() ?? "AUTO",
        'exp': row[27]?.toString() ?? "12/26", 'qty': qty, 'free': double.tryParse(row[29].toString()) ?? 0.0,
        'mrp': double.tryParse(row[30].toString()) ?? 0.0, 'purRate': double.tryParse(row[31].toString()) ?? 0.0,
        'rate': rate, 'gstPer': gstPer, 'csvTotal': csvTotal, 'sysTotal': systemTotal, 'itemDiscPer': itemDiscPer, 'discAmt': discAmt,
        'match': match, 'isSelected': match != null, 'status': match == null ? 'new' : 'exact',
        'isFixed': false, 'taxable': taxable, 'cgst': isLocal ? taxAmt/2 : 0.0, 'sgst': isLocal ? taxAmt/2 : 0.0, 'igst': isLocal ? 0.0 : taxAmt,
      });
    }
    setState(() => isLoading = false);
  }

  // 🆕 DYNAMIC AUTO-PROPAGATION: Ek row link hote hi baaki saari matching rows ko instantly auto-link karega
  void _propagateMatchingLinks(Medicine matchedMed) {
    setState(() {
      for (var it in reviewedItems) {
        if (it['match'] == null && 
            it['name'].toString().toUpperCase().trim() == matchedMed.name.toUpperCase().trim() && 
            it['pack'].toString().toUpperCase().trim() == matchedMed.packing.toUpperCase().trim()) {
          it['match'] = matchedMed;
          it['status'] = 'exact';
          it['isSelected'] = true;
        }
      }
    });
  }

  // 🆕 INSTANT BILLING-STYLE SEARCH SHEET: Direct link sheet (bypasses full master view)
  void _showInstantLinkOverlay(int itemIndex) {
    final ph = Provider.of<PharoahManager>(context, listen: false); // Mapped via context safely
    String localSearch = "";
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B), // Premium Dark Slate matching theme
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final filteredMeds = ph.medicines
              .where((m) => m.name.toLowerCase().contains(localSearch.toLowerCase()))
              .toList();

          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 15),
            child: Column(
              children: [
                Container(height: 5, width: 50, decoration: const BoxDecoration(color: Colors.white24)),
                const SizedBox(height: 15),
                const Text(
                  "SEARCH SYSTEM MASTER TO LINK",
                  style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                const SizedBox(height: 15),
                TextField(
                  style: const TextStyle(color: Colors.white),
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: "Type name to search product...",
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.search, color: Colors.blueAccent),
                    filled: true,
                    fillColor: Colors.white10,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  ),
                  onChanged: (v) => setSheetState(() => localSearch = v),
                ),
                const SizedBox(height: 15),
                Expanded(
                  child: filteredMeds.isEmpty
                      ? const Center(child: Text("No products found.", style: TextStyle(color: Colors.white38)))
                      : ListView.builder(
                          itemCount: filteredMeds.length,
                          itemBuilder: (c, idx) {
                            final m = filteredMeds[idx];
                            return LibraryListTile(m, context);
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    ).then((selectedMed) {
      if (selectedMed != null && selectedMed is Medicine) {
        setState(() {
          reviewedItems[itemIndex]['match'] = selectedMed;
          reviewedItems[itemIndex]['status'] = 'exact';
          reviewedItems[itemIndex]['isSelected'] = true;
        });
        // Matching unlinked items ko instantly cascade (propagate) karein
        _propagateMatchingLinks(selectedMed);
      }
    });
  }

  // Helper widget to bypass compiler nested state rebuild checks
  Widget LibraryListTile(Medicine m, BuildContext context) {
    return ListTile(
      title: Text(m.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      subtitle: Text("Pack: ${m.packing} | Stock: ${m.stock.toInt()}", style: const TextStyle(color: Colors.white54, fontSize: 11)),
      trailing: const Icon(Icons.link_rounded, color: Colors.greenAccent, size: 18),
      onTap: () {
        Navigator.pop(context, m);
      },
    );
  }

 void _autoResolveAllNewProducts(PharoahManager ph) async {
    List<int> newIndices = [];
    for (int i = 0; i < reviewedItems.length; i++) { 
      if (reviewedItems[i]['status'] == 'new') newIndices.add(i); 
    }
    if (newIndices.isEmpty) return;

    setState(() => isLoading = true);
    
    // System ID Counter Setup
    String startNoStr = await PharoahNumberingEngine.getNextNumber(type: "PRODUCT", companyID: ph.activeCompany!.id, prefix: "PH-", startFrom: 10001, currentList: ph.medicines);
    int currentNum = int.parse(startNoStr.replaceAll("PH-", ""));

    // Loop ke andar duplicate master creation se bachne ke liye local cache
    Map<String, Medicine> newlyCreatedInLoop = {};

    for (int idx in newIndices) {
      var it = reviewedItems[idx];
      String nameKey = "${it['name'].toString().toUpperCase().trim()}|${it['pack'].toString().toUpperCase().trim()}";

      if (newlyCreatedInLoop.containsKey(nameKey)) {
        // 🆕 DEDUPLICATION: Use the product created in previous loop iteration
        it['match'] = newlyCreatedInLoop[nameKey];
        it['status'] = 'exact';
        it['isSelected'] = true;
      } else {
        // Safe check: Kahin loop chalne ke dauran hi user ne manual create ya link toh nahi kiya
        Medicine? doubleCheckMaster;
        try {
          doubleCheckMaster = ph.medicines.firstWhere((m) => 
            m.name.toUpperCase().trim() == it['name'].toString().toUpperCase().trim() && 
            m.packing.toUpperCase().trim() == it['pack'].toString().toUpperCase().trim()
          );
        } catch (_) { doubleCheckMaster = null; }

        if (doubleCheckMaster != null) {
          it['match'] = doubleCheckMaster;
          it['status'] = 'exact';
          it['isSelected'] = true;
          newlyCreatedInLoop[nameKey] = doubleCheckMaster;
        } else {
          // Unique New Product Master creation
          String genId = "PH-$currentNum";
          final m = Medicine(
            id: DateTime.now().millisecondsSinceEpoch.toString() + idx.toString(), 
            systemId: genId, 
            name: it['name'], 
            packing: it['pack'], 
            hsnCode: it['hsn'], 
            gst: it['gstPer'], 
            mrp: it['mrp'], 
            purRate: it['purRate'], 
            rateA: it['rate'], 
            drugForm: it['form'], 
            isNarcotic: it['isNaco'], 
            isScheduleH1: it['isH1'], 
            companyId: ph.getOrCreateCompany(it['mfg']), 
            saltId: ph.getOrCreateSalt(it['salt'])
          );
          
          ph.addMedicine(m, doSave: false); 
          it['match'] = m; 
          it['status'] = 'exact'; 
          it['isSelected'] = true; 
          
          newlyCreatedInLoop[nameKey] = m;
          currentNum++;
        }
      }
    }
    await ph.save(); 
    setState(() => isLoading = false);
  }

  void _showQuickPartyPicker(PharoahManager ph) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: const Color(0xFF0F172A), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))), builder: (c) {
      String s = ""; return StatefulBuilder(builder: (context, setPickerState) {
        final list = ph.parties.where((p) => p.name.toLowerCase().contains(s.toLowerCase())).toList();
        return Container(height: MediaQuery.of(context).size.height * 0.8, padding: const EdgeInsets.all(20), child: Column(children: [
          const Text("SELECT PARTY FROM SYSTEM", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 15),
          TextField(style: const TextStyle(color: Colors.white), autofocus: true, decoration: InputDecoration(hintText: "Type name to search...", hintStyle: const TextStyle(color: Colors.white24), prefixIcon: const Icon(Icons.search, color: Colors.blueAccent), filled: true, fillColor: Colors.white10, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15))), onChanged: (v) => setPickerState(() => s = v)),
          Expanded(child: ListView.builder(itemCount: list.length, itemBuilder: (c, i) => ListTile(title: Text(list[i].name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), subtitle: Text("${list[i].city} | GST: ${list[i].gst}", style: const TextStyle(color: Colors.white54, fontSize: 11)), onTap: () { setState(() => matchedParty = list[i]); Navigator.pop(context); })))
        ]));
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    if (isLoading) return const Scaffold(backgroundColor: Color(0xFF0F172A), body: Center(child: CircularProgressIndicator()));
    int newCount = reviewedItems.where((it) => it['status'] == 'new').length;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(title: const Text("MIRROR AUDIT ENGINE"), backgroundColor: const Color(0xFF1E293B)),
      body: Column(children: [
        _buildPartyCard(),
        if (newCount > 0) _buildBulkBanner(ph, newCount),
        Expanded(child: ListView.builder(padding: const EdgeInsets.all(12), itemCount: reviewedItems.length, itemBuilder: (c, i) => _buildRow(i))),
        _buildAnalyticsFooter(ph),
      ]),
    );
  }

 Widget _buildPartyCard() {
    bool isOk = matchedParty != null;
    bool wasDateAdjusted = partyInfoInFile['isDateAdjusted'] ?? false;
    String rawDateStr = partyInfoInFile['rawCsvDate'] ?? "";
    String adjustedDateStr = DateFormat('dd/MM/yyyy').format(partyInfoInFile['date'] as DateTime);

    return Column(
      children: [
        InkWell(
          onTap: () => _showPartyVerifySheet(),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(15), border: Border.all(color: isOk ? Colors.blueAccent : Colors.redAccent)),
            child: Row(children: [
              CircleAvatar(backgroundColor: isOk ? Colors.blue : Colors.redAccent, child: const Icon(Icons.business, color: Colors.white)),
              const SizedBox(width: 15),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(partyInfoInFile['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                Text("Mob: ${partyInfoInFile['phone']} | GST: ${partyInfoInFile['gst']}", style: const TextStyle(color: Colors.white54, fontSize: 10)),
                const Text("VIEW & MANAGE DETAILS", style: TextStyle(color: Colors.blueAccent, fontSize: 9, fontWeight: FontWeight.bold)),
              ])),
              Icon(isOk ? Icons.verified : Icons.error_outline, color: isOk ? Colors.greenAccent : Colors.orange),
            ]),
          ),
        ),

        // --- ⚠️ SMART DATE WARNING BADGE (NEW) ---
        if (wasDateAdjusted)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.3))
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Warning: Bill Date ($rawDateStr) was from different year. Forcing to 1st April ($adjustedDateStr) for compliance.",
                  style: const TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ]),
          ),
      ],
    );
  }

  Widget _buildBulkBanner(PharoahManager ph, int count) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.withOpacity(0.3))),
    child: Row(children: [const Icon(Icons.auto_fix_high, color: Colors.orange, size: 18), const SizedBox(width: 10), Expanded(child: Text("Found $count new items. Auto-create all with PH-IDs?", style: const TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold))), ElevatedButton(onPressed: () => _autoResolveAllNewProducts(ph), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, minimumSize: const Size(60, 30)), child: const Text("AUTO-CREATE", style: TextStyle(fontSize: 9)))]),
  );

  Widget _buildRow(int i) {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    var it = reviewedItems[i];
    bool hasErr = (it['sysTotal'] - it['csvTotal']).abs() > 0.1 && !it['isFixed'];
    Color statusColor = it['status'] == 'new' ? Colors.orange : (hasErr ? Colors.redAccent : Colors.greenAccent);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12), border: Border.all(color: statusColor.withOpacity(0.4))),
      child: Column(children: [
        ListTile(
          dense: true,
          leading: Checkbox(value: it['isSelected'], activeColor: Colors.green, onChanged: (v) => setState(() => it['isSelected'] = v!)),
          title: Text(it['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          subtitle: Wrap(spacing: 5, children: [ _badge("PK: ${it['pack']}", Colors.blueGrey), _badge("DISC: ${it['itemDiscPer']}%", Colors.orangeAccent), ]),
        trailing: it['match'] == null 
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                // 🆕 INSTANT LOOKUP SHEET: Master page par jane ke bajaye billing style sheet open karega
                IconButton(
                  icon: const Icon(Icons.link, color: Colors.blueAccent, size: 20), 
                  onPressed: () => _showInstantLinkOverlay(i),
                ),
                // 🆕 SINGLE CREATION WITH CASCADE: Naya product save hote hi sabhi matching unlinked items ko auto-link kar dega
                IconButton(
                  icon: const Icon(Icons.add_box, color: Colors.redAccent, size: 20), 
                  onPressed: () async {
                    final res = await Navigator.push(
                      context, 
                      MaterialPageRoute(builder: (c) => ProductMasterView(isSelectionMode: true, preFillData: it))
                    );
                    if (res != null && res is Medicine) {
                      setState(() { 
                        it['match'] = res; 
                        it['status'] = 'exact'; 
                        it['isSelected'] = true; 
                      });
                      // Mismatches aur duplicates se bachne ke liye auto-cascade check run karein
                      _propagateMatchingLinks(res);
                    }
                  },
                ),
              ])
            : const Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
        ),
        Container(
          padding: const EdgeInsets.all(10), color: Colors.black12,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _metric("CSV TOTAL", it['csvTotal']),
            _metric("SYSTEM CALC", it['sysTotal'], color: hasErr ? Colors.redAccent : Colors.greenAccent),
            if (hasErr) ElevatedButton(onPressed: () => setState(() { it['isFixed'] = true; it['sysTotal'] = it['csvTotal']; }), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(50, 28)), child: const Text("FIX", style: TextStyle(fontSize: 9)))
          ]),
        )
      ]),
    );
  }

  void _showPartyVerifySheet() {
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF0F172A), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))), builder: (c) => Padding(padding: const EdgeInsets.all(25), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("SENDER VERIFICATION", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
      const Divider(color: Colors.white10, height: 30),
      _detailRow("NAME", partyInfoInFile['name']),
      _detailRow("PHONE", partyInfoInFile['phone']),
      _detailRow("GSTIN", partyInfoInFile['gst']),
      _detailRow("STATE", partyInfoInFile['state']),
      const SizedBox(height: 30),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () { Navigator.pop(context); _showQuickPartyPicker(Provider.of<PharoahManager>(context, listen: false)); }, child: const Text("LINK EXISTING"))),
        const SizedBox(width: 15),
        Expanded(child: ElevatedButton(onPressed: () async {
           final res = await Navigator.push(context, MaterialPageRoute(builder: (c) => PartyMasterView(isSelectionMode: true, preFillData: partyInfoInFile)));
           if(res != null) { setState(() => matchedParty = res); Navigator.pop(context); }
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text("CREATE NEW"))),
      ])
    ])));
  }

  Widget _buildAnalyticsFooter(PharoahManager ph) {
    double sT = reviewedItems.where((e)=>e['isSelected']).fold(0.0, (s, e)=>s+e['sysTotal']);
    double cT = reviewedItems.where((e)=>e['isSelected']).fold(0.0, (s, e)=>s+e['csvTotal']);
    double dF = sT - cT;
    return Container(padding: const EdgeInsets.all(20), decoration: const BoxDecoration(color: Color(0xFF1E293B), borderRadius: BorderRadius.vertical(top: Radius.circular(25))), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ _footStat("SYSTEM NET", sT), _footStat("CSV NET", cT), _footStat("DIFF", dF, color: dF.abs() > 0.1 ? Colors.redAccent : Colors.greenAccent), ]),
      const Divider(color: Colors.white10, height: 25),
      SizedBox(width: double.infinity, height: 55, child: ElevatedButton.icon(onPressed: () => _handleFinalImport(ph), icon: const Icon(Icons.cloud_done), label: const Text("FINALIZE MIRROR DATA"), style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)))))
    ]));
  }

  void _handleFinalImport(PharoahManager ph) async {
    if (matchedParty == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Link/Create Party first!"))); return; }
    if (reviewedItems.any((it) => it['isSelected'] && it['match'] == null)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Link all products first!"))); return; }
    setState(() => isLoading = true);
    double curST = reviewedItems.where((e)=>e['isSelected']).fold(0.0, (s, e)=>s+e['sysTotal']);
    bool isLoc = matchedParty!.state.toLowerCase() == (ph.activeCompany?.state.toLowerCase() ?? "rajasthan");

   // Adjusted Date Fetch karna jo Step 1 mein set hui thi
    DateTime adjustedBillDate = partyInfoInFile['date'] as DateTime;
    String auditNote = partyInfoInFile['dateAdjustmentNote'] ?? "";
    
    // final import tag preparation
    String finalSourceTag = widget.exchangeMode;
    if (auditNote.isNotEmpty) {
      finalSourceTag += " $auditNote"; // Append audit log to sourceTag
    }

    if (widget.importType == "PURCHASE") {
      List<PurchaseItem> items = [];
      for (var it in reviewedItems.where((e) => e['isSelected'])) {
        Medicine m = it['match'];
        ph.registerBatchActivity(productKey: m.identityKey, batchNo: it['batch'], exp: it['exp'], packing: m.packing, mrp: it['mrp'], rate: it['rate']);
        items.add(PurchaseItem(id: DateTime.now().toString() + m.id, srNo: items.length + 1, medicineID: m.id, name: m.name, packing: m.packing, batch: it['batch'], exp: it['exp'], hsn: it['hsn'], mrp: it['mrp'], qty: it['qty'], freeQty: it['free'], purchaseRate: it['rate'], gstRate: it['gstPer'], total: it['sysTotal'], discountPer: it['itemDiscPer'], discountRupees: it['discAmt']));
      }
      
      // FIXED: Using already parsed and adjusted DateTime object (adjustedBillDate)
      ph.finalizePurchase(
        internalNo: "MIR-PUR-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}", 
        billNo: partyInfoInFile['billNo'], 
        date: adjustedBillDate, 
        entryDate: DateTime.now(), 
        party: matchedParty!, 
        items: items, 
        total: items.fold(0, (s, e)=>s+e.total), 
        mode: "CREDIT", 
        sourceTag: finalSourceTag
      );
    } else {
      List<BillItem> items = [];
      for (var it in reviewedItems.where((e) => e['isSelected'])) {
        Medicine m = it['match'];
        double tVal = it['taxable']; double tTax = it['sysTotal'] - tVal;
        items.add(BillItem(id: DateTime.now().toString() + m.id, srNo: items.length + 1, medicineID: m.id, name: m.name, packing: m.packing, batch: it['batch'], exp: it['exp'], hsn: it['hsn'], mrp: it['mrp'], qty: it['qty'], freeQty: it['free'], rate: it['rate'], gstRate: it['gstPer'], cgst: isLoc ? tTax/2 : 0, sgst: isLoc ? tTax/2 : 0, igst: isLoc ? 0 : tTax, total: it['sysTotal'], discountRupees: it['discAmt'], discountPer: it['itemDiscPer']));
      }
      
      // FIXED: Using adjustedBillDate
      await ph.finalizeSale(
        billNo: partyInfoInFile['billNo'], 
        date: adjustedBillDate, 
        party: matchedParty!, 
        items: items, 
        total: (curST - partyInfoInFile['extraDisc'] + partyInfoInFile['roundOff']), 
        mode: "CREDIT", 
        sourceTag: finalSourceTag, 
        extraDiscount: partyInfoInFile['extraDisc'], 
        roundOff: partyInfoInFile['roundOff']
      );
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ C2C Data Sync Successful!"), backgroundColor: Colors.green));
  }

  Widget _badge(String t, Color c) => Container(margin: const EdgeInsets.only(top: 4, right: 4), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text(t, style: TextStyle(color: c, fontSize: 8, fontWeight: FontWeight.bold)));
  Widget _metric(String l, double v, {Color color = Colors.white70}) => Column(children: [Text(l, style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold)), Text("₹${v.toStringAsFixed(2)}", style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900))]);
  Widget _footStat(String l, double v, {Color color = Colors.white70}) => Column(children: [Text(l, style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)), Text("₹${v.toStringAsFixed(2)}", style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold))]);
  Widget _detailRow(String l, String v) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [Text("$l: ", style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)), Expanded(child: Text(v, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)))]));
}
