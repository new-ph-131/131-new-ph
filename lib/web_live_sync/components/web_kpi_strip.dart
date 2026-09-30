// FILE: lib/web_live_sync/components/web_kpi_strip.dart

import 'package:flutter/material.dart';
import '../pharoah_web_manager.dart';

class WebKpiStrip extends StatelessWidget {
  final PharoahWebManager webPh;

  const WebKpiStrip({super.key, required this.webPh});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    double todaySales = 0.0;
    int todaySalesCount = 0;
    for (var s in webPh.sales) {
      if (s.date.year == now.year && s.date.month == now.month && s.date.day == now.day && s.status == "Active") {
        todaySales += s.totalAmount;
        todaySalesCount++;
      }
    }

    double todayPurchases = 0.0;
    int todayPurCount = 0;
    for (var p in webPh.purchases) {
      if (p.date.year == now.year && p.date.month == now.month && p.date.day == now.day) {
        todayPurchases += p.totalAmount;
        todayPurCount++;
      }
    }

    double totalStockVal = 0.0;
    for (var m in webPh.medicines) {
      totalStockVal += (m.stock * m.purRate);
    }

    double totalOutstanding = 0.0;
    int debtorsCount = 0;
    for (var p in webPh.parties) {
      if (p.opBal > 0 && p.group == "Sundry Debtors") {
        totalOutstanding += p.opBal;
        debtorsCount++;
      }
    }

    String salesDisplay = todaySales > 0 ? "₹${todaySales.toStringAsFixed(0)}" : (webPh.sales.isNotEmpty ? "₹${_totalSales(webPh).toStringAsFixed(0)}" : "₹0");
    String salesSub = todaySalesCount > 0 ? "$todaySalesCount Bills Today" : "${webPh.sales.length} Total Bills";

    String purDisplay = todayPurchases > 0 ? "₹${todayPurchases.toStringAsFixed(0)}" : (webPh.purchases.isNotEmpty ? "₹${_totalPur(webPh).toStringAsFixed(0)}" : "₹0");
    String purSub = todayPurCount > 0 ? "$todayPurCount Inwards Today" : "${webPh.purchases.length} Total Inwards";

    String stockDisplay = totalStockVal > 0 ? "₹${totalStockVal.toStringAsFixed(0)}" : "${webPh.medicines.length} Items";
    String stockSub = "${webPh.medicines.length} Catalog Items";

    String outDisplay = totalOutstanding > 0 ? "₹${totalOutstanding.toStringAsFixed(0)}" : "${webPh.parties.length} Parties";
    String outSub = "$debtorsCount Debtors";

    return LayoutBuilder(
      builder: (context, constraints) {
        bool isWide = constraints.maxWidth > 950;
        bool isMedium = constraints.maxWidth > 550;

        if (isWide) {
          return Row(
            children: [
              Expanded(child: _kpiCard("TODAY SALES", salesDisplay, salesSub, Icons.trending_up_rounded, const Color(0xFF10B981))),
              const SizedBox(width: 12),
              Expanded(child: _kpiCard("TODAY PURCHASES", purDisplay, purSub, Icons.shopping_cart_rounded, const Color(0xFFF59E0B))),
              const SizedBox(width: 12),
              Expanded(child: _kpiCard("STOCK VALUATION", stockDisplay, stockSub, Icons.inventory_2_rounded, const Color(0xFF06B6D4))),
              const SizedBox(width: 12),
              Expanded(child: _kpiCard("OUTSTANDING", outDisplay, outSub, Icons.account_balance_wallet_rounded, const Color(0xFF8B5CF6))),
            ],
          );
        } else if (isMedium) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: _kpiCard("TODAY SALES", salesDisplay, salesSub, Icons.trending_up_rounded, const Color(0xFF10B981))),
                  const SizedBox(width: 10),
                  Expanded(child: _kpiCard("TODAY PURCHASES", purDisplay, purSub, Icons.shopping_cart_rounded, const Color(0xFFF59E0B))),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _kpiCard("STOCK VALUATION", stockDisplay, stockSub, Icons.inventory_2_rounded, const Color(0xFF06B6D4))),
                  const SizedBox(width: 10),
                  Expanded(child: _kpiCard("OUTSTANDING", outDisplay, outSub, Icons.account_balance_wallet_rounded, const Color(0xFF8B5CF6))),
                ],
              ),
            ],
          );
        } else {
          return Column(
            children: [
              _kpiCard("TODAY SALES", salesDisplay, salesSub, Icons.trending_up_rounded, const Color(0xFF10B981)),
              const SizedBox(height: 8),
              _kpiCard("TODAY PURCHASES", purDisplay, purSub, Icons.shopping_cart_rounded, const Color(0xFFF59E0B)),
              const SizedBox(height: 8),
              _kpiCard("STOCK VALUATION", stockDisplay, stockSub, Icons.inventory_2_rounded, const Color(0xFF06B6D4)),
              const SizedBox(height: 8),
              _kpiCard("OUTSTANDING", outDisplay, outSub, Icons.account_balance_wallet_rounded, const Color(0xFF8B5CF6)),
            ],
          );
        }
      },
    );
  }

  double _totalSales(PharoahWebManager ph) => ph.sales.where((s) => s.status == "Active").fold(0.0, (sum, s) => sum + s.totalAmount);
  double _totalPur(PharoahWebManager ph) => ph.purchases.fold(0.0, (sum, p) => sum + p.totalAmount);

  Widget _kpiCard(String title, String value, String sub, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF19243B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(90), width: 1.2),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              Icon(icon, color: color, size: 16),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(sub, style: const TextStyle(color: Colors.white38, fontSize: 8.5)),
        ],
      ),
    );
  }
}
