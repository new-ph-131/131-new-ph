// FILE: lib/web_live_sync/sub_views/web_billing/quick_add_party_modal.dart

import 'package:flutter/material.dart';
import '../../web_models.dart';
import '../../pharoah_web_manager.dart';

class QuickAddPartyModal extends StatefulWidget {
  final PharoahWebManager webPh;
  final Function(Party newParty) onPartyCreated;
  final Map<String, dynamic>? preFillData;

  const QuickAddPartyModal({
    super.key,
    required this.webPh,
    required this.onPartyCreated,
    this.preFillData,
  });

  @override
  State<QuickAddPartyModal> createState() => _QuickAddPartyModalState();
}

class _QuickAddPartyModalState extends State<QuickAddPartyModal> {
  final nameC = TextEditingController();
  final phoneC = TextEditingController();
  final emailC = TextEditingController();
  final addressC = TextEditingController();
  final cityC = TextEditingController();
  final gstC = TextEditingController();
  final panC = TextEditingController();
  final dlC = TextEditingController();
  final dlExpC = TextEditingController();
  final opBalC = TextEditingController(text: "0.0");
  final creditLimitC = TextEditingController(text: "0.0");
  final creditDaysC = TextEditingController(text: "30");

  String selectedGroup = "Sundry Debtors";
  String selectedState = "Rajasthan";
  String selectedPriceLevel = "A";
  String selectedSeriesId = "";

  final List<String> accountGroups = [
    "Sundry Debtors",
    "Sundry Creditors",
    "Bank Accounts",
    "Cash in Hand",
    "Expenses",
  ];

  final List<String> states = [
    "Andhra Pradesh", "Assam", "Bihar", "Chhattisgarh", "Goa", "Gujarat", "Haryana",
    "Himachal Pradesh", "Jharkhand", "Karnataka", "Kerala", "Madhya Pradesh",
    "Maharashtra", "Manipur", "Meghalaya", "Mizoram", "Nagaland", "Odisha",
    "Punjab", "Rajasthan", "Sikkim", "Tamil Nadu", "Telangana", "Tripura",
    "Uttar Pradesh", "Uttarakhand", "West Bengal", "Delhi",
  ];

  @override
  void initState() {
    super.initState();
    if (widget.preFillData != null) {
      final pf = widget.preFillData!;
      nameC.text = (pf['name'] ?? '').toString();
      phoneC.text = (pf['phone'] ?? '').toString();
      emailC.text = (pf['email'] ?? '').toString();
      addressC.text = (pf['address'] ?? '').toString();
      cityC.text = (pf['city'] ?? '').toString();
      gstC.text = (pf['gst'] ?? '').toString();
      panC.text = (pf['pan'] ?? '').toString();
      dlC.text = (pf['dl'] ?? '').toString();
      selectedGroup = (pf['group'] ?? 'Sundry Debtors').toString();
      selectedState = (pf['state'] ?? 'Rajasthan').toString();
    }

    gstC.addListener(() {
      if (gstC.text.length >= 12) {
        String extPan = gstC.text.substring(2, 12).toUpperCase();
        if (panC.text != extPan) {
          panC.text = extPan;
        }
      }
    });
  }

  @override
  void dispose() {
    nameC.dispose();
    phoneC.dispose();
    emailC.dispose();
    addressC.dispose();
    cityC.dispose();
    gstC.dispose();
    panC.dispose();
    dlC.dispose();
    dlExpC.dispose();
    opBalC.dispose();
    creditLimitC.dispose();
    creditDaysC.dispose();
    super.dispose();
  }

  void _saveParty() {
    if (nameC.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Firm / Customer Name is required!"), backgroundColor: Colors.orange),
      );
      return;
    }

    final newParty = Party(
      id: 'PARTY-WEB-${DateTime.now().millisecondsSinceEpoch}',
      name: nameC.text.trim().toUpperCase(),
      group: selectedGroup,
      phone: phoneC.text.trim(),
      email: emailC.text.trim().toLowerCase(),
      address: addressC.text.trim(),
      city: cityC.text.trim().toUpperCase(),
      state: selectedState,
      gst: gstC.text.trim().toUpperCase().isEmpty ? 'N/A' : gstC.text.trim().toUpperCase(),
      pan: panC.text.trim().toUpperCase(),
      dl: dlC.text.trim().toUpperCase().isEmpty ? 'N/A' : dlC.text.trim().toUpperCase(),
      dlExp: dlExpC.text.trim(),
      opBal: double.tryParse(opBalC.text) ?? 0.0,
      creditLimit: double.tryParse(creditLimitC.text) ?? 0.0,
      creditDays: int.tryParse(creditDaysC.text) ?? 30,
      priceLevel: selectedPriceLevel,
      defaultSeriesId: selectedSeriesId,
    );

    widget.webPh.addParty(newParty);
    Navigator.pop(context);
    widget.onPartyCreated(newParty);
  }

  @override
  Widget build(BuildContext context) {
    final activeSeries = widget.webPh.numberingSeries.where((s) => s.type == "SALE" && s.isActive).toList();
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth > 640 ? 600.0 : (screenWidth * 0.94);

    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Colors.white12),
      ),
      titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: const BoxDecoration(
              color: Color(0x332563EB),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF38BDF8), size: 18),
          ),
          const SizedBox(width: 10),
          const Text(
            "CREATE CUSTOMER / SUPPLIER",
            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ipadInput("FIRM / PARTY NAME *", nameC, Icons.business, isCaps: true),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ipadDropdown(
                      "ACCOUNT GROUP *",
                      accountGroups.contains(selectedGroup) ? selectedGroup : "Sundry Debtors",
                      accountGroups.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                      (v) => setState(() => selectedGroup = v!),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ipadDropdown(
                      "STATE (FOR GST)",
                      states.contains(selectedState) ? selectedState : "Rajasthan",
                      states.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      (v) => setState(() => selectedState = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _ipadInput("MOBILE NUMBER", phoneC, Icons.phone, isPhone: true)),
                  const SizedBox(width: 10),
                  Expanded(child: _ipadInput("EMAIL ID", emailC, Icons.email)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _ipadInput("GSTIN NUMBER", gstC, Icons.receipt_long, isCaps: true)),
                  const SizedBox(width: 10),
                  Expanded(child: _ipadInput("PAN (AUTO)", panC, Icons.badge_outlined, isCaps: true)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _ipadInput("DRUG LICENSE (DL)", dlC, Icons.medical_services, isCaps: true)),
                  const SizedBox(width: 10),
                  Expanded(child: _ipadInput("DL EXPIRY", dlExpC, Icons.event_busy, isCaps: true)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _ipadInput("CITY", cityC, Icons.location_city, isCaps: true)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ipadDropdown(
                      "PRICING LEVEL",
                      selectedPriceLevel,
                      ["A", "B", "C"].map((p) => DropdownMenuItem(value: p, child: Text("Rate $p"))).toList(),
                      (v) => setState(() => selectedPriceLevel = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ipadInput("OFFICE / SHOP ADDRESS", addressC, Icons.location_on),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _ipadInput("OPENING BAL ₹", opBalC, Icons.account_balance_wallet, isNum: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _ipadInput("LIMIT ₹", creditLimitC, Icons.speed, isNum: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _ipadInput("DAYS", creditDaysC, Icons.timer, isNum: true)),
                ],
              ),
              if (activeSeries.isNotEmpty) ...[
                const SizedBox(height: 12),
                _ipadDropdown(
                  "DEFAULT BILLING SERIES PREFERENCE",
                  selectedSeriesId.isEmpty ? null : selectedSeriesId,
                  activeSeries.map((s) => DropdownMenuItem(value: s.id, child: Text("${s.name} (${s.prefix})"))).toList(),
                  (v) => setState(() => selectedSeriesId = v ?? ""),
                  hint: "Select Default Series (Optional)",
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _saveParty,
          child: const Text("SAVE PARTY", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
        ),
      ],
    );
  }

  Widget _ipadInput(
    String label,
    TextEditingController ctrl,
    IconData icon, {
    bool isNum = false,
    bool isPhone = false,
    bool isCaps = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 8.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        const SizedBox(height: 4),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF38BDF8), size: 15),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: ctrl,
                  keyboardType: isPhone ? TextInputType.phone : (isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text),
                  textCapitalization: isCaps ? TextCapitalization.characters : TextCapitalization.none,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ipadDropdown<T>(
    String label,
    T? value,
    List<DropdownMenuItem<T>> items,
    ValueChanged<T?> onChanged, {
    String hint = "",
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 8.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        const SizedBox(height: 4),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF1E293B),
              style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
              items: items,
              onChanged: onChanged,
              hint: hint.isNotEmpty ? Text(hint, style: const TextStyle(color: Colors.white38, fontSize: 10.5)) : null,
            ),
          ),
        ),
      ],
    );
  }
}
