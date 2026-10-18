// FILE: lib/web_live_sync/sub_views/web_challans/web_sale_challan_view.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../web_models.dart';
import '../../pharoah_web_manager.dart';
import '../../web_app_date_logic.dart';
import '../web_billing/quick_add_party_modal.dart';
import 'web_sale_challan_billing_view.dart';

class WebSaleChallanView extends StatefulWidget {
  final VoidCallback onBack;
  final SaleChallan? existingRecord;
  final bool isReadOnly;

  const WebSaleChallanView({
    super.key,
    required this.onBack,
    this.existingRecord,
    this.isReadOnly = false,
  });

  @override
  State<WebSaleChallanView> createState() => _WebSaleChallanViewState();
}

class _WebSaleChallanViewState extends State<WebSaleChallanView> {
  final challanNoC = TextEditingController();
  final searchController = TextEditingController();
  final transportMemoC = TextEditingController();
  DateTime selectedDate = DateTime.now();
  Party? selectedParty;
  String searchQuery = "";
  String partyFilter = "ALL"; // ALL, RECENT, GST, UNREG
  String dispatchMode = "Local Delivery";
  bool isLoading = true;

  final List<String> dispatchModes = const [
    "Local Delivery",
    "By Hand / Self",
    "Transport / Courier",
    "Tempo / Van",
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
        challanNoC.text = ex.billNo;
        selectedDate = ex.date;
        transportMemoC.text = ex.remarks;
        try {
          selectedParty = webPh.parties.firstWhere(
            (p) =>
                p.id == ex.partyId ||
                p.name.trim().toLowerCase() == ex.partyName.trim().toLowerCase(),
          );
        } catch (_) {
          selectedParty = Party(
            id: ex.partyId.isNotEmpty ? ex.partyId : 'temp',
            name: ex.partyName,
            gst: ex.partyGstin,
            state: ex.partyState.isNotEmpty ? ex.partyState : 'Rajasthan',
          );
        }
        setState(() => isLoading = false);
      } else {
        String nextNo = webPh.getNextBillNumber("CHALLAN", "SCH-", 101);
        setState(() {
          challanNoC.text = nextNo;
          selectedDate = WebAppDateLogic.getSmartDate(webPh.financialYear);
          isLoading = false;
        });
      }
    });
  }

  void _openQuickAddCustomer(PharoahWebManager webPh) {
    showDialog(
      context: context,
      builder: (c) => QuickAddPartyModal(
        webPh: webPh,
        onPartyCreated: (newParty) {
          setState(() => selectedParty = newParty);
        },
      ),
    );
  }

  @override
  void dispose() {
    challanNoC.dispose();
    searchController.dispose();
    transportMemoC.dispose();
    super.dispose();
  }

  // --- STATS CALCULATIONS ---
  List<SaleChallan> _getPartyChallans(PharoahWebManager webPh, Party? party) {
    if (party == null) return [];
    return webPh.saleChallans.where((c) {
      return (c.partyId.isNotEmpty && c.partyId == party.id) ||
          c.partyName.trim().toLowerCase() == party.name.trim().toLowerCase();
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  List<Party> _getRecentChallanParties(PharoahWebManager webPh) {
    final recentPartyNames = <String>{};
    final recentList = <Party>[];
    final sortedChallans = List<SaleChallan>.from(webPh.saleChallans)
      ..sort((a, b) => b.date.compareTo(a.date));

    for (var ch in sortedChallans) {
      final nameLower = ch.partyName.trim().toLowerCase();
      if (nameLower.isEmpty || recentPartyNames.contains(nameLower)) continue;
      recentPartyNames.add(nameLower);
      try {
        final p = webPh.parties.firstWhere(
          (party) =>
              party.id == ch.partyId ||
              party.name.trim().toLowerCase() == nameLower,
        );
        recentList.add(p);
      } catch (_) {
        recentList.add(
          Party(
            id: ch.partyId.isNotEmpty ? ch.partyId : 'temp',
            name: ch.partyName,
            gst: ch.partyGstin,
            state: ch.partyState,
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
          child: CircularProgressIndicator(color: Color(0xFF2DD4BF)),
        ),
      );
    }

    final totalChallans = webPh.saleChallans.length;
    final pendingChallans =
        webPh.saleChallans.where((c) => c.status == "Pending").toList();
    final double totalPendingAmt =
        pendingChallans.fold(0.0, (s, c) => s + c.totalAmount);
    final double totalDispatchedAmt =
        webPh.saleChallans.fold(0.0, (s, c) => s + c.totalAmount);

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
                      // Header Navigation Bar
                      _buildTopNavBar(webPh),
                      const SizedBox(height: 16),

                      // Responsive Content Layout
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left Main Entry Column
                            Expanded(
                              flex: 7,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildChallanMetaCard(webPh),
                                  const SizedBox(height: 16),
                                  if (selectedParty != null)
                                    _buildSelectedPartyCard()
                                  else
                                    _buildPartySearchCard(webPh),
                                  if (selectedParty != null) ...[
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
                                    totalDispatchedAmt: totalDispatchedAmt,
                                  ),
                                  const SizedBox(height: 16),
                                  if (selectedParty != null)
                                    _buildPartyHistoryCard(webPh)
                                  else
                                    _buildStoreRecentChallansCard(webPh),
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
                          totalDispatchedAmt: totalDispatchedAmt,
                          isCompact: true,
                        ),
                        const SizedBox(height: 14),
                        _buildChallanMetaCard(webPh),
                        const SizedBox(height: 14),
                        if (selectedParty != null)
                          _buildSelectedPartyCard()
                        else
                          _buildPartySearchCard(webPh),
                        if (selectedParty != null) ...[
                          const SizedBox(height: 16),
                          _buildProceedButton(),
                          const SizedBox(height: 16),
                          _buildPartyHistoryCard(webPh),
                        ] else ...[
                          const SizedBox(height: 16),
                          _buildStoreRecentChallansCard(webPh),
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
              color: Color(0x332DD4BF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_shipping_rounded,
              color: Color(0xFF2DD4BF),
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
                      ? "VIEW SALE CHALLAN"
                      : (widget.existingRecord != null
                          ? "MODIFY SALE CHALLAN"
                          : "OUTWARD DELIVERY CHALLAN ENTRY"),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  "FY: ${webPh.financialYear}  •  Stock Movement without Immediate Invoice",
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0x262DD4BF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x552DD4BF)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.verified_rounded,
                  color: Color(0xFF2DD4BF),
                  size: 13,
                ),
                const SizedBox(width: 5),
                Text(
                  challanNoC.text.isNotEmpty ? challanNoC.text : "SCH-NEW",
                  style: const TextStyle(
                    color: Color(0xFF2DD4BF),
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
    required double totalDispatchedAmt,
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
                color: Color(0xFF2DD4BF),
                size: 16,
              ),
              const SizedBox(width: 8),
              const Text(
                "CHALLAN REGISTER INSIGHTS",
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
                  "$totalChallans Total Logged",
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
                  icon: Icons.local_shipping_outlined,
                  color: const Color(0xFF2DD4BF),
                  label: "DISPATCHED",
                  value: "$totalChallans Bills",
                  sub: "₹${totalDispatchedAmt.toStringAsFixed(0)}",
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.hourglass_top_rounded,
                  color: const Color(0xFFF59E0B),
                  label: "PENDING (UNBILLED)",
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

  // --- CHALLAN METADATA CARD (NUMBER, DATE, DISPATCH MODE, MEMO) ---
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
                Icons.assignment_rounded,
                color: Color(0xFF2DD4BF),
                size: 16,
              ),
              const SizedBox(width: 8),
              const Text(
                "DISPATCH DOCUMENT SETUP",
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
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    "EDIT MODE",
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Challan Number & Date Row
          Row(
            children: [
              Expanded(
                flex: 5,
                child: TextField(
                  controller: challanNoC,
                  readOnly: true,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2DD4BF),
                    fontSize: 13.5,
                  ),
                  decoration: InputDecoration(
                    labelText: "CHALLAN NUMBER",
                    labelStyle:
                        const TextStyle(color: Colors.white54, fontSize: 9.5),
                    prefixIcon: const Icon(
                      Icons.tag_rounded,
                      color: Color(0xFF2DD4BF),
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
                              color: Color(0xFF2DD4BF),
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  "DISPATCH DATE",
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
                                    fontSize: 12.5,
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
            ],
          ),
          const SizedBox(height: 12),

          // Dispatch / Transport Mode Chips
          Row(
            children: [
              const Text(
                "DISPATCH VIA:",
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: dispatchModes.map((mode) {
                    final bool isSel = dispatchMode == mode;
                    return InkWell(
                      onTap: widget.isReadOnly
                          ? null
                          : () => setState(() => dispatchMode = mode),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isSel
                              ? const Color(0xFF0F766E)
                              : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSel
                                ? const Color(0xFF2DD4BF)
                                : Colors.white12,
                          ),
                        ),
                        child: Text(
                          mode,
                          style: TextStyle(
                            color: isSel ? Colors.white : Colors.white70,
                            fontSize: 10,
                            fontWeight:
                                isSel ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Optional Transport / Remarks Memo
          TextField(
            controller: transportMemoC,
            readOnly: widget.isReadOnly,
            style: const TextStyle(color: Colors.white, fontSize: 11.5),
            decoration: InputDecoration(
              hintText:
                  "Optional Transport Memo / Vehicle No. / Transporter LR...",
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

  // --- CUSTOMER SEARCH & SELECTION CARD ---
  Widget _buildPartySearchCard(PharoahWebManager webPh) {
    final query = searchQuery.trim().toLowerCase();
    final recentParties = _getRecentChallanParties(webPh);

    List<Party> list = webPh.parties.where((p) {
      if (query.isNotEmpty) {
        final name = p.name.toLowerCase();
        final city = p.city.toLowerCase();
        final gst = p.gst.toLowerCase();
        final phone = p.phone.toLowerCase();
        if (!name.contains(query) &&
            !city.contains(query) &&
            !gst.contains(query) &&
            !phone.contains(query)) {
          return false;
        }
      }
      if (partyFilter == "GST") {
        return p.gst.trim().isNotEmpty && p.gst.trim() != "N/A";
      }
      if (partyFilter == "UNREG") {
        return p.gst.trim().isEmpty || p.gst.trim() == "N/A";
      }
      return true;
    }).toList();

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
                    Icons.people_alt_rounded,
                    color: Color(0xFF2DD4BF),
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Text(
                    "SELECT CUSTOMER / CONSIGNEE",
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
                  onPressed: () => _openQuickAddCustomer(webPh),
                  icon: const Icon(Icons.person_add_rounded, size: 15),
                  label: const Text(
                    "+ NEW CUSTOMER",
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
              hintText: "Search customer by name, city, phone or GSTIN...",
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 11.5),
              prefixIcon: const Icon(
                Icons.search,
                color: Color(0xFF2DD4BF),
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
              _buildFilterChip("ALL", "All (${webPh.parties.length})"),
              const SizedBox(width: 6),
              _buildFilterChip("RECENT", "Recent Dispatched"),
              const SizedBox(width: 6),
              _buildFilterChip("GST", "GST Registered"),
              const SizedBox(width: 6),
              _buildFilterChip("UNREG", "Unregistered"),
            ],
          ),

          // Quick Picks from Recent Challans (if any)
          if (recentParties.isNotEmpty &&
              searchQuery.isEmpty &&
              partyFilter == "ALL") ...[
            const SizedBox(height: 12),
            const Text(
              "⚡ FREQUENT CHALLAN CUSTOMERS (QUICK SELECT):",
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
                children: recentParties.map((p) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      backgroundColor: const Color(0xFF0F172A),
                      side: const BorderSide(color: Color(0x552DD4BF)),
                      avatar: CircleAvatar(
                        backgroundColor: const Color(0x332DD4BF),
                        child: Text(
                          p.name.isNotEmpty
                              ? p.name[0].toUpperCase()
                              : "C",
                          style: const TextStyle(
                            color: Color(0xFF2DD4BF),
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
                      onPressed: () => setState(() => selectedParty = p),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Matching Parties List
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
                            ? "No parties found in store database."
                            : "No customer found matching '$searchQuery'.",
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
                      final pastChallans = _getPartyChallans(webPh, p);
                      final bool hasChallans = pastChallans.isNotEmpty;

                      return Container(
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.white10),
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          hoverColor: const Color(0x1A2DD4BF),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: hasChallans
                                  ? const Color(0x332DD4BF)
                                  : Colors.white10,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.person_outline_rounded,
                              color: hasChallans
                                  ? const Color(0xFF2DD4BF)
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
                                    color: const Color(0x262DD4BF),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    "${pastChallans.length} Challan(s)",
                                    style: const TextStyle(
                                      color: Color(0xFF2DD4BF),
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
                          onTap: () => setState(() => selectedParty = p),
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
    final bool isSel = partyFilter == key;
    return InkWell(
      onTap: () => setState(() => partyFilter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isSel
              ? const Color(0xFF0F766E)
              : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSel ? const Color(0xFF2DD4BF) : Colors.transparent,
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

  // --- SELECTED PARTY MASTER CARD ---
  Widget _buildSelectedPartyCard() {
    final p = selectedParty!;
    final bool hasGst = p.gst.trim().isNotEmpty && p.gst.trim() != "N/A";

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2DD4BF), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332DD4BF),
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
                  color: Color(0x332DD4BF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Color(0xFF2DD4BF),
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
                    "CHANGE PARTY",
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    setState(() {
                      selectedParty = null;
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
                "Group: ${p.group.isNotEmpty ? p.group : 'Sundry Debtors'}",
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
          backgroundColor: const Color(0xFF0F766E),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 4,
          shadowColor: const Color(0x660F766E),
        ),
        onPressed: () async {
          final res = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (c) => WebSaleChallanBillingView(
                party: selectedParty!,
                challanNo: challanNoC.text.trim(),
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
        label: const Text(
          "PROCEED TO ITEM ENTRY ➔",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 14,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }

  // --- RIGHT PANEL: PARTY-SPECIFIC CHALLAN HISTORY ---
  Widget _buildPartyHistoryCard(PharoahWebManager webPh) {
    final partyChallans = _getPartyChallans(webPh, selectedParty);
    final unbilledCount =
        partyChallans.where((c) => c.status == "Pending").length;
    final double totalPartyAmt =
        partyChallans.fold(0.0, (s, c) => s + c.totalAmount);

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
                color: Color(0xFF2DD4BF),
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "DISPATCH HISTORY: ${selectedParty!.name.toUpperCase()}",
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
                  color: const Color(0x262DD4BF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "${partyChallans.length} Challans",
                  style: const TextStyle(
                    color: Color(0xFF2DD4BF),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Summary Stats for this Party
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
                      "TOTAL DISPATCH VALUE",
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "₹${totalPartyAmt.toStringAsFixed(2)}",
                      style: const TextStyle(
                        color: Color(0xFF2DD4BF),
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
                      color: Colors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber.withOpacity(0.5)),
                    ),
                    child: Text(
                      "⚠️ $unbilledCount Unbilled Challan(s)",
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Challan Records List
          if (partyChallans.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              alignment: Alignment.center,
              child: Column(
                children: const [
                  Icon(
                    Icons.inventory_2_outlined,
                    color: Colors.white24,
                    size: 36,
                  ),
                  SizedBox(height: 8),
                  Text(
                    "No Previous Challans Found",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "This is the first delivery challan for this customer.",
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
                itemCount: partyChallans.length,
                itemBuilder: (context, idx) {
                  final ch = partyChallans[idx];
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
                                  ch.billNo,
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
                                        : Colors.green.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isPending ? "PENDING" : "BILLED",
                                    style: TextStyle(
                                      color: isPending
                                          ? Colors.amberAccent
                                          : Colors.greenAccent,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "${DateFormat('dd/MM/yyyy').format(ch.date)}  •  ${ch.items.length} Items",
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

  // --- RIGHT PANEL: STORE-WIDE RECENT CHALLANS LOG ---
  Widget _buildStoreRecentChallansCard(PharoahWebManager webPh) {
    final recentChallans = List<SaleChallan>.from(webPh.saleChallans)
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
                color: Color(0xFF2DD4BF),
                size: 16,
              ),
              const SizedBox(width: 8),
              const Text(
                "RECENT STORE DISPATCHES",
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
                "No dispatch challans recorded yet.\nSelect customer to create your first challan.",
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
                              : const Color(0x332DD4BF),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.local_shipping_outlined,
                          color: isPending
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF2DD4BF),
                          size: 14,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ch.partyName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              "${ch.billNo}  •  ${DateFormat('dd/MM/yy').format(ch.date)}  •  ${ch.items.length} Items",
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
                                  : Colors.green.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isPending ? "Pending" : "Billed",
                              style: TextStyle(
                                color: isPending
                                    ? Colors.amberAccent
                                    : Colors.greenAccent,
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
          // Regulatory / Dispatch Guideline tip box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0x1A2DD4BF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x402DD4BF)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF2DD4BF),
                  size: 16,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Delivery Challans update batch inventory immediately. Multiple unbilled challans can be combined into a single GST Invoice later via Challan Stitcher.",
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
