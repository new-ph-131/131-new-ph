// FILE: lib/administration/system_user_model.dart

import 'dart:convert';

class SystemUser {
  String id, name, username, password;
  
  // --- PERMISSIONS ---
  bool canDeleteBill;
  bool canEditBill;         
  bool canViewPurchaseRate; 
  bool canViewFinance;      
  bool canExportData;  
  bool canRunMaintenance;   // NAYA: Permission for File Maintenance

  SystemUser({
    required this.id, 
    required this.name, 
    required this.username, 
    required this.password,
    this.canDeleteBill = false,
    this.canEditBill = false,         
    this.canViewPurchaseRate = false,
    this.canViewFinance = false,
    this.canExportData = false,
    this.canRunMaintenance = false, // Default OFF rahega
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id, 
      'name': name, 
      'username': username, 
      'password': password,
      'canDeleteBill': canDeleteBill, 
      'canEditBill': canEditBill,
      'canViewPurchaseRate': canViewPurchaseRate, 
      'canViewFinance': canViewFinance,
      'canExportData': canExportData,
      'canRunMaintenance': canRunMaintenance, // JSON mein save karne ke liye
    };
  }

  factory SystemUser.fromMap(Map<String, dynamic> map) {
    return SystemUser(
      id: map['id'] ?? '', 
      name: map['name'] ?? '', 
      username: map['username'] ?? '', 
      password: map['password'] ?? '',
      canDeleteBill: map['canDeleteBill'] ?? false,
      canEditBill: map['canEditBill'] ?? false,
      canViewPurchaseRate: map['canViewPurchaseRate'] ?? false,
      canViewFinance: map['canViewFinance'] ?? false,
      canExportData: map['canExportData'] ?? false,
      canRunMaintenance: map['canRunMaintenance'] ?? false, // Load karte waqt safety (?? false)
    );
  }
}
