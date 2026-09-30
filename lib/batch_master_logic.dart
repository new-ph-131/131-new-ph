import 'models.dart';

class BatchMasterLogic {
  static List<BatchInfo> updateBatchList(List<BatchInfo> existingBatches, BatchInfo newBatch) {
    List<BatchInfo> updatedList = List.from(existingBatches);
    
    // Batch number check (case-insensitive)
    int idx = updatedList.indexWhere((b) => b.batch.trim().toUpperCase() == newBatch.batch.trim().toUpperCase());
    
    if (idx != -1) {
      // Agar batch pehle se hai, update details
      updatedList[idx] = newBatch;
    } else {
      // Naya batch add karein
      updatedList.add(newBatch);
    }
    return updatedList;
  }
}
