// FILE: lib/sync_core/modules/challan_sync_module.dart
import '../../models.dart';
import '../models/sync_envelope.dart';
import 'sale_challan_sync_module.dart';
import 'purchase_challan_sync_module.dart';

export 'sale_challan_sync_module.dart';
export 'purchase_challan_sync_module.dart';

/// Legacy adapter maintaining backward compatibility.
/// Delegates directly to the isolated SaleChallanSyncModule and PurchaseChallanSyncModule.
class ChallanSyncModule {
  static const String docTypeSaleChallan = SaleChallanSyncModule.docTypeSaleChallan;
  static const String docTypePurchaseChallan = PurchaseChallanSyncModule.docTypePurchaseChallan;

  // Sale Challan delegations
  static void onChallanSaved(SaleChallan challan, String storeToken) =>
      SaleChallanSyncModule.onSaleChallanSaved(challan, storeToken);

  static void onChallanDeleted(SaleChallan challan, String storeToken) =>
      SaleChallanSyncModule.onSaleChallanDeleted(challan, storeToken);

  static bool mergeIncomingChallanEnvelope(List<SaleChallan> currentChallans, SyncEnvelope envelope) =>
      SaleChallanSyncModule.mergeIncomingSaleChallanEnvelope(currentChallans, envelope);

  static bool applyChallanMutation(List<SaleChallan> currentChallans, SaleChallan incoming) =>
      SaleChallanSyncModule.applySaleChallanMutation(currentChallans, incoming);

  // Purchase Challan delegations
  static void onPurchaseChallanSaved(PurchaseChallan challan, String storeToken) =>
      PurchaseChallanSyncModule.onPurchaseChallanSaved(challan, storeToken);

  static void onPurchaseChallanDeleted(PurchaseChallan challan, String storeToken) =>
      PurchaseChallanSyncModule.onPurchaseChallanDeleted(challan, storeToken);

  static bool mergeIncomingPurchaseChallanEnvelope(List<PurchaseChallan> currentList, SyncEnvelope envelope) =>
      PurchaseChallanSyncModule.mergeIncomingPurchaseChallanEnvelope(currentList, envelope);

  static bool applyPurchaseChallanMutation(List<PurchaseChallan> currentList, PurchaseChallan incoming) =>
      PurchaseChallanSyncModule.applyPurchaseChallanMutation(currentList, incoming);
}
