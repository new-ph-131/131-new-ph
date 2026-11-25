// FILE: lib/web_live_sync/sub_views/web_returns/debit_note/ui/debit_note_magic_history_modal.dart
// ignore_for_file: prefer_const_constructors, unnecessary_const

import 'package:flutter/material.dart';
import '../../../../web_models.dart';
import '../../../../pharoah_web_manager.dart';
import '../../../../../logic/return_history_engine.dart';
import '../../shared/web_return_batch_history_dialog.dart';

class DebitNoteMagicHistoryModal extends StatelessWidget {
  final Medicine medicine;
  final Party supplier;
  final PharoahWebManager webPh;
  final List<dynamic> currentCartItems;
  final String? excludeNoteId;
  final Function(Map<String, dynamic>? selectedHistory) onSelect;
  final Function(List<ReturnAllocationItem> allocations, bool hasOverReturn)? onAutoSplit;

  const DebitNoteMagicHistoryModal({
    super.key,
    required this.medicine,
    required this.supplier,
    required this.webPh,
    this.currentCartItems = const [],
    this.excludeNoteId,
    required this.onSelect,
    this.onAutoSplit,
  });

  @override
  Widget build(BuildContext context) {
    return WebReturnBatchHistoryDialog(
      isSale: false,
      medicine: medicine,
      party: supplier,
      webPh: webPh,
      currentCartItems: currentCartItems,
      excludeNoteId: excludeNoteId,
      onSelect: onSelect,
      onAutoSplit: onAutoSplit,
    );
  }
}
