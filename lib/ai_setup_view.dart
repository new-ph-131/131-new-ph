import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiSetupView extends StatefulWidget {
  const AiSetupView({super.key});

  @override
  State<AiSetupView> createState() => _AiSetupViewState();
}

class _AiSetupViewState extends State<AiSetupView> {
  final geminiKeyC = TextEditingController();
  bool autoOffline = true;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedKeys();
  }

  // Pehle se save ki hui keys load karna
  Future<void> _loadSavedKeys() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      geminiKeyC.text = prefs.getString('geminiKey') ?? "";
      autoOffline = prefs.getBool('autoOffline') ?? true;
      isLoading = false;
    });
  }

  // Keys save karne ka logic
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('geminiKey', geminiKeyC.text.trim());
    await prefs.setBool('autoOffline', autoOffline);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ AI Configuration Saved Successfully!"), backgroundColor: Colors.green),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("AI Configuration"),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
      ),
      body: isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderIcon(),
                const SizedBox(height: 25),
                
                // --- SECTION: GOOGLE GEMINI (Main AI) ---
                _buildSectionTitle("SMART CLOUD AI (RECOMMENDED)"),
                _buildGeminiCard(),

                const SizedBox(height: 25),

                // --- SECTION: HYBRID SETTINGS ---
                _buildSectionTitle("HYBRID & OFFLINE BEHAVIOR"),
                _buildHybridSettings(),

                const SizedBox(height: 30),

                // --- SAVE BUTTON ---
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo.shade900,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                    ),
                    onPressed: _saveSettings,
                    child: const Text("ACTIVATE SMART VISION", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildHeaderIcon() {
    return Center(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(Icons.psychology_rounded, size: 60, color: Colors.indigo.shade900),
          ),
          const SizedBox(height: 10),
          const Text("Pharoah AI Brain Settings", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Text("Manage your API keys and extraction logic", style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 5),
      child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1)),
    );
  }

  Widget _buildGeminiCard() {
    return Card(
      elevation: 0,
      // FIXED: 'border' parameter ko 'side' se replace kiya gaya hai
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20), 
        side: BorderSide(color: Colors.indigo.withOpacity(0.1)) 
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: Colors.blue),
                const SizedBox(width: 10),
                const Text("Google Gemini API", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                TextButton(onPressed: () {}, child: const Text("Get Free Key", style: TextStyle(fontSize: 11))),
              ],
            ),
            const SizedBox(height: 15),
            TextField(
              controller: geminiKeyC,
              decoration: const InputDecoration(
                labelText: "Paste Gemini API Key Here",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key_rounded),
                hintText: "AIzaSy..."
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "Note: Gemini enables 99% accurate table and handwriting extraction.",
              style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildHybridSettings() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text("Smart Auto-Fallback", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: const Text("Switch to Offline AI if internet is disconnected.", style: TextStyle(fontSize: 11)),
            value: autoOffline,
            onChanged: (v) => setState(() => autoOffline = v),
            activeColor: Colors.green,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.speed_rounded, color: Colors.orange),
            title: const Text("Processing Speed", style: TextStyle(fontSize: 14)),
            trailing: const Text("Balanced", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo)),
            onTap: () {},
          )
        ],
      ),
    );
  }
}
