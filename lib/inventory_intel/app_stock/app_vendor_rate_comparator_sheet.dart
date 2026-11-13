// FILE: lib/inventory_intel/app_stock/app_vendor_rate_comparator_sheet.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pharoah_erp/models.dart';
import 'package:pharoah_erp/pharoah_manager.dart';
import 'package:provider/provider.dart';
import 'app_stock_analytics_engine.dart';
import 'app_stock_theme.dart';

class AppVendorRateComparatorSheet extends StatelessWidget {
  final Medicine medicine;
  final String companyName;

  const AppVendorRateComparatorSheet({
    super.key,
    required this.medicine,
    required this.companyName,
  });

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final med = ph.medicines.firstWhere(
      (m) => (m.identityKey.isNotEmpty && m.identityKey == medicine.identityKey) || m.id == medicine.id,
      orElse: () => medicine,
    );
    final data = AppStockAnalyticsEngine.buildVendorInwardRecords(ph, med);
    final inwardRecords = data.inwardRecords;
    final summaries = data.vendorSummaries;
    final overallMin = data.overallMinRate;
    final overallMax = data.overallMaxRate;
    final double spreadPct = overallMin > 0 ? ((overallMax - overallMin) / overallMin) * 100 : 0.0;

    return Scaffold(
      backgroundColor: MargStockTheme.canvas,
      appBar: AppBar(
        backgroundColor: MargStockTheme.headerDark,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Vendor Rate Radar • ${med.name}",
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              "$companyName  •  ${med.packing}  •  Curr Pur: ₹${med.purRate.toStringAsFixed(2)}",
              style: const TextStyle(fontSize: 10.5, color: Colors.white70),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: inwardRecords.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.storefront_rounded, size: 46, color: MargStockTheme.textMuted),
                  SizedBox(height: 8),
                  Text(
                    "No purchase history found for this item",
                    style: TextStyle(color: MargStockTheme.textMuted, fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // Top Summary KPI Strip
                Row(
                  children: [
                    _statTile("SUPPLIERS", "${summaries.length}", MargStockTheme.headerDark, MargStockTheme.accentLight),
                    const SizedBox(width: 8),
                    _statTile("LOWEST NET", "₹${overallMin.toStringAsFixed(2)}", MargStockTheme.stockOk, MargStockTheme.stockOkBg),
                    const SizedBox(width: 8),
                    _statTile("HIGHEST NET", "₹${overallMax.toStringAsFixed(2)}", MargStockTheme.stockAlert, MargStockTheme.stockAlertBg),
                    const SizedBox(width: 8),
                    _statTile("SPREAD", "${spreadPct.toStringAsFixed(1)}%", MargStockTheme.goldText, MargStockTheme.goldBg),
                  ],
                ),
                const SizedBox(height: 16),

                const Text(
                  "SUPPLIER BENCHMARKING (LOWEST TO HIGHEST)",
                  style: TextStyle(
                    color: MargStockTheme.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 8),

                ...summaries.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final v = entry.value;
                  final bool isBest = idx == 0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isBest ? const Color(0xFFF0FDF4) : MargStockTheme.cardBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isBest ? MargStockTheme.stockOk : MargStockTheme.border,
                        width: isBest ? 1.3 : 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                v.vendorName,
                                style: const TextStyle(
                                  color: MargStockTheme.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (isBest)
                              MargStockTheme.badge(
                                label: "BEST RATE",
                                fg: Colors.white,
                                bg: MargStockTheme.stockOk,
                                icon: Icons.verified_rounded,
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _miniMetric("LATEST NET", "₹${v.latestRate.toStringAsFixed(2)}", MargStockTheme.headerDark),
                            _miniMetric("MIN / MAX", "₹${v.minRate.toStringAsFixed(1)} / ₹${v.maxRate.toStringAsFixed(1)}", MargStockTheme.textSecondary),
                            _miniMetric("BOUGHT", "${formatQty(v.totalQty)} (${v.purchaseCount}x)", MargStockTheme.codeBlue),
                          ],
                        ),
                        if (v.isHike || v.isDrop) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: v.isHike ? MargStockTheme.stockAlertBg : MargStockTheme.stockOkBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  v.isHike ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                                  size: 14,
                                  color: v.isHike ? MargStockTheme.stockAlert : MargStockTheme.stockOk,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    v.isHike
                                        ? "Rate hiked from ₹${v.firstRate.toStringAsFixed(2)} -> ₹${v.latestRate.toStringAsFixed(2)} (+${v.priceChangePct.toStringAsFixed(1)}%)"
                                        : "Rate dropped from ₹${v.firstRate.toStringAsFixed(2)} -> ₹${v.latestRate.toStringAsFixed(2)} (${v.priceChangePct.toStringAsFixed(1)}%)",
                                    style: TextStyle(
                                      color: v.isHike ? MargStockTheme.stockAlert : MargStockTheme.stockOk,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text(
                      "INWARD INVOICE CHRONOLOGY",
                      style: TextStyle(
                        color: MargStockTheme.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      "${inwardRecords.length} Bills",
                      style: const TextStyle(color: MargStockTheme.textMuted, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                ...inwardRecords.map((r) {
                  final double effRate = r['effRate'] as double;
                  final double rawRate = r['rawRate'] as double;
                  final double discPer = r['discPer'] as double;
                  final double mrp = r['mrp'] as double;
                  final double freeQ = r['freeQty'] as double;
                  final bool isMin = (effRate - overallMin).abs() < 0.01;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: MargStockTheme.cardBg,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: MargStockTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            MargStockTheme.badge(
                              label: "#${r['billNo']}",
                              fg: MargStockTheme.codeBlue,
                              bg: MargStockTheme.codeBlueBg,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                r['vendor'].toString(),
                                style: const TextStyle(
                                  color: MargStockTheme.textPrimary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              DateFormat('dd/MM/yy').format(r['date'] as DateTime),
                              style: const TextStyle(color: MargStockTheme.textMuted, fontSize: 11),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Batch: ${(r['batch']?.toString().isNotEmpty == true) ? r['batch'] : 'NO BATCH'} (${r['exp']})",
                              style: const TextStyle(color: MargStockTheme.textSecondary, fontSize: 11),
                            ),
                            Text(
                              "Qty: ${freeQ > 0 ? formatQtyPair(r['qty'], freeQ) : formatQty(r['qty'])}",
                              style: const TextStyle(color: MargStockTheme.textPrimary, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Raw: ₹${rawRate.toStringAsFixed(2)}  •  Disc: ${discPer.toStringAsFixed(1)}%  •  MRP: ₹${mrp.toStringAsFixed(2)}",
                              style: const TextStyle(color: MargStockTheme.textMuted, fontSize: 10.5),
                            ),
                            Text(
                              "Net: ₹${effRate.toStringAsFixed(2)}",
                              style: MargStockTheme.tabularNum.copyWith(
                                fontSize: 12,
                                color: isMin ? MargStockTheme.stockOk : MargStockTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }

  Widget _statTile(String label, String val, Color fg, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: fg.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: fg, fontSize: 8.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(val, style: MargStockTheme.tabularNum.copyWith(color: fg, fontSize: 12.5), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _miniMetric(String label, String val, Color c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: MargStockTheme.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold)),
        Text(val, style: MargStockTheme.tabularNum.copyWith(color: c, fontSize: 12)),
      ],
    );
  }
}
