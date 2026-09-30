// FILE: lib/modifications/modify_hub_view.dart (Replace Full)

import 'package:flutter/material.dart';
import 'sub_views/modify_sales_list.dart';
import 'sub_views/modify_purchase_list.dart';
import 'sub_views/modify_challan_list.dart';
import 'sub_views/modify_returns_list.dart';

class ModifyHubView extends StatefulWidget {
  const ModifyHubView({super.key});
  @override State<ModifyHubView> createState() => _ModifyHubViewState();
}

class _ModifyHubViewState extends State<ModifyHubView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchC = TextEditingController();
  String query = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Universal Modification Hub"),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.orange,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: "SALE BILLS", icon: Icon(Icons.receipt, size: 18)),
            Tab(text: "PURCHASE", icon: Icon(Icons.shopping_bag, size: 18)),
            Tab(text: "CHALLANS", icon: Icon(Icons.local_shipping, size: 18)),
            Tab(text: "RETURNS", icon: Icon(Icons.assignment_return, size: 18)),
          ],
        ),
      ),
      body: Column(
        children: [
          // --- GLOBAL SEARCH ---
          Container(
            padding: const EdgeInsets.all(15),
            color: Colors.blue.shade900,
            child: TextField(
              controller: _searchC,
              style: const TextStyle(color: Colors.white),
              onChanged: (v) => setState(() => query = v),
              decoration: InputDecoration(
                hintText: "Search by Number, Name or Amount...",
                hintStyle: const TextStyle(color: Colors.white60),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                filled: true, fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          // --- TAB VIEWS ---
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                ModifySalesList(searchQuery: query),
                ModifyPurchaseList(searchQuery: query),
                ModifyChallanList(searchQuery: query),
                ModifyReturnsList(searchQuery: query),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
