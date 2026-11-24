// FILE: lib/web_live_sync/sub_views/web_returns/debit_note/logic/debit_note_controller.dart
// ignore_for_file: prefer_const_constructors, unnecessary_const

import 'package:flutter/material.dart';
import '../../../../web_models.dart';
import '../../../../pharoah_web_manager.dart';
import '../../../../web_app_date_logic.dart';
import '../../../../web_pdf_router_service.dart';
import '../mechanism/debit_note_mechanism.dart';
import '../../../web_billing/mechanism/web_billing_gst_engine.dart';
import '../../../../../logic/gst_compliance_helper.dart';

class DebitNoteController extends ChangeNotifier {
  final TextEditingController noteNoC = TextEditingController();
  final TextEditingController extraDiscC = TextEditingController(text: "0");
  final TextEditingController remarksC = TextEditingController();
  final TextEditingController origBillNoC = TextEditingController();
  DateTime? origBillDate;
  String paymentMode = "CREDIT";
  bool isCommercial = false;
  String selectedReason = GstComplianceHelper.standardReasons.first;
  final TextEditingController productSearchC = TextEditingController();
  final TextEditingController supplierSearchC = TextEditingController();

  DateTime selectedDate = DateTime.now();
  Party? selectedSupplier;
  bool isBreakageMode = false;
  List<PurchaseItem> items = [];
  bool isSaving = false;
  bool isReadOnly = false;
  String? existingRecordId;
  String shopState = "Rajasthan";
  String shopGstin = "";

  void init({
    required PharoahWebManager webPh,
    PurchaseReturn? existingRecord,
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
      items = GstComplianceHelper.resolveMissingPurchaseItemOrigins(
        items: existingRecord.items,
        purchases: webPh.purchases,
        partyId: existingRecord.partyId,
        partyName: existingRecord.distributorName,
      );
      try {
        selectedSupplier = webPh.parties.firstWhere(
          (p) => (existingRecord.partyId.isNotEmpty && p.id == existingRecord.partyId) ||
                 p.name.trim().toUpperCase() == existingRecord.distributorName.trim().toUpperCase(),
        );
      } catch (_) {
        selectedSupplier = Party(
          id: existingRecord.partyId.isNotEmpty ? existingRecord.partyId : 'temp',
          name: existingRecord.distributorName,
          gst: existingRecord.partyGstin,
          state: existingRecord.partyState,
          group: "Sundry Creditors",
        );
      }
      _syncHeaderOriginFromItems(webPh: webPh, silent: true, clearWhenEmpty: false);
    } else {
      selectedReason = GstComplianceHelper.standardReasons.first;
      remarksC.clear();
      noteNoC.text = webPh.getNextBillNumber("DEBIT_NOTE", "WDN-", 1);
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
      noteNoC.text = webPh.getNextBillNumber("DEBIT_NOTE", "WDN-", 1);
    }
  }

  void setDate(DateTime date, {PharoahWebManager? webPh}) {
    selectedDate = date;
    final bool canComm = webPh == null || GstComplianceHelper.isCommercialNoteAllowed(webPh.appConfig);
    if (canComm && isSection34Expired) {
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
    if (canComm && isSection34Expired) {
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

  DateTime? get expiredOriginDate => GstComplianceHelper.getExpiredOriginDate(
    headerOrigDate: origBillDate,
    items: items,
    noteDate: selectedDate,
  );

  bool get isSection34Expired => expiredOriginDate != null;

  void _syncHeaderOriginFromItems({
    PharoahWebManager? webPh,
    bool silent = false,
    bool clearWhenEmpty = true,
  }) {
    final summary = GstComplianceHelper.summarizeOriginInvoices(items);
    if (summary.uniqueCount > 0) {
      origBillNoC.text = summary.headerBillNo;
      origBillDate = summary.headerDate;
    } else if (clearWhenEmpty && (items.isEmpty || items.every((it) => it.isManualOrigin))) {
      origBillNoC.text = "";
      origBillDate = null;
    }
    final bool canComm = webPh == null || GstComplianceHelper.isCommercialNoteAllowed(webPh.appConfig);
    if (!silent && canComm && isSection34Expired && !isCommercial) {
      isCommercial = true;
      if (webPh != null) _refreshNumberForCommercial(webPh, true);
    }
  }

  void addItem(PurchaseItem item, {PharoahWebManager? webPh}) {
    items.add(item);
    _recalculateSR();
    _syncHeaderOriginFromItems(webPh: webPh);
    notifyListeners();
  }

  void updateItem(int index, PurchaseItem item, {PharoahWebManager? webPh}) {
    if (index >= 0 && index < items.length) {
      items[index] = item;
      _recalculateSR();
      _syncHeaderOriginFromItems(webPh: webPh);
      notifyListeners();
    }
  }

  void removeItem(int index, {PharoahWebManager? webPh}) {
    if (index >= 0 && index < items.length) {
      items.removeAt(index);
      _recalculateSR();
      _syncHeaderOriginFromItems(webPh: webPh, silent: true);
      notifyListeners();
    }
  }

  void clearCart({PharoahWebManager? webPh}) {
    items.clear();
    _syncHeaderOriginFromItems(webPh: webPh, silent: true);
    notifyListeners();
  }

  void _recalculateSR() {
    for (int i = 0; i < items.length; i++) {
      items[i] = items[i].copyWith(srNo: i + 1);
    }
  }

  // --- CALCULATIONS ---
  bool get isLocal => selectedSupplier == null || GstComplianceHelper.isIntraStateReturn(
    shopGstin: shopGstin,
    shopState: shopState,
    partyGstin: selectedSupplier?.gst,
    partyState: selectedSupplier?.state,
  );

  BillGstSummary get gstSummary => WebBillingGstEngine.calculateForPurchase(
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
  double get totalGst => gstSummary.totalTax;
  double get extraDiscount => double.tryParse(extraDiscC.text) ?? 0.0;
  double get rawGrandTotal => gstSummary.rawGrandTotal;
  double get grandTotal => gstSummary.finalGrandTotal;
  double get roundOff => gstSummary.roundOff;

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

    items = GstComplianceHelper.resolveMissingPurchaseItemOrigins(
      items: items,
      purchases: webPh.purchases,
      partyId: selectedSupplier!.id,
      partyName: selectedSupplier!.name,
    );
    _syncHeaderOriginFromItems(webPh: webPh, silent: true, clearWhenEmpty: false);

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
      paymentMode: paymentMode,
      origBillNo: origBillNoC.text.trim(),
      origBillDate: origBillDate,
      reason: effectiveReason,
      isCommercial: isCommercial,
      existingId: existingRecordId,
    );

    if (andPrint && success) {
      final newReturn = PurchaseReturn(
        id: id,
        billNo: noteNoC.text.trim(),
        partyId: selectedSupplier!.id,
        distributorName: selectedSupplier!.name,
        partyGstin: selectedSupplier!.gst,
        partyState: selectedSupplier!.state,
        date: selectedDate,
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
    origBillNoC.dispose();
    productSearchC.dispose();
    supplierSearchC.dispose();
    super.dispose();
  }
}
