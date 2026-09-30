// FILE: lib/master_data_library.dart

import 'models.dart';

class MasterDataLibrary {
  // 1. TOP PHARMA COMPANIES WITH IDs (CP- Series)
  static List<Company> getTopCompanies() {
    List<String> names = [
      "CIPLA LTD", "MANKIND PHARMA", "SUN PHARMA", "ABBOTT INDIA", "ALKEM LABORATORIES",
      "LUPIN LTD", "DR REDDYS LAB", "ZYDUS CADILA", "GLAXOSMITHKLINE", "PFIZER"
    ];
    return names.asMap().entries.map((e) {
      return Company(id: "CP-${1001 + e.key}", name: e.value);
    }).toList();
  }

  // 2. TOP SALTS WITH IDs (SL- Series)
  static List<Salt> getTopSalts() {
    List<Map<String, String>> salts = [
      {"name": "PARACETAMOL 500MG", "type": "Mono"},
      {"name": "PANTOPRAZOLE 40MG", "type": "Mono"},
      {"name": "AMOXICILLIN + CLAVULANIC ACID", "type": "Duo"},
      {"name": "AZITHROMYCIN 500MG", "type": "Mono"},
      {"name": "CETIRIZINE 10MG", "type": "Mono"}
    ];
    return salts.asMap().entries.map((e) {
      return Salt(id: "SL-${1001 + e.key}", name: e.value['name']!, type: e.value['type']!);
    }).toList();
  }

  // 3. DRUG TYPES WITH IDs (DT- Series)
  static List<DrugType> getDrugTypes() {
    List<String> types = [
      "GENERAL / OTC", "SCHEDULE H", "SCHEDULE H1", "SCHEDULE G", "NARCOTIC (NDPS)"
    ];
    return types.asMap().entries.map((e) {
      return DrugType(id: "DT-${101 + e.key}", name: e.value);
    }).toList();
  }
}
