// FILE: lib/administration/web_qr_scanner_view.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pharoah_manager.dart';
import '../realtime_signaling/coordinators/app_realtime_coordinator.dart';
import '../sync_bridge/engines/app_auto_sync_daemon.dart';
import '../web_live_sync/app_sync_engine.dart';
import '../web_live_sync/qr_login_service.dart';
import '../web_live_sync/weblivetoken.dart';

class WebQrScannerView extends StatefulWidget {
  const WebQrScannerView({super.key});

  @override
  State<WebQrScannerView> createState() => _WebQrScannerViewState();
}

class _WebQrScannerViewState extends State<WebQrScannerView> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _checkingPermission = true;
  bool _hasPermission = false;
  bool _permanentlyDenied = false;
  bool _isHandlingScan = false;
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    _ensureCameraPermission();
  }

  Future<void> _ensureCameraPermission() async {
    setState(() => _checkingPermission = true);
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    if (!mounted) return;
    setState(() {
      _checkingPermission = false;
      _hasPermission = status.isGranted;
      _permanentlyDenied = status.isPermanentlyDenied;
    });
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isHandlingScan) return;
    String? matchedRaw;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw != null && raw.trim().isNotEmpty) {
        matchedRaw = raw.trim();
        break;
      }
    }
    if (matchedRaw == null) return;

    final parsed = QrLoginService.parseQrPayload(matchedRaw);
    if (parsed == null) {
      _isHandlingScan = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Not a valid Pharoah Web Workstation QR code."),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      await Future.delayed(const Duration(milliseconds: 1600));
      _isHandlingScan = false;
      return;
    }

    _isHandlingScan = true;
    await _scannerController.stop();
    if (!mounted) return;

    final ph = Provider.of<PharoahManager>(context, listen: false);
    if (ph.activeCompany == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select/login to a company before linking Web."),
          backgroundColor: Colors.redAccent,
        ),
      );
      Navigator.pop(context, false);
      return;
    }

    final storeToken = await WebLiveToken.getOrCreateToken(ph.activeCompany!.id);
    if (!mounted) return;

    final bool? confirmed = await _showConfirmBottomSheet(
      ph: ph,
      storeToken: storeToken,
      target: parsed,
    );

    if (!mounted) return;
    if (confirmed == true) {
      Navigator.pop(context, true);
    } else {
      _isHandlingScan = false;
      await _scannerController.start();
    }
  }

  Future<bool?> _showConfirmBottomSheet({
    required PharoahManager ph,
    required String storeToken,
    required QrScannedTarget target,
  }) {
    final comp = ph.activeCompany!;
    final adminUser = comp.adminUser.trim().isNotEmpty ? comp.adminUser.trim() : "admin";
    final adminPass = comp.password;
    bool isApproving = false;
    String sheetStatus = "";

    return showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> approve() async {
              setSheetState(() {
                isApproving = true;
                sheetStatus = "Preparing cloud session...";
              });

              final prefs = await SharedPreferences.getInstance();
              final bool pausedByUser = prefs.getBool('is_cloud_sync_paused_by_user') ?? false;
              final String lastSyncTime = await AppSyncEngine.getLastSyncFormattedTime();

              if (pausedByUser) {
                await prefs.setBool('is_live_web_active', true);
                await prefs.setBool('is_cloud_sync_paused_by_user', false);
                AppRealtimeCoordinator.instance.start(ph);
                AppAutoSyncDaemon.instance.startHeartbeat(ph);
              }

              if (pausedByUser || lastSyncTime == "Never") {
                setSheetState(() => sheetStatus = "Syncing store database to cloud...");
                final pushed = await AppSyncEngine.pushStoreData(ph);
                if (!pushed && ctx.mounted) {
                  setSheetState(() {
                    isApproving = false;
                    sheetStatus = "Cloud sync failed. Check internet and try again.";
                  });
                  return;
                }
              }

              setSheetState(() => sheetStatus = "Authorizing Web Workstation...");
              final res = await QrLoginService.approveSession(
                sid: target.sid,
                otp: target.otp,
                storeToken: storeToken,
                username: adminUser,
                password: adminPass,
                companyName: comp.name,
              );

              if (!ctx.mounted) return;
              if (res.success) {
                Navigator.pop(ctx, true);
              } else {
                setSheetState(() {
                  isApproving = false;
                  sheetStatus = res.message.isNotEmpty
                      ? res.message
                      : "Could not authorize QR login.";
                });
              }
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      color: Color(0x1F22D3EE),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.desktop_windows_rounded, color: Colors.cyanAccent, size: 32),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    "Approve Web Workstation Login?",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Browser par bina password type kiye seedhe aapka store khul jayega.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _detailRow("Company", comp.name),
                        const SizedBox(height: 6),
                        _detailRow("Store Key", storeToken),
                        const SizedBox(height: 6),
                        _detailRow("Username", adminUser),
                        const SizedBox(height: 6),
                        _detailRow("Financial Year", ph.currentFY),
                      ],
                    ),
                  ),
                  if (sheetStatus.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      sheetStatus,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isApproving ? Colors.cyanAccent : Colors.redAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: isApproving ? null : () => Navigator.pop(ctx, false),
                          child: const Text("CANCEL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyanAccent,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          onPressed: isApproving ? null : approve,
                          icon: isApproving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                )
                              : const Icon(Icons.verified_user_rounded, size: 18),
                          label: Text(
                            isApproving ? "APPROVING..." : "APPROVE & LOGIN",
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        Flexible(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        title: const Text(
          "Scan Web Workstation QR",
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        actions: [
          if (_hasPermission)
            IconButton(
              icon: Icon(_torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded),
              onPressed: () async {
                await _scannerController.toggleTorch();
                if (mounted) setState(() => _torchOn = !_torchOn);
              },
            ),
        ],
      ),
      body: _checkingPermission
          ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
          : !_hasPermission
              ? _buildPermissionDenied()
              : Stack(
                  children: [
                    MobileScanner(
                      controller: _scannerController,
                      onDetect: _onDetect,
                    ),
                    Center(
                      child: Container(
                        width: 260,
                        height: 260,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.cyanAccent, width: 3),
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 12),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 42,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xCC0F172A),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: const Text(
                          "Web Workstation login screen par dikh raha QR Code frame ke andar rakhein.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_rounded, color: Colors.orangeAccent, size: 54),
            const SizedBox(height: 16),
            const Text(
              "Camera Permission Required",
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Web QR code scan karne ke liye app ko camera access allow karein.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                if (_permanentlyDenied) {
                  openAppSettings();
                } else {
                  _ensureCameraPermission();
                }
              },
              icon: const Icon(Icons.settings_rounded),
              label: Text(
                _permanentlyDenied ? "OPEN APP SETTINGS" : "ALLOW CAMERA",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
