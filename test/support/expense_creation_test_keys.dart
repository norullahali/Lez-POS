// test/support/expense_creation_test_keys.dart

import 'package:uuid/uuid.dart';

const _b18TestUuid = Uuid();

String b18ExpenseCreationIdempotencyKey() => _b18TestUuid.v4();