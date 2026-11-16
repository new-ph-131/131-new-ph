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

function isRecordHardDeleted(rec) {
  if (!rec || typeof rec !== "object") return false;
  var d = rec.isDeleted;
  if (d === true || d === 1 || d === "1" || d === "true") return true;
  var st = (rec.status || "").toString().trim().toUpperCase();
  return st === "DELETED";
}

function challanStatusRank(status) {
  var st = (status || "").toString().trim().toUpperCase();
  if (st === "BILLED") return 3;
  if (st === "CANCELLED") return 2;
  return 1;
}

function shouldIncomingChallanWin(existingRec, incomingRec) {
  if (!existingRec) return true;
  if (!incomingRec) return false;
  var exTs = Number(existingRec.updatedAt) || 0;
  var inTs = Number(incomingRec.updatedAt) || 0;
  if (inTs !== exTs) return inTs > exTs;

  var exVer = Number(existingRec.version) || 1;
  var inVer = Number(incomingRec.version) || 1;
  if (inVer !== exVer) return inVer > exVer;

  var exRank = challanStatusRank(existingRec.status);
  var inRank = challanStatusRank(incomingRec.status);
  if (inRank !== exRank) return inRank > exRank;

  return true;
}

function isChallanTombstoned(rec, mergedTombMap, mergedReg, incomingTombSet, unmarkedMap, fallbackFy) {
  if (isRecordHardDeleted(rec)) return true;

  var rId = (rec.id || "").toString().trim();
  var rTs = Number(rec.updatedAt) || 0;

  if (rId) {
    var rIdUp = rId.toUpperCase();
    if ((unmarkedMap[rId] || unmarkedMap[rIdUp]) && !incomingTombSet[rId] && !incomingTombSet[rIdUp]) {
      return false;
    }
    var delTs = Number(mergedReg[rId] || mergedReg[rIdUp]) || 0;
    if (delTs > 0) {
      return rTs <= delTs;
    }
    if (mergedTombMap[rId] || mergedTombMap[rIdUp]) {
      return true;
    }
    return false;
  }

  // Legacy fallback only when UUID is empty
  var rFy = (rec.originalFy || rec.fy || fallbackFy || "").toString().trim();
  var rKeyRaw = (rec.internalNo || rec.billNo || "").toString().trim();
  if (!rKeyRaw) return false;
  var rKeyUp = rKeyRaw.toUpperCase();
  var scopedKey = rFy ? (rFy + "::" + rKeyUp) : "";

  if ((unmarkedMap[rKeyUp] || (scopedKey && unmarkedMap[scopedKey])) &&
      !incomingTombSet[rKeyRaw] && !incomingTombSet[rKeyUp] &&
      (!scopedKey || !incomingTombSet[scopedKey])) {
    return false;
  }
  var legDelTs = Number(
    (scopedKey && (mergedReg[scopedKey] || mergedReg[scopedKey.toUpperCase()])) ||
    mergedReg[rKeyRaw] || mergedReg[rKeyUp]
  ) || 0;
  if (legDelTs > 0) return rTs <= legDelTs;
  return !!(
    (scopedKey && (mergedTombMap[scopedKey] || mergedTombMap[scopedKey.toUpperCase()])) ||
    mergedTombMap[rKeyRaw] || mergedTombMap[rKeyUp]
  );
}

function parseJsonArraySafe(raw) {
  if (!raw) return [];
  try {
    var parsed = typeof raw === "string" ? JSON.parse(raw) : raw;
    return Array.isArray(parsed) ? parsed : [];
  } catch (_) {
    return [];
  }
}

function parseJsonObjSafe(raw) {
  if (!raw) return {};
  try {
    var parsed = typeof raw === "string" ? JSON.parse(raw) : raw;
    return (parsed && typeof parsed === "object" && !Array.isArray(parsed)) ? parsed : {};
  } catch (_) {
    return {};
  }
}

function mergeChallanJsonString(existingRaw, incomingRaw, mergedTombMap, mergedReg, incomingTombSet, unmarkedMap, fallbackFy) {
  var existingArr = parseJsonArraySafe(existingRaw);
  var incomingArr = parseJsonArraySafe(incomingRaw);

  var mergedByKey = {};
  var orderedKeys = [];

  function recordMergeKey(rec, prefixTag, fallbackIdx) {
    var rId = (rec && rec.id ? rec.id : "").toString().trim();
    if (rId) return "ID:" + rId;
    var rFy = (rec && (rec.originalFy || rec.fy) ? (rec.originalFy || rec.fy) : (fallbackFy || "")).toString().trim();
    var rNo = (rec && (rec.internalNo || rec.billNo) ? (rec.internalNo || rec.billNo) : "").toString().trim().toUpperCase();
    if (rNo) return "LEGACY:" + rFy + "::" + rNo;
    return "ANON:" + prefixTag + ":" + fallbackIdx;
  }

  function upsert(rec, prefixTag, idx) {
    if (!rec || typeof rec !== "object") return;
    if (isChallanTombstoned(rec, mergedTombMap, mergedReg, incomingTombSet, unmarkedMap, fallbackFy)) {
      var kDel = recordMergeKey(rec, prefixTag, idx);
      if (Object.prototype.hasOwnProperty.call(mergedByKey, kDel)) {
        delete mergedByKey[kDel];
      }
      return;
    }
    var k = recordMergeKey(rec, prefixTag, idx);
    if (!Object.prototype.hasOwnProperty.call(mergedByKey, k)) {
      mergedByKey[k] = rec;
      orderedKeys.push(k);
    } else if (shouldIncomingChallanWin(mergedByKey[k], rec)) {
      mergedByKey[k] = rec;
    }
  }

  for (var i = 0; i < incomingArr.length; i++) {
    upsert(incomingArr[i], "IN", i);
  }
  for (var j = 0; j < existingArr.length; j++) {
    upsert(existingArr[j], "EX", j);
  }

  var result = [];
  for (var kIdx = 0; kIdx < orderedKeys.length; kIdx++) {
    var key = orderedKeys[kIdx];
    if (Object.prototype.hasOwnProperty.call(mergedByKey, key) && mergedByKey[key]) {
      result.push(mergedByKey[key]);
    }
  }
  return JSON.stringify(result);
}

function mergeHwmMaps(baseMap, extraMap) {
  var out = {};
  var k;
  if (baseMap && typeof baseMap === "object" && !Array.isArray(baseMap)) {
    for (k in baseMap) {
      if (Object.prototype.hasOwnProperty.call(baseMap, k)) {
        var bv = parseInt(baseMap[k], 10);
        if (!isNaN(bv) && bv >= 0) out[k] = bv;
      }
    }
  }
  if (extraMap && typeof extraMap === "object" && !Array.isArray(extraMap)) {
    for (k in extraMap) {
      if (Object.prototype.hasOwnProperty.call(extraMap, k)) {
        var ev = parseInt(extraMap[k], 10);
        if (!isNaN(ev) && ev >= 0) {
          out[k] = Object.prototype.hasOwnProperty.call(out, k) ? Math.max(out[k], ev) : ev;
        }
      }
    }
  }
  return out;
}

function mergeConfigWithMonotonicHwm(existingCfgRaw, incomingCfgRaw, globalMergedHwm) {
  var exCfg = parseJsonObjSafe(existingCfgRaw);
  var inCfg = parseJsonObjSafe(incomingCfgRaw);

  var hasEx = Object.keys(exCfg).length > 0;
  var hasIn = Object.keys(inCfg).length > 0;
  if (!hasEx && !hasIn) return null;

  var exTs = Number(exCfg.updatedAt) || 0;
  var inTs = Number(inCfg.updatedAt) || 0;
  var exVer = Number(exCfg.version) || 0;
  var inVer = Number(inCfg.version) || 0;

  var baseCfg;
  if (!hasIn) {
    baseCfg = JSON.parse(JSON.stringify(exCfg));
  } else if (!hasEx) {
    baseCfg = JSON.parse(JSON.stringify(inCfg));
  } else if (inTs > exTs || (inTs === exTs && inVer >= exVer)) {
    baseCfg = JSON.parse(JSON.stringify(inCfg));
  } else {
    baseCfg = JSON.parse(JSON.stringify(exCfg));
  }

  var combinedHwm = mergeHwmMaps(
    exCfg.challanHwm || exCfg.challan_hwm,
    inCfg.challanHwm || inCfg.challan_hwm
  );
  if (globalMergedHwm && typeof globalMergedHwm === "object") {
    combinedHwm = mergeHwmMaps(combinedHwm, globalMergedHwm);
  }
  if (Object.keys(combinedHwm).length > 0) {
    baseCfg.challanHwm = combinedHwm;
  }
  return JSON.stringify(baseCfg);
}

function mergeHwmFileString(existingRaw, incomingRaw, globalMergedHwm) {
  var exMap = parseJsonObjSafe(existingRaw);
  var inMap = parseJsonObjSafe(incomingRaw);
  var combined = mergeHwmMaps(exMap, inMap);
  if (globalMergedHwm && typeof globalMergedHwm === "object") {
    combined = mergeHwmMaps(combined, globalMergedHwm);
  }
  return JSON.stringify(combined);
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
    version: "1.2.0-CHALLAN-MERGE",
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

      // Cumulative Tombstone Protection + UUID-based Challan Merge + Monotonic HWM Merge
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
          var activeIdTsMap = {};
          var hardDeletedIdTsMap = {};
          var liveFileList = ["sales.json", "purc.json", "s_challan.json", "p_challan.json"];
          var rootFy = (request.fy || request.activeFy || "").toString().trim();
          for (var lfIdx = 0; lfIdx < liveFileList.length; lfIdx++) {
            var lfName = liveFileList[lfIdx];
            if (request.files[lfName]) {
              try {
                var arr = JSON.parse(request.files[lfName]) || [];
                for (var rIdx = 0; rIdx < arr.length; rIdx++) {
                  var rec = arr[rIdx] || {};
                  var rId = (rec.id || "").toString().trim();
                  var rTs = Number(rec.updatedAt) || 0;
                  if (isRecordHardDeleted(rec)) {
                    if (rId && (lfName === "s_challan.json" || lfName === "p_challan.json")) {
                      hardDeletedIdTsMap[rId] = Math.max(hardDeletedIdTsMap[rId] || 0, rTs);
                    }
                    continue;
                  }
                  var rBill = (rec.billNo || "").toString().trim();
                  var rInt = (rec.internalNo || "").toString().trim().toUpperCase();
                  var rParty = (rec.partyId || "").toString().trim().toUpperCase();
                  var rFy = (rec.originalFy || rec.fy || rootFy || "").toString().trim();
                  if (rId) {
                    activeRecordTsMap[rId] = Math.max(activeRecordTsMap[rId] || 0, rTs);
                    activeIdTsMap[rId] = Math.max(activeIdTsMap[rId] || 0, rTs);
                    activeIdTsMap[rId.toUpperCase()] = Math.max(activeIdTsMap[rId.toUpperCase()] || 0, rTs);
                  }
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

          var mergedTombMap = {};
          if (existingContent.files && existingContent.files["tombstones.json"]) {
            var existingTombstones = JSON.parse(existingContent.files["tombstones.json"]) || [];
            for (var i = 0; i < existingTombstones.length; i++) {
              var eKey = (existingTombstones[i] || "").toString().trim();
              if (!eKey) continue;
              if (unmarkedMap[eKey] || unmarkedMap[eKey.toUpperCase()]) continue;
              var activeTs = activeRecordTsMap[eKey] || activeRecordTsMap[eKey.toUpperCase()] || 0;
              var delTs = Number(existingReg[eKey] || existingReg[eKey.toUpperCase()]) || 0;
              var isUuidMatch = !!(activeIdTsMap[eKey] || activeIdTsMap[eKey.toUpperCase()]);
              // For UUID tombstones with delTs === 0, never strip just from stale snapshots unless explicitly unmarked
              var canStrip = activeTs > 0 && !incomingTombSet[eKey] &&
                (delTs > 0 ? activeTs > delTs : !isUuidMatch);
              if (canStrip) {
                continue;
              }
              mergedTombMap[eKey] = true;
            }
          }
          for (var j = 0; j < incomingTombstones.length; j++) {
            var iKey = (incomingTombstones[j] || "").toString().trim();
            if (!iKey) continue;
            if (unmarkedMap[iKey] || unmarkedMap[iKey.toUpperCase()]) continue;
            mergedTombMap[iKey] = true;
          }
          for (var hdId in hardDeletedIdTsMap) {
            if (Object.prototype.hasOwnProperty.call(hardDeletedIdTsMap, hdId)) {
              if (!unmarkedMap[hdId] && !unmarkedMap[hdId.toUpperCase()]) {
                mergedTombMap[hdId] = true;
              }
            }
          }
          if ((existingContent.files && existingContent.files["tombstones.json"]) || request.files["tombstones.json"] || Object.keys(hardDeletedIdTsMap).length > 0) {
            request.files["tombstones.json"] = JSON.stringify(Object.keys(mergedTombMap));
          }

          // Cumulative Tombstone Registry Protection: Keep max deletion timestamp per key unless unmarked/recreated
          var mergedReg = {};
          if (existingContent.files && (existingContent.files["tombstone_registry.json"] || request.files["tombstone_registry.json"] || Object.keys(hardDeletedIdTsMap).length > 0)) {
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
            for (var hdRegId in hardDeletedIdTsMap) {
              if (Object.prototype.hasOwnProperty.call(hardDeletedIdTsMap, hdRegId)) {
                if (unmarkedMap[hdRegId] || unmarkedMap[hdRegId.toUpperCase()]) continue;
                var hdTs = Number(hardDeletedIdTsMap[hdRegId]) || 0;
                var curRegTs = Number(mergedReg[hdRegId]) || 0;
                if (hdTs > curRegTs) mergedReg[hdRegId] = hdTs;
              }
            }
            request.files["tombstone_registry.json"] = JSON.stringify(mergedReg);
          }

          // Parse existing & incoming fy_vault.json BEFORE merging HWM & Challan records
          var existingVault = (existingContent.files && existingContent.files["fy_vault.json"])
            ? parseJsonObjSafe(existingContent.files["fy_vault.json"])
            : {};
          var incomingVault = request.files["fy_vault.json"]
            ? parseJsonObjSafe(request.files["fy_vault.json"])
            : {};

          // Collect monotonic global Challan High-Water Mark map across top-level + all FY slices
          var globalMergedHwm = {};
          function absorbHwmFromFilesMap(filesMap) {
            if (!filesMap || typeof filesMap !== "object") return;
            if (filesMap["challan_hwm.json"]) {
              globalMergedHwm = mergeHwmMaps(globalMergedHwm, parseJsonObjSafe(filesMap["challan_hwm.json"]));
            }
            if (filesMap["config.json"]) {
              var cObj = parseJsonObjSafe(filesMap["config.json"]);
              globalMergedHwm = mergeHwmMaps(globalMergedHwm, cObj.challanHwm || cObj.challan_hwm);
            }
          }
          absorbHwmFromFilesMap(existingContent.files);
          absorbHwmFromFilesMap(request.files);
          var fyK;
          for (fyK in existingVault) {
            if (Object.prototype.hasOwnProperty.call(existingVault, fyK)) {
              absorbHwmFromFilesMap(existingVault[fyK]);
            }
          }
          for (fyK in incomingVault) {
            if (Object.prototype.hasOwnProperty.call(incomingVault, fyK)) {
              absorbHwmFromFilesMap(incomingVault[fyK]);
            }
          }

          // Record-level UUID merge inside fy_vault.json for every FY (preserving missing FYs & merging shared FYs)
          if (Object.keys(existingVault).length > 0 || Object.keys(incomingVault).length > 0) {
            var allVaultFys = {};
            for (fyK in existingVault) {
              if (Object.prototype.hasOwnProperty.call(existingVault, fyK)) allVaultFys[fyK] = true;
            }
            for (fyK in incomingVault) {
              if (Object.prototype.hasOwnProperty.call(incomingVault, fyK)) allVaultFys[fyK] = true;
            }

            var mergedVault = {};
            for (fyK in allVaultFys) {
              if (!Object.prototype.hasOwnProperty.call(allVaultFys, fyK)) continue;
              var exSlice = parseJsonObjSafe(existingVault[fyK]);
              var inSlice = parseJsonObjSafe(incomingVault[fyK]);
              var hasInSlice = Object.prototype.hasOwnProperty.call(incomingVault, fyK) && Object.keys(inSlice).length > 0;
              var targetSlice = hasInSlice ? JSON.parse(JSON.stringify(inSlice)) : JSON.parse(JSON.stringify(exSlice));

              if (Object.prototype.hasOwnProperty.call(exSlice, "s_challan.json") || Object.prototype.hasOwnProperty.call(inSlice, "s_challan.json")) {
                targetSlice["s_challan.json"] = mergeChallanJsonString(
                  exSlice["s_challan.json"], inSlice["s_challan.json"],
                  mergedTombMap, mergedReg, incomingTombSet, unmarkedMap, fyK
                );
              }
              if (Object.prototype.hasOwnProperty.call(exSlice, "p_challan.json") || Object.prototype.hasOwnProperty.call(inSlice, "p_challan.json")) {
                targetSlice["p_challan.json"] = mergeChallanJsonString(
                  exSlice["p_challan.json"], inSlice["p_challan.json"],
                  mergedTombMap, mergedReg, incomingTombSet, unmarkedMap, fyK
                );
              }
              if (Object.prototype.hasOwnProperty.call(exSlice, "config.json") || Object.prototype.hasOwnProperty.call(inSlice, "config.json")) {
                var mCfgStr = mergeConfigWithMonotonicHwm(exSlice["config.json"], inSlice["config.json"], globalMergedHwm);
                if (mCfgStr !== null) targetSlice["config.json"] = mCfgStr;
              }
              if (Object.keys(globalMergedHwm).length > 0 || Object.prototype.hasOwnProperty.call(exSlice, "challan_hwm.json") || Object.prototype.hasOwnProperty.call(inSlice, "challan_hwm.json")) {
                targetSlice["challan_hwm.json"] = mergeHwmFileString(exSlice["challan_hwm.json"], inSlice["challan_hwm.json"], globalMergedHwm);
              }

              mergedVault[fyK] = targetSlice;
            }
            request.files["fy_vault.json"] = JSON.stringify(mergedVault);
            incomingVault = mergedVault;
          }

          // Top-level Challan & HWM merge strictly scoped to request FY (avoid mixing 2026-27 top-level into 2027-28!)
          var existingFy = (existingContent.fy || "").toString().trim();
          var sameTopFy = (!existingFy || !rootFy || existingFy === rootFy);
          var existingTopSlice = (rootFy && existingVault[rootFy]) ? parseJsonObjSafe(existingVault[rootFy]) : {};
          var mergedTopSlice = (rootFy && incomingVault[rootFy]) ? parseJsonObjSafe(incomingVault[rootFy]) : {};

          var baseExSCh = Object.prototype.hasOwnProperty.call(existingTopSlice, "s_challan.json")
            ? existingTopSlice["s_challan.json"]
            : (sameTopFy && existingContent.files ? existingContent.files["s_challan.json"] : "[]");
          if (request.files["s_challan.json"] || Object.prototype.hasOwnProperty.call(mergedTopSlice, "s_challan.json")) {
            var topMergedSCh = mergeChallanJsonString(
              baseExSCh, request.files["s_challan.json"] || "[]",
              mergedTombMap, mergedReg, incomingTombSet, unmarkedMap, rootFy
            );
            if (Object.prototype.hasOwnProperty.call(mergedTopSlice, "s_challan.json")) {
              topMergedSCh = mergeChallanJsonString(
                mergedTopSlice["s_challan.json"], topMergedSCh,
                mergedTombMap, mergedReg, incomingTombSet, unmarkedMap, rootFy
              );
              mergedTopSlice["s_challan.json"] = topMergedSCh;
              if (rootFy && incomingVault[rootFy]) {
                incomingVault[rootFy] = mergedTopSlice;
                request.files["fy_vault.json"] = JSON.stringify(incomingVault);
              }
            }
            request.files["s_challan.json"] = topMergedSCh;
          }

          var baseExPCh = Object.prototype.hasOwnProperty.call(existingTopSlice, "p_challan.json")
            ? existingTopSlice["p_challan.json"]
            : (sameTopFy && existingContent.files ? existingContent.files["p_challan.json"] : "[]");
          if (request.files["p_challan.json"] || Object.prototype.hasOwnProperty.call(mergedTopSlice, "p_challan.json")) {
            var topMergedPCh = mergeChallanJsonString(
              baseExPCh, request.files["p_challan.json"] || "[]",
              mergedTombMap, mergedReg, incomingTombSet, unmarkedMap, rootFy
            );
            if (Object.prototype.hasOwnProperty.call(mergedTopSlice, "p_challan.json")) {
              topMergedPCh = mergeChallanJsonString(
                mergedTopSlice["p_challan.json"], topMergedPCh,
                mergedTombMap, mergedReg, incomingTombSet, unmarkedMap, rootFy
              );
              mergedTopSlice["p_challan.json"] = topMergedPCh;
              if (rootFy && incomingVault[rootFy]) {
                incomingVault[rootFy] = mergedTopSlice;
                request.files["fy_vault.json"] = JSON.stringify(incomingVault);
              }
            }
            request.files["p_challan.json"] = topMergedPCh;
          }

          var baseExCfg = Object.prototype.hasOwnProperty.call(existingTopSlice, "config.json")
            ? existingTopSlice["config.json"]
            : (sameTopFy && existingContent.files ? existingContent.files["config.json"] : null);
          if (request.files["config.json"] || baseExCfg) {
            var topMergedCfg = mergeConfigWithMonotonicHwm(baseExCfg, request.files["config.json"], globalMergedHwm);
            if (topMergedCfg !== null) {
              request.files["config.json"] = topMergedCfg;
            }
          }
          if (Object.keys(globalMergedHwm).length > 0 || request.files["challan_hwm.json"] || (existingContent.files && existingContent.files["challan_hwm.json"])) {
            request.files["challan_hwm.json"] = mergeHwmFileString(
              existingContent.files ? existingContent.files["challan_hwm.json"] : null,
              request.files["challan_hwm.json"],
              globalMergedHwm
            );
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
