// FILE: lib/web_live_sync/sub_views/web_returns/debit_note/logic/debit_note_controller.dart
// ignore_for_file: prefer_const_constructors, unnecessary_const

import 'package:flutter/material.dart';
import '../../../../web_models.dart';
import '../../../../pharoah_web_manager.dart';
import '../../../../web_app_date_logic.dart';
import '../../../../web_pdf_router_service.dart';
import '../mechanism/debit_note_mechanism.dart';

class DebitNoteController extends ChangeNotifier {
  final TextEditingController noteNoC = TextEditingController();
  final TextEditingController extraDiscC = TextEditingController(text: "0");
  final TextEditingController remarksC = TextEditingController();
  final TextEditingController productSearchC = TextEditingController();
  final TextEditingController supplierSearchC = TextEditingController();

  DateTime selectedDate = DateTime.now();
  Party? selectedSupplier;
  bool isBreakageMode = false;
  List<PurchaseItem> items = [];
  bool isSaving = false;
  bool isReadOnly = false;
  String? existingRecordId;

  void init({
    required PharoahWebManager webPh,
    PurchaseReturn? existingRecord,
    bool readOnly = false,
  }) {
    isReadOnly = readOnly;
    if (existingRecord != null) {
      existingRecordId = existingRecord.id;
      noteNoC.text = existingRecord.billNo;
      selectedDate = existingRecord.date;
      extraDiscC.text = existingRecord.extraDiscount.toString();
      isBreakageMode = existingRecord.returnType.toLowerCase().contains("breakage") ||
          existingRecord.returnType.toLowerCase().contains("expiry");
      items = List.from(existingRecord.items);
      try {
        selectedSupplier = webPh.parties.firstWhere(
          (p) => p.name.trim().toUpperCase() == existingRecord.distributorName.trim().toUpperCase(),
        );
      } catch (_) {
        selectedSupplier = Party(id: 'temp', name: existingRecord.distributorName, group: "Sundry Creditors");
      }
    } else {
      noteNoC.text = webPh.getNextBillNumber("RETURN", "DN-", 101);
      selectedDate = WebAppDateLogic.getSmartDate(webPh.financialYear);
    }
    notifyListeners();
  }

  void notifySearch() {
    notifyListeners();
  }

  void toggleBreakageMode(bool val) {
    isBreakageMode = val;
    notifyListeners();
  }

  void setSupplier(Party supplier) {
    selectedSupplier = supplier;
    supplierSearchC.clear();
    notifyListeners();
  }

  void clearSupplier() {
    selectedSupplier = null;
    notifyListeners();
  }

  void setDate(DateTime date) {
    selectedDate = date;
    notifyListeners();
  }

  void addItem(PurchaseItem item) {
    items.add(item);
    _recalculateSR();
    notifyListeners();
  }

  void updateItem(int index, PurchaseItem item) {
    if (index >= 0 && index < items.length) {
      items[index] = item;
      _recalculateSR();
      notifyListeners();
    }
  }

  void removeItem(int index) {
    if (index >= 0 && index < items.length) {
      items.removeAt(index);
      _recalculateSR();
      notifyListeners();
    }
  }

  void clearCart() {
    items.clear();
    notifyListeners();
  }

  void _recalculateSR() {
    for (int i = 0; i < items.length; i++) {
      items[i] = items[i].copyWith(srNo: i + 1);
    }
  }

  // --- CALCULATIONS ---
  double get subTotal => items.fold(0.0, (sum, it) => sum + it.total);
  double get totalTaxable => items.fold(0.0, (sum, it) => sum + (it.qty * it.purchaseRate - it.discountRupees));
  double get totalGst => subTotal - totalTaxable;
  double get extraDiscount => double.tryParse(extraDiscC.text) ?? 0.0;
  double get rawGrandTotal => (subTotal - extraDiscount);
  double get grandTotal => rawGrandTotal.roundToDouble();
  double get roundOff => double.parse((grandTotal - rawGrandTotal).toStringAsFixed(2));

  Future<bool> saveDebitNote(BuildContext context, PharoahWebManager webPh, {bool andPrint = false}) async {
    if (selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a Supplier / Distributor first!"), backgroundColor: Colors.orange),
      );
      return false;
    }

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Debit Note cannot be empty! Please add products."), backgroundColor: Colors.orange),
      );
      return false;
    }

    isSaving = true;
    notifyListeners();

    String id = existingRecordId ?? "DN-WEB-${DateTime.now().millisecondsSinceEpoch}";
    String returnType = isBreakageMode ? "Breakage" : "Sellable";
    if (items.any((i) => i.isBreakage) && items.any((i) => !i.isBreakage)) {
      returnType = "Mixed";
    }

    bool success = await DebitNoteMechanism.commitDebitNote(
      webPh: webPh,
      noteId: id,
      noteNo: noteNoC.text.trim(),
      supplier: selectedSupplier!,
      date: selectedDate,
      items: items,
      totalAmount: grandTotal,
      extraDiscount: extraDiscount,
      roundOff: roundOff,
      returnType: returnType,
      existingId: existingRecordId,
    );

    if (andPrint && success) {
      final newReturn = PurchaseReturn(
        id: id,
        billNo: noteNoC.text.trim(),
        distributorName: selectedSupplier!.name,
        date: selectedDate,
        items: List.from(items),
        totalAmount: grandTotal,
        extraDiscount: extraDiscount,
        roundOff: roundOff,
        returnType: returnType,
        status: "Active",
      );
      final shopProfile = CompanyProfile.fromMap(webPh.companyProfile);
      await WebPdfRouterService.printDebitNote(returnObj: newReturn, party: selectedSupplier!, shop: shopProfile);
    }

    isSaving = false;
    notifyListeners();
    return success;
  }

  @override
  void dispose() {
    noteNoC.dispose();
    extraDiscC.dispose();
    remarksC.dispose();
    productSearchC.dispose();
    supplierSearchC.dispose();
    super.dispose();
  }
}
