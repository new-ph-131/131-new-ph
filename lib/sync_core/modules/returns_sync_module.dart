// FILE: lib/sync_core/modules/returns_sync_module.dart
import '../../models.dart';
import '../models/sync_envelope.dart';
import 'credit_note_sync_module.dart';
import 'debit_note_sync_module.dart';

export 'credit_note_sync_module.dart';
export 'debit_note_sync_module.dart';

/// Legacy adapter maintaining backward compatibility.
/// Delegates directly to the isolated CreditNoteSyncModule and DebitNoteSyncModule.
class ReturnsSyncModule {
  static const String docTypeSaleReturn = CreditNoteSyncModule.docTypeSaleReturn;
  static const String docTypePurchaseReturn = DebitNoteSyncModule.docTypePurchaseReturn;

  // --- SALE RETURN (CREDIT NOTE) DELEGATIONS ---
  static void onSaleReturnSaved(SaleReturn ret, String storeToken) =>
      CreditNoteSyncModule.onCreditNoteSaved(ret, storeToken);

  static void onSaleReturnDeleted(SaleReturn ret, String storeToken) =>
      CreditNoteSyncModule.onCreditNoteDeleted(ret, storeToken);

  static bool mergeIncomingSaleReturn(List<SaleReturn> currentList, SyncEnvelope envelope) =>
      CreditNoteSyncModule.mergeIncomingCreditNoteEnvelope(currentList, envelope);

  static bool applySaleReturnMutation(List<SaleReturn> currentList, SaleReturn incoming) =>
      CreditNoteSyncModule.applyCreditNoteMutation(currentList, incoming);

  // --- PURCHASE RETURN (DEBIT NOTE) DELEGATIONS ---
  static void onPurchaseReturnSaved(PurchaseReturn ret, String storeToken) =>
      DebitNoteSyncModule.onDebitNoteSaved(ret, storeToken);

  static void onPurchaseReturnDeleted(PurchaseReturn ret, String storeToken) =>
      DebitNoteSyncModule.onDebitNoteDeleted(ret, storeToken);

  static bool mergeIncomingPurchaseReturn(List<PurchaseReturn> currentList, SyncEnvelope envelope) =>
      DebitNoteSyncModule.mergeIncomingDebitNoteEnvelope(currentList, envelope);

  static bool applyPurchaseReturnMutation(List<PurchaseReturn> currentList, PurchaseReturn incoming) =>
      DebitNoteSyncModule.applyDebitNoteMutation(currentList, incoming);
}
