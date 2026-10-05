// lib/features/returns/providers/customer_invoice_return_service_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/customer_invoice_return_service.dart';

final customerInvoiceReturnServiceProvider =
    Provider<CustomerInvoiceReturnService>((ref) {
  return CustomerInvoiceReturnService(AppDatabase.instance);
});