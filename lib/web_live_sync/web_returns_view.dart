// FILE: lib/web_live_sync/web_returns_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'web_models.dart';
import 'pharoah_web_manager.dart';
import 'web_app_date_logic.dart';
import 'web_pdf_router_service.dart';

class WebReturnsView extends StatefulWidget {
  final VoidCallback onBack;
  final String initialAction;
  final int initialTabIndex;

  const WebReturnsView({
    super.key,
    required this.onBack,
    this.initialAction = "RETURNS",
    this.initialTabIndex = -1,
  });

  @override
  State<WebReturnsView> createState() => _WebReturnsViewState();
}

class _WebReturnsViewState extends State<WebReturnsView> {
  late String activeSubView; // "HUB", "CN", "DN", "BREAKAGE", "REGISTER"

  DateTime regFromDate = DateTime.now();
  DateTime regToDate = DateTime.now();
  String registerSearch = "";
  bool _isInit = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialAction == "GO_CN" || widget.initialTabIndex == 0) {
      activeSubView = "CN";
    } else if (widget.initialAction == "GO_DN" || widget.initialTabIndex == 1) {
      activeSubView = "DN";
    } else if (widget.initialAction == "GO_BREAKAGE") {
      activeSubView = "BREAKAGE";
    } else if (widget.initialAction == "GO_RET_REG" || widget.initialTabIndex == 2) {
      activeSubView = "REGISTER";
    } else {
      activeSubView = "HUB";
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final webPh = Provider.of<PharoahWebManager>(context, listen: false);
      final now = DateTime.now();
      regToDate = DateTime(now.year, now.month, now.day);
      DateTime thirtyDaysAgo = regToDate.subtract(const Duration(days: 30));
      DateTime fyStart = WebAppDateLogic.getFYStart(webPh.financialYear);
      regFromDate = thirtyDaysAgo.isBefore(fyStart) ? fyStart : thirtyDaysAgo;
      _isInit = true;
    }
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  DateTime _getReturnDate(dynamic r) {
    if (r is SaleReturn) return r.date;
    if (r is PurchaseReturn) return r.date;
    return DateTime.now();
  }

  double _getReturnTotal(dynamic r) {
    if (r is SaleReturn) return r.totalAmount;
    if (r is PurchaseReturn) return r.totalAmount;
    return 0.0;
  }

  String _getReturnParty(dynamic r) {
    if (r is SaleReturn) return r.partyName;
    if (r is PurchaseReturn) return r.distributorName;
    return "";
  }

  String _getReturnBillNo(dynamic r) {
    if (r is SaleReturn) return r.billNo;
    if (r is PurchaseReturn) return r.billNo;
    return "";
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);
    final activeShop = CompanyProfile.fromMap(webPh.companyProfile);

    // Sub-view: Register
    if (activeSubView == "REGISTER") {
      return _buildRegisterContainer(webPh, activeShop);
    }

    // Sub-view: Placeholders for next phases
    if (activeSubView == "CN") {
      return _buildPlaceholderScreen("CREDIT NOTE (SALE RETURN)", "Customer Sales Return with Magic History Box", Colors.redAccent);
    }
    if (activeSubView == "DN") {
      return _buildPlaceholderScreen("DEBIT NOTE (PURCHASE RETURN)", "Distributor Inward Return & Rate Pull", const Color(0xFFD97706));
    }
    if (activeSubView == "BREAKAGE") {
      return _buildPlaceholderScreen("EXPIRY / BREAKAGE RETURN", "Non-Sellable Stock Damage Right-Off", Colors.orangeAccent);
    }

    // Main Hub: 4 Master Buttons
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white12,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text("BACK TO DASHBOARD", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.assignment_return_rounded, color: Color(0xFFEF4444), size: 24),
              const SizedBox(width: 10),
              const Text(
                "RETURNS & REVERSALS HUB",
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 25),
          const Text(
            "PRIMARY RETURN MODULES",
            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5),
          ),
          const SizedBox(height: 16),

          LayoutBuilder(
            builder: (context, constraints) {
              int crossAxisCount = constraints.maxWidth > 950 ? 4 : (constraints.maxWidth > 650 ? 2 : 1);

              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.25,
                children: [
                  _returnModuleCard(
                    title: "Credit Note",
                    subtitle: "Customer Sales Return",
                    badgeText: "${webPh.saleReturns.length} CN Records",
                    icon: Icons.assignment_return_rounded,
                    color: const Color(0xFFDC2626),
                    onTap: () => setState(() => activeSubView = "CN"),
                  ),
                  _returnModuleCard(
                    title: "Debit Note",
                    subtitle: "Return to Supplier / Distributor",
                    badgeText: "${webPh.purchaseReturns.length} DN Records",
                    icon: Icons.remove_shopping_cart_rounded,
                    color: const Color(0xFFD97706),
                    onTap: () => setState(() => activeSubView = "DN"),
                  ),
                  _returnModuleCard(
                    title: "Breakage / Expiry",
                    subtitle: "Non-Sellable Stock Right-Off",
                    badgeText: "Damage Out",
                    icon: Icons.delete_sweep_rounded,
                    color: const Color(0xFFEA580C),
                    onTap: () => setState(() => activeSubView = "BREAKAGE"),
                  ),
                  _returnModuleCard(
                    title: "Returns Register",
                    subtitle: "Full CN & DN Reversals Audit",
                    badgeText: "${webPh.saleReturns.length + webPh.purchaseReturns.length} Records",
                    icon: Icons.format_list_bulleted_rounded,
                    color: const Color(0xFF991B1B),
                    onTap: () => setState(() => activeSubView = "REGISTER"),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _returnModuleCard({
    required String title,
    required String subtitle,
    required String badgeText,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withAlpha(100), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(20),
              blurRadius: 14,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withAlpha(35),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: color.withAlpha(30),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withAlpha(100), width: 0.5),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(color: color, fontSize: 8.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: color, fontSize: 13.5, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderScreen(String title, String subtitle, Color color) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white12, foregroundColor: Colors.white),
                onPressed: () => setState(() => activeSubView = "HUB"),
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text("BACK TO RETURNS HUB", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              Icon(Icons.assignment_return_rounded, color: color, size: 22),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 40),
          Center(
            child: Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(16)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.construction_rounded, color: color, size: 40),
                  const SizedBox(height: 12),
                  Text("STEP 1: BUTTON READY", style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 14)),
                  const SizedBox(height: 6),
                  Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 12),
                  const Text("अगले स्टेप में हम इसका पूरा वर्कफ़्लो (Magic History Box + Items) बनाएंगे।", style: TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterContainer(PharoahWebManager webPh, CompanyProfile activeShop) {
    final fDateOnly = _dateOnly(regFromDate);
    final tDateOnly = _dateOnly(regToDate);

    List<dynamic> allReturns = [...webPh.saleReturns, ...webPh.purchaseReturns];
    allReturns.sort((a, b) => _getReturnDate(b).compareTo(_getReturnDate(a)));

    final filtered = allReturns.where((r) {
      final rDateOnly = _dateOnly(_getReturnDate(r));
      bool dateMatch = !rDateOnly.isBefore(fDateOnly) && !rDateOnly.isAfter(tDateOnly);
      String name = _getReturnParty(r);
      String billNo = _getReturnBillNo(r);
      bool searchMatch = registerSearch.isEmpty || 
          name.toLowerCase().contains(registerSearch.toLowerCase()) || 
          billNo.toLowerCase().contains(registerSearch.toLowerCase());
      return dateMatch && searchMatch;
    }).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white12, foregroundColor: Colors.white),
                onPressed: () => setState(() => activeSubView = "HUB"),
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text("BACK TO RETURNS HUB", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.format_list_bulleted_rounded, color: Color(0xFFF87171), size: 22),
              const SizedBox(width: 10),
              const Text("COMBINED RETURNS REGISTER (CN & DN)", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: "Search in Returns Register by party, note no...", 
              filled: true, 
              fillColor: Colors.black26, 
              border: InputBorder.none,
              prefixIcon: Icon(Icons.search, color: Color(0xFFF87171)),
            ),
            onChanged: (v) => setState(() => registerSearch = v),
          ),
          const SizedBox(height: 12),
          filtered.isEmpty
              ? const Padding(padding: EdgeInsets.all(30), child: Center(child: Text("No return records found.", style: TextStyle(color: Colors.white38))))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  itemBuilder: (c, i) {
                    final item = filtered[i];
                    bool isCn = item is SaleReturn;
                    String party = _getReturnParty(item);
                    String billNo = _getReturnBillNo(item);
                    double total = _getReturnTotal(item);

                    return Card(
                      color: const Color(0xFF1E293B),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        dense: true,
                        leading: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: isCn ? const Color(0x33DC2626) : const Color(0x33F59E0B),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(isCn ? "CN" : "DN", style: TextStyle(color: isCn ? const Color(0xFFF87171) : const Color(0xFFFBBF24), fontSize: 9.5, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(party, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5)),
                        subtitle: Text("No: $billNo • Date: ${DateFormat('dd/MM/yyyy').format(_getReturnDate(item))}", style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("₹${total.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.print, color: Colors.cyanAccent, size: 18),
                              onPressed: () {
                                final pObj = webPh.parties.firstWhere((p) => p.name == party, orElse: () => Party(id: 'temp', name: party));
                                if (item is SaleReturn) {
                                  WebPdfRouterService.printCreditNote(returnObj: item, party: pObj, shop: activeShop);
                                } else if (item is PurchaseReturn) {
                                  WebPdfRouterService.printDebitNote(returnObj: item, party: pObj, shop: activeShop);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}
