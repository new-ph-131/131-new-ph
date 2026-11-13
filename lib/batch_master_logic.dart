import 'inventory_logic_center.dart';
import 'models.dart';

class BatchMasterLogic {
  static List<BatchInfo> updateBatchList(List<BatchInfo> existingBatches, BatchInfo newBatch) {
    List<BatchInfo> updatedList = List.from(existingBatches);
    int idx = InventoryLogicCenter.findMatchingBatchIndex(
      updatedList,
      batchNo: newBatch.batch,
      exp: newBatch.exp,
      mrp: newBatch.mrp,
      purRate: newBatch.purRate > 0 ? newBatch.purRate : newBatch.rate,
      exactEmptyBatchLot: true,
    );
    if (idx != -1) {
      updatedList[idx] = newBatch;
    } else {
      updatedList.add(newBatch);
    }
    return updatedList;
  }
}
