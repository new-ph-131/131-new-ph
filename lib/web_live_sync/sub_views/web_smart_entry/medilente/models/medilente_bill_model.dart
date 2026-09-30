class MedilenteItem {
  final int srNo;
  final String hsn;
  final String productName;
  String pack;
  double qty;
  double freeQty;
  final String batch;
  final String mfg;
  final String exp;
  double netMrp;
  double oldMrp;
  double rate;
  final double discountPer;
  final double igstRate;
  double igstValue;
  double amount;
  int conversionFactor;
  String originalPack;

  MedilenteItem({
    required this.srNo,
    required this.hsn,
    required this.productName,
    required this.pack,
    required this.qty,
    this.freeQty = 0.0,
    required this.batch,
    required this.mfg,
    required this.exp,
    required this.netMrp,
    required this.oldMrp,
    required this.rate,
    this.discountPer = 0.0,
    required this.igstRate,
    required this.igstValue,
    required this.amount,
    this.conversionFactor = 1,
    this.originalPack = "",
  });

  Map<String, dynamic> toMap() => {
    'srNo': srNo,
    'hsn': hsn,
    'productName': productName,
    'pack': pack,
    'qty': qty,
    'freeQty': freeQty,
    'batch': batch,
    'mfg': mfg,
    'exp': exp,
    'netMrp': netMrp,
    'oldMrp': oldMrp,
    'rate': rate,
    'discountPer': discountPer,
    'igstRate': igstRate,
    'igstValue': igstValue,
    'amount': amount,
    'conversionFactor': conversionFactor,
    'originalPack': originalPack,
  };
}

class MedilenteBill {
  final String invoiceNo;
  final String invoiceDate;
  final String supplierName;
  final String supplierGstin;
  final String supplierPan;
  final String supplierDl;
  final String supplierEmail;
  final String supplierPhone;
  final String supplierAddress;
  final String buyerName;
  final String buyerGstin;
  final List<MedilenteItem> items;
  final double taxableTotal;
  final double igstTotal;
  final double roundOff;
  final double grandTotal;

  MedilenteBill({
    required this.invoiceNo,
    required this.invoiceDate,
    required this.supplierName,
    required this.supplierGstin,
    required this.supplierPan,
    required this.supplierDl,
    required this.supplierEmail,
    required this.supplierPhone,
    required this.supplierAddress,
    required this.buyerName,
    required this.buyerGstin,
    required this.items,
    required this.taxableTotal,
    required this.igstTotal,
    required this.roundOff,
    required this.grandTotal,
  });
}
