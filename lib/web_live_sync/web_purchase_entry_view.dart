// FILE: lib/web_live_sync/web_purchase_entry_view.dart

import 'package:flutter/material.dart';
import '../models.dart';
import 'sub_views/web_purchase/ui/web_purchase_entry_screen.dart';

class WebPurchaseEntryView extends StatelessWidget {
  final VoidCallback onBack;
  final int initialTabIndex;
  final Party? initialSupplier;
  final String? initialInternalNo;
  final String? initialBillNo;
  final DateTime? initialDate;
  final DateTime? initialEntryDate;
  final String? initialMode;
  final List<PurchaseItem>? existingItems;
  final List<String>? linkedChallanIds;
  final String? modifyPurchaseId;
  final bool isReadOnly;
  final Purchase? existingPurchase;
  final double initialExtraDiscount;
  final double initialRoundOff;
  final double initialTotalAmount;
  final int initialVersion;

  const WebPurchaseEntryView({
    super.key,
    required this.onBack,
    this.initialTabIndex = 0,
    this.initialSupplier,
    this.initialInternalNo,
    this.initialBillNo,
    this.initialDate,
    this.initialEntryDate,
    this.initialMode,
    this.existingItems,
    this.linkedChallanIds,
    this.modifyPurchaseId,
    this.isReadOnly = false,
    this.existingPurchase,
    this.initialExtraDiscount = 0.0,
    this.initialRoundOff = 0.0,
    this.initialTotalAmount = 0.0,
    this.initialVersion = 1,
  });

  @override
  Widget build(BuildContext context) {
    Purchase? reconstructedPurchase = existingPurchase;
    
    // RECONSTRUCT PURCHASE OBJECT FOR STEP 1 (WITH FULL VERSION & DISCOUNT FIDELITY)
    if (reconstructedPurchase == null && modifyPurchaseId != null && initialSupplier != null && existingItems != null) {
      reconstructedPurchase = Purchase(
        id: modifyPurchaseId!,
        internalNo: initialInternalNo ?? "PUR-1",
        billNo: initialBillNo ?? "",
        partyId: initialSupplier!.id,
        distributorName: initialSupplier!.name,
        date: initialDate ?? DateTime.now(),
        entryDate: initialEntryDate ?? DateTime.now(),
        paymentMode: initialMode ?? "CREDIT",
        totalAmount: initialTotalAmount,
        extraDiscount: initialExtraDiscount,
        roundOff: initialRoundOff,
        version: initialVersion,
        items: existingItems ?? [],
        linkedChallanIds: linkedChallanIds ?? [],
      );
    }

    return WebPurchaseEntryScreen(
      onBack: onBack,
      existingPurchase: reconstructedPurchase,
      isReadOnly: isReadOnly,
    );
  }
}
