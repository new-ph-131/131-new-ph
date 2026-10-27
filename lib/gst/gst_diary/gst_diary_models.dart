// FILE: lib/gst/gst_diary/gst_diary_models.dart

/// Represents a persistent GST Settlement session with deduction tracking, D1 LWW versioning, and audit snapshot
class GstDiarySession {
  String id;
  String title;
  int createdAt;
  String fromDate;
  String toDate;
  List<String> purchasePartyIds;
  List<String> salePartyIds;
  List<String> purchasePartyNames;
  List<String> salePartyNames;
  List<String> includedBillIds;
  double totalPurchaseTaxable;
  double totalPurchaseItc;
  double totalSaleTaxable;
  double totalSaleOutputGst;
  double netGstPayable;
  double deductedAmount;
  int totalBillsCount;
  String status; // 'DEDUCTED', 'SETTLED', 'OPEN'
  String remarks;
  String createdBy;
  int version;
  int updatedAt;
  int isDeleted;

  GstDiarySession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.fromDate,
    required this.toDate,
    this.purchasePartyIds = const [],
    this.salePartyIds = const [],
    this.purchasePartyNames = const [],
    this.salePartyNames = const [],
    this.includedBillIds = const [],
    this.totalPurchaseTaxable = 0.0,
    required this.totalPurchaseItc,
    this.totalSaleTaxable = 0.0,
    required this.totalSaleOutputGst,
    required this.netGstPayable,
    required this.deductedAmount,
    this.totalBillsCount = 0,
    this.status = 'DEDUCTED',
    this.remarks = '',
    this.createdBy = 'Admin',
    this.version = 1,
    int? updatedAt,
    this.isDeleted = 0,
  }) : updatedAt = updatedAt ?? createdAt;

  GstDiarySession copyWith({
    String? title,
    double? deductedAmount,
    String? status,
    String? remarks,
    int? version,
    int? updatedAt,
    int? isDeleted,
  }) {
    return GstDiarySession(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      fromDate: fromDate,
      toDate: toDate,
      purchasePartyIds: purchasePartyIds,
      salePartyIds: salePartyIds,
      purchasePartyNames: purchasePartyNames,
      salePartyNames: salePartyNames,
      includedBillIds: includedBillIds,
      totalPurchaseTaxable: totalPurchaseTaxable,
      totalPurchaseItc: totalPurchaseItc,
      totalSaleTaxable: totalSaleTaxable,
      totalSaleOutputGst: totalSaleOutputGst,
      netGstPayable: netGstPayable,
      deductedAmount: deductedAmount ?? this.deductedAmount,
      totalBillsCount: totalBillsCount,
      status: status ?? this.status,
      remarks: remarks ?? this.remarks,
      createdBy: createdBy,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'createdAt': createdAt,
    'fromDate': fromDate,
    'toDate': toDate,
    'purchasePartyIds': purchasePartyIds,
    'salePartyIds': salePartyIds,
    'purchasePartyNames': purchasePartyNames,
    'salePartyNames': salePartyNames,
    'includedBillIds': includedBillIds,
    'totalPurchaseTaxable': totalPurchaseTaxable,
    'totalPurchaseItc': totalPurchaseItc,
    'totalSaleTaxable': totalSaleTaxable,
    'totalSaleOutputGst': totalSaleOutputGst,
    'netGstPayable': netGstPayable,
    'deductedAmount': deductedAmount,
    'totalBillsCount': totalBillsCount,
    'status': status,
    'remarks': remarks,
    'createdBy': createdBy,
    'version': version,
    'updatedAt': updatedAt,
    'isDeleted': isDeleted,
  };

  factory GstDiarySession.fromMap(Map<String, dynamic> map) {
    final int created = int.tryParse(map['createdAt']?.toString() ?? '0') ?? 0;
    final int updated = int.tryParse(map['updatedAt']?.toString() ?? map['updated_at']?.toString() ?? '0') ?? created;
    return GstDiarySession(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Session',
      createdAt: created,
      fromDate: map['fromDate']?.toString() ?? '',
      toDate: map['toDate']?.toString() ?? '',
      purchasePartyIds: (map['purchasePartyIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      salePartyIds: (map['salePartyIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      purchasePartyNames: (map['purchasePartyNames'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      salePartyNames: (map['salePartyNames'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      includedBillIds: (map['includedBillIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      totalPurchaseTaxable: (map['totalPurchaseTaxable'] ?? 0.0).toDouble(),
      totalPurchaseItc: (map['totalPurchaseItc'] ?? 0.0).toDouble(),
      totalSaleTaxable: (map['totalSaleTaxable'] ?? 0.0).toDouble(),
      totalSaleOutputGst: (map['totalSaleOutputGst'] ?? 0.0).toDouble(),
      netGstPayable: (map['netGstPayable'] ?? 0.0).toDouble(),
      deductedAmount: (map['deductedAmount'] ?? 0.0).toDouble(),
      totalBillsCount: int.tryParse(map['totalBillsCount']?.toString() ?? '0') ??
          ((map['includedBillIds'] as List<dynamic>?)?.length ?? 0),
      status: map['status']?.toString() ?? 'DEDUCTED',
      remarks: map['remarks']?.toString() ?? '',
      createdBy: map['createdBy']?.toString() ?? 'Admin',
      version: int.tryParse(map['version']?.toString() ?? '1') ?? 1,
      updatedAt: updated,
      isDeleted: int.tryParse(map['isDeleted']?.toString() ?? map['is_deleted']?.toString() ?? '0') ?? 0,
    );
  }
}

/// Represents product-wise purchase vs sale GST calculation
class GstProductDifferenceRow {
  final String productId;
  final String productName;
  final String packing;
  final String hsn;

  final double purchaseQty;
  final double purchaseTaxable;
  final double purchaseGst; // Input Tax Credit
  final double avgPurchaseGstPerUnit;

  final double saleQty;
  final double saleTaxable;
  final double saleGst; // Output Liability
  final double avgSaleGstPerUnit;

  final double eligibleItcForSoldUnits;
  final double gstDifference; // Output - Eligible ITC

  String get selectionKey =>
      (productId.isNotEmpty ? productId : productName.trim().toLowerCase());

  GstProductDifferenceRow({
    required this.productId,
    required this.productName,
    required this.packing,
    required this.hsn,
    required this.purchaseQty,
    required this.purchaseTaxable,
    required this.purchaseGst,
    required this.avgPurchaseGstPerUnit,
    required this.saleQty,
    required this.saleTaxable,
    required this.saleGst,
    required this.avgSaleGstPerUnit,
    required this.eligibleItcForSoldUnits,
    required this.gstDifference,
  });
}

/// Represents party-wise aggregated GST contributions
class GstPartyDifferenceRow {
  final String partyId;
  final String partyName;
  final String gstin;
  final String type; // 'PURCHASE_SUPPLIER' or 'SALE_CUSTOMER'
  final int totalBills;
  final double taxableAmount;
  final double cgst;
  final double sgst;
  final double igst;
  final double totalGst;

  String get selectionKey =>
      '${type}_${partyId.isNotEmpty ? partyId : partyName.trim().toLowerCase()}';

  GstPartyDifferenceRow({
    required this.partyId,
    required this.partyName,
    required this.gstin,
    required this.type,
    required this.totalBills,
    required this.taxableAmount,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.totalGst,
  });
}

/// Represents individual voucher / bill rows with session deduction status
class GstBillDifferenceRow {
  final String billId;
  final String billNo;
  final String date;
  final String partyName;
  final String partyGstin;
  final String voucherType; // 'PURCHASE' or 'SALE'
  final double taxableAmount;
  final double gstAmount;
  final double netBillAmount;
  final bool isDeducted;
  final String deductedSessionName;
  final String deductedSessionId;

  GstBillDifferenceRow({
    required this.billId,
    required this.billNo,
    required this.date,
    required this.partyName,
    required this.partyGstin,
    required this.voucherType,
    required this.taxableAmount,
    required this.gstAmount,
    required this.netBillAmount,
    this.isDeducted = false,
    this.deductedSessionName = '',
    this.deductedSessionId = '',
  });
}
