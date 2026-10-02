import 'package:flutter/material.dart';
import '../amazon/models/amazon_bill_model.dart';
import '../amazon/ui/amazon_file_picker_view.dart';
import '../amazon/ui/amazon_review_screen.dart';

class AmazonEntryScreen extends StatefulWidget {
  final VoidCallback onBack;

  const AmazonEntryScreen({super.key, required this.onBack});

  @override
  State<AmazonEntryScreen> createState() => _AmazonEntryScreenState();
}

class _AmazonEntryScreenState extends State<AmazonEntryScreen> {
  AmazonBill? loadedBill;

  @override
  Widget build(BuildContext context) {
    if (loadedBill != null) {
      return AmazonReviewScreen(
        bill: loadedBill!,
        onBack: () => setState(() => loadedBill = null),
      );
    }

    return AmazonFilePickerView(
      onBack: widget.onBack,
      onBillLoaded: (bill) {
        setState(() => loadedBill = bill);
      },
    );
  }
}
