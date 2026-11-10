// FILE: lib/web_live_sync/sub_views/web_mail/widgets/web_smart_mail_button.dart
// Revision: #PH-REV-798 (ENTERPRISE-WEB-SMART-MAIL-BUTTON)
import 'package:flutter/material.dart';
import '../../../pharoah_web_manager.dart';
import '../../../web_models.dart';
import '../services/web_mail_router_service.dart';

/// 📬 WebSmartMailButton
/// Reusable UI button that automatically hides when Mail is OFF (`!webPh.appConfig.isMailActive`),
/// shows `@` (`Icons.alternate_email`) when sending to Party/Customer/Supplier,
/// and shows Forward-Inbox (`Icons.forward_to_inbox_rounded`) when CA Audit Redirection is ON (`isAuditMode`).
class WebSmartMailButton extends StatelessWidget {
  final PharoahWebManager webPh;
  final dynamic doc;
  final Party party;
  final String type;
  final Color normalColor;
  final String normalTooltip;
  final bool isPillStyle;
  final DateTime? fromDate;
  final DateTime? toDate;

  const WebSmartMailButton({
    super.key,
    required this.webPh,
    required this.doc,
    required this.party,
    required this.type,
    this.normalColor = const Color(0xFF38BDF8),
    this.normalTooltip = "Send to Party Mail",
    this.isPillStyle = false,
    this.fromDate,
    this.toDate,
  });

  @override
  Widget build(BuildContext context) {
    final config = webPh.appConfig;
    if (!config.isMailActive) {
      return const SizedBox.shrink();
    }

    final bool isCaMode = config.isAuditMode;
    final IconData iconData = isCaMode ? Icons.forward_to_inbox_rounded : Icons.alternate_email_rounded;
    final Color activeColor = isCaMode ? const Color(0xFFFB923C) : normalColor;
    final String tooltipText = isCaMode
        ? "Forward to CA (Auditor${config.caMailID.isNotEmpty ? ': ${config.caMailID}' : ''})"
        : normalTooltip;

    if (isPillStyle) {
      return Tooltip(
        message: tooltipText,
        child: InkWell(
          onTap: () => WebMailRouterService.emailDocument(
            context: context,
            doc: doc,
            party: party,
            webPh: webPh,
            type: type,
            fromDate: fromDate,
            toDate: toDate,
          ),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: activeColor.withOpacity(0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: activeColor.withOpacity(0.45)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(iconData, color: activeColor, size: 14),
                const SizedBox(width: 5),
                Text(
                  isCaMode ? "CA MAIL" : "MAIL",
                  style: TextStyle(
                    color: activeColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return IconButton(
      icon: Icon(iconData, color: activeColor, size: 19),
      tooltip: tooltipText,
      onPressed: () => WebMailRouterService.emailDocument(
        context: context,
        doc: doc,
        party: party,
        webPh: webPh,
        type: type,
        fromDate: fromDate,
        toDate: toDate,
      ),
    );
  }
}
