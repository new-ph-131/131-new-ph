// FILE: lib/gateway/company_registry_model.dart

import 'dart:convert';

class CompanyProfile {
  // --- Core Identity ---
  final String id;           
  final String name;         
  final String businessType; 
  final DateTime createdAt;

  // --- Detailed Profile ---
  final String address;
  final String state;
  final String gstin;
  final String dlNo;
  final String phone;
  final String email;

  // --- Security & Access ---
  final String adminUser;    
  final String password;     
  
  // --- NEW SECURITY FIELDS ---
  final bool isBiometricEnabled;  // Fingerprint choice
  final String recoveryKey;       // 16-digit Reset Key
  final int autoLockMinutes;      // 0, 5, 10 minutes

  // --- System Context ---
  final List<String> fYears; 

  CompanyProfile({
    required this.id,
    required this.name,
    required this.businessType,
    required this.createdAt,
    this.address = "",
    this.state = "Rajasthan",
    this.gstin = "N/A",
    this.dlNo = "N/A",
    this.phone = "",
    this.email = "",
    this.adminUser = "admin",
    required this.password,
    this.isBiometricEnabled = false,
    this.recoveryKey = "",
    this.autoLockMinutes = 5,
    this.fYears = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'businessType': businessType,
      'createdAt': createdAt.toIso8601String(),
      'address': address,
      'state': state,
      'gstin': gstin,
      'dlNo': dlNo,
      'phone': phone,
      'email': email,
      'adminUser': adminUser,
      'password': password,
      'isBiometricEnabled': isBiometricEnabled,
      'recoveryKey': recoveryKey,
      'autoLockMinutes': autoLockMinutes,
      'fYears': fYears,
    };
  }

  factory CompanyProfile.fromMap(Map<String, dynamic> map) {
    return CompanyProfile(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      businessType: map['businessType'] ?? 'WHOLESALE',
      createdAt: DateTime.parse(map['createdAt'] ?? DateTime.now().toIso8601String()),
      address: map['address'] ?? '',
      state: map['state'] ?? 'Rajasthan',
      gstin: map['gstin'] ?? 'N/A',
      dlNo: map['dlNo'] ?? 'N/A',
      phone: map['phone'] ?? '',
      email: map['email'] ?? '',
      adminUser: map['adminUser'] ?? 'admin',
      password: map['password'] ?? '',
      isBiometricEnabled: map['isBiometricEnabled'] ?? false,
      recoveryKey: map['recoveryKey'] ?? '',
      autoLockMinutes: map['autoLockMinutes'] ?? 5,
      fYears: List<String>.from(map['fYears'] ?? []),
    );
  }
}
