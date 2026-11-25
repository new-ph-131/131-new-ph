import 'package:flutter_test/flutter_test.dart';
import 'package:pharoah_erp/logic/return_history_engine.dart';
import 'package:pharoah_erp/models.dart';

void main() {
  Medicine makeMed({String id = 'MED_X', String name = 'Amoxycillin 500'}) =>
      Medicine(
        id: id,
        name: name,
        packing: '10x10',
        mrp: 120.0,
        purRate: 70.0,
        rateA: 90.0,
        gst: 12.0,
        hsnCode: '3004',
      );

  BillItem makeSaleItem({
    required String id,
    required String medId,
    required String name,
    required String batch,
    double qty = 10.0,
    double freeQty = 0.0,
    double rate = 90.0,
    double discPer = 10.0,
    String origBillNo = '',
    DateTime? origBillDate,
  }) {
    final gross = qty * rate;
    final discRs = gross * (discPer / 100.0);
    final taxable = gross - discRs;
    final tax = taxable * 0.12;
    return BillItem(
      id: id,
      srNo: 1,
      medicineID: medId,
      name: name,
      packing: '10x10',
      batch: batch,
      exp: '12/28',
      hsn: '3004',
      mrp: 120.0,
      qty: qty,
      freeQty: freeQty,
      rate: rate,
      gstRate: 12.0,
      cgst: tax / 2,
      sgst: tax / 2,
      total: taxable + tax,
      discountPer: discPer,
      discountRupees: discRs,
      origBillNo: origBillNo,
      origBillDate: origBillDate,
    );
  }

  PurchaseItem makePurItem({
    required String id,
    required String medId,
    required String name,
    required String batch,
    double qty = 10.0,
    double freeQty = 0.0,
    double rate = 70.0,
    double discPer = 5.0,
    String origBillNo = '',
    DateTime? origBillDate,
  }) {
    final gross = qty * rate;
    final discRs = gross * (discPer / 100.0);
    final taxable = gross - discRs;
    final tax = taxable * 0.12;
    return PurchaseItem(
      id: id,
      srNo: 1,
      medicineID: medId,
      name: name,
      packing: '10x10',
      batch: batch,
      exp: '12/28',
      hsn: '3004',
      mrp: 120.0,
      qty: qty,
      freeQty: freeQty,
      purchaseRate: rate,
      gstRate: 12.0,
      total: taxable + tax,
      discountPer: discPer,
      discountRupees: discRs,
      origBillNo: origBillNo,
      origBillDate: origBillDate,
    );
  }

  test('Groups 50 repeated sales of same batch into 1 Master Batch Card and computes returnable balance accurately', () {
    final med = makeMed();
    final sales = List.generate(50, (i) {
      final num = i + 1;
      final dt = DateTime(2026, 1, 1).add(Duration(days: i));
      return Sale(
        id: 'S-$num',
        billNo: 'INV-$num',
        partyId: 'P1',
        date: dt,
        partyName: 'Alpha Pharma',
        partyGstin: '08AAAAA0000A1Z5',
        partyState: 'Rajasthan',
        paymentMode: 'CREDIT',
        totalAmount: 1000.0,
        items: [
          makeSaleItem(
            id: 'SI-$num',
            medId: med.id,
            name: med.name,
            batch: 'B-101',
            qty: 4.0,
            freeQty: 1.0,
          ),
        ],
      );
    });

    // Should ignore Cancelled and Deleted sales
    sales.add(Sale(
      id: 'S-CANCEL',
      billNo: 'INV-CANCEL',
      partyId: 'P1',
      date: DateTime(2026, 3, 1),
      partyName: 'Alpha Pharma',
      partyGstin: '08AAAAA0000A1Z5',
      partyState: 'Rajasthan',
      paymentMode: 'CREDIT',
      status: 'Cancelled',
      totalAmount: 500.0,
      items: [makeSaleItem(id: 'SC1', medId: med.id, name: med.name, batch: 'B-101', qty: 10)],
    ));
    sales.add(Sale(
      id: 'S-DEL',
      billNo: 'INV-DEL',
      partyId: 'P1',
      date: DateTime(2026, 3, 2),
      partyName: 'Alpha Pharma',
      partyGstin: '08AAAAA0000A1Z5',
      partyState: 'Rajasthan',
      paymentMode: 'CREDIT',
      isDeleted: 1,
      totalAmount: 500.0,
      items: [makeSaleItem(id: 'SD1', medId: med.id, name: med.name, batch: 'B-101', qty: 10)],
    ));

    // Active Credit Note returning 3 from INV-50
    final saleReturns = [
      SaleReturn(
        id: 'CN-1',
        billNo: 'TXN-1',
        date: DateTime(2026, 3, 5),
        partyId: 'P1',
        partyName: 'Alpha Pharma',
        totalAmount: 300.0,
        items: [
          makeSaleItem(
            id: 'CNI-1',
            medId: med.id,
            name: med.name,
            batch: 'B-101',
            qty: 3.0,
            origBillNo: 'INV-50',
          ),
        ],
      ),
      // Cancelled Credit Note must be ignored
      SaleReturn(
        id: 'CN-CANC',
        billNo: 'TXN-2',
        date: DateTime(2026, 3, 6),
        partyId: 'P1',
        partyName: 'Alpha Pharma',
        status: 'Cancelled',
        totalAmount: 300.0,
        items: [
          makeSaleItem(
            id: 'CNI-CANC',
            medId: med.id,
            name: med.name,
            batch: 'B-101',
            qty: 9.0,
            origBillNo: 'INV-49',
          ),
        ],
      ),
    ];

    // Current cart already has 2 pcs from INV-49
    final currentCart = [
      makeSaleItem(
        id: 'CART-1',
        medId: med.id,
        name: med.name,
        batch: 'B-101',
        qty: 2.0,
        origBillNo: 'INV-49',
      ),
    ];

    final groups = ReturnHistoryEngine.buildBatchGroups(
      isSale: true,
      partyId: 'P1',
      partyName: 'Alpha Pharma',
      medicineId: med.id,
      medicineName: med.name,
      sales: sales,
      purchases: const [],
      saleReturns: saleReturns,
      purchaseReturns: const [],
      currentCartItems: currentCart,
    );

    expect(groups.length, equals(1));
    final g = groups.first;
    expect(g.batch, equals('B-101'));
    expect(g.billCount, equals(50));
    expect(g.totalBilledQty, equals(200.0)); // 50 * 4
    expect(g.totalBilledFree, equals(50.0)); // 50 * 1
    expect(g.alreadyReturnedQty, equals(5.0)); // 3 (CN-1) + 2 (cart)
    expect(g.netReturnableQty, equals(195.0));

    // When modifying CN-1 (excludeNoteId: 'CN-1'), its 3 pcs are freed back!
    final modGroups = ReturnHistoryEngine.buildBatchGroups(
      isSale: true,
      partyId: 'P1',
      partyName: 'Alpha Pharma',
      medicineId: med.id,
      medicineName: med.name,
      sales: sales,
      purchases: const [],
      saleReturns: saleReturns,
      purchaseReturns: const [],
      currentCartItems: const [],
      excludeNoteId: 'CN-1',
    );
    expect(modGroups.first.alreadyReturnedQty, equals(0.0));
    expect(modGroups.first.netReturnableQty, equals(200.0));
  });

  test('Auto-Split LIFO & FIFO allocates across bills and flags over-return', () {
    final med = makeMed();
    final sales = [
      Sale(
        id: 'S1',
        billNo: 'INV-1',
        partyId: 'P1',
        date: DateTime(2026, 1, 10),
        partyName: 'Alpha Pharma',
        partyGstin: '',
        partyState: 'Rajasthan',
        paymentMode: 'CREDIT',
        totalAmount: 500,
        items: [makeSaleItem(id: '1', medId: med.id, name: med.name, batch: 'B1', qty: 5)],
      ),
      Sale(
        id: 'S2',
        billNo: 'INV-2',
        partyId: 'P1',
        date: DateTime(2026, 2, 10),
        partyName: 'Alpha Pharma',
        partyGstin: '',
        partyState: 'Rajasthan',
        paymentMode: 'CREDIT',
        totalAmount: 400,
        items: [makeSaleItem(id: '2', medId: med.id, name: med.name, batch: 'B1', qty: 4)],
      ),
    ];

    final groups = ReturnHistoryEngine.buildBatchGroups(
      isSale: true,
      partyId: 'P1',
      partyName: 'Alpha Pharma',
      medicineId: med.id,
      medicineName: med.name,
      sales: sales,
      purchases: const [],
      saleReturns: const [],
      purchaseReturns: const [],
    );

    final g = groups.first;
    // LIFO (newestFirst: true): 6 -> INV-2 gets 4, INV-1 gets 2
    final lifo = ReturnHistoryEngine.allocateReturnQty(
      group: g,
      requestedQty: 6.0,
      newestFirst: true,
    );
    expect(lifo.hasOverReturn, isFalse);
    expect(lifo.allocations.length, equals(2));
    expect(lifo.allocations[0].line.billNo, equals('INV-2'));
    expect(lifo.allocations[0].allocatedQty, equals(4.0));
    expect(lifo.allocations[1].line.billNo, equals('INV-1'));
    expect(lifo.allocations[1].allocatedQty, equals(2.0));

    // FIFO (newestFirst: false): 6 -> INV-1 gets 5, INV-2 gets 1
    final fifo = ReturnHistoryEngine.allocateReturnQty(
      group: g,
      requestedQty: 6.0,
      newestFirst: false,
    );
    expect(fifo.hasOverReturn, isFalse);
    expect(fifo.allocations[0].line.billNo, equals('INV-1'));
    expect(fifo.allocations[0].allocatedQty, equals(5.0));
    expect(fifo.allocations[1].line.billNo, equals('INV-2'));
    expect(fifo.allocations[1].allocatedQty, equals(1.0));

    // Over-return (12 > 9)
    final over = ReturnHistoryEngine.allocateReturnQty(
      group: g,
      requestedQty: 12.0,
      newestFirst: true,
    );
    expect(over.hasOverReturn, isTrue);
    expect(over.allocations[0].line.billNo, equals('INV-2'));
    expect(over.allocations[0].allocatedQty, equals(7.0)); // 4 + 3 extra
    expect(over.allocations[1].line.billNo, equals('INV-1'));
    expect(over.allocations[1].allocatedQty, equals(5.0));
  });

  test('Purchase batch grouping & getRecentPartyBills works for Debit Note', () {
    final med = makeMed();
    final purchases = [
      Purchase(
        id: 'PU1',
        internalNo: 'PUR-1',
        billNo: 'SUP-101',
        partyId: 'SUP1',
        date: DateTime(2026, 2, 1),
        entryDate: DateTime(2026, 2, 1),
        distributorName: 'Metro Distributors',
        paymentMode: 'CREDIT',
        totalAmount: 1000.0,
        items: [
          makePurItem(id: 'PI1', medId: med.id, name: med.name, batch: 'LOT-9', qty: 10),
        ],
      ),
      Purchase(
        id: 'PU2',
        internalNo: 'PUR-2',
        billNo: 'SUP-102',
        partyId: 'SUP1',
        date: DateTime(2026, 2, 15),
        entryDate: DateTime(2026, 2, 15),
        distributorName: 'Metro Distributors',
        paymentMode: 'CREDIT',
        totalAmount: 1000.0,
        items: [
          makePurItem(id: 'PI2', medId: med.id, name: med.name, batch: 'LOT-9', qty: 10),
        ],
      ),
    ];
    final purReturns = [
      PurchaseReturn(
        id: 'DN1',
        billNo: 'DN-1',
        date: DateTime(2026, 2, 20),
        partyId: 'SUP1',
        distributorName: 'Metro Distributors',
        totalAmount: 200.0,
        items: [
          makePurItem(
            id: 'DNI1',
            medId: med.id,
            name: med.name,
            batch: 'LOT-9',
            qty: 3.0,
            origBillNo: 'SUP-102',
          ),
        ],
      ),
    ];

    final groups = ReturnHistoryEngine.buildBatchGroups(
      isSale: false,
      partyId: 'SUP1',
      partyName: 'Metro Distributors',
      medicineId: med.id,
      medicineName: med.name,
      sales: const [],
      purchases: purchases,
      saleReturns: const [],
      purchaseReturns: purReturns,
    );
    expect(groups.length, equals(1));
    expect(groups.first.billCount, equals(2));
    expect(groups.first.netReturnableQty, equals(17.0));

    final recent = ReturnHistoryEngine.getRecentPartyBills(
      isSale: false,
      partyId: 'SUP1',
      partyName: 'Metro Distributors',
      sales: const [],
      purchases: purchases,
      saleReturns: const [],
      purchaseReturns: purReturns,
    );
    expect(recent.length, equals(2));
    expect(recent.first.billNo, equals('SUP-102'));
    expect(recent.first.lines.first.availableQty, equals(7.0));
  });

  test('recalcBillItemQty & recalcPurchaseItemQty preserve discount percentage', () {
    final saleItem = makeSaleItem(
      id: '1',
      medId: 'M1',
      name: 'Med',
      batch: 'B1',
      qty: 10,
      rate: 100,
      discPer: 10,
    );
    final updatedSale = ReturnHistoryEngine.recalcBillItemQty(
      saleItem,
      qty: 5,
      isLocal: true,
      isCommercial: false,
    );
    expect(updatedSale.qty, equals(5.0));
    expect(updatedSale.discountRupees, equals(50.0)); // 10% of 500
    expect(updatedSale.total, equals(504.0)); // 450 + 12% GST (54)

    final purItem = makePurItem(
      id: '2',
      medId: 'M1',
      name: 'Med',
      batch: 'B1',
      qty: 10,
      rate: 100,
      discPer: 20,
    );
    final updatedPur = ReturnHistoryEngine.recalcPurchaseItemQty(
      purItem,
      qty: 4,
      isCommercial: true,
    );
    expect(updatedPur.qty, equals(4.0));
    expect(updatedPur.discountRupees, equals(80.0)); // 20% of 400
    expect(updatedPur.total, equals(320.0)); // commercial -> 0 GST
  });
}
