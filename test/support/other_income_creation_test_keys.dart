// test/support/other_income_creation_test_keys.dart

import 'package:uuid/uuid.dart';

const _b19TestUuid = Uuid();

String b19OtherIncomeCreationIdempotencyKey() => _b19TestUuid.v4();