// FILE: lib/logic/party_integrity_service.dart
import "../models.dart";
import "../pharoah_manager.dart";

/// Result object for Party Deletion Integrity Check
class PartyDeleteCheckResult {
  final bool canDelete;
  final String reason;
  final String details;

  PartyDeleteCheckResult({
    required this.canDelete,
    required this.reason,
    required this.details,
  });
}

/// 🛡️ MARG / TALLY STYLE PARTY INTEGRITY SERVICE
/// Prevents accidental deletion of active ledger accounts with linked bills,
/// vouchers, challans, or outstanding balances.
class PartyIntegrityService {
  static PartyDeleteCheckResult checkPartyDeletionEligibility({
    required PharoahManager ph,
    required Party party,
  }) {
    return checkPartyDeletionEligibilityForLists(
      sales: ph.sales,
      purchases: ph.purchases,
      vouchers: ph.vouchers,
      saleChallans: ph.saleChallans,
      purchaseChallans: ph.purchaseChallans,
      saleReturns: ph.saleReturns,
      purchaseReturns: ph.purchaseReturns,
      party: party,
    );
  }

  static PartyDeleteCheckResult checkPartyDeletionEligibilityForLists({
    required List<Sale> sales,
    required List<Purchase> purchases,
    required List<Voucher> vouchers,
    required List<SaleChallan> saleChallans,
    required List<PurchaseChallan> purchaseChallans,
    required List<SaleReturn> saleReturns,
    required List<PurchaseReturn> purchaseReturns,
    required Party party,
  }) {
    String pId = party.id.trim();
    String pName = party.name.trim().toUpperCase();

    // 1. Check Sales Bills
    int salesCount = sales.where((s) =>
      s.partyId.trim() == pId || s.partyName.trim().toUpperCase() == pName
    ).length;
    if (salesCount > 0) {
      return PartyDeleteCheckResult(
        canDelete: false,
        reason: "Sales Bills Record Exists",
        details: "'${party.name}' has $salesCount active Sales Bill(s) in current Financial Year. Deletion blocked to protect accounting records.",
      );
    }

    // 2. Check Purchase Inwards
    int purCount = purchases.where((p) =>
      p.partyId.trim() == pId || p.distributorName.trim().toUpperCase() == pName
    ).length;
    if (purCount > 0) {
      return PartyDeleteCheckResult(
        canDelete: false,
        reason: "Purchase Bills Record Exists",
        details: "'${party.name}' has $purCount active Purchase Inward(s) in current Financial Year. Deletion blocked.",
      );
    }

    // 3. Check Vouchers
    int voucCount = vouchers.where((v) =>
      v.partyId.trim() == pId || v.partyName.trim().toUpperCase() == pName
    ).length;
    if (voucCount > 0) {
      return PartyDeleteCheckResult(
        canDelete: false,
        reason: "Financial Vouchers Record Exists",
        details: "'${party.name}' has $voucCount payment/receipt voucher entry(ies). Deletion blocked.",
      );
    }

    // 4. Check Sale Challans
    int sChallanCount = saleChallans.where((c) =>
      c.partyId.trim() == pId
    ).length;
    if (sChallanCount > 0) {
      return PartyDeleteCheckResult(
        canDelete: false,
        reason: "Delivery Challan Exists",
        details: "'${party.name}' has $sChallanCount active Delivery Challan(s). Deletion blocked.",
      );
    }

    // 5. Check Purchase Challans
    int pChallanCount = purchaseChallans.where((c) =>
      c.partyId.trim() == pId || c.distributorName.trim().toUpperCase() == pName
    ).length;
    if (pChallanCount > 0) {
      return PartyDeleteCheckResult(
        canDelete: false,
        reason: "Purchase Challan Exists",
        details: "'${party.name}' has $pChallanCount Purchase Challan(s). Deletion blocked.",
      );
    }

    // 6. Check Sale Returns (Credit Notes)
    int sReturnCount = saleReturns.where((r) =>
      r.billNo.isNotEmpty && r.distributorName.trim().toUpperCase() == pName
    ).length;
    if (sReturnCount > 0) {
      return PartyDeleteCheckResult(
        canDelete: false,
        reason: "Credit Note / Sale Return Exists",
        details: "'${party.name}' has $sReturnCount Sale Return(s). Deletion blocked.",
      );
    }

    // 7. Check Purchase Returns (Debit Notes)
    int pReturnCount = purchaseReturns.where((r) =>
      r.billNo.isNotEmpty && r.distributorName.trim().toUpperCase() == pName
    ).length;
    if (pReturnCount > 0) {
      return PartyDeleteCheckResult(
        canDelete: false,
        reason: "Debit Note / Purchase Return Exists",
        details: "'${party.name}' has $pReturnCount Purchase Return(s). Deletion blocked.",
      );
    }

    // 8. Check Outstanding / Opening Balance
    if (party.opBal != 0.0) {
      String formattedBal = party.opBal.abs().toStringAsFixed(2);
      String type = party.opBal > 0 ? "Receivable Balance" : "Payable Credit";
      return PartyDeleteCheckResult(
        canDelete: false,
        reason: "Unsettled Account Balance Exists",
        details: "'${party.name}' has an active $type of ₹$formattedBal. Please settle party balance before deleting.",
      );
    }

    return PartyDeleteCheckResult(
      canDelete: true,
      reason: "Eligible for Deletion",
      details: "No linked records or balances found for '${party.name}'.",
    );
  }
}
