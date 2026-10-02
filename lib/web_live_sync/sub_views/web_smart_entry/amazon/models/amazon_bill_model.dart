class AmazonItem {
  final int srNo;
  final String hsn;
  final String productName;
  String pack;
  double qty;
  double freeQty;
  final String batch;
  final String mfg;
  final String exp;
  double mrp;
  double rate;
  final double discountPer;
  final double sgstRate;
  final double cgstRate;
  final double igstRate;
  final double totalTaxRate;
  double taxAmount;
  double amount;
  int conversionFactor;
  String originalPack;

  AmazonItem({
    required this.srNo,
    required this.hsn,
    required this.productName,
    required this.pack,
    required this.qty,
    this.freeQty = 0.0,
    required this.batch,
    required this.mfg,
    required this.exp,
    required this.mrp,
    required this.rate,
    this.discountPer = 0.0,
    required this.sgstRate,
    required this.cgstRate,
    required this.igstRate,
    required this.totalTaxRate,
    required this.taxAmount,
    required this.amount,
    this.conversionFactor = 1,
    this.originalPack = "",
  });
}

class AmazonBill {
  final String invoiceNo;
  final String invoiceDate;
  final String supplierName;
  final String supplierGstin;
  final String supplierPan;
  final String supplierDl;
  final String supplierPhone;
  final String supplierAddress;
  final String buyerName;
  final String buyerGstin;
  final List<AmazonItem> items;
  final double taxableTotal;
  final double sgstTotal;
  final double cgstTotal;
  final double totalTax;
  final double roundOff;
  final double grandTotal;

  AmazonBill({
    required this.invoiceNo,
    required this.invoiceDate,
    required this.supplierName,
    required this.supplierGstin,
    required this.supplierPan,
    required this.supplierDl,
    required this.supplierPhone,
    required this.supplierAddress,
    required this.buyerName,
    required this.buyerGstin,
    required this.items,
    required this.taxableTotal,
    required this.sgstTotal,
    required this.cgstTotal,
    required this.totalTax,
    required this.roundOff,
    required this.grandTotal,
  });
}
