// FILE: lib/gst/gst_diary/gst_diary_models.dart

/// Represents a persistent GST Settlement session with deduction tracking
class GstDiarySession {
  final String id;
  final String title;
  final int createdAt;
  final String fromDate;
  final String toDate;
  final List<String> purchasePartyIds;
  final List<String> salePartyIds;
  final double totalPurchaseItc;
  final double totalSaleOutputGst;
  final double netGstPayable;
  final double deductedAmount;
  final String status; // 'DEDUCTED', 'SETTLED', 'OPEN'
  final String remarks;
  final String createdBy;

  GstDiarySession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.fromDate,
    required this.toDate,
    this.purchasePartyIds = const [],
    this.salePartyIds = const [],
    required this.totalPurchaseItc,
    required this.totalSaleOutputGst,
    required this.netGstPayable,
    required this.deductedAmount,
    this.status = 'DEDUCTED',
    this.remarks = '',
    this.createdBy = 'Admin',
  });

  GstDiarySession copyWith({
    String? title,
    double? deductedAmount,
    String? status,
    String? remarks,
  }) {
    return GstDiarySession(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      fromDate: fromDate,
      toDate: toDate,
      purchasePartyIds: purchasePartyIds,
      salePartyIds: salePartyIds,
      totalPurchaseItc: totalPurchaseItc,
      totalSaleOutputGst: totalSaleOutputGst,
      netGstPayable: netGstPayable,
      deductedAmount: deductedAmount ?? this.deductedAmount,
      status: status ?? this.status,
      remarks: remarks ?? this.remarks,
      createdBy: createdBy,
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
    'totalPurchaseItc': totalPurchaseItc,
    'totalSaleOutputGst': totalSaleOutputGst,
    'netGstPayable': netGstPayable,
    'deductedAmount': deductedAmount,
    'status': status,
    'remarks': remarks,
    'createdBy': createdBy,
  };

  factory GstDiarySession.fromMap(Map<String, dynamic> map) => GstDiarySession(
    id: map['id']?.toString() ?? '',
    title: map['title']?.toString() ?? 'Session',
    createdAt: int.tryParse(map['createdAt']?.toString() ?? '0') ?? 0,
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
    totalPurchaseItc: (map['totalPurchaseItc'] ?? 0.0).toDouble(),
    totalSaleOutputGst: (map['totalSaleOutputGst'] ?? 0.0).toDouble(),
    netGstPayable: (map['netGstPayable'] ?? 0.0).toDouble(),
    deductedAmount: (map['deductedAmount'] ?? 0.0).toDouble(),
    status: map['status']?.toString() ?? 'DEDUCTED',
    remarks: map['remarks']?.toString() ?? '',
    createdBy: map['createdBy']?.toString() ?? 'Admin',
  );
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

/// Represents individual voucher / bill rows
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
  });
}
