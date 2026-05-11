import '../database/app_database.dart';

class InvoiceNumberService {
  final AppDatabase db;

  InvoiceNumberService(this.db);

  Future<String> next() async {
    final now = DateTime.now();
    final prefix =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

    // جلب آخر فاتورة اليوم
    final result = await db.customSelect(
      '''
      SELECT invoice_number 
      FROM sales_invoices
      WHERE invoice_number LIKE '$prefix-%'
      ORDER BY invoice_number DESC
      LIMIT 1
      ''',
    ).getSingleOrNull();

    int nextNumber = 1;

    if (result != null) {
      final last = result.data['invoice_number'] as String;
      final parts = last.split('-');
      final lastNumber = int.tryParse(parts.last) ?? 0;
      nextNumber = lastNumber + 1;
    }

    final number = nextNumber.toString().padLeft(4, '0');

    return '$prefix-$number';
  }
}