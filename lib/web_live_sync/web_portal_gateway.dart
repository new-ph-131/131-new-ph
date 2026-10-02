// FILE: lib/web_live_sync/web_portal_gateway.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pharoah_web_manager.dart';
import 'components/web_top_bar.dart';
import 'components/web_recent_sidebar.dart';
import 'components/web_kpi_strip.dart';
import 'components/web_module_grid.dart';
import 'components/web_invoice_feed.dart';
import 'components/web_login_card.dart';

// Sub Views
import 'sub_views/web_billing/web_new_sale_view.dart';
import 'web_sale_summary_view.dart';
import 'web_purchase_entry_view.dart';
import 'web_purchase_summary_view.dart';
import 'web_challan_stitcher_wizard.dart';
import 'web_returns_view.dart';
import 'sub_views/web_challans/web_challan_hub.dart'; 
import 'sub_views/web_challans/web_sale_challan_view.dart';
import 'sub_views/web_challans/web_purchase_challan_view.dart';
import 'web_voucher_view.dart';
import 'web_product_master.dart';
import 'web_party_master.dart';
import 'web_batch_master.dart';
import 'web_aux_masters.dart';
import 'web_challan_view.dart';
import 'sub_views/web_smart_entry/ui/web_smart_entry_hub.dart';

class WebPortalGateway extends StatefulWidget {
  const WebPortalGateway({super.key});

  @override
  State<WebPortalGateway> createState() => _WebPortalGatewayState();
}

class _WebPortalGatewayState extends State<WebPortalGateway> {
  String currentView = "HOME";
  String currentViewTitle = "MAIN BUSINESS MODULES";
  String searchQuery = "";

  List<Map<String, dynamic>> recentShortcuts = [];

  void _navigateToHub(String hubId, String hubTitle) {
    setState(() {
      currentView = hubId;
      currentViewTitle = hubTitle;
    });
  }

  void _handleActionTap(String actionTitle, IconData icon, String navKey) {
    if (!recentShortcuts.any((item) => item['module'] == navKey)) {
      setState(() {
        recentShortcuts.insert(0, {
          "title": actionTitle,
          "icon": icon,
          "module": navKey,
        });
        if (recentShortcuts.length > 8) {
          recentShortcuts.removeLast();
        }
      });
    }
    _navigateToHub(navKey, actionTitle.toUpperCase());
  }

  void _removeShortcut(int index) {
    setState(() {
      recentShortcuts.removeAt(index);
    });
  }

  void _clearAllRecents() {
    setState(() {
      recentShortcuts.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    if (!webPh.isAuthenticated) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: WebLoginCard(
          errorMessage: webPh.errorMessage,
          isLoading: webPh.isLoading,
          onLogin: (token, user, pass) => webPh.loginWithStoreKey(
            storeToken: token,
            username: user,
            password: pass,
          ),
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    bool isHomeDashboard = currentView == "HOME";
    bool showSidebar = isHomeDashboard && screenWidth > 900;

    return Scaffold(
      backgroundColor: const Color(0xFF0B132B),
      appBar: WebTopBar(
        webPh: webPh,
        showGlobalSearch: isHomeDashboard,
        onSearchChanged: (v) => setState(() => searchQuery = v),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showSidebar)
            WebRecentSidebar(
              currentView: currentView,
              recentShortcuts: recentShortcuts,
              onHomeTap: () => _navigateToHub("HOME", "MAIN BUSINESS MODULES"),
              onActionTap: _handleActionTap,
              onRemoveShortcut: _removeShortcut,
              onClearAll: _clearAllRecents,
            ),

          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: screenWidth > 600 ? 18.0 : 10.0,
                vertical: 14.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBreadcrumbs(),
                  const SizedBox(height: 14),
                  _buildCurrentView(webPh),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentView(PharoahWebManager webPh) {
    // --- DATA HUB ---
    if (currentView == "GO_SMART_ENTRY") {
      return WebSmartEntryHub(onBack: () => _navigateToHub("DATA_HUB", "DATA EXCHANGE HUB"));
    }
    
    // --- BILLING & SALES ---
    if (currentView == "GO_SALE") {
      return WebNewSaleView(onBack: () => _navigateToHub("BILLING", "BILLING & SALES"));
    }
    if (currentView == "GO_SALE_REG") {
      return WebSaleSummaryView(onBack: () => _navigateToHub("BILLING", "BILLING & SALES"));
    }
    if (currentView == "GO_PURCHASE") {
      return WebPurchaseEntryView(onBack: () => _navigateToHub("BILLING", "BILLING & SALES"));
    }
    if (currentView == "GO_PUR_REG") {
      return WebPurchaseSummaryView(onBack: () => _navigateToHub("BILLING", "BILLING & SALES"));
    }
    
    // --- CHALLANS ---
    if (currentView == "GO_STITCHER") {
      return WebChallanStitcherWizard(onBack: () => _navigateToHub("CHALLANS", "CHALLAN MANAGEMENT"));
    }
    if (currentView == "GO_CHALLAN_SALE") {
      return WebSaleChallanView(onBack: () => _navigateToHub("CHALLANS", "CHALLAN MANAGEMENT"));
    }
    if (currentView == "GO_CHALLAN_PUR") {
      return WebPurchaseChallanView(onBack: () => _navigateToHub("CHALLANS", "CHALLAN MANAGEMENT"));
    }
    if (currentView == "GO_CHALLAN_SALE_REG") {
      return WebChallanView(onBack: () => _navigateToHub("CHALLANS", "CHALLAN MANAGEMENT"), initialTabIndex: 2);
    }
    if (currentView == "GO_CHALLAN_PUR_REG") {
      return WebChallanView(onBack: () => _navigateToHub("CHALLANS", "CHALLAN MANAGEMENT"), initialTabIndex: 3);
    }
    if (currentView == "CHALLANS") {
      return WebChallanHub(onBack: () => _navigateToHub("HOME", "MAIN BUSINESS MODULES"));
    }

    // --- RETURNS & REVERSALS ---
    if (currentView == "GO_CN" || currentView == "GO_DN" || currentView == "GO_BREAKAGE" || currentView == "GO_RET_REG" || currentView == "RETURNS") {
      return WebReturnsView(
        onBack: () => _navigateToHub("HOME", "MAIN BUSINESS MODULES"),
        initialAction: currentView,
      );
    }

    // --- ACCOUNTS & VOUCHERS ---
    if (currentView == "GO_RECEIPT" || currentView == "GO_PAYMENT" || currentView == "GO_DAYBOOK" || currentView == "GO_LEDGERS" || currentView == "ACCOUNTS") {
      int tabIdx = 0;
      if (currentView == "GO_PAYMENT") tabIdx = 1;
      if (currentView == "GO_DAYBOOK" || currentView == "GO_LEDGERS") tabIdx = 2;
      return WebVoucherView(onBack: () => _navigateToHub("HOME", "MAIN BUSINESS MODULES"), initialTabIndex: tabIdx);
    }

    // --- INVENTORY ---
    if (currentView == "GO_STOCK" || currentView == "GO_SHORTAGE" || currentView == "INVENTORY") {
      return WebProductMasterView(onBack: () => _navigateToHub("INVENTORY", "STOCK & ANALYTICS"));
    }

    // --- MASTERS ---
    if (currentView == "GO_M_ITEM") {
      return WebProductMasterView(onBack: () => _navigateToHub("MASTERS", "BUSINESS MASTERS"));
    }
    if (currentView == "GO_M_PARTY") {
      return WebPartyMasterView(onBack: () => _navigateToHub("MASTERS", "BUSINESS MASTERS"));
    }
    if (currentView == "GO_M_BATCH") {
      return WebBatchMasterView(onBack: () => _navigateToHub("MASTERS", "BUSINESS MASTERS"));
    }

    // --- AUX MASTERS ---
    if (currentView == "GO_M_COMP" || currentView == "GO_M_SALT" || currentView == "GO_M_ROUTE") {
      int tabIdx = 0;
      if (currentView == "GO_M_SALT") tabIdx = 1;
      if (currentView == "GO_M_ROUTE") tabIdx = 2;
      return WebAuxMastersView(onBack: () => _navigateToHub("MASTERS", "BUSINESS MASTERS"), initialTabIndex: tabIdx);
    }

    // --- DEFAULT GRID (HOME) ---
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WebKpiStrip(webPh: webPh),
        const SizedBox(height: 18),
        WebModuleGrid(
          currentView: currentView,
          onHubTap: _navigateToHub,
          onActionTap: _handleActionTap,
          onBackToHome: () => _navigateToHub("HOME", "MAIN BUSINESS MODULES"),
        ),
        const SizedBox(height: 20),
        if (currentView == "HOME")
          WebInvoiceFeed(webPh: webPh),
      ],
    );
  }

  Widget _buildBreadcrumbs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => _navigateToHub("HOME", "MAIN BUSINESS MODULES"),
            child: const Row(
              children: [
                Icon(Icons.home_rounded, color: Color(0xFF38BDF8), size: 14),
                SizedBox(width: 5),
                Text("Home", style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          if (currentView != "HOME") ...[
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 14),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                currentViewTitle,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const Spacer(),
          if (currentView != "HOME")
            InkWell(
              onTap: () => _navigateToHub("HOME", "MAIN BUSINESS MODULES"),
              child: const Row(
                children: [
                  Icon(Icons.arrow_back_rounded, color: Colors.white54, size: 13),
                  SizedBox(width: 4),
                  Text("Back", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
