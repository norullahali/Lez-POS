import 'package:lez_pos/core/services/customer_invoice_return_posting_result.dart';
import 'package:lez_pos/core/services/customer_invoice_return_service.dart';
import 'package:lez_pos/core/services/partial_return_service.dart';

import 'customer_invoice_return_test_keys.dart';

Future<CustomerInvoiceReturnPostingResult> postPartialCustomerInvoiceReturn(
  CustomerInvoiceReturnService service, {
  required int saleInvoiceId,
  required int returnedByUserId,
  required List<CustomerInvoicePartialReturnLine> lines,
  String? note,
  String? idempotencyKey,
}) {
  return service.processPartialReturn(
    idempotencyKey: idempotencyKey ?? b16CustomerInvoiceReturnIdempotencyKey(),
    saleInvoiceId: saleInvoiceId,
    lines: lines,
    returnedByUserId: returnedByUserId,
    note: note,
  );
}

Future<CustomerInvoiceReturnPostingResult> postFullCustomerInvoiceReturn(
  CustomerInvoiceReturnService service, {
  required int saleInvoiceId,
  required int returnedByUserId,
  required String note,
  String? idempotencyKey,
}) {
  return service.processFullReturn(
    idempotencyKey: idempotencyKey ?? b16CustomerInvoiceReturnIdempotencyKey(),
    saleInvoiceId: saleInvoiceId,
    returnedByUserId: returnedByUserId,
    note: note,
  );
}