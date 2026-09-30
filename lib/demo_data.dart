// FILE: lib/demo_data.dart

import 'models.dart';

class DemoData {
  
  // 1. DEMO MEDICINES (Matching PH- Prefix)
  static List<Medicine> getMedicines() {
    List<Map<String, dynamic>> products = [
      {"name": "DOLO 650 MG", "pack": "15 TAB", "mrp": 30.91, "pur": 25.40, "a": 28.50, "b": 27.00, "c": 26.50, "sid": "PH-00001", "cid": "CP-00001", "slid": "SL-00001"},
      {"name": "PAN 40 MG", "pack": "10 TAB", "mrp": 120.00, "pur": 95.00, "a": 110.00, "b": 105.00, "c": 100.00, "sid": "PH-00002", "cid": "CP-00002", "slid": "SL-00002"},
      {"name": "AZITHRAL 500", "pack": "5 TAB", "mrp": 115.00, "pur": 88.00, "a": 105.00, "b": 100.00, "c": 98.00, "sid": "PH-00003", "cid": "CP-00003", "slid": "SL-00003"},
      {"name": "LIMCEE 500", "pack": "15 TAB", "mrp": 25.00, "pur": 18.00, "a": 23.00, "b": 22.00, "c": 20.00, "sid": "PH-00004", "cid": "CP-00004", "slid": "SL-00004"},
    ];

    return products.map((p) {
      return Medicine(
        id: "demo_${p['sid']}", // Technical Unique ID
        systemId: p['sid'],     // Business Series ID (Engine isko scan karega)
        name: p['name'],
        packing: p['pack'],
        companyId: p['cid'],    // Linked to Demo Company
        saltId: p['slid'],       // Linked to Demo Salt
        mrp: p['mrp'],
        purRate: p['pur'],
        rateA: p['a'],
        rateB: p['b'],
        rateC: p['c'],
        stock: 0.0,
        gst: 12.0,
        hsnCode: "3004",
      );
    }).toList();
  }

  // 2. DEMO COMPANIES (Matching CP- Prefix)
  static List<Company> getCompanies() {
    return [
      Company(id: "CP-00001", name: "MICRO LABS LTD"),
      Company(id: "CP-00002", name: "ALKEM LABORATORIES"),
      Company(id: "CP-00003", name: "ALEMBIC PHARMA"),
      Company(id: "CP-00004", name: "ABBOTT INDIA"),
    ];
  }

  // 3. DEMO SALTS (Matching SL- Prefix)
  static List<Salt> getSalts() {
    return [
      Salt(id: "SL-00001", name: "PARACETAMOL 650MG", type: "Mono"),
      Salt(id: "SL-00002", name: "PANTOPRAZOLE 40MG", type: "Mono"),
      Salt(id: "SL-00003", name: "AZITHROMYCIN 500MG", type: "Mono"),
      Salt(id: "SL-00004", name: "VITAMIN C (ASCORBIC ACID)", type: "Mono"),
    ];
  }

  // 4. DEMO PARTY
  static Party getDemoParty() {
    return Party(
      id: "demo_party_1", 
      name: "ABC PHARMA DISTRIBUTORS", 
      address: "M.G. ROAD, INDUSTRIAL AREA", 
      city: "UDAIPUR", 
      gst: "08ABCDE1234F1Z5",
      group: "Sundry Creditors"
    );
  }
}
