import 'package:flutter/material.dart';
import 'widgets.dart';
import 'gst_report_detail_view.dart';
import 'eway_bill_management_view.dart';
import 'gst_reconciliation_view.dart';

class GSTMenuView extends StatelessWidget {
  const GSTMenuView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: const Text("GST Reports & Compliance"),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- SECTION 1: STATUTORY RETURNS ---
            _buildSectionTitle("GOVERNMENT RETURNS"),
            const SizedBox(height: 15),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 0.9,
              children: [
                // GSTR-1: Sales Register
                ActionIconBtn(
                  title: "GSTR-1",
                  icon: Icons.assignment_outlined,
                  color: Colors.green,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (c) => const GSTReportDetailView(reportType: "GSTR-1 (Sales Register)"),
                    ),
                  ),
                ),
                // GSTR-3B: Monthly Summary & Tax Payment
                ActionIconBtn(
                  title: "GSTR-3B",
                  icon: Icons.summarize_outlined,
                  color: Colors.blue,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (c) => const GSTReportDetailView(reportType: "GSTR-3B (Monthly Summary)"),
                    ),
                  ),
                ),
                // GSTR-2: Purchase Register / ITC Check
                ActionIconBtn(
                  title: "GSTR-2",
                  icon: Icons.shopping_cart_checkout_rounded,
                  color: Colors.orange,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (c) => const GSTReportDetailView(reportType: "GSTR-2 (Purchase Register)"),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 35),

            // --- SECTION 2: TOOLS & RECONCILIATION ---
            _buildSectionTitle("RECONCILIATION & TOOLS"),
            const SizedBox(height: 15),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 0.9,
              children: [
                // E-Way Bill Generation for High-Value Invoices
                ActionIconBtn(
                  title: "E-Way Bill",
                  icon: Icons.local_shipping_outlined,
                  color: Colors.indigo,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (c) => const EWayBillManagementView(),
                    ),
                  ),
                ),
                // Portal Match: Reconcile Purchase with GSTR-2A/2B
                ActionIconBtn(
                  title: "Portal Match",
                  icon: Icons.fact_check_outlined,
                  color: Colors.teal,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (c) => const GSTReconciliationView(),
                    ),
                  ),
                ),
                // Placeholder for HSN Wise Summary
                ActionIconBtn(
                  title: "HSN Sum",
                  icon: Icons.grid_on_rounded,
                  color: Colors.blueGrey,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("HSN-wise summary is being prepared for next update.")),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 40),

            // --- USER GUIDANCE CARD ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
              ),
              child: const Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline, color: Colors.orange),
                      SizedBox(width: 10),
                      Text("Accounting Tip", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text(
                    "Always mark your purchase bills as 'Matched' using the Portal Match tool once they appear in your GSTR-2A online. This ensures accurate ITC claims.",
                    style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.blueGrey,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
