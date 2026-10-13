import 'package:flutter_test/flutter_test.dart';
import 'package:pharoah_erp/models.dart';
import 'package:pharoah_erp/sync_core/modules/purchase_sync_module.dart';
import 'package:pharoah_erp/sync_bridge/engines/universal_delta_merger.dart';

Purchase purchase({required String id, required String partyId, required String billNo, required String internalNo, required double amount, int version=1, int updatedAt=100, int isDeleted=0}) {
  final now = DateTime.fromMillisecondsSinceEpoch(1000);
  return Purchase(id:id, internalNo:internalNo, billNo:billNo, partyId:partyId, date:now, entryDate:now,
    distributorName:'Supplier $partyId', items:const [], totalAmount:amount, paymentMode:'CREDIT',
    version:version, updatedAt:updatedAt, isDeleted:isDeleted);
}
void main() {
  test('Supplier + invoice composite identity beats internalNo', () {
    final a=purchase(id:'A1',partyId:'supplier-1',billNo:'inv-77',internalNo:'LOCAL-1',amount:100);
    final b=purchase(id:'B1',partyId:'SUPPLIER-1',billNo:'INV-77',internalNo:'LOCAL-2',amount:200);
    expect(PurchaseSyncModule.getCompositeKey(a),'SUPPLIER-1_INV-77');
    expect(PurchaseSyncModule.getCompositeKey(b),PurchaseSyncModule.getCompositeKey(a));
  });
  test('Different IDs/internalNos for same supplier invoice update one row', () {
    final list=[purchase(id:'APP-ID',partyId:'SUP-1',billNo:'INV-77',internalNo:'APP-1',amount:100)];
    expect(PurchaseSyncModule.applyPurchaseMutation(list,purchase(id:'WEB-ID',partyId:'SUP-1',billNo:'INV-77',internalNo:'WEB-9',amount:250,version:2,updatedAt:200)),isTrue);
    expect(list,hasLength(1)); expect(list.single.totalAmount,250);
  });
  test('Purchase tombstone deletes by supplier + invoice when IDs differ', () {
    final list=[purchase(id:'APP-ID',partyId:'SUP-1',billNo:'INV-77',internalNo:'APP-1',amount:100)];
    expect(PurchaseSyncModule.applyPurchaseMutation(list,purchase(id:'WEB-ID',partyId:'SUP-1',billNo:'INV-77',internalNo:'WEB-9',amount:0,version:2,updatedAt:200,isDeleted:1)),isTrue);
    expect(list,isEmpty);
  });
  test('Universal merge matches and blocks stale Purchase by composite tombstone', () {
    final list=[purchase(id:'APP-ID',partyId:'SUP-1',billNo:'INV-77',internalNo:'APP-1',amount:100,updatedAt:100)];
    final cloud=[purchase(id:'WEB-ID',partyId:'SUP-1',billNo:'INV-77',internalNo:'WEB-9',amount:250,version:2,updatedAt:200).toMap()];
    final args = <String, dynamic>{};
    bool merge(Set<String> tombstones) => UniversalDeltaMerger.mergeEntityList<Purchase>(
      cloudList:cloud, localList:list, tombstones:tombstones,
      getId:(p)=>p.id, getRefNo:(p)=>PurchaseSyncModule.getCompositeKey(p),
      getCompositeKey:(p)=>PurchaseSyncModule.getCompositeKey(p),
      getCloudCompositeKey:(m)=>PurchaseSyncModule.makeCompositeKey((m['partyId']??'').toString(),(m['billNo']??'').toString(),(m['internalNo']??'').toString()),
      fromMap:Purchase.fromMap, toMap:(p)=>p.toMap());
    expect(merge(<String>{}),isTrue); expect(list,hasLength(1)); expect(list.single.totalAmount,250);
    list.clear(); expect(merge(<String>{'SUP-1_INV-77'}),isFalse); expect(list,isEmpty);
  });
}
