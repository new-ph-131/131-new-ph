// FILE: google_backend/Code.js
// PHAROAH ERP - ATOMIC CLOUD RELAY & CONCURRENCY LOCK ENGINE

function findStoreFile(cleanToken) {
  var fileName = cleanToken + ".json";
  
  // 1. Direct fast lookup in Pharoah_ERP_Cloud folder
  var folder = getCloudFolder();
  if (folder) {
    var files = folder.getFilesByName(fileName);
    if (files.hasNext()) {
      return { folder: folder, file: files.next() };
    }
  }

  // 2. Global search fallback across Drive if not in main folder
  var allFiles = DriveApp.getFilesByName(fileName);
  if (allFiles.hasNext()) {
    return { folder: null, file: allFiles.next() };
  }
  
  return null;
}

function doGet(e) {
  if (e && e.parameter) {
    var action = e.parameter.action;

    // 🔍 DEEP GLOBAL SCAN: Sabhi stores ko Drive se dhoondhna
    if (action === "LIST_ALL_STORES") {
      try {
        var storeList = [];
        var seenTokens = {};
        var totalBytes = 0;

        var fileIterator = DriveApp.searchFiles("title contains '.json'");
        while (fileIterator.hasNext()) {
          var file = fileIterator.next();
          var name = file.getName();

          if (name === "appsscript.json" || name === "package.json" || name === "manifest.json") {
            continue;
          }

          var tokenKey = name.replace(".json", "");
          if (!seenTokens[tokenKey]) {
            seenTokens[tokenKey] = true;
            try {
              var contentStr = file.getBlob().getDataAsString();
              var data = JSON.parse(contentStr);

              if (data.storeToken || data.companyName || data.files) {
                var salesCount = 0;
                var medsCount = 0;
                var partsCount = 0;
                var purcCount = 0;

                if (data.files) {
                  if (data.files["sales.json"]) salesCount = JSON.parse(data.files["sales.json"]).length;
                  if (data.files["meds.json"]) medsCount = JSON.parse(data.files["meds.json"]).length;
                  if (data.files["parts.json"]) partsCount = JSON.parse(data.files["parts.json"]).length;
                  if (data.files["purc.json"]) purcCount = JSON.parse(data.files["purc.json"]).length;
                }

                var fileSize = file.getSize();
                totalBytes += fileSize;

                storeList.push({
                  storeToken: data.storeToken || tokenKey,
                  companyName: data.companyName || "Unknown",
                  adminUser: data.adminUser || "admin",
                  fy: data.fy || "N/A",
                  totalSales: salesCount,
                  totalMeds: medsCount,
                  totalParties: partsCount,
                  totalPurchases: purcCount,
                  syncedAt: data.syncedAt || file.getLastUpdated().toISOString(),
                  fileSizeKb: (fileSize / 1024).toFixed(2),
                  fileSizeMb: (fileSize / (1024 * 1024)).toFixed(4)
                });
              }
            } catch(err) {
              // Ignore corrupted json
            }
          }
        }

        return createJsonResponse({
          status: "SUCCESS",
          totalStores: storeList.length,
          totalStorageKb: (totalBytes / 1024).toFixed(2),
          totalStorageMb: (totalBytes / (1024 * 1024)).toFixed(4),
          stores: storeList
        });
      } catch(err) {
        return createJsonResponse({ status: "ERROR", message: err.toString() });
      }
    }

    if (action === "PULL_STORE_DATA") {
      var storeToken = e.parameter.storeToken;
      var username = e.parameter.username;
      var password = e.parameter.password;
      return handlePullRequest(storeToken, username, password);
    }
  }

  return createJsonResponse({
    status: "ACTIVE",
    service: "Pharoah ERP Cloud Relay Engine",
    version: "1.1.0-ATOMIC",
    timestamp: new Date().toISOString()
  });
}

function doPost(e) {
  var lock = LockService.getScriptLock();
  var hasLock = false;

  try {
    // 🛡️ CRITICAL: 15-second lock prevents race condition collisions
    hasLock = lock.waitLock(15000);

    if (!e || !e.postData || !e.postData.contents) {
      return createJsonResponse({ status: "ERROR", message: "Empty request payload." });
    }

    var request = JSON.parse(e.postData.contents);
    var action = request.action;

    if (action === "PUSH_STORE_DATA") {
      var storeToken = (request.storeToken || "").trim().toUpperCase();
      if (!storeToken) {
        return createJsonResponse({ status: "ERROR", message: "Store Token is missing." });
      }

      var fileObj = findStoreFile(storeToken);
      request.syncedAt = new Date().toISOString();

      // Cumulative Tombstone Protection with Unmark & Re-creation Support
      if (fileObj && fileObj.file && request.files) {
        try {
          var existingContent = JSON.parse(fileObj.file.getBlob().getDataAsString());
          var unmarkedMap = {};
          var rawUnmarkedList = [];
          if (Array.isArray(request.unmarkedTombstones)) {
            rawUnmarkedList = rawUnmarkedList.concat(request.unmarkedTombstones);
          }
          if (request.files["unmarked_tombstones.json"]) {
            try {
              var parsedUnm = JSON.parse(request.files["unmarked_tombstones.json"]);
              if (Array.isArray(parsedUnm)) rawUnmarkedList = rawUnmarkedList.concat(parsedUnm);
            } catch (_) {}
          }
          for (var uIdx = 0; uIdx < rawUnmarkedList.length; uIdx++) {
            var uKey = (rawUnmarkedList[uIdx] || "").toString().trim();
            if (uKey) {
              unmarkedMap[uKey] = true;
              unmarkedMap[uKey.toUpperCase()] = true;
            }
          }

          // Collect active record keys and timestamps from incoming live files so recreated records strip stale tombstones
          var activeRecordTsMap = {};
          var liveFileList = ["sales.json", "purc.json", "s_challan.json", "p_challan.json"];
          var rootFy = (request.fy || "").toString().trim();
          for (var lfIdx = 0; lfIdx < liveFileList.length; lfIdx++) {
            var lfName = liveFileList[lfIdx];
            if (request.files[lfName]) {
              try {
                var arr = JSON.parse(request.files[lfName]) || [];
                for (var rIdx = 0; rIdx < arr.length; rIdx++) {
                  var rec = arr[rIdx] || {};
                  if (rec.isDeleted === true || rec.status === "Deleted") continue;
                  var rId = (rec.id || "").toString().trim();
                  var rBill = (rec.billNo || "").toString().trim();
                  var rInt = (rec.internalNo || "").toString().trim().toUpperCase();
                  var rParty = (rec.partyId || "").toString().trim().toUpperCase();
                  var rFy = (rec.originalFy || rec.fy || rootFy || "").toString().trim();
                  var rTs = Number(rec.updatedAt) || 0;
                  if (rId) activeRecordTsMap[rId] = Math.max(activeRecordTsMap[rId] || 0, rTs);
                  if (rBill && (lfName === "sales.json" || lfName === "s_challan.json")) {
                    var upBill = rBill.toUpperCase();
                    activeRecordTsMap[upBill] = Math.max(activeRecordTsMap[upBill] || 0, rTs);
                    if (rFy) {
                      var scBill = rFy + "::" + upBill;
                      activeRecordTsMap[scBill] = Math.max(activeRecordTsMap[scBill] || 0, rTs);
                    }
                  }
                  if (rInt) {
                    activeRecordTsMap[rInt] = Math.max(activeRecordTsMap[rInt] || 0, rTs);
                    if (rFy) activeRecordTsMap[rFy + "::" + rInt] = Math.max(activeRecordTsMap[rFy + "::" + rInt] || 0, rTs);
                  }
                  if (rParty && rBill && (lfName === "purc.json" || lfName === "p_challan.json")) {
                    var c2 = rParty + "_" + rBill;
                    activeRecordTsMap[c2] = Math.max(activeRecordTsMap[c2] || 0, rTs);
                    if (rFy) activeRecordTsMap[rFy + "::" + c2] = Math.max(activeRecordTsMap[rFy + "::" + c2] || 0, rTs);
                  }
                }
              } catch (_) {}
            }
          }

          var incomingTombSet = {};
          var incomingTombstones = [];
          if (request.files["tombstones.json"]) {
            try {
              incomingTombstones = JSON.parse(request.files["tombstones.json"]) || [];
              for (var itIdx = 0; itIdx < incomingTombstones.length; itIdx++) {
                var itKey = (incomingTombstones[itIdx] || "").toString().trim();
                if (itKey) incomingTombSet[itKey] = true;
              }
            } catch (_) {}
          }

          var existingReg = {};
          var incomingReg = {};
          try {
            if (existingContent.files && existingContent.files["tombstone_registry.json"]) {
              existingReg = JSON.parse(existingContent.files["tombstone_registry.json"]) || {};
            }
          } catch (_) {}
          try {
            if (request.files["tombstone_registry.json"]) {
              incomingReg = JSON.parse(request.files["tombstone_registry.json"]) || {};
            }
          } catch (_) {}

          if (existingContent.files && existingContent.files["tombstones.json"]) {
            var existingTombstones = JSON.parse(existingContent.files["tombstones.json"]) || [];
            var mergedTombMap = {};
            for (var i = 0; i < existingTombstones.length; i++) {
              var eKey = (existingTombstones[i] || "").toString().trim();
              if (!eKey) continue;
              if (unmarkedMap[eKey] || unmarkedMap[eKey.toUpperCase()]) continue;
              var activeTs = activeRecordTsMap[eKey] || activeRecordTsMap[eKey.toUpperCase()] || 0;
              var delTs = Number(existingReg[eKey] || existingReg[eKey.toUpperCase()]) || 0;
              if (activeTs > 0 && !incomingTombSet[eKey] && (delTs === 0 || activeTs > delTs)) {
                continue;
              }
              mergedTombMap[eKey] = true;
            }
            for (var j = 0; j < incomingTombstones.length; j++) {
              var iKey = (incomingTombstones[j] || "").toString().trim();
              if (!iKey) continue;
              if (unmarkedMap[iKey] || unmarkedMap[iKey.toUpperCase()]) continue;
              mergedTombMap[iKey] = true;
            }
            request.files["tombstones.json"] = JSON.stringify(Object.keys(mergedTombMap));
          }
          // Cumulative Tombstone Registry Protection: Keep max deletion timestamp per key unless unmarked/recreated
          if (existingContent.files && (existingContent.files["tombstone_registry.json"] || request.files["tombstone_registry.json"])) {
            var mergedReg = {};
            for (var ek in existingReg) {
              if (Object.prototype.hasOwnProperty.call(existingReg, ek)) {
                if (unmarkedMap[ek] || unmarkedMap[ek.toUpperCase()]) continue;
                var prevDelTs = Number(existingReg[ek]) || 0;
                var liveTs = activeRecordTsMap[ek] || activeRecordTsMap[ek.toUpperCase()] || 0;
                if (liveTs > 0 && !Object.prototype.hasOwnProperty.call(incomingReg, ek) && liveTs > prevDelTs) {
                  continue;
                }
                mergedReg[ek] = prevDelTs;
              }
            }
            for (var ik in incomingReg) {
              if (Object.prototype.hasOwnProperty.call(incomingReg, ik)) {
                if (unmarkedMap[ik] || unmarkedMap[ik.toUpperCase()]) continue;
                var incTs = Number(incomingReg[ik]) || 0;
                var prevTs = Number(mergedReg[ik]) || 0;
                if (incTs >= prevTs) {
                  mergedReg[ik] = incTs;
                }
              }
            }
            request.files["tombstone_registry.json"] = JSON.stringify(mergedReg);
          }
          // Preserve any Financial Year vault slices from existing Drive snapshot that are absent from incoming payload
          if (existingContent.files && existingContent.files["fy_vault.json"] && request.files["fy_vault.json"]) {
            try {
              var existingVault = JSON.parse(existingContent.files["fy_vault.json"]) || {};
              var incomingVault = JSON.parse(request.files["fy_vault.json"]) || {};
              for (var fyKey in existingVault) {
                if (Object.prototype.hasOwnProperty.call(existingVault, fyKey) &&
                    !Object.prototype.hasOwnProperty.call(incomingVault, fyKey)) {
                  incomingVault[fyKey] = existingVault[fyKey];
                }
              }
              request.files["fy_vault.json"] = JSON.stringify(incomingVault);
            } catch (_) {}
          }
        } catch(mergeErr) {}
      }

      var jsonPayload = JSON.stringify(request);

      if (fileObj && fileObj.file) {
        fileObj.file.setContent(jsonPayload);
      } else {
        var folder = getCloudFolder();
        folder.createFile(storeToken + ".json", jsonPayload, MimeType.PLAIN_TEXT);
      }

      return createJsonResponse({
        status: "SUCCESS",
        message: "Store snapshot synced atomically to cloud.",
        syncedAt: request.syncedAt
      });
    }

    if (action === "PULL_STORE_DATA") {
      return handlePullRequest(request.storeToken, request.username, request.password);
    }

    return createJsonResponse({ status: "ERROR", message: "Unknown action: " + action });
  } catch (err) {
    return createJsonResponse({ status: "ERROR", message: err.toString() });
  } finally {
    if (hasLock) {
      lock.releaseLock();
    }
  }
}

function handlePullRequest(storeToken, username, password) {
  var cleanToken = (storeToken || "").trim().toUpperCase();
  var inputUser = (username || "").trim().toLowerCase();
  var inputPass = (password || "").trim();

  if (!cleanToken) {
    return createJsonResponse({ status: "ERROR", message: "Store Key is required." });
  }

  var fileObj = findStoreFile(cleanToken);
  if (!fileObj || !fileObj.file) {
    return createJsonResponse({
      status: "ERROR",
      message: "Store Key '" + cleanToken + "' not found on Google Drive. Please tap 'SYNC NOW TO CLOUD' in your mobile app first."
    });
  }

  var storeData = JSON.parse(fileObj.file.getBlob().getDataAsString());
  var savedUser = (storeData.adminUser || "").trim().toLowerCase();
  var savedPass = (storeData.adminPassword || "").trim();

  if (savedUser === inputUser && savedPass === inputPass) {
    return createJsonResponse({
      status: "SUCCESS",
      companyName: storeData.companyName,
      fy: storeData.fy,
      registryProfile: storeData.registryProfile,
      files: storeData.files,
      syncedAt: storeData.syncedAt
    });
  } else {
    return createJsonResponse({
      status: "ERROR",
      message: "Invalid Username or Password for Store Key '" + cleanToken + "'."
    });
  }
}

function createJsonResponse(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

function getCloudFolder() {
  var folderName = "Pharoah_ERP_Cloud";
  var folders = DriveApp.getFoldersByName(folderName);
  return folders.hasNext() ? folders.next() : DriveApp.createFolder(folderName);
}
