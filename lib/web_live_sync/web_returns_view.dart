// FILE: lib/web_live_sync/web_returns_view.dart
// ignore_for_file: prefer_const_constructors, unnecessary_const

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'web_models.dart';
import 'pharoah_web_manager.dart';
import 'web_app_date_logic.dart';
import 'web_pdf_router_service.dart';
import 'sub_views/web_returns/credit_note/ui/web_credit_note_screen.dart';
import 'sub_views/web_returns/debit_note/ui/web_debit_note_screen.dart';

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
  late String activeSubView; // "HUB", "CN", "DN", "REGISTER"
  dynamic recordToEdit;
  bool isReadOnlyMode = false;

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
      activeSubView = "CN"; // Handled seamlessly inside Credit Note with Breakage mode
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

    // 1. FULL MODULAR CREDIT NOTE (SALE RETURN) SCREEN
    if (activeSubView == "CN") {
      return WebCreditNoteScreen(
        existingRecord: recordToEdit is SaleReturn ? recordToEdit : null,
        isReadOnly: isReadOnlyMode,
        onBack: () => setState(() {
          activeSubView = "HUB";
          recordToEdit = null;
          isReadOnlyMode = false;
        }),
      );
    }

    // 2. FULL MODULAR DEBIT NOTE (PURCHASE RETURN) SCREEN
    if (activeSubView == "DN") {
      return WebDebitNoteScreen(
        existingRecord: recordToEdit is PurchaseReturn ? recordToEdit : null,
        isReadOnly: isReadOnlyMode,
        onBack: () => setState(() {
          activeSubView = "HUB";
          recordToEdit = null;
          isReadOnlyMode = false;
        }),
      );
    }

    // 3. COMBINED RETURNS REGISTER (CN & DN)
    if (activeSubView == "REGISTER") {
      return _buildRegisterContainer(webPh, activeShop);
    }

    // 4. MAIN RETURNS HUB (4 MODULE CARDS)
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
                    onTap: () => setState(() {
                      recordToEdit = null;
                      isReadOnlyMode = false;
                      activeSubView = "CN";
                    }),
                  ),
                  _returnModuleCard(
                    title: "Debit Note",
                    subtitle: "Return to Supplier / Distributor",
                    badgeText: "${webPh.purchaseReturns.length} DN Records",
                    icon: Icons.remove_shopping_cart_rounded,
                    color: const Color(0xFFD97706),
                    onTap: () => setState(() {
                      recordToEdit = null;
                      isReadOnlyMode = false;
                      activeSubView = "DN";
                    }),
                  ),
                  _returnModuleCard(
                    title: "Breakage / Expiry",
                    subtitle: "Non-Sellable Damage Out",
                    badgeText: "Damage Reversal",
                    icon: Icons.delete_sweep_rounded,
                    color: const Color(0xFFEA580C),
                    onTap: () => setState(() {
                      recordToEdit = null;
                      isReadOnlyMode = false;
                      activeSubView = "CN";
                    }),
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white12,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: () => setState(() => activeSubView = "HUB"),
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text("BACK TO RETURNS HUB", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.format_list_bulleted_rounded, color: Color(0xFFF87171), size: 22),
              const SizedBox(width: 10),
              const Text(
                "COMBINED RETURNS REGISTER (CN & DN)",
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  style: const TextStyle(color: Colors.white, fontSize: 12.5),
                  decoration: const InputDecoration(
                    hintText: "Search in Returns Register by party, note number...", 
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 11.5),
                    filled: true, 
                    fillColor: Color(0xFF1E293B), 
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide.none),
                    prefixIcon: Icon(Icons.search, color: Color(0xFFF87171), size: 18),
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (v) => setState(() => registerSearch = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          filtered.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(35),
                  child: Center(
                    child: Text("No return records found for current filters.", style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ),
                )
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

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isCn ? const Color(0x33DC2626) : const Color(0x33D97706),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isCn ? "SALE CN" : "PUR DN",
                            style: TextStyle(
                              color: isCn ? const Color(0xFFF87171) : const Color(0xFFFBBF24),
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(party, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text(
                          "No: $billNo • Date: ${DateFormat('dd/MM/yyyy').format(_getReturnDate(item))} • Type: ${item.returnType}",
                          style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "₹${total.toStringAsFixed(2)}",
                              style: TextStyle(
                                color: isCn ? const Color(0xFFF87171) : const Color(0xFFFBBF24),
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              icon: const Icon(Icons.print_outlined, color: Color(0xFF38BDF8), size: 18),
                              tooltip: isCn ? "Print Credit Note" : "Print Debit Note",
                              onPressed: () {
                                final pObj = webPh.parties.firstWhere((p) => p.name == party, orElse: () => Party(id: 'temp', name: party));
                                if (isCn) {
                                  WebPdfRouterService.printCreditNote(returnObj: item, party: pObj, shop: activeShop);
                                } else {
                                  WebPdfRouterService.printDebitNote(returnObj: item, party: pObj, shop: activeShop);
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.download_rounded, color: Colors.greenAccent, size: 18),
                              tooltip: "Download PDF",
                              onPressed: () {
                                final pObj = webPh.parties.firstWhere((p) => p.name == party, orElse: () => Party(id: 'temp', name: party));
                                if (isCn) {
                                  WebPdfRouterService.downloadCreditNotePdf(returnObj: item, party: pObj, shop: activeShop);
                                } else {
                                  WebPdfRouterService.downloadDebitNotePdf(returnObj: item, party: pObj, shop: activeShop);
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_note_rounded, color: Colors.orangeAccent, size: 20),
                              tooltip: "Modify Return",
                              onPressed: () {
                                setState(() {
                                  recordToEdit = item;
                                  isReadOnlyMode = false;
                                  activeSubView = isCn ? "CN" : "DN";
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                              tooltip: "Delete Return Record",
                              onPressed: () {
                                if (isCn) {
                                  webPh.deleteSaleReturn(item.id);
                                } else {
                                  webPh.deletePurchaseReturn(item.id);
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("🗑️ Return Record Removed & Stock Adjusted!"), backgroundColor: Colors.redAccent),
                                );
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
