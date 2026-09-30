// FILE: lib/web_live_sync/sub_views/web_challans/sale_challan/logic/sale_challan_controller.dart

import 'package:flutter/material.dart';
import 'package:pharoah_erp/models.dart';
import 'package:pharoah_erp/gateway/company_registry_model.dart';
import 'package:pharoah_erp/app_date_logic.dart';
import '../../../../pharoah_web_manager.dart';
import '../../../../web_pharoah_numbering_engine.dart';
import '../../../../web_pdf_router_service.dart';
import '../mechanism/sale_challan_mechanism.dart';

class SaleChallanController extends ChangeNotifier {
  final TextEditingController challanNoC = TextEditingController();
  final TextEditingController remarksC = TextEditingController();
  final TextEditingController productSearchC = TextEditingController();
  final TextEditingController customerSearchC = TextEditingController();

  DateTime selectedDate = DateTime.now();
  Party? selectedCustomer;
  List<BillItem> items = [];
  bool isSaving = false;
  bool isReadOnly = false;
  String? existingRecordId;

  void init({
    required PharoahWebManager webPh,
    SaleChallan? existingRecord,
    bool readOnly = false,
  }) {
    isReadOnly = readOnly;
    if (existingRecord != null) {
      existingRecordId = existingRecord.id;
      challanNoC.text = existingRecord.billNo;
      selectedDate = existingRecord.date;
      remarksC.text = existingRecord.remarks;
      items = List.from(existingRecord.items);
      try {
        selectedCustomer = webPh.parties.firstWhere((p) => p.id == existingRecord.partyId || p.name == existingRecord.partyName);
      } catch (_) {
        selectedCustomer = Party(id: existingRecord.partyId, name: existingRecord.partyName, state: existingRecord.partyState, gst: existingRecord.partyGstin);
      }
    } else {
      challanNoC.text = WebPharoahNumberingEngine.getNextNumber(
        prefix: "SCH-",
        startFrom: 101,
        currentList: webPh.saleChallans,
      );
      selectedDate = AppDateLogic.getSmartDate(webPh.financialYear);
    }
    notifyListeners();
  }

  void notifySearch() {
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

  double get grandTotal => SaleChallanMechanism.calculateChallanTotal(items);

  Future<bool> saveChallan(BuildContext context, PharoahWebManager webPh, {bool andPrint = false}) async {
    if (selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select Customer first!"), backgroundColor: Colors.orange),
      );
      return false;
    }

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Challan cannot be empty! Please add products."), backgroundColor: Colors.orange),
      );
      return false;
    }

    isSaving = true;
    notifyListeners();

    String id = existingRecordId ?? "SCH-WEB-${DateTime.now().millisecondsSinceEpoch}";
    double total = grandTotal;

    bool success = await SaleChallanMechanism.commitSaleChallan(
      webPh: webPh,
      challanId: id,
      challanNo: challanNoC.text.trim(),
      customer: selectedCustomer!,
      date: selectedDate,
      items: items,
      totalAmount: total,
      remarks: remarksC.text.trim(),
      existingId: existingRecordId,
    );

    if (andPrint && success) {
      final newChallan = SaleChallan(
        id: id,
        billNo: challanNoC.text.trim(),
        partyId: selectedCustomer!.id,
        partyName: selectedCustomer!.name,
        partyGstin: selectedCustomer!.gst,
        partyState: selectedCustomer!.state,
        date: selectedDate,
        items: List.from(items),
        totalAmount: total,
        remarks: remarksC.text.trim(),
      );
      final shopProfile = CompanyProfile.fromMap(webPh.companyProfile);
      await WebPdfRouterService.printSaleChallan(challan: newChallan, party: selectedCustomer!, shop: shopProfile);
    }

    isSaving = false;
    notifyListeners();
    return success;
  }

  @override
  void dispose() {
    challanNoC.dispose();
    remarksC.dispose();
    productSearchC.dispose();
    customerSearchC.dispose();
    super.dispose();
  }
}
