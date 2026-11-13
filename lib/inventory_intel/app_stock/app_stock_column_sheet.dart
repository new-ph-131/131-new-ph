// FILE: lib/inventory_intel/app_stock/app_stock_column_sheet.dart
import 'package:flutter/material.dart';
import 'package:pharoah_erp/web_live_sync/sub_views/web_stock/models/stock_column_model.dart';
import 'app_stock_theme.dart';

class AppStockColumnSheet extends StatefulWidget {
  final Map<StockColumnId, StockColumnDef> columnDefs;
  final FreezePaneOption currentFreeze;
  final void Function(Map<StockColumnId, StockColumnDef> newDefs, FreezePaneOption newFreeze) onApply;

  const AppStockColumnSheet({
    super.key,
    required this.columnDefs,
    required this.currentFreeze,
    required this.onApply,
  });

  @override
  State<AppStockColumnSheet> createState() => _AppStockColumnSheetState();
}

class _AppStockColumnSheetState extends State<AppStockColumnSheet> {
  late Map<StockColumnId, bool> _visibilityMap;
  late FreezePaneOption _selectedFreeze;

  @override
  void initState() {
    super.initState();
    _visibilityMap = {
      for (final entry in widget.columnDefs.entries) entry.key: entry.value.isVisible,
    };
    _selectedFreeze = widget.currentFreeze;
  }

  void _applyPreset(String preset) {
    setState(() {
      if (preset == "ALL") {
        for (final k in _visibilityMap.keys) {
          _visibilityMap[k] = true;
        }
      } else if (preset == "COMPACT") {
        for (final k in _visibilityMap.keys) {
          _visibilityMap[k] = false;
        }
        for (final k in [
          StockColumnId.srNo,
          StockColumnId.systemId,
          StockColumnId.name,
          StockColumnId.packing,
          StockColumnId.currentStock,
          StockColumnId.purRate,
          StockColumnId.mrp,
          StockColumnId.actions,
        ]) {
          _visibilityMap[k] = true;
        }
      } else if (preset == "VALUATION") {
        for (final k in _visibilityMap.keys) {
          _visibilityMap[k] = false;
        }
        for (final k in [
          StockColumnId.srNo,
          StockColumnId.name,
          StockColumnId.company,
          StockColumnId.currentStock,
          StockColumnId.purRate,
          StockColumnId.mrp,
          StockColumnId.purValuation,
          StockColumnId.mrpValuation,
          StockColumnId.actions,
        ]) {
          _visibilityMap[k] = true;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: MargStockTheme.cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: const BoxDecoration(
              color: MargStockTheme.headerDark,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                const Icon(Icons.view_column_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    "Sheet Columns & Freeze Pane",
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "FREEZE LEFT COLUMNS (MOBILE SHEET)",
                  style: TextStyle(
                    color: MargStockTheme.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _freezeChip(FreezePaneOption.none, "No Freeze"),
                    _freezeChip(FreezePaneOption.idAndName, "ID + Name"),
                    _freezeChip(FreezePaneOption.idNameAndCompany, "ID + Name + Mfg"),
                    _freezeChip(FreezePaneOption.idNameAndPack, "ID + Name + Pack"),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text(
                      "VISIBLE COLUMNS",
                      style: TextStyle(
                        color: MargStockTheme.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const Spacer(),
                    _presetBtn("All", "ALL"),
                    const SizedBox(width: 6),
                    _presetBtn("Compact", "COMPACT"),
                    const SizedBox(width: 6),
                    _presetBtn("Valuation", "VALUATION"),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: MargStockTheme.border),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: widget.columnDefs.entries.map((entry) {
                final col = entry.value;
                final isChecked = _visibilityMap[entry.key] ?? true;
                final isLocked = entry.key == StockColumnId.name || entry.key == StockColumnId.actions;
                return CheckboxListTile(
                  dense: true,
                  activeColor: MargStockTheme.headerMid,
                  value: isChecked,
                  onChanged: isLocked
                      ? null
                      : (v) => setState(() => _visibilityMap[entry.key] = v ?? true),
                  title: Row(
                    children: [
                      Text(
                        col.title,
                        style: TextStyle(
                          color: isChecked ? MargStockTheme.textPrimary : MargStockTheme.textMuted,
                          fontSize: 13,
                          fontWeight: isChecked ? FontWeight.w700 : FontWeight.normal,
                        ),
                      ),
                      if (isLocked) ...[
                        const SizedBox(width: 8),
                        MargStockTheme.badge(
                          label: "REQUIRED",
                          fg: MargStockTheme.headerDark,
                          bg: MargStockTheme.accentLight,
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: MargStockTheme.canvas,
              border: Border(top: BorderSide(color: MargStockTheme.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MargStockTheme.textSecondary,
                      side: const BorderSide(color: MargStockTheme.border),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text("CANCEL", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MargStockTheme.headerDark,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text("APPLY SETTINGS", style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      final updatedDefs = Map<StockColumnId, StockColumnDef>.from(widget.columnDefs);
                      for (final entry in _visibilityMap.entries) {
                        if (updatedDefs.containsKey(entry.key)) {
                          updatedDefs[entry.key] = updatedDefs[entry.key]!.copyWith(isVisible: entry.value);
                        }
                      }
                      widget.onApply(updatedDefs, _selectedFreeze);
                      Navigator.pop(context);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _freezeChip(FreezePaneOption option, String label) {
    final isSel = _selectedFreeze == option;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSel ? Colors.white : MargStockTheme.textPrimary,
          fontSize: 11,
          fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      selected: isSel,
      selectedColor: MargStockTheme.headerMid,
      backgroundColor: MargStockTheme.canvas,
      side: BorderSide(color: isSel ? MargStockTheme.headerDark : MargStockTheme.border),
      onSelected: (_) => setState(() => _selectedFreeze = option),
    );
  }

  Widget _presetBtn(String title, String preset) {
    return InkWell(
      onTap: () => _applyPreset(preset),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: MargStockTheme.accentLight,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: MargStockTheme.headerMid.withOpacity(0.35)),
        ),
        child: Text(
          title,
          style: const TextStyle(
            color: MargStockTheme.headerDark,
            fontSize: 10.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
