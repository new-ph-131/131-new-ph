// FILE: lib/main_control_shell.dart

import 'challans/purchase_challan_register.dart';
import 'challans/sale_challan_register.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pharoah_manager.dart';
import 'models.dart';
import 'widgets.dart';
import 'inventory_logic_center.dart';
import 'returns/universal_return_hub.dart';
// --- VIEWS IMPORTS ---
import 'data_exchange_view.dart';
import 'returns/purchase_return_register.dart';
import 'returns/sale_return_register.dart';
import 'challans/challan_stitcher_wizard.dart';
import 'sale_entry_view.dart';
import 'purchase/purchase_entry_view.dart';
import 'challans/sale_challan_view.dart';
import 'challans/purchase_challan_view.dart';
import 'challans/challan_to_bill_converter.dart';
import 'returns/sale_return_view.dart';
import 'returns/purchase_return_view.dart';
import 'returns/expiry_breakage_return_view.dart';
import 'item_ledger_view.dart';
import 'inventory_intel/shortage_register.dart';
import 'inventory_intel/stock_health_reports.dart';
import 'daybook_view.dart';
import 'ledger_reports_view.dart';
import 'accounting_views.dart';
import 'party_master.dart';
import 'product_master.dart';
import 'batch_master_view.dart';
import 'route_master_view.dart';
import 'administration/system_user_master_view.dart';
import 'company_master_view.dart';
import 'salt_master_view.dart';
import 'gst_report_detail_view.dart';
import 'gst_reconciliation_view.dart';
import 'pharoah_ai_vision.dart';
import 'modifications/modify_hub_view.dart'; 
import 'compliance/compliance_hub.dart';   
import 'administration/series_master_view.dart'; 
import 'administration/app_settings_view.dart'; 
import 'administration/ca_profile_view.dart'; // <--- NAYA IMPORT ADDED
import 'sale_summary_view.dart'; 
import 'purchase/purchase_summary_view.dart'; 
import 'payment_receipt_history.dart';
import 'finance/statement_hub.dart';

class MainControlShell extends StatefulWidget {
  const MainControlShell({super.key});
  @override State<MainControlShell> createState() => _MainControlShellState();
}

class _MainControlShellState extends State<MainControlShell> {
  
  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    List<ModuleAction> displayActions;
    String displayTitle;

    switch (ph.activeModule) {
      case "BILLING": displayActions = ph.billingActions; displayTitle = "BILLING & TRANSACTIONS"; break;
      case "CHALLANS": displayActions = ph.challanActions; displayTitle = "CHALLAN MANAGEMENT"; break;
      case "RETURNS": displayActions = ph.returnActions; displayTitle = "SALES & PUR RETURNS"; break;
      case "INVENTORY": displayActions = ph.inventoryActions; displayTitle = "STOCK & ANALYTICS"; break;
      case "ACCOUNTS": displayActions = ph.accountsActions; displayTitle = "CASH & BANK ACCOUNTS"; break;
      case "MASTERS": displayActions = ph.mastersActions; displayTitle = "BUSINESS MASTERS"; break;
      case "GST": displayActions = ph.gstActions; displayTitle = "GST COMPLIANCE"; break;
      default: displayActions = ph.mainMenuActions; displayTitle = "MAIN BUSINESS MODULES";
    }

    return PopScope(
      canPop: ph.activeModule == "HOME", 
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (ph.activeModule != "HOME") {
          ph.updateModule("HOME");
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FD),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D47A1),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ph.activeCompany?.name ?? "PHAROAH ERP", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text("FY: ${ph.currentFY}", style: const TextStyle(fontSize: 10, color: Colors.white70)),
            ],
          ),
          actions: [
            if (ph.activeModule != "HOME") 
               IconButton(icon: const Icon(Icons.grid_view_rounded), onPressed: () => ph.updateModule("HOME")),
            
            IconButton(
              icon: const Icon(Icons.search), 
              onPressed: () {
                showSearch(context: context, delegate: PharoahGlobalSearch(ph: ph));
              }
            ),

            IconButton(
              icon: const Icon(Icons.exit_to_app_rounded, color: Colors.orangeAccent), 
              tooltip: "Logout",
              onPressed: () => ph.clearSession()
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLiveKpiStrip(ph), 
                    const SizedBox(height: 30),
                    Text(displayTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey, letterSpacing: 1)),
                    const SizedBox(height: 15),
                    PharoahSmartGrid(
                      actions: displayActions,
                      onActionTap: (action) => _handleNavigation(context, ph, action),
                    ),
                  ],
                ),
              ),
            ),
            if (ph.shortages.isNotEmpty) _buildAlertsBar(ph.shortages.length),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: ph.activeModule == "GST" ? 1 : 0,
          selectedItemColor: const Color(0xFF0D47A1),
          onTap: (i) { 
            if(i == 0) ph.updateModule("HOME");
            if(i == 1) ph.updateModule("GST"); 
            if(i == 2) Navigator.push(context, MaterialPageRoute(builder: (c) => const AppSettingsView()));
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: "Menu"),
            BottomNavigationBarItem(icon: Icon(Icons.analytics_outlined), label: "GST/Reports"),
            BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: "Settings"),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveKpiStrip(PharoahManager ph) {
    DateTime now = DateTime.now();
    double todaySales = ph.sales.where((s) => s.status == "Active" && s.date.day == now.day && s.date.month == now.month).fold(0.0, (sum, s) => sum + s.totalAmount);
    double todayPur = ph.purchases.where((p) => p.date.day == now.day && p.date.month == now.month).fold(0.0, (sum, p) => sum + p.totalAmount);
    double stockVal = InventoryLogicCenter.calculateTotalStockValue(batchHistory: ph.batchHistory, medicines: ph.medicines);

    return Column(
      children: [
        Row(children: [
          Expanded(child: StatWidget(title: "TODAY SALE", value: "₹${todaySales.toStringAsFixed(0)}", period: "Live", icon: "trending_up", color: Colors.green)),
          const SizedBox(width: 12),
          Expanded(child: StatWidget(title: "TODAY PURCHASE", value: "₹${todayPur.toStringAsFixed(0)}", period: "Inward", icon: "shopping_cart", color: Colors.orange)),
        ]),
        const SizedBox(height: 12),
        StatWidget(title: "ESTIMATED STOCK VALUE", value: "₹${stockVal.toStringAsFixed(0)}", period: "Taxable", icon: "inventory_2", color: Colors.purple),
      ],
    );
  }

  Widget _buildAlertsBar(int count) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 15),
      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade100)),
      child: Row(children: [
          const Icon(Icons.notification_important_rounded, color: Colors.red, size: 20),
          const SizedBox(width: 10),
          Text("Shortage Alert: $count Items need ordering!", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11)),
          const Spacer(),
          const Icon(Icons.arrow_forward_ios, size: 10, color: Colors.red),
      ]),
    );
  }

  void _handleNavigation(BuildContext context, PharoahManager ph, ModuleAction action) {
    if (action.navModule != null && !action.navModule!.startsWith("GO_")) {
      if (action.navModule == "AI") Navigator.push(context, MaterialPageRoute(builder: (c) => const PharoahAiVision()));
      else ph.updateModule(action.navModule!);
    } else if (action.navModule != null) {
      Widget? target;
      switch (action.navModule) {
        case "GO_RETURN_PUR_REG": target = const UniversalReturnHub(); break; 
        case "GO_RETURN_SALE_REG": target = const UniversalReturnHub(); break; 
        case "GO_CHALLAN_PUR_REG": target = const PurchaseChallanRegister(); break;
        case "GO_CHALLAN_SALE_REG": target = const SaleChallanRegister(); break;
        case "GO_SALE": target = const SaleEntryView(); break;
        case "GO_PURCHASE": target = const PurchaseEntryView(); break;
        case "GO_SALE_REG": target = const SaleSummaryView(); break;
        case "GO_PUR_REG": target = const PurchaseSummaryView(); break;
        case "GO_CHALLAN_SALE": target = const SaleChallanView(); break;
        case "GO_CHALLAN_PUR": target = const PurchaseChallanView(); break;
        case "GO_CHALLAN_CONV": target = const ChallanToBillConverter(); break;
        case "GO_RETURN_SALE": target = const SaleReturnView(); break;
        case "GO_RETURN_PUR": target = const PurchaseReturnView(); break;
        case "GO_RETURN_BREAKAGE": target = const ExpiryBreakageReturnView(); break;
        case "GO_STOCK": target = const ItemLedgerSearchView(); break;
        case "GO_SHORTAGE": target = const ShortageRegister(); break;
        case "GO_ITEM_LEDGER": target = const ItemLedgerSearchView(); break;
        case "GO_DUMP": target = const StockHealthReports(); break;
        case "GO_DAYBOOK": target = const DaybookView(); break;
        case "GO_STATEMENT_HUB": target = const StatementHubView(); break;
        case "GO_LEDGERS": target = const LedgerReportsView(); break;
        case "GO_RECEIPT": target = const VoucherEntryView(type: "Receipt"); break;
        case "GO_PAYMENT": target = const VoucherEntryView(type: "Payment"); break;
        case "GO_HISTORY": target = const PaymentReceiptHistory(); break;
        case "GO_MODIFICATION": target = const ModifyHubView(); break;
        case "GO_COMPLIANCE": target = const ComplianceHub(); break;
        case "GO_M_PARTY": target = const PartyMasterView(); break;
        case "GO_M_ITEM": target = const ProductMasterView(); break;
        case "GO_M_SERIES": target = const SeriesMasterView(); break;
        case "GO_M_STAFF": target = const SystemUserMasterView(); break;
        case "GO_M_BATCH": target = const BatchMasterView(); break;
        case "GO_M_ROUTE": target = const RouteMasterView(); break;
        case "GO_M_COMP": target = const CompanyMasterView(); break;
        case "GO_M_SALT": target = const SaltMasterView(); break;
        case "GO_GST_1": target = const GSTReportDetailView(reportType: "GSTR-1"); break;
        case "GO_GST_3B": target = const GSTReportDetailView(reportType: "GSTR-3B"); break;
        case "GO_GST_RECON": target = const GSTReconciliationView(); break;
        case "GO_STITCHER_WIZARD": target = const ChallanStitcherWizard(); break;
        case "GO_DATA_HUB": target = const DataExchangeView(); break; 
        case "GO_CA_PROFILE": target = const CaProfileView(); break; // <--- NAYA CASE ADDED
      }

      if (target != null) Navigator.push(context, MaterialPageRoute(builder: (c) => target!));
    }
  }
}

class PharoahGlobalSearch extends SearchDelegate {
  final PharoahManager ph;
  PharoahGlobalSearch({required this.ph});

  @override
  List<Widget>? buildActions(BuildContext context) => [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = "")];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => _buildSearchList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchList(context);

  Widget _buildSearchList(BuildContext context) {
    if (query.isEmpty) return const Center(child: Text("Search Products or Parties..."));
    final filteredMeds = ph.medicines.where((m) => m.name.toLowerCase().contains(query.toLowerCase())).toList();
    final filteredParties = ph.parties.where((p) => p.name.toLowerCase().contains(query.toLowerCase())).toList();

    return ListView(
      children: [
        if (filteredMeds.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.all(15), child: Text("ITEMS / STOCK", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.blueGrey))),
          ...filteredMeds.map((m) => ListTile(
            leading: const Icon(Icons.medication, color: Colors.purple),
            title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("Stock: ${m.stock} | Pack: ${m.packing}"),
            onTap: () { close(context, null); Navigator.push(context, MaterialPageRoute(builder: (c) => ItemLedgerDetailView(medicine: m))); },
          )),
        ],
        if (filteredParties.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.all(15), child: Text("PARTIES / LEDGERS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.blueGrey))),
          ...filteredParties.map((p) => ListTile(
            leading: const Icon(Icons.person, color: Colors.indigo),
            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("${p.city} | ${p.group}"),
            onTap: () { close(context, null); Navigator.push(context, MaterialPageRoute(builder: (c) => SingleLedgerDetailView(party: p))); },
          )),
        ],
      ],
    );
  }
}
