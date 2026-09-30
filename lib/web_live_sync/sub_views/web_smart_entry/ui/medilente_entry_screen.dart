import 'package:flutter/material.dart';
import '../medilente/ui/medilente_file_picker_view.dart';

class MedilenteEntryScreen extends StatelessWidget {
  final VoidCallback onBack;

  const MedilenteEntryScreen({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return MedilenteFilePickerView(onBack: onBack);
  }
}
