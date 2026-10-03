// test/support/customer_quick_return_test_keys.dart

import 'package:uuid/uuid.dart';

const _b9TestUuid = Uuid();

String b9QuickReturnIdempotencyKey() => _b9TestUuid.v4();
