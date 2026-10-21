// FILE: lib/web_live_sync/sub_views/web_stock/components/stock_column_config_dialog.dart

import 'package:flutter/material.dart';
import '../models/stock_column_model.dart';

class StockColumnConfigDialog extends StatefulWidget {
  final Map<StockColumnId, StockColumnDef> columnDefs;
  final FreezePaneOption currentFreeze;
  final Function(Map<StockColumnId, StockColumnDef> newDefs, FreezePaneOption newFreeze) onApply;

  const StockColumnConfigDialog({
    super.key,
    required this.columnDefs,
    required this.currentFreeze,
    required this.onApply,
  });

  @override
  State<StockColumnConfigDialog> createState() => _StockColumnConfigDialogState();
}

class _StockColumnConfigDialogState extends State<StockColumnConfigDialog> {
  late Map<StockColumnId, bool> _visibilityMap;
  late FreezePaneOption _selectedFreeze;

  @override
  void initState() {
    super.initState();
    _visibilityMap = {
      for (var entry in widget.columnDefs.entries)
        entry.key: entry.value.isVisible
    };
    _selectedFreeze = widget.currentFreeze;
  }

  void _applyPreset(String preset) {
    setState(() {
      if (preset == "ALL") {
        for (var k in _visibilityMap.keys) {
          _visibilityMap[k] = true;
        }
      } else if (preset == "COMPACT") {
        for (var k in _visibilityMap.keys) {
          _visibilityMap[k] = false;
        }
        _visibilityMap[StockColumnId.srNo] = true;
        _visibilityMap[StockColumnId.systemId] = true;
        _visibilityMap[StockColumnId.name] = true;
        _visibilityMap[StockColumnId.packing] = true;
        _visibilityMap[StockColumnId.company] = true;
        _visibilityMap[StockColumnId.currentStock] = true;
        _visibilityMap[StockColumnId.purRate] = true;
        _visibilityMap[StockColumnId.mrp] = true;
        _visibilityMap[StockColumnId.actions] = true;
      } else if (preset == "VALUATION") {
        for (var k in _visibilityMap.keys) {
          _visibilityMap[k] = true;
        }
        _visibilityMap[StockColumnId.rackNo] = false;
        _visibilityMap[StockColumnId.drugForm] = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.white12),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.view_column_rounded, color: Color(0xFFA78BFA), size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "CUSTOMIZE COLUMNS & FREEZE PANES",
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                SizedBox(height: 2),
                Text(
                  "Excel Spreadsheet View Configurations",
                  style: TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
          ),
        ],
      ),
      content: SizedBox(
        width: 680,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🧊 FREEZE PANES CONFIGURATION SECTION
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.ac_unit_rounded, color: Color(0xFF38BDF8), size: 16),
                      SizedBox(width: 8),
                      Text(
                        "FREEZE COLUMNS (STICKY PANE)",
                        style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      Spacer(),
                      Text(
                        "Locks left columns while scrolling horizontally",
                        style: TextStyle(color: Colors.white38, fontSize: 9.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _freezeChip(FreezePaneOption.none, "No Freeze"),
                      _freezeChip(FreezePaneOption.idAndName, "Freeze ID + Name (Default)"),
                      _freezeChip(FreezePaneOption.idNameAndCompany, "Freeze ID + Name + Company"),
                      _freezeChip(FreezePaneOption.idNameAndPack, "Freeze ID + Name + Packing"),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 👁️ COLUMN VISIBILITY PRESETS
            Row(
              children: [
                const Text(
                  "VISIBLE COLUMNS (SHOW / HIDE)",
                  style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                _presetButton("Show All", "ALL"),
                const SizedBox(width: 6),
                _presetButton("Standard / Compact", "COMPACT"),
                const SizedBox(width: 6),
                _presetButton("Valuation Focus", "VALUATION"),
              ],
            ),
            const SizedBox(height: 8),

            // COLUMN CHECKBOX LIST
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  children: widget.columnDefs.entries.map((entry) {
                    final col = entry.value;
                    final isChecked = _visibilityMap[entry.key] ?? true;
                    final isLocked = entry.key == StockColumnId.name || entry.key == StockColumnId.actions;

                    return CheckboxListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      activeColor: const Color(0xFF7C3AED),
                      title: Row(
                        children: [
                          Text(
                            col.title,
                            style: TextStyle(
                              color: isChecked ? Colors.white : Colors.white38,
                              fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
                              fontSize: 12,
                            ),
                          ),
                          if (isLocked) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text("Required", style: TextStyle(color: Colors.white38, fontSize: 8.5)),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        col.isNumeric ? "Numeric alignment • ${col.width.toInt()}px" : "Text alignment • ${col.width.toInt()}px",
                        style: const TextStyle(color: Colors.white38, fontSize: 9.5),
                      ),
                      value: isChecked,
                      onChanged: isLocked
                          ? null
                          : (val) {
                              setState(() {
                                _visibilityMap[entry.key] = val ?? true;
                              });
                            },
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("CANCEL", style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7C3AED),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          icon: const Icon(Icons.check_rounded, size: 16),
          label: const Text("APPLY VIEW SETTINGS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          onPressed: () {
            final updatedDefs = Map<StockColumnId, StockColumnDef>.from(widget.columnDefs);
            for (var entry in _visibilityMap.entries) {
              if (updatedDefs.containsKey(entry.key)) {
                updatedDefs[entry.key] = updatedDefs[entry.key]!.copyWith(isVisible: entry.value);
              }
            }
            widget.onApply(updatedDefs, _selectedFreeze);
            Navigator.pop(context);
          },
        ),
      ],
    );
  }

  Widget _freezeChip(FreezePaneOption option, String label) {
    final isSelected = _selectedFreeze == option;
    return ChoiceChip(
      label: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 10, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      selectedColor: const Color(0xFF0284C7),
      backgroundColor: const Color(0xFF1E293B),
      side: BorderSide(color: isSelected ? const Color(0xFF38BDF8) : Colors.white10),
      onSelected: (_) {
        setState(() {
          _selectedFreeze = option;
        });
      },
    );
  }

  Widget _presetButton(String title, String preset) {
    return InkWell(
      onTap: () => _applyPreset(preset),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(title, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
