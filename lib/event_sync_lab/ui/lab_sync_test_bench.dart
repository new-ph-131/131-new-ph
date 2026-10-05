// FILE: lib/event_sync_lab/ui/lab_sync_test_bench.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../pharoah_manager.dart';
import '../../web_live_sync/pharoah_web_manager.dart';
import '../../web_live_sync/weblivetoken.dart';
import '../models/lab_sync_event.dart';
import '../method/lab_event_transport.dart';
import '../logic/lab_delta_processor.dart';
import '../workflow/lab_sync_orchestrator.dart';

/// 🧪 LAB SYNC TEST BENCH: Interactive Test Studio for Plan 1 (Event-Driven 2-Way Sync)
class LabSyncTestBench extends StatefulWidget {
  final bool isWebEnvironment;
  const LabSyncTestBench({super.key, this.isWebEnvironment = false});

  @override
  State<LabSyncTestBench> createState() => _LabSyncTestBenchState();
}

class _LabSyncTestBenchState extends State<LabSyncTestBench> {
  Timer? _uiRefreshTimer;
  String currentStoreToken = "";
  bool isSimulating = false;

  @override
  void initState() {
    super.initState();
    _initLab();
    LabSyncOrchestrator.instance.onLogUpdated = () {
      if (mounted) setState(() {});
    };
    _uiRefreshTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uiRefreshTimer?.cancel();
    LabSyncOrchestrator.instance.onLogUpdated = null;
    super.dispose();
  }

  Future<void> _initLab() async {
    if (widget.isWebEnvironment) {
      try {
        final webPh = Provider.of<PharoahWebManager>(context, listen: false);
        currentStoreToken = webPh.activeStoreToken;
        LabSyncOrchestrator.instance.bindWeb(webPh);
      } catch (_) {}
    } else {
      try {
        final ph = Provider.of<PharoahManager>(context, listen: false);
        if (ph.activeCompany != null) {
          currentStoreToken = await WebLiveToken.getOrCreateToken(ph.activeCompany!.id);
          await LabSyncOrchestrator.instance.bindApp(ph);
        }
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<void> _simulateEvent({required String source, required String action, required String entityId}) async {
    setState(() => isSimulating = true);
    final event = LabSyncEvent(
      id: "sim_${DateTime.now().millisecondsSinceEpoch}",
      storeToken: currentStoreToken,
      source: source,
      action: action,
      entityId: entityId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: {"simulated": true, "sampleAmount": 1250.0},
    );

    await LabEventTransport.instance.emitSignal(event);
    setState(() => isSimulating = false);
  }

  @override
  Widget build(BuildContext context) {
    final transport = LabEventTransport.instance;
    final orchestrator = LabSyncOrchestrator.instance;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text("🧪 Event-Driven 2-Way Sync Lab (Plan 1)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: "Re-bind Listener",
            onPressed: _initLab,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 🟢 STATUS BANNER
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: transport.connectionStatus == "CONNECTED" ? Colors.tealAccent.shade400 : Colors.orangeAccent,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    transport.connectionStatus == "CONNECTED" ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded,
                    color: transport.connectionStatus == "CONNECTED" ? Colors.tealAccent : Colors.orangeAccent,
                    size: 28,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "EVENT BUS: ${transport.connectionStatus}",
                          style: TextStyle(
                            color: transport.connectionStatus == "CONNECTED" ? Colors.tealAccent : Colors.orangeAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Store Token: ${currentStoreToken.isEmpty ? 'NOT CONFIGURED' : currentStoreToken} | Role: ${widget.isWebEnvironment ? 'WEB' : 'APP'}",
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 📊 4 LIVE METRICS CARDS
            Row(
              children: [
                Expanded(child: _metricCard("ROUND-TRIP LATENCY", "${transport.lastLatencyMs} ms", Colors.cyanAccent, Icons.speed_rounded)),
                const SizedBox(width: 12),
                Expanded(child: _metricCard("SIGNALS SENT", "${transport.totalSignalsSent}", Colors.greenAccent, Icons.upload_rounded)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _metricCard("SIGNALS RECEIVED", "${transport.totalSignalsReceived}", Colors.amberAccent, Icons.download_rounded)),
                const SizedBox(width: 12),
                Expanded(child: _metricCard("DRIVE CALLS SAVED", "${transport.totalDriveCallsSaved}", Colors.purpleAccent, Icons.shield_rounded)),
              ],
            ),
            const SizedBox(height: 20),

            // 🧪 INTERACTIVE SIMULATION PANEL
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.science_rounded, color: Colors.cyanAccent, size: 20),
                      SizedBox(width: 8),
                      Text("SIMULATION CONTROLS (TEST WITHOUT AFFECTING REAL BILLS)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Yeh buttons simulate karenge ki Web ya App ne naya bill banaya ya delete kiya, taaki aap real-time me test kar sakein ki event kitni jaldi transfer hota hai aur kitni calls bachti hain.",
                    style: TextStyle(color: Colors.white60, fontSize: 11, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        onPressed: isSimulating ? null : () => _simulateEvent(source: 'WEB', action: 'SALE_SAVED', entityId: 'TEST-BILL-WEB-001'),
                        icon: const Icon(Icons.language_rounded, size: 16),
                        label: const Text("Simulate Web Created Bill", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        onPressed: isSimulating ? null : () => _simulateEvent(source: 'APP', action: 'SALE_SAVED', entityId: 'TEST-BILL-APP-002'),
                        icon: const Icon(Icons.phone_android_rounded, size: 16),
                        label: const Text("Simulate App Created Bill", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        onPressed: isSimulating ? null : () => _simulateEvent(source: widget.isWebEnvironment ? 'WEB' : 'APP', action: 'SALE_DELETED', entityId: 'TEST-DEL-999'),
                        icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                        label: const Text("Simulate Delete Action", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 📝 REAL-TIME AUDIT LOG TERMINAL
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF020617),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.terminal_rounded, color: Colors.greenAccent, size: 18),
                          SizedBox(width: 8),
                          Text("REAL-TIME EVENT LOG TERMINAL", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)),
                        ],
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: Colors.white54),
                        onPressed: () {
                          orchestrator.eventLog.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear_all_rounded, size: 16),
                        label: const Text("Clear", style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 6),
                  orchestrator.eventLog.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(
                            child: Text("No events recorded yet. Event Bus is idle waiting for mutations.", style: TextStyle(color: Colors.white38, fontSize: 11, fontStyle: FontStyle.italic)),
                          ),
                        )
                      : Container(
                          constraints: const BoxConstraints(maxHeight: 250),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: orchestrator.eventLog.length,
                            itemBuilder: (context, i) {
                              final line = orchestrator.eventLog[i];
                              Color textColor = Colors.white70;
                              if (line.contains("✅") || line.contains("🟢")) textColor = Colors.greenAccent;
                              if (line.contains("📥") || line.contains("⚡")) textColor = Colors.cyanAccent;
                              if (line.contains("❌") || line.contains("⚠")) textColor = Colors.redAccent;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Text(line, style: TextStyle(color: textColor, fontFamily: 'monospace', fontSize: 11)),
                              );
                            },
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricCard(String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(child: Text(title, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5), overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
