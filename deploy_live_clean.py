import re
import subprocess
import sys

# 1. Clean web_party_ledger_pdf.dart
p1 = 'lib/web_live_sync/pdf/web_party_ledger_pdf.dart'
try:
    with open(p1, 'r', encoding='utf-8') as f:
        c1 = f.read()
    c1 = c1.replace("import 'package:pharoah_erp/pdf/pdf_master_service.dart';\n", "")
    with open(p1, 'w', encoding='utf-8') as f:
        f.write(c1)
    print('✔ Fixed: web_party_ledger_pdf.dart')
except Exception as e:
    print('Error on p1:', e)

# 2. Clean pharoah_web_manager.dart
p2 = 'lib/web_live_sync/pharoah_web_manager.dart'
try:
    with open(p2, 'r', encoding='utf-8') as f:
        c2 = f.read()

    new_date_filter = """    DateTime fStart = DateTime(fromDate.year, fromDate.month, fromDate.day);
    DateTime tEnd = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);

    for (var txn in allTxns) {
      DateTime tDate = txn['date'] as DateTime;
      if (tDate.isBefore(fStart)) {
        periodOpBal += ((txn['dr'] as double) - (txn['cr'] as double));
      } else if (!tDate.isAfter(tEnd)) {
        filteredLedger.add(txn);
      }
    }"""

    c2 = re.sub(
        r'DateTime fStart = DateTime\(fromDate\.year, fromDate\.month, fromDate\.day\);\s*DateTime tEnd = DateTime\(toDate\.year, toDate\.month, toDate\.day, 23, 59, 59\);.*?for \(var txn in allTxns\) \{.*?\}',
        new_date_filter,
        c2,
        flags=re.DOTALL
    )

    with open(p2, 'w', encoding='utf-8') as f:
        f.write(c2)
    print('✔ Fixed: pharoah_web_manager.dart')
except Exception as e:
    print('Error on p2:', e)

# 3. Clean web_ledger_view.dart
p3 = 'lib/web_live_sync/web_ledger_view.dart'
try:
    with open(p3, 'r', encoding='utf-8') as f:
        c3 = f.read()

    c3 = re.sub(
        r"selectedParty!\.city\.isNotEmpty \? ', ' \+ selectedParty!\.city : ''",
        "selectedParty!.city.isNotEmpty ? ', ${selectedParty!.city}' : ''",
        c3
    )

    with open(p3, 'w', encoding='utf-8') as f:
        f.write(c3)
    print('✔ Fixed: web_ledger_view.dart')
except Exception as e:
    print('Error on p3:', e)

# 4. Bump Tag in web_top_bar.dart
tb_path = 'lib/web_live_sync/components/web_top_bar.dart'
try:
    with open(tb_path, 'r', encoding='utf-8') as f:
        tb = f.read()
    new_tag = '#PH-REV-597 (LIVE-READY-DEPLOY)'
    tb = re.sub(r'#PH-REV-\d+[^\"]*', new_tag, tb)
    with open(tb_path, 'w', encoding='utf-8') as f:
        f.write(tb)
    print('✔ Updated Tag: ' + new_tag)
except Exception as e:
    print('Error on tag:', e)

