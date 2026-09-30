import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Safe date calculations ke liye
import 'models.dart'; // <--- YE LINE SABSE ZAROORI HAI

// --- 1. STAT WIDGET ---
class StatWidget extends StatelessWidget {
  final String title, value, period;
  final String icon; 
  final Color color;
  const StatWidget({super.key, required this.title, required this.value, required this.period, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    IconData getIconData(String name) {
      switch (name) {
        case "trending_up": return Icons.trending_up_rounded;
        case "shopping_cart": return Icons.shopping_cart_rounded;
        case "payments": return Icons.payments_rounded;
        case "inventory_2": return Icons.inventory_2_rounded;
        default: return Icons.analytics_rounded;
      }
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 8))], border: Border.all(color: color.withOpacity(0.05), width: 1)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(getIconData(icon), color: color, size: 20)),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(8)), child: Text(period.toUpperCase(), style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5))),
          ]),
          const SizedBox(height: 10),
          Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1A237E)))),
      ]),
    );
  }
}

// --- 2. ACTION ICON BUTTON ---
class ActionIconBtn extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const ActionIconBtn({super.key, required this.title, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.grey.shade100, width: 1.5), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(height: 52, width: 52, decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color, size: 28)),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800)),
    ])));
  }
}

// --- 3. SMART GRID (REPLACEMENT CODE) ---
class PharoahSmartGrid extends StatelessWidget {
  final List<ModuleAction> actions;
  final Function(ModuleAction) onActionTap;

  const PharoahSmartGrid({
    super.key,
    required this.actions,
    required this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemBuilder: (context, index) {
        final action = actions[index];
        return ActionIconBtn(
          title: action.title,
          icon: action.icon,
          color: action.color,
          onTap: () => onActionTap(action),
        );
      },
    );
  }
}

// =============================================================================
// 📠 MARG-STYLE HIGH-DENSITY BATCH LOOKUP DIALOG (WHOLESALE COMPLIANT)
// =============================================================================

class MargBatchLookupDialog extends StatefulWidget {
  final Medicine medicine;
  final List<BatchInfo> batches;
  final bool prioritizeExpired; // Return screens me true pass karenge

  const MargBatchLookupDialog({
    super.key,
    required this.medicine,
    required this.batches,
    this.prioritizeExpired = false,
  });

  @override
  State<MargBatchLookupDialog> createState() => _MargBatchLookupDialogState();
}

class _MargBatchLookupDialogState extends State<MargBatchLookupDialog> {
  // June 2026 system date context
  final DateTime systemToday = DateTime.now();

  DateTime _parseExpiry(String exp) {
    try {
      final parts = exp.split('/');
      int m = int.parse(parts[0]);
      int y = 2000 + int.parse(parts[1]);
      return DateTime(y, m + 1, 0); // Month ka last day
    } catch (_) {
      return DateTime(2100);
    }
  }

  bool _isExpired(String exp) {
    if (exp.isEmpty || !exp.contains('/')) return false;
    return _parseExpiry(exp).isBefore(systemToday);
  }

  bool _isNearExpiry(String exp) {
    if (exp.isEmpty || !exp.contains('/')) return false;
    DateTime expDate = _parseExpiry(exp);
    if (expDate.isBefore(systemToday)) return false;
    return expDate.difference(systemToday).inDays <= 180; // 6 months alert
  }

  @override
  Widget build(BuildContext context) {
    // 1. Expiry sorting logic
    final sortedBatches = List<BatchInfo>.from(widget.batches);
    if (widget.prioritizeExpired) {
      // Returns me expired batches ko automatic sabse upar dikhayein
      sortedBatches.sort((a, b) {
        bool aExp = _isExpired(a.exp);
        bool bExp = _isExpired(b.exp);
        if (aExp && !bExp) return -1;
        if (!aExp && bExp) return 1;
        return _parseExpiry(a.exp).compareTo(_parseExpiry(b.exp));
      });
    } else {
      // Standard FIFO: Nearest Expiry ko pehle nikalne ke liye
      sortedBatches.sort((a, b) => _parseExpiry(a.exp).compareTo(_parseExpiry(b.exp)));
    }

    double grandTotalQty = widget.batches.fold(0.0, (sum, b) => sum + b.qty);
    int activeBatchesCount = widget.batches.where((b) => !_isExpired(b.exp)).length;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      backgroundColor: const Color(0xFF1E293B), // Premium Dark Slate
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "SELECT BATCH - ${widget.medicine.name}",
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            "Select batch to autofill prices & details",
            style: TextStyle(color: Colors.white54, fontSize: 9),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Table Column Headers
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              color: const Color(0xFF0F172A),
              child: Row(
                children: const [
                  Expanded(flex: 3, child: Text("BATCH NO", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold))),
                  Expanded(flex: 2, child: Text("EXPIRY", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold))),
                  Expanded(flex: 2, child: Text("MRP", textAlign: TextAlign.right, style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold))),
                  Expanded(flex: 2, child: Text("RATE A", textAlign: TextAlign.right, style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold))),
                  Expanded(flex: 3, child: Text("LIVE STOCK", textAlign: TextAlign.right, style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold))),
                ],
              ),
            ),
            const SizedBox(height: 5),

            // Scrollable List of Batches
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: sortedBatches.length,
                itemBuilder: (context, idx) {
                  final b = sortedBatches[idx];
                  bool expired = _isExpired(b.exp);
                  bool nearExp = _isNearExpiry(b.exp);

                  Color rowColor = Colors.white;
                  String statusText = "Active";
                  if (expired) {
                    rowColor = Colors.red.shade400;
                    statusText = "Expired";
                  } else if (nearExp) {
                    rowColor = Colors.orangeAccent;
                    statusText = "Near Exp";
                  }

                  return InkWell(
                    onTap: () {
                      Navigator.pop(context, b); // Selected Batch ka data text-fields me load karega
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
                      ),
                      child: Row(
                        children: [
                          Expanded(flex: 3, child: Text(b.batch, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                          Expanded(flex: 2, child: Text(b.exp, style: TextStyle(color: rowColor, fontWeight: FontWeight.bold, fontSize: 11))),
                          Expanded(flex: 2, child: Text("₹${b.mrp.toStringAsFixed(2)}", textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70, fontSize: 11))),
                          Expanded(flex: 2, child: Text("₹${b.rateA.toStringAsFixed(2)}", textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70, fontSize: 11))),
                          Expanded(
                            flex: 3, 
                            child: Text(
                              "${b.qty.toInt()} ($statusText)", 
                              textAlign: TextAlign.right, 
                              style: TextStyle(color: rowColor, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 15),

            // Wholesale Compliant Bottom Summary Bar (No unit/tabs suffix)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("TOTAL ITEM STOCK", style: TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.bold)),
                      Text(
                        "${grandTotalQty.toInt()}", // Direct Plain Numeric Value
                        style: const TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Text(
                    "Active Batches: $activeBatchesCount", 
                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context, "MANUAL"); // Manual Entry signal
                    },
                    icon: const Icon(Icons.add_circle_outline, size: 14, color: Colors.orangeAccent),
                    label: const Text("New Manual", style: TextStyle(color: Colors.orangeAccent, fontSize: 11)),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
