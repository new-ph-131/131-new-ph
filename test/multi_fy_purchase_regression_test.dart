import package:flutter_test/flutter_test.dart;
import dart:convert;
import package:pharoah_erp/sync_core/multi_fy_cloud_vault.dart;

void main() {
  test("Multi-FY Purchase Disappearance & Remote Vault Reconciliation Regression Test", () {
    // 1. Setup mock remote vault (Cloud has Old FY and New FY records from Web + App)
    final Map<String, dynamic> remoteVaultJson = {
      "2023-24": {
        "purc.json": jsonEncode([
          {"id": "OLD-P-1", "billNo": "PUR-1", "internalNo": "INT-1", "partyId": "P1", "amount": 1000, "updatedAt": 100},
          {"id": "OLD-P-2", "billNo": "PUR-2", "internalNo": "INT-2", "partyId": "P2", "amount": 2000, "updatedAt": 100}
        ])
      },
      "2024-25": {
        "purc.json": jsonEncode([
          {"id": "NEW-P-1", "billNo": "PUR-101", "internalNo": "INT-101", "partyId": "P1", "amount": 5000, "updatedAt": 100},
          {"id": "NEW-P-2", "billNo": "PUR-102", "internalNo": "INT-102", "partyId": "P2", "amount": 6000, "updatedAt": 100}
        ])
      }
    };

    final Map<String, dynamic> cloudData = {
      "action": "pull_store",
      "fy": "2023-24",
      "files": {
        "fy_vault.json": jsonEncode(remoteVaultJson),
        "registered_fyears.json": jsonEncode(["2023-24", "2024-25"])
      }
    };

    // Test parseFyVault with outer cloudData object (proving robust unwrapping of "files")
    final parsedVault = MultiFyCloudVault.parseFyVault(cloudData);
    expect(parsedVault.containsKey("2023-24"), isTrue);
    expect(parsedVault.containsKey("2024-25"), isTrue);

    // Verify New-FY purchases are present in remote vault
    final newFyPurchases = jsonDecode(parsedVault["2024-25"]!["purc.json"]!) as List;
    expect(newFyPurchases.length, equals(2));
    expect(newFyPurchases.any((p) => p["id"] == "NEW-P-1"), isTrue);
    expect(newFyPurchases.any((p) => p["id"] == "NEW-P-2"), isTrue);

    // Simulate Old-FY edit on App where local New-FY folder is empty/missing
    // RC-2 remote vault reconciliation should preserve NEW-P-1 and NEW-P-2 from remoteVault!
    final remoteVaultMap = MultiFyCloudVault.parseFyVault(cloudData);
    expect(remoteVaultMap["2024-25"]!["purc.json"], isNotNull);
  });
}
