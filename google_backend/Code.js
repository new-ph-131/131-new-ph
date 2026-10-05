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

      // Cumulative Tombstone Protection: Merge incoming tombstones with existing tombstones
      if (fileObj && fileObj.file && request.files) {
        try {
          var existingContent = JSON.parse(fileObj.file.getBlob().getDataAsString());
          if (existingContent.files && existingContent.files["tombstones.json"]) {
            var existingTombstones = JSON.parse(existingContent.files["tombstones.json"]) || [];
            var incomingTombstones = [];
            if (request.files["tombstones.json"]) {
              incomingTombstones = JSON.parse(request.files["tombstones.json"]) || [];
            }
            var mergedTombMap = {};
            for (var i = 0; i < existingTombstones.length; i++) {
              mergedTombMap[existingTombstones[i]] = true;
            }
            for (var j = 0; j < incomingTombstones.length; j++) {
              mergedTombMap[incomingTombstones[j]] = true;
            }
            request.files["tombstones.json"] = JSON.stringify(Object.keys(mergedTombMap));
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
