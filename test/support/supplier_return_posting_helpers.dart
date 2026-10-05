import 'package:lez_pos/core/services/supplier_return_posting_result.dart';
import 'package:lez_pos/core/services/supplier_return_service.dart';

import 'supplier_return_test_keys.dart';

Future<SupplierReturnPostingResult> postSupplierReturn(
  SupplierReturnService service,
  SupplierReturnPostingInput input, {
  String? idempotencyKey,
}) {
  return service.postPurchaseLinkedReturn(
    idempotencyKey: idempotencyKey ?? b15SupplierReturnIdempotencyKey(),
    input: input,
  );
}

Future<int> postSupplierReturnId(
  SupplierReturnService service,
  SupplierReturnPostingInput input, {
  String? idempotencyKey,
}) async {
  final result = await postSupplierReturn(
    service,
    input,
    idempotencyKey: idempotencyKey,
  );
  return result.supplierReturnId;
}
