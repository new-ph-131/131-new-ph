// FILE: lib/web_live_sync/sub_views/web_stock/models/stock_column_model.dart

enum StockColumnId {
  srNo,
  systemId,
  name,
  packing,
  drugForm,
  company,
  rackNo,
  gst,
  currentStock,
  purRate,
  mrp,
  purValuation,
  mrpValuation,
  batchCount,
  nearestExpiry,
  priceVariance,
  actions,
}

enum FreezePaneOption {
  none,
  idAndName,
  idNameAndCompany,
  idNameAndPack,
}

class StockColumnDef {
  final StockColumnId id;
  final String title;
  final double width;
  final bool isNumeric;
  bool isVisible;

  StockColumnDef({
    required this.id,
    required this.title,
    required this.width,
    this.isNumeric = false,
    this.isVisible = true,
  });

  StockColumnDef copyWith({
    bool? isVisible,
    double? width,
  }) {
    return StockColumnDef(
      id: id,
      title: title,
      width: width ?? this.width,
      isNumeric: isNumeric,
      isVisible: isVisible ?? this.isVisible,
    );
  }
}
