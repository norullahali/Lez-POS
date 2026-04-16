// lib/core/constants/app_constants.dart
class AppConstants {
  AppConstants._();

  static const String appName = 'Lez POS';
  static const String appVersion = '1.0.0';
  static const String dbFileName = 'lez_pos.db';
  static const int dbVersion = 1;

  // Default settings
  static const String defaultCurrency = 'IQD';
  static const String defaultCurrencySymbol = 'د.ع';
  static const int lowStockThreshold = 5;
  static const int expiryWarningDays = 30;

  // POS
  static const int maxCartItems = 500;
  static const double defaultDiscount = 0.0;

  // Pagination
  static const int pageSize = 50;
}
