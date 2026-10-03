// test/support/supplier_payment_test_keys.dart

import 'package:uuid/uuid.dart';

const _b8TestUuid = Uuid();

String b8SupplierPaymentIdempotencyKey() => _b8TestUuid.v4();
