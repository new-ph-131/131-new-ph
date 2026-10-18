// FILE: lib/web_live_sync/sub_views/web_challans/web_purchase_challan_view.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../web_models.dart';
import '../../pharoah_web_manager.dart';
import '../../web_app_date_logic.dart';
import '../web_billing/quick_add_party_modal.dart';
import 'web_purchase_challan_billing_view.dart';

class WebPurchaseChallanView extends StatefulWidget {
  final VoidCallback onBack;
  final PurchaseChallan? existingRecord;
  final bool isReadOnly;

  const WebPurchaseChallanView({
    super.key,
    required this.onBack,
    this.existingRecord,
    this.isReadOnly = false,
  });

  @override
  State<WebPurchaseChallanView> createState() => _WebPurchaseChallanViewState();
}

class _WebPurchaseChallanViewState extends State<WebPurchaseChallanView> {
  final internalNoC = TextEditingController();
  final supplierRefC = TextEditingController();
  final searchController = TextEditingController();
  final transportMemoC = TextEditingController();
  DateTime selectedDate = DateTime.now();
  Party? selectedSupplier;
  String searchQuery = "";
  String supplierFilter = "CREDITORS"; // CREDITORS, ALL, RECENT, GST
  String inwardReceiptMode = "Direct Delivery";
  bool isLoading = true;

  final List<String> inwardModes = const [
    "Direct Delivery",
    "Transporter L.R.",
    "Courier",
    "Distributor Boy",
  ];

  @override
  void initState() {
    super.initState();
    _initChallanFlow();
  }

  void _initChallanFlow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final webPh = Provider.of<PharoahWebManager>(context, listen: false);
      if (widget.existingRecord != null) {
        final ex = widget.existingRecord!;
        internalNoC.text = ex.internalNo;
        supplierRefC.text = ex.billNo;
        selectedDate = ex.date;
        transportMemoC.text = ex.remarks;
        try {
          selectedSupplier = webPh.parties.firstWhere(
            (p) =>
                p.name.trim().toLowerCase() ==
                    ex.distributorName.trim().toLowerCase() ||
                (ex.partyId.isNotEmpty && p.id == ex.partyId),
          );
        } catch (_) {
          selectedSupplier = Party(
            id: ex.partyId.isNotEmpty ? ex.partyId : 'temp',
            name: ex.distributorName,
            group: "Sundry Creditors",
          );
        }
        setState(() => isLoading = false);
      } else {
        String nextNo = webPh.getNextBillNumber("PURCHASE_CHALLAN", "WPCH-", 1);
        setState(() {
          internalNoC.text = nextNo;
          selectedDate = WebAppDateLogic.getSmartDate(webPh.financialYear);
          isLoading = false;
        });
      }
    });
  }

  void _openQuickAddSupplier(PharoahWebManager webPh) {
    showDialog(
      context: context,
      builder: (c) => QuickAddPartyModal(
        webPh: webPh,
        preFillData: const {'group': 'Sundry Creditors'},
        onPartyCreated: (newParty) {
          setState(() => selectedSupplier = newParty);
        },
      ),
    );
  }

  @override
  void dispose() {
    internalNoC.dispose();
    supplierRefC.dispose();
    searchController.dispose();
    transportMemoC.dispose();
    super.dispose();
  }

  bool _isCreditorGroup(String group) {
    final g = group.trim().toLowerCase();
    return g.contains("creditor") ||
        g.contains("supplier") ||
        g.contains("vendor") ||
        g.contains("distributor");
  }

  bool _isSystemNonParty(Party p) {
    final nameUpper = p.name.trim().toUpperCase();
    final grpLower = p.group.trim().toLowerCase();
    if (nameUpper == "CASH") return true;
    if (grpLower == "bank accounts" ||
        grpLower == "cash in hand" ||
        grpLower == "expenses") return true;
    return false;
  }

  List<PurchaseChallan> _getSupplierChallans(
    PharoahWebManager webPh,
    Party? supplier,
  ) {
    if (supplier == null) return [];
    return webPh.purchaseChallans.where((c) {
      return (c.partyId.isNotEmpty && c.partyId == supplier.id) ||
          c.distributorName.trim().toLowerCase() ==
              supplier.name.trim().toLowerCase();
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  List<Party> _getRecentInwardSuppliers(PharoahWebManager webPh) {
    final recentSupplierNames = <String>{};
    final recentList = <Party>[];
    final sortedChallans = List<PurchaseChallan>.from(webPh.purchaseChallans)
      ..sort((a, b) => b.date.compareTo(a.date));

    for (var ch in sortedChallans) {
      final nameLower = ch.distributorName.trim().toLowerCase();
      if (nameLower.isEmpty || recentSupplierNames.contains(nameLower)) continue;
      recentSupplierNames.add(nameLower);
      try {
        final p = webPh.parties.firstWhere(
          (party) =>
              (ch.partyId.isNotEmpty && party.id == ch.partyId) ||
              party.name.trim().toLowerCase() == nameLower,
        );
        recentList.add(p);
      } catch (_) {
        recentList.add(
          Party(
            id: ch.partyId.isNotEmpty ? ch.partyId : 'temp',
            name: ch.distributorName,
            group: "Sundry Creditors",
          ),
        );
      }
      if (recentList.length >= 6) break;
    }
    return recentList;
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    if (isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFF59E0B)),
        ),
      );
    }

    final totalChallans = webPh.purchaseChallans.length;
    final pendingChallans =
        webPh.purchaseChallans.where((c) => c.status == "Pending").toList();
    final double totalPendingAmt =
        pendingChallans.fold(0.0, (s, c) => s + c.totalAmount);
    final double totalInwardAmt =
        webPh.purchaseChallans.fold(0.0, (s, c) => s + c.totalAmount);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isWide = constraints.maxWidth >= 980;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isWide ? 24 : 14,
                vertical: 18,
              ),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1360),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Navigation Bar
                      _buildTopNavBar(webPh),
                      const SizedBox(height: 16),

                      // Responsive Layout
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left Main Column
                            Expanded(
                              flex: 7,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildChallanMetaCard(webPh),
                                  const SizedBox(height: 16),
                                  if (selectedSupplier != null)
                                    _buildSelectedSupplierCard()
                                  else
                                    _buildSupplierSearchCard(webPh),
                                  if (selectedSupplier != null) ...[
                                    const SizedBox(height: 18),
                                    _buildProceedButton(),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 20),
                            // Right Intelligence & History Column
                            Expanded(
                              flex: 5,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildKpiMetricsCard(
                                    totalChallans: totalChallans,
                                    pendingCount: pendingChallans.length,
                                    pendingAmt: totalPendingAmt,
                                    totalInwardAmt: totalInwardAmt,
                                  ),
                                  const SizedBox(height: 16),
                                  if (selectedSupplier != null)
                                    _buildSupplierHistoryCard(webPh)
                                  else
                                    _buildStoreRecentInwardCard(webPh),
                                ],
                              ),
                            ),
                          ],
                        )
                      else ...[
                        // Mobile / Portrait Single-Column
                        _buildKpiMetricsCard(
                          totalChallans: totalChallans,
                          pendingCount: pendingChallans.length,
                          pendingAmt: totalPendingAmt,
                          totalInwardAmt: totalInwardAmt,
                          isCompact: true,
                        ),
                        const SizedBox(height: 14),
                        _buildChallanMetaCard(webPh),
                        const SizedBox(height: 14),
                        if (selectedSupplier != null)
                          _buildSelectedSupplierCard()
                        else
                          _buildSupplierSearchCard(webPh),
                        if (selectedSupplier != null) ...[
                          const SizedBox(height: 16),
                          _buildProceedButton(),
                          const SizedBox(height: 16),
                          _buildSupplierHistoryCard(webPh),
                        ] else ...[
                          const SizedBox(height: 16),
                          _buildStoreRecentInwardCard(webPh),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // --- HEADER NAVIGATION BAR ---
  Widget _buildTopNavBar(PharoahWebManager webPh) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white12,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text(
              "BACK TO CHALLANS",
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0x33F59E0B),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inventory_2_rounded,
              color: Color(0xFFF59E0B),
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.isReadOnly
                      ? "VIEW INWARD PURCHASE CHALLAN"
                      : (widget.existingRecord != null
                          ? "MODIFY INWARD CHALLAN"
                          : "NEW INWARD PURCHASE CHALLAN ENTRY"),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  "FY: ${webPh.financialYear}  •  Goods Receipt & Inward Stock Ingestion",
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0x26F59E0B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x55F59E0B)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.receipt_long_rounded,
                  color: Color(0xFFF59E0B),
                  size: 13,
                ),
                const SizedBox(width: 5),
                Text(
                  internalNoC.text.isNotEmpty ? internalNoC.text : "WPCH-NEW",
                  style: const TextStyle(
                    color: Color(0xFFF59E0B),
                    fontWeight: FontWeight.w900,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- KPI METRICS STRIP ---
  Widget _buildKpiMetricsCard({
    required int totalChallans,
    required int pendingCount,
    required double pendingAmt,
    required double totalInwardAmt,
    bool isCompact = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.analytics_rounded,
                color: Color(0xFFF59E0B),
                size: 16,
              ),
              const SizedBox(width: 8),
              const Text(
                "INWARD CHALLAN REGISTER INSIGHTS",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "$totalChallans Inward Logged",
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.inventory_2_outlined,
                  color: const Color(0xFFF59E0B),
                  label: "GOODS RECEIVED",
                  value: "$totalChallans Dockets",
                  sub: "₹${totalInwardAmt.toStringAsFixed(0)}",
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.pending_actions_rounded,
                  color: const Color(0xFF14B8A6),
                  label: "PENDING VERIFICATION",
                  value: "$pendingCount Open",
                  sub: "₹${pendingAmt.toStringAsFixed(0)}",
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required String sub,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
                Text(
                  sub,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- CHALLAN METADATA CARD (INTERNAL NO, SUPPLIER REF NO, DATE, MODE, MEMO) ---
  Widget _buildChallanMetaCard(PharoahWebManager webPh) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.assignment_turned_in_rounded,
                color: Color(0xFFF59E0B),
                size: 16,
              ),
              const SizedBox(width: 8),
              const Text(
                "INWARD DOCKET & RECEIPT SETUP",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              if (widget.existingRecord != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    "MODIFY RECORD",
                    style: TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Internal Entry No & Supplier Ref No
          Row(
            children: [
              Expanded(
                flex: 5,
                child: TextField(
                  controller: internalNoC,
                  readOnly: true,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFF59E0B),
                    fontSize: 13.5,
                  ),
                  decoration: InputDecoration(
                    labelText: "INTERNAL ENTRY NO",
                    labelStyle:
                        const TextStyle(color: Colors.white54, fontSize: 9.5),
                    prefixIcon: const Icon(
                      Icons.numbers_rounded,
                      color: Color(0xFFF59E0B),
                      size: 17,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 6,
                child: TextField(
                  controller: supplierRefC,
                  readOnly: widget.isReadOnly,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 13.5,
                  ),
                  decoration: InputDecoration(
                    labelText: "SUPPLIER CHALLAN / REF NO *",
                    labelStyle: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                    ),
                    hintText: "e.g. CH-8902 / INV-991",
                    hintStyle:
                        const TextStyle(color: Colors.white24, fontSize: 11),
                    prefixIcon: const Icon(
                      Icons.receipt_rounded,
                      color: Color(0xFFF59E0B),
                      size: 17,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  onChanged: (v) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Date & Receipt Mode Row
          Row(
            children: [
              Expanded(
                flex: 5,
                child: InkWell(
                  onTap: widget.isReadOnly
                      ? null
                      : () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: WebAppDateLogic.getFYStart(
                              webPh.financialYear,
                            ),
                            lastDate:
                                WebAppDateLogic.getFYEnd(webPh.financialYear),
                          );
                          if (picked != null) {
                            setState(() => selectedDate = picked);
                          }
                        },
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_month_rounded,
                              color: Color(0xFFF59E0B),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  "INWARD DATE",
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  DateFormat(
                                    'dd/MM/yyyy (EEE)',
                                  ).format(selectedDate),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const Icon(
                          Icons.edit_calendar_rounded,
                          color: Colors.white38,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 6,
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.local_shipping_outlined,
                        color: Color(0xFFF59E0B),
                        size: 17,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "MODE:",
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: inwardReceiptMode,
                            dropdownColor: const Color(0xFF1E293B),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                            isExpanded: true,
                            items: inwardModes.map((m) {
                              return DropdownMenuItem(
                                value: m,
                                child: Text(m),
                              );
                            }).toList(),
                            onChanged: widget.isReadOnly
                                ? null
                                : (v) {
                                    if (v != null) {
                                      setState(() => inwardReceiptMode = v);
                                    }
                                  },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Transport Memo / Docket No
          TextField(
            controller: transportMemoC,
            readOnly: widget.isReadOnly,
            style: const TextStyle(color: Colors.white, fontSize: 11.5),
            decoration: InputDecoration(
              hintText:
                  "Optional Inward Docket / L.R. No. / Carrier Details...",
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 10.5),
              prefixIcon: const Icon(
                Icons.notes_rounded,
                color: Colors.white38,
                size: 16,
              ),
              filled: true,
              fillColor: const Color(0xFF0F172A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- SUPPLIER SEARCH & SELECTION CARD ---
  Widget _buildSupplierSearchCard(PharoahWebManager webPh) {
    final query = searchQuery.trim().toLowerCase();
    final recentSuppliers = _getRecentInwardSuppliers(webPh);

    List<Party> list = webPh.parties.where((p) {
      if (_isSystemNonParty(p)) return false;
      if (query.isNotEmpty) {
        final name = p.name.toLowerCase();
        final city = p.city.toLowerCase();
        final gst = p.gst.toLowerCase();
        final phone = p.phone.toLowerCase();
        final grp = p.group.toLowerCase();
        if (!name.contains(query) &&
            !city.contains(query) &&
            !gst.contains(query) &&
            !phone.contains(query) &&
            !grp.contains(query)) {
          return false;
        }
      }
      if (supplierFilter == "CREDITORS") {
        return _isCreditorGroup(p.group);
      }
      if (supplierFilter == "GST") {
        return p.gst.trim().isNotEmpty && p.gst.trim() != "N/A";
      }
      return true;
    }).toList();

    // Sort: Creditors / Suppliers always appear first, then alphabetically
    list.sort((a, b) {
      final aCred = _isCreditorGroup(a.group);
      final bCred = _isCreditorGroup(b.group);
      if (aCred != bCred) return aCred ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.business_rounded,
                    color: Color(0xFFF59E0B),
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Text(
                    "SELECT DISTRIBUTOR / SUPPLIER",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              if (!widget.isReadOnly)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => _openQuickAddSupplier(webPh),
                  icon: const Icon(Icons.person_add_rounded, size: 15),
                  label: const Text(
                    "+ NEW SUPPLIER",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Search Field
          TextField(
            controller: searchController,
            style: const TextStyle(color: Colors.white, fontSize: 12.5),
            decoration: InputDecoration(
              hintText: "Search distributor by name, city, phone or GSTIN...",
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 11.5),
              prefixIcon: const Icon(
                Icons.search,
                color: Color(0xFFF59E0B),
                size: 18,
              ),
              suffixIcon: searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.clear_rounded,
                        color: Colors.white54,
                        size: 16,
                      ),
                      onPressed: () {
                        searchController.clear();
                        setState(() => searchQuery = "");
                      },
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFF0F172A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
            onChanged: (v) => setState(() => searchQuery = v),
          ),
          const SizedBox(height: 10),

          // Filter Chips Row
          Row(
            children: [
              _buildFilterChip("CREDITORS", "Creditors / Vendors"),
              const SizedBox(width: 6),
              _buildFilterChip("ALL", "All Parties (${webPh.parties.length})"),
              const SizedBox(width: 6),
              _buildFilterChip("GST", "GST Registered"),
            ],
          ),

          // Quick Picks from Recent Inward Suppliers (if any)
          if (recentSuppliers.isNotEmpty &&
              searchQuery.isEmpty &&
              supplierFilter == "CREDITORS") ...[
            const SizedBox(height: 12),
            const Text(
              "⚡ FREQUENT INWARD SUPPLIERS (QUICK SELECT):",
              style: TextStyle(
                color: Colors.white38,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: recentSuppliers.map((p) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      backgroundColor: const Color(0xFF0F172A),
                      side: const BorderSide(color: Color(0x55F59E0B)),
                      avatar: CircleAvatar(
                        backgroundColor: const Color(0x33F59E0B),
                        child: Text(
                          p.name.isNotEmpty
                              ? p.name[0].toUpperCase()
                              : "S",
                          style: const TextStyle(
                            color: Color(0xFFF59E0B),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      label: Text(
                        p.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () => setState(() => selectedSupplier = p),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Matching Suppliers List
          Container(
            constraints: const BoxConstraints(minHeight: 140, maxHeight: 330),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: list.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        searchQuery.isEmpty
                            ? "No suppliers found in store database."
                            : "No supplier found matching '$searchQuery'.",
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: list.length,
                    itemBuilder: (context, idx) {
                      final p = list[idx];
                      final pastChallans = _getSupplierChallans(webPh, p);
                      final bool hasChallans = pastChallans.isNotEmpty;

                      return Container(
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.white10),
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          hoverColor: const Color(0x1AF59E0B),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: hasChallans
                                  ? const Color(0x33F59E0B)
                                  : Colors.white10,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.business_outlined,
                              color: hasChallans
                                  ? const Color(0xFFF59E0B)
                                  : Colors.white54,
                              size: 16,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (hasChallans)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0x26F59E0B),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    "${pastChallans.length} Inward",
                                    style: const TextStyle(
                                      color: Color(0xFFF59E0B),
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            "${p.city.isEmpty ? 'No City' : p.city} | GST: ${p.gst.isEmpty ? 'N/A' : p.gst}${p.phone.isNotEmpty ? ' | Ph: ${p.phone}' : ''}",
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 10.5,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.white24,
                            size: 13,
                          ),
                          onTap: () => setState(() => selectedSupplier = p),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final bool isSel = supplierFilter == key;
    return InkWell(
      onTap: () => setState(() => supplierFilter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isSel
              ? const Color(0xFFB45309)
              : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSel ? const Color(0xFFF59E0B) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSel ? Colors.white : Colors.white60,
            fontSize: 10,
            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // --- SELECTED SUPPLIER MASTER CARD ---
  Widget _buildSelectedSupplierCard() {
    final p = selectedSupplier!;
    final bool hasGst = p.gst.trim().isNotEmpty && p.gst.trim() != "N/A";

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33F59E0B),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Color(0x33F59E0B),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.business_rounded,
                  color: Color(0xFFF59E0B),
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            p.name.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: hasGst
                                ? Colors.green.withOpacity(0.2)
                                : Colors.grey.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            hasGst ? "GST REGISTERED" : "UNREGISTERED",
                            style: TextStyle(
                              color: hasGst
                                  ? Colors.greenAccent
                                  : Colors.white60,
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${p.city.isEmpty ? 'City: N/A' : p.city} • State: ${p.state.isEmpty ? 'Rajasthan' : p.state}${p.phone.isNotEmpty ? ' • Phone: ${p.phone}' : ''}",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (!widget.isReadOnly)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    backgroundColor: Colors.red.withOpacity(0.12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.change_circle_rounded, size: 16),
                  label: const Text(
                    "CHANGE SUPPLIER",
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    setState(() {
                      selectedSupplier = null;
                      searchQuery = "";
                      searchController.clear();
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "GSTIN: ${hasGst ? p.gst : 'Not Available'}",
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "Group: ${p.group.isNotEmpty ? p.group : 'Sundry Creditors'}",
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- PROCEED BUTTON ---
  Widget _buildProceedButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFD97706),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 4,
          shadowColor: const Color(0x66D97706),
        ),
        onPressed: () async {
          if (supplierRefC.text.trim().isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "Supplier Challan / Ref No is required for inward tracking!",
                ),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }
          final res = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (c) => WebPurchaseChallanBillingView(
                supplier: selectedSupplier!,
                internalNo: internalNoC.text.trim(),
                supplierRefNo: supplierRefC.text.trim(),
                challanDate: selectedDate,
                existingRecord: widget.existingRecord,
                isReadOnly: widget.isReadOnly,
              ),
            ),
          );
          if (res == true && mounted) {
            widget.onBack();
          }
        },
        icon: const Icon(Icons.arrow_forward_rounded, size: 20),
        label: Text(
          widget.isReadOnly
              ? "VIEW INWARD ITEMS ➔"
              : "PROCEED TO INWARD ENTRY ➔",
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 14,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }

  // --- RIGHT PANEL: SUPPLIER-SPECIFIC INWARD HISTORY ---
  Widget _buildSupplierHistoryCard(PharoahWebManager webPh) {
    final supplierChallans = _getSupplierChallans(webPh, selectedSupplier);
    final unbilledCount =
        supplierChallans.where((c) => c.status == "Pending").length;
    final double totalSupplierAmt =
        supplierChallans.fold(0.0, (s, c) => s + c.totalAmount);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.history_rounded,
                color: Color(0xFFF59E0B),
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "INWARD RECEIPTS: ${selectedSupplier!.name.toUpperCase()}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0x26F59E0B),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "${supplierChallans.length} Inward",
                  style: const TextStyle(
                    color: Color(0xFFF59E0B),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Summary Stats for this Supplier
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "TOTAL INWARD VALUE",
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "₹${totalSupplierAmt.toStringAsFixed(2)}",
                      style: const TextStyle(
                        color: Color(0xFFF59E0B),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                if (unbilledCount > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.teal.withOpacity(0.5)),
                    ),
                    child: Text(
                      "$unbilledCount Pending Verification",
                      style: const TextStyle(
                        color: Colors.tealAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Inward Challan Records List
          if (supplierChallans.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              alignment: Alignment.center,
              child: Column(
                children: const [
                  Icon(
                    Icons.inventory_rounded,
                    color: Colors.white24,
                    size: 36,
                  ),
                  SizedBox(height: 8),
                  Text(
                    "No Previous Inward Challans",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "This is the first inward receipt logged from this distributor.",
                    style: TextStyle(color: Colors.white38, fontSize: 10.5),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: supplierChallans.length,
                itemBuilder: (context, idx) {
                  final ch = supplierChallans[idx];
                  final bool isPending = ch.status == "Pending";
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isPending
                            ? Colors.amber.withOpacity(0.3)
                            : Colors.white10,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  ch.internalNo,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isPending
                                        ? Colors.amber.withOpacity(0.15)
                                        : Colors.teal.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isPending ? "PENDING" : "VERIFIED",
                                    style: TextStyle(
                                      color: isPending
                                          ? Colors.amberAccent
                                          : Colors.tealAccent,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Ref: ${ch.billNo}  •  ${DateFormat('dd/MM/yyyy').format(ch.date)}  •  ${ch.items.length} Items",
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 9.5,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          "₹${ch.totalAmount.toStringAsFixed(2)}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // --- RIGHT PANEL: STORE-WIDE RECENT INWARD CHALLANS LOG ---
  Widget _buildStoreRecentInwardCard(PharoahWebManager webPh) {
    final recentChallans = List<PurchaseChallan>.from(webPh.purchaseChallans)
      ..sort((a, b) => b.date.compareTo(a.date));
    final displayList = recentChallans.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.recent_actors_rounded,
                color: Color(0xFFF59E0B),
                size: 16,
              ),
              const SizedBox(width: 8),
              const Text(
                "RECENT INWARD RECEIPTS",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              const Text(
                "Latest 5",
                style: TextStyle(color: Colors.white38, fontSize: 9.5),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (displayList.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              child: const Text(
                "No inward purchase challans recorded yet.\nSelect supplier to create your first inward challan.",
                style: TextStyle(color: Colors.white38, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayList.length,
              itemBuilder: (context, idx) {
                final ch = displayList[idx];
                final bool isPending = ch.status == "Pending";

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isPending
                              ? const Color(0x33F59E0B)
                              : const Color(0x3314B8A6),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.inventory_2_outlined,
                          color: isPending
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF14B8A6),
                          size: 14,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ch.distributorName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              "${ch.internalNo} (Ref: ${ch.billNo})  •  ${DateFormat('dd/MM/yy').format(ch.date)}  •  ${ch.items.length} Items",
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 9.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            "₹${ch.totalAmount.toStringAsFixed(0)}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: isPending
                                  ? Colors.amber.withOpacity(0.15)
                                  : Colors.teal.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isPending ? "Pending" : "Verified",
                              style: TextStyle(
                                color: isPending
                                    ? Colors.amberAccent
                                    : Colors.tealAccent,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),

          const SizedBox(height: 12),
          // Regulatory / Inward Guideline tip box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0x1AF59E0B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x40F59E0B)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFFF59E0B),
                  size: 16,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Ensure distributor delivery challan number matches physical invoice docket. Recorded stock is immediately verified into store batches.",
                    style: TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
