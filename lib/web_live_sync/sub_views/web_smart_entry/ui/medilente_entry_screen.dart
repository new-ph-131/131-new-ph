import 'package:flutter/material.dart';
import '../medilente/models/medilente_bill_model.dart';
import '../medilente/ui/medilente_file_picker_view.dart';
import '../medilente/ui/medilente_review_screen.dart';

class MedilenteEntryScreen extends StatefulWidget {
  final VoidCallback onBack;

  const MedilenteEntryScreen({super.key, required this.onBack});

  @override
  State<MedilenteEntryScreen> createState() => _MedilenteEntryScreenState();
}

class _MedilenteEntryScreenState extends State<MedilenteEntryScreen> {
  MedilenteBill? loadedBill;

  @override
  Widget build(BuildContext context) {
    if (loadedBill != null) {
      return MedilenteReviewScreen(
        bill: loadedBill!,
        onBack: () => setState(() => loadedBill = null),
      );
    }

    return MedilenteFilePickerView(
      onBack: widget.onBack,
      onBillLoaded: (bill) {
        setState(() => loadedBill = bill);
      },
    );
  }
}
