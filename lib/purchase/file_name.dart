import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import 'purchase_billing_view.dart';

class PurchaseEntryView extends StatefulWidget {
  const PurchaseEntryView({super.key});

  @override
  State<PurchaseEntryView> createState() => _PurchaseEntryViewState();
}

class _PurchaseEntryViewState extends State<PurchaseEntryView> {
  // --- CONTROLLERS & STATE ---
  final distBillNoC = TextEditingController(); // Supplier's Bill Number
  final internalNoC = TextEditingController(); // Internal Entry Number (PUR-X)
  DateTime selectedBillDate = DateTime.now(); 
  String paymentMode = "CREDIT"; 
  Party? selectedDistributor; 
  String distributorSearchKey = "";

  // Date constraints for current Financial Year
  DateTime firstDateOfFY = DateTime(2024, 4, 1); 
  DateTime lastDateOfFY = DateTime(2030, 3, 31);

  @override
  void initState() {
    super.initState();
    _initializePurchaseHeader();
  }

  // --- INITIAL SETUP LOGIC ---
  Future<void> _initializePurchaseHeader() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Load Financial Year Settings
    String fy = prefs.getString('fy') ?? "2025-26";
    try {
      int startYear = int.parse(fy.split('-')[0]); 
      if (startYear < 2000) startYear += 2000;
      
      setState(() {
        firstDateOfFY = DateTime(startYear, 4, 1);
        lastDateOfFY = DateTime(startYear + 1, 3, 31);
        
        // Adjust default date if today is outside the selected FY
        DateTime today = DateTime.now();
        if (today.isBefore(firstDateOfFY) || today.isAfter(lastDateOfFY)) {
          selectedBillDate = firstDateOfFY;
        } else {
          selectedBillDate = today;
        }
      });
    } catch (e) {
      debugPrint("FY Parse Error: $e");
    }

    // 2. Generate Next Internal Purchase Number (PUR-X)
    int lastPurId = prefs.getInt('lastPurID') ?? 0;
    setState(() {
      internalNoC.text = "PUR-${lastPurId + 1}";
    });
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: const Text("Purchase Entry (Stock In)"), 
        backgroundColor: Colors.orange.shade800, 
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // --- HEADER SECTION: ENTRY DETAILS ---
          Container(
            padding: const EdgeInsets.all(20), 
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(25), bottomRight: Radius.circular(25)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // Internal Tracking No (Read Only)
                    Expanded(
                      child: TextField(
                        controller: internalNoC, 
                        enabled: false, 
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                        decoration: const InputDecoration(
                          labelText: "ENTRY NO", 
                          border: OutlineInputBorder(), 
                          filled: true, 
                          fillColor: Color(0xFFF0F0F0)
                        )
                      )
                    ),
                    const SizedBox(width: 15),
                    // Supplier Bill No (Manual Entry)
                    Expanded(
                      child: TextField(
                        controller: distBillNoC, 
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: "SUPPLIER BILL NO", 
                          hintText: "Enter Bill No",
                          border: OutlineInputBorder(), 
                          filled: true, 
                          fillColor: Colors.white
                        )
                      )
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    // Bill Date Picker
                    Expanded(
                      child: InkWell(
                        onTap: () async { 
                          DateTime? picked = await showDatePicker(
                            context: context, 
                            initialDate: selectedBillDate, 
                            firstDate: firstDateOfFY, 
                            lastDate: lastDateOfFY
                          ); 
                          if (picked != null) setState(() => selectedBillDate = picked); 
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12), 
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400), 
                            borderRadius: BorderRadius.circular(5), 
                            color: Colors.white
                          ), 
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("BILL DATE", style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)), 
                              Text(
                                DateFormat('dd/MM/yyyy').format(selectedBillDate), 
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)
                              )
                            ],
                          )
                        )
                      )
                    ),
                    const SizedBox(width: 15),
                    // Payment Mode Segment
                    Expanded(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'CASH', label: Text('CASH'), icon: Icon(Icons.money, size: 16)), 
                          ButtonSegment(value: 'CREDIT', label: Text('CREDIT'), icon: Icon(Icons.credit_card, size: 16))
                        ], 
                        selected: {paymentMode}, 
                        onSelectionChanged: (v) => setState(() => paymentMode = v.first),
                      )
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // --- DISTRIBUTOR SELECTION SECTION ---
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 10), 
            child: Align(
              alignment: Alignment.centerLeft, 
              child: Text("SELECT DISTRIBUTOR / SUPPLIER", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 12, letterSpacing: 1))
            )
          ),
          
          if (selectedDistributor != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.orange.shade200)),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(15),
                  leading: const CircleAvatar(backgroundColor: Colors.orange, child: Icon(Icons.business, color: Colors.white)),
                  title: Text(selectedDistributor!.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  subtitle: Text("${selectedDistributor!.city} | GST: ${selectedDistributor!.gst}"),
                  trailing: IconButton(
                    icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 28), 
                    onPressed: () => setState(() => selectedDistributor = null)
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20), 
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: "Search Distributor by Name...", 
                        prefixIcon: const Icon(Icons.search, color: Colors.orange), 
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white
                      ), 
                      onChanged: (v) => setState(() => distributorSearchKey = v)
                    )
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      children: ph.parties
                          .where((p) => p.name.toLowerCase().contains(distributorSearchKey.toLowerCase()))
                          .map((p) => ListTile(
                                leading: const Icon(Icons.business_outlined, color: Colors.grey),
                                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)), 
                                subtitle: Text(p.city),
                                onTap: () => setState(() => selectedDistributor = p)
                              ))
                          .toList()
                    ),
                  )
                ],
              )
            ),

          // --- BOTTOM NAVIGATION BUTTON ---
          if (selectedDistributor != null)
            Padding(
              padding: const EdgeInsets.all(20), 
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 60), 
                  backgroundColor: Colors.orange.shade800,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  elevation: 5
                ),
                onPressed: () {
                  if (distBillNoC.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Please enter the Supplier's Bill Number to proceed."))
                    );
                    return;
                  }
                  
                  // Navigate to the Items Entry Screen
                  Navigator.push(
                    context, 
                    MaterialPageRoute(builder: (c) => PurchaseBillingView(
                      distributor: selectedDistributor!,
                      internalNo: internalNoC.text,
                      distBillNo: distBillNoC.text.trim(),
                      billDate: selectedBillDate,
                      mode: paymentMode,
                    ))
                  );
                },
                child: const Text(
                  "PROCEED TO ITEM ENTRY", 
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)
                ),
              ),
            ),
        ],
      ),
    );
  }
}
