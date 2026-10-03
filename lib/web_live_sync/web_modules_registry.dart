import 'package:flutter/material.dart';

class WebActionItem {
  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const WebActionItem({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

class WebHubItem {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<WebActionItem> subActions;

  const WebHubItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.subActions,
  });
}

class WebModulesRegistry {
  static const List<WebHubItem> allHubs = [
    // 1. BILLING & TRANSACTIONS
    WebHubItem(
      id: "BILLING",
      title: "BILLING & SALES",
      subtitle: "Invoicing, Purchases & Registers",
      icon: Icons.receipt_long_rounded,
      color: Color(0xFF2563EB),
      subActions: [
        WebActionItem(key: "GO_SALE", title: "New Sale Bill", subtitle: "Standard Outward Tax Invoice", icon: Icons.add_shopping_cart, color: Color(0xFF2563EB)),
        WebActionItem(key: "GO_PURCHASE", title: "Purchase", subtitle: "Stock Inward Invoicing", icon: Icons.downloading_rounded, color: Color(0xFFEA580C)),
        WebActionItem(key: "GO_SALE_REG", title: "Sale Reg", subtitle: "Outward Bills Summary & Audit", icon: Icons.description_outlined, color: Color(0xFF3B82F6)),
        WebActionItem(key: "GO_PUR_REG", title: "Pur Reg", subtitle: "Inward Tax Register & Summary", icon: Icons.history_rounded, color: Color(0xFFB45309)),
      ],
    ),

    // 2. DELIVERY CHALLANS (4 EXACT APP BUTTONS)
    WebHubItem(
      id: "CHALLANS",
      title: "CHALLAN MANAGEMENT",
      subtitle: "Inward/Outward Notes & Registers",
      icon: Icons.local_shipping_rounded,
      color: Color(0xFF0F766E),
      subActions: [
        WebActionItem(key: "GO_CHALLAN_SALE", title: "Sale Challan", subtitle: "Outward Delivery Note", icon: Icons.local_shipping_rounded, color: Colors.teal),
        WebActionItem(key: "GO_CHALLAN_PUR", title: "Pur Challan", subtitle: "Inward Purchase Note", icon: Icons.inventory_2_rounded, color: Colors.orange),
        WebActionItem(key: "GO_CHALLAN_SALE_REG", title: "Sale Reg", subtitle: "Outward Challans Register", icon: Icons.list_alt_rounded, color: Colors.indigo),
        WebActionItem(key: "GO_CHALLAN_PUR_REG", title: "Pur Reg", subtitle: "Inward Challans Register", icon: Icons.history_edu_rounded, color: Colors.amber),
      ],
    ),

    // 3. RETURNS
    WebHubItem(
      id: "RETURNS",
      title: "RETURNS & REVERSALS",
      subtitle: "Credit Notes, Debit Notes & Breakage",
      icon: Icons.assignment_return_rounded,
      color: Color(0xFFDC2626),
      subActions: [
        WebActionItem(key: "GO_CN", title: "Credit Note", subtitle: "Sellable Customer Return", icon: Icons.assignment_return_rounded, color: Color(0xFFDC2626)),
        WebActionItem(key: "GO_DN", title: "Debit Note", subtitle: "Return to Distributor", icon: Icons.remove_shopping_cart_rounded, color: Color(0xFF92400E)),
        WebActionItem(key: "GO_BREAKAGE", title: "Breakage / Expiry", subtitle: "Non-Sellable Stock Out", icon: Icons.delete_sweep_rounded, color: Color(0xFFEA580C)),
        WebActionItem(key: "GO_RET_REG", title: "Return Reg", subtitle: "Full Reversals History", icon: Icons.format_list_bulleted_rounded, color: Color(0xFF991B1B)),
      ],
    ),

    // 4. INVENTORY
    WebHubItem(
      id: "INVENTORY",
      title: "STOCK & ANALYTICS",
      subtitle: "Live Stock, 1.5x Shortage & Batches",
      icon: Icons.inventory_2_rounded,
      color: Color(0xFF7C3AED),
      subActions: [
        WebActionItem(key: "GO_STOCK", title: "Stock", subtitle: "Batch & Expiry Search", icon: Icons.view_in_ar_rounded, color: Color(0xFF7C3AED)),
        WebActionItem(key: "GO_SHORTAGE", title: "Shortage", subtitle: "45-Days Requirement PO", icon: Icons.trending_down_rounded, color: Color(0xFFDC2626)),
        WebActionItem(key: "GO_ITEM_LEDGER", title: "Ledger", subtitle: "In/Out Stock Timeline", icon: Icons.menu_book_rounded, color: Color(0xFF475569)),
        WebActionItem(key: "GO_DUMP", title: "Dumping", subtitle: "Dead Stock Analysis (90 Days)", icon: Icons.delete_sweep_outlined, color: Color(0xFFC2410C)),
      ],
    ),

    // 5. ACCOUNTS
    WebHubItem(
      id: "ACCOUNTS",
      title: "CASH & BANK ACCOUNTS",
      subtitle: "Daybook, Vouchers & Ledgers",
      icon: Icons.account_balance_wallet_rounded,
      color: Color(0xFF3730A3),
      subActions: [
        WebActionItem(key: "GO_RECEIPT", title: "Receipts", subtitle: "Customer Inflow & Collection", icon: Icons.add_chart_rounded, color: Color(0xFF15803D)),
        WebActionItem(key: "GO_PAYMENT", title: "Payments", subtitle: "Supplier Payment Out", icon: Icons.analytics_rounded, color: Color(0xFFB91C1C)),
        WebActionItem(key: "GO_CONTRA", title: "Contra", subtitle: "Bank Deposit & Withdrawal", icon: Icons.sync_alt_rounded, color: Color(0xFFD97706)),
        WebActionItem(key: "GO_EXPENSE", title: "Expenses", subtitle: "Store Operating Expenses", icon: Icons.money_off_rounded, color: Color(0xFFB45309)),
        WebActionItem(key: "GO_DAYBOOK", title: "Daybook", subtitle: "Daily Inflow & Outflow", icon: Icons.event_note_rounded, color: Color(0xFF475569)),
        WebActionItem(key: "GO_HISTORY", title: "Audit History", subtitle: "Voucher Register & Excel", icon: Icons.format_list_bulleted_rounded, color: Color(0xFF0F766E)),
        WebActionItem(key: "GO_BANK_BOOK", title: "Passbook", subtitle: "Bank Ledger Statement", icon: Icons.account_balance_rounded, color: Color(0xFF0284C7)),
        WebActionItem(key: "GO_LEDGERS", title: "Ledgers", subtitle: "Party Balance & Statements", icon: Icons.people_alt_rounded, color: Color(0xFF4338CA)),
      ],
    ),

    // 6. MASTERS
    WebHubItem(
      id: "MASTERS",
      title: "BUSINESS MASTERS",
      subtitle: "Parties, Medicines, Salts & Brands",
      icon: Icons.stars_rounded,
      color: Color(0xFFC2410C),
      subActions: [
        WebActionItem(key: "GO_M_PARTY", title: "Parties", subtitle: "Customers & Suppliers", icon: Icons.group_add_rounded, color: Color(0xFF4338CA)),
        WebActionItem(key: "GO_M_ITEM", title: "Items", subtitle: "Drug & Product Catalog", icon: Icons.medication_rounded, color: Color(0xFF7C3AED)),
        WebActionItem(key: "GO_M_BATCH", title: "Batches", subtitle: "Central Batch Adjustments", icon: Icons.layers_outlined, color: Color(0xFF312E81)),
        WebActionItem(key: "GO_M_ROUTE", title: "Routes", subtitle: "Delivery Route Planner", icon: Icons.map_rounded, color: Color(0xFF0F766E)),
        WebActionItem(key: "GO_M_COMP", title: "Company", subtitle: "Manufacturer Library", icon: Icons.business_rounded, color: Color(0xFF9A3412)),
        WebActionItem(key: "GO_M_SALT", title: "Salt Master", subtitle: "Mono/Duo Salt Master", icon: Icons.science_rounded, color: Color(0xFFC2410C)),
        WebActionItem(key: "GO_M_CA", title: "CA Profile", subtitle: "Auditor & Mail Redirection", icon: Icons.assignment_ind_rounded, color: Color(0xFFEA580C)),
      ],
    ),

    // 7. GST
    WebHubItem(
      id: "GST",
      title: "GST COMPLIANCE",
      subtitle: "GSTR-1, GSTR-3B, GSTR-2, Recon & E-Way",
      icon: Icons.verified_rounded,
      color: Color(0xFF15803D),
      subActions: [
        WebActionItem(key: "GO_GST_1", title: "GSTR-1", subtitle: "B2B, B2C, HSN & Docs", icon: Icons.assignment_outlined, color: Color(0xFF15803D)),
        WebActionItem(key: "GO_GST_3B", title: "GSTR-3B", subtitle: "Monthly Tax Computation", icon: Icons.summarize_outlined, color: Color(0xFF2563EB)),
        WebActionItem(key: "GO_GST_2", title: "GSTR-2", subtitle: "Purchase Register & ITC", icon: Icons.shopping_cart_checkout_rounded, color: Color(0xFFD97706)),
        WebActionItem(key: "GO_GST_RECON", title: "Portal Match", subtitle: "2A / 2B ITC Reconciliation", icon: Icons.fact_check_outlined, color: Color(0xFF0D9488)),
        WebActionItem(key: "GO_EWAY", title: "E-Way Bill", subtitle: ">= ₹50,000 JSON Download", icon: Icons.local_shipping_outlined, color: Color(0xFF6366F1)),
      ],
    ),

    // 8. DATA HUB
    WebHubItem(
      id: "DATA_HUB",
      title: "DATA EXCHANGE HUB",
      subtitle: "C2C Store Sync & 39-Col Universal CSV",
      icon: Icons.cloud_sync_rounded,
      color: Color(0xFF334155),
      subActions: [
        WebActionItem(key: "GO_SMART_ENTRY", title: "Smart Entry", subtitle: "1. Medilente  2. Amazon", icon: Icons.auto_fix_high_rounded, color: Color(0xFF38BDF8)),
        WebActionItem(key: "GO_C2C", title: "Store to Store", subtitle: "Internal Branch Synchronization", icon: Icons.sync_alt_rounded, color: Color(0xFF2563EB)),
        WebActionItem(key: "GO_C2V", title: "Vendor Supply", subtitle: "External Trade (Masked Rate)", icon: Icons.business_center_rounded, color: Color(0xFF0D9488)),
        WebActionItem(key: "GO_CSV", title: "39-Col CSV", subtitle: "Universal Data Import/Export", icon: Icons.table_chart_rounded, color: Color(0xFFD97706)),
      ],
    ),
  ];
}
