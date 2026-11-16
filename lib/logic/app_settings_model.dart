// FILE: lib/logic/app_settings_model.dart

import 'dart:math' show max;
import '../models.dart' show SaleChallan, PurchaseChallan, normalizeFyString;

class ChallanHwmState {
  int value;
  int seq;
  int gen;
  String op; // "SET" or "ROLLBACK"
  int updatedAt;
  int deletedNum;
  String tombUuid;

  ChallanHwmState({
    required this.value,
    this.seq = 0,
    this.gen = 0,
    this.op = 'SET',
    this.updatedAt = 0,
    this.deletedNum = 0,
    this.tombUuid = '',
  });

  ChallanHwmState copy() => ChallanHwmState(
        value: value,
        seq: seq,
        gen: gen,
        op: op,
        updatedAt: updatedAt,
        deletedNum: deletedNum,
        tombUuid: tombUuid,
      );

  Map<String, dynamic> toMap() => {
        'v': value,
        'value': value,
        'seq': seq,
        'gen': gen,
        'op': op,
        'ts': updatedAt,
        'updatedAt': updatedAt,
        if (deletedNum > 0) 'deletedNum': deletedNum,
        if (tombUuid.isNotEmpty) 'tombUuid': tombUuid,
      };

  static int _parseInt(dynamic raw, [int fallback = 0]) {
    if (raw == null) return fallback;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString()) ?? fallback;
  }

  factory ChallanHwmState.fromMap(Map<dynamic, dynamic> raw) {
    final int val = _parseInt(raw['v'] ?? raw['value'], 0);
    final String rawOp = (raw['op'] ?? 'SET').toString().trim().toUpperCase();
    final String normOp = rawOp == 'ROLLBACK' ? 'ROLLBACK' : 'SET';
    final int parsedGen = _parseInt(raw['gen'], val);
    return ChallanHwmState(
      value: val < 0 ? 0 : val,
      seq: _parseInt(raw['seq'], 0),
      gen: parsedGen < 0 ? 0 : parsedGen,
      op: normOp,
      updatedAt: _parseInt(raw['ts'] ?? raw['updatedAt'] ?? raw['updated_at'], 0),
      deletedNum: _parseInt(raw['deletedNum'], 0),
      tombUuid: (raw['tombUuid'] ?? '').toString().trim(),
    );
  }
}

class AppConfig {
  String salePrefix;
  String saleChallanPrefix;
  String saleReturnPrefix;
  String purPrefix;
  String purReturnPrefix;
  bool isArchitectMode;
  bool useZebraShading;
  bool showStaffSign;
  String signLabel;
  bool showCustomerSignChallan;
  bool showLogo;
  String? logoPath;
  String printFormat;
  bool askFormatEveryTime;
  bool showQrCode;
  String? qrCodePath;
  String bankAccName;
  String bankAccNumber;
  String bankIfsc;
  String bankNameBranch;
  bool showTerms;
  String termsAndConditions;

  // --- 📬 DISPATCH / MAIL CONFIGURATION (Email Word Removed) ---
  bool isMailActive;      // Pehle isEmailActive tha
  String smtpMailID;      // Pehle smtpEmail tha
  String smtpMailPass;    // Pehle smtpPassword tha
  String smtpHost;
  int smtpPort;

  // --- 🛡️ CA AUDIT NEXUS ---
  String caName;
  String caMailID;        // Pehle caEmail tha
  String caPhone;
  bool isAuditMode;

  // --- 🔐 USER CONTROL & DEVELOPER SECURITY ACCESS ---
  String developerPassword;
  String userMasterPin;
  bool developerAllowBatchHistoryToUser;
  bool userEnableBatchHistory;
  bool developerAllowGstDiaryToUser;
  bool userEnableGstDiary;
  int version;
  int updatedAt;
  Map<String, int> challanHwm;
  Map<String, ChallanHwmState> challanHwmMeta;
  bool challanHwmTailMigrated;

  AppConfig({
    this.salePrefix = "INV-",
    this.saleChallanPrefix = "SCH-",
    this.saleReturnPrefix = "SRN-",
    this.purPrefix = "PUR-",
    this.purReturnPrefix = "PRN-",
    this.isArchitectMode = false,
    this.useZebraShading = true,
    this.showStaffSign = true,
    this.signLabel = "Authorised Signatory",
    this.showCustomerSignChallan = false,
    this.showLogo = true,
    this.logoPath,
    this.printFormat = "A4",
    this.askFormatEveryTime = false,
    this.showQrCode = false,
    this.qrCodePath,
    this.bankAccName = "",
    this.bankAccNumber = "",
    this.bankIfsc = "",
    this.bankNameBranch = "",
    this.showTerms = true,
    this.termsAndConditions = "1. Goods once sold will not be taken back.\n2. All disputes subject to local jurisdiction.",

    // Default Mail Values
    this.isMailActive = false,
    this.smtpMailID = "",
    this.smtpMailPass = "",
    this.smtpHost = "smtp.gmail.com",
    this.smtpPort = 587,

    // CA Nexus Defaults
    this.caName = "",
    this.caMailID = "",
    this.caPhone = "",
    this.isAuditMode = false,

    // Developer & User Access Control Defaults
    this.developerPassword = "Rawat@1122",
    this.userMasterPin = "1234",
    this.developerAllowBatchHistoryToUser = true,
    this.userEnableBatchHistory = true,
    this.developerAllowGstDiaryToUser = true,
    this.userEnableGstDiary = true,
    this.version = 1,
    this.updatedAt = 0,
    Map<String, int>? challanHwm,
    Map<String, ChallanHwmState>? challanHwmMeta,
    this.challanHwmTailMigrated = false,
  })  : challanHwm = challanHwm != null ? Map<String, int>.from(challanHwm) : <String, int>{},
        challanHwmMeta = challanHwmMeta != null
            ? challanHwmMeta.map((k, v) => MapEntry(k, v.copy()))
            : <String, ChallanHwmState>{};

  Map<String, dynamic> toMap() {
    return {
      'salePrefix': salePrefix,
      'saleChallanPrefix': saleChallanPrefix,
      'saleReturnPrefix': saleReturnPrefix,
      'purPrefix': purPrefix,
      'purReturnPrefix': purReturnPrefix,
      'isArchitectMode': isArchitectMode,
      'useZebraShading': useZebraShading,
      'showStaffSign': showStaffSign,
      'signLabel': signLabel,
      'showCustomerSignChallan': showCustomerSignChallan,
      'showLogo': showLogo,
      'logoPath': logoPath,
      'printFormat': printFormat,
      'askFormatEveryTime': askFormatEveryTime,
      'showQrCode': showQrCode,
      'qrCodePath': qrCodePath,
      'bankAccName': bankAccName,
      'bankAccNumber': bankAccNumber,
      'bankIfsc': bankIfsc,
      'bankNameBranch': bankNameBranch,
      'showTerms': showTerms,
      'termsAndConditions': termsAndConditions,
      // Mapping
      'isMailActive': isMailActive,
      'smtpMailID': smtpMailID,
      'smtpMailPass': smtpMailPass,
      'smtpHost': smtpHost,
      'smtpPort': smtpPort,
      'caName': caName,
      'caMailID': caMailID,
      'caPhone': caPhone,
      'isAuditMode': isAuditMode,

      // Access Control
      'developerPassword': developerPassword,
      'userMasterPin': userMasterPin,
      'developerAllowBatchHistoryToUser': developerAllowBatchHistoryToUser,
      'userEnableBatchHistory': userEnableBatchHistory,
      'developerAllowGstDiaryToUser': developerAllowGstDiaryToUser,
      'userEnableGstDiary': userEnableGstDiary,
      'version': version,
      'updatedAt': updatedAt,
      'challanHwm': Map<String, int>.from(challanHwm),
      'challanHwmMeta': challanHwmMeta.map((k, v) => MapEntry(k, v.toMap())),
      'challanHwmTailMigrated': challanHwmTailMigrated,
    };
  }

  factory AppConfig.fromMap(Map<String, dynamic> map) {
    final bool rawMigrated = map['challanHwmTailMigrated'] == true ||
        map['challan_hwm_tail_migrated'] == true ||
        map['challanHwmTailMigrated']?.toString().toLowerCase() == 'true';
    return AppConfig(
      salePrefix: map['salePrefix'] ?? "INV-",
      saleChallanPrefix: map['saleChallanPrefix'] ?? "SCH-",
      saleReturnPrefix: map['saleReturnPrefix'] ?? "SRN-",
      purPrefix: map['purPrefix'] ?? "PUR-",
      purReturnPrefix: map['purReturnPrefix'] ?? "PRN-",
      isArchitectMode: map['isArchitectMode'] ?? false,
      useZebraShading: map['useZebraShading'] ?? true,
      showStaffSign: map['showStaffSign'] ?? true,
      signLabel: map['signLabel'] ?? "Authorised Signatory",
      showCustomerSignChallan: map['showCustomerSignChallan'] ?? false,
      showLogo: map['showLogo'] ?? true,
      logoPath: map['logoPath'],
      printFormat: map['printFormat'] ?? "A4",
      askFormatEveryTime: map['askFormatEveryTime'] ?? false,
      showQrCode: map['showQrCode'] ?? false,
      qrCodePath: map['qrCodePath'],
      bankAccName: map['bankAccName'] ?? "",
      bankAccNumber: map['bankAccNumber'] ?? "",
      bankIfsc: map['bankIfsc'] ?? "",
      bankNameBranch: map['bankNameBranch'] ?? "",
      showTerms: map['showTerms'] ?? true,
      termsAndConditions: map['termsAndConditions'] ?? "",

      // Migration Logic: Agar purana 'Email' key milti hai toh use naye 'Mail' mein load karein
      isMailActive: map['isMailActive'] ?? map['isEmailActive'] ?? false,
      smtpMailID: map['smtpMailID'] ?? map['smtpEmail'] ?? "",
      smtpMailPass: map['smtpMailPass'] ?? map['smtpPassword'] ?? "",

      smtpHost: map['smtpHost'] ?? "smtp.gmail.com",
      smtpPort: map['smtpPort'] ?? 587,

      caName: map['caName'] ?? "",
      caMailID: map['caMailID'] ?? map['caEmail'] ?? "",
      caPhone: map['caPhone'] ?? "",
      isAuditMode: map['isAuditMode'] ?? false,

      developerPassword: map['developerPassword'] ?? "Rawat@1122",
      userMasterPin: map['userMasterPin'] ?? "1234",
      developerAllowBatchHistoryToUser: map['developerAllowBatchHistoryToUser'] ?? true,
      userEnableBatchHistory: map['userEnableBatchHistory'] ?? true,
      developerAllowGstDiaryToUser: (int.tryParse(map['updatedAt']?.toString() ?? '0') ?? 0) == 0
          ? true
          : (map['developerAllowGstDiaryToUser'] ?? true),
      userEnableGstDiary: (int.tryParse(map['updatedAt']?.toString() ?? '0') ?? 0) == 0
          ? true
          : (map['userEnableGstDiary'] ?? true),
      version: int.tryParse(map['version']?.toString() ?? '1') ?? 1,
      updatedAt: int.tryParse(map['updatedAt']?.toString() ?? '0') ?? 0,
      challanHwm: parseHwmMap(map['challanHwm'] ?? map['challan_hwm']),
      challanHwmMeta: parseHwmMetaMap(map['challanHwmMeta'] ?? map['challan_hwm_meta']),
      challanHwmTailMigrated: rawMigrated,
    );
  }

  /// Parses raw JSON map or object into strongly-typed Map<String, int>
  static Map<String, int> parseHwmMap(dynamic raw) {
    final Map<String, int> result = {};
    if (raw is Map) {
      raw.forEach((k, v) {
        final key = k.toString().trim();
        final val = int.tryParse(v?.toString() ?? '');
        if (key.isNotEmpty && val != null && val >= 0) {
          result[key] = val;
        }
      });
    }
    return result;
  }

  /// Parses raw JSON map into strongly-typed Map<String, ChallanHwmState>
  static Map<String, ChallanHwmState> parseHwmMetaMap(dynamic raw) {
    final Map<String, ChallanHwmState> result = {};
    if (raw is Map) {
      raw.forEach((k, v) {
        final key = k.toString().trim();
        if (key.isNotEmpty && v is Map) {
          result[key] = ChallanHwmState.fromMap(v);
        }
      });
    }
    return result;
  }

  static final RegExp _seriesNumRegex = RegExp(r'^(.*?)(\d+)$');

  /// Extracts exact `(prefix, number)` from a series document string (e.g., `WSCH-12` -> `("WSCH-", 12)`).
  static ({String prefix, int? number}) parseSeriesNumber(String docNo) {
    final clean = docNo.trim().toUpperCase();
    if (clean.isEmpty) return (prefix: '', number: null);
    final match = _seriesNumRegex.firstMatch(clean);
    if (match == null) return (prefix: '', number: null);
    final String prefix = (match.group(1) ?? '').trim();
    final int? number = int.tryParse(match.group(2) ?? '');
    if (prefix.isEmpty || number == null) return (prefix: '', number: null);
    return (prefix: prefix, number: number);
  }

  static bool inferIsWebChallanRecord(dynamic item) {
    try {
      if (item is SaleChallan) {
        return item.id.trim().startsWith("SCH-WEB") ||
            item.salesmanName.trim().toUpperCase() == "WEB-PORTAL" ||
            item.billNo.trim().toUpperCase().startsWith("WSCH-");
      }
      if (item is PurchaseChallan) {
        return item.id.trim().startsWith("PCH-WEB") ||
            item.internalNo.trim().toUpperCase().startsWith("WPCH-") ||
            item.remarks.contains("WEB-PORTAL");
      }
      if (item is Map) {
        final id = (item['id'] ?? '').toString().trim();
        final sm = (item['salesmanName'] ?? '').toString().trim().toUpperCase();
        final rem = (item['remarks'] ?? '').toString();
        final bNo = (item['billNo'] ?? '').toString().trim().toUpperCase();
        final iNo = (item['internalNo'] ?? '').toString().trim().toUpperCase();
        return id.startsWith("SCH-WEB") ||
            id.startsWith("PCH-WEB") ||
            sm == "WEB-PORTAL" ||
            rem.contains("WEB-PORTAL") ||
            bNo.startsWith("WSCH-") ||
            iNo.startsWith("WPCH-");
      }
    } catch (_) {}
    return false;
  }

  /// Computes authoritative non-deleted Challan floor per scope key
  /// `${companyID}::${fy}::${normType}::${env}::${prefix}` from Active + Billed + Cancelled challans.
  static Map<String, int> computeChallanRecordFloor({
    required String companyID,
    Iterable<dynamic> saleChallans = const [],
    Iterable<dynamic> purchaseChallans = const [],
    String? targetFy,
  }) {
    final Map<String, int> floor = {};
    final String cleanComp = companyID.trim();
    final String cleanTargetFy = normalizeFyString(targetFy ?? '');

    void inspect(dynamic item, bool isPurchase) {
      if (item == null) return;
      String rawNo = '';
      String rawFy = '';
      int isDeleted = 0;
      String status = '';
      if (item is SaleChallan) {
        isDeleted = item.isDeleted;
        status = item.status.trim().toUpperCase();
        rawNo = item.billNo;
        rawFy = item.effectiveOriginalFy;
      } else if (item is PurchaseChallan) {
        isDeleted = item.isDeleted;
        status = item.status.trim().toUpperCase();
        rawNo = item.internalNo;
        rawFy = item.effectiveOriginalFy;
      } else if (item is Map) {
        isDeleted = int.tryParse((item['isDeleted'] ?? item['is_deleted'] ?? '0').toString()) ?? 0;
        status = (item['status'] ?? '').toString().trim().toUpperCase();
        rawNo = (isPurchase ? (item['internalNo'] ?? '') : (item['billNo'] ?? '')).toString();
        rawFy = normalizeFyString((item['originalFy'] ?? item['original_fy'] ?? item['fy'] ?? '').toString());
      } else {
        return;
      }

      if (isDeleted == 1 || status == 'DELETED') return;
      final String itemFy = normalizeFyString(rawFy.isNotEmpty ? rawFy : cleanTargetFy);
      if (cleanTargetFy.isNotEmpty && cleanTargetFy != 'default_fy' && itemFy != cleanTargetFy) {
        return;
      }
      final parsed = parseSeriesNumber(rawNo);
      if (parsed.prefix.isEmpty || parsed.number == null) return;
      final String env = inferIsWebChallanRecord(item) ? 'WEB' : 'APP';
      final String normType = isPurchase ? 'PURCHASE_CHALLAN' : 'SALE_CHALLAN';
      final String key = '${cleanComp}::${itemFy}::${normType}::${env}::${parsed.prefix}';
      if (parsed.number! > (floor[key] ?? 0)) {
        floor[key] = parsed.number!;
      }
    }

    for (final sc in saleChallans) {
      inspect(sc, false);
    }
    for (final pc in purchaseChallans) {
      inspect(pc, true);
    }
    return floor;
  }

  /// Resolves two HWM state entries without depending on client wall-clock timestamps.
  /// Priority order when at least one entry is ROLLBACK:
  /// 1) Server-authoritative D1 `seq` (when both > 0 and distinct)
  /// 2) Per-scope monotonic causal Lamport `gen`
  /// 3) Tie-breaker: `SET` over `ROLLBACK`, then higher `value`
  static ChallanHwmState resolveCausalHwmState(
    ChallanHwmState? a,
    ChallanHwmState? b, {
    int floor = 0,
  }) {
    late ChallanHwmState chosen;
    final int maxGenAB = max(a?.gen ?? 0, b?.gen ?? 0);
    if (a == null && b == null) {
      chosen = ChallanHwmState(value: floor > 0 ? floor : 0, gen: floor > 0 ? floor : 0, op: 'SET');
    } else if (a == null) {
      chosen = b!.copy();
    } else if (b == null) {
      chosen = a.copy();
    } else if (a.op != 'ROLLBACK' && b.op != 'ROLLBACK') {
      chosen = ChallanHwmState(
        value: max(a.value, b.value),
        seq: max(a.seq, b.seq),
        gen: maxGenAB,
        op: 'SET',
        updatedAt: max(a.updatedAt, b.updatedAt),
      );
    } else {
      bool aWins;
      if (a.seq > 0 && b.seq > 0 && a.seq != b.seq) {
        aWins = a.seq > b.seq;
      } else if (a.gen != b.gen) {
        aWins = a.gen > b.gen;
      } else if (a.op != b.op) {
        aWins = a.op != 'ROLLBACK';
      } else {
        aWins = a.value >= b.value;
      }
      chosen = (aWins ? a : b).copy();
      if (chosen.seq < max(a.seq, b.seq) && chosen.op != 'ROLLBACK') {
        chosen.seq = max(a.seq, b.seq);
      }
    }

    if (floor > chosen.value) {
      chosen = ChallanHwmState(
        value: floor,
        seq: max(a?.seq ?? 0, b?.seq ?? 0),
        gen: max(maxGenAB, chosen.gen) + 1,
        op: 'SET',
        updatedAt: chosen.updatedAt,
      );
    }
    return chosen;
  }

  /// Causally merges `challanHwm` + `challanHwmMeta` with an optional non-deleted `recordFloor`.
  static ({Map<String, int> hwm, Map<String, ChallanHwmState> meta}) mergeHwmMapsWithMeta({
    required Map<String, int> localHwm,
    required Map<String, ChallanHwmState> localMeta,
    required Map<String, int> remoteHwm,
    required Map<String, ChallanHwmState> remoteMeta,
    Map<String, int> recordFloor = const {},
  }) {
    final Set<String> allKeys = {
      ...localHwm.keys,
      ...localMeta.keys,
      ...remoteHwm.keys,
      ...remoteMeta.keys,
      ...recordFloor.keys,
    };
    final Map<String, int> outHwm = {};
    final Map<String, ChallanHwmState> outMeta = {};

    ChallanHwmState? derive(String k, Map<String, int> hwm, Map<String, ChallanHwmState> meta) {
      final hasMeta = meta.containsKey(k);
      final hasHwm = hwm.containsKey(k);
      if (!hasMeta && !hasHwm) return null;
      final int rawV = hwm[k] ?? 0;
      if (hasMeta) {
        final s = meta[k]!.copy();
        if (s.op == 'SET' && rawV > s.value) {
          s.value = rawV;
          if (rawV > s.gen) s.gen = rawV;
        }
        return s;
      }
      return ChallanHwmState(
        value: rawV < 0 ? 0 : rawV,
        seq: 0,
        gen: rawV < 0 ? 0 : rawV,
        op: 'SET',
        updatedAt: 0,
      );
    }

    for (final rawK in allKeys) {
      final k = rawK.trim();
      if (k.isEmpty) continue;
      final a = derive(k, localHwm, localMeta);
      final b = derive(k, remoteHwm, remoteMeta);
      final int floor = recordFloor[k] ?? 0;
      final resolved = resolveCausalHwmState(a, b, floor: floor);
      if (resolved.value > 0) {
        outHwm[k] = resolved.value;
      }
      if (resolved.value > 0 || resolved.op == 'ROLLBACK') {
        outMeta[k] = resolved;
      }
    }

    return (hwm: outHwm, meta: outMeta);
  }

  /// Backward-compatible SET-only monotonic helper preserved for existing callers.
  static Map<String, int> mergeHwmMaps(Map<String, int> a, Map<String, int> b) {
    final Map<String, int> merged = Map<String, int>.from(a);
    b.forEach((k, v) {
      final existing = merged[k] ?? 0;
      if (v > existing) {
        merged[k] = v;
      }
    });
    return merged;
  }

  /// Causally merges incoming `AppConfig` with `current`, preserving non-monotonic rollbacks
  /// when `challanHwmMeta` causality dictates while taking newer general settings.
  static AppConfig mergeAppConfigWithCausalHwm({
    required AppConfig local,
    required AppConfig incoming,
    Map<String, int> recordFloor = const {},
    bool incomingFieldsWin = false,
  }) {
    final mergedState = mergeHwmMapsWithMeta(
      localHwm: local.challanHwm,
      localMeta: local.challanHwmMeta,
      remoteHwm: incoming.challanHwm,
      remoteMeta: incoming.challanHwmMeta,
      recordFloor: recordFloor,
    );
    final bool useIncoming = incomingFieldsWin ||
        local.updatedAt == 0 ||
        incoming.updatedAt > local.updatedAt ||
        incoming.version > local.version;
    final AppConfig target = useIncoming ? AppConfig.fromMap(incoming.toMap()) : AppConfig.fromMap(local.toMap());
    target.challanHwm = mergedState.hwm;
    target.challanHwmMeta = mergedState.meta;
    target.challanHwmTailMigrated = local.challanHwmTailMigrated || incoming.challanHwmTailMigrated;
    return target;
  }
}
