// test/support/customer_payment_test_keys.dart

import 'package:uuid/uuid.dart';

const _b6TestUuid = Uuid();

String b6PaymentIdempotencyKey() => _b6TestUuid.v4();