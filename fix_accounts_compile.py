import re

# 1. Fix web_voucher_entry_view.dart (Remove unused imports)
p1 = 'lib/web_live_sync/sub_views/web_accounts/web_voucher_entry_view.dart'
with open(p1, 'r', encoding='utf-8') as f:
    c1 = f.read()

c1 = c1.replace("import 'package:intl/intl.dart';\n", "")
c1 = c1.replace("import '../../web_pharoah_numbering_engine.dart';\n", "")
c1 = c1.replace("import '../../web_pdf_router_service.dart';\n", "")

with open(p1, 'w', encoding='utf-8') as f:
    f.write(c1)
print('✔ Cleaned: web_voucher_entry_view.dart')

# 2. Fix web_voucher_view.dart (Remove bad provider import & unused imports)
p2 = 'lib/web_live_sync/web_voucher_view.dart'
with open(p2, 'r', encoding='utf-8') as f:
    c2 = f.read()

c2 = c2.replace("import 'provider.dart' if (dart.library.html) 'package:provider/provider.dart';\n", "")
c2 = c2.replace("import 'web_models.dart';\n", "")
c2 = c2.replace("import 'web_app_date_logic.dart';\n", "")

with open(p2, 'w', encoding='utf-8') as f:
    f.write(c2)
print('✔ Cleaned: web_voucher_view.dart')

# 3. Add getPendingBills and isCashLimitExceeded to PharoahWebManager
p3 = 'lib/web_live_sync/pharoah_web_manager.dart'
with open(p3, 'r', encoding='utf-8') as f:
    c3 = f.read()

accounts_engine_methods = """
  // ===========================================================================
  // 💰 VOUCHER & ACCOUNTS HELPER ENGINE
  // ===========================================================================
  List<Map<String, dynamic>> getPendingBills(String partyId, bool isReceipt) {
    List<Map<String, dynamic>> pending = [];
    DateTime now = DateTime.now();

    if (isReceipt) {
      for (var s in sales.where((s) => (s.partyId == partyId || s.partyName == partyId) && s.paymentMode == "CREDIT" && s.status == "Active")) {
        bool alreadySettled = vouchers.any((v) => v.linkedBillNumbers.contains(s.billNo) && v.status == "Active");
        if (!alreadySettled) {
          int days = now.difference(s.date).inDays;
          pending.add({'date': s.date, 'billNo': s.billNo, 'amount': s.totalAmount, 'dueDays': days});
        }
      }
    } else {
      for (var p in purchases.where((p) => (p.partyId == partyId || p.distributorName == partyId))) {
        bool alreadySettled = vouchers.any((v) => v.linkedBillNumbers.contains(p.billNo) && v.status == "Active");
        if (!alreadySettled) {
          int days = now.difference(p.date).inDays;
          pending.add({'date': p.date, 'billNo': p.billNo, 'amount': p.totalAmount, 'dueDays': days});
        }
      }
    }
    pending.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
    return pending;
  }

  bool isCashLimitExceeded(String partyId, double newAmount) {
    DateTime today = DateTime.now();
    double todayTotal = vouchers
        .where((v) => v.partyId == partyId && v.paymentMode == "Cash" && 
                v.date.day == today.day && v.date.month == today.month && v.status == "Active")
        .fold(0.0, (sum, v) => sum + v.amount);
    return (todayTotal + newAmount) > 200000;
  }
"""

if 'List<Map<String, dynamic>> getPendingBills' not in c3:
    last_brace = c3.rfind('}')
    if last_brace != -1:
        c3 = c3[:last_brace] + accounts_engine_methods + "\n}\n"
        with open(p3, 'w', encoding='utf-8') as f:
            f.write(c3)
        print('✔ Added accounts helper methods to PharoahWebManager')

