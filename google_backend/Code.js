// FILE: google_backend/Code.js
// PHAROAH ERP - DEEP GLOBAL SCAN ENGINE

function findStoreFile(cleanToken) {
  var fileName = cleanToken + ".json";
  
  // 1. Search in all Pharoah_ERP_Cloud folders
  var folders = DriveApp.getFoldersByName("Pharoah_ERP_Cloud");
  while (folders.hasNext()) {
    var f = folders.next();
    var files = f.getFilesByName(fileName);
    if (files.hasNext()) {
      return { folder: f, file: files.next() };
    }
  }
  
  // 2. Global search across entire Google Drive
  var allFiles = DriveApp.getFilesByName(fileName);
  if (allFiles.hasNext()) {
    return { folder: null, file: allFiles.next() };
  }
  
  return null;
}

function doGet(e) {
  if (e && e.parameter) {
    var action = e.parameter.action;

    // 🔍 DEEP GLOBAL SCAN: Sabhi 15-20 stores ko Drive se dhoondhna
    if (action === "LIST_ALL_STORES") {
      try {
        var storeList = [];
        var seenTokens = {};
        var totalBytes = 0;

        // Search all .json files in Google Drive containing PH-LIVE or store data
        var fileIterator = DriveApp.searchFiles("title contains '.json'");

        while (fileIterator.hasNext()) {
          var file = fileIterator.next();
          var name = file.getName();

          // Skip non-store system json files
          if (name === "appsscript.json" || name === "package.json" || name === "manifest.json") {
            continue;
          }

          var tokenKey = name.replace(".json", "");
          if (!seenTokens[tokenKey]) {
            seenTokens[tokenKey] = true;
            try {
              var contentStr = file.getBlob().getDataAsString();
              var data = JSON.parse(contentStr);

              // Check if valid Pharoah ERP store file
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
              // Ignore corrupted or non-pharoah json
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
    version: "1.0.9",
    timestamp: new Date().toISOString()
  });
}

function doPost(e) {
  try {
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
