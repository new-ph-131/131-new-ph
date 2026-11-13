// FILE: lib/web_live_sync/web_models.dart

export '../models.dart';
export '../gateway/company_registry_model.dart';
export '../administration/system_user_model.dart';
export '../logic/app_settings_model.dart';
export '../gst/gst_diary/gst_diary_models.dart';

import '../models.dart';

/// Web-specific Helper Extensions
extension WebMedicineExtension on Medicine {
  String get displayStock => "${formatQty(stock)} $packing";
}

extension WebPartyExtension on Party {
  bool get isDebtor => group == "Sundry Debtors";
  bool get isCreditor => group == "Sundry Creditors";
}
