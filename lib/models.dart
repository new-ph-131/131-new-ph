// FILE: lib/models.dart (FINAL UPDATED VERSION)

import 'dart:convert';
import 'package:flutter/material.dart';

// ===========================================================================
// 1. SYSTEM CONFIGURATION & SIGNATURE MODELS
// ===========================================================================

class NumberingSeries {
  String id, name, type, prefix;
  int startNumber;
  bool isDefault, isActive;

  NumberingSeries({
    required this.id, required this.name, required this.type, 
    required this.prefix, this.startNumber = 1, 
    this.isDefault = false, this.isActive = true
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'type': type, 'prefix': prefix, 
    'startNumber': startNumber, 'isDefault': isDefault, 'isActive': isActive
  };

  factory NumberingSeries.fromMap(Map<String, dynamic> map) => NumberingSeries(
    id: map['id'] ?? '', name: map['name'] ?? '', type: map['type'] ?? 'SALE', 
    prefix: map['prefix'] ?? '', startNumber: map['startNumber'] ?? 1, 
    isDefault: map['isDefault'] ?? false, isActive: map['isActive'] ?? true
  );
}

class ChallanSignature {
  String id, imagePath, verificationCode;
  double signedAmount, signedQty, signX, signY;
  DateTime signDate;

  ChallanSignature({
    required this.id, required this.imagePath, required this.verificationCode,
    required this.signedAmount, required this.signedQty, required this.signDate,
    this.signX = 0.0, this.signY = 0.0,
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'imagePath': imagePath, 'verificationCode': verificationCode,
    'signedAmount': signedAmount, 'signedQty': signedQty,
    'signDate': signDate.toIso8601String(), 'signX': signX, 'signY': signY,
  };

  factory ChallanSignature.fromMap(Map<String, dynamic> map) => ChallanSignature(
    id: map['id'] ?? '', imagePath: map['imagePath'] ?? '',
    verificationCode: map['verificationCode'] ?? '',
    signedAmount: (map['signedAmount'] ?? 0.0).toDouble(),
    signedQty: (map['signedQty'] ?? 0.0).toDouble(),
    signDate: DateTime.parse(map['signDate'] ?? DateTime.now().toIso8601String()),
    signX: (map['signX'] ?? 0.0).toDouble(),
    signY: (map['signY'] ?? 0.0).toDouble(),
  );
}

// ===========================================================================
// 2. MASTER MODELS (Static & Business Lists)
// ===========================================================================

class RouteArea { 
  String id, name; 
  RouteArea({required this.id, required this.name}); 
  Map<String, dynamic> toMap() => {'id': id, 'name': name}; 
  factory RouteArea.fromMap(Map<String, dynamic> map) => RouteArea(id: map['id'] ?? "", name: map['name'] ?? ""); 
}

class Company { 
  String id, name; 
  Company({required this.id, required this.name}); 
  Map<String, dynamic> toMap() => {'id': id, 'name': name}; 
  factory Company.fromMap(Map<String, dynamic> map) => Company(id: map['id'] ?? "", name: map['name'] ?? ""); 
}

class Salt { 
  String id, name, type; 
  Salt({required this.id, required this.name, this.type = "Mono"}); 
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'type': type}; 
  factory Salt.fromMap(Map<String, dynamic> map) => Salt(id: map['id'] ?? "", name: map['name'] ?? "", type: map['type'] ?? "Mono"); 
}

class DrugType { 
  String id, name; 
  DrugType({required this.id, required this.name}); 
  Map<String, dynamic> toMap() => {'id': id, 'name': name}; 
  factory DrugType.fromMap(Map<String, dynamic> map) => DrugType(id: map['id'] ?? "", name: map['name'] ?? ""); 
}

class Bank { 
  String id, name, branch, accountNo;
  double openingBalance; 
  Bank({required this.id, required this.name, this.branch = "", this.accountNo = "", this.openingBalance = 0.0});
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'branch': branch, 'accountNo': accountNo, 'openingBalance': openingBalance};
  factory Bank.fromMap(Map<String, dynamic> map) => Bank(id: map['id'] ?? "", name: map['name'] ?? "", branch: map['branch'] ?? "", accountNo: map['accountNo'] ?? "", openingBalance: (map['openingBalance'] ?? 0.0).toDouble());
}

class Salesman { 
  String id, name, phone, route; 
  Salesman({required this.id, required this.name, this.phone = "", this.route = ""});
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'phone': phone, 'route': route};
  factory Salesman.fromMap(Map<String, dynamic> map) => Salesman(id: map['id'] ?? "", name: map['name'] ?? "", phone: map['phone'] ?? "", route: map['route'] ?? "");
}

class BatchInfo { 
  String batch, exp, packing, adjReason; 
  double mrp, rate, qty, openingQty, adjustmentQty, breakageQty; 
  bool isShell;
  
  // --- MARG-STYLE AUTONOMOUS BATCH DETAILS ---
  double purRate;
  double rateA;
  double rateB;
  double rateC;
  double rateCFormula;
  String appliedRateType;
  String status; // 'Active', 'Hold', 'Blocked'

  BatchInfo({
    required this.batch, 
    required this.exp, 
    required this.packing, 
    required this.mrp, 
    required this.rate, 
    this.qty = 0.0, 
    this.openingQty = 0.0, 
    this.adjustmentQty = 0.0, 
    this.breakageQty = 0.0, 
    this.adjReason = "", 
    this.isShell = false,
    // Default safe fallbacks to prevent crash on old data
    this.purRate = 0.0,
    this.rateA = 0.0,
    this.rateB = 0.0,
    this.rateC = 0.0,
    this.rateCFormula = 0.0,
    this.appliedRateType = "A",
    this.status = "Active",
  });

  Map<String, dynamic> toMap() => {
    'batch': batch, 
    'exp': exp, 
    'packing': packing, 
    'mrp': mrp, 
    'rate': rate, 
    'qty': qty, 
    'openingQty': openingQty, 
    'adjustmentQty': adjustmentQty, 
    'breakageQty': breakageQty, 
    'adjReason': adjReason, 
    'isShell': isShell,
    // Database mapping updates
    'purRate': purRate,
    'rateA': rateA,
    'rateB': rateB,
    'rateC': rateC,
    'rateCFormula': rateCFormula,
    'appliedRateType': appliedRateType,
    'status': status,
  };

  factory BatchInfo.fromMap(Map<String, dynamic> map) => BatchInfo(
    batch: map['batch'] ?? "", 
    exp: map['exp'] ?? "", 
    packing: map['packing'] ?? "", 
    mrp: (map['mrp'] ?? 0.0).toDouble(), 
    rate: (map['rate'] ?? 0.0).toDouble(), 
    qty: (map['qty'] ?? 0.0).toDouble(), 
    openingQty: (map['openingQty'] ?? 0.0).toDouble(), 
    adjustmentQty: (map['adjustmentQty'] ?? 0.0).toDouble(), 
    breakageQty: (map['breakageQty'] ?? 0.0).toDouble(), 
    adjReason: map['adjReason'] ?? "", 
    isShell: map['isShell'] ?? false,
    // Fallback support: system calculates previous rate as default purRate / rateA
    purRate: (map['purRate'] ?? (map['rate'] ?? 0.0)).toDouble(),
    rateA: (map['rateA'] ?? (map['mrp'] ?? 0.0)).toDouble(),
    rateB: (map['rateB'] ?? 0.0).toDouble(),
    rateC: (map['rateC'] ?? 0.0).toDouble(),
    rateCFormula: (map['rateCFormula'] ?? 0.0).toDouble(),
    appliedRateType: map['appliedRateType'] ?? "A",
    status: map['status'] ?? "Active",
  ); 
}

// ===========================================================================
// 3. CORE INVENTORY & PARTY MODELS
// ===========================================================================

class Medicine {
  String id, systemId, uniqueCode, name, packing, companyId, saltId, drugTypeId, rackNo, hsnCode, drugForm, storageCondition; 
  int conversion; double reorderLevel, gst, mrp, purRate, rateA, rateB, rateC, stock; bool isNarcotic, isScheduleH1;
  String get identityKey => systemId.isNotEmpty ? systemId : id;

  Medicine({required this.id, this.systemId = "", this.uniqueCode = "", required this.name, required this.packing, this.companyId = "", this.saltId = "", this.drugTypeId = "", this.rackNo = "", this.hsnCode = "N/A", this.conversion = 1, this.reorderLevel = 0.0, this.gst = 12.0, this.mrp = 0.0, this.purRate = 0.0, this.rateA = 0.0, this.rateB = 0.0, this.rateC = 0.0, this.stock = 0.0, this.drugForm = "TAB", this.isNarcotic = false, this.isScheduleH1 = false, this.storageCondition = "Room Temp"});

  Map<String, dynamic> toMap() => {'id': id, 'systemId': systemId, 'uniqueCode': uniqueCode, 'name': name, 'packing': packing, 'companyId': companyId, 'saltId': saltId, 'drugTypeId': drugTypeId, 'rackNo': rackNo, 'hsnCode': hsnCode, 'conversion': conversion, 'reorderLevel': reorderLevel, 'gst': gst, 'mrp': mrp, 'purRate': purRate, 'rateA': rateA, 'rateB': rateB, 'rateC': rateC, 'stock': stock, 'drugForm': drugForm, 'isNarcotic': isNarcotic, 'isScheduleH1': isScheduleH1, 'storageCondition': storageCondition};
  factory Medicine.fromMap(Map<String, dynamic> map) => Medicine(id: map['id'] ?? "", systemId: map['systemId'] ?? "", uniqueCode: map['uniqueCode'] ?? "", name: map['name'] ?? "", packing: map['packing'] ?? "", companyId: map['companyId'] ?? "", saltId: map['saltId'] ?? "", drugTypeId: map['drugTypeId'] ?? "", rackNo: map['rackNo'] ?? "", hsnCode: map['hsnCode'] ?? "N/A", conversion: map['conversion'] ?? 1, reorderLevel: (map['reorderLevel'] ?? 0.0).toDouble(), gst: (map['gst'] ?? 12).toDouble(), mrp: (map['mrp'] ?? 0.0).toDouble(), purRate: (map['purRate'] ?? 0.0).toDouble(), rateA: (map['rateA'] ?? 0.0).toDouble(), rateB: (map['rateB'] ?? 0.0).toDouble(), rateC: (map['rateC'] ?? 0.0).toDouble(), stock: (map['stock'] ?? 0.0).toDouble(), drugForm: map['drugForm'] ?? "TAB", isNarcotic: map['isNarcotic'] ?? false, isScheduleH1: map['isScheduleH1'] ?? false, storageCondition: map['storageCondition'] ?? "Room Temp");
}

class Party {
  String id, name, group, phone, email, address, city, state, route, gst, dl, dlExp, pan, transport, priceLevel, defaultSeriesId, hsnCode; 
  double opBal, creditLimit; int creditDays;
  Party({required this.id, required this.name, this.group = "Sundry Debtors", this.phone = "", this.email = "", this.address = "", this.city = "", this.state = "Rajasthan", this.route = "", this.gst = "", this.dl = "", this.dlExp = "", this.pan = "", this.transport = "", this.priceLevel = "A", this.defaultSeriesId = "", this.hsnCode = "N/A", this.opBal = 0.0, this.creditLimit = 0.0, this.creditDays = 0});
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'group': group, 'phone': phone, 'email': email, 'address': address, 'city': city, 'state': state, 'route': route, 'gst': gst, 'dl': dl, 'dlExp': dlExp, 'pan': pan, 'transport': transport, 'priceLevel': priceLevel, 'defaultSeriesId': defaultSeriesId, 'hsnCode': hsnCode, 'opBal': opBal, 'creditLimit': creditLimit, 'creditDays': creditDays};
  factory Party.fromMap(Map<String, dynamic> map) => Party(id: map['id'] ?? "", name: map['name'] ?? "", group: map['group'] ?? "Sundry Debtors", phone: map['phone'] ?? "", email: map['email'] ?? "", address: map['address'] ?? "", city: map['city'] ?? "", state: map['state'] ?? "Rajasthan", route: map['route'] ?? "", gst: map['gst'] ?? "", dl: map['dl'] ?? "", dlExp: map['dlExp'] ?? "", pan: map['pan'] ?? "", transport: map['transport'] ?? "", priceLevel: map['priceLevel'] ?? "A", defaultSeriesId: map['defaultSeriesId'] ?? "", hsnCode: map['hsnCode'] ?? "N/A", opBal: (map['opBal'] ?? 0.0).toDouble(), creditLimit: (map['creditLimit'] ?? 0.0).toDouble(), creditDays: map['creditDays'] ?? 0);
}

// ===========================================================================
// 4. TRANSACTION ITEM MODELS (DUAL DISCOUNT & COPY-WITH UPDATED)
// ===========================================================================

// ===========================================================================
// 🛒 UPDATED TRANSACTION ITEM MODELS (WITH MEMORY PERSISTENCE)
// ===========================================================================

class BillItem {
  String id, medicineID, name, packing, batch, exp, hsn, sourceChallanNo, sourceChallanId, appliedRateType; 
  int srNo; 
  double mrp, qty, freeQty, rate, gstRate, cgst, sgst, igst, total, discountRupees, discountPer, rateCFormula; 
  bool isBreakage;

  BillItem({
    required this.id, required this.srNo, required this.medicineID, required this.name, required this.packing, required this.batch, required this.exp, required this.hsn, required this.mrp, required this.qty, this.freeQty = 0, required this.rate, required this.gstRate, this.cgst = 0, this.sgst = 0, this.igst = 0, required this.total, this.discountRupees = 0, 
    this.discountPer = 0.0, 
    this.isBreakage = false,
    this.sourceChallanNo = "", this.sourceChallanId = "",
    this.appliedRateType = "A", // Naya field: Choice Memory
    this.rateCFormula = 0.0     // Naya field: Formula Memory
  });

  BillItem copyWith({int? srNo, String? sourceChallanNo, String? sourceChallanId, double? discountPer, double? discountRupees, bool? isBreakage}) => BillItem(
    id: id, srNo: srNo ?? this.srNo, medicineID: medicineID, name: name, packing: packing, batch: batch, exp: exp, hsn: hsn, mrp: mrp, qty: qty, freeQty: freeQty, rate: rate, gstRate: gstRate, cgst: cgst, sgst: sgst, igst: igst, total: total, 
    discountRupees: discountRupees ?? this.discountRupees, 
    discountPer: discountPer ?? this.discountPer, 
    isBreakage: isBreakage ?? this.isBreakage,
    sourceChallanNo: sourceChallanNo ?? this.sourceChallanNo, 
    sourceChallanId: sourceChallanId ?? this.sourceChallanId,
    appliedRateType: appliedRateType, rateCFormula: rateCFormula
  );
  
  Map<String, dynamic> toMap() => {'id': id, 'srNo': srNo, 'medicineID': medicineID, 'name': name, 'packing': packing, 'batch': batch, 'exp': exp, 'hsn': hsn, 'mrp': mrp, 'qty': qty, 'freeQty': freeQty, 'rate': rate, 'gstRate': gstRate, 'cgst': cgst, 'sgst': sgst, 'igst': igst, 'total': total, 'discountRupees': discountRupees, 'discountPer': discountPer, 'isBreakage': isBreakage, 'sourceChallanNo': sourceChallanNo, 'sourceChallanId': sourceChallanId, 'appliedRateType': appliedRateType, 'rateCFormula': rateCFormula};
  
  factory BillItem.fromMap(Map<String, dynamic> map) => BillItem(
    id: map['id'] ?? "", srNo: map['srNo'] ?? 0, medicineID: map['medicineID'] ?? "", name: map['name'] ?? "", packing: map['packing'] ?? "", batch: map['batch'] ?? "", exp: map['exp'] ?? "", hsn: map['hsn'] ?? "", mrp: (map['mrp'] ?? 0.0).toDouble(), qty: (map['qty'] ?? 0.0).toDouble(), freeQty: (map['freeQty'] ?? 0.0).toDouble(), rate: (map['rate'] ?? 0.0).toDouble(), gstRate: (map['gstRate'] ?? 0.0).toDouble(), cgst: (map['cgst'] ?? 0.0).toDouble(), sgst: (map['sgst'] ?? 0.0).toDouble(), igst: (map['igst'] ?? 0.0).toDouble(), total: (map['total'] ?? 0.0).toDouble(), 
    discountRupees: (map['discountRupees'] ?? 0.0).toDouble(), 
    discountPer: (map['discountPer'] ?? 0.0).toDouble(), 
    isBreakage: map['isBreakage'] ?? false,
    sourceChallanNo: map['sourceChallanNo'] ?? "", sourceChallanId: map['sourceChallanId'] ?? "",
    appliedRateType: map['appliedRateType'] ?? "A",
    rateCFormula: (map['rateCFormula'] ?? 0.0).toDouble(),
  );
}

class PurchaseItem {
  String id, medicineID, name, packing, batch, exp, hsn, sourceChallanNo, sourceChallanId, appliedRateType; 
  int srNo; 
  double mrp, qty, freeQty, purchaseRate, gstRate, total, rateA, rateB, rateC, discountPer, discountRupees, rateCFormula;
  bool isBreakage;

  PurchaseItem({
    required this.id, required this.srNo, required this.medicineID, required this.name, required this.packing, required this.batch, required this.exp, required this.hsn, required this.mrp, required this.qty, this.freeQty = 0, required this.purchaseRate, required this.gstRate, required this.total, this.rateA = 0, this.rateB = 0, this.rateC = 0, 
    this.discountPer = 0.0, this.discountRupees = 0.0,
    this.isBreakage = false,
    this.sourceChallanNo = "", this.sourceChallanId = "",
    this.appliedRateType = "A", // Choice Memory
    this.rateCFormula = 0.0     // Formula Memory
  });

  PurchaseItem copyWith({int? srNo, String? sourceChallanNo, String? sourceChallanId, double? discountPer, double? discountRupees, bool? isBreakage}) => PurchaseItem(
    id: id, srNo: srNo ?? this.srNo, medicineID: medicineID, name: name, packing: packing, batch: batch, exp: exp, hsn: hsn, mrp: mrp, qty: qty, freeQty: freeQty, purchaseRate: purchaseRate, gstRate: gstRate, total: total, rateA: rateA, rateB: rateB, rateC: rateC, 
    discountPer: discountPer ?? this.discountPer, 
    discountRupees: discountRupees ?? this.discountRupees, 
    isBreakage: isBreakage ?? this.isBreakage,
    sourceChallanNo: sourceChallanNo ?? this.sourceChallanNo, 
    sourceChallanId: sourceChallanId ?? this.sourceChallanId,
    appliedRateType: appliedRateType, rateCFormula: rateCFormula
  );

  Map<String, dynamic> toMap() => {'id': id, 'srNo': srNo, 'medicineID': medicineID, 'name': name, 'packing': packing, 'batch': batch, 'exp': exp, 'hsn': hsn, 'mrp': mrp, 'qty': qty, 'freeQty': freeQty, 'purchaseRate': purchaseRate, 'gstRate': gstRate, 'total': total, 'rateA': rateA, 'rateB': rateB, 'rateC': rateC, 'discountPer': discountPer, 'discountRupees': discountRupees, 'isBreakage': isBreakage, 'sourceChallanNo': sourceChallanNo, 'sourceChallanId': sourceChallanId, 'appliedRateType': appliedRateType, 'rateCFormula': rateCFormula};
  
  factory PurchaseItem.fromMap(Map<String, dynamic> map) => PurchaseItem(
    id: map['id'] ?? "", srNo: map['srNo'] ?? 0, medicineID: map['medicineID'] ?? "", name: map['name'] ?? "", packing: map['packing'] ?? "", batch: map['batch'] ?? "", exp: map['exp'] ?? "", hsn: map['hsn'] ?? "", mrp: (map['mrp'] ?? 0.0).toDouble(), qty: (map['qty'] ?? 0.0).toDouble(), freeQty: (map['freeQty'] ?? 0.0).toDouble(), purchaseRate: (map['purchaseRate'] ?? 0.0).toDouble(), gstRate: (map['gstRate'] ?? 0.0).toDouble(), total: (map['total'] ?? 0.0).toDouble(), rateA: (map['rateA'] ?? 0.0).toDouble(), rateB: (map['rateB'] ?? 0.0).toDouble(), rateC: (map['rateC'] ?? 0.0).toDouble(), 
    discountPer: (map['discountPer'] ?? 0.0).toDouble(), 
    discountRupees: (map['discountRupees'] ?? 0.0).toDouble(),
    isBreakage: map['isBreakage'] ?? false,
    sourceChallanNo: map['sourceChallanNo'] ?? "", sourceChallanId: map['sourceChallanId'] ?? "",
    appliedRateType: map['appliedRateType'] ?? "A",
    rateCFormula: (map['rateCFormula'] ?? 0.0).toDouble(),
  );
}

// ===========================================================================
// 5. TRANSACTION HEADER MODELS (With P2P Support)
// ===========================================================================

class Sale { 
  String id, billNo, partyId, partyName, partyGstin, partyState, status, invoiceType, paymentMode, transporterName, transporterId, vehicleNo, salesmanName, sourceTag, partyPhone, partyEmail, partyAddress, partyCity, partyDl, partyPan; 
  DateTime date; List<BillItem> items; double totalAmount, extraDiscount, roundOff; List<String> linkedChallanIds; 
  Sale({required this.id, required this.billNo, required this.partyId, required this.date, required this.partyName, required this.partyGstin, required this.partyState, required this.items, required this.totalAmount, required this.paymentMode, this.status = "Active", this.invoiceType = "B2C", this.transporterName = "", this.transporterId = "", this.vehicleNo = "", this.salesmanName = "", this.sourceTag = "", this.partyPhone = "", this.partyEmail = "", this.partyAddress = "", this.partyCity = "", this.partyDl = "", this.partyPan = "", this.extraDiscount = 0.0, this.roundOff = 0.0, this.linkedChallanIds = const []});
  
  Map<String, dynamic> toMap() => {
    'id': id, 'billNo': billNo, 'partyId': partyId, 'date': date.toIso8601String(), 'partyName': partyName, 
    'partyGstin': partyGstin, 'partyState': partyState, 'paymentMode': paymentMode, 'totalAmount': totalAmount, 
    'status': status, 'invoiceType': invoiceType, 'transporterName': transporterName, 'transporterId': transporterId, 
    'vehicleNo': vehicleNo, 'salesmanName': salesmanName, 'items': items.map((i) => i.toMap()).toList(), 
    'linkedChallanIds': linkedChallanIds, 'extraDiscount': extraDiscount, 'roundOff': roundOff,
    'partyAddress': partyAddress, 'partyPhone': partyPhone, 'partyEmail': partyEmail, 'partyDl': partyDl, 'partyPan': partyPan, 'partyCity': partyCity, 'sourceTag': sourceTag
  };
  
  factory Sale.fromMap(Map<String, dynamic> map) => Sale(
    id: map['id'] ?? '', billNo: map['billNo'] ?? '', partyId: map['partyId'] ?? '', date: DateTime.parse(map['date'] ?? DateTime.now().toIso8601String()), 
    partyName: map['partyName'] ?? '', partyGstin: map['partyGstin'] ?? "", partyState: map['partyState'] ?? "Rajasthan", paymentMode: map['paymentMode'] ?? "CASH", 
    totalAmount: (map['totalAmount'] ?? 0.0).toDouble(), status: map['status'] ?? "Active", invoiceType: map['invoiceType'] ?? "B2C", 
    transporterName: map['transporterName'] ?? "", transporterId: map['transporterId'] ?? "", vehicleNo: map['vehicleNo'] ?? "", salesmanName: map['salesmanName'] ?? "", 
    items: (map['items'] as List?)?.map((i) => BillItem.fromMap(i)).toList() ?? [], linkedChallanIds: List<String>.from(map['linkedChallanIds'] ?? []),
    extraDiscount: (map['extraDiscount'] ?? 0.0).toDouble(), roundOff: (map['roundOff'] ?? 0.0).toDouble(),
    partyAddress: map['partyAddress'] ?? "", partyPhone: map['partyPhone'] ?? "", partyEmail: map['partyEmail'] ?? "", partyDl: map['partyDl'] ?? "", partyPan: map['partyPan'] ?? "", partyCity: map['partyCity'] ?? "", sourceTag: map['sourceTag'] ?? ""
  ); 
}

class Purchase { 
  String id, internalNo, billNo, partyId, distributorName, paymentMode, gstStatus, sourceTag; 
  DateTime date, entryDate; List<PurchaseItem> items; double totalAmount; List<String> linkedChallanIds;
  
  // 🆕 PURCHASE EXTRA DISCOUNT & ROUND OFF
  double extraDiscount;
  double roundOff;

  Purchase({
    required this.id, 
    required this.internalNo, 
    required this.billNo, 
    required this.partyId, 
    required this.date, 
    required this.entryDate, 
    required this.distributorName, 
    required this.items, 
    required this.totalAmount, 
    required this.paymentMode, 
    this.gstStatus = "Pending", 
    this.linkedChallanIds = const [], 
    this.sourceTag = "",
    this.extraDiscount = 0.0,
    this.roundOff = 0.0,
  });
  
  Map<String, dynamic> toMap() => {
    'id': id, 'internalNo': internalNo, 'billNo': billNo, 'partyId': partyId, 'date': date.toIso8601String(), 
    'entryDate': entryDate.toIso8601String(), 'distributorName': distributorName, 'paymentMode': paymentMode, 
    'gstStatus': gstStatus, 'totalAmount': totalAmount, 'items': items.map((i) => i.toMap()).toList(), 
    'linkedChallanIds': linkedChallanIds, 'sourceTag': sourceTag,
    'extraDiscount': extraDiscount, 'roundOff': roundOff
  };
  
  factory Purchase.fromMap(Map<String, dynamic> map) => Purchase(
    id: map['id'] ?? "", internalNo: map['internalNo'] ?? "", billNo: map['billNo'] ?? "", distributorName: map['distributorName'] ?? "", partyId: map['partyId'] ?? "", paymentMode: map['paymentMode'] ?? "CREDIT", gstStatus: map['gstStatus'] ?? "Pending", date: DateTime.parse(map['date'] ?? DateTime.now().toIso8601String()), entryDate: DateTime.parse(map['entryDate'] ?? DateTime.now().toIso8601String()), totalAmount: (map['totalAmount'] ?? 0.0).toDouble(), items: (map['items'] as List?)?.map((i) => PurchaseItem.fromMap(i)).toList() ?? [], sourceTag: map['sourceTag'] ?? "", linkedChallanIds: List<String>.from(map['linkedChallanIds'] ?? []),
    // 🆕 Fallbacks to load older purchase files safely
    extraDiscount: (map['extraDiscount'] ?? 0.0).toDouble(),
    roundOff: (map['roundOff'] ?? 0.0).toDouble(),
  ); 
}

class SaleChallan { 
  String id, billNo, partyId, partyName, partyGstin, partyState, status, salesmanName, remarks; DateTime date; List<BillItem> items; double totalAmount; List<ChallanSignature> sigHistory; bool isSigned;
  SaleChallan({required this.id, required this.billNo, required this.partyId, required this.date, required this.partyName, required this.partyGstin, required this.partyState, required this.items, required this.totalAmount, this.status = "Pending", this.salesmanName = "", this.remarks = "", this.sigHistory = const [], this.isSigned = false});
  Map<String, dynamic> toMap() => {'id': id, 'billNo': billNo, 'partyId': partyId, 'date': date.toIso8601String(), 'partyName': partyName, 'partyGstin': partyGstin, 'partyState': partyState, 'totalAmount': totalAmount, 'status': status, 'salesmanName': salesmanName, 'remarks': remarks, 'items': items.map((i) => i.toMap()).toList(), 'sigHistory': sigHistory.map((s) => s.toMap()).toList(), 'isSigned': isSigned};
  factory SaleChallan.fromMap(Map<String, dynamic> map) => SaleChallan(id: map['id'] ?? "", billNo: map['billNo'] ?? "", partyId: map['partyId'] ?? "", date: DateTime.parse(map['date'] ?? DateTime.now().toIso8601String()), partyName: map['partyName'] ?? "", partyGstin: map['partyGstin'] ?? "", partyState: map['partyState'] ?? "Rajasthan", totalAmount: (map['totalAmount'] ?? 0.0).toDouble(), status: map['status'] ?? "Pending", salesmanName: map['salesmanName'] ?? "", remarks: map['remarks'] ?? "", items: (map['items'] as List?)?.map((i) => BillItem.fromMap(i)).toList() ?? [], isSigned: map['isSigned'] ?? false, sigHistory: (map['sigHistory'] as List?)?.map((s) => ChallanSignature.fromMap(s)).toList() ?? []); 
}

class PurchaseChallan { 
  String id, internalNo, billNo, partyId, distributorName, status, remarks; DateTime date; List<PurchaseItem> items; double totalAmount;
  PurchaseChallan({required this.id, required this.internalNo, required this.billNo, required this.partyId, required this.date, required this.distributorName, required this.items, required this.totalAmount, this.status = "Pending", this.remarks = ""});
  Map<String, dynamic> toMap() => {'id': id, 'internalNo': internalNo, 'billNo': billNo, 'partyId': partyId, 'date': date.toIso8601String(), 'distributorName': distributorName, 'totalAmount': totalAmount, 'status': status, 'remarks': remarks, 'items': items.map((i) => i.toMap()).toList()};
  factory PurchaseChallan.fromMap(Map<String, dynamic> map) => PurchaseChallan(id: map['id'] ?? "", internalNo: map['internalNo'] ?? "", billNo: map['billNo'] ?? "", partyId: map['partyId'] ?? "", distributorName: map['distributorName'] ?? "", date: DateTime.parse(map['date'] ?? DateTime.now().toIso8601String()), totalAmount: (map['totalAmount'] ?? 0.0).toDouble(), status: map['status'] ?? "Pending", remarks: map['remarks'] ?? "", items: (map['items'] as List?)?.map((i) => PurchaseItem.fromMap(i)).toList() ?? []); 
}

class SaleReturn { 
  String id, billNo, partyName, status, returnType; 
  DateTime date; 
  List<BillItem> items; 
  double totalAmount, extraDiscount, roundOff; // Naya Fields jode gaye

  SaleReturn({
    required this.id, required this.billNo, required this.date, 
    required this.partyName, required this.items, required this.totalAmount, 
    this.status = "Active", this.returnType = "Sellable",
    this.extraDiscount = 0.0, this.roundOff = 0.0
  }); 

  Map<String, dynamic> toMap() => {
    'id': id, 'billNo': billNo, 'date': date.toIso8601String(), 
    'partyName': partyName, 'totalAmount': totalAmount, 
    'status': status, 'returnType': returnType, 
    'extraDiscount': extraDiscount, 'roundOff': roundOff,
    'items': items.map((i) => i.toMap()).toList()
  }; 

  factory SaleReturn.fromMap(Map<String, dynamic> map) => SaleReturn(
    id: map['id'] ?? "", billNo: map['billNo'] ?? "", 
    date: DateTime.parse(map['date'] ?? DateTime.now().toIso8601String()), 
    partyName: map['partyName'] ?? "", 
    totalAmount: (map['totalAmount'] ?? 0.0).toDouble(), 
    extraDiscount: (map['extraDiscount'] ?? 0.0).toDouble(),
    roundOff: (map['roundOff'] ?? 0.0).toDouble(),
    status: map['status'] ?? "Active", 
    returnType: map['returnType'] ?? "Sellable", 
    items: (map['items'] as List?)?.map((i) => BillItem.fromMap(i)).toList() ?? []
  ); 
}

class PurchaseReturn { 
  String id, billNo, distributorName, status, returnType; 
  DateTime date; 
  List<PurchaseItem> items; 
  double totalAmount, extraDiscount, roundOff; // Naya Fields

  PurchaseReturn({
    required this.id, required this.billNo, required this.distributorName, 
    required this.items, required this.totalAmount, required this.date, 
    this.status = "Active", this.returnType = "Sellable",
    this.extraDiscount = 0.0, this.roundOff = 0.0
  }); 

  Map<String, dynamic> toMap() => {
    'id': id, 'billNo': billNo, 'date': date.toIso8601String(), 
    'distributorName': distributorName, 'totalAmount': totalAmount, 
    'status': status, 'returnType': returnType, 
    'items': items.map((i) => i.toMap()).toList(),
    'extraDiscount': extraDiscount, 'roundOff': roundOff
  }; 

  factory PurchaseReturn.fromMap(Map<String, dynamic> map) => PurchaseReturn(
    id: map['id'] ?? "", billNo: map['billNo'] ?? "", 
    date: DateTime.parse(map['date'] ?? DateTime.now().toIso8601String()), 
    distributorName: map['distributorName'] ?? "", 
    totalAmount: (map['totalAmount'] ?? 0.0).toDouble(), 
    status: map['status'] ?? "Active", 
    returnType: map['returnType'] ?? "Sellable", 
    extraDiscount: (map['extraDiscount'] ?? 0.0).toDouble(),
    roundOff: (map['roundOff'] ?? 0.0).toDouble(),
    items: (map['items'] as List?)?.map((i) => PurchaseItem.fromMap(i)).toList() ?? []
  ); 
}

// 6. SYSTEM
class LogEntry { String id, action, details; DateTime time; LogEntry({required this.id, required this.action, required this.details, required this.time}); Map<String, dynamic> toMap() => {'id': id, 'action': action, 'details': details, 'time': time.toIso8601String()}; factory LogEntry.fromMap(Map<String, dynamic> map) => LogEntry(id: map['id'] ?? "", action: map['action'] ?? "", details: map['details'] ?? "", time: DateTime.parse(map['time'] ?? DateTime.now().toIso8601String())); }
class Voucher {
  String id, type, voucherNo, status; // Added status: 'Active' or 'Cancelled'
  DateTime date;
  String partyId, partyName, paymentMode, narration;
  double amount;
  List<String> linkedBillNumbers; 
  String chequeNo;               
  String bankName;               
  String depositedIn;            
  DateTime? chequeDate;          
  double roundOff;

  Voucher({
    required this.id,
    required this.type,
    required this.voucherNo,
    required this.date,
    required this.partyId,
    required this.partyName,
    required this.amount,
    required this.paymentMode,
    this.status = "Active", // Default Active
    this.narration = "",
    this.linkedBillNumbers = const [],
    this.chequeNo = "",
    this.bankName = "",
    this.depositedIn = "",
    this.chequeDate,
    this.roundOff = 0.0,
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'type': type, 'voucherNo': voucherNo, 'date': date.toIso8601String(),
    'partyId': partyId, 'partyName': partyName, 'amount': amount,
    'paymentMode': paymentMode, 'narration': narration, 'status': status,
    'linkedBillNumbers': linkedBillNumbers,
    'chequeNo': chequeNo, 'bankName': bankName, 'depositedIn': depositedIn,
    'chequeDate': chequeDate?.toIso8601String(), 'roundOff': roundOff
  };

  factory Voucher.fromMap(Map<String, dynamic> map) => Voucher(
    id: map['id'] ?? "", type: map['type'] ?? "",
    voucherNo: map['voucherNo'] ?? "LEGACY",
    date: DateTime.parse(map['date'] ?? DateTime.now().toIso8601String()),
    partyId: map['partyId'] ?? "", partyName: map['partyName'] ?? "",
    amount: (map['amount'] ?? 0.0).toDouble(),
    paymentMode: map['paymentMode'] ?? "Cash", 
    narration: map['narration'] ?? "",
    status: map['status'] ?? "Active",
    linkedBillNumbers: List<String>.from(map['linkedBillNumbers'] ?? []),
    chequeNo: map['chequeNo'] ?? "", bankName: map['bankName'] ?? "",
    depositedIn: map['depositedIn'] ?? "",
    chequeDate: map['chequeDate'] != null ? DateTime.parse(map['chequeDate']) : null,
    roundOff: (map['roundOff'] ?? 0.0).toDouble(),
  );
}
  
class ChequeEntry { String id, partyName, billNo, chequeNo, partyBank, depositBank, status, remark; DateTime date, chequeDate; double amount; ChequeEntry({required this.id, required this.partyName, this.billNo = "", required this.amount, required this.chequeNo, required this.date, required this.chequeDate, this.partyBank = "", this.depositBank = "", this.status = "Received", this.remark = ""}); Map<String, dynamic> toMap() => {'id': id, 'partyName': partyName, 'billNo': billNo, 'amount': amount, 'chequeNo': chequeNo, 'date': date.toIso8601String(), 'chequeDate': chequeDate.toIso8601String(), 'partyBank': partyBank, 'depositBank': depositBank, 'status': status, 'remark': remark}; factory ChequeEntry.fromMap(Map<String, dynamic> map) => ChequeEntry(id: map['id'] ?? "", partyName: map['partyName'] ?? "", billNo: map['billNo'] ?? "", amount: (map['amount'] ?? 0.0).toDouble(), chequeNo: map['chequeNo'] ?? "", date: DateTime.parse(map['date'] ?? DateTime.now().toIso8601String()), chequeDate: DateTime.parse(map['chequeDate'] ?? DateTime.now().toIso8601String()), partyBank: map['partyBank'] ?? "", depositBank: map['depositBank'] ?? "", status: map['status'] ?? "Received", remark: map['remark'] ?? ""); }
class ShortageItem { String id, medicineId, medicineName, companyName, distributorName, customerName, source; double qtyRequired, currentStock; DateTime date; Map<String, dynamic> toMap() => {'id': id, 'medicineId': medicineId, 'medicineName': medicineName, 'companyName': companyName, 'distributorName': distributorName, 'customerName': customerName, 'source': source, 'qtyRequired': qtyRequired, 'currentStock': currentStock, 'date': date.toIso8601String()}; ShortageItem({required this.id, required this.medicineId, required this.medicineName, required this.companyName, this.distributorName = "", this.customerName = "", this.source = "Manual", required this.qtyRequired, required this.currentStock, required this.date}); factory ShortageItem.fromMap(Map<String, dynamic> map) => ShortageItem(id: map['id'] ?? "", medicineId: map['medicineId'] ?? "", medicineName: map['medicineName'] ?? "", companyName: map['companyId'] ?? "N/A", distributorName: map['distributorName'] ?? "", customerName: map['customerName'] ?? "", source: map['source'] ?? "Manual", qtyRequired: (map['qtyRequired'] ?? 0.0).toDouble(), currentStock: (map['currentStock'] ?? 0.0).toDouble(), date: DateTime.parse(map['date'] ?? DateTime.now().toIso8601String())); }
class ModuleAction { final String title; final IconData icon; final Color color; final Widget? targetScreen; final String? navModule; ModuleAction({required this.title, required this.icon, required this.color, this.targetScreen, this.navModule}); }
