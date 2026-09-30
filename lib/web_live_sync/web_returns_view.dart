// FILE: lib/web_live_sync/web_returns_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'web_models.dart';
import 'pharoah_web_manager.dart';
import 'web_app_date_logic.dart';
import 'web_pdf_router_service.dart';

class WebReturnsView extends StatefulWidget {
  final VoidCallback onBack;
  final int initialTabIndex;

  const WebReturnsView({super.key, required this.onBack, this.initialTabIndex = 0});

  @override
  State<WebReturnsView> createState() => _WebReturnsViewState();
}

class _WebReturnsViewState extends State<WebReturnsView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  DateTime regFromDate = DateTime.now();
  DateTime regToDate = DateTime.now();
  String registerSearch = "";
  bool _isInit = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTabIndex);
    final webPh = Provider.of<PharoahWebManager>(context, listen: false);
    regToDate = DateTime.now();
    regFromDate = WebAppDateLogic.getFYStart(webPh.financialYear);
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
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);
    final activeShop = CompanyProfile.fromMap(webPh.companyProfile);

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
      decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: widget.onBack, 
                icon: const Icon(Icons.arrow_back_rounded, size: 16), 
                label: const Text("BACK"), 
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white12, foregroundColor: Colors.white)
              ),
              const SizedBox(width: 15),
              const Text("RETURNS & REVERSALS HUB", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 15),
          Container(
            decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12)),
            child: TabBar(
              controller: _tabController, 
              indicatorColor: const Color(0xFFDC2626), 
              labelColor: const Color(0xFFF87171), 
              unselectedLabelColor: Colors.white54,
              tabs: const [Tab(text: "CREDIT NOTE (SALE RETURN)"), Tab(text: "DEBIT NOTE (PUR RETURN)"), Tab(text: "RETURNS REGISTER")],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabController, 
              children: [
                const Center(child: Text("Credit Note Entry Screen", style: TextStyle(color: Colors.white54))),
                const Center(child: Text("Debit Note Entry Screen", style: TextStyle(color: Colors.white54))),
                _buildRegister(filtered, webPh, activeShop),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegister(List<dynamic> filtered, PharoahWebManager webPh, CompanyProfile activeShop) {
    return Column(
      children: [
        TextField(
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Search in Returns Register...", 
            filled: true, 
            fillColor: Colors.black26, 
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search, color: Color(0xFFDC2626)),
          ),
          onChanged: (v) => setState(() => registerSearch = v),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (c, i) {
              final item = filtered[i];
              bool isCn = item is SaleReturn;
              String party = _getReturnParty(item);
              String billNo = _getReturnBillNo(item);
              double total = _getReturnTotal(item);

              return Card(
                color: const Color(0xFF1E293B),
                child: ListTile(
                  dense: true,
                  leading: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isCn ? const Color(0x33DC2626) : const Color(0x33F59E0B),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(isCn ? "CN" : "DN", style: TextStyle(color: isCn ? const Color(0xFFF87171) : const Color(0xFFFBBF24), fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(party, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5)),
                  subtitle: Text("No: $billNo", style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
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
        ),
      ],
    );
  }
}
