// FILE: lib/web_live_sync/web_purchase_entry_view.dart

import 'package:flutter/material.dart';
import '../models.dart';
import 'sub_views/web_purchase/ui/web_purchase_entry_screen.dart';
import 'sub_views/web_purchase/ui/web_purchase_billing_screen.dart';

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
  });

  @override
  Widget build(BuildContext context) {
    if (initialSupplier != null && existingItems != null) {
      return WebPurchaseBillingScreen(
        supplier: initialSupplier!,
        internalNo: initialInternalNo ?? "PUR-1",
        supplierBillNo: initialBillNo ?? "",
        billDate: initialDate ?? DateTime.now(),
        entryDate: initialEntryDate ?? DateTime.now(),
        paymentMode: initialMode ?? "CREDIT",
        existingPurchase: modifyPurchaseId != null
            ? Purchase(
                id: modifyPurchaseId!,
                internalNo: initialInternalNo ?? "PUR-1",
                billNo: initialBillNo ?? "",
                partyId: initialSupplier!.id,
                distributorName: initialSupplier!.name,
                date: initialDate ?? DateTime.now(),
                entryDate: initialEntryDate ?? DateTime.now(),
                paymentMode: initialMode ?? "CREDIT",
                totalAmount: 0.0,
                items: existingItems ?? [],
                linkedChallanIds: linkedChallanIds ?? [],
              )
            : null,
        isReadOnly: isReadOnly,
        onCompleted: onBack,
      );
    }

    return WebPurchaseEntryScreen(
      onBack: onBack,
      isReadOnly: isReadOnly,
    );
  }
}
