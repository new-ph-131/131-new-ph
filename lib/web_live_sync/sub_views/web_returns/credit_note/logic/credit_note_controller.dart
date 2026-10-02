// FILE: lib/web_live_sync/sub_views/web_returns/credit_note/logic/credit_note_controller.dart

import 'package:flutter/material.dart';
import '../../../../web_models.dart';
import '../../../../pharoah_web_manager.dart';
import '../../../../web_app_date_logic.dart';
import '../../../../web_pdf_router_service.dart';
import '../mechanism/credit_note_mechanism.dart';

class CreditNoteController extends ChangeNotifier {
  final TextEditingController noteNoC = TextEditingController();
  final TextEditingController extraDiscC = TextEditingController(text: "0");
  final TextEditingController remarksC = TextEditingController();
  final TextEditingController productSearchC = TextEditingController();
  final TextEditingController customerSearchC = TextEditingController();

  DateTime selectedDate = DateTime.now();
  Party? selectedCustomer;
  bool isBreakageMode = false;
  List<BillItem> items = [];
  bool isSaving = false;
  bool isReadOnly = false;
  String? existingRecordId;

  void init({
    required PharoahWebManager webPh,
    SaleReturn? existingRecord,
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
        selectedCustomer = webPh.parties.firstWhere((p) => p.name == existingRecord.partyName);
      } catch (_) {
        selectedCustomer = Party(id: 'temp', name: existingRecord.partyName);
      }
    } else {
      noteNoC.text = webPh.getNextBillNumber("RETURN", "CN-", 101);
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

  void setCustomer(Party customer) {
    selectedCustomer = customer;
    customerSearchC.clear();
    notifyListeners();
  }

  void clearCustomer() {
    selectedCustomer = null;
    notifyListeners();
  }

  void setDate(DateTime date) {
    selectedDate = date;
    notifyListeners();
  }

  void addItem(BillItem item) {
    items.add(item);
    _recalculateSR();
    notifyListeners();
  }

  void updateItem(int index, BillItem item) {
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
  double get totalTaxable => items.fold(0.0, (sum, it) => sum + (it.qty * it.rate - it.discountRupees));
  double get totalCGST => items.fold(0.0, (sum, it) => sum + it.cgst);
  double get totalSGST => items.fold(0.0, (sum, it) => sum + it.sgst);
  double get totalIGST => items.fold(0.0, (sum, it) => sum + it.igst);
  double get extraDiscount => double.tryParse(extraDiscC.text) ?? 0.0;
  double get rawGrandTotal => (subTotal - extraDiscount);
  double get grandTotal => rawGrandTotal.roundToDouble();
  double get roundOff => double.parse((grandTotal - rawGrandTotal).toStringAsFixed(2));

  Future<bool> saveCreditNote(BuildContext context, PharoahWebManager webPh, {bool andPrint = false}) async {
    if (selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a Customer first!"), backgroundColor: Colors.orange),
      );
      return false;
    }

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Credit Note cannot be empty! Please add products."), backgroundColor: Colors.orange),
      );
      return false;
    }

    isSaving = true;
    notifyListeners();

    String id = existingRecordId ?? "CN-WEB-${DateTime.now().millisecondsSinceEpoch}";
    String returnType = isBreakageMode ? "Breakage" : "Sellable";
    if (items.any((i) => i.isBreakage) && items.any((i) => !i.isBreakage)) {
      returnType = "Mixed";
    }

    bool success = await CreditNoteMechanism.commitCreditNote(
      webPh: webPh,
      noteId: id,
      noteNo: noteNoC.text.trim(),
      customer: selectedCustomer!,
      date: selectedDate,
      items: items,
      totalAmount: grandTotal,
      extraDiscount: extraDiscount,
      roundOff: roundOff,
      returnType: returnType,
      existingId: existingRecordId,
    );

    if (andPrint && success) {
      final newReturn = SaleReturn(
        id: id,
        billNo: noteNoC.text.trim(),
        date: selectedDate,
        partyName: selectedCustomer!.name,
        items: List.from(items),
        totalAmount: grandTotal,
        extraDiscount: extraDiscount,
        roundOff: roundOff,
        returnType: returnType,
        status: "Active",
      );
      final shopProfile = CompanyProfile.fromMap(webPh.companyProfile);
      await WebPdfRouterService.printCreditNote(returnObj: newReturn, party: selectedCustomer!, shop: shopProfile);
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
    customerSearchC.dispose();
    super.dispose();
  }
}
