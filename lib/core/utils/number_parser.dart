// lib/core/utils/number_parser.dart

extension ArabicNumbersParsing on String {
  /// Converts Eastern Arabic (and Persian) numerals to standard numerals and parses as double.
  double? tryParseArabicDouble() {
    if (trim().isEmpty) return null;
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    const persian = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
    
    String normalized = this;
    for (int i = 0; i < english.length; i++) {
      normalized = normalized.replaceAll(arabic[i], english[i]);
      normalized = normalized.replaceAll(persian[i], english[i]);
    }
    normalized = normalized.replaceAll('٫', '.'); // Eastern Arabic decimal separator
    normalized = normalized.replaceAll(',', '.'); // Normal comma to dot
    
    return double.tryParse(normalized);
  }

  /// Converts Eastern Arabic (and Persian) numerals to standard numerals and parses as int.
  int? tryParseArabicInt() {
    if (trim().isEmpty) return null;
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    const persian = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
    
    String normalized = this;
    for (int i = 0; i < english.length; i++) {
      normalized = normalized.replaceAll(arabic[i], english[i]);
      normalized = normalized.replaceAll(persian[i], english[i]);
    }
    
    return int.tryParse(normalized);
  }
}
