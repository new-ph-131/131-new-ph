// FILE: lib/web_live_sync/sub_views/web_returns/credit_note/logic/credit_note_controller.dart

import 'package:flutter/material.dart';
import '../../../../web_models.dart';
import '../../../../pharoah_web_manager.dart';
import '../../../../web_app_date_logic.dart';
import '../../../../web_pdf_router_service.dart';
import '../mechanism/credit_note_mechanism.dart';
import '../../../web_billing/mechanism/web_billing_gst_engine.dart';
import '../../../../../logic/gst_compliance_helper.dart';

class CreditNoteController extends ChangeNotifier {
  final TextEditingController noteNoC = TextEditingController();
  final TextEditingController extraDiscC = TextEditingController(text: "0");
  final TextEditingController remarksC = TextEditingController();
  final TextEditingController origBillNoC = TextEditingController();
  DateTime? origBillDate;
  String paymentMode = "CREDIT";
  bool isCommercial = false;
  String selectedReason = GstComplianceHelper.standardReasons.first;
  final TextEditingController productSearchC = TextEditingController();
  final TextEditingController customerSearchC = TextEditingController();

  DateTime selectedDate = DateTime.now();
  Party? selectedCustomer;
  bool isBreakageMode = false;
  List<BillItem> items = [];
  bool isSaving = false;
  bool isReadOnly = false;
  String? existingRecordId;
  String shopState = "Rajasthan";
  String shopGstin = "";

  void init({
    required PharoahWebManager webPh,
    SaleReturn? existingRecord,
    bool readOnly = false,
  }) {
    isReadOnly = readOnly;
    shopState = (webPh.companyProfile['state'] != null && webPh.companyProfile['state'].toString().trim().isNotEmpty) ? webPh.companyProfile['state'].toString().trim() : "Rajasthan";
    shopGstin = (webPh.companyProfile['gstin'] ?? '').toString().trim();
    if (existingRecord != null) {
      existingRecordId = existingRecord.id;
      noteNoC.text = existingRecord.billNo;
      selectedDate = existingRecord.date;
      extraDiscC.text = existingRecord.extraDiscount.toString();
      paymentMode = existingRecord.paymentMode.isNotEmpty ? existingRecord.paymentMode : "CREDIT";
      origBillNoC.text = existingRecord.origBillNo;
      origBillDate = existingRecord.origBillDate;
      final parsedReason = GstComplianceHelper.parseReason(existingRecord.reason);
      selectedReason = parsedReason.selectedReason;
      remarksC.text = parsedReason.customRemark;
      isCommercial = existingRecord.isCommercial;
      isBreakageMode = existingRecord.returnType.toLowerCase().contains("breakage") ||
          existingRecord.returnType.toLowerCase().contains("expiry");
      items = List.from(existingRecord.items);
      try {
        selectedCustomer = webPh.parties.firstWhere(
          (p) => (existingRecord.partyId.isNotEmpty && p.id == existingRecord.partyId) ||
                 p.name.trim().toUpperCase() == existingRecord.partyName.trim().toUpperCase(),
        );
      } catch (_) {
        selectedCustomer = Party(
          id: existingRecord.partyId.isNotEmpty ? existingRecord.partyId : 'temp',
          name: existingRecord.partyName,
          gst: existingRecord.partyGstin,
          state: existingRecord.partyState,
        );
      }
    } else {
      selectedReason = GstComplianceHelper.standardReasons.first;
      remarksC.clear();
      noteNoC.text = webPh.getNextBillNumber("RETURN", "WCN-", 1);
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

  void setReason(String reason) {
    selectedReason = reason;
    notifyListeners();
  }

  String get effectiveReason => GstComplianceHelper.formatReason(selectedReason, remarksC.text);

  void _refreshNumberForCommercial(PharoahWebManager webPh, bool commercial) {
    if (existingRecordId != null) return;
    if (commercial) {
      final pref = webPh.appConfig.commercialNotePrefix.trim().isNotEmpty
          ? webPh.appConfig.commercialNotePrefix.trim()
          : "CCN-";
      noteNoC.text = webPh.getNextBillNumber("COMMERCIAL_NOTE", pref, 1);
    } else {
      noteNoC.text = webPh.getNextBillNumber("RETURN", "WCN-", 1);
    }
  }

  void setDate(DateTime date, {PharoahWebManager? webPh}) {
    selectedDate = date;
    final bool canComm = webPh == null || GstComplianceHelper.isCommercialNoteAllowed(webPh.appConfig);
    if (canComm && GstComplianceHelper.isSection34Expired(origInvoiceDate: origBillDate, noteDate: selectedDate)) {
      isCommercial = true;
      if (webPh != null) _refreshNumberForCommercial(webPh, true);
    }
    notifyListeners();
  }

  void setPaymentMode(String mode) {
    paymentMode = mode;
    notifyListeners();
  }

  void setOrigBillDate(DateTime? date, {PharoahWebManager? webPh}) {
    origBillDate = date;
    final bool canComm = webPh == null || GstComplianceHelper.isCommercialNoteAllowed(webPh.appConfig);
    if (canComm && GstComplianceHelper.isSection34Expired(origInvoiceDate: origBillDate, noteDate: selectedDate)) {
      isCommercial = true;
      if (webPh != null) _refreshNumberForCommercial(webPh, true);
    }
    notifyListeners();
  }

  void toggleCommercial(bool val, {PharoahWebManager? webPh}) {
    isCommercial = val;
    if (webPh != null) _refreshNumberForCommercial(webPh, val);
    notifyListeners();
  }

  bool get isSection34Expired => GstComplianceHelper.isSection34Expired(
    origInvoiceDate: origBillDate,
    noteDate: selectedDate,
  );

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
  bool get isLocal => selectedCustomer == null || GstComplianceHelper.isIntraStateReturn(
    shopGstin: shopGstin,
    shopState: shopState,
    partyGstin: selectedCustomer?.gst,
    partyState: selectedCustomer?.state,
  );

  BillGstSummary get gstSummary => WebBillingGstEngine.calculate(
    items: items,
    extraDiscount: extraDiscount,
    isLocal: isLocal,
    isCommercial: isCommercial,
  );

  double get subTotal => gstSummary.grossTaxable;
  double get totalTaxable => gstSummary.netTaxable;
  double get totalCGST => gstSummary.totalCGST;
  double get totalSGST => gstSummary.totalSGST;
  double get totalIGST => gstSummary.totalIGST;
  double get totalTax => gstSummary.totalTax;
  double get extraDiscount => double.tryParse(extraDiscC.text) ?? 0.0;
  double get rawGrandTotal => gstSummary.rawGrandTotal;
  double get grandTotal => gstSummary.finalGrandTotal;
  double get roundOff => gstSummary.roundOff;

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
      paymentMode: paymentMode,
      origBillNo: origBillNoC.text.trim(),
      origBillDate: origBillDate,
      reason: effectiveReason,
      isCommercial: isCommercial,
      existingId: existingRecordId,
    );

    if (andPrint && success) {
      final newReturn = SaleReturn(
        id: id,
        billNo: noteNoC.text.trim(),
        date: selectedDate,
        partyId: selectedCustomer!.id,
        partyName: selectedCustomer!.name,
        partyGstin: selectedCustomer!.gst,
        partyState: selectedCustomer!.state,
        items: List.from(items),
        totalAmount: grandTotal,
        extraDiscount: extraDiscount,
        roundOff: roundOff,
        returnType: returnType,
        paymentMode: paymentMode,
        origBillNo: origBillNoC.text.trim(),
        origBillDate: origBillDate,
        reason: effectiveReason,
        isCommercial: isCommercial,
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
    origBillNoC.dispose();
    productSearchC.dispose();
    customerSearchC.dispose();
    super.dispose();
  }
}
