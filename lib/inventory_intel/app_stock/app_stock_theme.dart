// FILE: lib/inventory_intel/app_stock/app_stock_theme.dart
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';

/// Classic Marg ERP Pharma Theme Tokens for Mobile Stock Analytics
class MargStockTheme {
  // Primary Marg Petrol / Deep Teal Palette
  static const Color headerDark = Color(0xFF004D40);
  static const Color headerMid = Color(0xFF00695C);
  static const Color accentTeal = Color(0xFF00796B);
  static const Color accentLight = Color(0xFFE0F2F1);

  // Canvas & Crisp Ledger Surfaces
  static const Color canvas = Color(0xFFF3F7F6);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color zebraRow = Color(0xFFEDF5F3);
  static const Color headerBand = Color(0xFFE6EFEA);
  static const Color border = Color(0xFFCBD8D5);
  static const Color divider = Color(0xFFE2ECE9);

  // Marg Signature Gold / Amber Highlight
  static const Color goldBg = Color(0xFFFEF3C7);
  static const Color goldBorder = Color(0xFFD97706);
  static const Color goldText = Color(0xFF92400E);

  // Semantic Status Colors
  static const Color stockOk = Color(0xFF047857);
  static const Color stockOkBg = Color(0xFFD1FAE5);
  static const Color stockLow = Color(0xFFB45309);
  static const Color stockLowBg = Color(0xFFFEF3C7);
  static const Color stockAlert = Color(0xFFDC2626);
  static const Color stockAlertBg = Color(0xFFFEE2E2);

  // Typography & Code Colors
  static const Color textPrimary = Color(0xFF0F2925);
  static const Color textSecondary = Color(0xFF3E5B56);
  static const Color textMuted = Color(0xFF647D78);
  static const Color codeBlue = Color(0xFF0369A1);
  static const Color codeBlueBg = Color(0xFFE0F2FE);
  static const Color valuationPurple = Color(0xFF5B21B6);

  static const TextStyle tabularNum = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
    fontWeight: FontWeight.w700,
    color: textPrimary,
  );

  static Widget badge({
    required String label,
    required Color fg,
    required Color bg,
    Color? borderColor,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: borderColor != null ? Border.all(color: borderColor, width: 0.7) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
