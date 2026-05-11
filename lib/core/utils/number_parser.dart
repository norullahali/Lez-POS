// lib/core/utils/number_parser.dart

extension ArabicNumbersParsing on String {
  /// Normalises Eastern Arabic (٠-٩) and Persian (۰-۹) digits to ASCII (0-9).
  /// All non-digit characters pass through unchanged.
  ///
  /// Examples:
  ///   '٤٥٦٤٥٧'  → '456457'
  ///   '۱۲۳'     → '123'
  ///   'ABC-٧٨٩' → 'ABC-789'
  String normalizeBarcode() {
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    const persian = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

    String result = this;
    for (int i = 0; i < english.length; i++) {
      result = result.replaceAll(arabic[i], english[i]);
      result = result.replaceAll(persian[i], english[i]);
    }
    return result;
  }


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
