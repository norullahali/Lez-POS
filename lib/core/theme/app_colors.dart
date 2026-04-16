// lib/core/theme/app_colors.dart
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary - Deep Blue
  static const Color primary = Color(0xFF1A237E);
  static const Color primaryLight = Color(0xFF3949AB);
  static const Color primaryDark = Color(0xFF0D1642);
  static const Color primarySurface = Color(0xFFE8EAF6);

  // Accent - Vivid Orange
  static const Color accent = Color(0xFFFF6F00);
  static const Color accentLight = Color(0xFFFFA726);
  static const Color accentDark = Color(0xFFE65100);

  // Semantic Colors
  static const Color success = Color(0xFF2E7D32);
  static const Color successLight = Color(0xFFE8F5E9);
  static const Color warning = Color(0xFFF57F17);
  static const Color warningLight = Color(0xFFFFF8E1);
  static const Color error = Color(0xFFC62828);
  static const Color errorLight = Color(0xFFFFEBEE);
  static const Color info = Color(0xFF01579B);
  static const Color infoLight = Color(0xFFE1F5FE);

  // Neutral
  static const Color background = Color(0xFFF5F6FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF0F2F8);
  static const Color border = Color(0xFFE0E3EF);
  static const Color divider = Color(0xFFECEEF5);

  // Input specific
  static const Color inputFill = Color(0xFFFFFFFF);
  static const Color inputBorder = Color(0xFFD1D5DB);

  // Text
  static const Color textPrimary = Color(0xFF1A1C2E);
  static const Color textSecondary = Color(0xFF5C6080);
  static const Color textHint = Color(0xFF9EA3C0);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textOnAccent = Color(0xFFFFFFFF);
  static const Color text = textPrimary;
  static const Color textVariant = textSecondary;
  static const Color card = surface;

  // POS specific
  static const Color posBackground = Color(0xFF0F1535);
  static const Color posPanel = Color(0xFF1A2040);
  static const Color posPanelLight = Color(0xFF252B50);
  static const Color posProductCard = Color(0xFF1E2748);
  static const Color posCartBg = Color(0xFF12193A);
  static const Color posHighlight = Color(0xFF2D3A6B);

  // Category colors for product categories
  static const List<Color> categoryColors = [
    Color(0xFF1565C0),
    Color(0xFF6A1B9A),
    Color(0xFF00838F),
    Color(0xFF2E7D32),
    Color(0xFFF57F17),
    Color(0xFFC62828),
    Color(0xFF4527A0),
    Color(0xFF00695C),
    Color(0xFFAD1457),
    Color(0xFF37474F),
  ];
}
